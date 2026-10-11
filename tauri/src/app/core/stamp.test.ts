import { describe, expect, it } from 'vitest';
import { inLocale } from '../../test/locale.ts';
import { clockTime, longDate, longDay, stamp } from './stamp.ts';

/**
 * A moment as words: the day and the month in the device's order, and a 24-hour clock in every language. Monday 28
 * September 2026, 14:05, in the device's own time zone.
 */

const AFTERNOON = new Date(2026, 8, 28, 14, 5);
const MORNING = new Date(2026, 8, 28, 9, 5);

describe('a moment as words', () => {
  it('writes the day and the short month in the locale’s order, then the year and the time', () => {
    expect(inLocale('en-GB', () => stamp(AFTERNOON))).toBe('28 Sept 2026, 14:05');
    expect(inLocale('en-US', () => stamp(AFTERNOON))).toBe('Sep 28 2026, 14:05');
    // The literal after a German day goes; the month keeps its own abbreviation.
    expect(inLocale('de-DE', () => stamp(AFTERNOON))).toBe('28 Sept. 2026, 14:05');
  });

  it('keeps a 24-hour clock where the locale would say pm, with the hour in two figures', () => {
    expect(inLocale('en-US', () => clockTime(AFTERNOON))).toBe('14:05');
    expect(inLocale('en-US', () => clockTime(MORNING))).toBe('09:05');
    expect(inLocale('en-GB', () => clockTime(MORNING))).toBe('09:05');
  });

  it('greets the day as the home page does: weekday, day and month, no year', () => {
    expect(inLocale('en-GB', () => longDay(AFTERNOON))).toBe('Monday 28 September');
    expect(inLocale('en-US', () => longDay(AFTERNOON))).toBe('Monday, September 28');
    expect(inLocale('de-DE', () => longDay(AFTERNOON))).toBe('Montag, 28. September');
  });

  it('writes a worked-out date whole, in the person’s own form (docs/DESIGN.md §145)', () => {
    expect(inLocale('en-GB', () => longDate(AFTERNOON))).toMatch(/^Monday,? 28 September 2026$/);
    expect(inLocale('en-US', () => longDate(AFTERNOON))).toBe('Monday, September 28, 2026');
    expect(inLocale('de-DE', () => longDate(AFTERNOON))).toBe('Montag, 28. September 2026');
  });
});
