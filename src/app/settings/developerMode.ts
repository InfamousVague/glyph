import { deviceFlag } from '../core/deviceFlag.ts';

/**
 * Developer mode: the switch behind the hidden tools.
 *
 * Unlocked by seven presses on the version in About (the way Android's own
 * developer options are), and from then on a plain switch at the top of the
 * Developer page. While it is on, Settings grows a Developer section under
 * About; while it is off the section is absent from the list.
 *
 * A live store rather than a preference, the same shape as core/haptics.ts
 * (core/deviceFlag.ts): the flag is flipped from INSIDE a pane (About) and has
 * to change the PARENT's sections on the spot. Kept in its own key, not in the
 * preferences object, so a device that never unlocked the tools carries
 * nothing about them - and a reset leaves it on (core/reset.ts).
 */
const developer = deviceFlag('glyph-developer');

export const setDeveloperMode = developer.set;

/** The flag, live across every component that reads it. */
export const useDeveloperMode = developer.use;

/** Presses on the version in About needed to unlock the tools. */
export const KNOCKS_WANTED = 7;
/** A run of presses resets when a gap is longer than this. */
const KNOCK_GAP_MS = 900;

let knocks = 0;
let lastKnock = 0;

/**
 * Counts a press; answers how many remain, 0 on the press that completes the
 * run. Module state rather than a ref, because the About pane is a fresh
 * element every time the sections array is rebuilt.
 */
export function countKnock(now = Date.now()): number {
  knocks = now - lastKnock > KNOCK_GAP_MS ? 1 : knocks + 1;
  lastKnock = now;
  if (knocks < KNOCKS_WANTED) return KNOCKS_WANTED - knocks;
  knocks = 0;
  return 0;
}
