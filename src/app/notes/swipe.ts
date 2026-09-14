/**
 * The pure half of a swipeable row: which action a distance arms, and where a
 * touch may start a swipe at all. Kept apart from SwipeRow.tsx so it can be
 * tested without a DOM, and because a component file may only export components.
 */

export type SwipeTone = 'accent' | 'neutral' | 'danger';

export interface SwipeAction {
  id: string;
  /** The word shown behind the row, and the action's name for assistive tech. */
  label: string;
  /** The picture behind the row, drawn above the word. */
  icon: 'pin' | 'unpin' | 'archive' | 'restore' | 'delete';
  tone: SwipeTone;
  /** Fraction of the row's width at which this action arms. */
  detent: number;
  /** Slide the row away before acting: for actions that take it out of this list. */
  removes?: boolean;
}

/** The furthest action armed at `distance` (a fraction of the width, always positive), or null. */
export function armedAt(actions: readonly SwipeAction[], distance: number): SwipeAction | null {
  let armed: SwipeAction | null = null;
  for (const action of actions) if (distance >= action.detent) armed = action;
  return armed;
}

/**
 * Android's back gesture owns a band at each edge of the screen - wider on a
 * Fold's inner display, and adjustable by the person - and a row swipe that
 * starts there would fight it. 28 px is the default inset; a touch that begins
 * inside it is left to the system.
 */
export const EDGE_PX = 28;

export function startsInGestureEdge(clientX: number, viewportWidth: number): boolean {
  return clientX < EDGE_PX || clientX > viewportWidth - EDGE_PX;
}

/**
 * The row's offset for a finger `moveX` px from where it started. It follows
 * the finger to a little past the last detent, then only a quarter as fast: a
 * rubber band that says "nothing further this way" without a hard stop.
 */
export function followFinger(moveX: number, lastDetent: number, width: number): number {
  const limit = (lastDetent + 0.18) * width;
  const over = Math.abs(moveX) - limit;
  return over > 0 ? Math.sign(moveX) * (limit + over * 0.25) : moveX;
}
