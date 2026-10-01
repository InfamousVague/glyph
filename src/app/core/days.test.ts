import { afterEach, describe, expect, it } from 'vitest';
import { dateOfDay, daysBetween, isIsoDay, isoDay, isoDayAfter } from './days.ts';

/*
 * A day is the person's own, by the device's clock (core/days.ts). The zone is moved for the tests that need a clock
 * west of Greenwich, where `toISOString` names the wrong day in the evening.
 */

const zone = process.env.TZ;
afterEach(() => {
  if (zone === undefined) delete process.env.TZ;
  else process.env.TZ = zone;
});

describe('a day from a moment', () => {
  it('is the day on the device’s calendar, late or early', () => {
    expect(isoDay(new Date(2026, 9, 3, 23, 59))).toBe('2026-10-03');
    expect(isoDay(new Date(2026, 9, 3, 0, 1))).toBe('2026-10-03');
    expect(isoDay(new Date(2026, 0, 1, 12))).toBe('2026-01-01');
  });

  it('is never the day in UTC: 23:30 in New York on the 3rd is the 3rd', () => {
    process.env.TZ = 'America/New_York';
    const evening = new Date(Date.UTC(2026, 9, 4, 3, 30));
    expect(evening.toISOString().slice(0, 10)).toBe('2026-10-04');
    expect(isoDay(evening)).toBe('2026-10-03');
  });
});

describe('a written day', () => {
  it('is four figures, two and two, on the calendar', () => {
    for (const day of ['2026-10-03', '2028-02-29', '2026-12-31', '0099-01-01']) expect(isIsoDay(day), day).toBe(true);
  });

  it('is not a day the calendar has not got, another form, or a day with words round it', () => {
    for (const text of ['2026-02-29', '2026-02-30', '2026-13-01', '2026-00-10', '2026-10-00', '2026-10-3', '26-10-03', '2026/10/03', '3 Oct', '', ' 2026-10-03', '2026-10-03T12:00']) {
      expect(isIsoDay(text), text).toBe(false);
    }
  });
});

describe('a day some days on', () => {
  it('counts on and back by the calendar, over months, years and a leap day', () => {
    expect(isoDayAfter('2026-10-03', 7)).toBe('2026-10-10');
    expect(isoDayAfter('2026-10-03', 0)).toBe('2026-10-03');
    expect(isoDayAfter('2026-10-03', -3)).toBe('2026-09-30');
    expect(isoDayAfter('2026-12-31', 1)).toBe('2027-01-01');
    expect(isoDayAfter('2028-02-28', 1)).toBe('2028-02-29');
    expect(isoDayAfter('2027-02-28', 1)).toBe('2027-03-01');
    expect(isoDayAfter('2026-10-03', 365)).toBe('2027-10-03');
  });

  it('counts whole days, from a moment by its day on the device’s clock', () => {
    expect(isoDayAfter(new Date(2026, 9, 3, 23, 30), 1)).toBe('2026-10-04');
    expect(isoDayAfter('2026-10-03', 1.9)).toBe('2026-10-04');
  });

  it('is the next Saturday a week on from the Saturday before the clocks go back', () => {
    process.env.TZ = 'Europe/London';
    expect(isoDayAfter(new Date(2026, 9, 24, 23, 30), 7)).toBe('2026-10-31');
    expect(isoDayAfter('2026-10-24', 7)).toBe('2026-10-31');
  });

  it('is nothing from words that are not a day', () => {
    expect(isoDayAfter('Friday', 1)).toBeNull();
    expect(isoDayAfter('2026-02-30', 1)).toBeNull();
  });
});

describe('days between two days', () => {
  it('are whole days, later minus earlier', () => {
    expect(daysBetween('2026-10-03', '2026-10-10')).toBe(7);
    expect(daysBetween('2026-10-10', '2026-10-03')).toBe(-7);
    expect(daysBetween('2026-10-03', '2026-10-03')).toBe(0);
    expect(daysBetween('2026-12-31', '2027-01-01')).toBe(1);
    expect(daysBetween('2026-03-28', '2026-03-30')).toBe(2);
  });

  it('are nothing where either is not a day', () => {
    expect(daysBetween('2026-10-03', 'Friday')).toBeNull();
    expect(daysBetween('', '2026-10-03')).toBeNull();
  });
});

describe('a written day as a moment', () => {
  it('is noon that day on the device’s clock, for a calendar to place and Intl to name', () => {
    const at = dateOfDay('2026-10-03');
    expect([at?.getFullYear(), at?.getMonth(), at?.getDate(), at?.getHours()]).toEqual([2026, 9, 3, 12]);
    expect(at && isoDay(at)).toBe('2026-10-03');
    expect(at?.getDay()).toBe(6);
  });

  it('is the same day west of Greenwich, and nothing for words that are not a day', () => {
    process.env.TZ = 'America/Los_Angeles';
    expect(isoDay(dateOfDay('2026-10-03')!)).toBe('2026-10-03');
    expect(dateOfDay('2026-02-30')).toBeNull();
  });
});
