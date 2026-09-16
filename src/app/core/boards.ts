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
  return line.replace(
    TASK,
    (_all, open: string, _box: string, close: string, text: string, anchor = '') => `${open}${done ? 'x' : ' '}${close}${text}${anchor}`,
  );
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

/** An anchor made from a task's words: short, lower case, and not one the note already uses. */
export function anchorFor(text: string, taken: readonly string[]): string {
  const base =
    text
      // A link is named by its words, not by where it points: [notion](https://…) anchors as "notion", never as a URL.
      .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .split('-')
      .filter(Boolean)
      .slice(0, 3)
      .join('-') || 'task';
  if (!taken.includes(base)) return base;
  for (let n = 2; ; n += 1) {
    const tried = `${base}-${n}`;
    if (!taken.includes(tried)) return tried;
  }
}

/**
 * A task's words as a card says them: links by their own words, not by where they point, and the marks that would be
 * drawn as bold or code taken off. The note keeps every character; this is only what the card shows.
 */
export function cardText(text: string): string {
  return text
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/<((?:https?|mailto):[^>]+)>/g, '$1')
    .replace(/[*_`~]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

/** The columns a note is given when its to-dos are made into a board. */
export const NEW_COLUMNS = ['To do', 'Doing', 'Done'];

/** A note turned into a board: the words it becomes, and what it took. */
export interface BoardMade {
  doc: string;
  /** How many to-dos became cards. */
  cards: number;
  /** How many of them were already ticked, and so went straight to Done. */
  done: number;
}

/**
 * A list of to-dos made into a board (Matt: "transform the task management note i have into kanban format").
 *
 * Every to-do in the note is given an anchor if it has none, and a fence of columns goes in under the note's title
 * naming them all: the ticked ones in Done, the rest in the first column. Nothing else about the note is touched -
 * the words, the headings and the order stay exactly as they were, which is the point of the standard.
 *
 * Null when there is nothing to do: a note with no to-dos, or one that is a board already.
 */
export function boardFrom(doc: string, columns: readonly string[] = NEW_COLUMNS): BoardMade | null {
  if (boardsIn(doc).some((board) => board.to > board.from)) return null;
  const lines = doc.split('\n');
  const taken = tasksIn(doc).map((task) => task.id);
  const cards: { id: string; done: boolean }[] = [];
  lines.forEach((text, index) => {
    const box = /^(\s*[-*+]\s+\[)([ xX])(\]\s+)(\S.*)$/.exec(text);
    if (!box) return;
    const already = taskOnLine(text);
    const id = already?.id ?? anchorFor(already?.text ?? (box[4] ?? '').trim(), taken);
    if (!already?.id) {
      taken.push(id);
      lines[index] = `${text.replace(/\s+$/, '')} ^${id}`;
    }
    cards.push({ id, done: box[2] !== ' ' });
  });
  if (!cards.length) return null;
  const named = columns.length ? [...columns] : [...NEW_COLUMNS];
  const called = named.findIndex((name) => /^done\b|\bdone$/i.test(name.trim()));
  const last = called >= 0 ? called : named.length - 1;
  const board: BoardColumn[] = named.map((name, index) => ({
    name,
    cards: cards.filter((card) => (card.done ? last : 0) === index).map((card) => card.id),
  }));
  const fence = ['```board', writeBoard(board), '```', ''];
  // Under the note's title, where a board is read first; a note that opens with words takes the board above them.
  const title = /^#\s+\S/.test(lines[0] ?? '') ? 1 : 0;
  const blank = title && (lines[1] ?? '').trim() === '';
  lines.splice(blank ? 2 : title, 0, ...(title && !blank ? ['', ...fence] : fence));
  return { doc: lines.join('\n'), cards: cards.length, done: cards.filter((card) => card.done).length };
}

/** What putting the to-do on line `line` onto a board changes: the line itself, when it needs an anchor, and the fence. */
export interface CardAdded {
  id: string;
  /** The task's line rewritten with its anchor, or null when it already had one. */
  line: { number: number; text: string } | null;
  /** The board's fence body rewritten, and which lines it lies between. */
  fence: { from: number; to: number; body: string };
  /** The column it went into. */
  column: string;
}

/**
 * The to-do on `line` put on a board: the nearest board above it, else the first in the note. It lands in the Done
 * column when it is already ticked, else the first column. Null when the line is not a to-do, there is no board, or
 * it is on one already.
 */
export function addToBoard(doc: string, line: number): CardAdded | null {
  const lines = doc.split('\n');
  const text = lines[line - 1];
  if (text === undefined) return null;
  const task = taskOnLine(text);
  if (!task && !/^\s*[-*+]\s+\[[ xX]\]\s+\S/.test(text)) return null;
  const boards = boardsIn(doc).filter((board) => board.to > board.from && board.columns.length);
  if (!boards.length) return null;
  const above = [...boards].reverse().find((board) => board.to < line);
  const board = above ?? boards[0]!;
  const id =
    task?.id ??
    anchorFor(
      taskOnLine(`${text} ^x`)?.text ?? text,
      tasksIn(doc).map((other) => other.id),
    );
  if (columnOf(board.columns, id) >= 0) return null;
  const done = doneColumn(board.columns);
  const into = task?.done && done >= 0 ? done : 0;
  const columns = putCard(board.columns, id, into);
  return {
    id,
    line: task?.id ? null : { number: line, text: `${text.replace(/\s+$/, '')} ^${id}` },
    fence: { from: board.from, to: board.to, body: writeBoard(columns) },
    column: columns[into]?.name ?? '',
  };
}
