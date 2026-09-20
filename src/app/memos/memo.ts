import type { Note } from '../core/store.ts';

/**
 * A memo: a note that is a few words and nothing else, collected with the others (docs/MEMOS.md).
 *
 * Matt (2026-09-20): "a new type, memo, which is like a note but super small and designed to be collected in a
 * collection of memos". His choices: a memo is a tiny note of its own, so it syncs, links, searches and archives
 * like any note and Obsidian sees a small file; there is one collection, Memos, newest first; it is read and
 * written on a wall of small cards (memos/MemosScreen.tsx); and every + asks whether it is a note, a memo or a
 * canvas that is wanted (notes/NewSheet.tsx).
 *
 * What makes a note a memo is one line of front matter, `kind: memo`, which is how any note from outside carries
 * what it is (docs/MARKDOWN.md, docs/LIBRARY.md). No title: a memo is what it says, and the list names it by its
 * first words as it names any note. Its file goes in the library's `Memos/` folder rather than the inbox.
 */

export const MEMO_KIND = 'memo';
/** The library folder a memo's file lives in (core/noteFolders.ts). */
export const MEMOS_FOLDER = 'Memos';

/** A front matter fence, `---` or `+++`, on a line of its own. */
const FENCE = /^(---|\+\+\+)\s*$/;

/** The keys between a note's front matter fences, and where the body starts after them; null for no front matter. */
function frontMatter(body: string): { keys: string[]; from: number } | null {
  const lines = body.split('\n');
  if (!FENCE.test(lines[0] ?? '')) return null;
  for (let n = 1; n < Math.min(lines.length, 40); n += 1) {
    const line = lines[n] ?? '';
    if (FENCE.test(line)) return { keys: lines.slice(1, n), from: n + 1 };
    if (!/^\s*[\w.-]+\s*:/.test(line) && line.trim() !== '') return null;
  }
  return null;
}

/** Whether the note is a memo: its front matter says `kind: memo`. */
export function isMemo(body: string): boolean {
  const matter = frontMatter(body);
  return !!matter && matter.keys.some((key) => /^\s*kind\s*:\s*memo\s*$/i.test(key));
}

/** A memo's body: the one line of front matter that makes it one, then the words. */
export function memoBody(text: string): string {
  return `---\nkind: ${MEMO_KIND}\n---\n${text.trim()}\n`;
}

/** The words of a memo, without the front matter that makes it one. */
export function memoText(body: string): string {
  const matter = frontMatter(body);
  const lines = body.split('\n');
  return (matter ? lines.slice(matter.from) : lines).join('\n').trim();
}

/** The memos among the notes: not in the archive, newest first - the one collection there is. */
export function memosOf(notes: readonly Note[]): Note[] {
  return notes.filter((n) => !n.archivedAt && isMemo(n.body)).sort((a, b) => b.updatedAt - a.updatedAt);
}

/** The notes that are not memos: what the home page, the sidebar and the tabs show. */
export function withoutMemos(notes: readonly Note[]): Note[] {
  return notes.filter((n) => !isMemo(n.body));
}
