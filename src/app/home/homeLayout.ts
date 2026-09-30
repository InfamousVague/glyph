import { isBookBody, type BookPlace } from '../book/book.ts';
import { isCanvasBody } from '../canvas/jsonCanvas.ts';
import { frontMatterEnd } from '../core/frontMatter.ts';
import type { HomeLayout } from '../core/preferences.ts';
import { noteTitle, type Note } from '../core/store.ts';
import { matches } from '../notes/allNotes.ts';

/**
 * The home page's rules (home/HomeScreen.tsx; docs/DESIGN.md §147): what it shows, in what order, and the five ways it
 * can lay them out. Pure, so each rule is a test.
 *
 * Matt: "redesign the home page / dashboard to be easier to navigate, remove things like the todo list and other
 * things, focus more on displaying the books and notes in an easy way to search and look through; give me 5 different
 * dashboard layout styles we can choose from in the settings". So the page is the notebooks and the notes, a search
 * over them, and a filter - All, Notebooks, Notes, Pinned - drawn one of five ways.
 */

/** The five layouts, in the order Settings offers them, each with the sentence that says what it looks like. */
export const HOME_LAYOUTS: readonly { id: HomeLayout; label: string; hint: string }[] = [
  { id: 'cards', label: 'Cards', hint: 'Notebooks and notes as cards, each note drawn small.' },
  { id: 'list', label: 'List', hint: 'One line each: the name, how it starts, and when. The most on a screen.' },
  { id: 'shelf', label: 'Shelf', hint: 'Notebooks as covers along a shelf, and the notes as small cards under it.' },
  { id: 'library', label: 'Library', hint: 'Each notebook open with its pages under it, then the notes in no notebook.' },
  { id: 'timeline', label: 'Timeline', hint: 'Everything by when you last touched it: today, yesterday, this week and earlier.' },
];

/** What the page is showing: everything, only notebooks, only loose notes and pages, or only what is pinned. */
export type HomeFilter = 'all' | 'books' | 'notes' | 'pinned';

export const HOME_FILTERS: readonly { id: HomeFilter; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'books', label: 'Notebooks' },
  { id: 'notes', label: 'Notes' },
  { id: 'pinned', label: 'Pinned' },
];

/** A note's kind as the page marks it: a notebook (a journal is one), a canvas, or words. */
export type HomeKind = 'book' | 'canvas' | 'note';

export function kindOf(note: Note): HomeKind {
  if (isBookBody(note.body)) return 'book';
  if (isCanvasBody(note.body)) return 'canvas';
  return 'note';
}

/** What the page lists: the notebooks and the notes, each newest first, pinned ones first within each. */
export interface HomeLists {
  books: Note[];
  notes: Note[];
}

const newestPinnedFirst = (a: Note, b: Note) => Number(Boolean(b.starred)) - Number(Boolean(a.starred)) || b.updatedAt - a.updatedAt;

/** The notes the page shows under a search and a filter, never the archive. */
export function homeLists(all: readonly Note[], query: string, filter: HomeFilter): HomeLists {
  const shown = all.filter((n) => !n.archivedAt && matches(n, query) && (filter !== 'pinned' || n.starred));
  const books = filter === 'notes' ? [] : shown.filter((n) => kindOf(n) === 'book').sort(newestPinnedFirst);
  const notes = filter === 'books' ? [] : shown.filter((n) => kindOf(n) !== 'book').sort(newestPinnedFirst);
  return { books, notes };
}

/** How many of each kind there are, for the filter's counts: the archive left out, the search not applied. */
export function homeCounts(all: readonly Note[]): Record<HomeFilter, number> {
  const live = all.filter((n) => !n.archivedAt);
  const books = live.filter((n) => kindOf(n) === 'book').length;
  return { all: live.length, books, notes: live.length - books, pinned: live.filter((n) => n.starred).length };
}

/**
 * How a note starts, on one line, after its name: its first line of words that is not its title, the marks that start
 * a line and the stars around words taken off. Empty for a note with nothing under its name.
 */
export function firstLine(body: string, most = 120): string {
  const lines = body.split('\n');
  const title = noteTitle(body).trim();
  let titleSeen = false;
  for (const raw of lines.slice(frontMatterEnd(lines))) {
    const line = raw
      .replace(/^\s*(?:#{1,6}\s+|>\s?|[-*+]\s+\[[ xX]\]\s*|[-*+]\s+|\d+[.)]\s+)/, '')
      .replace(/\*\*|__|`/g, '')
      .trim();
    if (!line) continue;
    if (!titleSeen && line === title) {
      titleSeen = true;
      continue;
    }
    return line.length > most ? `${line.slice(0, most - 1).trimEnd()}…` : line;
  }
  return '';
}

/** The timeline's spans, newest first. */
export type Span = 'today' | 'yesterday' | 'week' | 'month' | 'earlier';

export const SPAN_WORDS: Record<Span, string> = {
  today: 'Today',
  yesterday: 'Yesterday',
  week: 'Earlier this week',
  month: 'This month',
  earlier: 'Earlier',
};

/** Which span a moment falls in, counted in this device's days from `now`. */
export function spanOf(at: number, now = Date.now()): Span {
  const start = new Date(now);
  start.setHours(0, 0, 0, 0);
  const day = 24 * 60 * 60 * 1000;
  const today = start.getTime();
  if (at >= today) return 'today';
  if (at >= today - day) return 'yesterday';
  if (at >= today - 6 * day) return 'week';
  if (at >= today - 30 * day) return 'month';
  return 'earlier';
}

/** Notebooks and notes together, grouped by when each was last touched, the spans in order and empty ones left out. */
export function timeline(lists: HomeLists, now = Date.now()): { span: Span; notes: Note[] }[] {
  const every = [...lists.books, ...lists.notes].sort((a, b) => b.updatedAt - a.updatedAt);
  const order: Span[] = ['today', 'yesterday', 'week', 'month', 'earlier'];
  return order.map((span) => ({ span, notes: every.filter((n) => spanOf(n.updatedAt, now) === span) })).filter((group) => group.notes.length);
}

/**
 * The library: each notebook with the notes that are its pages, in its order, and then the notes in no notebook.
 * `placeOf` is the book index's lookup (book/book.ts); a page in two notebooks shows under each.
 */
export function library(lists: HomeLists, pagesOf: (book: Note) => Note[], placeOf: (note: Note) => BookPlace | null): { books: { book: Note; pages: Note[] }[]; loose: Note[] } {
  return {
    books: lists.books.map((book) => ({ book, pages: pagesOf(book) })),
    loose: lists.notes.filter((n) => !placeOf(n)),
  };
}
