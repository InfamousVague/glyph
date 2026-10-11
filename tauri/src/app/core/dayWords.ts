import { dateOfDay, isIsoDay, isoDayAfter } from './days.ts';

/**
 * A day said in words, as the day a note writes (core/days.ts): "today", "tomorrow", "Friday", "next Friday", "next
 * week", "in two weeks", "the third of October", "October 3rd". What a spoken "due Friday" sets on a to-do
 * (capture/spoken/fields.ts) and what the press-and-hold menu's Today, Tomorrow and Next week set
 * (editor/fieldMenu.ts), so the menu's "Next week" and the voice's are one day (docs/DESIGN.md §158).
 *
 * The rules, counted from `today`, the person's own day:
 *
 * - **A weekday** is the next one, today included: "Friday" said on a Friday is today. "This Friday" is the same day.
 *   "Next Friday" is the Friday of next week, a week that starts on a Monday, as a British calendar's does: said on a
 *   Monday it is eleven days on, and said on a Thursday it is eight.
 * - **Next week** is that week's Monday, the day a thing put off to next week is looked at again; "the weekend" is
 *   the coming Saturday, or today when today is the weekend.
 * - **A date** with no year is the next one, today included: "the third of October" said on the 4th is next year's.
 *   "The third" alone is this month's, or next month's once it has gone.
 * - **A count** of days or weeks, "in three days", "in a week", "in a fortnight".
 *
 * Words that are not one of these are not a day, and the caller keeps them as words: a due day that cannot be read
 * is never guessed at. Pure, so each rule is a line of core/dayWords.test.ts.
 */

const WEEKDAYS = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
const MONTHS = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];
/** A month as it may be shortened, "Sept" and "Oct"; "May" is its own. */
const MONTH_SHORT: Record<string, number> = { jan: 0, feb: 1, mar: 2, apr: 3, jun: 5, jul: 6, aug: 7, sep: 8, sept: 8, oct: 9, nov: 10, dec: 11 };

