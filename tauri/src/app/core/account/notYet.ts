/**
 * The one 404 that is not an answer (docs/TEAMS.md, "Not yet"), in a module of its own with no imports: the page's
 * api.ts re-exports it, and the MCP server (mcp/glyph.ts) imports it from here, since api.ts reads
 * `import.meta.env` as it loads, which Node has no value for and the MCP bundles run under Node.
 */

/** What the service answers for a route it does not have (server/src/main.rs): the one 404 that is not an answer. */
export const NO_SUCH_ROUTE = 'no such route';

/** The service's words in a refusal's body, `{ error }`, or null where the body is not one. */
export function wordsOf(body: unknown): string | null {
  return body && typeof body === 'object' && typeof (body as { error?: unknown }).error === 'string' ? (body as { error: string }).error : null;
}

/**
 * Whether a refusal means the service does not have the route yet: the organizations and notifications routes ship
 * on the service first and reach the page after the login gap, and in between - or against an older service - a
 * page must stay quiet rather than show a failure. Not yet is a 404 whose body is the service's
 * `{ error: 'no such route' }`, or no service body at all (a proxy's 404). Every other 404 is an answer in the
 * service's words - "No one has that handle.", "You were not invited." - and is shown as one.
 *
 * Reads `status` and `body` off whatever was thrown, so the page's `ApiError` (core/account/api.ts) and the MCP
 * server's own error (mcp/glyph.ts `GlyphApiError`, which carries the same two) both ask it.
 */
export function notYet(failure: unknown): boolean {
  if (!(failure instanceof Error) || (failure as { status?: unknown }).status !== 404) return false;
  const words = wordsOf((failure as { body?: unknown }).body);
  return words === null || words === NO_SUCH_ROUTE;
}
