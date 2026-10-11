import { describe, expect, it } from 'vitest';
import { SPEC_SAMPLE } from '../../test/canvas.ts';
import { atDot, CHART_CARD, clearSpot, colouredNode, duplicated, GRID, GROUP_ROOM, heldBy, joined, labelledEdge, labelledGroup, LEAST_CARD, movedNode, movedWithHeld, newCanvasId, newEdge, newFileNode, newGroupNode, newLinkNode, newPictureNode, newTextNode, onGrid, resizedBy, resizedNode, STEP_ASIDE, TABLE_CARD, withEdge, withGroup, withNode, withoutEdge, withoutNode } from './edits.ts';
import { parseCanvas, serializeCanvas, type Canvas } from './jsonCanvas.ts';

/** Making and changing a canvas: cards and lines added, moved, resized, named and taken off, each a new canvas. */

describe('changing a canvas', () => {
  const canvas = parseCanvas(SPEC_SAMPLE) as Canvas;

  it('adds a card, moves it to the pixel, replaces it, and takes it out with its lines', () => {
    const card = newTextNode(10.4, 20.6, 'abc');
    expect(card).toMatchObject({ id: 'abc', type: 'text', x: 10, y: 21, text: '' });
    const added = withNode(canvas, card);
    expect(added.nodes.at(-1)).toBe(card);
    const moved = withNode(added, movedNode(card, 99.7, -3.2));
    expect(moved.nodes.length).toBe(added.nodes.length);
    expect(moved.nodes.at(-1)).toMatchObject({ id: 'abc', x: 100, y: -3 });
    // t1 has two edges; both go with it, and nothing else does.
    const gone = withoutNode(canvas, 't1');
    expect(gone.nodes.map((n) => n.id)).toEqual(['g1', 'f1', 'l1']);
    expect(gone.edges).toEqual([]);
  });

  it('names a new node the way Obsidian does: sixteen hex characters, never the same twice', () => {
    const ids = new Set(Array.from({ length: 50 }, () => newCanvasId()));
    expect(ids.size).toBe(50);
    for (const id of ids) expect(id).toMatch(/^[0-9a-f]{16}$/);
  });
});

describe('lines between cards', () => {
  const canvas = parseCanvas(SPEC_SAMPLE) as Canvas;

  it('makes a new line from one card to another, adds it last, and takes it off again', () => {
    const line = newEdge('f1', 'l1', 'ln');
    expect(line).toEqual({ id: 'ln', fromNode: 'f1', toNode: 'l1' });
    const added = withEdge(canvas, line);
    expect(added.edges.at(-1)).toBe(line);
    expect(withoutEdge(added, 'ln').edges).toEqual(canvas.edges);
    // Read back through the spec, it is the same line.
    expect(parseCanvas(serializeCanvas(added))?.edges.at(-1)).toEqual(line);
  });

  it('labels a line, replaces the label, and takes it off with blank', () => {
    const line = newEdge('f1', 'l1', 'ln');
    expect(labelledEdge(line, '  then  ').label).toBe('then');
    expect(labelledEdge(labelledEdge(line, 'then'), 'after')).toMatchObject({ label: 'after' });
    expect('label' in labelledEdge(labelledEdge(line, 'then'), '   ')).toBe(false);
    expect(withEdge(canvas, labelledEdge(canvas.edges[0]!, 'later')).edges[0]).toMatchObject({ id: 'e1', label: 'later' });
  });

  it('knows when two cards are already joined, either way round', () => {
    expect(joined(canvas, 't1', 'f1')).toBe(true);
    expect(joined(canvas, 'f1', 't1')).toBe(true);
    expect(joined(canvas, 'f1', 'l1')).toBe(false);
  });
});

describe('sizes and groups', () => {
  const canvas = parseCanvas(SPEC_SAMPLE) as Canvas;

  it('resizes a card to the pixel and never smaller than a word and a cross', () => {
    const t1 = canvas.nodes.find((n) => n.id === 't1')!;
    expect(resizedNode(t1, 300.4, 80.6)).toMatchObject({ x: 0, y: 0, width: 300, height: 81 });
    expect(resizedNode(t1, 10, 10)).toMatchObject({ width: 120, height: 60 });
  });

  it('moves a group with everything wholly inside it, and a card on its own', () => {
    const g1 = canvas.nodes.find((n) => n.id === 'g1')!;
    // g1 is -40,-40 600x300: t1 (0,0 250x60) and f1 (300,0 250x120) are inside; l1 (0,150 250x80) is inside too.
    expect(heldBy(canvas, g1).map((n) => n.id)).toEqual(['t1', 'f1', 'l1']);
    const moved = movedWithHeld(canvas, g1, 60, -40);
    expect(moved.nodes.map((n) => [n.id, n.x, n.y])).toEqual([['g1', 60, -40], ['t1', 100, 0], ['f1', 400, 0], ['l1', 100, 150]]);
    const alone = movedWithHeld(canvas, canvas.nodes.find((n) => n.id === 't1')!, 20, 20);
    expect(alone.nodes.map((n) => [n.id, n.x, n.y])).toEqual([['g1', -40, -40], ['t1', 20, 20], ['f1', 300, 0], ['l1', 0, 150]]);
  });

  it('names a group, and takes the name off with blank; a card that is not a group has no name to take', () => {
    const g1 = canvas.nodes.find((n) => n.id === 'g1')!;
    expect('label' in labelledGroup(g1, '  ')).toBe(false);
    expect(labelledGroup(g1, ' Plans ')).toMatchObject({ id: 'g1', label: 'Plans' });
    const t1 = canvas.nodes.find((n) => n.id === 't1')!;
    expect(labelledGroup(t1, 'Plans')).toBe(t1);
  });
});

