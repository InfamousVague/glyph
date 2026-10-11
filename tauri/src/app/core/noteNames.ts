import { longDate } from './stamp.ts';
import { formatStamp } from './template.ts';
import { titleKey } from './titleKey.ts';

/**
 * The names a new note is offered under its empty first line (docs/DESIGN.md §144; editor/nameChips.ts draws them).
 * Matt: "Add suggestions for note names like the days date and other standard note formats".
 *
 * Four, always in this order, so a thumb learns where each is: the day in words with its year, "Monday, 28 September
 * 2026" (Matt: "the day in words first"), then `2026-09-28`, Obsidian's daily note's name, then `2026-09-28 14.05`, the
 * journal's name for an entry, for a second note in a day, then `2026-W40`, the ISO week, for a weekly note. The three
 * ISO names are ASCII digits in every language, so a file name and a title's key (core/titleKey.ts) keep them whole,
 * and none has a colon. The day in words has its year so it never names two days; the home page's yearless day
 * repeats every year.
 *
 * A name another note already has is left out, and the rest keep their places: no name opens another note, and none
 * makes a second note of a name that is taken. `taken` is every note's title key, archived and in the Trash too.
 * Where a language's key loses the month (Russian's "понедельник, 28 сентября 2026 г." keys as "28 2026", like every
 * other 28th that year), the words are still offered, but whether today is taken is asked of its ISO name, which does
 * keep the month (`keysTheDay`).
 *
 * Nothing is learned and nothing is stored: the clock, and the titles the store already holds. Pure, so every rule is
 * a test.
 */

export type NameKind = 'words' | 'day' | 'minute' | 'week';

export interface NameOffer {
  kind: NameKind;
  /** What the chip shows, and what a tap writes as the note's heading. */
  name: string;
  /** What a screen reader says for it. */
  label: string;
}

/** "2026-09-28 14.05": the minute as a name, as a journal names an entry (book/journal.ts `entryTitle`). */
export function minuteName(at: Date): string {
  return formatStamp(at, 'YYYY-MM-DD HH.mm');
}

/**
 * Whether the day in words still tells one day from another once reduced to its key: not empty, and not the key of the
 * same day a month on or a year on. English, German, Japanese and Chinese keep it; Russian, Greek, Hebrew and Hindi
 * key only the day and the year, and Arabic and Persian key nothing at all. The day is read at the 28th at most, so
 * the month on is the same day and not a turn into the one after.
 */
export function keysTheDay(at: Date): boolean {
  const day = Math.min(at.getDate(), 28);
  const key = titleKey(longDate(new Date(at.getFullYear(), at.getMonth(), day)));
  if (!key) return false;
  const monthOn = titleKey(longDate(new Date(at.getFullYear(), at.getMonth() + 1, day)));
  const yearOn = titleKey(longDate(new Date(at.getFullYear() + 1, at.getMonth(), day)));
  return key !== monthOn && key !== yearOn;
}

/** The names on offer at `at`, in their fixed order, leaving out any whose key is in `taken`. */
export function nameOffers(at: Date, taken: ReadonlySet<string>): NameOffer[] {
  const day = formatStamp(at, 'YYYY-MM-DD');
  const words = longDate(at);
  const minute = minuteName(at);
  const week = formatStamp(at, 'GGGG-[W]WW');
  const all: (NameOffer & { key: string })[] = [
    { kind: 'words', name: words, label: 'Name it for today, in words.', key: keysTheDay(at) ? titleKey(words) : titleKey(day) },
    { kind: 'day', name: day, label: `Name it for today, ${day}.`, key: titleKey(day) },
    { kind: 'minute', name: minute, label: `Name it for this minute, ${minute}.`, key: titleKey(minute) },
    { kind: 'week', name: week, label: `Name it for this week, ${week}.`, key: titleKey(week) },
  ];
  return all.filter((offer) => !taken.has(offer.key)).map(({ kind, name, label }) => ({ kind, name, label }));
}
