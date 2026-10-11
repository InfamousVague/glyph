import type { EditorView } from '@codemirror/view';
import { fireNativeHaptic } from '../../core/haptics.ts';
import { BOARD_HEIGHT, clampHeight, withBoardHeight } from '../../core/boards.ts';

/**
 * The line under a board, which sets how tall its lanes are, and the board drawn at the height the fence sets.
 */

/**
 * How tall a board is, set by dragging the line under it (Matt: "make board height configurable with glacierUI split
 * view"). The line is Glacier's split-pane divider (@glacier/react `ResizableSplitPane`), made for a board that sits
 * in a scrolling note rather than in a box of its own: a hairline with a grip, a separator a screen reader can set,
 * dragged, stepped with the arrow keys, sent to either end with Home and End, and put back with a double tap. The
 * grip shows all the time, since a phone has no hover to show it on, and the line takes a finger's width of touch.
 *
 * The height is the lanes', in their own ems, so a board keeps its number of cards when the text size changes. It is
 * written into the board's fence when the finger lifts (core/boards.ts `withBoardHeight`), so it goes wherever the
 * note goes; while the finger moves it is only a style, and nothing is written.
 */
export function heightSplit(view: EditorView, wrap: HTMLElement): HTMLElement {
  const split = document.createElement('div');
  split.className = 'cm-boardSplit';
  split.setAttribute('role', 'separator');
  split.setAttribute('aria-orientation', 'horizontal');
  split.setAttribute('aria-label', 'Board height');
  split.setAttribute('aria-valuemin', String(BOARD_HEIGHT.min));
  split.setAttribute('aria-valuemax', String(BOARD_HEIGHT.max));
  split.tabIndex = 0;
  split.title = 'Drag to resize the board';
  // The handle: Glacier's grip pill at the middle of the line under the board (Matt: "Add resize handle in the bottom
  // middle of board to resize", then "the resize handle under the board changed and doesnt match the simplistic
  // version anymore").
  const grip = document.createElement('span');
  grip.className = 'cm-boardGrip';
  grip.setAttribute('aria-hidden', 'true');
  split.append(grip);

  // The note must not take the press as a caret move, or the finger's drag as a text selection.
  split.addEventListener('mousedown', (event) => event.preventDefault());
  split.addEventListener('pointerdown', (event) => dragHeight(view, wrap, split, event));
  split.addEventListener('dblclick', (event) => {
    event.preventDefault();
    writeHeight(view, wrap, null);
  });
  split.addEventListener('keydown', (event) => {
    const now = laneHeight(wrap);
    const next =
      event.key === 'ArrowUp' ? now - 1 : event.key === 'ArrowDown' ? now + 1 : event.key === 'Home' ? BOARD_HEIGHT.min : event.key === 'End' ? BOARD_HEIGHT.max : null;
    if (next === null) return;
    event.preventDefault();
    writeHeight(view, wrap, clampHeight(next));
  });
  return split;
}

/** The board drawn at its set height, or its own; and the divider saying which. */
export function sized(board: HTMLElement, split: HTMLElement, height: number | null): void {
  if (height === null) {
    board.style.removeProperty('--cm-lane-height');
    delete board.dataset.sized;
  } else {
    board.style.setProperty('--cm-lane-height', `${height}em`);
    board.dataset.sized = '';
    // A height from the fence is the height: no pin under it.
    board.style.removeProperty('--cm-board-pin');
    delete board.dataset.pinned;
  }
  if (height !== null) {
    split.setAttribute('aria-valuenow', String(height));
    return;
  }
  // Left to itself, the height is measured, and a board just built is not on the page to be measured until the
  // frame after.
  const measure = () => split.setAttribute('aria-valuenow', String(Math.round(laneHeightOf(board))));
  if (board.isConnected) measure();
  else requestAnimationFrame(measure);
}

/** How tall the lanes are drawn now, in their own ems. */
function laneHeight(wrap: HTMLElement): number {
  const board = wrap.querySelector<HTMLElement>(':scope > .cm-board');
  return board ? laneHeightOf(board) : BOARD_HEIGHT.min;
}

