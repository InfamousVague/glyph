import { holdDrag, liftGhost, type Ghost } from '../../core/holdDrag.ts';
import type { Card } from '../../core/boards.ts';
import { EDGE, noteScroller } from './scrolling.ts';

/**
 * A card picked up and dragged to where it goes, in its own lane or another (Matt: "add a way to tap and drag to re
 * organize items in lanes").
 *
 * A finger rests on a card to lift it; before the hold is up it is still scrolling the board. Lifted, the card stays
 * in the page as the gap it would leave, a copy follows the finger overhead, and the board, a lane or the note rolls
 * along when the card is held near an edge. Where it is let go is handed back to the board to write (`land`); this
 * module only ever moves the page's own elements, and never the note.
 */

/** How fast a held card near an edge (`EDGE`) rolls the board, a lane or the note along. */
const EDGE_STEP = 14;

/**
 * Press and hold, then drag: the card is lifted under the finger, a gap opens where it would land, and letting go
 * writes it there. Before the hold is up the finger still scrolls the board, which is why nothing is taken over
 * until the card is actually lifted. The gesture is the app's one way of carrying a thing (core/holdDrag.ts), shared
 * with a query's board and rows and a notebook's pages, so they all pick up and carry alike.
 */
export function holdToDrag(card: HTMLElement, held: Card, land: (column: number, index: number) => void): void {
  card.addEventListener('pointerdown', (event: PointerEvent) => {
    if (event.button !== 0 && event.pointerType === 'mouse') return;
    // A press on one of the card's controls is that control's: a finger resting on the tick box a little past the
    // hold used to lift the card instead of ticking it, so a slow tap did nothing and the next landed on the words.
    if ((event.target as Element | null)?.closest?.('.cm-boardTick, .cm-boardMove, .cm-boardAdd, .cm-boardMore, .cm-boardMenu')) return;
    const board = card.closest('.cm-board') as HTMLElement | null;
    if (!board) return;
    // The card answers its own press and hold: the note's long-press menu is for the words, not for a card.
    event.stopPropagation();
    let lift: Lift | null = null;
    holdDrag(event, {
      lift: (x, y) => {
        lift = pickUp(board, card, held, x, y);
      },
      move: (x, y) => {
        if (lift) dragTo(lift, x, y);
      },
      drop: () => {
        const landed = lift;
        if (!landed) return;
        const column = landed.column;
        const index = Math.max(0, landed.index);
        // Put down first, then written: the note's change draws the board again from what it says.
        putDown(landed);
        lift = null;
        land(column, index);
      },
      end: () => {
        if (lift) putDown(lift);
        lift = null;
      },
    });
  });
}

/**
 * A card in the air: what was picked up, and where it would land.
 *
 * The card itself stays in the page as the gap it would leave, emptied out and outlined, and it is that element
 * which moves from place to place as the finger goes: the space under the finger is always the space the card will
 * take. A copy of it follows the finger overhead.
 */
interface Lift {
  board: HTMLElement;
  card: HTMLElement;
  /** The copy following the finger (core/holdDrag.ts `liftGhost`). */
  ghost: Ghost;
  column: number;
  index: number;
  /** Where the finger is, for placing the gap again while something scrolls under a finger that is still. */
  x: number;
  y: number;
  /** The board scrolling itself while a card is held against its edge. */
  scroll: number;
  /** A lane, or the note, scrolling while a card is held near its top or foot. */
  rise: number;
  /** What is rising, so the roll can be stopped when the finger moves to another. */
  rising: HTMLElement | null;
}

function pickUp(board: HTMLElement, card: HTMLElement, held: Card, x: number, y: number): Lift {
  const box = card.getBoundingClientRect();
  // The copy is drawn over the whole page, so it lives outside the note - but the board's look is written under the
  // editor's own classes (EditorView.baseTheme), so it goes in a layer that carries them. Straight on the body it had
  // no look at all, and was drawn a screen below the finger.
  const editor = board.closest<HTMLElement>('.cm-editor');
  const ghost = liftGhost(card, x, y, { layerClass: editor?.className ?? '', ghostClass: 'cm-boardGhost' });

  card.dataset.lifted = '';
  card.style.blockSize = `${box.height}px`;
  // Held, the finger drags rather than scrolls; the board is scrolled for it at the edges instead.
  card.style.touchAction = 'none';
  board.dataset.holding = '';

  const lift: Lift = { board, card, ghost, column: held.column, index: 0, x, y, scroll: 0, rise: 0, rising: null };
  dragTo(lift, x, y);
  return lift;
}