const UNITS = ['', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine'];
const TEENS = ['ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
const ORDINAL_UNITS = ['', 'first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh', 'eighth', 'ninth'];
const ORDINAL_TEENS = ['tenth', 'eleventh', 'twelfth', 'thirteenth', 'fourteenth', 'fifteenth', 'sixteenth', 'seventeenth', 'eighteenth', 'nineteenth'];

/** "Third", "twenty-first", "3rd", "3": a day of the month, 1 to 31, or null. */
function dayNumber(said: string): number | null {
  const word = said.replace(/[\s-]+/g, ' ').trim();
  const digits = /^(\d{1,2})(?:st|nd|rd|th)?$/.exec(word);
  if (digits) return Number(digits[1]);
  const plain = ORDINAL_UNITS.indexOf(word);
  if (plain > 0) return plain;
  const teen = ORDINAL_TEENS.indexOf(word);
  if (teen >= 0) return 10 + teen;
  if (word === 'twentieth') return 20;
  if (word === 'thirtieth') return 30;
  const compound = /^(twenty|thirty) (\w+)$/.exec(word);
  const unit = compound ? ORDINAL_UNITS.indexOf(compound[2] ?? '') : -1;
  return compound && unit > 0 ? (compound[1] === 'twenty' ? 20 : 30) + unit : null;
}

/** "Two", "a", "12": a small count, or null. */
function count(said: string): number | null {
  if (/^\d{1,3}$/.test(said)) return Number(said);
  if (said === 'a' || said === 'an') return 1;
  const unit = UNITS.indexOf(said);
  if (unit > 0) return unit;
  const teen = TEENS.indexOf(said);
  return teen >= 0 ? 10 + teen : null;
}

/** A month by name, full or short, from 0; null for none. */
function monthOf(said: string): number | null {
  const full = MONTHS.indexOf(said);
  if (full >= 0) return full;
  return MONTH_SHORT[said] ?? null;
}

/** Which day of the week `day` is, from Sunday's 0; null where it is not a day. */
function weekdayOf(day: string): number | null {
  return dateOfDay(day)?.getDay() ?? null;
}

/**
 * The Monday of the week after `today`'s: next week, as a thing is put off to it. A week starts on a Monday, so said
 * on a Sunday it is the next day.
 */
export function nextWeek(today: string): string | null {
  const weekday = weekdayOf(today);
  if (weekday === null) return null;
  return isoDayAfter(today, 7 - ((weekday + 6) % 7));
}

/** The next `weekday` (Sunday 0) from `today`, today included. */
function comingWeekday(today: string, weekday: number): string | null {
  const now = weekdayOf(today);
  return now === null ? null : isoDayAfter(today, (weekday - now + 7) % 7);
}

/** `year-month-day` written as a day, or null where the calendar has not got it. */
function written(year: number, month: number, day: number): string | null {
  const iso = `${String(year).padStart(4, '0')}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
  return isIsoDay(iso) ? iso : null;
}

/** A date with no year: this year's, or next year's once this year's has gone. */
function comingDate(today: string, month: number, day: number, year: number | null): string | null {
  if (year !== null) return written(year, month, day);
  const thisYear = Number(today.slice(0, 4));
  const here = written(thisYear, month, day);
  // 29 February in a year without one is the next year that has it, at most four on.
  if (here && here >= today) return here;
  for (let ahead = 1; ahead <= 4; ahead += 1) {
    const there = written(thisYear + ahead, month, day);
    if (there) return there;
  }
  return null;
}

/** "The third": this month's, or next month's once it has gone (and the one after, for a 31st a short month lacks). */
function comingDayOfMonth(today: string, day: number): string | null {
  let year = Number(today.slice(0, 4));
  let month = Number(today.slice(5, 7)) - 1;
  for (let ahead = 0; ahead < 3; ahead += 1) {
    const there = written(year, month, day);
    if (there && there >= today) return there;
    month += 1;
    if (month > 11) {
      month = 0;
      year += 1;
    }
  }
  return null;
}

/** A day of the month said as words or digits: "third", "twenty first", "3rd". */
const DAY = String.raw`(\d{1,2}(?:st|nd|rd|th)?|(?:twenty|thirty)[\s-]?\w+|\w+(?:st|nd|rd|th))`;
const MONTH = String.raw`([a-z]{3,9})`;
const YEAR = String.raw`(?:\s+(\d{4}))?`;
/** "The third of October", "3 October 2027", "3rd of Oct". */
const DAY_MONTH = new RegExp(String.raw`^(?:the\s+)?${DAY}(?:\s+of)?\s+${MONTH}${YEAR}$`);
/** "October the third", "October 3rd", "Oct 3 2027". */
const MONTH_DAY = new RegExp(String.raw`^${MONTH}\s+(?:the\s+)?${DAY}${YEAR}$`);
/** "The third", "the 3rd". */
const THE_DAY = new RegExp(String.raw`^the\s+${DAY}$`);

/**
 * The day `said` names, counted from `today`, or null where the words are not a day this reads. Case, a leading "on",
 * "by" or "this", and the stops and commas Whisper writes inside a date are not part of what was said.
 */
export function dayOfWords(said: string, today: string): string | null {
  if (!isIsoDay(today)) return null;
  const words = said
    .toLowerCase()
    .replace(/[.,!?;:]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/^(?:on|by|for)\s+/, '');
  if (!words) return null;

  if (/^(?:today|tonight|this (?:morning|afternoon|evening)|(?:the )?end of (?:the )?day)$/.test(words)) return today;
  if (/^tomorrow(?: (?:morning|afternoon|evening|night))?$/.test(words)) return isoDayAfter(today, 1);
  if (/^(?:the )?day after tomorrow$/.test(words)) return isoDayAfter(today, 2);
  if (words === 'yesterday') return isoDayAfter(today, -1);
  if (/^next week$/.test(words)) return nextWeek(today);
  if (/^(?:this |the )?weekend$/.test(words)) {
    const weekday = weekdayOf(today);
    return weekday === 6 || weekday === 0 ? today : comingWeekday(today, 6);
  }
  const fortnight = /^in (?:a|one) fortnight$/.exec(words);
  if (fortnight) return isoDayAfter(today, 14);
  const after = /^in (\w+) (day|days|week|weeks)$/.exec(words);
  if (after) {
    const n = count(after[1] ?? '');
    return n === null ? null : isoDayAfter(today, after[2]!.startsWith('week') ? n * 7 : n);
  }

  const weekday = /^(?:(this|next|on) )?(\w+)$/.exec(words);
  const named = weekday ? WEEKDAYS.indexOf(weekday[2] ?? '') : -1;
  if (weekday && named >= 0) {
    if (weekday[1] !== 'next') return comingWeekday(today, named);
    const monday = nextWeek(today);
    return monday ? isoDayAfter(monday, (named + 6) % 7) : null;
  }

  const dayMonth = DAY_MONTH.exec(words);
  if (dayMonth) {
    const day = dayNumber(dayMonth[1] ?? '');
    const month = monthOf(dayMonth[2] ?? '');
    if (day !== null && month !== null) return comingDate(today, month, day, dayMonth[3] ? Number(dayMonth[3]) : null);
  }
  const monthDay = MONTH_DAY.exec(words);
  if (monthDay) {
    const month = monthOf(monthDay[1] ?? '');
    const day = dayNumber(monthDay[2] ?? '');
    if (day !== null && month !== null) return comingDate(today, month, day, monthDay[3] ? Number(monthDay[3]) : null);
  }
  const theDay = THE_DAY.exec(words);
  if (theDay) {
    const day = dayNumber(theDay[1] ?? '');
    if (day !== null) return comingDayOfMonth(today, day);
  }
  return null;
}
