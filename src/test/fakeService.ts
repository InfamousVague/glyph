import type { Note } from '../app/core/store.ts';
import { derive, fromBase64Url, newAccountKey, open, passwordSalt, seal, wrap, type Bytes } from '../app/core/sync/crypto.ts';
import type { NotePayload } from '../app/core/sync/notes.ts';

/**
 * Glyph's account and sync service in memory, for tests: the routes, revisions and refusals of
 * server/src/accounts.rs and server/src/sync.rs, so every rule a client lives by is tried without a server. Served to
 * the code under test as a `fetch` (`fetcher`), which is how the app's calls (core/account/api.ts), the MCP server's
 * (mcp/glyph.ts) and the hosted page's all take it.
 *
 * One account at most, as a device only ever knows one: already there (`fakeService({ handle, password })`, the
 * account a test signs in to), or made by a signup through the fetcher (`fakeService()`, for the account flows
 * themselves). Its feed of notes, its settings and its recordings share one revision counter, as the server's do.
 *
 * What it does NOT do: rate limits, and the shape checks on ids and blobs - those are the server's own, tested in
 * server/src. And it never holds the account key the way the server never does, with one exception it says out loud:
 * for an account it was given a password for, it made the key itself, so it can play "another device" - sealing a
 * note as the app seals one (`deviceWrites`) and opening what a client wrote (`stored`).
 *
 * The MCP's tests (mcp/glyph.test.ts, mcp/hosted.test.ts) and the app's (core/sync/pictures.test.ts,
 * core/account/account.test.ts, core/sync/prefs.test.ts) all use this one; there were two copies, and they had
 * started to answer differently.
 */

/** PBKDF2 rounds for a test: the real 600 000 are for a person's password, not for a test that makes ten accounts. */
export const FAST = 1_000;

/** The id the one account is given, whoever makes it. */
const ACCOUNT_ID = 7;

interface Stored {
  rev: number;
  deleted: boolean;
  blob: string | null;
}

interface Account {
  handle: string;
  /** The login half of the password, as sign-in sends it (the server keeps a hash of it; a test needs no hash). */
  loginSecret: string;
  /** The account key wrapped under the password's other half. */
  wrapped: string;
  /** Each device's public signing key, as base64url. */
  devices: string[];
  /** The recovery sheet: each code's login half, and the account key wrapped under that code. */
  recovery: Map<string, string>;
  /** The account key itself, only for an account this service was given a password for (see the header). */
  key: CryptoKey | null;
}

export interface FakeServiceOptions {
  /** False: a HEAD never reaches the service, and the fetch throws as a browser's does when something drops it. */
  head?: boolean;
}

const encoder = new TextEncoder();

