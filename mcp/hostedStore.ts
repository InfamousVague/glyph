import { randomBytes, randomUUID } from 'node:crypto';
import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import type { OAuthRegisteredClientsStore } from '@modelcontextprotocol/sdk/server/auth/clients.js';
import type { AuthorizationParams } from '@modelcontextprotocol/sdk/server/auth/provider.js';
import type { OAuthClientInformationFull, OAuthTokens } from '@modelcontextprotocol/sdk/shared/auth.js';
import { failureText } from '../src/app/core/failure.ts';
import type { GlyphAccount } from './glyph.ts';
import { newSealKey, open, seal, tokenId, unwrapWith, wrapFor } from './hostedSeal.ts';

/**
 * What the hosted server holds (mcp/hosted.ts), and when it lets go of it: the clients Claude registered, the sign-in
 * requests waiting on the page, the codes the page handed back, the sessions - each holding an account's key - and
 * the tokens that name them.
 *
 *   a sign-in request   10 minutes, for the person to finish the page
 *   a code              10 minutes, for Claude to trade it for tokens
 *   an access token     an hour
 *   a refresh token     thirty days
 *   a session           until its tokens are gone, or a week without a request, whichever comes first
 *   a client            while a session is its own, and thirty days after it was last heard from
 *
 * A session that ends takes its tokens with it, and the account and its key with those, since nothing else holds them.
 *
 * **Across a restart.** Given a file (`GLYPH_MCP_STATE` on the box), the clients, the sessions and their tokens are
 * written to it, so a restart of the service signs nobody out. Never in the clear (mcp/hostedSeal.ts): a session's
 * account key and sync token are sealed under a key of the session's own, that key is written only wrapped under each
 * token that names the session, and a token is written only as an id derived from it. So the file opens nothing by
 * itself; a session read back from it is *closed* - no account, no seal key - until Claude presents one of its tokens,
 * which opens it (`unseal`). Sign-in requests and codes are not written: a restart in the moment between the page
 * and Claude's exchange costs that one sign-in.
 *
 * It is written whole, to a file beside it and renamed over, at once when a token is issued or a session ends, and at
 * the next sweep for the rest (when a session was last used, when a client was last heard from). A write that fails
 * is a line on stderr: the sessions go on in memory.
 */

/** A sign-in the page has not finished: who asked, and where to send the person back. */
export interface AuthRequest {
  client: OAuthClientInformationFull;
  params: AuthorizationParams;
  expiresAt: number;
}

/** A code the page handed back, bound to the client, the PKCE challenge and the redirect it was made for. */
export interface IssuedCode {
  clientId: string;
  codeChallenge: string;
  redirectUri: string;
  sessionId: string;
  expiresAt: number;
}

/** A person signed in: their handle and, in `account`, the key their browser unwrapped. */
export interface Session {
  id: string;
  handle: string;
  clientId: string;
  /** The account, open. Absent on a session read back after a restart, until one of its tokens opens it. */
  account?: GlyphAccount;
  lastUsed: number;
  /** The sync service would not renew its token: the person has to sign in again. */
  lapsed: boolean;
  /**
   * What the AI's app calls itself: its registered name at sign-in, then its clientInfo from `initialize`. Kept here
   * because each request builds a fresh server that never saw the `initialize`, and a note's authors are named from it
   * (core/authors.ts).
   */
  client?: { name?: string; title?: string };
  /** The session's seal key, in memory while the session is open and never written (mcp/hostedSeal.ts). */
  sealKey?: Buffer;
  /** The account key, and the sync service's token, each sealed under the seal key: what the file holds of them. */
  sealedKey: string;
  sealedToken: string;
}

/** An access or refresh token: the session it names, the client it was issued to, when it runs out, and the session's seal key wrapped for it. */
export interface Issued {
  sessionId: string;
  clientId: string;
  expiresAt: number;
  wrap: string;
}

/** The file: everything that outlasts a restart, none of it a key or a token in the clear. */
interface Kept {
  v: 1;
  clients: { client: OAuthClientInformationFull; seen: number }[];
  sessions: Pick<Session, 'id' | 'handle' | 'clientId' | 'lastUsed' | 'client' | 'sealedKey' | 'sealedToken'>[];
  access: Record<string, Issued>;
  refresh: Record<string, Issued>;
}

