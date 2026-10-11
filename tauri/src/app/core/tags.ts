/**
 * A tag's grammar, read here and drawn in editor/tags.ts (Matt: "add ability to make tags on list items"):
 *
 *   - [ ] Ship the pricing page #web #launch
 *
 * Written the way Obsidian and Bear write them, so a note reads the same elsewhere: a `#` straight against a letter,
 * then letters, digits, `_`, `-` or `/` (for `#work/clients`). A `#` with a space after it is a heading, a `#` inside
 * a word or a link is part of that. On a linked item, tags go with the words, before the mark and the anchor:
 * `- [ ] Ship it #web [notion](…) ^ship`.
 *
 * Here in core/ and not beside the drawing since 2026-09-30, because two readers away from the editor need the same
 * answer: a query's `from: #bug` (docs/DESIGN.md §156), which reads notes the editor has never opened, and the fields'
 * writer (core/taskFields.ts), which keeps Obsidian Tasks' fields at the end of an item's words with its tags among
 * them. Pure, and it imports nothing, so the MCP server can bundle it. What counts as code or an address is the
 * caller's to say: the editor asks its parser (editor/syntax.ts `inQuietText`).
 */

/** A tag: after the line's start or a space or an opening bracket, `#`, a letter, then the rest of the name. */
export const TAG = /(^|[\s([{])(#[\p{L}][\p{L}\p{N}_/-]*)/gu;

export interface Tag {
  /** The `#` and the name. */
  from: number;
  to: number;
  /** The name without the `#`, lower-cased: how two tags are compared. */
  name: string;
}

/** Every tag in `text`, counting positions from `offset`. A trailing `-` or `/` is punctuation, not the name. */
export function tagsIn(text: string, offset = 0): Tag[] {
  const found: Tag[] = [];
  const pattern = new RegExp(TAG.source, TAG.flags);
  for (let match = pattern.exec(text); match; match = pattern.exec(text)) {
    const written = (match[2] ?? '').replace(/[-/]+$/, '');
    const from = offset + match.index + (match[1] ?? '').length;
    found.push({ from, to: from + written.length, name: written.slice(1).toLowerCase() });
  }
  return found;
}
