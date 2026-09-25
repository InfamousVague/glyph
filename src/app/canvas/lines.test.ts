import { describe, expect, it } from 'vitest';
import { SPEC_SAMPLE } from '../../test/canvas.ts';
import { newEdge, withEdge } from './edits.ts';
import { parseCanvas, type Canvas, type CanvasNode } from './jsonCanvas.ts';
import { brokenInto, edgePaths, END_SPREAD, HEAD, HEAD_CLEAR } from './lines.ts';

/** A canvas's lines as they are drawn: the curves, their heads, ends kept apart, and labels placed off the cards. */

describe('a line drawn', () => {
  const canvas = parseCanvas(SPEC_SAMPLE) as Canvas;

  it('draws an edge as a curve with an arrow at its end unless told otherwise, stopping short of the head', () => {
    const e1 = edgePaths(canvas).get('e1');
    expect(e1?.d.startsWith(`M250 30C`)).toBe(true);
    expect(e1?.d.endsWith(`${300 - HEAD} 60`)).toBe(true);
    expect(e1?.toHead?.startsWith('M300 60')).toBe(true);
    expect(e1?.fromHead).toBeNull();
    expect(e1?.mid.x).toBeGreaterThan(250);
    expect(e1?.mid.x).toBeLessThan(300);
    const e2 = edgePaths(canvas).get('e2');
    expect(e2?.toHead).toBeNull();
    expect(e2?.d.endsWith('125 150')).toBe(true);
    // A line to a card that is not there is not drawn.
    expect(edgePaths({ ...canvas, edges: [{ id: 'x', fromNode: 't1', toNode: 'nope' }] }).get('x')).toBeUndefined();
  });

  it('draws a new line with an arrow at its end', () => {
    const line = newEdge('f1', 'l1', 'ln');
    expect(edgePaths(withEdge(canvas, line)).get('ln')?.toHead).not.toBeNull();
  });
});

