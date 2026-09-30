import { isBookBody, isJournalBody, type BookPlace } from '../book/book.ts';
import { stampOf } from '../book/journal.ts';
import { isCanvasBody } from '../canvas/jsonCanvas.ts';
import { frontMatterEnd } from '../core/frontMatter.ts';
import type { HomeLayout } from '../core/preferences.ts';
import { noteTitle, type Note } from '../core/store.ts';
import { matches } from '../notes/allNotes.ts';

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
 * views" (docs/DESIGN.md §148). The four mixes put the two he liked first and cross them with the others: the cards
 * by when, the newest few as cards over a timeline, the shelf over a timeline, and each notebook with its pages as
 * cards.
 */

/**
 * The layouts, in the order Settings offers them, each with the sentence that says what it looks like: Spotlight, the
 * default (Matt: "make the spotlight mode the default"), then the two Matt liked, the other mixes of them, and the three
 * single ways the page was first drawn.
 */
export const HOME_LAYOUTS: readonly { id: HomeLayout; label: string; hint: string }[] = [
  { id: 'spotlight', label: 'Spotlight', hint: 'The four you touched last as cards, then everything else by when.' },
  { id: 'cards', label: 'Cards', hint: 'Notebooks and notes as cards, each note drawn small.' },
  { id: 'timeline', label: 'Timeline', hint: 'Everything by when you last touched it: today, yesterday, this week and earlier.' },
  { id: 'card-timeline', label: 'Card timeline', hint: 'Cards, under today, yesterday, this week and earlier.' },
  { id: 'shelf-timeline', label: 'Shelf and timeline', hint: 'Notebooks as covers along a shelf, then the notes by when.' },
  { id: 'notebook-cards', label: 'Notebook cards', hint: 'Each notebook with its pages as cards, then the notes in no notebook.' },
  { id: 'list', label: 'List', hint: 'One line each: the name, how it starts, and when. The most on a screen.' },
  { id: 'shelf', label: 'Shelf', hint: 'Notebooks as covers along a shelf, and the notes as small cards under it.' },
  { id: 'library', label: 'Library', hint: 'Each notebook open with its pages under it, then the notes in no notebook.' },
];

/**
 * The most cards a layout draws. A card is the note itself drawn small (notes/NotePeek.tsx), an editor each, so each
 * layout that draws them stops here (`homePlan`) and the foot sends the rest to All notes.
 */
export const CARDS_AT_MOST = 48;

/** How many cards Spotlight leads with, and how many pages Notebook cards shows of each notebook before "More". */
export const SPOTLIT = 4;
export const PAGES_CARDED = 6;

/** What the page is showing: everything, only notebooks, only notes and pages, or only what is pinned. */
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
 * Spotlight: the few touched last, as cards, and everything else by when. By when alone, not pinned first: the cards
 * are where the person was, and a pinned note has its pin on its row further down, or the Pinned filter.
 */
export function spotlight(lists: HomeLists, lead = SPOTLIT, now = Date.now()): { lead: Note[]; rest: { span: Span; notes: Note[] }[] } {
  const every = together(lists);
  return { lead: every.slice(0, lead), rest: spans(every.slice(lead), now) };
}

/** A section's mark before its heading: a notebook's, a note's, the clock of the recent ones, or none (a span). */
export type SectionMark = 'notebook' | 'note' | 'recent' | null;

/** How a section draws its notes: as cards, as the Shelf's small cards, as rows, or as covers along a shelf. */
export type SectionDraw = 'cards' | 'dense' | 'rows' | 'covers';

/** A section under a heading of words: "Notebooks", "Today", "In no notebook". `count` is how many in all, where drawn. */
export interface WordsSection {
  key: string;
  heading: string;
  mark: SectionMark;
  count: number | null;
  draw: SectionDraw;
  notes: Note[];
}

/**
 * A notebook's own section (Library, Notebook cards): its name opens it, its pages under it, `more` past what is drawn.
 * Its pages are every page of it, whatever the search and the filter: the notebook is what was found.
 */
export interface BookSection {
  key: string;
  book: Note;
  count: number;
  draw: 'cards' | 'rows';
  notes: Note[];
  more: number;
}

export type HomeSection = WordsSection | BookSection;

/** The page in one layout: its sections in order, and how many notes were left for All notes (`cut`). */
export interface HomePlan {
  sections: HomeSection[];
  cut: number;
}

