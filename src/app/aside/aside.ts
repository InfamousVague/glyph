import { bookIndex, chaptersOf, isBookBody, type BookPlace } from '../book/book.ts';
import { chapterOf } from '../book/chapterNumber.ts';
import { noteTitle, type Note } from '../core/store.ts';
import { wikiLinksIn } from '../editor/wikiLinks.ts';

/**
 * What the right-hand aside shows (Matt: "a right side aside menu that can pop out book indexes"), or nothing:
 *
 * - **A book**, while it or one of its pages is open: its index, the open chapter marked.
 * - **Chapters with no book**, while a numbered chapter is open (book/chapterNumber.ts): it and its fellow chapters,
 *   in the order of their numbers (Matt: "that should let us lay out the chapters in order when there is no book").
 * - **Nothing** anywhere else, and the aside and its toggle aren't shown (Matt: "when there is no book on the page
 *   and there is no use for the aside don't show it"). It used to list the workspace's other notes here.
 *
 * Pure, so each rule is a test.
 */
export type AsideContent =
  | { kind: 'book'; place: BookPlace; open: string | null }
  | { kind: 'chapters'; title: string; titleId: string | null; chapters: NumberedChapter[]; open: string };

export interface NumberedChapter {
  id: string;
  number: number;
  /** The title without its number: the number is drawn in its own column. */
  name: string;
}

/**
 * `notes` are the library's notes as the app shows them; `open` the note on screen, or null on the home page.
 * A book shows its own index with no chapter marked; a page of one shows its book's with itself marked.
 */
export function asideContent(notes: readonly Note[], open: Note | null): AsideContent | null {
  if (!open) return null;
  if (isBookBody(open.body)) {
    return { kind: 'book', place: { book: open, title: noteTitle(open.body), chapters: chaptersOf(open.body), at: -1 }, open: null };
  }
  const place = bookIndex(notes).get(keyOf(noteTitle(open.body)));
  if (place) return { kind: 'book', place, open: open.id };
  return chapterRun(notes, open);
}

/**
 * The numbered chapters that belong with the open one, in order. Chapters belong together when their pages point at
 * the same note first (a chapter's "« [[The book]]" line; a link to another numbered chapter doesn't count), or,
 * with no such link, when they sit in the same folder. One chapter alone is no run, so it shows nothing.
 */
function chapterRun(notes: readonly Note[], open: Note): AsideContent | null {
  const mine = chapterOf(noteTitle(open.body));
  if (!mine) return null;
  const group = groupOf(open);
  const chapters: NumberedChapter[] = [];
  for (const note of notes) {
    if (note.archivedAt || isBookBody(note.body)) continue;
    const numbered = note.id === open.id ? mine : chapterOf(noteTitle(note.body));
    if (!numbered || groupOf(note).key !== group.key) continue;
    chapters.push({ id: note.id, number: numbered.number, name: numbered.name });
  }
  if (chapters.length < 2) return null;
  chapters.sort((a, b) => a.number - b.number || a.name.localeCompare(b.name));
  const titleId = group.link ? (notes.find((n) => keyOf(noteTitle(n.body)) === keyOf(group.link!))?.id ?? null) : null;
  return { kind: 'chapters', title: group.link ?? group.folder ?? 'Chapters', titleId, chapters, open: open.id };
}

/** What a chapter belongs to: the first note its page points at that isn't another chapter, else its folder. */
function groupOf(note: Note): { key: string; link: string | null; folder: string | null } {
  const own = keyOf(noteTitle(note.body));
  for (const link of wikiLinksIn(note.body)) {
    const title = link.title.trim();
    if (!title || keyOf(title) === own || chapterOf(title)) continue;
    return { key: `link:${keyOf(title)}`, link: title, folder: null };
  }
  const folder = note.path?.includes('/') ? note.path.slice(0, note.path.lastIndexOf('/')) : null;
  return { key: `folder:${folder ?? ''}`, link: null, folder: folder ? folder.split('/').pop()! : null };
}

/** The key `bookIndex` files a page under (book/book.ts `titleKey`), without the import cycle a re-export would make. */
function keyOf(title: string): string {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

/** Whether the aside is shown, kept to this device between launches; hidden until it has been opened once. */
const SHOWN_KEY = 'glyph-aside-shown';

export function readAsideShown(): boolean {
  try {
    return localStorage.getItem(SHOWN_KEY) === '1';
  } catch {
    return false;
  }
}

export function writeAsideShown(shown: boolean): void {
  try {
    localStorage.setItem(SHOWN_KEY, shown ? '1' : '0');
  } catch {
    // Not kept: it opens hidden next time.
  }
}
