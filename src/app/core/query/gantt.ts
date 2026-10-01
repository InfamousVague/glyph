import { isoDayAfter } from '../days.ts';
import type { Group } from './run.ts';

/**
 * A query shown as a gantt (`show: gantt`): its records turned into the text of a Mermaid gantt chart, which the
 * diagrams' own path draws (editor/mermaid.ts), so a gantt is drawn the way every diagram in a note is, in the app's
 * two inks, and nothing new is loaded for it (docs/QUERIES.md, docs/DESIGN.md §158).
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
 * has one, named for what it lists. A bar is `done` when its record is finished with, `active` when it is under way,
 * and `crit` when it is overdue, which are Mermaid's own words for those, and the chart marks today.
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
  return KEYWORDS.test(clean) ? ` ${clean}` : clean;
}

/**
 * The Mermaid text for `groups`' records, and how many it places; empty text where it places none. `kind` names the
 * one section of a query that is not grouped: "To-dos", "Tickets", "Notes".
 */
export function ganttOf(groups: readonly Group[], kind = 'Records'): { code: string; placed: number } {
  const lines = ['gantt', '  dateFormat YYYY-MM-DD', '  axisFormat %e %b'];
  let placed = 0;
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
      const tags = [row.category === 'done' || row.done === true ? 'done' : row.category === 'doing' ? 'active' : '', row.overdue ? 'crit' : ''].filter(Boolean);
      const name = ganttWords(row.id ? `${row.id} ${row.name}` : row.name, 'Untitled');
      bars.push(`  ${name} :${[...tags, start, end].join(', ')}`);
    }
    if (!bars.length) continue;
    lines.push(`  section ${ganttWords(group.label, kind)}`, ...bars);
    placed += bars.length;
  }
  return { code: placed ? lines.join('\n') : '', placed };
}
