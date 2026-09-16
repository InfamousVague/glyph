/**
 * Boards in markdown: the whole syntax, read and written here and nowhere else (docs/BOARDS.md).
 *
 * Matt: "define and create a markdown standard we use to create kanban boards and task management boards entirely
 * within markdown, linking the tasks in the board to a task on the page". Two pieces of ordinary markdown:
 *
 *   - [ ] Ship the pricing page ^ship-page      a to-do with an anchor, the block id other tools write the same way
 *
 *   ```board                                     a fence whose lines are the columns
 *   To do: ship-page, email-list
 *   Done: pick-date
 *   ```
 *
 * So a board is readable as words wherever the note is opened, and Glyph draws the columns with the tasks as cards
 * (editor/boards.ts). A card IS its task: the same tick box, the same words, and tapping it goes to the line.
 */

export interface BoardColumn {
  name: string;
  /** The anchors of the cards in it, in the order they sit. */
  cards: string[];
}

export interface Task {
  /** The anchor that names it. */
  id: string;
  /** The words, without the tick box or the anchor. */
  text: string;
  done: boolean;
  /** Which line of the note it is on, counting from 1. */
  line: number;
}

/** A to-do line, with its box and any anchor at the end. */
const TASK = /^(\s*[-*+]\s+\[)([ xX])(\]\s+)(.*?)(\s+\^([a-z0-9][a-z0-9_-]*))?\s*$/;
/** An anchor name: lower case, the shape a person can type and read. */
export const ANCHOR = /^[a-z0-9][a-z0-9_-]*$/;
/** The fence that opens a board. */
const OPEN = /^\s*(`{3,}|~{3,})\s*board\s*$/i;

/** The columns a board fence's body lays out. A line with no colon is a column with no cards. */
export function readBoard(body: string): BoardColumn[] {
  const columns: BoardColumn[] = [];
  for (const line of body.split('\n')) {
    const text = line.trim();
    if (!text) continue;
    const at = text.indexOf(':');
    const name = (at >= 0 ? text.slice(0, at) : text).trim();
    if (!name) continue;
    const cards = (at >= 0 ? text.slice(at + 1) : '')
      .split(',')
      .map((card) => card.trim().replace(/^\^/, ''))
      .filter((card) => ANCHOR.test(card));
    const already = columns.find((column) => column.name.toLowerCase() === name.toLowerCase());
    if (already) already.cards.push(...cards.filter((card) => !already.cards.includes(card)));
    else columns.push({ name, cards: cards.filter((card, i) => cards.indexOf(card) === i) });
  }
  return columns;
}

/** The columns written back as a fence's body, exactly as a person would type them. */
export function writeBoard(columns: readonly BoardColumn[]): string {
  return columns.map((column) => `${column.name}: ${column.cards.join(', ')}`.replace(/:\s+$/, ':')).join('\n');
}

/** Every anchored task in the note, the first of a repeated anchor winning. */
export function tasksIn(doc: string): Task[] {
  const tasks: Task[] = [];
  const seen = new Set<string>();
  doc.split('\n').forEach((line, index) => {
    const found = TASK.exec(line);
    const id = found?.[6];
    if (!found || !id || seen.has(id)) return;
    seen.add(id);
    tasks.push({ id, text: (found[4] ?? '').trim(), done: found[2] !== ' ', line: index + 1 });
  });
  return tasks;
}

/** The task a line is, if it is one with an anchor. */
export function taskOnLine(line: string): Task | null {
  const found = TASK.exec(line);
  const id = found?.[6];
  return found && id ? { id, text: (found[4] ?? '').trim(), done: found[2] !== ' ', line: 0 } : null;
}

/** That line with its box ticked or cleared. */
export function setTaskDone(line: string, done: boolean): string {
  return line.replace(TASK, (_all, open: string, _box: string, close: string, text: string, anchor = '') => `${open}${done ? 'x' : ' '}${close}${text}${anchor}`);
}

/** Which column holds `id`, or -1. */
export function columnOf(columns: readonly BoardColumn[], id: string): number {
  return columns.findIndex((column) => column.cards.includes(id));
}

/** The column a board calls Done, or -1: the one a ticked task belongs in. */
export function doneColumn(columns: readonly BoardColumn[]): number {
  return columns.findIndex((column) => /^done\b|\bdone$/i.test(column.name.trim()));
}

/** The columns with `id` moved `by` columns along, as far as there are columns to move it to. */
export function moveCard(columns: readonly BoardColumn[], id: string, by: number): BoardColumn[] {
  const from = columnOf(columns, id);
  if (from < 0) return columns.map((column) => ({ ...column, cards: [...column.cards] }));
  const to = Math.min(columns.length - 1, Math.max(0, from + by));
  // Already at the end it was pushed against: nothing moves, and the card stays where it is.
  if (to === from) return columns.map((column) => ({ ...column, cards: [...column.cards] }));
  return columns.map((column, index) => ({
    ...column,
    cards: index === from ? column.cards.filter((card) => card !== id) : index === to ? [...column.cards.filter((card) => card !== id), id] : [...column.cards],
  }));
}

/** The columns with `id` in `to`, wherever it was. */
export function putCard(columns: readonly BoardColumn[], id: string, to: number): BoardColumn[] {
  if (to < 0 || to >= columns.length || columnOf(columns, id) === to) return columns.map((column) => ({ ...column, cards: [...column.cards] }));
  return columns.map((column, index) => ({
    ...column,
    cards: index === to ? [...column.cards.filter((card) => card !== id), id] : column.cards.filter((card) => card !== id),
  }));
}

export interface Board {
  /** The line the opening fence is on, counting from 1. */
  from: number;
  /** The line the closing fence is on; the same as `from` when the fence never closes. */
  to: number;
  /** The fence's body: the lines between. */
  body: string;
  columns: BoardColumn[];
}

/** Every board in the note, in order. */
export function boardsIn(doc: string): Board[] {
  const lines = doc.split('\n');
  const boards: Board[] = [];
  for (let i = 0; i < lines.length; i += 1) {
    const open = OPEN.exec(lines[i] ?? '');
    if (!open) continue;
    const fence = open[1] ?? '```';
    let end = i;
    for (let j = i + 1; j < lines.length; j += 1) {
      if (new RegExp(`^\\s*${fence[0] === '~' ? '~' : '`'}{${fence.length},}\\s*$`).test(lines[j] ?? '')) {
        end = j;
        break;
      }
    }
    const body = end > i ? lines.slice(i + 1, end).join('\n') : '';
    boards.push({ from: i + 1, to: end + 1, body, columns: readBoard(body) });
    i = end;
  }
  return boards;
}

/** A board's cards, each with the task it names: the ones whose task is gone are answered too, so nothing vanishes. */
export interface Card {
  id: string;
  column: number;
  task: Task | null;
}

export function cardsOf(columns: readonly BoardColumn[], tasks: readonly Task[]): Card[] {
  const byId = new Map(tasks.map((task) => [task.id, task]));
  return columns.flatMap((column, index) => column.cards.map((id) => ({ id, column: index, task: byId.get(id) ?? null })));
}

/** A task's own column: the Done one when it is ticked, else where the board has it. */
export function columnFor(columns: readonly BoardColumn[], task: Task): number {
  const done = doneColumn(columns);
  if (task.done && done >= 0) return done;
  return columnOf(columns, task.id);
}
