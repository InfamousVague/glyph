/**
 * A fresh id that nothing else has: a note's, a conflict copy's, a picture's.
 *
 * `crypto.randomUUID` needs a secure context, which a Tauri custom protocol is
 * and an `http://` dev server on a phone on the LAN is not - so the fallback is
 * not hypothetical, it is what runs when the editor is opened from another
 * device on the network. The fallback is the time and eight random characters
 * behind a prefix that says what the id is for, which is unique enough for
 * the ids one device makes.
 *
 * Two modules wrote this out, and a third - the pictures' - called
 * `crypto.randomUUID` with no fallback, so pasting a picture on the LAN dev
 * server threw. A leaf with no imports, so the MCP server shares it too.
 */

/** A UUID where the context allows one, and `<prefix>-<time>-<random>` where it does not. */
export function randomId(prefix = 'n'): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}
