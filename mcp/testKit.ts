import type { OAuthClientProvider } from '@modelcontextprotocol/sdk/client/auth.js';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import type { OAuthClientInformationFull, OAuthClientMetadata, OAuthTokens } from '@modelcontextprotocol/sdk/shared/auth.js';
import type { Note } from '../src/app/core/store.ts';
import { derive, passwordSalt, toBase64Url, unwrap } from '../src/app/core/sync/crypto.ts';
import { fakeService, FAST, type FakeService } from '../src/test/fakeService.ts';
import { makeNote } from '../src/test/notes.ts';
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
 * Matt's account on a fresh service in memory, signed in as the MCP client signs in, and Claude connected to the
 * server's tools. `hooks` reach the account (a fetcher that steps in, say); `hosted` makes it the hosted server.
 */
export async function connected({ hooks = {}, hosted }: { hooks?: Omit<Hooks, 'fetcher'> & { fetcher?: (service: FakeService) => typeof fetch }; hosted?: HostedHooks } = {}) {
  const service = await fakeService({ handle: 'matt', password: 'correct horse' });
  const session = await GlyphAccount.signIn(API, 'matt', 'correct horse', { rounds: FAST, fetcher: service.fetcher });
  const { fetcher, ...rest } = hooks;
  const account = new GlyphAccount(session, { ...rest, fetcher: fetcher ? fetcher(service) : service.fetcher });
  const client = new Client({ name: 'claude-ai', version: '0' });
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
