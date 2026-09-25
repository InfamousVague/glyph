/**
 * Where a dragged tab is, worked out from the row as it was measured: the place in the order it has reached, the group
 * it is over, and how far a flick along the row carries on once the finger has left it.
 *
 * Pure, over boxes the row hands in (notes/useTabDrag.ts measures them), so each rule is a test rather than something
 * to drag about and look at: the tab bar's gesture is the riskiest code in it.
 */

/** A tab in the row, or a folded group's chip, as measured on screen. */
export interface RowStop {
  left: number;
  width: number;
  /** How many tabs it stands for in the order: one for a tab, a folded group's count for its chip. */
  tabs: number;
}

/**
 * Which place in the row `x` is over: how many of the tabs' middles it has passed, counted in tabs.
 *
 * The tab being dragged is not among `stops`, on purpose. It carries an offset so it can follow the finger, which
 * moves the box it would be measured by, and measuring it made the row swap and swap back as the offset chased the
 * answer that had caused it. A folded group is its chip on screen and all its tabs in the order, so passing it passes
 * every one of them.
 */
export function placeAt(stops: readonly RowStop[], x: number): number {
  let place = 0;
  for (const stop of stops) if (x > stop.left + stop.width / 2) place += stop.tabs;
  return place;
}

/** Something a dragged tab can be over: a tab (in `group`, or none), a group's chip, or the + at the row's end. */
export interface DropSpot {
  left: number;
  right: number;
  /** The group a tab dropped here is in: the tab's own group, the chip's group, or null for a tab of none and the +. */
  group: string | null;
}

/**
 * Which group a dragged tab belongs in, by what it is over (Matt: "Allow dragging into tab groups"), the way Chrome
 * decides it: over a tab of a group, or the group's chip, it is in that group; over a tab of none, over the + or past
 * either end of the row, it is in none. Between two things - the few pixels of gap - it stays as it was, which is
 * `undefined`; so is a row with nothing in it but the tab being dragged.
 *
 * It used to be read off where the tab landed: in a group only when dropped between two of its tabs. So a group of
 * one could never be dragged into, nor a group at either end, nor a folded one, which draws no tabs to land between.
 */
export function groupAt(spots: readonly DropSpot[], x: number): string | null | undefined {
  const first = spots[0];
  const last = spots[spots.length - 1];
  if (!first || !last) return undefined;
  if (x < first.left || x > last.right) return null;
  return spots.find((spot) => x >= spot.left && x <= spot.right)?.group;
}

/** A frame at sixty a second, which the coast's slowing is measured in. */
const FRAME_MS = 16.67;
/** How much of its speed a coasting row loses each frame: a fifteenth. */
const FRICTION = 1 / 15;
/** Slower than this - a pixel every few frames - and the row has stopped. */
const STILL = 0.02;

/**
 * One frame of a flick carrying on: the row `ms` further along from `left` at `pace` pixels a millisecond, slowed,
 * and whether it has now stopped - too slow to see, or at either end of a row that scrolls to `end`. A long gap between
 * frames counts as four at most, so a stalled frame cannot fling the row.
 */
export function coasted(left: number, pace: number, ms: number, end: number): { left: number; pace: number; done: boolean } {
  const frames = Math.min(4, ms / FRAME_MS);
  const next = left + pace * FRAME_MS * frames;
  const slowed = pace * (1 - FRICTION) ** frames;
  return { left: next, pace: slowed, done: Math.abs(slowed) < STILL || next <= 0 || next >= end };
}
