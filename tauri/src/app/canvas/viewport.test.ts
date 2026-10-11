import { describe, expect, it } from 'vitest';
import { VIEW_SAMPLE } from '../../test/canvas.ts';
import { parseCanvas, type Canvas } from './jsonCanvas.ts';
import { clampScale, fitted, fittedTo, shown, zoomedAt } from './viewport.ts';

/** The view maths the canvas moves by (canvas/CanvasView.tsx): fitting, zooming about a point, and what the screen shows. */

const canvas = parseCanvas(VIEW_SAMPLE) as Canvas;

describe('fitting the canvas to the screen', () => {
  it('scales the whole canvas into the screen with room around it, no larger than life, centred', () => {
    const view = fitted(canvas, 1000, 600);
    // The cards run from -20 to 500 across and -20 to 180 down: 520 by 200, which fits a 1000 by 600 screen at life size.
    expect(view.scale).toBe(1);
    expect(view.x).toBe((1000 - 520) / 2 + 20);
    expect(view.y).toBe((600 - 200) / 2 + 20);
    // Too wide for 300 by 300: the cards' 520 fill the 236 between the room, and sit centred down the screen.
    const small = fitted(canvas, 300, 300);
    expect(small.scale).toBeCloseTo((300 - 64) / 520, 5);
    expect(small.x - 20 * small.scale).toBeCloseTo(32, 5);
    expect(small.y - 20 * small.scale).toBeCloseTo((300 - 200 * small.scale) / 2, 5);
    expect(fitted({ nodes: [], edges: [] }, 300, 300)).toEqual({ x: 32, y: 32, scale: 1 });
  });

  it('has room and life size for a screen with no size yet, and for a card with none', () => {
    expect(fitted(canvas, 0, 600)).toEqual({ x: 32, y: 32, scale: 1 });
    expect(fittedTo({ x: 5, y: 5, width: 10, height: 10 }, 400, -1)).toEqual({ x: 32, y: 32, scale: 1 });
    // A card of no size is a point: centred, at life size, not scaled up without end.
    const point: Canvas = { nodes: [{ id: 'p', type: 'text', text: '', x: 10, y: 20, width: 0, height: 0 }], edges: [] };
    expect(fitted(point, 400, 300)).toEqual({ x: 190, y: 130, scale: 1 });
  });

  it('never goes smaller than a tenth or larger than three times life', () => {
    expect(fittedTo({ x: 0, y: 0, width: 1_000_000, height: 10 }, 400, 300).scale).toBe(0.1);
    expect(clampScale(99)).toBe(3);
    expect(clampScale(0.001)).toBe(0.1);
    expect(clampScale(1.5)).toBe(1.5);
  });
});

describe('zooming and what the screen shows', () => {
  it('zooms about a point of the screen, keeping what was under it under it', () => {
    const view = { x: 100, y: 50, scale: 1 };
    // The canvas point under (300, 250) is (200, 200); at double size it must still be at (300, 250).
    const doubled = zoomedAt(view, 300, 250, 2);
    expect(doubled).toEqual({ x: 300 - 200 * 2, y: 250 - 200 * 2, scale: 2 });
    expect(zoomedAt(view, 0, 0, 99).scale).toBe(3);
    expect(zoomedAt(view, 0, 0, 0.001).scale).toBe(0.1);
  });

  it('fits a card to the screen no larger than life, and reports the box the screen shows', () => {
    const view = fittedTo({ x: 100, y: 50, width: 200, height: 80 }, 400, 300);
    expect(view.scale).toBe(1);
    expect(view).toEqual({ x: 0, y: 60, scale: 1 });
    const small = fittedTo({ x: 0, y: 0, width: 2000, height: 1000 }, 400, 300);
    expect(small.scale).toBeCloseTo(0.168, 3);
    expect(shown({ x: -100, y: -50, scale: 0.5 }, 400, 300)).toEqual({ x: 200, y: 100, width: 800, height: 600 });
  });
});
