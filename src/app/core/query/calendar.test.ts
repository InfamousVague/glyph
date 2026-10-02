import { describe, expect, it } from 'vitest';
import { inMonth, monthAfter, monthName, monthOf, monthWeeks, openingMonth } from './calendar.ts';
import type { Row } from './run.ts';

/* A query's records laid out as a month (core/query/calendar.ts). */

const row = (name: string, day: string | null): Row => ({
  key: name,
  kind: 'task',
  noteId: 'n',
  line: 0,
  source: '',
  anchor: null,
  name,
  id: null,
  done: false,
  category: 'todo',
  workflow: [],
  cells: [],
  day,
  start: null,
  due: day,
  overdue: false,
});

describe('months', () => {
  it('counts on and back across years', () => {
    expect(monthOf('2026-10-05')).toBe('2026-10');
    expect(monthAfter('2026-10', 1)).toBe('2026-11');
    expect(monthAfter('2026-12', 1)).toBe('2027-01');
    expect(monthAfter('2026-01', -1)).toBe('2025-12');
    expect(monthAfter('2026-10', -22)).toBe('2024-12');
  });

  it('names a month in the language asked', () => {
    expect(monthName('2026-10', 'en-GB')).toBe('October 2026');
  });

  it('opens on today’s month, unless everything is in another', () => {
    expect(openingMonth([row('a', '2026-10-09')], '2026-10-05')).toBe('2026-10');
    expect(openingMonth([], '2026-10-05')).toBe('2026-10');
    expect(openingMonth([row('a', '2026-12-01'), row('b', '2026-11-20'), row('c', '2026-02-01')], '2026-10-05')).toBe('2026-11');
    expect(openingMonth([row('a', '2026-02-01'), row('b', '2026-03-01')], '2026-10-05')).toBe('2026-03');
  });
});

describe('a month of weeks', () => {
  it('starts on the Monday of the week the 1st is in, and ends with the week the last day is in', () => {
    // 1 October 2026 is a Thursday.
    const weeks = monthWeeks('2026-10', [], '2026-10-05');
    expect(weeks).toHaveLength(5);
    expect(weeks[0]!.map((day) => day.day)).toEqual(['2026-09-28', '2026-09-29', '2026-09-30', '2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04']);
    expect(weeks[0]!.map((day) => day.inMonth)).toEqual([false, false, false, true, true, true, true]);
    expect(weeks.at(-1)!.at(-1)!.day).toBe('2026-11-01');
    expect(weeks.flat().filter((day) => day.today).map((day) => day.day)).toEqual(['2026-10-05']);
  });

  it('is four weeks for a February that starts on a Monday', () => {
    expect(monthWeeks('2027-02', [], '2027-02-01')).toHaveLength(4);
  });

  it('puts each row on its day, and none that has no day', () => {
    const weeks = monthWeeks('2026-10', [row('Milk', '2026-10-04'), row('Bread', '2026-10-04'), row('Undated', null), row('Late', '2026-11-01')], '2026-10-05');
    const on = (day: string) => weeks.flat().find((each) => each.day === day)!.rows.map((each) => each.name);
    expect(on('2026-10-04')).toEqual(['Milk', 'Bread']);
    expect(on('2026-11-01')).toEqual(['Late']);
    expect(inMonth([row('Milk', '2026-10-04'), row('Late', '2026-11-01'), row('Undated', null)], '2026-10')).toBe(1);
  });
});
