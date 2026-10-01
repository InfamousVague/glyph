import { daysBetween, isoDayAfter } from '../days.ts';
import type { Group } from './run.ts';

/**
 * A query shown as a gantt (`show: gantt`): its records turned into the text of a Mermaid gantt chart, which the
 * diagrams' own path draws (editor/mermaid.ts), so a gantt is drawn the way every diagram in a note is, in the app's
 * two inks, and nothing new is loaded for it (docs/QUERIES.md, docs/DESIGN.md §159).
 *
 *   gantt
 *     dateFormat YYYY-MM-DD
 *     axisFormat %e %b
 *     section In progress
 *     Fix the login loop :active, 2026-09-28, 2026-10-04
 *
 * A record is a bar from its start to its due day, the due day drawn whole (Mermaid's end is the start of the day it
 * names, so the bar ends the day after). One with only a due day, or only a start, is a bar of that one day; one with
 * neither is not on the chart, and is counted for the page to say so. Each group is a section; a query not grouped
 * has none, so its bars have the width a section's name would take. A bar is `done` when its record is finished with,
 * `active` when it is under way, and `crit` when it is overdue, which are Mermaid's own words for those, and the chart
 * marks today.
 *
 * Laid out for a card on a phone: the ticks a day, a week or a month apart as the bars span days, weeks or months, so
 * their dates never run into each other, and the room Mermaid keeps either side for a desktop's page cut down, in a
 * directive at the top that any other renderer of Mermaid reads too.
 *
 * The words are a record's own, so they are made safe for Mermaid's grammar, which reads `:` as the end of a bar's
 * name, `;` and `#` as its own, `%%` as a comment, and a line that starts `section` or `title` as one of those: each is
 * taken out or set apart. Pure (core/query/gantt.test.ts).
 */

/** The words Mermaid's gantt reads at the start of a line as its own. */
const KEYWORDS = /^(?:section|title|dateformat|axisformat|tickinterval|excludes|includes|todaymarker|weekday|weekend|click|acctitle|accdescr|inclusiveenddates|topaxis|displaymode)\b/i;

/** A record's words as a bar's name, or a group's as a section's: one line Mermaid reads as words. */
export function ganttWords(words: string, fallback: string): string {
  const clean = words
    .replace(/%%/g, '%')
    .replace(/[:;#\n\r]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 80)
    .trim();
  if (!clean) return fallback;
  // A no-break space before a name that starts like one of Mermaid's lines keeps it a name.
  return KEYWORDS.test(clean) ? `\u00a0${clean}` : clean;
}

/**
 * The Mermaid text for `groups`' records, and how many it places; empty text where it places none. `kind` names a
 * section whose group has no words of its own: "To-dos", "Tickets", "Notes".
 */
export function ganttOf(groups: readonly Group[], kind = 'Records'): { code: string; placed: number } {
  const body: string[] = [];
  const sections = groups.length > 1 || groups.some((group) => group.label);
  let placed = 0;
  // The days the bars run from and to, all of them: what the ticks are spaced for.
  let from: string | null = null;
  let to: string | null = null;
  for (const group of groups) {
    const bars: string[] = [];
    for (const row of group.rows) {
      const first = row.start ?? row.due;
      const last = row.due ?? row.start;
      if (!first || !last) continue;
      // A start written after the due day is the two the wrong way round: the bar still runs between them.
      const start = first <= last ? first : last;
      const end = isoDayAfter(first <= last ? last : first, 1);
      if (!end) continue;
      if (!from || start < from) from = start;
      if (!to || end > to) to = end;
      const tags = [row.category === 'done' || row.done === true ? 'done' : row.category === 'doing' ? 'active' : '', row.overdue ? 'crit' : ''].filter(Boolean);
      const name = ganttWords(row.id ? `${row.id} ${row.name}` : row.name, 'Untitled');
      bars.push(`  ${name} :${[...tags, start, end].join(', ')}`);
    }
    if (!bars.length) continue;
    if (sections) body.push(`  section ${ganttWords(group.label, kind)}`);
    body.push(...bars);
    placed += bars.length;
  }
  if (!placed || !from || !to) return { code: '', placed: 0 };
  const { tick, axis } = ticksFor(daysBetween(from, to) ?? 0);
  // Mermaid's own top and grid padding are kept: its axis is drawn a fixed distance up from the foot, and less room
  // above put the dates over the last bar.
  const layout = { gantt: { leftPadding: sections ? 80 : 8, rightPadding: 16, barHeight: 22, barGap: 6, fontSize: 12, sectionFontSize: 12 } };
  const lines = [`%%{init: ${JSON.stringify(layout)}}%%`, 'gantt', '  dateFormat YYYY-MM-DD', `  axisFormat ${axis}`, `  tickInterval ${tick}`, ...body];
  return { code: lines.join('\n'), placed };
}

/** How far apart the ticks are, and how each is dated, for bars that span `days`: few enough that no two dates touch. */
export function ticksFor(days: number): { tick: string; axis: string } {
  if (days <= 10) return { tick: '1day', axis: '%e' };
  if (days <= 70) return { tick: '1week', axis: '%e %b' };
  if (days <= 400) return { tick: '1month', axis: '%b' };
  return { tick: '3month', axis: '%b %Y' };
}
