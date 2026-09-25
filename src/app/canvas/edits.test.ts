import { describe, expect, it } from 'vitest';
import { SPEC_SAMPLE } from '../../test/canvas.ts';
import {
  CHART_CARD,
  heldBy,
  joined,
  labelledEdge,
  labelledGroup,
  movedNode,
  movedWithHeld,
  newCanvasId,
  newEdge,
  newFileNode,
  newLinkNode,
  newPictureNode,
  newTextNode,
  resizedNode,
  TABLE_CARD,
  withEdge,
  withNode,
  withoutEdge,
  withoutNode,
} from './edits.ts';
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
