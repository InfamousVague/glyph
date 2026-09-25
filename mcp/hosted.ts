import { randomUUID } from 'node:crypto';
import express, { type Request, type Response } from 'express';
import { authorizationHandler } from '@modelcontextprotocol/sdk/server/auth/handlers/authorize.js';
import { clientRegistrationHandler } from '@modelcontextprotocol/sdk/server/auth/handlers/register.js';
import { revocationHandler } from '@modelcontextprotocol/sdk/server/auth/handlers/revoke.js';
import { tokenHandler } from '@modelcontextprotocol/sdk/server/auth/handlers/token.js';
import { requireBearerAuth } from '@modelcontextprotocol/sdk/server/auth/middleware/bearerAuth.js';
import { InvalidGrantError, InvalidTokenError } from '@modelcontextprotocol/sdk/server/auth/errors.js';
import type { OAuthServerProvider } from '@modelcontextprotocol/sdk/server/auth/provider.js';
import type { AuthInfo } from '@modelcontextprotocol/sdk/server/auth/types.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import type { OAuthTokenRevocationRequest } from '@modelcontextprotocol/sdk/shared/auth.js';
import { failureText } from '../src/app/core/failure.ts';
import { GlyphAccount, GlyphApiError, importAccountKey } from './glyph.ts';
import { CODE_MS, hostedStore, newToken, REQUEST_MS, SCOPE, type Session } from './hostedStore.ts';
import { loginPage } from './loginPage.ts';
import { buildServer, VERSION } from './server.ts';

/**
 * The MCP server hosted on the box, for everyone (docs/MCP.md, "Hosted"): Claude connects to
 * https://attack.fm/glyph/api/mcp, the person signs in on a page here once, and the same tools as the local server
 * answer over HTTP. Matt: "run the server on our node so that the user doesn't need to".
 *
 * Notes are end-to-end encrypted, so the server has to hold the account key to serve them, and it does the one way
 * Matt chose: **in memory only**. The sign-in page unwraps the key in the person's browser - the password never
 * reaches this server, only the login half the sync service already sees - and hands the key to this process for the
 * session; it is kept as a key object the process cannot export, never written anywhere, and gone when the session
 * ends, when Claude disconnects, or when the process restarts. While a session lasts, this process can read that
 * account's notes; the page (mcp/loginPage.ts) says so in plain words before asking for the password.
 *
 * The rest is OAuth 2.1 as the MCP spec asks of a remote server, with the SDK's own handlers: dynamic client
 * registration, an authorization code with PKCE, refresh tokens, revocation. Every store is a map in memory
 * (mcp/hostedStore.ts, which says how long each thing lasts), so a restart signs everyone out and Claude simply asks
 * them to sign in again. The service is reached through
 * glyph-api, which proxies /glyph/api/mcp to it (server/src/mcp_proxy.rs), so nothing in the shared Caddy
 * configuration changes; the discovery documents live under that path, where the client library looks for them.
 */

export interface HostedOptions {
  /** The server's own URL, as Claude sees it: `https://attack.fm/glyph/api/mcp`. */
  issuer: string;
  /** The sync service this process talks to: the loopback one on the box. */
  api: string;
  /** The sync service as the person's browser reaches it, for the sign-in page. */
  apiPublic: string;
  fetcher?: typeof fetch;
  /** Rate limits on the sign-in endpoints: on by default; off in tests. */
  rateLimit?: boolean;
  now?: () => number;
}

/**
 * The hosted server as an express app, for the entry point (mcp/hosted-main.ts), with its `sweep` for the entry
 * point's timer; and its sessions, which only the tests read, to count them.
 */
