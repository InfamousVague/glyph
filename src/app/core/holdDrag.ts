import { HOLD_MS } from './gestures.ts';
import { fireNativeHaptic } from './haptics.ts';

/**
 * The one way a thing is picked up and carried in the app (Matt: "update the clicking and dragging ... the same
 * mechanism as clicking and dragging on board view, right now they seem to diverge"): a ```board's card
 * (editor/boards/drag.ts), a query board's card and a query list's row (editor/QueryView.tsx), and a notebook's pages
 * (book/rowDrag.ts) are all carried by this gesture and drawn by `liftGhost`, so none of them can drift from the others.
 *
 * Press and hold to lift, a mouse as much as a finger. Before the hold is up the pointer is still the page's: a move
 * past `DRAG_SLOP` is a scroll and nothing is taken over. Lifted, the pointer is the drag's - a touch's pan is refused
 * - until it lets go, which drops the thing where it is, or is cancelled.
 *
 * The moves are heard on the window, not the element, and the pointer is never captured: the drag can move the element
 * to where it would land, and a node moved in the page loses a captured pointer, leaving the thing held with its copy on
 * the screen; captured, a mouse's click also went to the card instead of a control in it.
 */

/** How far a pointer resting on a thing may stray before the hold (core/gestures.ts `HOLD_MS`) is up. */
export const DRAG_SLOP = 10;

export interface HoldDragHooks {
  /** Held long enough: the thing is lifted under the pointer. */
  lift: (x: number, y: number) => void;
  /** The lifted thing carried to (x, y). */
  move: (x: number, y: number) => void;
  /** Let go: dropped where it is. */
  drop: (x: number, y: number) => void;
  /** Cancelled, or let go before it was lifted. `lifted` says whether it had been. */
  end?: (lifted: boolean) => void;
}

/**
 * Starts the gesture for a pointer pressed on a thing. Call it from the thing's pointerdown, after the thing has
 * decided the press is its own (not one of its controls'). Answers a way to give the gesture up early.
 */
export function holdDrag(down: PointerEvent, hooks: HoldDragHooks): () => void {
  if (down.button !== 0 && down.pointerType === 'mouse') return () => undefined;
  const startX = down.clientX;
  const startY = down.clientY;
  let lifted = false;
  let finished = false;
  let timer = window.setTimeout(() => {
    timer = 0;
    lifted = true;
    fireNativeHaptic('selection');
    hooks.lift(startX, startY);
  }, HOLD_MS);

  const move = (moving: PointerEvent) => {
    if (moving.pointerId !== down.pointerId) return;
    if (!lifted) {
      // Moved before the hold was up: the pointer is scrolling, so the thing is left alone.
      if (Math.hypot(moving.clientX - startX, moving.clientY - startY) > DRAG_SLOP) finish();
      return;
    }
    moving.preventDefault();
    hooks.move(moving.clientX, moving.clientY);
  };
  const up = (lifting: PointerEvent) => {
    if (lifting.pointerId !== down.pointerId) return;
    // Dropped first, then the gesture's own ending: the thing decides where it landed while it is still lifted.
    if (lifted) hooks.drop(lifting.clientX, lifting.clientY);
    finish();
  };
  const cancel = (cancelling: PointerEvent) => {
    if (cancelling.pointerId === down.pointerId) finish();
  };
  // Held, a finger's movement is the drag and not a scroll. `touch-action` is read when the finger goes down, so
  // setting it at the lift is too late for this touch; a touchmove that is not passive can still refuse the pan.
  const still = (touching: TouchEvent) => {
    if (lifted && touching.cancelable) touching.preventDefault();
  };
  // A finger held still is a long press to the phone as well: at about half a second it selects the words under it, or
  // opens a menu (the note's own, editor/pressAndHold.ts), and the browser cancels the pointer to do it - so a thing
  // lifted at the hold was put down again a moment later, with no time to drag it (Matt: "it just sends the haptic
  // shows the dotted lines very briefly then returns"). While the press is the gesture's, neither happens.
  const refuse = (event: Event) => {
    event.preventDefault();
    event.stopPropagation();
  };
  function finish() {
    if (finished) return;
    finished = true;
    if (timer) window.clearTimeout(timer);
    timer = 0;
    window.removeEventListener('pointermove', move);
    window.removeEventListener('pointerup', up);
    window.removeEventListener('pointercancel', cancel);
    window.removeEventListener('touchmove', still);
    window.removeEventListener('contextmenu', refuse, true);
    document.removeEventListener('selectstart', refuse, true);
    hooks.end?.(lifted);
  }
  window.addEventListener('pointermove', move);
  window.addEventListener('pointerup', up);
  window.addEventListener('pointercancel', cancel);
  window.addEventListener('touchmove', still, { passive: false });
  window.addEventListener('contextmenu', refuse, true);
  document.addEventListener('selectstart', refuse, true);
  return finish;
}