export interface PlanWays {
  /** A notebook's pages, in its order (book/book.ts `chaptersOf`, looked up by title). */
  pagesOf: (book: Note) => Note[];
  /** The notebook a note is a page of, or null (book/book.ts `placeOf`): which heading the notes left over go under. */
  placeOf: (note: Note) => BookPlace | null;
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
 * A notebook's pages as the page draws them: each once, however often its index names it, in the notebook's order -
 * but a journal's newest first, by when each entry was written, as its own screen and its card order them
 * (book/journalMonths.ts). Its index is in the order the entries were added, so its first six were its oldest.
 */
function pagesIn(book: Note, ways: PlanWays): Note[] {
  const seen = new Set<string>();
  const pages = ways.pagesOf(book).filter((page) => !seen.has(page.id) && Boolean(seen.add(page.id)));
  if (!isJournalBody(book.body)) return pages;
  return pages
    .map((page, at) => ({ page, at, wall: stampOf(page.body, page.createdAt) }))
    .sort((a, b) => b.wall - a.wall || b.at - a.at)
    .map(({ page }) => page);
}

/**
 * What the page draws in a layout, as sections: the two single ways (Cards, Timeline), the mixes, and the other three.
 * Each card layout stops at `most` cards; what it left out is `cut`, which the foot counts on its way to All notes.
 */
export function homePlan(layout: HomeLayout, lists: HomeLists, ways: PlanWays): HomePlan {
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
    case 'cards':
    case 'shelf': {
      notebooks(layout === 'cards' ? 'cards' : 'covers');
      add({ key: 'notes', heading: 'Notes', mark: 'note', count: notes.length, draw: layout === 'cards' ? 'cards' : 'dense', notes: notes.slice(0, most) });
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
    case 'card-timeline': {
      // Each span says how many it holds, and draws what is left of the cards when its turn comes.
      let budget = most;
      for (const section of byWhen(timeline(lists, now), 'cards')) {
        const drawn = section.notes.slice(0, budget);
        budget -= drawn.length;
        cut += section.notes.length - drawn.length;
        add({ ...section, notes: drawn });
      }
      break;
    }
    case 'spotlight': {
      const lit = spotlight(lists, Math.min(SPOTLIT, most), now);
      add({ key: 'recent', heading: 'Recent', mark: 'recent', count: null, draw: 'cards', notes: lit.lead });
      sections.push(...byWhen(lit.rest, 'rows'));
      break;
    }
    case 'shelf-timeline': {
      notebooks('covers');
      sections.push(...byWhen(spans(notes, now), 'rows'));
      break;
    }
    case 'library':
    case 'notebook-cards': {
      const cards = layout === 'notebook-cards';
      // The card budget is spent notebook by notebook, a few pages each, and what is left goes to the loose notes.
      let budget = most;
      // A note is loose unless it is a page of a notebook drawn here. A page whose notebook the search or the filter
      // left out is loose too, so a search that finds only a page draws that page (§148).
      const paged = new Set<string>();
      for (const book of books) {
        const pages = pagesIn(book, ways);
        for (const page of pages) paged.add(page.id);
        const drawn = cards ? pages.slice(0, Math.min(PAGES_CARDED, budget)) : pages;
        budget -= cards ? drawn.length : 0;
        sections.push({ key: `book-${book.id}`, book, count: pages.length, draw: cards ? 'cards' : 'rows', notes: drawn, more: pages.length - drawn.length });
      }
      const rest = notes.filter((n) => !paged.has(n.id));
      const shown = cards ? rest.slice(0, budget) : rest;
      // In no notebook, unless some are pages of a notebook the search or the filter left out: then they are the others.
      const heading = !books.length ? 'Notes' : rest.some((n) => ways.placeOf(n)) ? 'Other notes' : 'In no notebook';
      add({ key: 'loose', heading, mark: 'note', count: rest.length, draw: cards ? 'cards' : 'rows', notes: shown });
      cut = rest.length - shown.length;
      break;
    }
  }
  return { sections, cut };
}

/** Whether a section is a notebook's own. */
export const isBookSection = (section: HomeSection): section is BookSection => 'book' in section;

/** Every note a plan draws as a card, in the page's order: the ones a line under the title is written for first. */
export const cardsIn = (plan: HomePlan): Note[] => plan.sections.flatMap((section) => (section.draw === 'cards' || section.draw === 'dense' ? section.notes : []));