/** The service in memory. `seed`: an account it already holds, signed up with that password. */
export async function fakeService(seed?: { handle: string; password: string }, { head = true }: FakeServiceOptions = {}) {
  let account: Account | null = null;
  if (seed) {
    const key = await newAccountKey();
    const { login, wrapKey } = await derive(seed.password, passwordSalt(seed.handle), FAST);
    account = { handle: seed.handle, loginSecret: login, wrapped: await wrap(key, wrapKey), devices: [], recovery: new Map(), key };
  }
  const notes = new Map<string, Stored>();
  const files = new Map<string, { rev: number; bytes: Bytes }>();
  let prefs: { rev: number; blob: string } | null = null;
  let counter = 0;
  const tokens = new Set<string>();
  const nonces = new Set<string>();
  let issued = 0;
  /** Every request, as `METHOD path`: what a test asserts the client asked, and in what order. */
  const calls: string[] = [];

  const token = () => {
    const t = `tok-${++issued}`;
    tokens.add(t);
    return t;
  };
  const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
  const refuse = (status: number, error: string) => json(status, { error });
  const who = (a: Account) => ({ id: ACCOUNT_ID, handle: a.handle });
  const signedIn = (a: Account, wrapped?: string) => json(200, { token: token(), account: who(a), ...(wrapped ? { wrapped } : {}) });
  const sameHandle = (a: Account | null, handle: unknown): a is Account => !!a && a.handle.toLowerCase() === String(handle ?? '').trim().toLowerCase();
  const nextRev = () => ++counter;
  const forget = () => {
    account = null;
    notes.clear();
    files.clear();
    prefs = null;
    counter = 0;
    tokens.clear();
  };

  const fetcher: typeof fetch = async (input, init) => {
    const url = new URL(String(input));
    const method = init?.method ?? 'GET';
    const path = url.pathname.replace(/^.*\/v1\//, '');
    calls.push(`${method} ${path}`);
    // JSON for every route but a recording's PUT, whose body is the bytes themselves.
    const body = typeof init?.body === 'string' && init.body ? (JSON.parse(init.body) as Record<string, unknown>) : {};
    const bearer = new Headers(init?.headers).get('Authorization')?.replace(/^Bearer /, '') ?? null;

    // --- the ways in, which need no session ---
    if (method === 'POST' && path === 'signup') {
      if (account && !sameHandle(account, body.handle)) throw new Error('The fake service holds one account, and this test signed up a second.');
      if (account) return refuse(409, 'That handle is taken.');
      const sheet = (body.recovery ?? []) as { login: string; wrapped: string }[];
      if (sheet.length !== 8) return refuse(400, 'A recovery sheet is eight codes.');
      const made: Account = {
        handle: String(body.handle).trim(),
        loginSecret: String(body.loginSecret ?? '').toLowerCase(),
        wrapped: String(body.wrapped ?? ''),
        devices: body.devicePublicKey ? [String(body.devicePublicKey)] : [],
        recovery: new Map(sheet.map((code) => [code.login.toLowerCase(), code.wrapped])),
        key: null,
      };
      account = made;
      return signedIn(made);
    }
    if (method === 'POST' && path === 'login') {
      // The same answer for a wrong handle and a wrong password, as the server gives.
      if (!sameHandle(account, body.handle) || account.loginSecret !== String(body.loginSecret).toLowerCase()) return refuse(401, 'Wrong handle or password.');
      return signedIn(account, account.wrapped);
    }
    if (method === 'POST' && path === 'login/challenge') {
      // A nonce whether or not the handle exists, so this says nothing about which do.
      const nonce = `nonce-${++issued}`;
      nonces.add(nonce);
      return json(200, { nonce });
    }
    if (method === 'POST' && path === 'login/device') {
      // The nonce is spent by the attempt, whether or not the signature holds.
      if (!nonces.delete(String(body.nonce))) return refuse(401, 'That sign-in took too long. Try again.');
      if (!sameHandle(account, body.handle)) return refuse(401, 'This device could not be verified.');
      const signature = fromBase64Url(String(body.signature));
      for (const device of account.devices) {
        const key = await crypto.subtle.importKey('raw', fromBase64Url(device), { name: 'Ed25519' }, false, ['verify']);
        if (await crypto.subtle.verify({ name: 'Ed25519' }, key, signature, encoder.encode(String(body.nonce)))) return signedIn(account);
      }
      return refuse(401, 'This device could not be verified.');
    }
    if (method === 'POST' && path === 'login/recovery') {
      // The code is spent, and what comes back is the key wrapped under that code alone.
      const login = String(body.login).toLowerCase();
      const wrapped = sameHandle(account, body.handle) ? account.recovery.get(login) : undefined;
      if (!account || wrapped === undefined) return refuse(401, 'Wrong handle or code, or a code already used.');
      account.recovery.delete(login);
      return signedIn(account, wrapped);
    }

    // --- everything else is for a signed-in device ---
    if (!bearer) return refuse(401, 'Sign in first.');
    if (!tokens.has(bearer) || !account) return refuse(401, 'Your session has ended. Sign in again.');
    const mine: Account = account;

    if (method === 'POST' && path === 'refresh') return signedIn(mine);
    if (method === 'POST' && path === 'device') {
      mine.devices.push(String(body.devicePublicKey));
      return json(200, { ok: true });
    }
    if (method === 'GET' && path === 'keys') return json(200, { wrapped: mine.wrapped });
    if (method === 'PUT' && path === 'password') {
      mine.loginSecret = String(body.loginSecret).toLowerCase();
      mine.wrapped = String(body.wrapped);
      return json(200, { ok: true });
    }
    if (method === 'GET' && path === 'recovery') return json(200, { left: mine.recovery.size });
    if (method === 'POST' && path === 'recovery') {
      const sheet = (body.codes ?? []) as { login: string; wrapped: string }[];
      if (sheet.length !== 8) return refuse(400, 'A recovery sheet is eight codes.');
      mine.recovery = new Map(sheet.map((code) => [code.login.toLowerCase(), code.wrapped]));
      return json(200, { left: 8 });
    }
    if (method === 'DELETE' && path === 'account') {
      // 403 rather than 401: the session is fine, only the password is wrong, and a 401 reads as signed out.
      if (mine.loginSecret !== String(body.loginSecret ?? '').toLowerCase()) return refuse(403, 'That is not the password.');
      forget();
      return json(200, { deleted: true });
    }

    if (method === 'GET' && path === 'notes') {
      const since = Number(url.searchParams.get('since') ?? 0);
      const items = [...notes.entries()]
        .filter(([, n]) => n.rev > since)
        .sort(([, a], [, b]) => a.rev - b.rev)
        .map(([id, n]) => ({ id, ...n }));
      return json(200, { rev: counter, items, more: false });
    }
    const note = /^notes\/([^/]+)$/.exec(path);
    if (note && (method === 'PUT' || method === 'DELETE')) {
      const id = decodeURIComponent(note[1]!);
      const current = notes.get(id);
      // A note never seen is taken whatever its base: there is nothing it could overwrite.
      if (current && current.rev !== Number(body.base ?? 0)) return json(409, { id, ...current });
      const rev = nextRev();
      notes.set(id, method === 'PUT' ? { rev, deleted: false, blob: String(body.blob) } : { rev, deleted: true, blob: null });
      return json(200, { rev });
    }

    if (path === 'prefs' && method === 'GET') return json(200, { rev: prefs?.rev ?? 0, blob: prefs?.blob ?? null });
    if (path === 'prefs' && method === 'PUT') {
      if ((prefs?.rev ?? 0) !== Number(body.base ?? 0)) return prefs ? json(409, prefs) : refuse(500, 'Those settings could not be stored.');
      prefs = { rev: nextRev(), blob: String(body.blob) };
      return json(200, { rev: prefs.rev });
    }

    const file = /^recordings\/([^/]+)$/.exec(path);
    if (file) {
      const id = file[1]!;
      const had = files.get(id);
      if (method === 'HEAD') {
        if (!head) throw new TypeError('Failed to fetch');
        return had ? new Response(null, { status: 200, headers: { 'x-glyph-rev': String(had.rev) } }) : new Response(null, { status: 404 });
      }
      if (method === 'GET') return had ? new Response(had.bytes, { status: 200, headers: { 'x-glyph-rev': String(had.rev) } }) : refuse(404, 'No recording by that id.');
      if (method === 'PUT') {
        const base = Number(url.searchParams.get('base') ?? 0);
        if (had && had.rev !== base) return json(409, { rev: had.rev });
        const rev = nextRev();
        files.set(id, { rev, bytes: new Uint8Array(init?.body as Bytes) });
        return json(200, { rev });
      }
    }
    return refuse(404, `No route ${method} ${path}`);
  };

  /** The account key the service made for a seeded account; a test asking for any other has made a mistake. */
  const keyOf = (): CryptoKey => {
    if (!account?.key) throw new Error('The fake service holds no account key: only an account it was seeded with has one.');
    return account.key;
  };

  return {
    fetcher,
    calls,
    /** The feed as stored: each note's revision and sealed blob, or its deletion marker. */
    notes,
    /** The recordings and pictures as stored, sealed, by their file id. */
    files,
    /** The seeded account's key, for a test that seals or opens as a device of that account would. */
    get accountKey(): CryptoKey {
      return keyOf();
    },
    /** A live token for the account, as a device that signed in earlier holds one. */
    signedIn(): string {
      if (!account) throw new Error('The fake service holds no account to sign in to.');
      return token();
    },
    /** Another device writing a note, sealed as the app seals it. Answers the note's new revision. */
    async deviceWrites(written: Note, extra: Partial<NotePayload> = {}): Promise<number> {
      const rev = nextRev();
      notes.set(written.id, { rev, deleted: false, blob: await seal(keyOf(), { v: 1, note: written, ...extra }, `note:${written.id}`) });
      return rev;
    },
    /** What the account holds for a note, opened: the payload a client wrote, or null for none or a deletion. */
    async stored(id: string): Promise<NotePayload | null> {
      const item = notes.get(id);
      if (!item?.blob) return null;
      return open<NotePayload>(keyOf(), item.blob, `note:${id}`);
    },
    /** Every token the service has handed out stops working at once, as a week passing would do. */
    expireAllTokens(): void {
      tokens.clear();
    },
    /** Whether the account is still there: false after a signup that never came, or after it was deleted. */
    hasAccount(): boolean {
      return account !== null;
    },
    /** How many recovery codes the account has left unspent. */
    codesLeft(): number {
      return account?.recovery.size ?? 0;
    },
  };
}

/** The service's own type, for a test that keeps one across its cases. */
export type FakeService = Awaited<ReturnType<typeof fakeService>>;