/** A copy of a lifted thing following the pointer overhead (`liftGhost`). */
export interface Ghost {
  follow: (x: number, y: number) => void;
  remove: () => void;
}

/**
 * The thing in the air: a copy of `element` drawn over the whole page, under the pointer at the spot it was taken by,
 * lifted with a shadow - the copy a ```board's card has always had (editor/boards/drag.ts). It lives outside the page,
 * so the look it needs comes with it: `layerClass` for styles written under a parent's classes (the editor's, for a
 * ```board), and the element's own type.
 */
export function liftGhost(element: HTMLElement, x: number, y: number, { layerClass = '', ghostClass = 'app-dragGhost' }: { layerClass?: string; ghostClass?: string } = {}): Ghost {
  const box = element.getBoundingClientRect();
  const ghost = element.cloneNode(true) as HTMLElement;
  ghost.classList.add(ghostClass);
  ghost.removeAttribute('id');
  ghost.setAttribute('aria-hidden', 'true');
  ghost.style.inlineSize = `${box.width}px`;
  const dx = x - box.left;
  const dy = y - box.top;
  const layer = document.createElement('div');
  layer.className = layerClass;
  layer.style.cssText = 'position:fixed;inset:0;z-index:40;pointer-events:none;background:none;border:none;outline:none;display:block';
  const face = window.getComputedStyle(element);
  layer.style.font = face.font;
  layer.style.color = face.color;
  // A table's row is lifted in a table of its own, its cells as wide as they are in the page: on its own it was
  // drawn as one cell's worth of words run together.
  const table = element instanceof HTMLTableRowElement ? element.closest('table') : null;
  if (table) {
    const sheet = document.createElement('table');
    sheet.className = table.className;
    sheet.classList.add(ghostClass);
    sheet.style.inlineSize = `${box.width}px`;
    sheet.style.tableLayout = 'fixed';
    ghost.classList.remove(ghostClass);
    const cells = (element as HTMLTableRowElement).cells;
    [...(ghost as HTMLTableRowElement).cells].forEach((cell, index) => (cell.style.inlineSize = `${cells[index]?.getBoundingClientRect().width ?? 0}px`));
    sheet.append(document.createElement('tbody'));
    sheet.tBodies[0]!.append(ghost);
    layer.append(sheet);
  } else layer.append(ghost);
  document.body.append(layer);
  const moved = table ? (layer.firstElementChild as HTMLElement) : ghost;
  const follow = (to: number, down: number) => {
    moved.style.transform = `translate(${to - dx}px, ${down - dy}px)`;
  };
  follow(x, y);
  return { follow, remove: () => layer.remove() };
}

/** How near an edge a carried thing rolls what is under it, and how fast (editor/boards/scrolling.ts `EDGE`). */
export const ROLL_EDGE = 44;
export const ROLL_STEP = 14;

/**
 * Rolls `scroller` while a carried thing is held near its edges - across for `'x'`, up and down for `'y'` - so a thing
 * can be taken past what it shows. Call `at` with each move; `stop` when the thing is let go. `onRoll` runs each frame
 * that moves it, for a gap to be placed again under a pointer that is still.
 */
export function edgeRoller(scroller: HTMLElement, axis: 'x' | 'y', onRoll?: () => void): { at: (x: number, y: number) => void; stop: () => void } {
  let frame = 0;
  let lean = 0;
  const roll = () => {
    if (axis === 'x') scroller.scrollLeft += lean;
    else scroller.scrollTop += lean;
    onRoll?.();
    frame = requestAnimationFrame(roll);
  };
  return {
    at: (x, y) => {
      const box = scroller.getBoundingClientRect();
      // Only the one the pointer is over rolls: a lane beside the one held near its foot stays where it is.
      const across = axis === 'x' ? y >= box.top && y <= box.bottom : x >= box.left && x <= box.right;
      const pos = axis === 'x' ? x : y;
      const start = axis === 'x' ? box.left : Math.max(box.top, 0);
      const end = axis === 'x' ? box.right : Math.min(box.bottom, window.innerHeight);
      const room = axis === 'x' ? scroller.scrollWidth - scroller.clientWidth : scroller.scrollHeight - scroller.clientHeight;
      const at = axis === 'x' ? scroller.scrollLeft : scroller.scrollTop;
      const next = !across ? 0 : pos < start + ROLL_EDGE && at > 0 ? -ROLL_STEP : pos > end - ROLL_EDGE && at < room - 1 ? ROLL_STEP : 0;
      if (next === lean) return;
      lean = next;
      if (frame) cancelAnimationFrame(frame);
      frame = lean ? requestAnimationFrame(roll) : 0;
    },
    stop: () => {
      if (frame) cancelAnimationFrame(frame);
      frame = 0;
      lean = 0;
    },
  };
}
