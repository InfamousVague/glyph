import type { OAuthClientProvider } from '@modelcontextprotocol/sdk/client/auth.js';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import type { OAuthClientInformationFull, OAuthClientMetadata, OAuthTokens } from '@modelcontextprotocol/sdk/shared/auth.js';
import type { Details } from '../tauri/src/app/core/notifications/kinds.ts';
import type { Note } from '../tauri/src/app/core/store.ts';
import { exportPrivateKey, newEncryptionKey, publicKeyOf, wrapContext, wrapFor } from '../tauri/src/app/core/orgs/wrap.ts';
import { derive, open, passwordSalt, seal, toBase64Url, unwrap, type Bytes } from '../tauri/src/app/core/sync/crypto.ts';
import type { LocalFiles, LocalNotes } from '../tauri/src/app/core/sync/notes.ts';
import { memoryDocs } from '../tauri/src/app/core/team/docs.ts';
import { emptyTeamState, syncTeamNotes, type TeamSyncContext, type TeamSyncState } from '../tauri/src/app/core/team/sync.ts';
import { fakeService, FAST, type FakeService } from '../tauri/src/test/fakeService.ts';
import { makeNote } from '../tauri/src/test/notes.ts';
import { GlyphAccount, type Hooks } from './glyph.ts';
import { buildServer, type HostedHooks } from './server.ts';

/**
 * What the MCP server's tests share (glyph.test.ts, server.test.ts, hosted.test.ts, cli.test.ts and
 * mcp.e2e.test.ts): a note as another device wrote it, the words a tool answered with, and an account signed in to
 * the sync service in memory (src/test/fakeService.ts) with Claude connected to its tools over a pair of in-memory
 * transports. For the hosted server, Claude's side of the OAuth connection and the sign-in page's script, played with
 * the app's own crypto (loginPage.test.ts runs the page's own). For the tests only; nothing built imports it.
 */

/** The fixed moment a test's notes were written: long enough ago that anything the tools write is newer. */
export const WRITTEN = 1_700_000_000_000;

/** A note another device wrote at `WRITTEN`, as a phone would have made it by voice. */
export function aNote(id: string, body: string, over: Partial<Note> = {}): Note {
  return makeNote(id, body, { createdAt: WRITTEN, updatedAt: WRITTEN, source: 'capture', starred: false, archivedAt: null, ...over });
}

/** The words a tool answered with: its first piece of text. */
export function asText(result: Awaited<ReturnType<Client['callTool']>>): string {
  return (result.content as { text?: string }[])[0]?.text ?? '';
}

/** The service's address in these tests: never reached, since the fake answers every call. */
export const API = 'https://fake.test/glyph/api';

/**
 * What the account was told of Claude's writes (docs/TEAMS.md): every self notification in the service's feed, in the
 * order it was written, opened with the account key as a device of the account opens one. The id rides with it, so a
 * test can see its shape.
 */
export async function told(service: FakeService): Promise<{ id: string; kind: string; details: Details }[]> {
  const rows = [...service.feed.values()].filter((n) => n.blob).sort((a, b) => a.rev - b.rev);
  return Promise.all(rows.map(async (n) => ({ id: n.id, kind: n.kind, details: await open<Details>(service.accountKey, n.blob!, `notification:${n.id}`) })));
}

/**
 * Matt's account on a fresh service in memory, signed in as the MCP client signs in, and Claude connected to the
 * server's tools. `hooks` reach the account (a fetcher that steps in, say); `hosted` makes it the hosted server;
 * `clientName` is what Claude's app calls itself when it connects (an empty one connects with no name to go on).
 */
export async function connected({ hooks = {}, hosted, clientName = 'claude-ai' }: { hooks?: Omit<Hooks, 'fetcher'> & { fetcher?: (service: FakeService) => typeof fetch }; hosted?: HostedHooks; clientName?: string } = {}) {
  const service = await fakeService({ handle: 'matt', password: 'correct horse' });
  const session = await GlyphAccount.signIn(API, 'matt', 'correct horse', { rounds: FAST, fetcher: service.fetcher });
  const { fetcher, ...rest } = hooks;
  const account = new GlyphAccount(session, { ...rest, fetcher: fetcher ? fetcher(service) : service.fetcher });
  const client = new Client({ name: clientName, version: '0' });
  const [ours, theirs] = InMemoryTransport.createLinkedPair();
  await Promise.all([buildServer(account, hosted).connect(theirs), client.connect(ours)]);
  /** A tool called, and what it said: its words, and whether it said them as a refusal. */
  const call = async (name: string, args: Record<string, unknown> = {}) => {
    const result = await client.callTool({ name, arguments: args });
    return { text: asText(result), isError: Boolean(result.isError) };
  };
  return { service, session, account, client, call };
}

