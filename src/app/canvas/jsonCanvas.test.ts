import { describe, expect, it } from 'vitest';
import { noteTitle } from '../core/store.ts';
import { anchorOf, bounds, canvasNoteBody, canvasOf, edgePath, fileTitle, HEAD, heldBy, isCanvasBody, joined, labelledEdge, labelledGroup, movedNode, movedWithHeld, newCanvasId, newEdge, newFileNode, newGroupAround, newLinkNode, newPictureNode, newTextNode, CHART_CARD, TABLE_CARD, paintOf, parseCanvas, resizedNode, serializeCanvas, sidesOf, withCanvas, withEdge, withNode, withoutEdge, withoutNode, type Canvas } from './jsonCanvas.ts';

const SPEC_SAMPLE = `{
  "nodes": [
    { "id": "g1", "type": "group", "x": -40, "y": -40, "width": 600, "height": 300, "label": "Before" },
    { "id": "t1", "type": "text", "x": 0, "y": 0, "width": 250, "height": 60, "text": "# Book the cabin", "color": "4" },
    { "id": "f1", "type": "file", "x": 300, "y": 0, "width": 250, "height": 120, "file": "Plans/Cabin trip.md", "subpath": "#^friday" },
    { "id": "l1", "type": "link", "x": 0, "y": 150.4, "width": 250, "height": 80, "url": "https://attack.fm/glyph", "color": "#ff8800" }
  ],
  "edges": [
    { "id": "e1", "fromNode": "t1", "toNode": "f1", "fromSide": "right", "toSide": "left", "label": "then" },
    { "id": "e2", "fromNode": "t1", "toNode": "l1", "toEnd": "none", "color": "2" }
  ]
}`;

describe('reading a JSON Canvas', () => {
  it('reads every node and edge the spec describes, and rounds a position to the pixel', () => {
    const canvas = parseCanvas(SPEC_SAMPLE);
    expect(canvas?.nodes.map((n) => n.type)).toEqual(['group', 'text', 'file', 'link']);
    expect(canvas?.nodes[3]).toMatchObject({ id: 'l1', y: 150, url: 'https://attack.fm/glyph', color: '#ff8800' });
    expect(canvas?.nodes[2]).toMatchObject({ file: 'Plans/Cabin trip.md', subpath: '#^friday' });
    expect(canvas?.edges).toEqual([
      { id: 'e1', fromNode: 't1', toNode: 'f1', fromSide: 'right', toSide: 'left', label: 'then' },
      { id: 'e2', fromNode: 't1', toNode: 'l1', toEnd: 'none', color: '2' },
    ]);
  });

  it('leaves out what is not a node, an edge to a node that is not there, and a second node with the same id', () => {
    const canvas = parseCanvas(`{
      "nodes": [
        { "id": "a", "type": "text", "x": 0, "y": 0, "width": 10, "height": 10, "text": "one" },
        { "id": "a", "type": "text", "x": 5, "y": 5, "width": 10, "height": 10, "text": "again" },
        { "id": "b", "type": "text", "x": 0, "y": 0, "width": 10, "height": 10 },
        { "id": "c", "type": "sticker", "x": 0, "y": 0, "width": 10, "height": 10 },
        { "id": "d", "type": "link", "x": "0", "y": 0, "width": 10, "height": 10, "url": "https://x" },
        { "id": "e", "type": "text", "x": 0, "y": 0, "width": 10, "height": 10, "text": "", "color": "9" }
      ],
      "edges": [
        { "id": "ok", "fromNode": "a", "toNode": "e", "fromSide": "middle" },
        { "id": "gone", "fromNode": "a", "toNode": "zz" },
        { "id": "ok", "fromNode": "e", "toNode": "a" }
      ]
    }`);
    expect(canvas?.nodes.map((n) => n.id)).toEqual(['a', 'e']);
    expect(canvas?.nodes[0]).toMatchObject({ text: 'one' });
    expect(canvas?.nodes[1]).not.toHaveProperty('color');
    expect(canvas?.edges).toEqual([{ id: 'ok', fromNode: 'a', toNode: 'e' }]);
  });

  it('is not a canvas when it is not JSON, not an object, or an object with neither nodes nor edges', () => {
    expect(parseCanvas('# A note')).toBeNull();
    expect(parseCanvas('[1, 2]')).toBeNull();
    expect(parseCanvas('{}')).toBeNull();
    expect(parseCanvas('{"nodes": []}')).toEqual({ nodes: [], edges: [] });
  });

  it('writes back what it read, in the spec’s shape, and nothing it did not', () => {
    const canvas = parseCanvas(SPEC_SAMPLE) as Canvas;
    const again = parseCanvas(serializeCanvas(canvas));
    expect(again).toEqual(canvas);
    expect(serializeCanvas(canvas).endsWith('\n')).toBe(true);
    expect(serializeCanvas(canvas)).not.toContain('undefined');
  });
});

