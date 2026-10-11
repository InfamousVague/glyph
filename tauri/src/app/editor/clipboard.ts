/**
 * The clipboard, as the note's press-and-hold menu reaches it (editor/ContextMenu.tsx).
 *
 * Reading it is the one thing the page cannot do in Android's WebView, which refuses `clipboard.read`: the activity
 * reads it instead and answers `GlyphHost.readClipboard` (core/host.ts), from native generation 12. The browser's
 * reader is tried where the activity gives nothing, which is what the web app has. Writing is allowed, so Cut and
 * Copy are the page's own.
 */

/** What the activity found on the clipboard: words, a picture it copied out by path, or why it could not read. */
export type Clipboard = { text?: string; path?: string; error?: string };

/**
 * What is on the clipboard, however this build can find out, and whether anything could actually answer.
 *
 * The activity is asked first: it is the only reader that answers with a picture, and inside the app it is usually
 * the only reader there is - `navigator.clipboard.readText` is missing or refuses in Android's WebView, where the
 * permission behind it is not wired up. The browser's reader is tried where the activity gives nothing. When neither
 * answers, that is not the same as an empty clipboard, and `read` says so, because a message claiming the clipboard
 * is empty when it could not be read sends a person looking in the wrong place. A browser reader that throws is the
 * caller's to answer.
 */
export async function readClipboard(): Promise<{ clip: Clipboard; read: boolean }> {
  const host = window.GlyphHost;
  let said: Clipboard = {};
  if (typeof host?.readClipboard === 'function') {
    try {
      const answer = host.readClipboard();
      said = answer ? (JSON.parse(answer) as Clipboard) : {};
    } catch {
      // The activity could not read it (an older build, or a read that threw): the browser is tried below.
      said = {};
    }
  }
  if (said.text || said.path || said.error) return { clip: said, read: true };
  if (typeof navigator.clipboard?.readText !== 'function') return { clip: said, read: false };
  // A reader that answers, even with nothing, has told us the clipboard is empty.
  const text = await navigator.clipboard.readText();
  return text ? { clip: { text }, read: true } : { clip: {}, read: true };
}

/** Whether a Paste row is worth showing at all: one of the two readers is there to try. */
export function clipboardReadable(): boolean {
  return typeof window.GlyphHost?.readClipboard === 'function' || typeof navigator.clipboard?.readText === 'function';
}

/** Words onto the clipboard, however this browser lets them go there. */
export async function writeClipboard(words: string): Promise<void> {
  try {
    await navigator.clipboard.writeText(words);
  } catch {
    // A browser with no clipboard access: the old way still copies a selection.
    document.execCommand('copy');
  }
}