describe('note and link cards made', () => {
  it('names a note card by its title as a file, and gives a bare address https', () => {
    expect(newFileNode('Cabin trip', 10.4, 20, 'f')).toMatchObject({ id: 'f', type: 'file', file: 'Cabin trip.md', x: 10, y: 20 });
    expect(newFileNode('  ', 0, 0, 'f')).toMatchObject({ file: 'Untitled.md' });
    expect(newFileNode('Plans/Cabin', 0, 0, 'f')).toMatchObject({ file: 'Plans-Cabin.md' });
    expect(newLinkNode('attack.fm/glyph', 0, 0, 'l')).toMatchObject({ type: 'link', url: 'https://attack.fm/glyph' });
    expect(newLinkNode('https://x.y', 0, 0, 'l')).toMatchObject({ url: 'https://x.y' });
    expect(newLinkNode('mailto:a@b.c', 0, 0, 'l')).toMatchObject({ url: 'mailto:a@b.c' });
    expect(newLinkNode('   ', 0, 0)).toBeNull();
  });
});

describe('pictures, charts and tables', () => {
  it('makes a picture card by the store name, and starts a chart and a table as what they are', () => {
    expect(newPictureNode('abc.jpg', 5.5, 6, 'p')).toMatchObject({ id: 'p', type: 'file', file: 'abc.jpg', x: 6, y: 6, height: 200 });
    expect(CHART_CARD.startsWith('```mermaid\n')).toBe(true);
    expect(TABLE_CARD.split('\n')[1]).toBe('| --- | --- |');
  });
});

describe('the picked card’s edits', () => {
  const card = { id: 'c', type: 'text', x: 100, y: 100, width: 200, height: 100, text: 'x' } as const;
  const box = (n: { x: number; y: number; width: number; height: number }) => [n.x, n.y, n.width, n.height];

  it('resizes by a corner or a side, the far sides staying where they are', () => {
    expect(box(resizedBy(card, 'se', 40, 20))).toEqual([100, 100, 240, 120]);
    expect(box(resizedBy(card, 'nw', -40, -20))).toEqual([60, 80, 240, 120]);
    expect(box(resizedBy(card, 'ne', 40, -20))).toEqual([100, 80, 240, 120]);
    expect(box(resizedBy(card, 'sw', -40, 20))).toEqual([60, 100, 240, 120]);
    // A side moves alone, whatever the pointer does across it.
    expect(box(resizedBy(card, 'e', 40, 900))).toEqual([100, 100, 240, 100]);
    expect(box(resizedBy(card, 'n', 900, -20))).toEqual([100, 80, 200, 120]);
    // To the pixel.
    expect(box(resizedBy(card, 'se', 10.6, 0.4))).toEqual([100, 100, 211, 100]);
  });

  it('stops at the least size, and the card does not slide once it has', () => {
    expect(box(resizedBy(card, 'se', -900, -900))).toEqual([100, 100, LEAST_CARD.width, LEAST_CARD.height]);
    // From the top left, the bottom-right corner (300, 200) is the one that stays.
    expect(box(resizedBy(card, 'nw', 900, 900))).toEqual([300 - LEAST_CARD.width, 200 - LEAST_CARD.height, LEAST_CARD.width, LEAST_CARD.height]);
  });

  it('copies a card a step aside under a new id, and steps again past a copy already there', () => {
    const canvas = { nodes: [card], edges: [] };
    const copy = duplicated(canvas, card, 'd1');
    expect(copy).toEqual({ ...card, id: 'd1', x: 124, y: 124 });
    const again = duplicated({ nodes: [card, copy], edges: [] }, card, 'd2');
    expect([again.x, again.y]).toEqual([148, 148]);
  });

  it('finds a spot clear of every card’s corner, and leaves a clear one alone', () => {
    const canvas = { nodes: [card], edges: [] };
    expect(clearSpot(canvas, 400, 400)).toEqual({ x: 400, y: 400 });
    expect(clearSpot(canvas, 100, 100)).toEqual({ x: 100 + STEP_ASIDE, y: 100 + STEP_ASIDE });
    // A group's corner is not a card's: a card may start in the corner of a group.
    expect(clearSpot({ nodes: [{ id: 'g', type: 'group', x: 0, y: 0, width: 500, height: 500 }], edges: [] }, 0, 0)).toEqual({ x: 0, y: 0 });
  });

  it('colours with a preset and takes the colour off, leaving no empty field', () => {
    expect(colouredNode(card, '5')).toEqual({ ...card, color: '5' });
    expect('color' in colouredNode({ ...card, color: '5' }, null)).toBe(false);
  });

  it('makes a group about a card with room round it, or a box of its own, and puts it under the cards', () => {
    expect(newGroupNode(card, 0, 0, 'g')).toEqual({ id: 'g', type: 'group', x: 100 - GROUP_ROOM, y: 100 - GROUP_ROOM, width: 200 + GROUP_ROOM * 2, height: 100 + GROUP_ROOM * 2 });
    const own = newGroupNode(null, 10.4, 20.6, 'g');
    expect(own).toEqual({ id: 'g', type: 'group', x: 10, y: 21, width: 480, height: 320 });
    expect(withGroup({ nodes: [card], edges: [] }, own).nodes.map((n) => n.id)).toEqual(['g', 'c']);
    // The card it was made about is held by it, so it moves with it.
    const about = newGroupNode(card, 0, 0, 'g');
    expect(heldBy({ nodes: [about, card], edges: [] }, about).map((n) => n.id)).toEqual(['c']);
  });
});

