import type { EditorView } from '@codemirror/view';
import { fireNativeHaptic } from '../../core/haptics.ts';
import {
  doneColumn,
  moveCard,
  putCard,
  putCardAt,
  setItemDone,
  settleColumns,
  withoutCard,
  writeBoard,
  type BoardColumn,
  type Card,
} from '../../core/boards.ts';
import type { DrawnBoard } from './drawn.ts';
import { hushGoTo, reveal } from './navigate.ts';

/**
 * What a card does to the note: ticked, stepped a lane along, dropped somewhere, or taken off the board. Each is one
 * change and one undo, the fence rewritten and the item's box turned together where the card crosses a Done column,
 * so the note says what the board shows. Every one carries the `input.board` user event: a board's edits are not
 * typing, and the wisp does not smoke them as letters someone wrote (editor/wispMotion.ts).
 */

/** The card's tick box is the item's: the line is ticked, and a Done column takes the card. */
export function tickCard(view: EditorView, board: DrawnBoard, card: Card): void {
  const item = card.item;
  if (!item || item.done === null) return;
  const line = view.state.doc.line(item.line);
  const done = !item.done;
  const changes = [{ from: line.from, to: line.to, insert: setItemDone(line.text, done) }];
  const put = done ? doneColumn(board.columns) : 0;
  const columns = put >= 0 ? putCard(board.columns, card.id, put) : null;
  hushGoTo();
  view.dispatch({ changes: columns ? [...changes, fenceEdit(view, board, columns, card.id)] : changes, userEvent: 'input.board' });
  fireNativeHaptic('selection');
  if (columns) reveal(view, card.id);
}

/** The card one lane along, left or right, by its chevrons. */
export function stepCard(view: EditorView, board: DrawnBoard, card: Card, by: number): void {
  view.dispatch({ changes: fenceEdit(view, board, moveCard(board.columns, card.id, by), card.id), userEvent: 'input.board' });
  fireNativeHaptic('selection');
}

/** The fence rewritten: the columns as a person would have typed them, between the two ``` lines. */
function fenceEdit(view: EditorView, board: DrawnBoard, columns: readonly BoardColumn[], moved?: string) {
  const open = view.state.doc.lineAt(board.from);
  const close = view.state.doc.lineAt(board.to);
  // What the board shows, written down: the card the person just moved where they put it, and any other card whose
  // item is ticked in Done, where it is already drawn (core/boards.ts `settleColumns`).
  return { from: open.to + 1, to: close.from - 1, insert: writeBoard(settleColumns(columns, board.items, moved)) };
}

/** Where the card was let go: the fence rewritten, and the tick box brought with it where a Done column is crossed. */
export function landCard(view: EditorView, board: DrawnBoard, card: Card, column: number, index: number): void {
  const was = card.column;
  if (was === column && index === board.cards.filter((other) => other.column === column).findIndex((other) => other.id === card.id)) return;
  const changes = [fenceEdit(view, board, putCardAt(board.columns, card.id, column, index), card.id)];
  // Dragged into Done, the item is done; dragged out of it, it is not. The note says so, not only the board.
  const done = doneColumn(board.columns);
  const item = card.item;
  if (item && item.done !== null && done >= 0 && (was === done) !== (column === done)) {
    const line = view.state.doc.line(item.line);
    changes.push({ from: line.from, to: line.to, insert: setItemDone(line.text, column === done) });
  }
  hushGoTo();
  view.dispatch({ changes, userEvent: 'input.board' });
  fireNativeHaptic('success');
  reveal(view, card.id);
}

/** The card off the board: the fence without it, and its item left exactly where it is in the note (core/boards.ts `withoutCard`). */
export function takeOffCard(view: EditorView, board: DrawnBoard, card: Card): void {
  view.dispatch({ changes: fenceEdit(view, board, withoutCard(board.columns, card.id), card.id), userEvent: 'input.board' });
  fireNativeHaptic('selection');
}
