import { describe, expect, it } from 'vitest';
import * as Y from 'yjs';
import { movedWithHeld, newEdge, newTextNode, withEdge, withGroup, withNode, withoutEdge, newGroupNode } from '../../canvas/edits.ts';
import { reopenedThread, resolvedThread, withReply, withThread, withoutThread } from '../../canvas/comments.ts';
import { canvasOf, parseCanvas, type Canvas } from '../../canvas/jsonCanvas.ts';
import { REMOTE } from '../live/session.ts';
import { CANVAS, canvasWords, hasTeamCanvas, reconcileCanvas, teamCanvas } from './canvas.ts';
import { teamDoc } from './doc.ts';
import { memoryDocs } from './docs.ts';

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

  it('writes a change into the types, which the words then say under the front matter, and tells what listens', () => {
    const a = device(SAMPLE);
    const team = teamCanvas(a)!;
    const heard: Canvas[] = [];
    team.onChange((canvas) => heard.push(canvas));
    team.apply(moved(team.canvas(), 'book', 48, 24));
    expect(nodeOf(team.canvas(), 'book')).toMatchObject({ x: 48, y: 24 });
    // The words are read from the types: the front matter as the text has it, then the spec's JSON as the note writes it.
    const words = canvasWords(a.doc, a.text.toString());
    expect(nodeOf(canvasOf(words)!, 'book')).toMatchObject({ x: 48, y: 24 });
    expect(words.startsWith('---\ntitle: "Plan"\n---\n{\n')).toBe(true);
    // The shared text itself is left alone: two members' JSON written into it at once would be no JSON at all.
    expect(nodeOf(canvasOf(a.text.toString())!, 'book')).toMatchObject({ x: 0, y: 0 });
    expect(heard).toHaveLength(1);
    // Only what changed is written: the other cards' words are the same Y.Text as before.
    const nodes = a.doc.getMap<Y.Map<unknown>>('canvas-nodes');
    const cardWords = nodes.get('book')!.get('text') as Y.Text;
    team.apply(written(team.canvas(), 'book', '# Book the cabin!'));
    expect(nodes.get('book')!.get('text')).toBe(cardWords);
    expect(cardWords.toString()).toBe('# Book the cabin!');
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

  it('merges two members’ threads: replies made at once both kept, a resolve and a reply apart both kept', () => {
    const a = device(SAMPLE);
    const teamA = teamCanvas(a)!;
    const b = device(Y.encodeStateAsUpdate(a.doc));
    const teamB = teamCanvas(b)!;
    const stamp = (by: string, at: string) => ({ by, at });
    teamA.apply(withThread(teamA.canvas(), 'book', stamp('matt', '2026-10-05T14:00:00Z'), 'Which Friday?', 'c1')!);
    sync(b, a);
    expect(teamB.canvas().comments).toHaveLength(1);
    // Both reply at the same moment: both replies land, in one order everywhere.
    teamA.apply(withReply(teamA.canvas(), 'c1', stamp('matt', '2026-10-05T14:01:00Z'), 'The 10th?')!);
    teamB.apply(withReply(teamB.canvas(), 'c1', stamp('sam', '2026-10-05T14:01:00Z'), 'The 17th.')!);
    both(a, b);
    expect(teamA.canvas().comments![0]!.replies.map((reply) => reply.text).sort()).toEqual(['The 10th?', 'The 17th.']);
    expect(teamB.canvas()).toEqual(teamA.canvas());
    // sam resolves while matt starts another thread on the link: both kept; the words follow on each device.
    teamB.apply(resolvedThread(teamB.canvas(), 'c1', stamp('sam', '2026-10-05T14:02:00Z'))!);
    teamA.apply(withThread(teamA.canvas(), 'site', stamp('matt', '2026-10-05T14:02:00Z'), 'Dead link?', 'c2')!);
    both(a, b);
    expect(teamA.canvas().comments!.map((thread) => [thread.id, Boolean(thread.resolved)])).toEqual([
      ['c1', true],
      ['c2', false],
    ]);
    expect(canvasOf(canvasWords(a.doc, a.text.toString()))!.comments).toEqual(teamA.canvas().comments);
    expect(canvasOf(canvasWords(b.doc, b.text.toString()))!.comments).toEqual(teamB.canvas().comments);
    // Reopened and deleted the same way.
    teamA.apply(reopenedThread(teamA.canvas(), 'c1')!);
    teamA.apply(withoutThread(teamA.canvas(), 'c2')!);
    sync(b, a);
    expect(teamB.canvas().comments!.map((thread) => [thread.id, Boolean(thread.resolved)])).toEqual([['c1', false]]);
  });

  it('keeps a thread through the view’s edits - a card moved, added, a line drawn and taken off, a group made - for every member', () => {
    const a = device(SAMPLE);
    const teamA = teamCanvas(a)!;
    const b = device(Y.encodeStateAsUpdate(a.doc));
    const teamB = teamCanvas(b)!;
    teamA.apply(withThread(teamA.canvas(), 'book', { by: 'matt', at: '2026-10-05T14:00:00Z' }, 'Which Friday?', 'c1')!);
    sync(b, a);
    const book = () => teamB.canvas().nodes.find((n) => n.id === 'book')!;
    teamB.apply(movedWithHeld(teamB.canvas(), book(), 48, 24));
    teamB.apply(withNode(teamB.canvas(), newTextNode(400, 0, 'more')));
    teamB.apply(withEdge(teamB.canvas(), newEdge('book', 'more', 'e2')));
    teamB.apply(withoutEdge(teamB.canvas(), 'e2'));
    teamB.apply(withGroup(teamB.canvas(), newGroupNode(book(), 0, 0, 'about')));
    expect(teamB.canvas().comments?.map((thread) => thread.id)).toEqual(['c1']);
    sync(a, b);
    expect(teamA.canvas().comments?.map((thread) => thread.id)).toEqual(['c1']);
    expect(canvasOf(canvasWords(a.doc, a.text.toString()))!.comments).toHaveLength(1);
  });

  it('reads words that reached the note without the view into the types, as the team document reconciles them', async () => {
    const a = device(SAMPLE);
    const teamA = teamCanvas(a)!;
    // Typed by hand in the JSON view, or written by Claude: words a pass reconciles into the document.
    const typed = a.text.toString().replace('"x": 0, "y": 160', '"x": 20, "y": 180');
    expect(reconcileCanvas(a.doc, typed)).toBe(true);
    expect(nodeOf(teamA.canvas(), 'site')).toMatchObject({ x: 20, y: 180 });
    expect(reconcileCanvas(a.doc, typed)).toBe(false);
    expect(reconcileCanvas(a.doc, '# Not a canvas')).toBe(false);
    expect(parseCanvas(canvasWords(a.doc, a.text.toString()).slice(canvasWords(a.doc, a.text.toString()).indexOf('{')))).not.toBeNull();
    // Through the team document itself: its words are the types', and a reconcile with a new name changes the front matter alone.
    const held = (await teamDoc('n-canvas', memoryDocs(), SAMPLE))!;
    teamCanvas(held)!.apply(moved(teamCanvas(held)!.canvas(), 'book', 3, 3));
    expect(nodeOf(canvasOf(held.words())!, 'book')).toMatchObject({ x: 3, y: 3 });
    expect(held.reconcile(held.words())).toBe(false);
    const renamed = held.words().replace('title: "Plan"', 'title: "Plan B"');
    expect(held.reconcile(renamed)).toBe(true);
    expect(held.words().startsWith('---\ntitle: "Plan B"\n---\n')).toBe(true);
    expect(nodeOf(canvasOf(held.words())!, 'book')).toMatchObject({ x: 3, y: 3 });
    const edited = held.words().replace('"x": 3', '"x": 30');
    expect(held.reconcile(edited)).toBe(true);
    expect(nodeOf(teamCanvas(held)!.canvas(), 'book')).toMatchObject({ x: 30 });
  });

  it('tells a change once, and keeps the order as the types hold it', () => {
    const a = device(SAMPLE);
    const team = teamCanvas(a)!;
    let told = 0;
    team.onChange(() => (told += 1));
    team.apply(moved(team.canvas(), 'book', 5, 5));
    expect(told).toBe(1);
    expect(a.doc.getArray('canvas-order').toArray()).toEqual(['before', 'book', 'site']);
    expect(CANVAS.toString()).toContain('canvas');
  });
});
