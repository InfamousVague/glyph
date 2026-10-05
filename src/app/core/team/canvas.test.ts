import { describe, expect, it } from 'vitest';
import * as Y from 'yjs';
import { canvasOf, parseCanvas, type Canvas } from '../../canvas/jsonCanvas.ts';
import { REMOTE } from '../live/session.ts';
import { CANVAS, hasTeamCanvas, teamCanvas } from './canvas.ts';
import { applyTextDiff } from './doc.ts';

/**
 * A team canvas as types in the note's document (core/team/canvas.ts; docs/SHARED.md, S9): seeded from the JSON,
 * written by the view's whole canvas as only what changed, the words kept in step, and two devices' edits merged
 * field by field rather than as a splice of two JSON strings.
 */

const SAMPLE = `---
title: "Plan"
---
{
  "nodes": [
    { "id": "before", "type": "group", "x": -40, "y": -40, "width": 660, "height": 340, "label": "Before" },
    { "id": "book", "type": "text", "x": 0, "y": 0, "width": 260, "height": 100, "text": "# Book the cabin", "color": "4" },
    { "id": "site", "type": "link", "x": 0, "y": 160, "width": 260, "height": 100, "url": "https://attack.fm/glyph" }
  ],
  "edges": [
    { "id": "e1", "fromNode": "book", "toNode": "site", "fromSide": "right", "toSide": "left", "label": "then" }
  ]
}
`;

/** A device's copy of the note: the document with its words, as core/team/doc.ts holds them. */
function device(words: string | Uint8Array) {
  const doc = new Y.Doc();
  const text = doc.getText('body');
  if (typeof words === 'string') text.insert(0, words);
  else Y.applyUpdate(doc, words, REMOTE);
  return { doc, text };
}

/** `from` brought up to date with `to`, as the room or the channel would: everything `to` has that `from` lacks. */
function sync(from: ReturnType<typeof device>, to: ReturnType<typeof device>) {
  Y.applyUpdate(from.doc, Y.encodeStateAsUpdate(to.doc, Y.encodeStateVector(from.doc)), REMOTE);
}
const both = (a: ReturnType<typeof device>, b: ReturnType<typeof device>) => {
  sync(a, b);
  sync(b, a);
};

const moved = (canvas: Canvas, id: string, x: number, y: number): Canvas => ({ ...canvas, nodes: canvas.nodes.map((n) => (n.id === id ? { ...n, x, y } : n)) });
const written = (canvas: Canvas, id: string, text: string): Canvas => ({ ...canvas, nodes: canvas.nodes.map((n) => (n.id === id && n.type === 'text' ? { ...n, text } : n)) });
const nodeOf = (canvas: Canvas, id: string) => canvas.nodes.find((n) => n.id === id)!;

