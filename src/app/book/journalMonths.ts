import { frontMatterEnd } from '../core/frontMatter.ts';
import { geoTagOf, tagLabel } from '../core/geotag.ts';
import { lineWords } from '../core/itemSyntax.ts';
import { noteTitle } from '../core/noteTitle.ts';
import { placeOfLine } from '../core/placeRefs.ts';
import type { Note } from '../core/store.ts';
import { titleKey } from '../core/titleKey.ts';
import { videoOfLine } from '../core/videoRefs.ts';
import { chaptersOf, isJournalBody, type BookPlace } from './book.ts';
import { isEntryTitle, stampOf, templateOf } from './journal.ts';
import { fillTemplate } from '../core/template.ts';

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
    weekdayLong: make({ weekday: 'long' }),
    time: make({ hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }),
    long: make({ weekday: 'long', month: 'long', day: 'numeric' }),
    month: make({ month: 'long', year: 'numeric' }),
    when: make({ weekday: 'short', day: 'numeric', month: 'short' }),
  };
}

/** A wall clock (journal.ts `stampOf`: its UTC fields are the clock) as the moment here that reads the same. */
function localOf(wall: number): Date {
  const at = new Date(wall);
  return new Date(at.getUTCFullYear(), at.getUTCMonth(), at.getUTCDate(), at.getUTCHours(), at.getUTCMinutes());
}

/**
 * The template as it was filled for an entry: its words, which are not the entry's own. With the rows' formatters, so
 * a year of entries fills a year of templates without a formatter made for each (`{{date}}` and `{{time}}` are these
 * formats, core/stamp.ts); only a format of your own, `{{date:dddd}}`, makes its own.
 */
function templateFor(template: string, journal: string, formats: ReturnType<typeof wallFormats>): (page: Written) => string {
  if (!template.includes('{{')) return () => template;
  return ({ wall, title }) =>
    fillTemplate(template, { at: localOf(wall), title, journal, said: { date: formats.long(wall), time: formats.time(wall), weekday: formats.weekdayLong(wall) } });
}

/** A time the template put at the start of a line, bold or not: "**14:05** ". */
const LEADING_TIME = /^(?:\*\*|__)?\d{1,2}[:.]\d{2}(?:\*\*|__)?\s*/;

