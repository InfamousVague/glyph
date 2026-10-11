import type { EditorView } from '@codemirror/view';
import { addToBoard, boardAt, boardCopy, boardFromList, listAround } from '../core/boards.ts';

/**
 * What the note offers to do with boards, where the caret is (core/boards.ts has the syntax, editor/boards.ts draws
 * them): copy a board, add an item to its list's board, make a board of a list. The press-and-hold menu offers these
 * (editor/ContextMenu.tsx), and the More sheet's Make a board says what it made in the same words (editor/NoteScreen.tsx).
 *
 * Each change is one dispatch, so one Undo takes it back, and each is marked `input.board`, so the typing smoke leaves
 * it alone: none of it is a letter someone wrote (editor/wispArrivals.ts).
 */

/** The lines of a list, first and last, 1-based. */
export interface LineRange {
  from: number;
  to: number;
}

export interface BoardOffers {
  /** The board the caret is on, by its fence's first and last lines, or null. */
  fence: LineRange | null;
  /** That board as words - the fence and the items it names - to copy, since a board drawn as columns cannot be dragged over. */
  copy: string | null;
  /** The caret's item could join its list's board: other items in the list are on one already. */
  joinable: boolean;
  /** The lines that would become a board of their own: the selection when it spans lines, else the list the caret is in. */
  list: LineRange | null;
}

/** What can be done with boards at the caret in `view`. */
export function boardOffers(view: EditorView): BoardOffers {
  const doc = view.state.doc;
  const text = doc.toString();
  const caret = doc.lineAt(view.state.selection.main.head).number;
  const fence = boardAt(text, caret);
  // Not offered on a board, or on a list that already has one above it (boardFromList says so).
  const list = (() => {
    if (fence) return null;
    const { from: start, to: end } = view.state.selection.main;
    const first = doc.lineAt(start).number;
    const last = doc.lineAt(end).number;
    return last > first ? { from: first, to: last } : listAround(text, caret);
  })();
  return {
    fence,
    copy: boardCopy(text, caret),
    joinable: addToBoard(text, caret) !== null,
    list: list && boardFromList(text, list.from, list.to) ? list : null,
  };
}

/**
 * Selects the whole of the board on `fence`, so a row that works on lines works on all of it: pressed on a drawn board
 * the caret is on one of its column lines, and duplicating or deleting that alone would leave half a board behind.
 */
export function selectBoard(view: EditorView, fence: LineRange): void {
  const open = view.state.doc.line(fence.from);
  const close = view.state.doc.line(fence.to);
  view.dispatch({ selection: { anchor: open.from, head: close.to } });
}

/**
 * The list on `lines` as a board of its own, set in just above it (core/boards.ts `boardFromList`; Matt: "add ability
 * to auto list a section of list items into a board"). Answers what it made, or null when those lines make none.
 */
export function makeListBoard(view: EditorView, lines: LineRange): { cards: number; done: number } | null {
  const made = boardFromList(view.state.doc.toString(), lines.from, lines.to);
  if (!made) return null;
  const doc = view.state.doc;
  // The item lines, and the fence put in at the start of the list's first line: where that line changes too, the
  // fence goes in front of its new words, as one change.
  const changes = made.lines.map(({ number, text }) => {
    const line = doc.line(number);
    return { from: line.from, to: line.to, insert: number === made.fence.before ? `${made.fence.text}${text}` : text };
  });
  if (!made.lines.some((line) => line.number === made.fence.before)) {
    const at = doc.line(made.fence.before).from;
    changes.push({ from: at, to: at, insert: made.fence.text });
  }
  view.dispatch({ changes, userEvent: 'input.board' });
  return made;
}

/**
 * The item on line `lineNumber` (1-based) joins its list's board: the line gains its anchor, and the fence gains the card
 * (core/boards.ts `addToBoard`; Matt: "add an 'add to board' option when other items in the list are in a board
 * already"). The line is the one the row was offered for, not wherever the caret has gone since. Answers the column
 * it went into, since the board may be well off the screen and where it went is said aloud; null for none.
 */
export function joinBoard(view: EditorView, lineNumber: number): string | null {
  const doc = view.state.doc;
  const added = addToBoard(doc.toString(), lineNumber);
  if (!added) return null;
  const open = doc.line(added.fence.from);
  const close = doc.line(added.fence.to);
  const changes = [{ from: open.to + 1, to: close.from - 1, insert: added.fence.body }];
  if (added.line) {
    const line = doc.line(added.line.number);
    changes.push({ from: line.from, to: line.to, insert: added.line.text });
  }
  view.dispatch({ changes, userEvent: 'input.board' });
  return added.column;
}

/** What a board made of a list is said as: "3 items are now cards, 1 in Done." - `becomes` is "cards" or "a board". */
export function boardMadeWords(made: { cards: number; done: number }, becomes: 'cards' | 'a board'): string {
  return `${made.cards} ${made.cards === 1 ? 'item is' : 'items are'} now ${becomes}${made.done ? `, ${made.done} in Done` : ''}.`;
}
