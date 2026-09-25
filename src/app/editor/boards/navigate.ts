import { EditorSelection } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { wordsEnd } from '../../core/itemSyntax.ts';
import { EDGE, noteScroller } from './scrolling.ts';

/**
 * Getting around from a board: a card's words take the caret to its item's line in the note, a card that has just
 * moved is shown where it landed, and for a moment after a card's status changes a press on its words is not taken
 * as "go to the line".
 */

/** The caret put on a line of the note, and the note scrolled to it. */
export function goToLine(view: EditorView, line: number): void {
  if (line < 1 || line > view.state.doc.lines) return;
  const at = view.state.doc.line(line);
  // At the end of the item's words, not the end of the line: typed there, a letter would go into the anchor after them.
  const caret = at.from + wordsEnd(at.text);
  view.dispatch({ selection: EditorSelection.cursor(caret), effects: EditorView.scrollIntoView(at.from, { y: 'center' }), scrollIntoView: true });
  view.focus();
}

/**
 * A status changed on the board - a card ticked, or dropped in another lane - keeps the person on the board (Matt:
 * "when changing the status of a ticket to done it jumps me way down to the item in the list instead of moving me to
 * view the task on the board"). For a moment after one, a press on a card's words is not taken as "go to the line":
 * on a phone the tick box sits beside the words, and a finger a little off, or the click a drop leaves behind, landed
 * on them and scrolled the note away.
 */
const QUIET_MS = 700;
let quietUntil = 0;

export function hushGoTo(): void {
  quietUntil = Date.now() + QUIET_MS;
}

/** Whether a status has just changed on a board, so a press on a card's words is a near miss and not "go to the line". */
export function hushed(): boolean {
  return Date.now() < quietUntil;
}

/**
 * The card where it landed, shown: its lane brought across the board and the card brought into its lane, then a short
 * flash so the eye finds it. The note is moved only as far as it takes to show the card, when a lane that shows every
 * card has put it past the top or foot of the screen.
 */
export function reveal(view: EditorView, id: string): void {
  // Twice over a frame: the board is redrawn by the change that moved the card, and the card is in its lane after that.
  requestAnimationFrame(() =>
    requestAnimationFrame(() => {
      const card = view.dom.querySelector<HTMLElement>(`.cm-boardCard[data-card="${CSS.escape(id)}"]`);
      const board = card?.closest<HTMLElement>('.cm-board');
      const lane = card?.closest<HTMLElement>('.cm-boardColumn');
      const stack = card?.closest<HTMLElement>('.cm-boardStack');
      if (!card || !board || !lane || !stack) return;
      const boardBox = board.getBoundingClientRect();
      const laneBox = lane.getBoundingClientRect();
      if (laneBox.left < boardBox.left || laneBox.right > boardBox.right) {
        board.scrollTo({ left: board.scrollLeft + laneBox.left - boardBox.left, behavior: 'smooth' });
      }
      const stackBox = stack.getBoundingClientRect();
      const cardBox = card.getBoundingClientRect();
      if (stack.scrollHeight > stack.clientHeight + 1) {
        if (cardBox.top < stackBox.top || cardBox.bottom > stackBox.bottom) {
          stack.scrollTo({ top: stack.scrollTop + cardBox.top - stackBox.top - 8, behavior: 'smooth' });
        }
      } else {
        const note = noteScroller(board);
        if (note) {
          const shown = note.getBoundingClientRect();
          const top = Math.max(shown.top, 0) + (parseFloat(window.getComputedStyle(note).getPropertyValue('--wisp-under')) || 0);
          const bottom = Math.min(shown.bottom, window.innerHeight);
          const by = cardBox.bottom > bottom - EDGE ? cardBox.bottom - bottom + EDGE : cardBox.top < top + 8 ? cardBox.top - top - 8 : 0;
          if (by) note.scrollBy({ top: by, behavior: 'smooth' });
        }
      }
      card.dataset.arrived = '';
      window.setTimeout(() => delete card.dataset.arrived, 900);
    }),
  );
}
