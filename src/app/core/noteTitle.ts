import { frontMatterEnd } from './frontMatter.ts';

/**
 * A note's title: the first line of its words, which is the only title Glyph has, and its lines with the front
 * matter taken off, which the title, a note's peek (notes/peek.ts) and a book's chapter (book/book.ts) all start
 * from.
 *
 * Lives here rather than in core/store.ts, which re-exports both for its callers, because the MCP server titles
 * notes too (mcp/glyph.ts, mcp/server.ts: `list_notes`, and finding a note by its title), and store.ts reaches for
 * React and the Tauri bridge, which a Node bundle cannot take. So the server kept a copy, and the copy drifted: it
 * took any block between two fences as front matter, and a note that opened with a rule, some words and another rule
 * was called one thing in the app's list and another by Claude's tools. This module imports nothing but the front
 * matter rule, so the server bundles the same code the list runs.
 */

/** A note's lines with its front matter taken off, and its `title:` first where it has one. */
export function withoutFrontMatter(lines: readonly string[]): string[] {
  const end = frontMatterEnd(lines);
  if (!end) return [...lines];
  const named = lines.slice(1, end - 1).find((key) => /^\s*title\s*:/i.test(key));
  const title = named
    ? named
        .replace(/^\s*title\s*:\s*/i, '')
        .replace(/^['"]|['"]$/g, '')
        .trim()
    : '';
  return title ? [title, ...lines.slice(end)] : lines.slice(end);
}

/** The first line of a note, which is the only title Glyph has. */
export function noteTitle(body: string): string {
  // A note that opens with front matter is titled by its words, not by the
  // fence: `---` in the list looked like a note with no name at all
  // (docs/MARKDOWN.md). The keys between the fences are skipped with it, and
  // `title:` among them is taken as the name, which is what wrote it.
  const lines = withoutFrontMatter(body.split('\n'));
  // The first line that is words, not a picture: a note that opens with a
  // photo is titled by what is said under it.
  const line = lines.find((l) => l.trim() && !/^!\[[^\]]*\]\([^)]*\)\s*$/.test(l)) ?? '';
  // Strip leading heading markers for the LIST only. The note itself keeps
  // every character; this is a label, not an edit.
  // The bookmark's mark too (editor/bookmarkLine.ts): set on the first line, it said "Weekend trip §§" in every tab and
  // card. It says where the note opens, not what it is called.
  return line.replace(/^#{1,6}\s+/, '').replace(/\s*§§\s*/g, ' ').trim();
}
