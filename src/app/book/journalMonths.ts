import { frontMatterEnd } from '../core/frontMatter.ts';
import { geoTagOf, tagLabel } from '../core/geotag.ts';
import { noteTitle } from '../core/noteTitle.ts';
import type { Note } from '../core/store.ts';
import { titleKey } from '../core/titleKey.ts';
import { chaptersOf, isJournalBody, type BookPlace } from './book.ts';
import { isEntryTitle, stampOf, templateOf } from './journal.ts';

/**
 * A journal's entries as its view draws them (book/JournalView.tsx; docs/DESIGN.md §142): newest first, in runs by the
 * month each was written in, every row what a person scans for - the day, the time, where, and how it starts.
 *
 * Ordered by when each entry was written (journal.ts `stampOf`: its `date:`, else when the note was made), never by
 * the index's order, so a notebook kept as a journal, an index edited by hand and one two devices merged (the lines in
 * either order) all draw each month once, newest first. Two written in the same minute are told apart by the index:
 * the later line is the newer.
 *
 * A line with no note is one of two things. An entry's name with no note is not drawn: an entry taken back that a sync
 * brought the line of back, or one in the Trash, which comes back with its note. Any other name is a page planned
 * before the notebook was kept as a journal, still to be written, listed apart.
 */

/** A line of the journal's index, and the note it names, if there is one. */
export interface JournalPage {
  title: string;
  /** The line it is on in the index. */
  line: number;
  note: Note | null;
}

export interface EntryRow {
  title: string;
  id: string;
  /** When it was written, as its wall clock (journal.ts `stampOf`). */
  wall: number;
  /** "28" and "Mon". */
  day: string;
  weekday: string;
  /** "14:05". */
  time: string;
  /** Where it was written, by name or by coordinates; null when it says nowhere. */
  place: string | null;
  /** The first line of its own words, plain; empty when it has none yet. */
  first: string;
  /** The row said whole: "Monday 28 September, 14:05, Trafalgar Square. Walked along the river." */
  label: string;
}

export interface JournalMonth {
  /** "2026-09". */
  key: string;
  /** "September 2026". */
  label: string;
  entries: EntryRow[];
}

/**
 * The ways a row writes a wall clock, in the device's language, each read as the clock it is rather than as a moment in
 * this zone. Made once for a journal's rows, not once a row: a year of entries is a year of rows.
 */
function wallFormats() {
  const make = (options: Intl.DateTimeFormatOptions) => {
    const format = new Intl.DateTimeFormat(undefined, { ...options, timeZone: 'UTC' });
    return (wall: number) => format.format(wall);
  };
  return {
    day: make({ day: 'numeric' }),
    weekday: make({ weekday: 'short' }),
    time: make({ hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }),
    long: make({ weekday: 'long', month: 'long', day: 'numeric' }),
    month: make({ month: 'long', year: 'numeric' }),
  };
}

/** A line of a template, as the lines it fills can be recognised: its placeholders stand for anything. */
function templateLine(line: string): RegExp {
  const pattern = line
    .trim()
    .split(/\{\{[^{}]*\}\}/)
    .map((piece) => piece.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))
    .join('.*?');
  return new RegExp(`^${pattern}$`);
}

/** A time the template put at the start of a line, bold or not: "**14:05** ". */
const LEADING_TIME = /^(?:\*\*|__)?\d{1,2}[:.]\d{2}(?:\*\*|__)?\s*/;

/**
 * The first line of an entry's own words, as plain text: past its front matter, its headings, a line that is only the
 * template's (its question, its empty to-do) and a time the template led a line with; a list's or a quote's mark, and
 * bold, taken off.
 */