/** The held card follows the finger, the gap goes where it would land, and the board scrolls at its edges. */
function dragTo(lift: Lift, x: number, y: number): void {
  lift.x = x;
  lift.y = y;
  lift.ghost.follow(x, y);

  const box = lift.board.getBoundingClientRect();
  const edge = x < box.left + EDGE ? -EDGE_STEP : x > box.right - EDGE ? EDGE_STEP : 0;
  if (edge && !lift.scroll) {
    const roll = () => {
      lift.board.scrollLeft += edge;
      placeGap(lift);
      lift.scroll = requestAnimationFrame(roll);
    };
    lift.scroll = requestAnimationFrame(roll);
  } else if (!edge && lift.scroll) {
    cancelAnimationFrame(lift.scroll);
    lift.scroll = 0;
  }

  const stack = placeGap(lift);
  if (!stack) return;

  // Up and down: a lane with more cards than it shows rolls itself when the card is held near its top or foot, so a
  // card can be dropped below what it shows. A lane that shows every card is rolled by the note instead, near the top
  // or foot of the screen, so a card can be taken down a lane longer than the screen.
  const roller = stack.scrollHeight - stack.clientHeight > 1 ? stack : noteScroller(lift.board);
  const lean = roller ? leanAt(roller, y, roller !== stack) : 0;
  if (lift.rise && (lift.rising !== roller || !lean)) {
    cancelAnimationFrame(lift.rise);
    lift.rise = 0;
    lift.rising = null;
  }
  if (roller && lean && !lift.rise) {
    lift.rising = roller;
    const roll = () => {
      roller.scrollTop += lean;
      placeGap(lift);
      lift.rise = requestAnimationFrame(roll);
    };
    lift.rise = requestAnimationFrame(roll);
  }
}

/** The lane under the finger gets the gap, above the first card whose middle the finger is over. */
function placeGap(lift: Lift): HTMLElement | null {
  const { x, y } = lift;
  const stacks = [...lift.board.querySelectorAll<HTMLElement>('.cm-boardStack')];
  if (!stacks.length) return null;
  // The column under the finger, or the nearest one when the finger is past the end of the board.
  const stack =
    stacks.find((pane) => {
      const at = pane.getBoundingClientRect();
      return x >= at.left && x <= at.right;
    }) ??
    stacks.reduce((near, pane) => {
      const gap = (rect: DOMRect) => (x < rect.left ? rect.left - x : x - rect.right);
      return gap(pane.getBoundingClientRect()) < gap(near.getBoundingClientRect()) ? pane : near;
    }, stacks[0]!);

  for (const pane of stacks) if (pane !== stack) delete pane.dataset.over;
  stack.dataset.over = '';

  const cards = [...stack.querySelectorAll<HTMLElement>('.cm-boardCard')].filter((other) => other !== lift.card);
  const before = cards.find((other) => {
    const at = other.getBoundingClientRect();
    return y < at.top + at.height / 2;
  });
  const place = before ?? stack.querySelector('.cm-boardEmpty');
  // Moved only when it would land somewhere else: moving it again and again as a roll goes by is work for nothing.
  if (lift.card.parentElement !== stack || lift.card.nextElementSibling !== place) stack.insertBefore(lift.card, place);

  lift.column = Number(stack.dataset.column ?? 0);
  lift.index = [...stack.querySelectorAll<HTMLElement>('.cm-boardCard')].indexOf(lift.card);
  return stack;
}

/**
 * How fast to roll `roller` for a finger at `y`: up near its top, down near its foot, nothing between. The note's
 * top is under its header, so the zone starts below that (`--wisp-under`, art/wispEdge.ts), and is wider, since the
 * finger is near the edge of the screen.
 */
function leanAt(roller: HTMLElement, y: number, note: boolean): number {
  const shown = roller.getBoundingClientRect();
  const under = note ? parseFloat(window.getComputedStyle(roller).getPropertyValue('--wisp-under')) || 0 : 0;
  const top = Math.max(shown.top, 0) + under;
  const bottom = Math.min(shown.bottom, window.innerHeight);
  const zone = note ? EDGE * 2 : EDGE;
  if (y < top + zone && roller.scrollTop > 0) return -EDGE_STEP;
  if (y > bottom - zone && roller.scrollTop + roller.clientHeight < roller.scrollHeight - 1) return EDGE_STEP;
  return 0;
}

/** The card set down: the copy overhead goes, and the card is a card again, wherever it ended up. */
function putDown(lift: Lift): void {
  if (lift.scroll) cancelAnimationFrame(lift.scroll);
  if (lift.rise) cancelAnimationFrame(lift.rise);
  // The layer the copy was drawn in goes with it.
  lift.ghost.remove();
  delete lift.card.dataset.lifted;
  lift.card.style.removeProperty('block-size');
  lift.card.style.removeProperty('touch-action');
  delete lift.board.dataset.holding;
  for (const pane of lift.board.querySelectorAll<HTMLElement>('.cm-boardStack')) delete pane.dataset.over;
}
