import type { OAuthClientProvider } from '@modelcontextprotocol/sdk/client/auth.js';
import type { OAuthClientInformationFull, OAuthClientMetadata, OAuthTokens } from '@modelcontextprotocol/sdk/shared/auth.js';

/**
 * Claude's side of an OAuth connection, stood in for in memory, for the hosted server's tests (hosted.test.ts,
 * mcp.e2e.test.ts). The sync service these tests talk to is src/test/fakeService.ts, shared with the app's own tests:
 * it lived here once, beside a second copy in core/sync/pictures.test.ts, until the two were made one.
 */

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

