/**
 * The launch screen's ghost watching the bar go round it (Matt: "I want the ghost's eyes to follow around the loading
 * bar that moves around the icon mask ... fake eyes that look around and follow the loader"). The picture's own eyes
 * are painted out (ghost-icon-eyeless.webp) and two are drawn in their place, each turned toward the bar.
 *
 * Positions are in the launch drawing's units: a 128 box, the icon 96 of it at (16, 16), drawn from a 192 picture, so
 * a point of the picture is at 16 + p / 2.
 */

export interface Point {
  x: number;
  y: number;
}

/** Where the picture's eyes were: the centres of its two dark ovals (192 picture: (85.6, 101.1) and (139.2, 101.4)). */
export const EYES: readonly Point[] = [
  { x: 58.8, y: 66.6 },
  { x: 85.6, y: 66.7 },
];

/** An eye's half-width and half-height: the ovals were 13 by 25 of the picture. */
export const EYE_RX = 3.3;
export const EYE_RY = 6.3;

/** How far an eye moves toward what it looks at: a little more up and down than across, as the ovals are tall. */
export const LOOK_X = 2.6;
export const LOOK_Y = 3.4;

/** One lap of the bar, in ms: the pace the CSS chase had. */
export const LAP_MS = 1150;
/** The bar's length, in hundredths of the ring (its dash, `stroke-dasharray: 14 86` on a pathLength of 100). */
export const DASH = 14;

/** Where an eye sits to look at `target`: moved toward it, as far as it goes, whatever the distance. */
export function lookAt(eye: Point, target: Point): Point {
  const dx = target.x - eye.x;
  const dy = target.y - eye.y;
  const distance = Math.hypot(dx, dy);
  if (distance < 0.001) return { x: 0, y: 0 };
  return { x: (dx / distance) * LOOK_X, y: (dy / distance) * LOOK_Y };
}

/** How far round the ring the bar's middle is at `ms`, from 0 to 1, and the dash offset that puts the bar there. */
export function barAt(ms: number): { middle: number; offset: number } {
  const lap = (((ms % LAP_MS) + LAP_MS) % LAP_MS) / LAP_MS;
  return { middle: (lap + DASH / 200) % 1, offset: -lap * 100 };
}

/** Once the app is open: how long the ghost takes to turn and look out of the screen, then how long its wink lasts. */
export const LOOK_OUT_MS = 240;
export const WINK_MS = 380;
/** The eye that winks: the one on the viewer's right. */
export const WINKING_EYE = 1;

/** How much of the way to its new place an eye goes in `ms`: it catches up in about a tenth of a second, as eyes do. */
export function easeFor(ms: number): number {
  return 1 - Math.exp(-Math.max(0, ms) / 90);
}
