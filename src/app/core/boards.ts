/**
 * Boards in markdown: the whole syntax, read and written here and nowhere else (docs/BOARDS.md).
 *
 * Matt: "define and create a markdown standard we use to create kanban boards and task management boards entirely
 * within markdown, linking the tasks in the board to a task on the page", and later "come up with a generic way to
 * link list items to the board". Two pieces of ordinary markdown, and one of them is the link:
 *
 *   - [ ] Ship the pricing page ^ship-page      any list item may end with an anchor: the block id other tools write
 *   - Ask Sam about the copy ^ask-sam           the same way. A bullet, a number or a to-do, all the same.
 *
 *   ```board                                     a fence whose lines are the columns, each naming anchors
 *   To do: ship-page, ask-sam
 *   Done: pick-date
 *   ```
 *
 * The anchor is the generic part. It names an item, and anything that wants that item points at the anchor: the
 * board fence is only the first thing to do it, and `[[#^ask-sam]]` in any line is the same pointer written in
 * prose. Nothing is stored beside the note, so a board is readable as words wherever the note is opened, and Glyph
 * draws the columns with the items as cards (editor/boards.ts). A card IS its item: the same tick box, the same
 * words, and tapping it goes to the line.
 */

export interface BoardColumn {
  name: string;
  /** The anchors of the cards in it, in the order they sit. */
  cards: string[];
}

export interface Item {
  /** The anchor that names it. */
  id: string;
  /** The words, without the list marker, the tick box or the anchor. */
  text: string;
  /** Ticked, unticked, or null for an item with no box at all: a bullet or a numbered step. */
  done: boolean | null;
  /** Which line of the note it is on, counting from 1. */
  line: number;
}

/**
 * A list item, with its marker, any tick box, and any anchor at the end. The words are lazy so the anchor is read
 * off the end of the line: a caret needs a space before it and the end of the line after it, which leaves `E = mc^2^`
 * and `foo ^2^` as the superscript they are.
 */
