import { describe, expect, it } from 'vitest';
import { parseCanvas, serializeCanvas, withCanvas } from './jsonCanvas.ts';

/** The threads in a canvas's JSON (docs/SHARED.md, S9): read leniently with the rest, written after the edges when there are any. */

const WITH = `{
  "nodes": [
    { "id": "book", "type": "text", "x": 0, "y": 0, "width": 260, "height": 100, "text": "# Book the cabin" }
  ],
  "edges": [],
  "comments": [
    { "id": "c1", "node": "book", "by": "matt", "at": "2026-10-05T14:00:00Z", "text": "Which Friday?", "replies": [ { "by": "sam", "at": "2026-10-05T14:05:00Z", "text": "The 10th." } ], "resolved": { "by": "sam", "at": "2026-10-05T14:06:00Z" } },
    { "id": "c2", "node": "gone", "by": "lee", "at": "2026-10-05T14:07:00Z", "text": "On a card that is not there", "replies": [] },
    { "id": "c3", "node": "book", "by": "lee", "at": "2026-10-05T14:08:00Z", "text": "Open, with a reply that is not one and no resolved", "replies": [ { "by": "x" }, 4 ], "resolved": { "by": 1 } },
    { "id": "c1", "node": "book", "by": "twice", "at": "2026-10-05T14:09:00Z", "text": "The same id again", "replies": [] }
  ]
}`;

describe('a canvas’s threads in its JSON', () => {
  it('reads the threads on cards that are there, drops what is not a thread, and keeps the first of an id', () => {
    const canvas = parseCanvas(WITH)!;
    expect(canvas.comments?.map((thread) => thread.id)).toEqual(['c1', 'c3']);
    expect(canvas.comments?.[0]).toEqual({ id: 'c1', node: 'book', by: 'matt', at: '2026-10-05T14:00:00Z', text: 'Which Friday?', replies: [{ by: 'sam', at: '2026-10-05T14:05:00Z', text: 'The 10th.' }], resolved: { by: 'sam', at: '2026-10-05T14:06:00Z' } });
    expect(canvas.comments?.[1]).toEqual({ id: 'c3', node: 'book', by: 'lee', at: '2026-10-05T14:08:00Z', text: 'Open, with a reply that is not one and no resolved', replies: [] });
  });

  it('writes them after the edges, and nothing at all for a canvas without any', () => {
    const canvas = parseCanvas(WITH)!;
    const written = serializeCanvas(canvas);
    expect(written.indexOf('"comments"')).toBeGreaterThan(written.indexOf('"edges"'));
    expect(parseCanvas(written)).toEqual(canvas);
    expect(serializeCanvas({ nodes: canvas.nodes, edges: [] })).not.toContain('comments');
    expect(serializeCanvas({ nodes: canvas.nodes, edges: [], comments: [] })).not.toContain('comments');
    expect(withCanvas('---\ntitle: "Plan"\n---\n{}\n', canvas)).toContain('"comments": [');
  });
});
