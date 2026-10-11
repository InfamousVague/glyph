import { dateOfDay, isoDayAfter } from '../days.ts';
import type { Row } from './run.ts';

/**
 * A query shown as a calendar (`show: calendar`, docs/QUERIES.md): a month of weeks, each day with the records it
 * holds, which is the day core/query/run.ts gives each row (its due day, else its scheduled day, its start, or its
 * note's `date:`). Weeks start on Monday, as a week does everywhere else in the app (core/dayWords.ts `nextWeek`), and
 * the days of the weeks either side of the month are there to fill the rows, marked as not in it. Pure, so the
 * drawing (editor/QueryView.tsx) only draws.
 */

export interface CalendarDay {
  /** The day, YYYY-MM-DD. */
  day: string;
  /** The day of the month, 1 to 31, as it is printed. */
  date: number;
  /** In the month being shown, or a day of the weeks either side that fills a row. */
  inMonth: boolean;
  today: boolean;
  rows: Row[];
}

/** A month as `YYYY-MM`. */
export function monthOf(day: string): string {
  return day.slice(0, 7);
}

/** The month `count` months after `month` (before, for a negative count). */
export function monthAfter(month: string, count: number): string {
  const [year, number] = month.split('-').map(Number) as [number, number];
  const at = year * 12 + (number - 1) + count;
  return `${String(Math.floor(at / 12)).padStart(4, '0')}-${String((at % 12) + 1).padStart(2, '0')}`;
}

/** The month a calendar opens on: today's, unless nothing is on it and something is on a later or an earlier one. */
export function openingMonth(rows: readonly Row[], today: string): string {
  const days = rows.map((row) => row.day).filter((day): day is string => day !== null);
  const here = monthOf(today);
  if (!days.length || days.some((day) => monthOf(day) === here)) return here;
  const later = days.filter((day) => day > today).sort();
  return monthOf(later[0] ?? days.sort().at(-1)!);
}

/** `month`'s weeks, Monday first, each day with the rows on it in the order they came. */
export function monthWeeks(month: string, rows: readonly Row[], today: string): CalendarDay[][] {
  const first = `${month}-01`;
  const start = dateOfDay(first);
  if (!start) return [];
  // Monday is 0: back to the Monday of the week the 1st is in.
  const lead = (start.getDay() + 6) % 7;
  const byDay = new Map<string, Row[]>();
  for (const row of rows) {
    if (!row.day) continue;
    const list = byDay.get(row.day) ?? [];
    list.push(row);
    byDay.set(row.day, list);
  }
  const weeks: CalendarDay[][] = [];
  let day = isoDayAfter(first, -lead)!;
  do {
    const week: CalendarDay[] = [];
    for (let i = 0; i < 7; i += 1) {
      week.push({ day, date: Number(day.slice(8)), inMonth: monthOf(day) === month, today: day === today, rows: byDay.get(day) ?? [] });
      day = isoDayAfter(day, 1)!;
    }
    weeks.push(week);
  } while (monthOf(day) === month);
  return weeks;
}

/** How many of `rows` fall in `month`. */
export function inMonth(rows: readonly Row[], month: string): number {
  return rows.filter((row) => row.day !== null && monthOf(row.day) === month).length;
}

/** The month's name as a heading says it, in the device's language: "October 2026". */
export function monthName(month: string, locale?: string): string {
  const at = dateOfDay(`${month}-01`);
  return at ? new Intl.DateTimeFormat(locale, { month: 'long', year: 'numeric' }).format(at) : month;
}
