import { columnOf, doneColumn, putCard, settleColumns } from './columns.ts';
import { boardsIn, writeBoard } from './fence.ts';
import { isItemLine, itemOnLine, itemsIn } from './items.ts';
import { addToBoard, listAround } from './make.ts';

/**
 * A tick, carried to the boards: what every fence in the note says once a box is ticked or cleared in the note's
 * list, or a batch of tasks goes Done in Notion (editor/doneSync.ts).
 *
 * A column called Done means done. `settleColumns` (columns.ts) is how a board DRAWS that, whatever its fence says;
 * these bring the markdown round to agree, since the markdown is the note. They answer the fences to write, and the
 * lines that gained an anchor to join a board; the editor applies both in the same transaction as the tick
 * (editor/boards.ts `settleFences`).
 */

/** A fence to be written again: the lines it is on, counting from 1, and its new body. */
export interface FenceEdit {
  /** The line the opening fence is on. */
  from: number;
  /** The line the closing fence is on. */
  to: number;
  body: string;
}

/**
 * Every fence in the note that has something to say again, given the boxes about to change: `ticks` is each item's
 * line and the state its box is being set to. One box tapped in the list, or a batch of them arriving from Notion,
 * are the same thing here.
 *
 * A box ticked puts its card in Done; a box cleared takes its card out of Done and back to the first lane, as
 * unticking a card on the board does. Any other card whose item is already ticked is settled at the same time, so a
 * note that has drifted comes right with the next change rather than staying wrong. Nothing else about the fence
 * moves, and a board with no Done lane leaves its ticks alone.
 */
export function settleBoards(doc: string, ticks: ReadonlyMap<number, boolean> = new Map()): FenceEdit[] {
  const items = itemsIn(doc).map((item) => (ticks.has(item.line) ? { ...item, done: ticks.get(item.line) ?? item.done } : item));
  const cleared = [...ticks].filter(([, on]) => !on).map(([line]) => items.find((item) => item.line === line));
  const edits: FenceEdit[] = [];
  for (const board of boardsIn(doc)) {
    if (board.to <= board.from + 1) continue;
    let columns = settleColumns(board.columns, items);
    const done = doneColumn(columns);
    for (const item of cleared) {
      if (item && done >= 0 && columnOf(columns, item.id) === done) columns = putCard(columns, item.id, 0);
    }
    const body = writeBoard(columns);
    if (body !== writeBoard(board.columns)) edits.push({ from: board.from, to: board.to, body });
  }
  return edits;
}

/** A tick that had to write more than a fence: the lines that gained an anchor so they could join a board. */
export interface SettledTicks {
  fences: FenceEdit[];
  /** The item's line, counting from 1, and the anchor to put at the end of it. */
  lines: { number: number; anchor: string }[];
}

/**
 * Everything a tick changes, when the box is turned somewhere other than the board.
 *
 * `settleBoards` moves cards that exist. This adds the one thing it cannot: an item that is **not** a card, ticked in
 * a list whose other items are on a board, joins that board and lands in Done (found in Matt's own note -
 * three ticked items with no anchor, so ticking them moved nothing, while the other 57 worked). From where a person
 * sits, two identical-looking to-dos behaved differently and nothing said why.
 *
 * Scoped to the item's own list on purpose: docs/BOARDS.md says a board never has to hold every item in the note, so
 * a to-do in some unrelated list further down must not leap onto the board because it was ticked. It joins the board
 * its neighbours are already on, and nothing else does.
 */
export function settleTicks(doc: string, ticks: ReadonlyMap<number, boolean>): SettledTicks {
  const lines = doc.split('\n');
  const joined: { number: number; anchor: string }[] = [];
  for (const [line, on] of ticks) {
    if (!on) continue;
    const working = lines.join('\n');
    const text = lines[line - 1];
    if (text === undefined || !isItemLine(text)) continue;
    const item = itemOnLine(text);
    // Already a card: moving it is `settleBoards`' job, not this one.
    if (item && boardsIn(working).some((board) => columnOf(board.columns, item.id) >= 0)) continue;
    if (!listOnBoard(working, line)) continue;
    const added = addToBoard(working, line);
    if (!added) continue;
    if (added.line) {
      lines[added.line.number - 1] = added.line.text;
      joined.push({ number: added.line.number, anchor: added.id });
    }
    // The fence keeps its number of lines, so every line number above stays good for the next tick in the batch.
    lines.splice(added.fence.from, added.fence.to - added.fence.from - 1, ...added.fence.body.split('\n'));
  }
  // Then the ordinary settling - ticked cards into Done, cleared ones back out - over the note as it now stands.
  for (const edit of settleBoards(lines.join('\n'), ticks)) {
    lines.splice(edit.from, edit.to - edit.from - 1, ...edit.body.split('\n'));
  }
  const now = boardsIn(lines.join('\n'));
  const fences: FenceEdit[] = [];
  boardsIn(doc).forEach((board, at) => {
    const body = now[at]?.body ?? board.body;
    if (board.to > board.from + 1 && body !== board.body) fences.push({ from: board.from, to: board.to, body });
  });
  return { fences, lines: joined };
}

/** Whether the list `line` stands in has any item that is already a card on a board. */
function listOnBoard(doc: string, line: number): boolean {
  const around = listAround(doc, line);
  if (!around) return false;
  const boards = boardsIn(doc).filter((board) => board.to > board.from);
  if (!boards.length) return false;
  return itemsIn(doc).some(
    (item) => item.line !== line && item.line >= around.from && item.line <= around.to && boards.some((board) => columnOf(board.columns, item.id) >= 0),
  );
}
