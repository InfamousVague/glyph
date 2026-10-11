/**
 * A tape's geometry, kept apart from its drawing so it can be tested.
 *
 * A spoken note's tape is drawn as a real one in miniature: recording moves
 * tape from the left reel to the right, so the right pack grows with the note
 * and the left shrinks, and each reel turns at the tape speed over its own
 * radius - the full reel slowly, the nearly empty one fast. Nobody has to read
 * a number to see how long a note is.
 *
 * Geometry is in the SVG's own units (viewBox 0 0 320 204).
 */

/**
 * How much recording fills the tape when nobody says otherwise. A voice note is short; five minutes shows growth from
 * the first seconds. A longer tape is given its own length (`lengthMs` below): the note's own once it runs past five
 * minutes, so playback winds across the whole reel, and on the home page's shelf the longest tape there, so a
 * three-minute note beside an hour's meeting is a thin ring beside a full reel (docs/DESIGN.md §127).
 */
export const TAPE_MS = 300_000;
export const HUB_R = 15;
/** The smallest a pack gets: a thin ring of leader tape around the hub. */
export const PACK_MIN_R = 18;
export const PACK_MAX_R = 44;
export const REEL_Y = 88;
export const LEFT_X = 104;
export const RIGHT_X = 216;
/** Tape speed, in units per millisecond: a half-full reel turns about once every 2.5 s. */
const TAPE_SPEED = 0.075;

export interface Packs {
  /** The left reel, which tape leaves while recording. */
  supply: number;
  /** The right reel, which tape winds onto. */
  takeup: number;
}

/** Pack radii for a recorded length on a tape `lengthMs` long. The tape's area is conserved, so the radii move as square roots. */
export function packRadii(positionMs: number, lengthMs = TAPE_MS): Packs {
  const f = Math.min(1, Math.max(0, positionMs / Math.max(1, lengthMs)));
  const span = PACK_MAX_R ** 2 - PACK_MIN_R ** 2;
  return {
    supply: Math.sqrt(PACK_MAX_R ** 2 - f * span),
    takeup: Math.sqrt(PACK_MIN_R ** 2 + f * span),
  };
}

/** Degrees each reel turns in `ms` of tape passing, at the radii for `positionMs` on a tape `lengthMs` long. */
export function reelTurn(positionMs: number, ms: number, lengthMs = TAPE_MS): Packs {
  const packs = packRadii(positionMs, lengthMs);
  const deg = (r: number) => ((ms * TAPE_SPEED) / r) * (180 / Math.PI);
  return { supply: deg(packs.supply), takeup: deg(packs.takeup) };
}

/** The tape counter: "0:07", "12:40", "1:02:03". */
export function counter(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = String(total % 60).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${s}` : `${m}:${s}`;
}
