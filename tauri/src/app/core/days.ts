/**
 * A day as a note writes one, ISO's `2026-10-03`: what a to-do's `📅 2026-10-03` holds (core/taskFields.ts), what a
 * ticket's `due:` says (core/properties.ts), and what a query sorts, compares and lays out on a calendar. The note
 * keeps the date as these ten characters and nothing else, so it reads the same in Obsidian, on GitHub and to a person,
 * and two of them compare as text: `'2026-10-03' < '2026-10-10'` is the earlier day.
 *
 * A day is the person's own day, by the device's clock and calendar, never the instant's day in UTC. `toISOString`
 * is the trap: at 23:30 in New York on 3 October it says the 4th, and a to-do written "due today" would be due
 * tomorrow. So a `Date` is read here by its local fields, and the arithmetic is done on the calendar (`Date.UTC` of the
 * day's parts, where no clock changes), so a week on from the Saturday the clocks go back is still the next Saturday.
 *
 * Here and not in core/template.ts, whose `{{date:YYYY-MM-DD}}` writes the same ten characters: the template engine
 * fills a ticket's template (docs/DESIGN.md §156), and the grammars it fills from need these, so a leaf with no imports
 * keeps that from going round in a circle, as core/titleKey.ts does for titles. Pure, so the MCP server can bundle it.
 */

const DAY_MS = 86_400_000;
/** A day as it is written: four figures, two and two. */
const ISO_DAY = /^(\d{4})-(\d{2})-(\d{2})$/;

const two = (n: number) => String(n).padStart(2, '0');
const written = (year: number, month: number, day: number) => `${String(year).padStart(4, '0')}-${two(month + 1)}-${two(day)}`;

/** "2026-10-03": the day `at` falls on by the device's clock and calendar. */
export function isoDay(at: Date): string {
  return written(at.getFullYear(), at.getMonth(), at.getDate());
}

/**
 * Where a written day is on the calendar, as a count of milliseconds from 1970 in UTC, which no clock change moves;
 * null for words that are not a day, or for a day the calendar has not got (`2026-02-30`).
 */
function calendarTime(iso: string): number | null {
  const found = ISO_DAY.exec(iso);
  if (!found) return null;
  const [year, month, day] = [Number(found[1]), Number(found[2]) - 1, Number(found[3])];
  const at = new Date(0);
  // setUTCFullYear and not Date.UTC, which reads a year under 100 as 19xx.
  at.setUTCFullYear(year, month, day);
  return at.getUTCFullYear() === year && at.getUTCMonth() === month && at.getUTCDate() === day ? at.getTime() : null;
}

/** Whether `text` is a day as a note writes one, and one the calendar has: `2026-10-03`, not `2026-02-30` or `3 Oct`. */
export function isIsoDay(text: string): boolean {
  return calendarTime(text) !== null;
}

/**
 * The day `days` after `day` (before it, for a negative count), by the calendar. From a `Date`, its day on the
 * device's clock; from a written day, null where it is not one.
 */
export function isoDayAfter(day: Date, days: number): string;
export function isoDayAfter(day: string, days: number): string | null;
export function isoDayAfter(day: Date | string, days: number): string | null {
  const from = typeof day === 'string' ? calendarTime(day) : calendarTime(isoDay(day));
  if (from === null) return null;
  const at = new Date(from + Math.trunc(days) * DAY_MS);
  return written(at.getUTCFullYear(), at.getUTCMonth(), at.getUTCDate());
}

/**
 * Whole days from one written day to another: 7 from a Saturday to the next, -1 back to the day before; null where
 * either is not a day.
 */
export function daysBetween(from: string, to: string): number | null {
  const start = calendarTime(from);
  const end = calendarTime(to);
  return start === null || end === null ? null : Math.round((end - start) / DAY_MS);
}

/**
 * A written day as a `Date` at noon on the device's clock, for `Intl` to name ("Saturday", "3 Oct") and for a calendar
 * to place: noon, so no clock change that day moves it into the next or the last. Null where it is not a day.
 */
export function dateOfDay(iso: string): Date | null {
  const at = calendarTime(iso);
  if (at === null) return null;
  const utc = new Date(at);
  const local = new Date(2000, 0, 1, 12);
  local.setFullYear(utc.getUTCFullYear(), utc.getUTCMonth(), utc.getUTCDate());
  return local;
}
