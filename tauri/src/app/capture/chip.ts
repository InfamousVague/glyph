import { findKeyword } from './command.ts';
import type { RouteView } from './takeHost.ts';

/**
 * What the chip at the foot of the recorder looks like, and how long it stays (RouteChip.tsx draws it).
 *
 * The chip says where the words are going while a command is heard, and what came of it. It takes one of three
 * looks the stylesheet draws (CaptureScreen.module.css `.route`): outlined with dots while a note is being named or a
 * command worked out, filled with a tick once something has landed, dashed when a name matched no note. Pure, so each
 * of the chip's views (capture/takeHost.ts `RouteView`) is a test.
 */

/**
 * The look a chip takes: still hearing, landed (`moved`), missed, taken back (its own: filled, with Undo and no tick),
 * or its own phase where that is one of them already.
 */
export function chipPhase(route: Exclude<RouteView, null>): string {
  if (route.phase === 'command') return 'hearing';
  if (route.phase === 'said') return 'missed';
  if (route.phase === 'done') return 'moved';
  return route.phase;
}

/**
 * How long a settled chip stays before it goes, or null for one still under way (a name being heard, a command being
 * said), which stays until the recorder says more. Words to read - a sentence said back, the items that landed - stay
 * longer than a tick, and a take-back with its Undo longer still, a second short of the reader's window
 * (liveRoute.ts `LIVE_TIMING.takeBackMs`), so a button drawn is a button that works.
 */
export function lingerMs(route: RouteView): number | null {
  if (!route) return null;
  const settled = route.phase === 'moved' || route.phase === 'missed' || route.phase === 'added' || route.phase === 'said' || route.phase === 'done' || route.phase === 'tookBack';
  if (!settled) return null;
  if (route.phase === 'tookBack') return 4000;
  return route.phase === 'added' || route.phase === 'said' ? 3200 : 2200;
}

/** The words of a command still being said, with the keyword taken off if it is in them. */
export function partialCommand(text: string): string {
  return (findKeyword(text)?.after ?? text).trim();
}
