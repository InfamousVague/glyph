import { noteTitle, type Note } from '../core/store.ts';

/**
 * The rules behind the All notes page (notes/AllNotesScreen.tsx): which notes it shows, in what order, and what a
 * search over them finds. Pure, so each rule is a test rather than a page to scroll through.
 *
 * Matt: "Browsing all notes is super hard there is no good UI it just opens in the sidebar, I'd like a grid view of
 * all the notes in the 'all notes' section." The sidebar is a tree for jumping to a note you know; the page is for
 * looking. So it takes every note the home page's workspace shows, lets the search narrow them, orders them one of
 * two ways, and keeps the archive out unless it is asked for.
 */

/** How the page orders its cards: the last touched first, or by name. */
export type AllNotesSort = 'newest' | 'title';

export const SORTS: readonly { id: AllNotesSort; label: string }[] = [
  { id: 'newest', label: 'Newest' },
  { id: 'title', label: 'A to Z' },
];

export interface Browse {
  /** Words typed into the search: a note is shown when they all appear somewhere in it. Blank shows every note. */
  query: string;
  sort: AllNotesSort;
  /** Whether the archived notes are shown too. They are marked on their cards when they are. */
  archived: boolean;
}

/** Words that count as having no title, so a note with none sorts after the named ones. */
const untitled = (note: Note) => noteTitle(note.body).trim() === '';

/**
 * Whether a note has every word of the query, in its title or its body, whatever the case. Words rather than the
 * whole phrase, so "trip packing" finds a note with those two words anywhere in it.
 */
export function matches(note: Note, query: string): boolean {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  if (!words.length) return true;
  const text = note.body.toLowerCase();
  return words.every((word) => text.includes(word));
}

/** A title to sort by: the note's own, lower-cased, with a nameless note's blank sorting after every name. */
function sortKey(note: Note): string {
  return noteTitle(note.body).trim().toLowerCase();
}

/** The notes the page shows, in the order it shows them. */
export function browseNotes(notes: readonly Note[], browse: Browse): Note[] {
  const shown = notes.filter((n) => (browse.archived || !n.archivedAt) && matches(n, browse.query));
  if (browse.sort === 'title') {
    return shown.sort((a, b) => {
      const blankA = untitled(a);
      const blankB = untitled(b);
      if (blankA !== blankB) return blankA ? 1 : -1;
      return sortKey(a).localeCompare(sortKey(b)) || b.updatedAt - a.updatedAt;
    });
  }
  return shown.sort((a, b) => b.updatedAt - a.updatedAt);
}

/** How many notes are in the archive, for the toggle that shows them. */
export function archivedCount(notes: readonly Note[]): number {
  return notes.filter((n) => Boolean(n.archivedAt)).length;
}

/** The order chosen last time, kept on the device (core/reset.ts clears it). */
const SORT_KEY = 'glyph-all-notes-sort';

export function readSort(): AllNotesSort {
  try {
    return localStorage.getItem(SORT_KEY) === 'title' ? 'title' : 'newest';
  } catch {
    // Storage that cannot be read: the newest first, as on the home page.
    return 'newest';
  }
}

export function writeSort(sort: AllNotesSort): void {
  try {
    localStorage.setItem(SORT_KEY, sort);
  } catch {
    // Storage that cannot be written: the choice holds for this page, and is asked again next time.
  }
}