describe('a canvas as a note', () => {
  const canvas: Canvas = { nodes: [{ id: 'a', type: 'text', x: 0, y: 0, width: 100, height: 50, text: 'hi' }], edges: [] };

  it('is front matter naming it, then the canvas; the note is titled by the front matter', () => {
    const body = canvasNoteBody('Cabin plan: the weekend', canvas);
    expect(body.startsWith('---\ntitle: "Cabin plan: the weekend"\n---\n{')).toBe(true);
    expect(noteTitle(body)).toBe('Cabin plan: the weekend');
    expect(canvasOf(body)).toEqual(canvas);
    expect(isCanvasBody(body)).toBe(true);
  });

  it('is read without front matter too, and a note of words is never one', () => {
    expect(canvasOf(serializeCanvas(canvas))).toEqual(canvas);
    expect(isCanvasBody('# Groceries\n\n- milk')).toBe(false);
    expect(isCanvasBody('---\ntitle: Plans\n---\n# Plans\n\n{ not a canvas }')).toBe(false);
    expect(isCanvasBody('')).toBe(false);
  });
});

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

  it('draws an edge as a curve with an arrow at its end unless told otherwise, stopping short of the head', () => {
    const e1 = edgePath(canvas, canvas.edges[0]!);
    expect(e1?.d.startsWith(`M250 30C`)).toBe(true);
    expect(e1?.d.endsWith(`${300 - HEAD} 60`)).toBe(true);
    expect(e1?.toHead?.startsWith('M300 60')).toBe(true);
    expect(e1?.fromHead).toBeNull();
    expect(e1?.mid.x).toBeGreaterThan(250);
    expect(e1?.mid.x).toBeLessThan(300);
    const e2 = edgePath(canvas, canvas.edges[1]!);
    expect(e2?.toHead).toBeNull();
    expect(e2?.d.endsWith('125 150')).toBe(true);
    expect(edgePath(canvas, { id: 'x', fromNode: 't1', toNode: 'nope' })).toBeNull();
  });
});

describe('colour and names', () => {
  it('paints the six presets as the page’s hues and keeps a chosen hex as it is', () => {
    expect(['1', '2', '3', '4', '5', '6'].map((c) => paintOf(c))).toEqual([{ hue: 'rose' }, { hue: 'ember' }, { hue: 'amber' }, { hue: 'moss' }, { hue: 'sea' }, { hue: 'violet' }]);
    expect(paintOf('#ff8800')).toEqual({ hex: '#ff8800' });
    expect(paintOf(undefined)).toBeNull();
  });

  it('names a file node by its file, without the folder or the .md', () => {
    expect(fileTitle('Plans/Cabin trip.md')).toBe('Cabin trip');
    expect(fileTitle('Cabin trip')).toBe('Cabin trip');
    expect(fileTitle('photos/tent.JPG')).toBe('tent.JPG');
  });
});

describe('changing a canvas', () => {
  const canvas = parseCanvas(SPEC_SAMPLE) as Canvas;

  it('puts the canvas back into its note and keeps the front matter as it was', () => {
    const body = `---\ntitle: "Cabin"\ntags: [trip]\n---\n{ "nodes": [] }\n`;
    const next = withCanvas(body, canvas);
    expect(next.startsWith('---\ntitle: "Cabin"\ntags: [trip]\n---\n')).toBe(true);
    expect(canvasOf(next)).toEqual(canvas);
    expect(noteTitle(next)).toBe('Cabin');
    // A body with no front matter is the canvas alone.
    expect(canvasOf(withCanvas('{ "nodes": [] }', canvas))).toEqual(canvas);
  });

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

  it('draws a new line with an arrow at its end and its sides worked out, adds it last, and takes it off again', () => {
    const line = newEdge('f1', 'l1', 'ln');
    expect(line).toEqual({ id: 'ln', fromNode: 'f1', toNode: 'l1' });
    const added = withEdge(canvas, line);
    expect(added.edges.at(-1)).toBe(line);
    expect(edgePath(added, line)?.toHead).not.toBeNull();
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

  it('draws a new group round the cards named, with room, under everything, and names it', () => {
    const grouped = newGroupAround(canvas, ['t1', 'l1'], 'Trip', 'gg')!;
    expect(grouped.nodes[0]).toMatchObject({ id: 'gg', type: 'group', label: 'Trip', x: -40, y: -64, width: 330, height: 334 });
    expect(heldBy(grouped, grouped.nodes[0]!).map((n) => n.id)).toEqual(['t1', 'l1']);
    expect(newGroupAround(canvas, ['nope'])).toBeNull();
    expect('label' in labelledGroup(grouped.nodes[0]!, '  ')).toBe(false);
    expect(labelledGroup(grouped.nodes[0]!, ' Plans ')).toMatchObject({ label: 'Plans' });
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
