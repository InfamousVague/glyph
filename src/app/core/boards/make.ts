import { isDoneName, listLead } from '../itemSyntax.ts';
import { columnOf, doneColumn, putCardAt } from './columns.ts';
import { boardAt, boardsIn, fencedLines, writeBoard, type BoardColumn } from './fence.ts';
import { anchorFor, isItemLine, itemOnLine, itemWords, itemsIn, withAnchor } from './items.ts';

/**
 * Boards and cards made from a note's own lists: a whole note's items made into a board, one list made into a board
 * of its own, an item put on the board its neighbours are already on, and a new card written from the board itself.
 *
 * Each answers the note's own markdown - anchors added to the ends of lines, a fence set in - and leaves every other
 * word where it was, which is the point of the standard (docs/BOARDS.md). None of them writes anything: the caller
 * applies what comes back, the editor in one transaction (editor/ContextMenu.tsx, editor/boards.ts), the recorder
 * to the note it is filing into (capture/).
 */

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
  const cards = anchorItems(lines, doc, 1, lines.length);
  if (!cards.length) return null;
  const fence = fenceFor(cards, columns);
  // Under the note's title, where a board is read first; a note that opens with words takes the board above them.
  const title = /^#\s+\S/.test(lines[0] ?? '') ? 1 : 0;
  const blank = title && (lines[1] ?? '').trim() === '';
  lines.splice(blank ? 2 : title, 0, ...(title && !blank ? ['', ...fence] : fence));
  return { doc: lines.join('\n'), cards: cards.length, done: cards.filter((card) => card.done).length };
}

/**
 * Every list item from line `from` to line `to` given an anchor where it has none, in place in `lines`, and each
 * one's anchor and whether it is ticked, in order. A list inside a block of code is code, not a list: its lines are
 * left exactly as they are.
 */
function anchorItems(lines: string[], doc: string, from: number, to: number): { id: string; done: boolean }[] {
  const taken = itemsIn(doc).map((item) => item.id);
  const inside = fencedLines(lines);
  const cards: { id: string; done: boolean }[] = [];
  for (let index = Math.max(0, from - 1); index < Math.min(lines.length, to); index += 1) {
    const text = lines[index] ?? '';
    if (inside.has(index + 1) || !isItemLine(text)) continue;
    const already = itemOnLine(text);
    const id = already?.id ?? anchorFor(itemWords(text) ?? text, taken);
    if (!already) {
      taken.push(id);
      lines[index] = withAnchor(text, id);
    }
    cards.push({ id, done: listLead(text)?.done === true });
  }
  return cards;
}

/** A board fence laying `cards` out in `columns`: the ticked ones in the column called Done, the rest in the first. */
function fenceFor(cards: readonly { id: string; done: boolean }[], columns: readonly string[]): string[] {
  const named = columns.length ? [...columns] : [...NEW_COLUMNS];
  const called = named.findIndex(isDoneName);
  const last = called >= 0 ? called : named.length - 1;
  const board: BoardColumn[] = named.map((name, index) => ({
    name,
    cards: cards.filter((card) => (card.done ? last : 0) === index).map((card) => card.id),
  }));
  return ['```board', writeBoard(board), '```', ''];
}

/**
 * The list line `line` is in, from its first item to its last, counting from 1; or null where the line is in no list
 * (Matt: "add ability to auto list a section of list items into a board").
 *
 * A list is the run of item lines around the line, with the indented lines that belong to its items and a single
 * blank line between two of them. A heading, a paragraph, a block of code, or two blank lines end it.
 */
export function listAround(doc: string, line: number): { from: number; to: number } | null {
  const lines = doc.split('\n');
  const inside = fencedLines(lines);
  const member = (index: number) => {
    const text = lines[index];
    if (text === undefined || inside.has(index + 1)) return false;
    return isItemLine(text) || /^\s{2,}\S/.test(text);
  };
  const blank = (index: number) => (lines[index] ?? 'x').trim() === '';
  let first = line - 1;
  if (!member(first)) return null;
  let last = first;
  for (;;) {
    if (member(first - 1)) first -= 1;
    else if (blank(first - 1) && member(first - 2)) first -= 2;
    else break;
  }
  for (;;) {
    if (member(last + 1)) last += 1;
    else if (blank(last + 1) && member(last + 2)) last += 2;
    else break;
  }
  // A list starts and ends with an item: indented lines outside those belong to something else.
  while (first <= last && !isItemLine(lines[first] ?? '')) first += 1;
  while (last >= first && !isItemLine(lines[last] ?? '')) last -= 1;
  return first <= last ? { from: first + 1, to: last + 1 } : null;
}

/** One list made into a board: what changes, where, and the board's opening line once it is in. */
export interface ListBoard extends BoardMade {
  /** Item lines that gained an anchor, each with its new words, numbered as the note was. */
  lines: { number: number; text: string }[];
  /** The fence, and the line of the note as it was that it goes in above. */
  fence: { before: number; text: string };
  /** The line the board opens on, in the note as it becomes. */
  open: number;
}

/**
 * The items from line `from` to line `to` made into a board of their own, set in just above them: each item named,
 * the ticked ones in Done. The rest of the note, other boards included, is left as it is, so a note can hold one
 * board per list.
 *
 * Null where there is nothing to make: no items in the lines, or a board already sitting right above them.
 */