function laneHeightOf(board: HTMLElement): number {
  // Set, the height is the one the fence gave; nothing to measure.
  const set = parseFloat(board.style.getPropertyValue('--cm-lane-height'));
  if (board.hasAttribute('data-sized') && Number.isFinite(set)) return set;
  const stack = board.querySelector<HTMLElement>('.cm-boardStack');
  if (!stack) return BOARD_HEIGHT.min;
  const em = parseFloat(window.getComputedStyle(stack).fontSize) || 16;
  // Left to themselves, the lanes are as tall as the tallest one's cards.
  const px = stack.getBoundingClientRect().height;
  return px > 0 ? px / em : BOARD_HEIGHT.min;
}

/** The height written into the board's fence, or taken out of it with null: one change, one undo. */
function writeHeight(view: EditorView, wrap: HTMLElement, height: number | null): void {
  const open = view.state.doc.lineAt(view.posAtDOM(wrap));
  const next = withBoardHeight(open.text, height);
  if (next !== open.text) view.dispatch({ changes: { from: open.from, to: open.to, insert: next }, userEvent: 'input.board' });
}

/**
 * The line under a board, dragged. The lanes follow the finger as a style; letting go writes the height. Heard on the
 * window and by pointer id, as the card drag is, so a pointer that wanders off the line still finishes the drag.
 */
function dragHeight(view: EditorView, wrap: HTMLElement, split: HTMLElement, event: PointerEvent): void {
  if (event.button !== 0 && event.pointerType === 'mouse') return;
  const board = wrap.querySelector<HTMLElement>(':scope > .cm-board');
  if (!board) return;
  event.preventDefault();
  event.stopPropagation();
  const stack = board.querySelector<HTMLElement>('.cm-boardStack');
  const em = stack ? parseFloat(window.getComputedStyle(stack).fontSize) || 16 : 16;
  const was = board.style.getPropertyValue('--cm-lane-height');
  const wasSized = board.hasAttribute('data-sized');
  const from = laneHeightOf(board);
  const startY = event.clientY;
  let height = from;
  let edge: 'min' | 'max' | null = null;
  split.dataset.dragging = '';

  const move = (moving: PointerEvent) => {
    if (moving.pointerId !== event.pointerId) return;
    moving.preventDefault();
    const wanted = from + (moving.clientY - startY) / em;
    height = clampHeight(wanted);
    board.style.setProperty('--cm-lane-height', `${height}em`);
    board.dataset.sized = '';
    split.setAttribute('aria-valuenow', String(height));
    // A buzz at either end, as Glacier's divider gives, so the finger knows it can go no further.
    const at = wanted <= BOARD_HEIGHT.min ? 'min' : wanted >= BOARD_HEIGHT.max ? 'max' : null;
    if (at !== edge) {
      edge = at;
      if (at) fireNativeHaptic('medium');
    }
  };
  const still = (touching: TouchEvent) => {
    if (touching.cancelable) touching.preventDefault();
  };
  const done = (write: boolean) => {
    window.removeEventListener('pointermove', move);
    window.removeEventListener('pointerup', up);
    window.removeEventListener('pointercancel', cancel);
    window.removeEventListener('touchmove', still);
    delete split.dataset.dragging;
    if (write && Math.abs(height - from) >= 0.5) {
      writeHeight(view, wrap, height);
      return;
    }
    // Let go where it started, or called off: the board as it was.
    if (was) board.style.setProperty('--cm-lane-height', was);
    else board.style.removeProperty('--cm-lane-height');
    if (wasSized) board.dataset.sized = '';
    else delete board.dataset.sized;
  };
  const up = (lifting: PointerEvent) => {
    if (lifting.pointerId === event.pointerId) done(true);
  };
  const cancel = (cancelling: PointerEvent) => {
    if (cancelling.pointerId === event.pointerId) done(false);
  };
  window.addEventListener('pointermove', move);
  window.addEventListener('pointerup', up);
  window.addEventListener('pointercancel', cancel);
  window.addEventListener('touchmove', still, { passive: false });
}
