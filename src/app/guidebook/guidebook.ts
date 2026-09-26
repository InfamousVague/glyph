import { isBookBody } from '../book/book.ts';
import { createNote, newNoteId, noteTitle, type Note } from '../core/store.ts';
import { sameTitle } from '../editor/wikiLinks.ts';

/**
 * Ghost.md: The Guide, the app's own manual, built in as a book (docs/BOOKS.md; Matt: "I would like a "Ghost.md: The
 * Guide""). Forty-four chapters in eleven parts, from the first five minutes to how a release ships: Parts I to VI for
 * anyone, Parts VII to XI for someone who reads code. Each chapter is a Markdown file in chapters/, named NN-slug.md so
 * the files' order is the book's, and index.md is the book note itself: `book: true` in its front matter, and its
 * numbered [[links]] are the chapters, found by title as any book's are.
 *
 * The book costs the app nothing until it is added. Only this file is in the bundle: the Markdown is read `?raw`
 * through a lazy glob, so each chapter and the index are chunks of their own, fetched when Settings › About › Add
 * Ghost.md: The Guide is pressed (DESIGN §124). Added, it is ordinary notes, written through the store as a note typed
 * in the editor is, and from then on the person's own to read, edit, share or delete.
 *
 * Adding it twice gives one book. A chapter whose title a note already has is not made again, since the index finds
 * its chapters by title, and a book already there by the guide's title is answered as it is rather than made twice.
 */

export const GUIDE_TITLE = 'Ghost.md: The Guide';

/** A chapter as it ships: its title, read from its heading as the list reads it, and its Markdown. */
export interface GuideChapter {
  title: string;
  body: string;
}

export interface GuideBook {
  /** The book note's body: front matter, the intro, the parts with their numbered links, and the words after them. */
  index: string;
  /** The chapters, in book order. */
  chapters: GuideChapter[];
}

/** Every chapter, each a lazy chunk of its own, keyed by its path; the numbers in the names are the order. */
const CHAPTERS = import.meta.glob<string>('./chapters/*.md', { query: '?raw', import: 'default' });

/** The whole book, read now. Nothing of it is fetched before this is called. */
export async function loadGuideBook(): Promise<GuideBook> {
  const loads = Object.entries(CHAPTERS)
    .sort(([a], [b]) => (a < b ? -1 : 1))
    .map(([, load]) => load());
  const [index, ...bodies] = await Promise.all([import('./index.md?raw').then((raw) => raw.default), ...loads]);
  return { index, chapters: bodies.map((body) => ({ title: noteTitle(body), body })) };
}

/**
 * Puts the guide in the library and answers its index, the note to open. `notes` are the notes there are now, out of
 * the trash; an archived one counts as missing, as it does to a [[link]] (App.tsx `openTitle`). The chapters are made
 * first, the last of them first, so a list sorted newest first reads the book from chapter one; the index comes last,
 * newest of all.
 */
export async function addGuideBook(notes: readonly Note[]): Promise<Note> {
  const shown = notes.filter((note) => !note.archivedAt);
  const already = shown.find((note) => isBookBody(note.body) && sameTitle(noteTitle(note.body), GUIDE_TITLE));
  if (already) return already;
  const book = await loadGuideBook();
  const titled = (title: string) => shown.some((note) => sameTitle(noteTitle(note.body), title));
  for (const chapter of [...book.chapters].reverse()) {
    if (!titled(chapter.title)) await createNote(newNoteId(), chapter.body, 'editor');
  }
  return createNote(newNoteId(), book.index, 'editor');
}
