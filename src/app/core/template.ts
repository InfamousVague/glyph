import type { Placing } from '../capture/place.ts';
import { lineWords, listLead } from './itemSyntax.ts';
import { clockTime, longDay } from './stamp.ts';

/**
 * A template filled for one note: a journal's for one entry (book/journal.ts; docs/DESIGN.md §142), and a new note's
 * from one of the six it can start from (notes/noteTemplates.ts; §144). Here in core/ and not in book/ since notes use
 * it as much as journals now. The double-brace placeholders are the ones Obsidian's core Templates plugin writes:
 *
 *   {{date}}      Monday 28 September         the home page's day, no year (core/stamp.ts `longDay`)
 *   {{time}}      14:05                       a 24-hour clock in every language (core/stamp.ts `clockTime`)
 *   {{weekday}}   Monday
 *   {{title}}     2026-09-28 14.05            the entry's name; empty for a new note, which has none yet
 *   {{journal}}   Diary                       the journal's name
 *   {{date:FORMAT}} and {{time:FORMAT}}       Moment's tokens, as Obsidian takes them, and the ISO week (below)
 *
 * Anything else is left as it was typed. A name is looked up among these by its own names only: format/prompt.ts's
 * lookup used `in`, so `{{constructor}}` or `{{toString}}` there would print a function's source.
 *
 * Words inside a format go in square brackets, as Moment and Obsidian both want them: every token letter outside
 * brackets is read, so `{{date:D MMMM at HH:mm}}` turns "at" into a meridiem and a letter ("pmt"). That rule stays
 * Moment's, and the sheet and the Guide say so in a line. Names follow the device's language, so `MMM` in en-GB is
 * "Sept", and Obsidian's `{{date}}`, which is `YYYY-MM-DD` there, is the long day here; `{{date:YYYY-MM-DD}}` is the
 * same in both.
 *
 * The week is ISO's, `GGGG` its year and `WW` its number (`{{date:GGGG-[W]WW}}` is `2026-W40`), the same everywhere.
 * Moment's own week, `gggg` and `ww`, starts on the locale's first day, a Sunday in en-US, and is not read: it stays as
 * it was typed, so Obsidian's weekly default `gggg-[W]ww` prints as it is, and `GGGG-[W]WW` is the form both read alike.
 *
 * And where a spoken entry's words go (`openEnd`), which is the template's last line: a line left open goes on, an
 * empty to-do starts the to-do list. And where a new note's caret goes (`firstOpenAt`), the first line left open. Pure:
 * the MCP server fills a template as the app does.
 */

/** A placeholder: its name, and a format after a colon for the two that take one. */
const PLACEHOLDER = /\{\{\s*([A-Za-z_$][\w$]*)(?::([^{}]*))?\s*\}\}/g;

/** What an entry's template is filled for: the moment, the entry's name and the journal's. */
export interface FillFor {
  at: Date;
  title?: string;
  journal?: string;
  /**
   * `{{date}}`, `{{time}}` and `{{weekday}}` already written for `at`, by a caller that fills a year of entries with
   * one set of formatters (book/journalMonths.ts). Absent, written here.
   */
  said?: { date: string; time: string; weekday: string };
}

/** The template with its placeholders filled for one entry. */
export function fillTemplate(text: string, { at, title = '', journal = '', said }: FillFor): string {
  const values: Record<string, string> = { ...(said ?? { date: longDay(at), time: clockTime(at), weekday: named(at, { weekday: 'long' }) }), title, journal };
  return text.replace(PLACEHOLDER, (whole, name: string, format: string | undefined) => {
    if (format !== undefined && format.trim()) return name === 'date' || name === 'time' ? formatStamp(at, format.trim()) : whole;
    return Object.hasOwn(values, name) ? values[name]! : whole;
  });
}

/** One part of a date in the device's language: a month's or a weekday's name, a meridiem. */
function named(at: Date, options: Intl.DateTimeFormatOptions): string {
  return new Intl.DateTimeFormat(undefined, options).format(at);
}

/** Two figures. */
const two = (n: number) => String(n).padStart(2, '0');

/** "1st", "22nd", "11th" in English; the number and a full stop, as German and the Nordic languages write it, elsewhere. */
function ordinal(n: number): string {
  const language = new Intl.DateTimeFormat().resolvedOptions().locale.split('-')[0];
  if (language !== 'en') return `${n}.`;
  const tens = n % 100;
  const suffix = tens >= 11 && tens <= 13 ? 'th' : (['th', 'st', 'nd', 'rd'][n % 10] ?? 'th');
  return `${n}${suffix}`;
}

/** The meridiem as the device's language says it on a 12-hour clock: "PM" in English. */
function meridiem(at: Date): string {
  const part = new Intl.DateTimeFormat(undefined, { hour: 'numeric', hour12: true }).formatToParts(at).find((each) => each.type === 'dayPeriod');
  return part?.value ?? (at.getHours() < 12 ? 'AM' : 'PM');
}

/**
 * The ISO week `at` falls in: its year and its number. A week is Monday to Sunday and belongs to the year its Thursday
 * is in, so 1 January 2021, a Friday, is in 2020's week 53, and 30 December 2024 is in 2025's week 1.
 */