describe('the grid', () => {
  it('is the dots, 24 apart from the canvas’s own corner, and a place goes to the nearest', () => {
    expect(GRID).toBe(24);
    expect([onGrid(0), onGrid(11), onGrid(12), onGrid(-11), onGrid(-13), onGrid(331)]).toEqual([0, 0, 24, -0, -24, 336]);
    expect(atDot(331, 143)).toEqual({ x: 336, y: 144 });
  });

  it('snaps the sides a handle moves, and brings a card that was off the grid onto it side by side', () => {
    const off = { id: 'c', type: 'text', x: 100, y: 100, width: 200, height: 100, text: 'x' } as const;
    const box = (n: { x: number; y: number; width: number; height: number }) => [n.x, n.y, n.width, n.height];
    // The right side was at 300: out by 10 it is 310, whose line is 312. The left side, not held, stays at 100.
    expect(box(resizedBy(off, 'e', 10, 0, true))).toEqual([100, 100, 212, 100]);
    // The top-left corner goes to 96,96; the far corner (300,200) stays.
    expect(box(resizedBy(off, 'nw', -3, -3, true))).toEqual([96, 96, 204, 104]);
    // Never smaller than the least, snapped or not: the side stops there.
    expect(box(resizedBy(off, 'e', -900, 0, true))).toEqual([100, 100, 120, 100]);
    // Without snapping, to the pixel as before.
    expect(box(resizedBy(off, 'e', 10, 0))).toEqual([100, 100, 210, 100]);
  });
});

describe('a canvas with comment threads, changed', () => {
  // Ghost.md's own field beside the spec's two (jsonCanvas.ts `Canvas.comments`; docs/SHARED.md, S9).
  const plain = parseCanvas(SPEC_SAMPLE) as Canvas;
  const thread = { id: 'c1', node: 't1', by: 'sam', at: '2026-10-05T14:00:00Z', text: 'Which Friday?', replies: [] };
  const canvas: Canvas = { ...plain, comments: [thread] };
  const t1 = canvas.nodes.find((n) => n.id === 't1')!;
  const g1 = canvas.nodes.find((n) => n.id === 'g1')!;
  const edge = canvas.edges[0]!;

  it('keeps its threads through every edit that does not take their card off', () => {
    expect(withNode(canvas, newTextNode(0, 0, 'new')).comments).toEqual([thread]);
    expect(withNode(canvas, movedNode(t1, 5, 5)).comments).toEqual([thread]);
    expect(movedWithHeld(canvas, t1, 40, 40).comments).toEqual([thread]);
    expect(movedWithHeld(canvas, g1, g1.x + 10, g1.y + 10).comments).toEqual([thread]);
    expect(withEdge(canvas, newEdge('t1', 'l1', 'line')).comments).toEqual([thread]);
    expect(withEdge(canvas, labelledEdge(edge, 'then')).comments).toEqual([thread]);
    expect(withoutEdge(canvas, edge.id).comments).toEqual([thread]);
    expect(withGroup(canvas, newGroupNode(t1, 0, 0, 'grp')).comments).toEqual([thread]);
    // And they are written: the JSON the note keeps still has them after a move.
    expect(parseCanvas(serializeCanvas(movedWithHeld(canvas, t1, 40, 40)))?.comments).toEqual([thread]);
  });

  it('writes a canvas that has none exactly as before: no comments field, the spec’s two alone', () => {
    const edits = [withNode(plain, newTextNode(0, 0, 'new')), movedWithHeld(plain, t1, 40, 40), withEdge(plain, newEdge('t1', 'l1', 'line')), withoutEdge(plain, edge.id), withGroup(plain, newGroupNode(t1, 0, 0, 'grp'))];
    for (const edited of edits) {
      expect(Object.keys(edited)).toEqual(['nodes', 'edges']);
      expect(serializeCanvas(edited)).toBe(`${JSON.stringify({ nodes: edited.nodes, edges: edited.edges }, null, 2)}\n`);
    }
  });
});