export function boardFromList(doc: string, from: number, to: number, columns: readonly string[] = NEW_COLUMNS): ListBoard | null {
  const lines = doc.split('\n');
  let above = from - 2;
  while (above >= 0 && (lines[above] ?? '').trim() === '') above -= 1;
  if (above >= 0 && boardsIn(doc).some((board) => board.to > board.from && board.to === above + 1)) return null;
  const before = [...lines];
  const cards = anchorItems(lines, doc, from, to);
  if (!cards.length) return null;
  const changed = lines.flatMap((text, index) => (text !== before[index] ? [{ number: index + 1, text }] : []));
  const fence = fenceFor(cards, columns);
  // A line of words straight above the list keeps a blank line between it and the board.
  const gap = from > 1 && (lines[from - 2] ?? '').trim() !== '';
  const block = gap ? ['', ...fence] : fence;
  lines.splice(from - 1, 0, ...block);
  return {
    doc: lines.join('\n'),
    cards: cards.length,
    done: cards.filter((card) => card.done).length,
    lines: changed,
    fence: { before: from, text: `${block.join('\n')}\n` },
    open: from + (gap ? 1 : 0),
  };
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
 * The list item on `line` put on a board (Matt: "add an 'add to board' option when other items in the list are in a
 * board already").
 *
 * The board is the one that already holds the item's neighbours - the list it stands in, `listAround` - since a list
 * with cards on a board is almost always the board it belongs to; failing that, the nearest board above it, else the
 * first in the note.
 *
 * It lands in the first lane, or in Done when it is already ticked: a new card is something to do, whatever lane the
 * item next to it sits in. Within that lane it goes in beside the nearest neighbour that is already there, on the
 * same side as the note has it, so a board keeps the list's own order instead of collecting new cards at the end.
 *
 * Null when the line is not a list item, there is no board to put it on, or its anchor is already a card.
 */
export function addToBoard(doc: string, line: number): CardAdded | null {
  const lines = doc.split('\n');
  const text = lines[line - 1];
  if (text === undefined || !isItemLine(text)) return null;
  const item = itemOnLine(text);
  const boards = boardsIn(doc).filter((board) => board.to > board.from && board.columns.length);
  if (!boards.length) return null;
  const id =
    item?.id ??
    anchorFor(
      itemWords(text) ?? text,
      itemsIn(doc).map((other) => other.id),
    );
  // The item's neighbours in its own list, nearest first: which board they are on, and where on it.
  const around = listAround(doc, line);
  const mates = around
    ? itemsIn(doc)
        .filter((other) => other.line >= around.from && other.line <= around.to && other.line !== line)
        .sort((one, two) => Math.abs(one.line - line) - Math.abs(two.line - line))
    : [];
  const held = mates.map((mate) => ({ mate, board: boards.find((board) => columnOf(board.columns, mate.id) >= 0) })).filter((found) => found.board);
  const above = [...boards].reverse().find((board) => board.to < line);
  const board = held[0]?.board ?? above ?? boards[0]!;
  if (columnOf(board.columns, id) >= 0) return null;
  const done = doneColumn(board.columns);
  const into = item?.done === true && done >= 0 ? done : 0;
  // Beside the nearest neighbour already in that lane, on the side the note has it: the list's order, kept.
  const beside = held.find((found) => found.board === board && columnOf(board.columns, found.mate.id) === into)?.mate;
  const cards = board.columns[into]?.cards ?? [];
  const at = beside ? cards.indexOf(beside.id) + (beside.line < line ? 1 : 0) : Number.MAX_SAFE_INTEGER;
  const columns = putCardAt(board.columns, id, into, at);
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
 * A new card in column `column` of the board whose fence opens on `open`, carrying `words` (Matt: "make the UI / UX
 * of these boards friendlier on mobile", and "a button on each board to add an item, it should add the item to the
 * list the board is derived from"): typing markdown to add one is not something to do on a phone, so the board
 * writes the line itself.
 *
 * The words come first and the line is made with them, so the anchor is named after what the item says from the
 * start. A card written empty and named later would be `^item`, `^item-2`, `^item-3` for as long as nobody renamed
 * it, and those are the names a person points at. No words, no card.
 *
 * The item goes in under the last item the board already names, so a board's items stay together, and under the
 * fence when it names none yet. It is written as a to-do, since a column is a place work waits in. The card goes in
 * at `index` in its column: the top by default, under the field it was typed into.
 */
export function newCard(doc: string, open: number, column: number, words: string, index = 0): CardMade | null {
  const said = words.replace(/\s+/g, ' ').trim();
  const board = boardAt(doc, open);
  if (!said || !board || !board.columns.length || column < 0 || column >= board.columns.length) return null;
  const named = new Set(board.columns.flatMap((held) => held.cards));
  const taken = itemsIn(doc);
  const last = taken.filter((item) => named.has(item.id) && item.line > board.to).pop();
  const id = anchorFor(
    said,
    taken.map((item) => item.id),
  );
  // Written at the indent of the item it follows, so a card added under a nested list stays in that list.
  const under = last ? (doc.split('\n')[last.line - 1] ?? '') : '';
  const indent = /^(\s*)/.exec(under)?.[1] ?? '';
  return {
    id,
    at: last ? last.line + 1 : board.to + 1,
    text: `${indent}- [ ] ${said} ^${id}`,
    fence: { from: board.from, to: board.to, body: writeBoard(putCardAt(board.columns, id, column, index)) },
  };
}
