import { isBookBody } from '../book/book.ts';
import { isCanvasBody } from '../canvas/jsonCanvas.ts';
import { frontMatterEnd } from '../core/frontMatter.ts';
import type { HomeLayout } from '../core/preferences.ts';
import { noteTitle, type Note } from '../core/store.ts';
import { hasTape, matches } from '../notes/allNotes.ts';

/**
 * The home page's rules (home/HomeScreen.tsx; docs/DESIGN.md §147, §148): what it shows, in what order, and the ways
 * it can lay them out. Pure, so each rule is a test.
 *
 * Matt: "redesign the home page / dashboard to be easier to navigate, remove things like the todo list and other
 * things, focus more on displaying the books and notes in an easy way to search and look through; give me 5 different
 * dashboard layout styles we can choose from in the settings". So the page is the notebooks and the notes, a search
 * over them, and a filter - All, Notebooks, Notes, Pinned, and the workspace - drawn one of several ways.
 *
 * Then: "i like the card view and the timeline view add a few more variations that are mixes and matches of different
 * views" (docs/DESIGN.md §148), which made nine. Nine was too many to choose between (Matt, 2026-10-03: "cut the home
 * page layout selection down to 4 items and show them in cards representing the actual layout", §178): the four that
 * differ stay - Spotlight, Cards, Timeline and List - and Settings draws each as a small picture of itself
 * (settings/LayoutCards.tsx). The mixes, the Shelf and the Library went with the code that drew them.
 */

/**
 * The layouts, in the order Settings offers them, each with the sentence that says what it looks like: Spotlight, the
 * default (Matt: "make the spotlight mode the default"), then the two Matt liked, then the list.
 */
export const HOME_LAYOUTS: readonly { id: HomeLayout; label: string; hint: string }[] = [
  { id: 'spotlight', label: 'Spotlight', hint: 'Your pinned notes in a list, the four you touched last as cards, then everything else by when.' },
  { id: 'cards', label: 'Cards', hint: 'Notebooks and notes as cards, each note drawn small.' },
  { id: 'timeline', label: 'Timeline', hint: 'Everything by when you last touched it: today, yesterday, this week and earlier.' },
  { id: 'list', label: 'List', hint: 'One line each: the name, how it starts, and when. The most on a screen.' },
];

/**
 * The most cards a layout draws. A card is the note itself drawn small (notes/NotePeek.tsx), an editor each, so each
 * layout that draws them stops here (`homePlan`) and the foot sends the rest to All notes.
 */
export const CARDS_AT_MOST = 48;

/** How many cards Spotlight leads with. */
export const SPOTLIT = 4;

/** What the page is showing: everything, only notebooks, only notes and pages, or only what is pinned. */
export type HomeFilter = 'all' | 'books' | 'notes' | 'pinned';

export const HOME_FILTERS: readonly { id: HomeFilter; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'books', label: 'Notebooks' },
  { id: 'notes', label: 'Notes' },
  { id: 'pinned', label: 'Pinned' },
];

/**
 * A note's kind as the page marks it: a notebook (a journal is one), a canvas, a voice recording (a note with its tape
 * kept, notes/allNotes.ts `hasTape`), or words. A recording is a note like any other in every list and filter; its kind
 * is only how its row looks (Matt: "make it so voice recordings also show up in the timeline", docs/DESIGN.md §150).
 */
export type HomeKind = 'book' | 'canvas' | 'tape' | 'note';

