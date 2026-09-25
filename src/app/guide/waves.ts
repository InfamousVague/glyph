/**
 * The rings the side key's edge sends out on the guide's side-key page
 * (SideKeyWaves.tsx): when one goes, how it grows and fades, and how its
 * outline wavers. Pure, so each is a test.
 *
 * One faint ring every 0.95 s, each living 3.8 s. The wobble is three slow
 * sines around the outline at different rates, so the ring wavers like
 * something seen through water rather than shivering (Matt: "make the
 * pulsing waves wobbly").
 *
 * They answered the microphone once, sent out closer together, wider and
 * brighter the louder the voice. The guide's page stopped listening (a page
 * that is only read is no place for an open microphone), and with nothing
 * feeding a level the voice's half of the pacing never ran, so it went. The
 * recorder's rings, which do follow the voice, are paced by
 * capture/voiceLevel.ts.
 */

export interface Ring {
  born: number;
  /** How long it lives, ms. */
  life: number;
  /** How far it reaches, as a multiple of the resting reach. */
  reach: number;
  /** How bright at its brightest, 0..1. */
  alpha: number;
  /** Stroke width, px. */
  width: number;
  /** A phase of its own, so no two rings wobble alike. */
  seed: number;
}

export interface Pacer {
  /** When the last ring went out. */
  lastAt: number;
}

export const REST_GAP_MS = 950;
export const REST_LIFE_MS = 3800;

/** How far the outline wobbles, as a fraction of the radius. */
export const WOBBLE = 0.035;

const clamp = (value: number) => Math.max(0, Math.min(1, value));

/** Frame by frame: the ring to send now, if it is time. */
export function paceWaves(pacer: Pacer, now: number, seed = Math.random() * Math.PI * 2): Ring | null {
  if (now - pacer.lastAt < REST_GAP_MS) return null;
  pacer.lastAt = now;
  return { born: now, life: REST_LIFE_MS, reach: 1, alpha: 0.55, width: 1.5, seed };
}

/** How far a ring has grown at `t` in 0..1: quickly out of the edge, slowly at the end. */
export function grown(t: number): number {
  return 1 - Math.pow(1 - clamp(t), 2.4);
}

/** How bright a ring is at `t`: up in the first tenth, then fading to nothing. */
export function shining(t: number): number {
  const at = clamp(t);
  return at < 0.12 ? at / 0.12 : 1 - (at - 0.12) / 0.88;
}

/** The wobble at angle `theta` (radians) and time `seconds`, in -1..1. */
export function wobbleAt(theta: number, seconds: number, seed: number): number {
  return 0.5 * Math.sin(3 * theta + seed + seconds * 1.1) + 0.3 * Math.sin(5 * theta - 2 * seed - seconds * 0.7) + 0.2 * Math.sin(8 * theta + seed * 0.5 + seconds * 1.9);
}
