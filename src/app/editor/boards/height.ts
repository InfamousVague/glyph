import type { EditorView } from '@codemirror/view';
import { wispFoot, wispFootFade } from '../../art/wispFoot.ts';
import { markOf, unmarked } from '../../core/itemLinks.ts';
import { cardText } from '../../core/boards.ts';
import { heightMemory } from '../heightMemory.ts';
import type { DrawnBoard } from './drawn.ts';
import { BOARD_TYPE, LANE_FOOT } from './theme.ts';

/**
 * How tall a board is on the page: the height it is held at while it is on the screen, so a card moving lanes never
 * moves the note under a finger (`pin`); the smoke at the foot of a lane with more cards than it shows (`laneFoot`);
 * and the height it is remembered at, so the editor knows it before the board is drawn (`estimatedHeight`).
 *
 * The height a person sets by dragging the line under a board is the divider's (editor/boards/divider.ts).
 */

/**
 * A board on the page, kept an eye on: its size, for the lanes' feet and for the height it is remembered at. The
 * observer goes when CodeMirror takes the board off the page (`unwatch`, from the widget's `destroy`).
 */
const watching = new WeakMap<HTMLElement, ResizeObserver>();
/** What each board on the page shows, for remembering its height by. */
const faces = new WeakMap<HTMLElement, string>();

export function watch(view: EditorView, wrap: HTMLElement, board: HTMLElement, face: string): void {
  faces.set(wrap, face);
  // Drawn or redrawn: the lanes are new, and the board may be a new height, once it is laid out.
  view.requestMeasure({
    read: () => null,
    write: () => {
      // Its own height, held while it is on the screen, so a card moving lanes never moves the note under a finger.
      pin(board);
      lanesFoot(board);
      remember(wrap, board);
    },
  });
  if (watching.has(wrap) || typeof ResizeObserver === 'undefined') return;
  const observer = new ResizeObserver(() => {
    repin(board);
    lanesFoot(board);
    remember(wrap, board);
  });
  observer.observe(board);
  watching.set(wrap, observer);
}

/** The observer a board was watched with, let go when CodeMirror takes the board off the page. */
export function unwatch(wrap: HTMLElement): void {
  watching.get(wrap)?.disconnect();
  watching.delete(wrap);
}

/**
 * A lane with more cards below than it shows: its foot goes to smoke, the app's wisp edge (art/wispFoot.ts), and
 * fades into the lane. Only a board with a set height has lanes that scroll; left to itself a lane shows every card.
 */
export function laneFoot(stack: HTMLElement): void {
  const board = stack.closest<HTMLElement>('.cm-board');
  const more = Boolean(board?.hasAttribute('data-sized')) && stack.scrollHeight - stack.clientHeight - stack.scrollTop > 4;
  stack.toggleAttribute('data-more', more);
  const smoke = more ? (board?.dataset.wisp ?? '') : '';
  if ((stack.dataset.smoke ?? '') === smoke) return;
  if (smoke) {
    stack.dataset.smoke = smoke;
    stack.style.filter = smoke;
    // The fade the smoke sits under, from the same place the lip is (art/wispFoot.ts): a longer one would rub out
    // the strongest bend, which is what the page's foot read as a plain gradient for. By the lane's own height,
    // since a short lane's band is scaled down to fit it and its fade has to come down with it. Without smoke the
    // lane keeps the em fade in the stylesheet, where there is no lip for it to agree with.
    stack.style.setProperty('--cm-lane-fade', `${wispFootFade(stack.offsetHeight)}px`);
  } else {
    delete stack.dataset.smoke;
    stack.style.removeProperty('filter');
    stack.style.removeProperty('--cm-lane-fade');
  }
}

/** Every lane's foot, and the smoke they wear: one filter for the board, made for the lanes' height. */
function lanesFoot(board: HTMLElement): void {
  const stack = board.querySelector<HTMLElement>('.cm-boardStack');
  // While the line under the board is being dragged the height changes by the pixel, and a filter for each would be
  // made and thrown away: the plain fade does until the finger lifts.
  const moving = board.parentElement?.querySelector(':scope > .cm-boardSplit[data-dragging]');
  const smoke = stack && board.hasAttribute('data-sized') && !moving ? wispFoot(stack.offsetHeight, stack.offsetWidth) : null;
  if (smoke) board.dataset.wisp = smoke;
  else delete board.dataset.wisp;
  for (const lane of board.querySelectorAll<HTMLElement>('.cm-boardStack')) laneFoot(lane);
}

/**
 * How tall boards are drawn, remembered by what they show (drawn.ts `faceOf`), in memory and across launches
 * (editor/heightMemory.ts): a note opened again knows its boards' heights before they are on the screen
 * (`estimatedHeight`). A board being typed into, having a card dragged, or having its height dragged is not at its
 * own height, and is not remembered.
 */
const heights = heightMemory('glyph-board-heights', 300, (px) => Math.round(px * 10) / 10);
/** The type a board and the note around it were last drawn in, in px, for guessing at a board not yet drawn. */
const drawnType = { board: 16.64, note: 19.35 };