export function kindOf(note: Note): HomeKind {
  if (isBookBody(note.body)) return 'book';
  if (isCanvasBody(note.body)) return 'canvas';
  if (hasTape(note)) return 'tape';
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

const SPANS: readonly Span[] = ['today', 'yesterday', 'week', 'month', 'earlier'];

/** Notes grouped by when each was last touched, newest first within each, the spans in order and empty ones left out. */
export function spans(notes: readonly Note[], now = Date.now()): { span: Span; notes: Note[] }[] {
  const every = [...notes].sort((a, b) => b.updatedAt - a.updatedAt);
  return SPANS.map((span) => ({ span, notes: every.filter((n) => spanOf(n.updatedAt, now) === span) })).filter((group) => group.notes.length);
}

/** Notebooks and notes together, newest first: what the timelines draw, and what they stop at. */
export function together(lists: HomeLists): Note[] {
  return [...lists.books, ...lists.notes].sort((a, b) => b.updatedAt - a.updatedAt);
}

/** Notebooks and notes together, grouped by when each was last touched. */
export function timeline(lists: HomeLists, now = Date.now()): { span: Span; notes: Note[] }[] {
  return spans(together(lists), now);
}

/**
 * Spotlight's cards and rows: the few touched last, as cards, and everything else by when. By when alone, not pinned
 * first: the cards are where the person was. `homePlan` draws the pinned notes in a list of their own above them, and
 * hands this only the rest.
 */
export function spotlight(lists: HomeLists, lead = SPOTLIT, now = Date.now()): { lead: Note[]; rest: { span: Span; notes: Note[] }[] } {
  const every = together(lists);
  return { lead: every.slice(0, lead), rest: spans(every.slice(lead), now) };
}

/** A section's mark before its heading: a notebook's, a note's, the pin, the clock of the recent ones, or none (a span). */
export type SectionMark = 'notebook' | 'note' | 'pinned' | 'recent' | null;

/**
 * How a section draws its notes: as cards, as rows, or as lines - one short line a note, its name and when, the
 * simplest list the page has.
 */
export type SectionDraw = 'cards' | 'rows' | 'lines';

/** A section under a heading of words: "Notebooks", "Today", "In no notebook". `count` is how many in all, where drawn. */
export interface WordsSection {
  key: string;
  heading: string;
  mark: SectionMark;
  count: number | null;
  draw: SectionDraw;
  notes: Note[];
}

/** Every section is one of words now: the Library's and Notebook cards' own went with those layouts (§178). */
export type HomeSection = WordsSection;

/** The page in one layout: its sections in order, and how many notes were left for All notes (`cut`). */
export interface HomePlan {
  sections: HomeSection[];
  cut: number;
}

export interface PlanWays {
  /**
   * The moment the spans are counted from: any time today will do, so the page passes the start of the day and makes a
   * new plan when the day turns rather than on every draw.
   */
  now?: number;
  /** The most cards the card layouts draw (`CARDS_AT_MOST`); a test sets it lower. */
  most?: number;
}

const byWhen = (groups: { span: Span; notes: Note[] }[], draw: SectionDraw): WordsSection[] =>
  groups.map(({ span, notes }) => ({ key: span, heading: SPAN_WORDS[span], mark: null, count: notes.length, draw, notes }));

/**
 * What the page draws in a layout, as sections. Cards stops at `most` cards; what it left out is `cut`, which the foot
 * counts on its way to All notes. Rows and lines are cheap, and never stop.
 */
export function homePlan(layout: HomeLayout, lists: HomeLists, ways: PlanWays = {}): HomePlan {
  const { books, notes } = lists;
  const now = ways.now ?? Date.now();
  const most = ways.most ?? CARDS_AT_MOST;
  const sections: HomeSection[] = [];
  const add = (section: WordsSection) => {
    if (section.notes.length) sections.push(section);
  };
  const notebooks = (draw: SectionDraw) => add({ key: 'books', heading: 'Notebooks', mark: 'notebook', count: books.length, draw, notes: books });
  let cut = 0;

  switch (layout) {
    case 'cards': {
      notebooks('cards');
      add({ key: 'notes', heading: 'Notes', mark: 'note', count: notes.length, draw: 'cards', notes: notes.slice(0, most) });
      cut = Math.max(0, notes.length - most);
      break;
    }
    case 'list': {
      notebooks('rows');
      add({ key: 'notes', heading: 'Notes', mark: 'note', count: notes.length, draw: 'rows', notes });
      break;
    }
    case 'timeline': {
      sections.push(...byWhen(timeline(lists, now), 'rows'));
      break;
    }
    case 'spotlight': {
      // The pinned notes first, a line each, above Recent (Matt: "add a section above all the others that shows above
      // recent that's a simple list of pinned notes"), and not again below it: a pin is a place of its own, as it is
      // at the top of a phone's notes.
      const pinned = together(lists).filter((n) => n.starred);
      add({ key: 'pinned', heading: 'Pinned', mark: 'pinned', count: pinned.length, draw: 'lines', notes: pinned });
      const unpinned = { books: books.filter((n) => !n.starred), notes: notes.filter((n) => !n.starred) };
      const lit = spotlight(unpinned, Math.min(SPOTLIT, most), now);
      add({ key: 'recent', heading: 'Recent', mark: 'recent', count: null, draw: 'cards', notes: lit.lead });
      sections.push(...byWhen(lit.rest, 'rows'));
      break;
    }
  }
  return { sections, cut };
}

/** Every note a plan draws as a card, in the page's order: the ones a line under the title is written for first. */
export const cardsIn = (plan: HomePlan): Note[] => plan.sections.flatMap((section) => (section.draw === 'cards' ? section.notes : []));