/** What Claude keeps for one server: the registration, the tokens, the PKCE verifier, and where it was sent to sign in. */
export class ClaudeMemory implements OAuthClientProvider {
  info: OAuthClientInformationFull | undefined;
  saved: OAuthTokens | undefined;
  verifier = '';
  sentTo: URL | null = null;
  constructor(readonly redirectUrl: string) {}
  get clientMetadata(): OAuthClientMetadata {
    return { client_name: 'Claude', redirect_uris: [this.redirectUrl], grant_types: ['authorization_code', 'refresh_token'], response_types: ['code'], token_endpoint_auth_method: 'none' };
  }
  clientInformation() {
    return this.info;
  }
  saveClientInformation(info: OAuthClientInformationFull) {
    this.info = info;
  }
  tokens() {
    return this.saved;
  }
  saveTokens(tokens: OAuthTokens) {
    this.saved = tokens;
  }
  redirectToAuthorization(url: URL) {
    this.sentTo = url;
  }
  saveCodeVerifier(verifier: string) {
    this.verifier = verifier;
  }
  codeVerifier() {
    return this.verifier;
  }
}

/** The hosted sign-in page (mcp/loginPage.ts) as a test reads it: its words, and the `data-` fields its script reads. */
export interface SignInPage {
  /** Where the page was fetched from, which a relative address on it is taken against. */
  url: URL;
  status: number;
  html: string;
  /** The sign-in request, the sync service the page signs in to, the server it hands the key to, and where Cancel goes. */
  request: string;
  api: string;
  base: string;
  deny: string;
}

/** The sign-in page Claude sent the person to, fetched and read. */
export async function readSignInPage(url: URL): Promise<SignInPage> {
  const page = await fetch(url);
  const html = await page.text();
  // Written into the page escaped, as HTML attributes are: an address's `&` is `&amp;` there.
  const field = (name: string) => new RegExp(`data-${name}="([^"]+)"`).exec(html)?.[1]?.replace(/&amp;/g, '&') ?? '';
  return { url, status: page.status, html, request: field('request'), api: field('api'), base: field('base'), deny: field('deny') };
}

/** What the page's script posts to the server once the person is signed in, and what `/authorize/complete` answers. */
export async function completeSignIn(page: SignInPage, fields: { handle: string; token: string; accountKey: string }) {
  const done = await fetch(new URL(`${page.base}/authorize/complete`, page.url), { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ request: page.request, ...fields }) });
  return { status: done.status, body: (await done.json()) as { redirect?: string; error?: string } };
}

/**
 * The sign-in page's script, played: the password's halves derived as the app derives them, the login half sent to
 * the page's sync service (through `fetcher`, a fake service's say), the account key unwrapped with the other half,
 * and handed to the server. The password goes nowhere but `derive`.
 */
