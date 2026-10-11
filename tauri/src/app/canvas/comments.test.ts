import { describe, expect, it } from 'vitest';
import type { Canvas } from './jsonCanvas.ts';
import { freshThreadId, markOf, quoteOf, reopenedThread, resolvedThread, threadsOf, threadsOn, withReply, withThread, withoutThread } from './comments.ts';
import { withoutNode } from './edits.ts';

/** A canvas's threads (canvas/comments.ts; docs/SHARED.md, S9): started, replied to, resolved, reopened, taken off, and read for the card and the rounds. */

const canvas: Canvas = {
  nodes: [
    { id: 'book', type: 'text', x: 0, y: 0, width: 260, height: 100, text: '# Book the cabin\n\nBy Friday.' },
    { id: 'site', type: 'link', x: 0, y: 160, width: 260, height: 100, url: 'https://attack.fm/glyph' },
    { id: 'g', type: 'group', x: -40, y: -40, width: 600, height: 400, label: 'Before' },
    { id: 'note', type: 'file', x: 300, y: 0, width: 260, height: 100, file: 'Plans/Cabin trip.md' },
  ],
  edges: [],
};
const matt = { by: 'matt', at: '2026-10-05T14:00:00Z' };
const sam = { by: 'sam', at: '2026-10-05T14:05:00Z' };

describe('a canvas’s threads', () => {
  it('starts one on a card with the words trimmed, replies under it, resolves, reopens and takes it off', () => {
    const started = withThread(canvas, 'book', matt, '  Which Friday?  ', 'c1')!;
    expect(started.comments).toEqual([{ id: 'c1', node: 'book', by: 'matt', at: matt.at, text: 'Which Friday?', replies: [] }]);
    expect(withThread(canvas, 'nobody', matt, 'x')).toBeNull();
    expect(withThread(canvas, 'book', matt, '   ')).toBeNull();
    const replied = withReply(started, 'c1', sam, 'The 10th.')!;
    expect(replied.comments![0]!.replies).toEqual([{ by: 'sam', at: sam.at, text: 'The 10th.' }]);
    expect(withReply(started, 'c9', sam, 'x')).toBeNull();
    const resolved = resolvedThread(replied, 'c1', sam)!;
    expect(resolved.comments![0]!.resolved).toEqual({ by: 'sam', at: sam.at });
    expect(reopenedThread(resolved, 'c1')!.comments![0]!.resolved).toBeUndefined();
    expect(withoutThread(resolved, 'c1')!.comments).toBeUndefined();
    expect(withoutThread(canvas, 'c1')).toBeNull();
    // The canvas itself is never changed in place.
    expect(canvas.comments).toBeUndefined();
  });

  it('draws the threads as the card wants them, oldest first, and a card’s own apart', () => {
    const two = withThread(withThread(canvas, 'site', sam, 'Dead link?', 'c2')!, 'book', matt, 'Which Friday?', 'c1')!;
    expect(threadsOf(two).map((thread) => thread.id)).toEqual(['c1', 'c2']);
    expect(threadsOf(two)[0]).toEqual({ id: 'c1', head: { by: 'matt', at: matt.at, words: 'Which Friday?' }, replies: [], resolved: null });
    expect(threadsOn(two, 'site').map((thread) => thread.id)).toEqual(['c2']);
    expect(threadsOn(two, 'g')).toEqual([]);
  });

  it('marks a card by who started its first open thread and how many are open, hollow once all are resolved', () => {
    const one = withThread(canvas, 'book', matt, 'A', 'c1')!;
    const two = withThread(one, 'book', sam, 'B', 'c2')!;
    expect(markOf(two, 'book')).toEqual({ count: 2, open: 2, by: 'matt' });
    expect(markOf(two, 'site')).toBeNull();
    const first = resolvedThread(two, 'c1', sam)!;
    expect(markOf(first, 'book')).toEqual({ count: 2, open: 1, by: 'sam' });
    const all = resolvedThread(first, 'c2', matt)!;
    expect(markOf(all, 'book')).toEqual({ count: 2, open: 0, by: 'matt' });
  });

  it('quotes what a card says: its first line, its name, its address or its note’s title', () => {
    expect(quoteOf(canvas, 'book')).toBe('# Book the cabin');
    expect(quoteOf(canvas, 'g')).toBe('Before');
    expect(quoteOf(canvas, 'site')).toBe('https://attack.fm/glyph');
    expect(quoteOf(canvas, 'note')).toBe('Cabin trip');
    expect(quoteOf(canvas, 'nobody')).toBeNull();
    const long = { ...canvas, nodes: [{ ...canvas.nodes[0]!, text: 'x'.repeat(120) }] } as Canvas;
    expect(quoteOf(long, 'book')).toHaveLength(90);
  });

  it('gives a thread an id the canvas has not used, and lets a card’s threads go with the card', () => {
    const one = withThread(canvas, 'book', matt, 'A', 'c1')!;
    const ids = new Set<string>();
    let roll = 0;
    const random = () => ((roll += 7) % 36) / 36;
    for (let i = 0; i < 5; i += 1) ids.add(freshThreadId(one, random));
    expect(ids.has('c1')).toBe(false);
    expect([...ids].every((id) => /^c[0-9a-z]{4,}$/.test(id))).toBe(true);
    const two = withThread(one, 'site', sam, 'B', 'c2')!;
    expect(withoutNode(two, 'book').comments).toEqual([two.comments![1]]);
    expect(withoutNode(withoutNode(two, 'book'), 'site').comments).toBeUndefined();
  });
});
