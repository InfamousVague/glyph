import { describe, expect, it } from 'vitest';
import { dayOfWords, nextWeek } from './dayWords.ts';

/**
 * A day said in words, counted from Thursday 1 October 2026 unless a case says otherwise: each rule core/dayWords.ts
 * promises, and the words it must leave as words, since a due day that cannot be read is never guessed at.
 */

const THURSDAY = '2026-10-01';
const said = (words: string, today = THURSDAY) => dayOfWords(words, today);

describe('days named by where they are from today', () => {
  it('reads today, tonight, tomorrow and the days either side', () => {
    expect(said('today')).toBe('2026-10-01');
    expect(said('Tonight')).toBe('2026-10-01');
    expect(said('this evening')).toBe('2026-10-01');
    expect(said('end of day')).toBe('2026-10-01');
    expect(said('tomorrow')).toBe('2026-10-02');
    expect(said('tomorrow morning')).toBe('2026-10-02');
    expect(said('the day after tomorrow')).toBe('2026-10-03');
    expect(said('yesterday')).toBe('2026-09-30');
  });

  it('reads a count of days or weeks', () => {
    expect(said('in three days')).toBe('2026-10-04');
    expect(said('in 10 days')).toBe('2026-10-11');
    expect(said('in a week')).toBe('2026-10-08');
    expect(said('in two weeks')).toBe('2026-10-15');
    expect(said('in a fortnight')).toBe('2026-10-15');
  });
});

describe('weekdays', () => {
  it('takes a weekday as the next one, today included', () => {
    expect(said('Friday')).toBe('2026-10-02');
    expect(said('on Friday')).toBe('2026-10-02');
    expect(said('this Friday')).toBe('2026-10-02');
    expect(said('by Saturday')).toBe('2026-10-03');
    expect(said('Thursday')).toBe('2026-10-01');
    expect(said('Wednesday')).toBe('2026-10-07');
  });

  it('takes "next" as the week after this one, which starts on a Monday', () => {
    expect(said('next Friday')).toBe('2026-10-09');
    expect(said('next Thursday')).toBe('2026-10-08');
    expect(said('next Monday')).toBe('2026-10-05');
    // Said on a Monday, next Friday is eleven days on; said on a Sunday, the week after this one starts tomorrow.
    expect(said('next Friday', '2026-10-05')).toBe('2026-10-16');
    expect(said('next Friday', '2026-10-04')).toBe('2026-10-09');
  });

  it('takes next week as its Monday, and the weekend as its Saturday', () => {
    expect(said('next week')).toBe('2026-10-05');
    expect(nextWeek('2026-10-04')).toBe('2026-10-05');
    expect(nextWeek('2026-10-05')).toBe('2026-10-12');
    expect(nextWeek('3 Oct')).toBeNull();
    expect(said('the weekend')).toBe('2026-10-03');
    expect(said('this weekend', '2026-10-03')).toBe('2026-10-03');
    expect(said('weekend', '2026-10-04')).toBe('2026-10-04');
  });
});

describe('dates', () => {
  it('reads a date said either way round, with its day in words or figures', () => {
    expect(said('the third of October')).toBe('2026-10-03');
    expect(said('October the third')).toBe('2026-10-03');
    expect(said('October third')).toBe('2026-10-03');
    expect(said('October 3rd')).toBe('2026-10-03');
    expect(said('3 October')).toBe('2026-10-03');
    expect(said('3rd of Oct')).toBe('2026-10-03');
    expect(said('the twenty-first of December')).toBe('2026-12-21');
    expect(said('December twenty first')).toBe('2026-12-21');
    expect(said('the thirtieth of November')).toBe('2026-11-30');
  });

  it('takes a date with no year as the next one, today included', () => {
    expect(said('1 October')).toBe('2026-10-01');
    expect(said('the 30th of September')).toBe('2027-09-30');
    expect(said('29 February')).toBe('2028-02-29');
  });

  it('keeps a year when one is said, commas and all', () => {
    expect(said('December 21st, 2027')).toBe('2027-12-21');
    expect(said('3 October 2025')).toBe('2025-10-03');
  });

  it('takes "the third" as this month’s, or the next month that has it', () => {
    expect(said('the third')).toBe('2026-10-03');
    expect(said('the first')).toBe('2026-10-01');
    expect(said('the 31st')).toBe('2026-10-31');
    expect(said('the 31st', '2026-11-15')).toBe('2026-12-31');
    expect(said('the second', '2026-12-20')).toBe('2027-01-02');
  });
});

describe('words that are not a day', () => {
  it('reads nothing it was not taught', () => {
    for (const words of ['', 'soon', 'later', 'the end of the month', 'Friday week', 'the 35th of October', '31 September', 'Fooday', 'next', 'in some days', 'the plumber'])
      expect(said(words), words).toBeNull();
  });

  it('reads nothing from a today that is not a day', () => {
    expect(dayOfWords('tomorrow', '1 Oct')).toBeNull();
  });
});
