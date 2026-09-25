/**
 * Words on the end of a note's body, with the one blank line between that every writer of a note agrees on.
 *
 * Two joins. `appendBody` is a capture's words below a note it continues: what a draft, the live page, the better
 * words and the voice suite all write with (it lived in continuation.ts, which went with memo mode). `appendBlock` is a
 * block of its own - a table, a list started for spoken items, a left note - put at the end, ending in a line break as
 * a written note does. The list writer spelled the second one out twice; it is this now.
 */

/** `addition` below `base`, a blank line between, for a note that grew by another recording. */
export function appendBody(base: string, addition: string): string {
  if (!addition.trim()) return base;
  if (!base.trim()) return addition;
  return `${base.replace(/\s+$/, '')}\n\n${addition}`;
}

/** `body` with `block` as its own block at the end, after a blank line when there is anything above it, and a line break after. */
export function appendBlock(body: string, block: string): string {
  const base = body.replace(/\s+$/, '');
  return `${base}${base ? '\n\n' : ''}${block}\n`;
}