describe('a team canvas', () => {
  it('is seeded from the note’s JSON once, reads back the same, and is not made for a note of words', () => {
    const a = device(SAMPLE);
    const team = teamCanvas(a)!;
    expect(team).not.toBeNull();
    expect(hasTeamCanvas(a.doc)).toBe(true);
    expect(team.canvas()).toEqual(canvasOf(SAMPLE));
    expect(teamCanvas(a)).toBe(team);
    expect(teamCanvas(device('# Just words\n\nNothing drawn.'))).toBeNull();
  });

  it('writes a change into the types and the words together, and tells what listens', () => {
    const a = device(SAMPLE);
    const team = teamCanvas(a)!;
    const heard: Canvas[] = [];
    team.onChange((canvas) => heard.push(canvas));
    team.apply(moved(team.canvas(), 'book', 48, 24));
    expect(nodeOf(team.canvas(), 'book')).toMatchObject({ x: 48, y: 24 });
    expect(nodeOf(canvasOf(a.text.toString())!, 'book')).toMatchObject({ x: 48, y: 24 });
    // The front matter is kept, and the words are the spec's JSON as the note writes it.
    expect(a.text.toString().startsWith('---\ntitle: "Plan"\n---\n{\n')).toBe(true);
    expect(heard).toHaveLength(1);
    // Only what changed is written: the other cards' words are the same Y.Text as before.
    const nodes = a.doc.getMap<Y.Map<unknown>>('canvas-nodes');
    const words = nodes.get('book')!.get('text') as Y.Text;
    team.apply(written(team.canvas(), 'book', '# Book the cabin!'));
    expect(nodes.get('book')!.get('text')).toBe(words);
    expect(words.toString()).toBe('# Book the cabin!');
  });

  it('merges two members’ edits field by field: a card each moved, and the same card typed in, both kept', () => {
    const a = device(SAMPLE);
    const teamA = teamCanvas(a)!;
    const b = device(Y.encodeStateAsUpdate(a.doc));
    const teamB = teamCanvas(b)!;
    expect(teamB.canvas()).toEqual(teamA.canvas());
    // Apart: matt moves the card, sam moves the link and types into the card.
    teamA.apply(moved(teamA.canvas(), 'book', 100, 100));
    teamB.apply(written(moved(teamB.canvas(), 'site', 300, 300), 'book', '# Book the cabin by Friday'));
    both(a, b);
    for (const team of [teamA, teamB]) {
      expect(nodeOf(team.canvas(), 'book')).toMatchObject({ x: 100, y: 100, text: '# Book the cabin by Friday' });
      expect(nodeOf(team.canvas(), 'site')).toMatchObject({ x: 300, y: 300 });
    }
    // The same card moved by both at once lands whole on one of the two places, never a splice of the numbers.
    teamA.apply(moved(teamA.canvas(), 'book', 10, 10));
    teamB.apply(moved(teamB.canvas(), 'book', 500, 500));
    both(a, b);
    const landed = nodeOf(teamA.canvas(), 'book');
    expect([10, 500]).toContain(landed.x);
    expect(landed.y).toBe(landed.x);
    expect(teamB.canvas()).toEqual(teamA.canvas());
  });

  it('adds and takes off cards and lines, keeps their order, and does not double an id two devices add at once', () => {
    const a = device(SAMPLE);
    const teamA = teamCanvas(a)!;
    const b = device(Y.encodeStateAsUpdate(a.doc));
    const teamB = teamCanvas(b)!;
    const card = { id: 'new', type: 'text', x: 400, y: 0, width: 200, height: 100, text: 'New' } as const;
    teamA.apply({ ...teamA.canvas(), nodes: [...teamA.canvas().nodes, card] });
    teamB.apply({ ...teamB.canvas(), nodes: [...teamB.canvas().nodes, { ...card, text: 'Also new' }], edges: [] });
    both(a, b);
    const ids = teamA.canvas().nodes.map((n) => n.id);
    expect(ids).toEqual(['before', 'book', 'site', 'new']);
    expect(teamA.canvas().edges).toEqual([]);
    expect(teamB.canvas()).toEqual(teamA.canvas());
    // A group made round the cards goes under them: first in the order.
    const group = { id: 'g2', type: 'group', x: -80, y: -80, width: 900, height: 600, label: 'All' } as const;
    teamA.apply({ ...teamA.canvas(), nodes: [group, ...teamA.canvas().nodes] });
    sync(b, a);
    expect(teamB.canvas().nodes.map((n) => n.id)).toEqual(['g2', 'before', 'book', 'site', 'new']);
    teamB.apply({ ...teamB.canvas(), nodes: teamB.canvas().nodes.filter((n) => n.id !== 'book') });
    sync(a, b);
    expect(teamA.canvas().nodes.map((n) => n.id)).toEqual(['g2', 'before', 'site', 'new']);
  });

  it('is seeded by two devices at once without either losing the other’s cards', () => {
    const a = device(SAMPLE);
    // The same note, adopted before either device had drawn it: both seed from the same JSON, apart.
    const b = device(Y.encodeStateAsUpdate(a.doc));
    const teamA = teamCanvas(a)!;
    const teamB = teamCanvas(b)!;
    teamA.apply(moved(teamA.canvas(), 'book', 7, 7));
    both(a, b);
    expect(teamB.canvas().nodes.map((n) => n.id)).toEqual(['before', 'book', 'site']);
    expect(teamA.canvas().nodes.map((n) => n.id)).toEqual(['before', 'book', 'site']);
    // A later write tidies the doubled order.
    teamB.apply(moved(teamB.canvas(), 'site', 9, 9));
    expect(b.doc.getArray('canvas-order').toArray()).toEqual(['before', 'book', 'site']);
  });

  it('reads words changed here without the types back into them, and leaves words that arrived from another device alone', async () => {
    const a = device(SAMPLE);
    const teamA = teamCanvas(a)!;
    // Typed by hand in the JSON view, or written by Claude and reconciled by a pass: a local change of the words.
    const typed = a.text.toString().replace('"x": 0, "y": 160', '"x": 20, "y": 180');
    applyTextDiff(a.text, a.text.toString(), typed);
    await Promise.resolve();
    expect(nodeOf(teamA.canvas(), 'site')).toMatchObject({ x: 20, y: 180 });
    // Words from another device carry their own types: a splice of two members' JSON would not be read.
    const b = device(Y.encodeStateAsUpdate(a.doc));
    const garbled = b.text.toString().replace('"x": 20, "y": 180', '"x": 2020, "y": 180');
    b.doc.transact(() => applyTextDiff(b.text, b.text.toString(), garbled), 'hand');
    sync(a, b);
    await Promise.resolve();
    expect(nodeOf(teamA.canvas(), 'site')).toMatchObject({ x: 20, y: 180 });
    // The next change here writes the JSON whole again, from the types.
    teamA.apply(moved(teamA.canvas(), 'book', 1, 1));
    expect(nodeOf(canvasOf(a.text.toString())!, 'site')).toMatchObject({ x: 20, y: 180 });
    expect(parseCanvas(a.text.toString().slice(a.text.toString().indexOf('{')))).not.toBeNull();
  });

  it('leaves a change of its own out of the follow, so the words and the types never chase each other', async () => {
    const a = device(SAMPLE);
    const team = teamCanvas(a)!;
    let told = 0;
    team.onChange(() => (told += 1));
    team.apply(moved(team.canvas(), 'book', 5, 5));
    await Promise.resolve();
    await Promise.resolve();
    expect(told).toBe(1);
    expect(a.doc.getArray('canvas-order').toArray()).toEqual(['before', 'book', 'site']);
    expect(CANVAS.toString()).toContain('canvas');
  });
});
