/**
 * A ```gantt fence on the shared page (docs/GANTT.md; Matt, 2026-10-31: "work on making a better gannt chart
 * implementation in markdown"). The reader draws no diagrams (a ```mermaid fence is its code), so a gantt is not drawn
 * as a chart here either: its list is read, as lib/core/gantt/format.dart reads it, and drawn as the readable list it
 * is (Rendered.tsx `GanttList`): the title, each section's name, and each task with its days, its people, how far
 * along it is and what it waits on, a milestone with its diamond. Nothing is worked out: a task with no days of its
 * own says what it waits on, as its line does.
 */

export interface GanttTask {
  name: string;
  milestone: boolean;
  /** The days as written: a start and an end (both in), a start and a length, or a length alone. */
  start: string | null;
  end: string | null;
  length: string | null;
  people: string[];
  tags: string[];
  after: string[];
  progress: number | null;
}

export interface GanttSection {
  name: string;
  tasks: GanttTask[];
}

export interface GanttList {
  title: string | null;
  sections: GanttSection[];
}

const FRONT = /^\s*(title|start|zoom|workdays|today|follow|colou?r)\s*:\s*(.*?)\s*$/i;
const HEADING = /^\s{0,3}#{1,6}\s+(.*?)(?:\s+#+)?\s*$/;
const COLON = /^\s*([^\s\-*+#>|`@[%][^:]*?)\s*:\s*$/;
const LEAD = /^\s*(?:[-*+]|\d{1,9}[.)])\s+/;
const DAY = '(\\d{4}-\\d{2}-\\d{2})';
const RANGE = new RegExp(`^\\s*${DAY}\\s*(?:→|->|–|—|\\.\\.|to)\\s*${DAY}\\s*$`);
const LENGTH = new RegExp(`^\\s*${DAY}\\s*\\+\\s*(\\d+\\s*(?:d|w|days?|weeks?)?)\\s*$`);
const ONLY = /^\s*\+?\s*(\d+\s*(?:d|w|days?|weeks?))\s*$/;
const ONE = new RegExp(`^\\s*${DAY}\\s*$`);

/** A task's line read: its name, then its marks. */
export function readTask(line: string): GanttTask | null {
  const lead = LEAD.exec(line);
  if (!lead) return null;
  let rest = line.slice(lead[0].length);
  const task: GanttTask = { name: '', milestone: false, start: null, end: null, length: null, people: [], tags: [], after: [], progress: null };
  // The days: the first brackets that are days, not a link's.
  rest = rest.replace(/(?<!\[)\[([^[\]\n]*)\](?!\])/, (all, inner: string) => {
    if (task.start || task.length) return all;
    let m = RANGE.exec(inner);
    if (m) {
      task.start = m[1]!;
      task.end = m[2]!;
      return '\u0000';
    }
    m = LENGTH.exec(inner);
    if (m) {
      task.start = m[1]!;
      task.length = m[2]!.replace(/\s+/g, '');
      return '\u0000';
    }
    m = ONLY.exec(inner);
    if (m) {
      task.length = m[1]!.replace(/\s+/g, '');
      return '\u0000';
    }
    m = ONE.exec(inner);
    if (m) {
      task.start = m[1]!;
      task.end = m[1]!;
      return '\u0000';
    }
    return all;
  });
  const after = /(?:^|\s)after:\s*(.*?)(?=\s+(?:@|#|\d{1,3}\s?%|colou?r:)|\s*\u0000|$)/i.exec(rest);
  if (after) {
    task.after = after[1]!.split(',').map((name) => name.trim()).filter(Boolean);
    rest = rest.replace(after[0], ' \u0000');
  }
  rest = rest.replace(/(?:^|\s)colou?r:\s*[A-Za-z]+(?=\s|$)/i, ' \u0000');
  rest = rest.replace(/(?<=^|\s)(\d{1,3})\s?%(?=\s|$)/, (_, value: string) => {
    task.progress = Math.min(100, Number(value));
    return '\u0000';
  });
  rest = rest.replace(/(?<=^|\s)@([^\s@#[\],]+)/g, (_, name: string) => {
    task.people.push(name);
    return '\u0000';
  });
  rest = rest.replace(/(?<=^|\s)#([^\s@#[\],%]+)/g, (_, tag: string) => {
    task.tags.push(tag);
    return '\u0000';
  });
  let name = rest.split('\u0000')[0]!.trim();
  const stone = /^(◆|◇|<>)\s*/.exec(name);
  if (stone) {
    task.milestone = true;
    name = name.slice(stone[0].length);
  }
  task.name = name.replace(/\[\[([^[\]|\n]+)(?:\|([^[\]\n]+))?\]\]/g, (_, title: string, alias?: string) => alias ?? title);
  return task;
}

/** A fence's body read as its list. */
export function readGantt(body: string): GanttList {
  let title: string | null = null;
  const sections: GanttSection[] = [];
  let current: GanttSection = { name: '', tasks: [] };
  sections.push(current);
  for (const line of body.split('\n')) {
    const front = FRONT.exec(line);
    if (front && !LEAD.test(line)) {
      if (front[1]!.toLowerCase() === 'title' && front[2]) title = front[2];
      continue;
    }
    const heading = HEADING.exec(line) ?? (LEAD.test(line) ? null : COLON.exec(line));
    if (heading && heading[1]!.trim()) {
      current = { name: heading[1]!.trim(), tasks: [] };
      sections.push(current);
      continue;
    }
    const task = readTask(line);
    if (task) current.tasks.push(task);
  }
  return { title, sections: sections.filter((section) => section.name || section.tasks.length > 0) };
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** `2026-11-02` as `2 Nov`. */
export function shortDay(day: string): string {
  const [, month, date] = day.split('-').map(Number);
  return `${date} ${MONTHS[(month ?? 1) - 1]}`;
}

/** A task's days as a reader says them: `2 Nov – 6 Nov`, `2 Nov, 5 days`, `3 days`, or `2 Nov`. */
export function daysSaid(task: GanttTask): string | null {
  const length = task.length ? task.length.replace(/^(\d+)\s*d(?:ays?)?$/, (_, n: string) => `${n} day${n === '1' ? '' : 's'}`).replace(/^(\d+)\s*w(?:eeks?)?$/, (_, n: string) => `${n} week${n === '1' ? '' : 's'}`) : null;
  if (task.start && task.end) return task.start === task.end ? shortDay(task.start) : `${shortDay(task.start)} – ${shortDay(task.end)}`;
  if (task.start) return length ? `${shortDay(task.start)}, ${length}` : shortDay(task.start);
  return length;
}
