/**
 * The date and the time as the app writes them into a note: one way, wherever a note is stamped. The + beside the
 * line writes "28 Sep 2026, 14:05" where the caret is (editor/AddList.tsx), and a journal titles its entries by the
 * same words, so a stamp typed by the + and an entry's title read alike.
 *
 * The rules are a meeting's title's (capture/meeting.ts `meetingTitle`): the day and the short month in the locale's
 * own order, with the locale's literals between them dropped and its own abbreviation kept ("Sept." in German), and
 * then a 24-hour clock. A stamp adds the year after the month, since a note outlives the year it was written in. The
 * long day is the home page's heading (home/HomeScreen.tsx), "Monday 28 September".
 *
 * Pure, and read in the device's own locale: a stamp is words for the person who wrote it.
 */

/** "28 Sep 2026, 14:05": the day and the short month in the locale's order, the year, and a 24-hour clock. */
export function stamp(date: Date): string {
  const parts = new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short' }).formatToParts(date);
  const day = parts
    .filter((part) => part.type === 'day' || part.type === 'month')
    .map((part) => part.value)
    .join(' ');
  return `${day} ${date.getFullYear()}, ${clockTime(date)}`;
}

/** "14:05": the time on a 24-hour clock, whatever the locale's own clock. */
export function clockTime(date: Date): string {
  return new Intl.DateTimeFormat(undefined, { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(date);
}

/** "Monday 28 September": the weekday, the day and the long month, as the home page heads its day. */
export function longDay(date: Date): string {
  return date.toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' });
}
