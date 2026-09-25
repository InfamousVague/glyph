import { randomBytes, randomUUID } from 'node:crypto';
import type { OAuthRegisteredClientsStore } from '@modelcontextprotocol/sdk/server/auth/clients.js';
import type { AuthorizationParams } from '@modelcontextprotocol/sdk/server/auth/provider.js';
import type { OAuthClientInformationFull, OAuthTokens } from '@modelcontextprotocol/sdk/shared/auth.js';
import type { GlyphAccount } from './glyph.ts';

/**
 * What the hosted server holds (mcp/hosted.ts), in memory only, and when it lets go of it: the clients Claude
 * registered, the sign-in requests waiting on the page, the codes the page handed back, the sessions - each holding an
 * account's key - and the tokens that name them. Nothing here is written anywhere, so a restart signs everyone out.
 *
 *   a sign-in request   10 minutes, for the person to finish the page
 *   a code              10 minutes, for Claude to trade it for tokens
 *   an access token     an hour
 *   a refresh token     thirty days
 *   a session           until its tokens are gone, or a week without a request, whichever comes first
 *
 * A session that ends takes its tokens with it, and the account and its key with those, since nothing else holds them.
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
  account: GlyphAccount;
  lastUsed: number;
  /** The sync service would not renew its token: the person has to sign in again. */
  lapsed: boolean;
  /**
   * What the AI's app calls itself: its registered name at sign-in, then its clientInfo from `initialize`. Kept here
   * because each request builds a fresh server that never saw the `initialize`, and a note's authors are named from it
   * (core/authors.ts).
   */
  client?: { name?: string; title?: string };
}

/** An access or refresh token: the session it names, the client it was issued to, and when it runs out. */
interface Issued {
  sessionId: string;
  clientId: string;
  expiresAt: number;
}

export const REQUEST_MS = 10 * 60 * 1000;
export const CODE_MS = 10 * 60 * 1000;
const ACCESS_MS = 60 * 60 * 1000;
const REFRESH_MS = 30 * 24 * 60 * 60 * 1000;
/** A session nobody has used for this long is over, key and all. */
const IDLE_MS = 7 * 24 * 60 * 60 * 1000;
/** The one scope there is: the account's notes. */
export const SCOPE = 'notes';

/** A new secret: a request's id, a code, a token. */
export const newToken = () => randomBytes(32).toString('base64url');

/** An empty store, on the clock `now` reads. */
export function hostedStore(now: () => number) {
  const clients = new Map<string, OAuthClientInformationFull>();
  const requests = new Map<string, AuthRequest>();
  const codes = new Map<string, IssuedCode>();
  const sessions = new Map<string, Session>();
  const accessTokens = new Map<string, Issued>();
  const refreshTokens = new Map<string, Issued>();

  /** Where the SDK's registration handler keeps the clients Claude registers. */
  const clientsStore: OAuthRegisteredClientsStore = {
    getClient: (clientId) => clients.get(clientId),
    registerClient: (client) => {
      const full = { ...(client as OAuthClientInformationFull), client_id: (client as OAuthClientInformationFull).client_id ?? randomUUID(), client_id_issued_at: Math.floor(now() / 1000) };
      clients.set(full.client_id, full);
      return full;
    },
  };

  /** A session is over: its tokens go, and with them the key. */
  function endSession(id: string): void {
    sessions.delete(id);
    for (const [t, issued] of accessTokens) if (issued.sessionId === id) accessTokens.delete(t);
    for (const [t, issued] of refreshTokens) if (issued.sessionId === id) refreshTokens.delete(t);
  }

  /** A fresh access token and refresh token for the session, as the token endpoint answers them. */
  function issue(session: Session, clientId: string): OAuthTokens {
    const access = newToken();
    const refresh = newToken();
    accessTokens.set(access, { sessionId: session.id, clientId, expiresAt: now() + ACCESS_MS });
    refreshTokens.set(refresh, { sessionId: session.id, clientId, expiresAt: now() + REFRESH_MS });
    return { access_token: access, token_type: 'bearer', expires_in: ACCESS_MS / 1000, refresh_token: refresh, scope: SCOPE };
  }

  /** What has run out: requests, codes, tokens, and sessions nobody has used for a week. */
  function sweep(): void {
    const at = now();
    for (const [id, r] of requests) if (r.expiresAt < at) requests.delete(id);
    for (const [c, issued] of codes) if (issued.expiresAt < at) codes.delete(c);
    for (const [t, issued] of accessTokens) if (issued.expiresAt < at) accessTokens.delete(t);
    for (const [t, issued] of refreshTokens) if (issued.expiresAt < at) refreshTokens.delete(t);
    for (const session of [...sessions.values()]) {
      const alive = [...refreshTokens.values()].some((i) => i.sessionId === session.id) || [...accessTokens.values()].some((i) => i.sessionId === session.id);
      if (!alive || session.lastUsed + IDLE_MS < at) endSession(session.id);
    }
  }

  return { clientsStore, requests, codes, sessions, accessTokens, refreshTokens, endSession, issue, sweep };
}