export function hostedApp(options: HostedOptions) {
  const issuer = options.issuer.replace(/\/+$/, '');
  const base = new URL(issuer).pathname;
  const api = options.api.replace(/\/+$/, '');
  const apiPublic = options.apiPublic.replace(/\/+$/, '');
  const now = options.now ?? (() => Date.now());
  const rateLimit = options.rateLimit === false ? false : undefined;

  // Everything it holds, in memory only, and when each lets go (mcp/hostedStore.ts).
  const { clientsStore, requests, codes, sessions, accessTokens, refreshTokens, endSession, issue, sweep } = hostedStore(now);

  const provider: OAuthServerProvider = {
    get clientsStore() {
      return clientsStore;
    },
    async authorize(client, params, res) {
      sweep();
      const id = newToken();
      requests.set(id, { client, params, expiresAt: now() + REQUEST_MS });
      const deny = new URL(params.redirectUri);
      deny.searchParams.set('error', 'access_denied');
      deny.searchParams.set('error_description', 'The person did not sign in.');
      if (params.state) deny.searchParams.set('state', params.state);
      res
        .status(200)
        .set('Content-Security-Policy', `default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; font-src data:; connect-src 'self' ${new URL(apiPublic).origin}; form-action 'none'; base-uri 'none'`)
        .set('Cache-Control', 'no-store')
        .set('Referrer-Policy', 'no-referrer')
        .type('html')
        .send(loginPage({ request: id, who: client.client_name?.trim() || 'Claude', apiPublic, base: issuer, deny: deny.href }));
    },
    async challengeForAuthorizationCode(client, code) {
      const issued = codes.get(code);
      if (!issued || issued.clientId !== client.client_id || issued.expiresAt < now()) throw new InvalidGrantError('That code is not one of ours, or has run out.');
      return issued.codeChallenge;
    },
    async exchangeAuthorizationCode(client, code, _verifier, redirectUri) {
      const issued = codes.get(code);
      codes.delete(code);
      if (!issued || issued.clientId !== client.client_id || issued.expiresAt < now()) throw new InvalidGrantError('That code is not one of ours, or has run out.');
      if (redirectUri && redirectUri !== issued.redirectUri) throw new InvalidGrantError('The redirect does not match the one the code was made for.');
      const session = sessions.get(issued.sessionId);
      if (!session) throw new InvalidGrantError('That sign-in is over; sign in again.');
      return issue(session, client.client_id);
    },
    async exchangeRefreshToken(client, refreshToken) {
      const issued = refreshTokens.get(refreshToken);
      if (!issued || issued.clientId !== client.client_id || issued.expiresAt < now()) throw new InvalidGrantError('That refresh token is not one of ours, or has run out.');
      refreshTokens.delete(refreshToken);
      const session = sessions.get(issued.sessionId);
      if (!session || session.lapsed) {
        if (session) endSession(session.id);
        throw new InvalidGrantError('That sign-in is over; sign in again.');
      }
      return issue(session, client.client_id);
    },
    async verifyAccessToken(access): Promise<AuthInfo> {
      const issued = accessTokens.get(access);
      if (!issued || issued.expiresAt < now()) throw new InvalidTokenError('That token is not one of ours, or has run out.');
      const session = sessions.get(issued.sessionId);
      if (!session || session.lapsed) {
        if (session) endSession(session.id);
        throw new InvalidTokenError('That sign-in is over; sign in again.');
      }
      return { token: access, clientId: issued.clientId, scopes: [SCOPE], expiresAt: Math.floor(issued.expiresAt / 1000), extra: { sessionId: session.id } };
    },
    async revokeToken(_client, request: OAuthTokenRevocationRequest) {
      const issued = accessTokens.get(request.token) ?? refreshTokens.get(request.token);
      accessTokens.delete(request.token);
      refreshTokens.delete(request.token);
      // Disconnecting Claude ends the session, and with it the key.
      if (issued) endSession(issued.sessionId);
    },
  };

  const metadata = {
    issuer,
    authorization_endpoint: `${issuer}/authorize`,
    token_endpoint: `${issuer}/token`,
    registration_endpoint: `${issuer}/register`,
    revocation_endpoint: `${issuer}/revoke`,
    jwks_uri: `${issuer}/jwks`,
    response_types_supported: ['code'],
    grant_types_supported: ['authorization_code', 'refresh_token'],
    code_challenge_methods_supported: ['S256'],
    token_endpoint_auth_methods_supported: ['none', 'client_secret_post'],
    revocation_endpoint_auth_methods_supported: ['none', 'client_secret_post'],
    scopes_supported: [SCOPE],
    // The OpenID form of the same document, for a client that looks for that one: no identity tokens are issued.
    subject_types_supported: ['public'],
    id_token_signing_alg_values_supported: ['none'],
    service_documentation: 'https://github.com/InfamousVague/glyph/blob/main/docs/MCP.md',
  };
  const resourceMetadataUrl = `${issuer}/.well-known/oauth-protected-resource`;
  const protectedResource = { resource: issuer, authorization_servers: [issuer], scopes_supported: [SCOPE], bearer_methods_supported: ['header'], resource_name: 'Ghost.md notes' };

  const app = express();
  // Behind glyph-api and Caddy on the box, both on loopback: the person's own address is what the limits count.
  app.set('trust proxy', 'loopback');
  app.disable('x-powered-by');

  const json = (value: unknown) => (_req: Request, res: Response) => res.set('Cache-Control', 'no-store').json(value);
  app.get(`${base}/.well-known/oauth-protected-resource`, json(protectedResource));
  app.get(`${base}/.well-known/oauth-authorization-server`, json(metadata));
  app.get(`${base}/.well-known/openid-configuration`, json(metadata));
  app.get(`${base}/jwks`, json({ keys: [] }));
  app.get(`${base}/health`, (_req, res) => {
    sweep();
    res.set('Cache-Control', 'no-store').json({ ok: true, version: VERSION, sessions: sessions.size });
  });

  app.use(`${base}/authorize`, authorizationHandler({ provider, rateLimit }));
  app.use(`${base}/token`, tokenHandler({ provider, rateLimit }));
  app.use(`${base}/register`, clientRegistrationHandler({ clientsStore, rateLimit }));
  app.use(`${base}/revoke`, revocationHandler({ provider, rateLimit }));

  /** The sign-in page's answer: the person's token and, unwrapped in their browser, the account key. */
  app.post(`${base}/authorize/complete`, express.json({ limit: '16kb' }), async (req: Request, res: Response) => {
    const body = req.body as { request?: unknown; handle?: unknown; token?: unknown; accountKey?: unknown };
    const request = typeof body.request === 'string' ? requests.get(body.request) : undefined;
    if (!request || request.expiresAt < now()) {
      res.status(400).json({ error: 'This sign-in page has run out. Go back to Claude and connect again.' });
      return;
    }
    if (typeof body.token !== 'string' || typeof body.accountKey !== 'string' || typeof body.handle !== 'string') {
      res.status(400).json({ error: 'The sign-in was incomplete.' });
      return;
    }
    let key: CryptoKey;
    try {
      // Not extractable: this process can use the key and never read it out.
      key = await importAccountKey(body.accountKey);
    } catch (failure) {
      // The message the person reads says what they can act on; the reason goes to the journal, because the last
      // time this fired it was not the key at all - it was a Node without WebCrypto (mcp/webcrypto.ts).
      process.stderr.write(`glyph-mcp: the account key was refused: ${failureText(failure)}\n`);
      res.status(400).json({ error: globalThis.crypto?.subtle ? 'That is not an account key.' : 'This server cannot open an account key. Its administrator will find the reason in its log.' });
      return;
    }
    const id = randomUUID();
    let handle = body.handle;
    let account: GlyphAccount;
    try {
      // The token is the sync service's to judge, and renewing it is how it is judged; the key is judged by opening the notes.
      account = new GlyphAccount(
        { v: 1, api, handle, accountId: 0, token: body.token, accountKey: '', deviceKey: null },
        {
          key,
          fetcher: options.fetcher,
          lapsed: () => {
            const session = sessions.get(id);
            if (session) session.lapsed = true;
          },
        },
      );
      await account.resume();
      handle = account.handle;
      await account.pull();
    } catch (failure) {
      const words = failure instanceof GlyphApiError ? failure.message : 'That key does not open this account’s notes.';
      res.status(failure instanceof GlyphApiError ? 401 : 400).json({ error: words });
      return;
    }
    requests.delete(body.request as string);
    const registered = request.client.client_name?.trim();
    const session: Session = {
      id,
      handle,
      clientId: request.client.client_id,
      account,
      lastUsed: now(),
      lapsed: false,
      ...(registered ? { client: { name: registered } } : {}),
    };
    sessions.set(id, session);
    const code = newToken();
    codes.set(code, { clientId: request.client.client_id, codeChallenge: request.params.codeChallenge, redirectUri: request.params.redirectUri, sessionId: id, expiresAt: now() + CODE_MS });
    const redirect = new URL(request.params.redirectUri);
    redirect.searchParams.set('code', code);
    if (request.params.state) redirect.searchParams.set('state', request.params.state);
    res.json({ redirect: redirect.href });
  });

  /** MCP itself: one request, one answer, no session held open (the account's own session is the state). */
  app.post(base, requireBearerAuth({ verifier: provider, resourceMetadataUrl }), express.json({ limit: '4mb' }), async (req: Request, res: Response) => {
    const sessionId = (req.auth?.extra as { sessionId?: string } | undefined)?.sessionId;
    const session = sessionId ? sessions.get(sessionId) : undefined;
    if (!session) {
      res.status(401).set('WWW-Authenticate', `Bearer resource_metadata="${resourceMetadataUrl}"`).json({ error: 'That sign-in is over; sign in again.' });
      return;
    }
    session.lastUsed = now();
    // The app says who it is once, when it connects: kept for the requests after, which come to fresh servers.
    const initialize = (req.body as { method?: string; params?: { clientInfo?: { name?: string; title?: string } } } | undefined) ?? {};
    if (initialize.method === 'initialize' && initialize.params?.clientInfo) session.client = { ...initialize.params.clientInfo };
    const server = buildServer(session.account, {
              client: () => session.client,
              // The connections this account has: every session signed in with its handle, this one included.
              connections: () => [...sessions.values()].filter((s) => s.handle === session.handle).length,
              // Sign out everywhere: every one of them ended, tokens and keys with them; the answer to this call
              // still goes out, since the transport it rides is already open.
              signOutEverywhere: () => {
                const ids = [...sessions.values()].filter((s) => s.handle === session.handle).map((s) => s.id);
                for (const id of ids) endSession(id);
                return ids.length;
              },
            });
    const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
    res.on('close', () => {
      void transport.close();
      void server.close();
    });
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  });
  const notHere = (_req: Request, res: Response) => {
    res.status(405).set('Allow', 'POST').json({ error: 'This server answers POST only: one request, one answer.' });
  };
  app.get(base, notHere);
  app.delete(base, notHere);

  return { app, sessions, sweep };
}
