/**
 * A caught thing, as words a person can read.
 *
 * `catch` hands over `unknown`. It is usually an Error, whose message is the
 * sentence, but a Tauri command rejects with the string Rust returned, and a
 * promise can reject with anything at all. Every place that shows or logs a
 * failure wants the same answer - the message when there is one, the thing
 * itself as text when there is not - and the tree had written that expression
 * out 43 times, under three names for the thing caught, before it lived here.
 *
 * A leaf with no imports on purpose: the MCP server (mcp/) and the reader page
 * (src/read/) share it, and neither may pull in the webview to say what went
 * wrong. A caller whose fallback is not this one - core/account/api.ts turns
 * any network failure into one fixed sentence - keeps its own expression.
 */

/** `failure`'s message when it is an Error, and `failure` as text when it is not. */
export function failureText(failure: unknown): string {
  return failure instanceof Error ? failure.message : String(failure);
}