const ITEM = /^(\s*(?:[-*+]|\d+[.)])\s+)(?:(\[)([ xX])(\]\s*))?(.*?)(?:\s+\^([a-z0-9][a-z0-9_-]*))?\s*$/;
/** An anchor name: lower case, the shape a person can type and read. */
export const ANCHOR = /^[a-z0-9][a-z0-9_-]*$/;
/** The fence that opens a board. */
const OPEN = /^\s*(`{3,}|~{3,})\s*board\s*$/i;
/** `[[#^ask-sam]]`: an item in this note, pointed at from anywhere in it. */
const REF = /\[\[#\^([a-z0-9][a-z0-9_-]*)\]\]/g;

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

/** Every anchored item in the note, the first of a repeated anchor winning. */
export function itemsIn(doc: string): Item[] {
  const items: Item[] = [];
  const seen = new Set<string>();
  doc.split('\n').forEach((line, index) => {
    const item = itemOnLine(line);
    if (!item || seen.has(item.id)) return;
    seen.add(item.id);
    items.push({ ...item, line: index + 1 });
  });
  return items;
}

/** The item a line is, if it is a list item with an anchor. */
export function itemOnLine(line: string): Item | null {
  const found = ITEM.exec(line);
  const id = found?.[6];
  if (!found || !id) return null;
  const box = found[3];
  return { id, text: (found[5] ?? '').trim(), done: box === undefined ? null : box !== ' ', line: 0 };
}

/** Whether a line is a list item at all: what can be given an anchor and put on a board. */
export function isItemLine(line: string): boolean {
  const found = ITEM.exec(line);
  return Boolean(found && ((found[5] ?? '').trim() || found[6]));
}

/** The words of a list item, box and anchor off, or null where the line is not one. */
export function itemWords(line: string): string | null {
  const found = ITEM.exec(line);
  return found ? (found[5] ?? '').trim() : null;
}

/** That line with its box ticked or cleared. An item with no box is left alone: there is nothing to tick. */
export function setItemDone(line: string, done: boolean): string {
  const found = ITEM.exec(line);
  if (!found?.[2]) return line;
  return line.replace(
    ITEM,
    (_all, lead: string, open: string, _state: string, close: string, text: string, anchor?: string) =>
      `${lead}${open}${done ? 'x' : ' '}${close}${text}${anchor ? ` ^${anchor}` : ''}`,
  );
}

/** That line given an anchor, or left as it is when it has one already. */
export function withAnchor(line: string, id: string): string {
  return itemOnLine(line) ? line : `${line.replace(/\s+$/, '')} ^${id}`;
}

/** Which column holds `id`, or -1. */
export function columnOf(columns: readonly BoardColumn[], id: string): number {
  return columns.findIndex((column) => column.cards.includes(id));
}

/** The column a board calls Done, or -1: the one a ticked item belongs in. */
export function doneColumn(columns: readonly BoardColumn[]): number {
  return columns.findIndex((column) => /^done\b|\bdone$/i.test(column.name.trim()));
}

/** A copy nothing shares with the columns given: every write here answers new columns, never the ones passed in. */
function copy(columns: readonly BoardColumn[]): BoardColumn[] {
  return columns.map((column) => ({ ...column, cards: [...column.cards] }));
}

/** The columns with `id` moved `by` columns along, as far as there are columns to move it to. */
export function moveCard(columns: readonly BoardColumn[], id: string, by: number): BoardColumn[] {
  const from = columnOf(columns, id);
  if (from < 0) return copy(columns);
  const to = Math.min(columns.length - 1, Math.max(0, from + by));
  // Already at the end it was pushed against: nothing moves, and the card stays where it is.
  if (to === from) return copy(columns);
  return putCard(columns, id, to);
}

/** The columns with `id` at the end of `to`, wherever it was. */
export function putCard(columns: readonly BoardColumn[], id: string, to: number): BoardColumn[] {
  return putCardAt(columns, id, to, Number.MAX_SAFE_INTEGER);
}

/**
 * The columns with `id` in `to` at `index`, wherever it was: what a card dropped between two others becomes
 * (Matt: "add a way to tap and drag to re organize items in lanes").
 *
 * The index counts the column as it will be, the card taken out of wherever it was first, so dragging a card down
 * its own column lands it where the gap was shown and not one place short.
 */
export function putCardAt(columns: readonly BoardColumn[], id: string, to: number, index: number): BoardColumn[] {
  if (to < 0 || to >= columns.length) return copy(columns);
  const without = columns.map((column) => column.cards.filter((card) => card !== id));
  const target = without[to] ?? [];
  const at = Math.max(0, Math.min(target.length, index));
  target.splice(at, 0, id);
  return columns.map((column, i) => ({ ...column, cards: i === to ? target : (without[i] ?? []) }));
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

/** A board's cards, each with the item it names: the ones whose item is gone are answered too, so nothing vanishes. */
export interface Card {
  id: string;
  column: number;
  item: Item | null;
}

export function cardsOf(columns: readonly BoardColumn[], items: readonly Item[]): Card[] {
  const byId = new Map(items.map((item) => [item.id, item]));
  return columns.flatMap((column, index) => column.cards.map((id) => ({ id, column: index, item: byId.get(id) ?? null })));
}

/** An item's own column: the Done one when it is ticked, else where the board has it. */
export function columnFor(columns: readonly BoardColumn[], item: Item): number {
  const done = doneColumn(columns);
  if (item.done === true && done >= 0) return done;
  return columnOf(columns, item.id);
}

/** An anchor made from an item's words: short, lower case, and not one the note already uses. */
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
      .join('-') || 'item';
  if (!taken.includes(base)) return base;
  for (let n = 2; ; n += 1) {
    const tried = `${base}-${n}`;
    if (!taken.includes(tried)) return tried;
  }
}

/** The board `line` is inside, fence lines included, or null. */
export function boardAt(doc: string, line: number): Board | null {
  return boardsIn(doc).find((board) => board.to > board.from && line >= board.from && line <= board.to) ?? null;
}

/**
 * Where an anchor is pointed at from: `[[#^ask-sam]]`, anywhere in a line, counting positions from `offset`.
 *
 * This is the anchor used as prose rather than as a card, and it is why the anchor is worth having on every kind of
 * item: "the copy is waiting on [[#^ask-sam]]" reads as words anywhere, and in Glyph it is a way back to the line.
 */
export interface ItemRef {
  from: number;
  to: number;
  id: string;
}

export function refsIn(text: string, offset = 0): ItemRef[] {
  const found: ItemRef[] = [];
  REF.lastIndex = 0;
  for (let match = REF.exec(text); match; match = REF.exec(text)) {
    found.push({ from: offset + match.index, to: offset + match.index + match[0].length, id: match[1] ?? '' });
  }
  return found;
}

/** The item an anchor names, wherever it is in the note, or null. */
export function itemAt(doc: string, id: string): Item | null {
  return itemsIn(doc).find((item) => item.id === id) ?? null;
}

/** An anchor written as a pointer to it, for anything that offers to write one. */
export function refFor(id: string): string {
  return `[[#^${id}]]`;
}

/**
 * A whole board as words to take away (Matt: "the task management board needs to be copyable but formatting is
 * splitting it up"). Drawn as columns, a board cannot be dragged over and copied a piece at a time, and its fence and
 * its items sit apart in the note anyway. This is both together, in the note's own markdown: the fence, then every
 * item it names in the order the note has them. Pasted into another note it is the same working board; pasted
 * anywhere else it reads as a list under its columns.
 *
 * Null when `line` is not inside a board.
 */
export function boardCopy(doc: string, line: number): string | null {
  const lines = doc.split('\n');
  const board = boardAt(doc, line);
  if (!board) return null;
  const named = new Set(board.columns.flatMap((column) => column.cards));
  const items = itemsIn(doc)
    .filter((item) => named.has(item.id))
    .map((item) => lines[item.line - 1] ?? '');
  const fence = lines.slice(board.from - 1, board.to).join('\n');
  return items.length ? `${fence}\n\n${items.join('\n')}\n` : `${fence}\n`;
}

/**
 * An item's words as a card says them: links by their own words, not by where they point, a pointer at another item
 * by its anchor, and the marks that would be drawn as bold or code taken off. The note keeps every character; this
 * is only what the card shows.
 */
export function cardText(text: string): string {
  return text
    .replace(REF, '^$1')
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/<((?:https?|mailto):[^>]+)>/g, '$1')
    .replace(/[*_`~]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

/** The columns a note is given when its items are made into a board. */
export const NEW_COLUMNS = ['To do', 'Doing', 'Done'];

/** A note turned into a board: the words it becomes, and what it took. */
export interface BoardMade {
  doc: string;
  /** How many items became cards. */
  cards: number;
  /** How many of them were already ticked, and so went straight to Done. */
  done: number;
}

/**
 * A list made into a board (Matt: "transform the task management note i have into kanban format").
 *
 * Every list item in the note is given an anchor if it has none, and a fence of columns goes in under the note's
 * title naming them all: the ticked ones in Done, the rest in the first column. Nothing else about the note is
 * touched - the words, the headings and the order stay exactly as they were, which is the point of the standard.
 *
 * Null when there is nothing to do: a note with no list, or one that is a board already.
 */
export function boardFrom(doc: string, columns: readonly string[] = NEW_COLUMNS): BoardMade | null {
  if (boardsIn(doc).some((board) => board.to > board.from)) return null;
  const lines = doc.split('\n');
  const taken = itemsIn(doc).map((item) => item.id);
  const cards: { id: string; done: boolean }[] = [];
  const inside = fencedLines(lines);
  lines.forEach((text, index) => {
    // A list inside a block of code is code, not a list: its lines are left exactly as they are.
    if (inside.has(index + 1) || !isItemLine(text)) return;
    const already = itemOnLine(text);
    const id = already?.id ?? anchorFor(itemWords(text) ?? text, taken);
    if (!already) {
      taken.push(id);
      lines[index] = withAnchor(text, id);
    }
    cards.push({ id, done: (already?.done ?? boxOf(text)) === true });
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

/** Whether a line's box is ticked, or null where it has none. */
function boxOf(line: string): boolean | null {
  const found = ITEM.exec(line);
  const box = found?.[3];
  return box === undefined ? null : box !== ' ';
}

/** Every line inside a fenced block, counting from 1: what is code and not markdown. */
function fencedLines(lines: readonly string[]): Set<number> {
  const inside = new Set<number>();
  let fence = '';
  lines.forEach((text, index) => {
    const edge = /^\s*(`{3,}|~{3,})/.exec(text);
    if (fence) {
      inside.add(index + 1);
      if (edge && edge[1]!.startsWith(fence[0]!) && edge[1]!.length >= fence.length && !text.trim().slice(edge[1]!.length).trim()) fence = '';
      return;
    }
    if (edge) {
      fence = edge[1]!;
      inside.add(index + 1);
    }
  });
  return inside;
}

/** What putting the item on line `line` onto a board changes: the line itself, when it needs an anchor, and the fence. */
export interface CardAdded {
  id: string;
  /** The item's line rewritten with its anchor, or null when it already had one. */
  line: { number: number; text: string } | null;
  /** The board's fence body rewritten, and which lines it lies between. */
  fence: { from: number; to: number; body: string };
  /** The column it went into. */
  column: string;
}

/**
 * The list item on `line` put on a board: the nearest board above it, else the first in the note. It lands in the
 * Done column when it is already ticked, else the first column. Null when the line is not a list item, there is no
 * board, or it is on one already.
 */
export function addToBoard(doc: string, line: number): CardAdded | null {
  const lines = doc.split('\n');
  const text = lines[line - 1];
  if (text === undefined || !isItemLine(text)) return null;
  const item = itemOnLine(text);
  const boards = boardsIn(doc).filter((board) => board.to > board.from && board.columns.length);
  if (!boards.length) return null;
  const above = [...boards].reverse().find((board) => board.to < line);
  const board = above ?? boards[0]!;
  const id =
    item?.id ??
    anchorFor(
      itemWords(text) ?? text,
      itemsIn(doc).map((other) => other.id),
    );
  if (columnOf(board.columns, id) >= 0) return null;
  const done = doneColumn(board.columns);
  const into = item?.done === true && done >= 0 ? done : 0;
  const columns = putCard(board.columns, id, into);
  return {
    id,
    line: item ? null : { number: line, text: withAnchor(text, id) },
    fence: { from: board.from, to: board.to, body: writeBoard(columns) },
    column: columns[into]?.name ?? '',
  };
}

/** A card made from the board itself: the new line to put in the note, where it goes, and the fence that names it. */
export interface CardMade {
  id: string;
  /** The line to write, and the line number it becomes. */
  at: number;
  text: string;
  fence: { from: number; to: number; body: string };
}

/**
 * A new card in column `column` of the board whose fence opens on `open` (Matt: "make the UI / UX of these boards
 * friendlier on mobile"): typing markdown to add one is not something to do on a phone, so the board writes the
 * line itself.
 *
 * The item goes in under the last item the board already names, so a board's items stay together, and under the
 * fence when it names none yet. It is written as a to-do, since a column is a place work waits in; the words are
 * left empty for the caret, which is what the editor puts there next.
 */
export function newCard(doc: string, open: number, column: number, words = ''): CardMade | null {
  const board = boardAt(doc, open);
  if (!board || !board.columns.length || column < 0 || column >= board.columns.length) return null;
  const named = new Set(board.columns.flatMap((held) => held.cards));
  const taken = itemsIn(doc);
  const last = taken.filter((item) => named.has(item.id) && item.line > board.to).pop();
  const id = anchorFor(
    words,
    taken.map((item) => item.id),
  );
  // Written at the indent of the item it follows, so a card added under a nested list stays in that list.
  const under = last ? (doc.split('\n')[last.line - 1] ?? '') : '';
  const indent = /^(\s*)/.exec(under)?.[1] ?? '';
  return {
    id,
    at: last ? last.line + 1 : board.to + 1,
    text: `${indent}- [ ] ${words}`.trimEnd() + ` ^${id}`,
    fence: { from: board.from, to: board.to, body: writeBoard(putCard(board.columns, id, column)) },
  };
}
