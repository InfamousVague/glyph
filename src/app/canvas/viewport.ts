import { bounds, type Box } from './geometry.ts';
import type { Canvas } from './jsonCanvas.ts';

/**
 * Where the screen is over the canvas (canvas/CanvasView.tsx): the world's offset in screen pixels and its scale.
 * A point of the canvas at (px, py) is on the screen at (px * scale + x, py * scale + y). Pure, for its tests.
 */
export interface View {
  x: number;
  y: number;
  scale: number;
}

const MIN_SCALE = 0.1;
const MAX_SCALE = 3;
/** Room around the whole canvas when it is fitted to the screen, in screen pixels. */
export const FIT_ROOM = 32;
/** The view before there is anything to fit, or a screen to fit it in: room at the top left, life size. */
const HOME: View = { x: FIT_ROOM, y: FIT_ROOM, scale: 1 };

/** A scale no smaller than a tenth of life and no larger than three times. */
export const clampScale = (scale: number): number => Math.min(MAX_SCALE, Math.max(MIN_SCALE, scale));

/** The view that shows the whole canvas in a screen this big, centred, no larger than life. */
export function fitted(canvas: Canvas, width: number, height: number): View {
  const box = bounds(canvas);
  return box ? fittedTo(box, width, height) : { ...HOME };
}

/** The view with the point of the canvas that was under (px, py) still under it at `scale`. */
export function zoomedAt(view: View, px: number, py: number, scale: number): View {
  const next = clampScale(scale);
  return { x: px - ((px - view.x) / view.scale) * next, y: py - ((py - view.y) / view.scale) * next, scale: next };
}

/** The view that shows this box in a screen this big, centred, no larger than life: zoom-to-card (choice 10). */
export function fittedTo(box: Box, width: number, height: number): View {
  if (width <= 0 || height <= 0) return { ...HOME };
  const scale = clampScale(Math.min((width - FIT_ROOM * 2) / Math.max(box.width, 1), (height - FIT_ROOM * 2) / Math.max(box.height, 1), 1));
  return { x: (width - box.width * scale) / 2 - box.x * scale, y: (height - box.height * scale) / 2 - box.y * scale, scale };
}

/** The part of the canvas the screen shows, in the canvas's own pixels: what the minimap draws as the viewport. */
export function shown(view: View, width: number, height: number): Box {
  return { x: -view.x / view.scale, y: -view.y / view.scale, width: width / view.scale, height: height / view.scale };
}
