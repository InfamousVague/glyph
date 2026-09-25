import { describe, expect, it } from 'vitest';
import { noteTitle } from '../core/noteTitle.ts';
import { SPEC_SAMPLE } from '../../test/canvas.ts';
import { canvasNoteBody, canvasOf, isCanvasBody, parseCanvas, serializeCanvas, withCanvas, type Canvas } from './jsonCanvas.ts';

/** The format read leniently and written exactly, and the note a canvas is: front matter naming it, then the JSON. */

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
  const sample = parseCanvas(SPEC_SAMPLE) as Canvas;
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

  // Until 2026-09-25 a canvas took any block that closed within forty lines as front matter, words and all; it now
  // takes what the list takes (core/frontMatter.ts), so the note it names is the note the list names.
  it('has front matter as the list reads it, and a rule with words under it is not that', () => {
    expect(isCanvasBody('---\nA rule, then words\n---\n{ "nodes": [] }')).toBe(false);
    const titled = '---\ntitle: "Plan"\n\ntags: [trip]\n---\n{ "nodes": [] }';
    expect(isCanvasBody(titled)).toBe(true);
    expect(withCanvas(titled, canvas).startsWith('---\ntitle: "Plan"\n\ntags: [trip]\n---\n{')).toBe(true);
  });

  it('puts the canvas back into its note and keeps the front matter as it was', () => {
    const body = `---\ntitle: "Cabin"\ntags: [trip]\n---\n{ "nodes": [] }\n`;
    const next = withCanvas(body, sample);
    expect(next.startsWith('---\ntitle: "Cabin"\ntags: [trip]\n---\n')).toBe(true);
    expect(canvasOf(next)).toEqual(sample);
    expect(noteTitle(next)).toBe('Cabin');
    // A body with no front matter is the canvas alone.
    expect(canvasOf(withCanvas('{ "nodes": [] }', sample))).toEqual(sample);
  });
});

describe('what a node keeps', () => {
  it('keeps a group’s picture and how it is laid, a 3-digit hex colour, and an anchor that is one; drops what is not', () => {
    const canvas = parseCanvas(`{ "nodes": [
      { "id": "g", "type": "group", "x": 0, "y": 0, "width": 10, "height": 10, "background": "sky.png", "backgroundStyle": "ratio", "color": "#f80" },
      { "id": "h", "type": "group", "x": 0, "y": 0, "width": 10, "height": 10, "background": "", "backgroundStyle": "stretch", "label": "" },
      { "id": "f", "type": "file", "x": 0, "y": 0, "width": 10, "height": 10, "file": "Trip.md", "subpath": "^friday" },
      { "id": "e", "type": "file", "x": 0, "y": 0, "width": 10, "height": 10, "file": "" },
      { "id": "u", "type": "link", "x": 0, "y": 0, "width": 10, "height": 10, "url": "" },
      { "id": "c", "type": "text", "x": 0, "y": 0, "width": 10, "height": 10, "text": "hi", "color": "#ff88" }
    ] }`) as Canvas;
    expect(canvas.nodes.map((n) => n.id)).toEqual(['g', 'h', 'f', 'c']);
    expect(canvas.nodes[0]).toEqual({ id: 'g', type: 'group', x: 0, y: 0, width: 10, height: 10, color: '#f80', background: 'sky.png', backgroundStyle: 'ratio' });
    expect(canvas.nodes[1]).toEqual({ id: 'h', type: 'group', x: 0, y: 0, width: 10, height: 10 });
    expect(canvas.nodes[2]).not.toHaveProperty('subpath');
    expect(canvas.nodes[3]).not.toHaveProperty('color');
  });

  it('keeps only the sides and ends the spec names on a line, and a line with no words has no label', () => {
    const canvas = parseCanvas(`{
      "nodes": [
        { "id": "a", "type": "text", "x": 0, "y": 0, "width": 10, "height": 10, "text": "a" },
        { "id": "b", "type": "text", "x": 50, "y": 0, "width": 10, "height": 10, "text": "b" }
      ],
      "edges": [{ "id": "e", "fromNode": "a", "toNode": "b", "fromSide": "top", "toSide": "under", "fromEnd": "arrow", "toEnd": "dot", "label": "", "color": "7" }]
    }`) as Canvas;
    expect(canvas.edges).toEqual([{ id: 'e', fromNode: 'a', toNode: 'b', fromSide: 'top', fromEnd: 'arrow' }]);
  });
});

describe('front matter a canvas note may have', () => {
  const canvas: Canvas = { nodes: [{ id: 'a', type: 'text', x: 0, y: 0, width: 100, height: 50, text: 'hi' }], edges: [] };
  const json = serializeCanvas(canvas);

  it('reads a canvas under +++ fences, and keeps them when it writes', () => {
    const body = `+++\ntitle: "Plan"\n+++\n${json}`;
    expect(canvasOf(body)).toEqual(canvas);
    expect(withCanvas(body, { nodes: [], edges: [] }).startsWith('+++\ntitle: "Plan"\n+++\n{')).toBe(true);
  });

  it('is not a canvas under a fence that never closes, or closes past the fortieth line', () => {
    expect(isCanvasBody(`---\ntitle: "Plan"\n${json}`)).toBe(false);
    const long = ['---', ...Array.from({ length: 40 }, (_, i) => `key${i}: ${i}`), '---', json].join('\n');
    expect(isCanvasBody(long)).toBe(false);
    const fits = ['---', ...Array.from({ length: 37 }, (_, i) => `key${i}: ${i}`), '---', json].join('\n');
    expect(canvasOf(fits)).toEqual(canvas);
  });
});