export const REQUEST_MS = 10 * 60 * 1000;
export const CODE_MS = 10 * 60 * 1000;
const ACCESS_MS = 60 * 60 * 1000;
const REFRESH_MS = 30 * 24 * 60 * 60 * 1000;
/** A session nobody has used for this long is over, key and all. */
const IDLE_MS = 7 * 24 * 60 * 60 * 1000;
/** A client with no session, not heard from for this long, is forgotten; Claude registers again if it comes back. */
const CLIENT_MS = REFRESH_MS;
/** The one scope there is: the account's notes. */
export const SCOPE = 'notes';

/** A new secret: a request's id, a code, a token. */
export const newToken = () => randomBytes(32).toString('base64url');

/** A store on the clock `now` reads: empty, or as `file` left it, if there is one. */
export function hostedStore(now: () => number, file?: string) {
  const clients = new Map<string, { client: OAuthClientInformationFull; seen: number }>();
  const requests = new Map<string, AuthRequest>();
  const codes = new Map<string, IssuedCode>();
  const sessions = new Map<string, Session>();
  // Both by the token's id (hostedSeal.ts tokenId), never by the token.
  const accessTokens = new Map<string, Issued>();
  const refreshTokens = new Map<string, Issued>();
  /** Something the file holds has changed and is not written yet. */
  let dirty = false;

  /** The file, written whole. */
  function persist(): void {
    dirty = false;
    if (!file) return;
    const kept: Kept = {
      v: 1,
      clients: [...clients.values()],
      sessions: [...sessions.values()].map(({ id, handle, clientId, lastUsed, client, sealedKey, sealedToken }) => ({ id, handle, clientId, lastUsed, ...(client ? { client } : {}), sealedKey, sealedToken })),
      access: Object.fromEntries(accessTokens),
      refresh: Object.fromEntries(refreshTokens),
    };
    try {
      writeFileSync(`${file}.new`, JSON.stringify(kept), { mode: 0o600 });
      renameSync(`${file}.new`, file);
    } catch (failure) {
      process.stderr.write(`glyph-mcp: the sessions could not be written to ${file}: ${failureText(failure)}\n`);
    }
  }

  /** What the file left, every session closed. A file that cannot be read is nobody signed in, and a line saying so. */
  function load(): void {
    if (!file || !existsSync(file)) return;
    try {
      const kept = JSON.parse(readFileSync(file, 'utf8')) as Kept;
      if (kept.v !== 1) throw new Error(`version ${String(kept.v)} is not one this server reads`);
      for (const entry of kept.clients) clients.set(entry.client.client_id, entry);
      for (const session of kept.sessions) sessions.set(session.id, { ...session, lapsed: false });
      for (const [id, issued] of Object.entries(kept.access)) accessTokens.set(id, issued);
      for (const [id, issued] of Object.entries(kept.refresh)) refreshTokens.set(id, issued);
    } catch (failure) {
      clients.clear();
      sessions.clear();
      accessTokens.clear();
      refreshTokens.clear();
      process.stderr.write(`glyph-mcp: the sessions in ${file} could not be read, so everyone signs in again: ${failureText(failure)}\n`);
    }
  }

  /** Where the SDK's handlers keep the clients Claude registers; asking after one is hearing from it. */
  const clientsStore: OAuthRegisteredClientsStore = {
    getClient: (clientId) => {
      const entry = clients.get(clientId);
      if (!entry) return undefined;
      entry.seen = now();
      dirty = true;
      return entry.client;
    },
    registerClient: (client) => {
      const full = { ...(client as OAuthClientInformationFull), client_id: (client as OAuthClientInformationFull).client_id ?? randomUUID(), client_id_issued_at: Math.floor(now() / 1000) };
      clients.set(full.client_id, { client: full, seen: now() });
      persist();
      return full;
    },
  };

  /** A person signed in on the page: a session, open, its secrets sealed under a seal key made for it. */
  function signIn(made: Pick<Session, 'id' | 'handle' | 'clientId' | 'client'> & { account: GlyphAccount; accountKey: string; token: string }): Session {
    const { accountKey, token, ...rest } = made;
    const sealKey = newSealKey();
    const session: Session = { ...rest, lastUsed: now(), lapsed: false, sealKey, sealedKey: seal(sealKey, accountKey, `${made.id}:key`), sealedToken: seal(sealKey, token, `${made.id}:token`) };
    sessions.set(session.id, session);
    return session;
  }

  /**
   * A closed session's secrets, opened with one of its own tokens, and the session's seal key kept from here on.
   * Throws for a token that is not this session's, or a file that was changed.
   */
  function unseal(session: Session, token: string, issued: Issued): { accountKey: string; token: string } {
    const sealKey = unwrapWith(token, issued.wrap, `${session.id}:wrap`);
    const secrets = { accountKey: open(sealKey, session.sealedKey, `${session.id}:key`).toString(), token: open(sealKey, session.sealedToken, `${session.id}:token`).toString() };
    session.sealKey = sealKey;
    return secrets;
  }

  /** The sync service renewed an open session's token: the new one is sealed in the old one's place. */
  function keepToken(session: Session, token: string): void {
    if (!session.sealKey) return;
    session.sealedToken = seal(session.sealKey, token, `${session.id}:token`);
    persist();
  }

  /** A request came for the session. */
  function touch(session: Session): void {
    session.lastUsed = now();
    dirty = true;
  }

  function drop(id: string): void {
    sessions.delete(id);
    for (const [c, issued] of codes) if (issued.sessionId === id) codes.delete(c);
    for (const [t, issued] of accessTokens) if (issued.sessionId === id) accessTokens.delete(t);
    for (const [t, issued] of refreshTokens) if (issued.sessionId === id) refreshTokens.delete(t);
  }

  /** A session is over: its tokens go, and with them the key, here and in the file. */
  function endSession(id: string): void {
    drop(id);
    persist();
  }

  /** A fresh access token and refresh token for an open session, as the token endpoint answers them. */
  function issue(session: Session, clientId: string): OAuthTokens {
    if (!session.sealKey) throw new Error('A closed session cannot be issued tokens.');
    const access = newToken();
    const refresh = newToken();
    const aad = `${session.id}:wrap`;
    accessTokens.set(tokenId(access), { sessionId: session.id, clientId, expiresAt: now() + ACCESS_MS, wrap: wrapFor(access, session.sealKey, aad) });
    refreshTokens.set(tokenId(refresh), { sessionId: session.id, clientId, expiresAt: now() + REFRESH_MS, wrap: wrapFor(refresh, session.sealKey, aad) });
    persist();
    return { access_token: access, token_type: 'bearer', expires_in: ACCESS_MS / 1000, refresh_token: refresh, scope: SCOPE };
  }

  /** What is known of a token Claude presented, as an access token or as a refresh token. */
  const access = (token: string) => accessTokens.get(tokenId(token));
  const refresh = (token: string) => refreshTokens.get(tokenId(token));

  /** A token is spent, or taken back: forgotten, and what it named answered. */
  function forget(token: string): Issued | undefined {
    const id = tokenId(token);
    const issued = accessTokens.get(id) ?? refreshTokens.get(id);
    if (accessTokens.delete(id) || refreshTokens.delete(id)) dirty = true;
    return issued;
  }

  /** What has run out: requests, codes, tokens, sessions nobody has used for a week, and clients nobody is behind. */
  function sweep(): void {
    const at = now();
    const before = sessions.size + accessTokens.size + refreshTokens.size + clients.size;
    for (const [id, r] of requests) if (r.expiresAt < at) requests.delete(id);
    for (const [c, issued] of codes) if (issued.expiresAt < at) codes.delete(c);
    for (const [t, issued] of accessTokens) if (issued.expiresAt < at) accessTokens.delete(t);
    for (const [t, issued] of refreshTokens) if (issued.expiresAt < at) refreshTokens.delete(t);
    // A code counts: the session it names has no tokens yet, in the moment between the page and Claude's exchange.
    const named = new Set([...codes.values(), ...accessTokens.values(), ...refreshTokens.values()].map((i) => i.sessionId));
    for (const session of [...sessions.values()]) if (!named.has(session.id) || session.lastUsed + IDLE_MS < at) drop(session.id);
    const behind = new Set([...[...sessions.values()].map((s) => s.clientId), ...[...requests.values()].map((r) => r.client.client_id)]);
    for (const [id, entry] of clients) if (!behind.has(id) && entry.seen + CLIENT_MS < at) clients.delete(id);
    if (dirty || before !== sessions.size + accessTokens.size + refreshTokens.size + clients.size) persist();
  }

  load();
  sweep();

  return { clientsStore, requests, codes, sessions, signIn, unseal, keepToken, touch, endSession, issue, access, refresh, forget, sweep, flush: persist };
}
