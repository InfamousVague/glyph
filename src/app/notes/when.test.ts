import { describe, expect, it } from 'vitest';
import { when } from './when.ts';

/** A card's timestamp, read rather than parsed: how long ago while that is short, and a day or a date after. */

const minute = 60_000;
const hour = 60 * minute;
const day = 24 * hour;
// A Friday at noon, local time.
const now = new Date(2026, 8, 25, 12, 0, 0).getTime();

describe('when a card says it was touched', () => {
  it('counts minutes and hours while they are few', () => {
    expect(when(now - 30_000, now)).toBe('Just now');
    expect(when(now - 5 * minute, now)).toBe('5 min ago');
    expect(when(now - 59 * minute, now)).toBe('59 min ago');
    expect(when(now - 3 * hour, now)).toBe('3 hr ago');
  });

  it('says yesterday, then the day of the week, then the date', () => {
    expect(when(now - 30 * hour, now)).toBe('Yesterday');
    expect(when(now - 3 * day, now)).toBe(new Date(now - 3 * day).toLocaleDateString(undefined, { weekday: 'long' }));
    expect(when(now - 30 * day, now)).toBe(new Date(now - 30 * day).toLocaleDateString(undefined, { month: 'long', day: 'numeric' }));
  });
});