describe('lines kept apart', () => {
  const card = (id: string, x: number, y: number): CanvasNode => ({ id, type: 'text', text: id, x, y, width: 300, height: 200 });
  /** The tip of a head: the first point of its path. */
  const tip = (d: string | null | undefined): { x: number; y: number } => {
    const m = /^M([\d.-]+) ([\d.-]+)/.exec(d ?? '');
    if (!m) throw new Error(`no head in ${d}`);
    return { x: Number(m[1]), y: Number(m[2]) };
  };

  it('sets two lines into one side of a card apart along it, in the order their far ends come', () => {
    const canvas: Canvas = {
      nodes: [card('a', 0, 0), card('b', 0, 400), card('c', 500, 200)],
      edges: [
        { id: 'e1', fromNode: 'a', toNode: 'c' },
        { id: 'e2', fromNode: 'b', toNode: 'c' },
      ],
    };
    const paths = edgePaths(canvas);
    const one = tip(paths.get('e1')?.toHead);
    const two = tip(paths.get('e2')?.toHead);
    // Both on c's left side (x 500, middle y 300): the line from above lands above, the one from below below.
    expect(one.x).toBe(500);
    expect(two.x).toBe(500);
    expect(one.y).toBe(300 - END_SPREAD / 2);
    expect(two.y).toBe(300 + END_SPREAD / 2);
    // Alone, a line lands on the middle as before.
    expect(tip(edgePaths({ ...canvas, edges: [canvas.edges[0]!] }).get('e1')?.toHead)).toEqual({ x: 500, y: 300 });
  });

  it('moves two heads apart that would meet across the gap between neighbouring cards', () => {
    // The screenshot: a line from above-left into the left card's right side, one from above-right into the right
    // card's left side, both landing at the row's middle, 40px apart tip to tip, their heads base to base in the gap.
    const canvas: Canvas = {
      nodes: [card('left', 0, 0), card('right', 340, 0), card('up', 0, -600), card('over', 340, -600)],
      edges: [
        { id: 'e1', fromNode: 'up', toNode: 'left', fromSide: 'bottom', toSide: 'right' },
        { id: 'e2', fromNode: 'over', toNode: 'right', fromSide: 'bottom', toSide: 'left' },
      ],
    };
    const paths = edgePaths(canvas);
    const one = tip(paths.get('e1')?.toHead);
    const two = tip(paths.get('e2')?.toHead);
    expect(one.x).toBe(300);
    expect(two.x).toBe(340);
    // Neither is at the middle any more, and they are a clear width apart.
    expect(one.y).not.toBe(100);
    expect(two.y).not.toBe(100);
    expect(Math.hypot(one.x - two.x, one.y - two.y)).toBeGreaterThanOrEqual(HEAD_CLEAR - 0.01);
    // Each still on its own side.
    expect(one.y).toBeGreaterThan(0);
    expect(one.y).toBeLessThan(200);
    expect(two.y).toBeGreaterThan(0);
    expect(two.y).toBeLessThan(200);
  });

  it('sits a label over open canvas rather than over a card, and in the middle when there is nowhere else', () => {
    // A straight line from a to c at y 100, with b sitting on it where the middle would be.
    const a = card('a', 0, 0);
    const c = card('c', 800, 0);
    const label = 'over';
    const clear = edgePaths({ nodes: [a, c, { ...card('b', 450, 0), width: 200 }], edges: [{ id: 'e', fromNode: 'a', toNode: 'c', label }] }).get('e')!;
    // Off b (450-650) and off a (to 300): the first try along the curve that is.
    expect(clear.mid.y).toBeCloseTo(100, 5);
    expect(clear.mid.x + 20).toBeLessThan(450);
    expect(clear.mid.x - 20).toBeGreaterThan(300);
    // A group is open canvas: a label may sit over one, at the curve's middle (the curve runs from a's side at 300 to
    // the base of the head at 790, so its middle is 545).
    const group: CanvasNode = { id: 'g', type: 'group', x: 300, y: -100, width: 500, height: 400 };
    expect(edgePaths({ nodes: [a, c, group], edges: [{ id: 'e', fromNode: 'a', toNode: 'c', label }] }).get('e')!.mid.x).toBeCloseTo(545, 5);
    // A card under the whole line: the middle, as it was, on one line.
    const wall = { ...card('b', 320, 0), width: 460 };
    const nowhere = edgePaths({ nodes: [a, c, wall], edges: [{ id: 'e', fromNode: 'a', toNode: 'c', label }] }).get('e')!;
    expect(nowhere.mid.x).toBeCloseTo(545, 5);
    expect(nowhere.lines).toEqual([label]);
    // No label: no lines.
    expect(edgePaths({ nodes: [a, c], edges: [{ id: 'e', fromNode: 'a', toNode: 'c' }] }).get('e')!.lines).toEqual([]);
  });

  it('breaks a label onto two lines where one line would not fit down the gap between two cards', () => {
    // The example canvas: "Launch week" and "Everything a note can hold" 120px apart, and the words between them
    // wider than that on one line (26 letters, about 185px) but not on two.
    const a = card('a', 0, 0);
    const c = card('c', 420, 0);
    const label = 'every mark a note can hold';
    const placed = edgePaths({ nodes: [a, c], edges: [{ id: 'e', fromNode: 'a', toNode: 'c', label, toEnd: 'none' }] }).get('e')!;
    expect(placed.lines).toEqual(['every mark a', 'note can hold']);
    // Down the gap: the box of the widest line clear of both cards.
    const half = (13 * 6.8 + 8) / 2;
    expect(placed.mid.x - half).toBeGreaterThan(300);
    expect(placed.mid.x + half).toBeLessThan(420);
  });

  it('breaks words into lines of about equal length, never inside a word', () => {
    expect(brokenInto('every mark a note can hold', 1)).toEqual(['every mark a note can hold']);
    expect(brokenInto('every mark a note can hold', 2)).toEqual(['every mark a', 'note can hold']);
    expect(brokenInto('every mark a note can hold', 3)).toEqual(['every mark', 'a note', 'can hold']);
    expect(brokenInto('one', 3)).toEqual(['one']);
    expect(brokenInto('  ', 2)).toEqual([]);
  });

  it('packs the ends on a side too short for the spread, and keeps them off its corners', () => {
    const tall = (id: string, y: number): CanvasNode => ({ id, type: 'text', text: id, x: 0, y, width: 300, height: 200 });
    // c's left side is 60px long: three ends cannot be END_SPREAD apart on it, and none may come within 16px of a corner.
    const canvas: Canvas = {
      nodes: [tall('a', 0), tall('b', 300), tall('d', 600), { id: 'c', type: 'text', text: 'c', x: 500, y: 270, width: 300, height: 60 }],
      edges: ['a', 'b', 'd'].map((from) => ({ id: from, fromNode: from, toNode: 'c' })),
    };
    const paths = edgePaths(canvas);
    const ys = ['a', 'b', 'd'].map((id) => Number(/^M[\d.-]+ ([\d.-]+)/.exec(paths.get(id)!.toHead!)![1]));
    // In the order their far ends come, top to bottom, evenly about the middle and no nearer a corner than 16px.
    expect(ys).toEqual([286, 300, 314]);
    for (const y of ys) {
      expect(y).toBeGreaterThanOrEqual(270 + 16);
      expect(y).toBeLessThanOrEqual(330 - 16);
    }
  });

  it('breaks a label onto three lines where two will not fit down the gap', () => {
    const card = (id: string, x: number): CanvasNode => ({ id, type: 'text', text: id, x, y: 0, width: 300, height: 200 });
    const label = 'the long way round the lake';
    const placed = edgePaths({ nodes: [card('a', 0), card('c', 390)], edges: [{ id: 'e', fromNode: 'a', toNode: 'c', label, toEnd: 'none' }] }).get('e')!;
    expect(placed.lines).toHaveLength(3);
    expect(placed.lines.join(' ')).toBe(label);
  });
});
