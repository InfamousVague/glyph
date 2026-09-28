import { describe, expect, it } from 'vitest';
import { clockTime, longDay, stamp } from './stamp.ts';

/**
 * The stamp the app writes (core/stamp.ts), in the locales a person might have: the day and the month in the locale's
 * own order and spelling, the year, and always a 24-hour clock. The helpers read the device's locale, so each case
 * runs with the locale set for it.
 */

/** 28 September 2026, 14:05, in this machine's time zone: the helpers read local time. */
const AT = new Date(2026, 8, 28, 14, 5);

/** Runs `read` as though the device's locale were `locale`. */
function inLocale<T>(locale: string, read: () => T): T {
  const Format = Intl.DateTimeFormat;
  const toLocaleDate = Date.prototype.toLocaleDateString;
  Intl.DateTimeFormat = function (_asked?: string | string[], options?: Intl.DateTimeFormatOptions) {
    return new Format(locale, options);
  } as unknown as typeof Intl.DateTimeFormat;
  Date.prototype.toLocaleDateString = function (this: Date, _asked?: string | string[], options?: Intl.DateTimeFormatOptions) {
    return toLocaleDate.call(this, locale, options);
  };
  try {
    return read();
  } finally {
    Intl.DateTimeFormat = Format;
    Date.prototype.toLocaleDateString = toLocaleDate;
  }
}

describe('stamp', () => {
  it('writes the day, the short month, the year and the time', () => {
    expect(inLocale('en-GB', () => stamp(new Date(2026, 9, 5, 14, 5)))).toBe('5 Oct 2026, 14:05');
  });

  it('keeps the locale’s own order and abbreviation, and drops what the locale puts between them', () => {
    // British English shortens September to "Sept", as a meeting's title does (capture/meeting.test.ts).
    expect(inLocale('en-GB', () => stamp(AT))).toBe('28 Sept 2026, 14:05');
    expect(inLocale('en-US', () => stamp(AT))).toBe('Sep 28 2026, 14:05');
    expect(inLocale('de-DE', () => stamp(AT))).toBe('28 Sept. 2026, 14:05');
  });

  it('is always a 24-hour clock, with the minutes padded', () => {
    const morning = new Date(2026, 0, 3, 9, 7);
    expect(inLocale('en-US', () => stamp(morning))).toBe('Jan 3 2026, 09:07');
    expect(inLocale('en-GB', () => stamp(new Date(2026, 11, 31, 23, 59)))).toBe('31 Dec 2026, 23:59');
  });

  it('turns midnight into 00, never 24', () => {
    expect(inLocale('en-US', () => clockTime(new Date(2026, 8, 28, 0, 30)))).toBe('00:30');
  });
});

describe('clockTime', () => {
  it('is the stamp’s own time', () => {
    expect(inLocale('en-GB', () => clockTime(AT))).toBe('14:05');
    expect(inLocale('en-US', () => clockTime(AT))).toBe('14:05');
  });
});

describe('longDay', () => {
  it('is the weekday, the day and the long month, as the home page heads its day', () => {
    expect(inLocale('en-GB', () => longDay(AT))).toBe('Monday 28 September');
    expect(inLocale('en-US', () => longDay(AT))).toBe('Monday, September 28');
  });
});
