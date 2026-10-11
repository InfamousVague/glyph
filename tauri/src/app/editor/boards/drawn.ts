import type { EditorState } from '@codemirror/state';
import { boardsIn, cardsOf, columnFor, itemsIn, type BoardColumn, type Card, type Item } from '../../core/boards.ts';

/**
 * A board as the editor draws it: where its fence is in the document, the columns the fence names, and the cards
 * those columns hold, each card the note's own item (core/boards.ts reads all of it from the markdown).
 */

export interface DrawnBoard {
  /** The whole fence, from the first backtick to the last. */
  from: number;
  to: number;
  columns: BoardColumn[];
  items: Item[];
  cards: Card[];
  /** How tall the lanes are set, in ems (core/boards.ts), or null for their own height. */
  height: number | null;
}

/** Every board in the note that has a body, in order. */
export function boardsOn(state: EditorState): DrawnBoard[] {
  const doc = state.doc.toString();
  const items = itemsIn(doc);
  const all = boardsIn(doc);
  // Every anchor any board names: an item one of them names is never taken for a card whose anchor has slipped.
  const named = new Set(all.flatMap((board) => board.columns.flatMap((column) => column.cards)));
  return all
    .filter((board) => board.to > board.from)
    .map((board) => {
      const columns = board.columns;
      // A ticked item sits in Done wherever the fence has it, so the board never disagrees with the note.
      const cards = cardsOf(columns, items, named).map((card) => (card.item ? { ...card, column: Math.max(0, columnFor(columns, card.item)) } : card));
      return {
        from: state.doc.line(board.from).from,
        to: state.doc.line(board.to).to,
        columns,
        items,
        cards,
        height: board.height,
      };
    });
}

/** What a board looks like now, so the widget is rebuilt only when something on it changed. */
export function faceOf(board: DrawnBoard): string {
  return [
    board.columns.map((column) => `${column.name}:${column.cards.join(',')}`).join('|'),
    board.cards
      .map((card) => `${card.id}@${card.column}:${card.item ? `${card.item.done === null ? '-' : card.item.done ? 'x' : ' '}${card.item.text}` : 'gone'}`)
      .join('|'),
    // A height set, or taken off, redraws the board at it.
    `h${board.height ?? ''}`,
  ].join('||');
}
