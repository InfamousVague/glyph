/**
 * The pure half of pulling a page down to refresh it (shell/PullToRefresh.tsx; docs/DESIGN.md §152): how far the page
 * follows a finger, where the detent is, and which touches are a pull at all. Kept apart so each rule is a test, and
 * because a component file may only export components.
 *
 * Matt: "add a pull to refresh feature on notes and the home page". The page follows the finger at half its travel,
 * so it feels weighted, to the detent; past it only a sixth as fast, a rubber band that says there is nothing further
 * to pull, and never more than `PULL_MOST_PX`.
 */

/** How far the page must come down for a let-go to refresh it, in px. */
export const PULL_DETENT_PX = 64;
/** The furthest the page comes down however far the finger goes. */
export const PULL_MOST_PX = 110;
/** Where the page rests while the refresh runs: enough to show the ring spinning above it. */
export const PULL_REST_PX = 52;
/** A refresh shown for less than this reads as a flicker, so the ring spins at least this long. */
export const PULL_LEAST_MS = 500;

/** How far to take the first touch's travel as saying what it is: a pull, a scroll, or neither yet. */
export const INTENT_PX = 10;
/**
 * A pull decides itself quickly. A finger that rests first and then moves is choosing words (a long press, then a
 * drag of the selection's handles), so a drag that has not said what it is by now is left to the page.
 */
export const INTENT_MS = 300;

/** The page's offset for a finger `dy` px below where it started: weighted to the detent, then a rubber band. */
export function pullOffset(dy: number): number {
  if (dy <= 0) return 0;
  const weighted = dy / 2;
  if (weighted <= PULL_DETENT_PX) return weighted;
  return Math.min(PULL_MOST_PX, PULL_DETENT_PX + (weighted - PULL_DETENT_PX) / 3);
}

/** Whether the page, down by `offset`, would refresh on a let-go. */
export const armed = (offset: number): boolean => offset >= PULL_DETENT_PX;

/**
 * What the start of a touch is: a pull (down, more than across, from a page at its top, and soon), a scroll or a
 * drag of something else, or not yet known.
 */
export function pullIntent(dx: number, dy: number, atTop: boolean, elapsedMs: number): 'pull' | 'other' | 'undecided' {
  if (Math.abs(dx) < INTENT_PX && Math.abs(dy) < INTENT_PX) return elapsedMs > INTENT_MS ? 'other' : 'undecided';
  return atTop && dy > 0 && dy > Math.abs(dx) * 1.2 && elapsedMs <= INTENT_MS ? 'pull' : 'other';
}
