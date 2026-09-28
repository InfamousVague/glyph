/**
 * A moment written as words, one way wherever the app writes one: the time the + puts at the line (docs/DESIGN.md
 * §141), a journal entry's date and time (§142, book/template.ts `{{date}}` and `{{time}}`), and the home page's day.
 *
 * In the device's own language and order, and always on a 24-hour clock, as a meeting's title is written
 * (capture/meeting.ts `meetingTitle`): "14:05" reads the same to everyone who reads the note later, and a note does
 * not say "2:05" and leave the afternoon to be guessed. Pure, and it imports nothing, so the MCP server fills a
 * journal's template with the same words the app does.
 *
 * Every format is asked of `Intl.DateTimeFormat` with no locale, which is the device's, so the three agree with each
 * other and with the rest of the page.
 */

/** "28 Sep 2026, 14:05": the day and the short month in the locale's order, the year, and the time. */
export function stamp(date: Date): string {
  // The day and the month in the locale's own order, its literals between them dropped (de-DE's "28. Sept." is
  // "28 Sept."), as a meeting's title takes them; a locale's own abbreviation is kept as it is.
  const dayMonth = new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short' })
    .formatToParts(date)
    .filter((part) => part.type === 'day' || part.type === 'month')
    .map((part) => part.value)
    .join(' ');
  const year = new Intl.DateTimeFormat(undefined, { year: 'numeric' }).format(date);
  return `${dayMonth} ${year}, ${clockTime(date)}`;
}

/** "14:05": the time on a 24-hour clock, whatever clock the locale keeps. */
export function clockTime(date: Date): string {
  return new Intl.DateTimeFormat(undefined, { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(date);
}

/** "Monday 28 September": the weekday, the day and the month, no year, as the home page greets the day. */
export function longDay(date: Date): string {
  return new Intl.DateTimeFormat(undefined, { weekday: 'long', month: 'long', day: 'numeric' }).format(date);
}

/**
 * "Monday 19 October 2026": the weekday, the day, the month and the year, as a worked-out date is drawn after a blank
 * (core/fillFacts.ts, docs/DESIGN.md §145). The person's own form, whatever their phone's language writes, since it is
 * read on this screen and never written into the note. The model is never shown it: its message has fixed English
 * (ai/fills/message.ts `modelDay`).
 */
export function longDate(date: Date): string {
  return new Intl.DateTimeFormat(undefined, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }).format(date);
}
