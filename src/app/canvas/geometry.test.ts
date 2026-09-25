import { describe, expect, it } from 'vitest';
import { SPEC_SAMPLE } from '../../test/canvas.ts';
import { anchorOf, bounds, sidesOf } from './geometry.ts';
import { parseCanvas, type Canvas } from './jsonCanvas.ts';

/** Where a canvas's cards are: the box round them, where a line attaches, and which sides two cards face by. */

describe('where things are', () => {
  const canvas = parseCanvas(SPEC_SAMPLE) as Canvas;

  it('bounds every node, and an empty canvas has none', () => {
    expect(bounds(canvas)).toEqual({ x: -40, y: -40, width: 600, height: 300 });
    expect(bounds({ nodes: [], edges: [] })).toBeNull();
  });

  it('anchors an edge on the middle of a side', () => {
    const box = { x: 10, y: 20, width: 100, height: 50 };
    expect(anchorOf(box, 'top')).toEqual({ x: 60, y: 20 });
    expect(anchorOf(box, 'right')).toEqual({ x: 110, y: 45 });
    expect(anchorOf(box, 'bottom')).toEqual({ x: 60, y: 70 });
    expect(anchorOf(box, 'left')).toEqual({ x: 10, y: 45 });
  });

  it('picks the sides that face each other when the edge does not say, and keeps the ones it does', () => {
    const left = { x: 0, y: 0, width: 100, height: 100 };
    const right = { x: 400, y: 20, width: 100, height: 100 };
    const below = { x: 20, y: 400, width: 100, height: 100 };
    expect(sidesOf(left, right, {})).toEqual({ from: 'right', to: 'left' });
    expect(sidesOf(right, left, {})).toEqual({ from: 'left', to: 'right' });
    expect(sidesOf(left, below, {})).toEqual({ from: 'bottom', to: 'top' });
    expect(sidesOf(left, below, { fromSide: 'right' })).toEqual({ from: 'right', to: 'top' });
  });

  it('faces across rather than down when two cards are as far apart each way', () => {
    const a = { x: 0, y: 0, width: 100, height: 100 };
    const b = { x: 200, y: 200, width: 100, height: 100 };
    expect(sidesOf(a, b, {})).toEqual({ from: 'right', to: 'left' });
    expect(sidesOf(b, a, {})).toEqual({ from: 'left', to: 'right' });
  });
});