export async function playSignInPage(page: SignInPage, { handle, password, rounds, fetcher = fetch }: { handle: string; password: string; rounds: number; fetcher?: typeof fetch }) {
  const { login, wrapKey } = await derive(password, passwordSalt(handle), rounds);
  const signedIn = await fetcher(`${page.api}/v1/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ handle, loginSecret: login }) });
  const answer = (await signedIn.json()) as { token: string; wrapped: string; account: { handle: string } };
  const key = await unwrap(answer.wrapped, wrapKey, true);
  const raw = toBase64Url(new Uint8Array(await crypto.subtle.exportKey('raw', key)));
  return completeSignIn(page, { handle: answer.account.handle, token: answer.token, accountKey: raw });
}

/** One JSON call to the fake service as a signed-in device of the account. */
async function asDevice<T>(service: FakeService, method: string, path: string, body?: unknown): Promise<T> {
  const response = await service.fetcher(`${API}/v1/${path}`, { method, headers: { Authorization: `Bearer ${service.signedIn()}`, 'Content-Type': 'application/json' }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
  if (!response.ok) throw new Error(`${method} ${path} answered ${response.status}: ${await response.text()}`);
  return (await response.json()) as T;
}

/**
 * The account's encryption key pair registered as its first device registers it (core/account/encKey.ts): the public
 * key, and the private half sealed under the account key. Once an account; answers the public key.
 */
export async function registerPair(service: FakeService): Promise<string> {
  if (service.encryption) return service.encryption.pub;
  const pair = await newEncryptionKey();
  const pub = await publicKeyOf(pair);
  await asDevice(service, 'PUT', 'account/key', { pub, sealed: await seal(service.accountKey, await exportPrivateKey(pair), 'encryption-key') });
  return pub;
}

/** An organization key as a member's device makes one: its bytes, and the key they are. */
async function anOrgKey(): Promise<{ raw: Bytes; key: CryptoKey }> {
  const raw = crypto.getRandomValues(new Uint8Array(32));
  return { raw, key: await crypto.subtle.importKey('raw', raw, { name: 'AES-GCM' }, true, ['encrypt', 'decrypt']) };
}

/**
 * An organization the account is in, with its key made as a member's device makes it (core/orgs/orgKeys.ts): the
 * first generation, wrapped for the account unless `wrap` is false - the member whose wrap no device has made yet.
 * `turn` makes the next generation, as the device of a member does after another has left; `wrapNow` makes the
 * account's wrap at the generation in force, as another member's device does on its next pass.
 */
export async function anOrganization(service: FakeService, name = 'Ghost', { wrap = true }: { wrap?: boolean } = {}) {
  const pub = await registerPair(service);
  // As the app's own call makes one (core/orgs/orgs.ts `createOrg`), without the app's settings it also writes.
  const { org } = await asDevice<{ org: { id: string } }>(service, 'POST', 'orgs', { name });
  const keys = [await anOrgKey()];
  const post = async (generation: number, make: boolean, wrapped: boolean) =>
    asDevice(service, 'POST', `orgs/${org.id}/keys`, { generation, ...(make ? { make: true } : {}), wraps: wrapped ? [{ handle: 'matt', wrapped: await wrapFor(pub, keys[generation - 1]!.raw, wrapContext(org.id, generation)) }] : [] });
  await post(1, true, wrap);
  return {
    id: org.id,
    name,
    /** The key in force, and its generation. */
    get key(): CryptoKey {
      return keys[keys.length - 1]!.key;
    },
    get generation(): number {
      return keys.length;
    },
    keyAt: (generation: number): CryptoKey => keys[generation - 1]!.key,
    async turn({ wrap: wrapped = true }: { wrap?: boolean } = {}): Promise<void> {
      keys.push(await anOrgKey());
      await post(keys.length, true, wrapped);
    },
    wrapNow: (): Promise<unknown> => post(keys.length, false, true),
  };
}

/**
 * A member's device in an organization, as the app is one (core/team/sync.ts `syncTeamNotes`, the app's own pass):
 * its notes in a map, each filed in the organization's workspace, its documents its own. The fake service's one
 * account stands for every member, as in the app's own tests of the channel.
 */
export function teamDevice(service: FakeService, org: { id: string; key: CryptoKey; generation: number }) {
  const notes = new Map<string, Note>();
  const filed = new Set<string>();
  const pictures = new Map<string, Bytes>();
  const docs = memoryDocs();
  let state: TeamSyncState = emptyTeamState();
  const clock = { at: WRITTEN };
  const local: LocalNotes = {
    list: async () => [...notes.values()],
    get: async (id) => notes.get(id) ?? null,
    apply: async (note) => {
      notes.set(note.id, note);
      return note;
    },
    remove: async (id) => {
      notes.delete(id);
    },
  };
  const files: LocalFiles = {
    read: async (kind, name) => (kind === 'image' ? (pictures.get(name) ?? null) : null),
    write: async (kind, name, bytes) => {
      if (kind === 'image') pictures.set(name, bytes);
    },
  };
  return {
    notes,
    filed,
    pictures,
    clock,
    /** A note written on this device in the organization's workspace, or one it holds written again. */
    put(id: string, body: string, over: Partial<Note> = {}): void {
      clock.at += 1;
      const was = notes.get(id);
      notes.set(id, { ...(was ?? { id, createdAt: clock.at, source: 'editor' as const }), body, updatedAt: clock.at, ...over });
      filed.add(id);
    },
    /** One pass of the organization channel, under the key in force unless told otherwise. */
    sync(over: Partial<TeamSyncContext> = {}) {
      clock.at += 1;
      return syncTeamNotes({ token: service.signedIn(), orgId: org.id, key: org.key, generation: org.generation, notes: local, files, docs, state, save: (s) => (state = s), fetcher: service.fetcher, now: () => clock.at, isTeamNote: (id) => filed.has(id), file: (id) => void filed.add(id), ...over });
    },
  };
}