/** A heading, `## ` with no words yet as well. */
const HEADING = /^#{1,6}(?:\s|$)/;
/** What opens or closes fenced code: its run of backticks or tildes. */
const FENCE = /^(`{3,}|~{3,})/;
/** A picture alone, or a canvas or a note drawn in a frame: `![](image/a.jpg)`, `![[Plan]]`. */
const PICTURE = /^!(?:\[[^\]]*\]\([^)]*\)|\[\[[^\]]*\]\])$/;
/** A table's row, in a quote or not. */
const TABLE_ROW = /^\s*(?:>\s*)*\|/;
/** A rule: three or more dashes, stars or underscores, spaced or not. */
const RULE = /^(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$/;
/** A callout's kind, `[!NOTE]`, and its fold sign, before its title. */
const CALLOUT = /^\[![A-Za-z][\w-]*\][+-]?\s*/;
/** A sum's lead, `= ` (editor/sums.ts). */
const SUM = /^=(?:\s+|$)/;
/** A footnote's line, `[^1]: `, and its marker in words. */
const FOOTNOTE_LINE = /^\[\^[^\]\s]+\]:\s*/;
const FOOTNOTE_REF = /\[\^[^\]\s]+\]/g;
/** A link to a note, `[[Title]]` or `[[Title|words]]`: its words. */
const NOTE_LINK = /\[\[([^\]|]*)(?:\|([^\]]*))?\]\]/g;
/** A link inside the words, a place's among them: its words, and not where it goes. */
const LINK = /(?<!!)\[((?:[^[\]]|\[[^\]]*\])*)\]\([^)]*\)/g;
/** A picture inside the words, a film's poster among them: not words. */
const INLINE_PICTURE = /!\[[^\]]*\]\([^)]*\)/g;

/**
 * A line the + beside the line draws as something other than words (editor/AddList.tsx; docs/DESIGN.md §141): a
 * picture, a film, a place, a canvas's frame, a table's row, a rule. Its Markdown is not how an entry starts: the row
 * read `[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)` when a place was the first thing written. The row says where
 * the entry was written on its own, from its tag.
 */
function drawnLine(raw: string): boolean {
  const said = lineWords(raw);
  return PICTURE.test(said) || TABLE_ROW.test(raw) || RULE.test(raw.trim()) || placeOfLine(raw) !== null || videoOfLine(raw) !== null;
}

/**
 * The first line of an entry's own words, as plain text: past its front matter, its headings, what draws as something
 * other than words (a picture, a film, a place, a canvas's frame, a table, a rule, and fenced code, a chart or a
 * board, whole), and `filled`, the template as it was filled for this entry: a line that is only the template's (its
 * question, its empty to-do) is skipped, and a line the template left open for the words to go on ("**14:05** ")
 * comes off the front of the line that goes on from it. Its own lines as they were filled, never a pattern of them: a
 * template line that is only a placeholder, `{{date}}`, read as a pattern stood for every line there is, and the row
 * had no words. A time that leads a line comes off too, for an entry made before its journal's template changed. A
 * list's or a quote's lead, a callout's kind, a sum's `=`, a footnote's marker, a card's anchor and bold come off,
 * and a link is its words: whatever the + beside the line writes first, the row reads as words or not at all.
 */
export function firstWords(body: string, filled = ''): string {
  const template = filled.split('\n').filter((line) => line.trim());
  const only = new Set(template.map((line) => line.trim()));
  const open = template.filter((line) => /\s$/.test(line)).map((line) => line.trimStart());
  const lines = body.split('\n');
  let fence: string | null = null;
  for (const raw of lines.slice(frontMatterEnd(lines))) {
    const line = raw.trim();
    const mark = FENCE.exec(line)?.[1];
    if (fence) {
      if (mark && mark[0] === fence[0] && mark.length >= fence.length && !line.slice(mark.length).trim()) fence = null;
      continue;
    }
    if (mark) {
      fence = mark;
      continue;
    }
    if (!line || HEADING.test(line) || only.has(line) || drawnLine(raw)) continue;
    const from = raw.trimStart();
    const lead = open.find((each) => from.startsWith(each));
    // A space kept at the end, so an item's lead with nothing after it, `- `, is still a lead.
    const words = lineWords(`${(lead ? from.slice(lead.length) : from).trimEnd()} `)
      .replace(CALLOUT, '')
      .replace(SUM, '')
      .replace(FOOTNOTE_LINE, '')
      .replace(LEADING_TIME, '')
      .replace(FOOTNOTE_REF, '')
      .replace(NOTE_LINK, (_whole, title: string, said?: string) => said ?? title)
      .replace(LINK, (_whole, said: string) => said)
      .replace(INLINE_PICTURE, '')
      .replace(/\*\*|__/g, '')
      .trim();
    if (words) return words;
  }
  return '';
}

/** A written entry, and when it was written. */
type Written = JournalPage & { note: Note; wall: number };

/** One entry's row. */
function rowOf(page: Written, filled: string, formats: ReturnType<typeof wallFormats>): EntryRow {
  const { wall } = page;
  const tag = geoTagOf(page.note.body);
  const place = tag ? tagLabel(tag) : null;
  const first = firstWords(page.note.body, filled);
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
 * order. `template` and `journal` are the journal's, so a row's first line is the entry's own words and not the
 * template's as it was filled for that entry.
 */
export function monthsOf(pages: readonly JournalPage[], template = '', journal = ''): { months: JournalMonth[]; unwritten: string[] } {
  const { rows, unwritten } = written(pages);
  const formats = wallFormats();
  const fill = templateFor(template, journal, formats);
  const months: JournalMonth[] = [];
  for (const page of rows) {
    const row = rowOf(page, fill(page), formats);
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
 * so Previous is the entry written before this one and the newest is "212 of 212". A page planned and not yet written
 * is not an entry: in a notebook kept as a journal the first entry read "2 of 3", with Next a page nobody had written.
 * A notebook's place is answered as it is.
 */
export function inTimeOrder(place: BookPlace, noteOf: (title: string) => Note | undefined): BookPlace {
  if (!place.journal) return place;
  const { rows } = written(pagesOf(place.book.body, noteOf));
  const order = rows.reverse().map((row) => row.title);
  const chapters = order.map((title) => place.chapters.find((chapter) => chapter.title === title)!).filter(Boolean);
  const current = place.chapters[place.at]?.title;
  const at = current === undefined ? -1 : chapters.findIndex((chapter) => chapter.title === current);
  // Not among the written (a note by that name the index finds no line for): walked as the index has it.
  return at < 0 ? place : { ...place, chapters, at };
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

/**
 * What a journal's card says (notes/NoteCard.tsx): how many entries are written, and the newest few by when each was
 * written, each said as its day and time ("Mon 28 Sept, 13:05") rather than its file's name. A page planned and not
 * yet written is not an entry, and is not counted.
 */
export interface JournalCard {
  count: number;
  newest: { title: string; when: string }[];
}

/** Every journal's card among `notes`, by the journal's id: none where there is no journal. */
export function journalCards(notes: readonly Note[], newest = 4): Map<string, JournalCard> {
  const cards = new Map<string, JournalCard>();
  const journals = notes.filter((note) => isJournalBody(note.body));
  if (!journals.length) return cards;
  const noteOf = byTitle(notes);
  const formats = wallFormats();
  for (const journal of journals) {
    const { rows } = written(pagesOf(journal.body, noteOf));
    cards.set(journal.id, { count: rows.length, newest: rows.slice(0, newest).map((row) => ({ title: row.title, when: `${formats.when(row.wall)}, ${formats.time(row.wall)}` })) });
  }
  return cards;
}

/** An entry's name read back as the wall clock it names (journal.ts `entryTitle`), or null for a name that is not one. */
function wallOfName(title: string): number | null {
  if (!isEntryTitle(title)) return null;
  const [, year, month, day, hour, minute] = /^(\d{4})-(\d{2})-(\d{2}) (\d{2})\.(\d{2})/.exec(title.trim())!;
  return Date.UTC(Number(year), Number(month) - 1, Number(day), Number(hour), Number(minute));
}

const DAY_MS = 24 * 60 * 60_000;

/**
 * What an entry's bar calls the entry either side of `open` (book/BookNav.tsx): its time when it was written the day
 * the open one was, else its day, "27 Sept". At a phone's width a side has room for about nine letters, and a name cut
 * there, "2026-09-2…", kept only what every entry shares. A name that is not an entry's is said as it is.
 */
export function sideName(title: string, open: string): string {
  const wall = wallOfName(title);
  if (wall === null) return title;
  const here = wallOfName(open);
  const options: Intl.DateTimeFormatOptions =
    here !== null && Math.floor(here / DAY_MS) === Math.floor(wall / DAY_MS) ? { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' } : { day: 'numeric', month: 'short' };
  return new Intl.DateTimeFormat(undefined, { ...options, timeZone: 'UTC' }).format(wall);
}

/**
 * The one month the aside lists for a journal or one of its entries (aside/Aside.tsx): the entry's own month, newest
 * first, or the journal's newest month. Null for a journal with nothing written.
 */
export function asideMonth(journal: Note, notes: readonly Note[], openTitle: string | null): JournalMonth | null {
  const { months } = monthsOf(pagesOf(journal.body, byTitle(notes)), templateOf(journal.body), noteTitle(journal.body));
  if (!months.length) return null;
  const key = openTitle === null ? null : titleKey(openTitle);
  return months.find((month) => month.entries.some((entry) => titleKey(entry.title) === key)) ?? months[0]!;
}