export function firstWords(body: string, template = ''): string {
  const own = template
    .split('\n')
    .filter((line) => line.trim())
    .map(templateLine);
  const lines = body.split('\n');
  for (const raw of lines.slice(frontMatterEnd(lines))) {
    const line = raw.trim();
    if (!line || /^#{1,6}\s/.test(line) || /^!\[[^\]]*\]\([^)]*\)$/.test(line) || own.some((pattern) => pattern.test(line))) continue;
    const words = line
      .replace(/^(?:>\s*)+/, '')
      .replace(/^(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?/, '')
      .replace(LEADING_TIME, '')
      .replace(/\*\*|__/g, '')
      .trim();
    if (words) return words;
  }
  return '';
}

/** A written entry, and when it was written. */
type Written = JournalPage & { note: Note; wall: number };

/** One entry's row. */
function rowOf(page: Written, template: string, formats: ReturnType<typeof wallFormats>): EntryRow {
  const { wall } = page;
  const tag = geoTagOf(page.note.body);
  const place = tag ? tagLabel(tag) : null;
  const first = firstWords(page.note.body, template);
  const time = formats.time(wall);
  const label = `${[formats.long(wall), time, place].filter(Boolean).join(', ')}.${first ? ` ${first}` : ''}`;
  return { title: page.title, id: page.note.id, wall, day: formats.day(wall), weekday: formats.weekday(wall), time, place, first, label };
}

/**
 * The written entries, newest first, and the names planned with no note yet, in the index's order: only the order,
 * with nothing written out, for the bar and the cards, which draw no rows.
 */
function written(pages: readonly JournalPage[]): { rows: Written[]; unwritten: string[] } {
  const rows: Written[] = [];
  const unwritten: string[] = [];
  for (const page of pages) {
    if (page.note) rows.push({ ...page, note: page.note, wall: stampOf(page.note.body, page.note.createdAt) });
    else if (!isEntryTitle(page.title)) unwritten.push(page.title);
  }
  rows.sort((a, b) => b.wall - a.wall || b.line - a.line);
  return { rows, unwritten };
}

/** A journal's lines with their notes, found by title as a link finds one. */
export function pagesOf(body: string, noteOf: (title: string) => Note | undefined): JournalPage[] {
  return chaptersOf(body).map((chapter) => ({ title: chapter.title, line: chapter.line, note: noteOf(chapter.title) ?? null }));
}

/**
 * The journal's written entries in months, newest first, and the names planned in it with no note yet, in the index's
 * order. `template` is the journal's, so a row's first line is the entry's own words and not the template's.
 */
export function monthsOf(pages: readonly JournalPage[], template = ''): { months: JournalMonth[]; unwritten: string[] } {
  const { rows, unwritten } = written(pages);
  const formats = wallFormats();
  const months: JournalMonth[] = [];
  for (const page of rows) {
    const row = rowOf(page, template, formats);
    const at = new Date(row.wall);
    const key = `${at.getUTCFullYear()}-${String(at.getUTCMonth() + 1).padStart(2, '0')}`;
    const last = months[months.length - 1];
    if (last?.key === key) last.entries.push(row);
    else months.push({ key, label: formats.month(row.wall), entries: [row] });
  }
  return { months, unwritten };
}

/**
 * A page's place in its journal as the bar and the foot walk it (book/BookNav.tsx): the written entries oldest first,
 * so Previous is the entry written before this one and the newest is "212 of 212", then any page planned and not yet
 * written. A notebook's place is answered as it is.
 */
export function inTimeOrder(place: BookPlace, noteOf: (title: string) => Note | undefined): BookPlace {
  if (!place.journal) return place;
  const { rows, unwritten } = written(pagesOf(place.book.body, noteOf));
  const order = [...rows.reverse().map((row) => row.title), ...unwritten];
  const chapters = order.map((title) => place.chapters.find((chapter) => chapter.title === title)!).filter(Boolean);
  const current = place.chapters[place.at]?.title;
  return { ...place, chapters, at: current === undefined ? -1 : chapters.findIndex((chapter) => chapter.title === current) };
}

/** Every note by its title's key, the first of two that share one, as a link finds it. */
function byTitle(notes: readonly Note[]): (title: string) => Note | undefined {
  const map = new Map<string, Note>();
  for (const note of notes) {
    const key = titleKey(noteTitle(note.body));
    if (key && !map.has(key)) map.set(key, note);
  }
  return (title) => map.get(titleKey(title));
}

/** What a journal's card says (notes/NoteCard.tsx): how many entries, and the newest few by when each was written. */
export interface JournalCard {
  count: number;
  newest: string[];
}

/** Every journal's card among `notes`, by the journal's id: none where there is no journal. */
export function journalCards(notes: readonly Note[], newest = 4): Map<string, JournalCard> {
  const cards = new Map<string, JournalCard>();
  const journals = notes.filter((note) => isJournalBody(note.body));
  if (!journals.length) return cards;
  const noteOf = byTitle(notes);
  for (const journal of journals) {
    const { rows, unwritten } = written(pagesOf(journal.body, noteOf));
    cards.set(journal.id, { count: rows.length + unwritten.length, newest: [...rows.map((row) => row.title), ...unwritten].slice(0, newest) });
  }
  return cards;
}

/**
 * The one month the aside lists for a journal or one of its entries (aside/Aside.tsx): the entry's own month, newest
 * first, or the journal's newest month. Null for a journal with nothing written.
 */
export function asideMonth(journal: Note, notes: readonly Note[], openTitle: string | null): JournalMonth | null {
  const { months } = monthsOf(pagesOf(journal.body, byTitle(notes)), templateOf(journal.body));
  if (!months.length) return null;
  const key = openTitle === null ? null : titleKey(openTitle);
  return months.find((month) => month.entries.some((entry) => titleKey(entry.title) === key)) ?? months[0]!;
}