function isoWeek(at: Date): { year: number; week: number } {
  const thursday = new Date(at.getFullYear(), at.getMonth(), at.getDate() + 3 - ((at.getDay() + 6) % 7));
  const first = new Date(thursday.getFullYear(), 0, 4);
  const firstThursday = new Date(first.getFullYear(), 0, 4 + 3 - ((first.getDay() + 6) % 7));
  // Whole days apart, by the calendar and not the clock, so a change to summer time in between counts for nothing.
  const days = Math.round((Date.UTC(thursday.getFullYear(), thursday.getMonth(), thursday.getDate()) - Date.UTC(firstThursday.getFullYear(), firstThursday.getMonth(), firstThursday.getDate())) / 86_400_000);
  return { year: thursday.getFullYear(), week: 1 + days / 7 };
}

const TOKENS: Record<string, (at: Date) => string> = {
  GGGG: (at) => String(isoWeek(at).year).padStart(4, '0'),
  WW: (at) => two(isoWeek(at).week),
  W: (at) => String(isoWeek(at).week),
  YYYY: (at) => String(at.getFullYear()).padStart(4, '0'),
  YY: (at) => two(at.getFullYear() % 100),
  MMMM: (at) => named(at, { month: 'long' }),
  MMM: (at) => named(at, { month: 'short' }),
  MM: (at) => two(at.getMonth() + 1),
  M: (at) => String(at.getMonth() + 1),
  Do: (at) => ordinal(at.getDate()),
  DD: (at) => two(at.getDate()),
  D: (at) => String(at.getDate()),
  dddd: (at) => named(at, { weekday: 'long' }),
  ddd: (at) => named(at, { weekday: 'short' }),
  HH: (at) => two(at.getHours()),
  H: (at) => String(at.getHours()),
  hh: (at) => two(at.getHours() % 12 || 12),
  h: (at) => String(at.getHours() % 12 || 12),
  mm: (at) => two(at.getMinutes()),
  // Moment's A is upper case and its a lower case; a language with a meridiem of its own keeps its own.
  A: (at) => {
    const said = meridiem(at);
    return /^[ap]\.?m\.?$/i.test(said) ? said.toUpperCase() : said;
  },
  a: (at) => meridiem(at).toLowerCase(),
};

/** Words in square brackets, or a token: the longest first at each place, as Moment reads them. */
const TOKEN = /\[([^\]]*)\]|GGGG|WW|W|YYYY|YY|MMMM|MMM|MM|M|Do|DD|D|dddd|ddd|HH|H|hh|h|mm|A|a/g;

/** `at` written in Moment's tokens (`YYYY-MM-DD`, `dddd [at] HH:mm`), words in square brackets kept as they are. */
export function formatStamp(at: Date, format: string): string {
  return format.replace(TOKEN, (token, words: string | undefined) => (words !== undefined ? words : TOKENS[token]!(at)));
}

/**
 * Where a spoken entry's words go (capture/place.ts), and the entry as it is written before they come, from the
 * filled template's last line:
 *
 * - an empty list item (`- [ ] `, `- `, `1. `): the entry without it, and the words as that list's items, so a day's
 *   to-dos said aloud are to-dos;
 * - words left open with a space (`**14:05** `): the entry without the line, and the words going on from it, so a
 *   spoken entry still starts with its time;
 * - anything else: the entry as it is, and the words at its end.
 */
export function openEnd(words: string): { base: string; placing: Placing } {
  const lines = words.split('\n');
  const last = lines[lines.length - 1] ?? '';
  const rest = lines.slice(0, -1).join('\n');
  const lead = listLead(last);
  if (lead && !last.slice(lead.wordsAt).trim()) {
    const task = lead.done !== null;
    const fresh = task ? 'task' : /\d/.test(lead.marker) ? 'number' : 'bullet';
    return { base: rest, placing: { kind: 'lists', task, heading: null, fresh } };
  }
  if (last.trim() && /\s$/.test(last)) return { base: rest, placing: { kind: 'end', lead: last } };
  return { base: words, placing: { kind: 'end' } };
}

/**
 * Where a new note's caret goes in its filled words: the end of the first line left open, or the end of the words. A
 * line is open when it is a heading with no words (`# `), a list's, a to-do's or a quote's lead with no words (`- `,
 * `- [ ] `, `1. `, `> `), or words ending in a space (`With `), which is `openEnd`'s own rule for a line left open. A
 * blank line is not open. So A day's caret is in its to-do, A meeting's after "With ", and the rest in their heading.
 */
export function firstOpenAt(words: string): number {
  let at = 0;
  for (const line of words.split('\n')) {
    const heading = /^ {0,3}#{1,6} +$/.test(line);
    // A lead with nothing after it: `- `, `- [ ] `, `1. `, `> `.
    const lead = line.trim() !== '' && !lineWords(line);
    const leftOpen = line.trim() !== '' && /\s$/.test(line);
    if (heading || lead || leftOpen) return at + line.length;
    at += line.length + 1;
  }
  return words.length;
}
