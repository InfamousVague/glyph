import { frontMatterEnd } from '../core/frontMatter.ts';
import { geoTagOf, tagLabel } from '../core/geotag.ts';
import type { Note } from '../core/store.ts';
import { isEntryTitle, stampOf } from './journal.ts';

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

/** A wall clock written in the device's language, read as the clock it is rather than as a moment in this zone. */
function wallText(wall: number, options: Intl.DateTimeFormatOptions): string {
  return new Intl.DateTimeFormat(undefined, { ...options, timeZone: 'UTC' }).format(wall);
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

/** One entry's row. */
function rowOf(page: JournalPage & { note: Note }, template: string): EntryRow {
  const wall = stampOf(page.note.body, page.note.createdAt);
  const tag = geoTagOf(page.note.body);
  const place = tag ? tagLabel(tag) : null;
  const first = firstWords(page.note.body, template);
  const day = wallText(wall, { day: 'numeric' });
  const weekday = wallText(wall, { weekday: 'short' });
  const time = wallText(wall, { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });
  const long = wallText(wall, { weekday: 'long', month: 'long', day: 'numeric' });
  const label = `${[long, time, place].filter(Boolean).join(', ')}.${first ? ` ${first}` : ''}`;
  return { title: page.title, id: page.note.id, wall, day, weekday, time, place, first, label };
}

/**
 * The journal's written entries in months, newest first, and the names planned in it with no note yet, in the index's
 * order. `template` is the journal's, so a row's first line is the entry's own words and not the template's.
 */
export function monthsOf(pages: readonly JournalPage[], template = ''): { months: JournalMonth[]; unwritten: string[] } {
  const rows: (EntryRow & { line: number })[] = [];
  const unwritten: string[] = [];
  for (const page of pages) {
    if (page.note) rows.push({ ...rowOf({ ...page, note: page.note }, template), line: page.line });
    else if (!isEntryTitle(page.title)) unwritten.push(page.title);
  }
  rows.sort((a, b) => b.wall - a.wall || b.line - a.line);
  const months: JournalMonth[] = [];
  for (const { line: _line, ...row } of rows) {
    const at = new Date(row.wall);
    const key = `${at.getUTCFullYear()}-${String(at.getUTCMonth() + 1).padStart(2, '0')}`;
    const last = months[months.length - 1];
    if (last?.key === key) last.entries.push(row);
    else months.push({ key, label: wallText(row.wall, { month: 'long', year: 'numeric' }), entries: [row] });
  }
  return { months, unwritten };
}
