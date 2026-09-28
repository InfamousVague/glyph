import type { Placing } from '../capture/place.ts';
import { listLead } from '../core/itemSyntax.ts';
import { clockTime, longDay } from '../core/stamp.ts';

/**
 * A journal's template filled for one entry (book/journal.ts; docs/DESIGN.md §142), with the double-brace placeholders
 * Obsidian's core Templates plugin writes:
 *
 *   {{date}}      Monday 28 September         the home page's day, no year (core/stamp.ts `longDay`)
 *   {{time}}      14:05                       a 24-hour clock in every language (core/stamp.ts `clockTime`)
 *   {{weekday}}   Monday
 *   {{title}}     2026-09-28 14.05            the entry's name
 *   {{journal}}   Diary                       the journal's name
 *   {{date:FORMAT}} and {{time:FORMAT}}       Moment's tokens, as Obsidian takes them
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
 * And where a spoken entry's words go (`openEnd`), which is the template's last line: a line left open goes on, an
 * empty to-do starts the to-do list. Pure: the MCP server fills a template as the app does.
 */

/** A placeholder: its name, and a format after a colon for the two that take one. */
const PLACEHOLDER = /\{\{\s*([A-Za-z_$][\w$]*)(?::([^{}]*))?\s*\}\}/g;

/** What an entry's template is filled for: the moment, the entry's name and the journal's. */
export interface FillFor {
  at: Date;
  title?: string;
  journal?: string;
}

/** The template with its placeholders filled for one entry. */
export function fillTemplate(text: string, { at, title = '', journal = '' }: FillFor): string {
  const values: Record<string, string> = { date: longDay(at), time: clockTime(at), weekday: named(at, { weekday: 'long' }), title, journal };
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

const TOKENS: Record<string, (at: Date) => string> = {
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
const TOKEN = /\[([^\]]*)\]|YYYY|YY|MMMM|MMM|MM|M|Do|DD|D|dddd|ddd|HH|H|hh|h|mm|A|a/g;

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
    return { base: rest, placing: { kind: 'lists', task, heading: null, fresh: task ? 'task' : 'bullet' } };
  }
  if (last.trim() && /\s$/.test(last)) return { base: rest, placing: { kind: 'end', lead: last } };
  return { base: words, placing: { kind: 'end' } };
}