function remember(wrap: HTMLElement, board: HTMLElement): void {
  const face = faces.get(wrap);
  if (!face || !wrap.isConnected || board.hasAttribute('data-holding')) return;
  if (wrap.querySelector('.cm-boardCompose, .cm-boardSplit[data-dragging]')) return;
  const height = wrap.getBoundingClientRect().height;
  if (!(height > 0)) return;
  drawnType.board = parseFloat(window.getComputedStyle(board).fontSize) || drawnType.board;
  drawnType.note = parseFloat(window.getComputedStyle(wrap).fontSize) || drawnType.note;
  heights.keep(face, height);
}

/** The room above a board, the line under it and the space around that, in the note's ems (`.cm-boardWrap`, `.cm-boardSplit`). */
const WRAP_ROOM = 0.4 * BOARD_TYPE + 0.3 + 1 + 0.5;

/**
 * A board's height before it has ever been drawn, worked out the way it is laid out (theme.ts): its lanes' heads,
 * the tallest lane's cards at one to three lines each by how many words they have, and the line under it. Near enough
 * that the editor's correction, when the board is drawn, is small.
 */
function guessHeight(board: DrawnBoard): number {
  const em = drawnType.board;
  // A column is min(78vw, 16rem) across.
  const rem = typeof window === 'undefined' ? 16 : parseFloat(window.getComputedStyle(document.documentElement).fontSize) || 16;
  const across = typeof window === 'undefined' ? 256 : Math.min(window.innerWidth * 0.78, 16 * rem);
  // A card's words have its width less the tick, the gaps and the padding, at about 0.45em a letter.
  const perLine = Math.max(8, (across - 3.7 * em) / (0.45 * em));
  const lane = (column: number): number => {
    const cards = board.cards.filter((card) => card.column === column);
    // An empty lane: its picture and its words.
    if (!cards.length) return 4.95;
    const tall = cards.reduce((sum, card) => {
      const text = card.item?.text ?? '';
      const words = card.item ? cardText(markOf(text) ? unmarked(text) : text).length : card.id.length + 1;
      const lines = Math.min(3, Math.max(1, Math.ceil(words / perLine)));
      return sum + 2.41 + 1.35 * lines + 0.4;
    }, -0.4);
    return tall + LANE_FOOT;
  };
  const lanes = board.height ?? Math.max(2.5, ...board.columns.map((_, index) => lane(index)));
  // The board's padding, a column's padding, its head and the gap under it; then the lanes; then the room around.
  return Math.round((em * (0.6 + 0.7 + 1.6 + 0.4 + lanes) + drawnType.note * WRAP_ROOM + 1) * 10) / 10;
}

/**
 * How tall the board is before it is drawn: the height it was last drawn at, or a guess from its cards. Left to
 * CodeMirror, a board not yet on the screen was one line tall, and grew by a screenful as it came into view; the
 * editor then moved the note to keep its place, and on a phone that move stops a fling dead (Matt: "scrolling past
 * boards is glitchy and stops scroll momentum").
 */
export function estimatedHeight(board: DrawnBoard, face: string): number {
  return heights.known(face) ?? guessHeight(board);
}

/**
 * A board with no height of its own, pinned to the height it was first drawn at (Matt: "Clicking an item to toggle
 * the done state on and off is now super laggy and doesn't actually change the state off").
 *
 * The lanes are as tall as the tallest lane's cards, so moving a card between lanes changed the board's height, and
 * everything under it jumped - by 48px in the case Matt hit. The second tap then landed on whatever had slid under
 * the finger: the next item, or the board itself. Nothing was broken about the tick; the note had moved.
 *
 * So a board's height is settled when it is drawn and held there: ticking, dragging, adding and taking off all leave
 * it exactly where it is, and the lanes scroll inside it as a board with a set height does. It is measured once,
 * from the height the board would have chosen for itself, and let go when the board is built again - the note
 * reopened, its columns changed - or when the line under it is dragged, which sets a real height in the fence.
 */
function pin(board: HTMLElement): void {
  if (board.dataset.pinned !== undefined || board.hasAttribute('data-sized') || !board.isConnected) return;
  const stack = board.querySelector<HTMLElement>('.cm-boardStack');
  const tall = stack?.getBoundingClientRect().height ?? 0;
  if (!stack || tall <= 0) return;
  board.style.setProperty('--cm-board-pin', `${Math.round(tall)}px`);
  board.dataset.pinned = '';
  // The type it was measured in: a board pinned in px must be measured again when the words change size.
  board.dataset.pinnedType = window.getComputedStyle(stack).fontSize;
}

/** A pinned board whose words have changed size is measured again: the pin is px, and a px height ages. */
function repin(board: HTMLElement): void {
  const stack = board.querySelector<HTMLElement>('.cm-boardStack');
  if (board.dataset.pinned === undefined || !stack) return;
  if (window.getComputedStyle(stack).fontSize === board.dataset.pinnedType) return;
  board.style.removeProperty('--cm-board-pin');
  delete board.dataset.pinned;
  delete board.dataset.pinnedType;
  pin(board);
}
