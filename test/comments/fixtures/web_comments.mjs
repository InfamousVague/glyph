// What the web app's own comments module answers, written down for test/comments/parity_test.dart to hold the Dart
// port to. Reads tauri/ and writes nothing there:
//
//   node --experimental-strip-types test/comments/fixtures/web_comments.mjs > test/comments/fixtures/web_comments.json
//
// A seeded generator: notes are grown an operation at a time (a thread on a line or round a selection, a reply, a
// resolution, a reopening, a deletion), and for each the module's edits are kept as it gave them, with what it read
// of the note before. The note moves on by the edits laid in the order the editor's dispatch lays them (two at one
// place in the order given), which is the Dart `applyEdits`; the page's own `applyEdits` is recorded beside it.
import { addReply, addThread, applyEdits, countsBy, countWords, deleteThread, freshId, readComments, reopenThread, resolveThread, stampNow, threadCounts, withoutAnchors } from '../../../tauri/src/app/core/comments/format.ts';

let seed = 4242;
const random = () => {
  seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
  return seed / 4294967296;
};
const int = (n) => Math.floor(random() * n);
const pick = (list) => list[int(list.length)];

/** Edits as the editor lays them: by place from the end, two at one place in the order given. */
const dispatch = (body, edits) => {
  let out = body;
  for (const [, edit] of [...edits.entries()].sort(([i, a], [j, b]) => b.from - a.from || b.to - a.to || j - i)) out = out.slice(0, edit.from) + edit.insert + out.slice(edit.to);
  return out;
};

const PROSE = ['# Barn dance', '', 'The venue is booked.  ', 'Call the ==caterer== today', 'a ==big words== here and ==more==', '```', 'code [^c1] here', '```', '~~~js', 'x', '~~~', 'naïve café 🥛 line', '   ', '- [ ] a task', '[^c1]: a footnote', 'tail'];
const WORDS = ['Which barn?', 'First line\n\n  second line', 'c9 sam 2026-10-04T19:00:00Z', 'sam 2026-10-04T19:00:00Z', 'resolved sam 2026-10-04T19:00:00Z', '```', '~~~', '\\back', '  ', '', 'ünï 🥛 words', 'resolved', 'plain'];
const STAMPS = [{ by: 'matt', at: '2026-10-05T09:00:00Z' }, { by: 'sam', at: '2026-10-05T09:10:00.123Z' }, { by: 'two words', at: '2026-10-05T09:10+01:00' }, { by: '', at: '2026-10-05T09:10:00Z' }];
const read = (body) => readComments(body);

const notes = [];
for (let i = 0; i < 30; i += 1) {
  let body = Array.from({ length: 1 + int(8) }, () => pick(PROSE)).join('\n') + pick(['', '\n', '\n\n']);
  const first = body;
  const steps = [];
  let next = 1;
  for (let step = 0, n = 5 + int(10); step < n; step += 1) {
    const ids = read(body).threads.map((t) => t.id);
    const id = random() < 0.9 && ids.length ? pick(ids) : 'c404';
    // The first two always open a thread with something to say, so the rest have threads to work on.
    const roll = step < 2 ? 0.1 : random();
    const say = () => (step < 2 || random() < 0.8 ? pick(WORDS.filter((w) => w.trim())) : pick(WORDS));
    let op;
    let edits;
    if (roll < 0.25) {
      const line = 1 + int(body.split('\n').length + 1);
      op = { op: 'line', line, stamp: pick(STAMPS), words: say(), id: `c${next}` };
      edits = addThread(body, { line }, op.stamp, op.words, op.id);
    } else if (roll < 0.5) {
      const a = int(body.length + 2) - 1;
      const b = Math.min(body.length + 1, a + int(14));
      op = { op: 'span', from: random() < 0.1 ? b : a, to: random() < 0.1 ? a : b, stamp: pick(STAMPS), words: say(), id: `c${next}` };
      edits = addThread(body, { from: op.from, to: op.to }, op.stamp, op.words, op.id);
    } else if (roll < 0.7) {
      op = { op: 'reply', id, stamp: pick(STAMPS), words: say() };
      edits = addReply(body, id, op.stamp, op.words);
    } else if (roll < 0.8) {
      op = { op: 'resolve', id, stamp: pick(STAMPS) };
      edits = resolveThread(body, id, op.stamp);
    } else if (roll < 0.9) {
      op = { op: 'reopen', id };
      edits = reopenThread(body, id);
    } else {
      op = { op: 'delete', id };
      edits = deleteThread(body, id);
    }
    if (edits && (op.op === 'line' || op.op === 'span')) next += 1;
    const after = edits ? dispatch(body, edits) : body;
    const threads = read(body).threads;
    const page = edits ? applyEdits(body, edits) : body;
    // `read` and the counts are of the note BEFORE the step, which is the step before's `after` (or `first`).
    steps.push({ ...op, read: read(body), counts: threadCounts(threads), said: countWords(threads), by: Object.fromEntries(countsBy(threads)), edits, after, ...(page === after ? {} : { page }) });
    body = after;
  }
  notes.push({ first, steps, last: body, read: read(body), bare: withoutAnchors(body) });
}

const HAND = [
  '',
  'x',
  '```comments',
  '```comments\n```',
  '~~~ Comments  \nc1 me 2026-10-05T08:00:00Z\nHi\n~~~',
  '   ```comments\nc1 me 2026-10-05T08:00Z\nHi\n   ```',
  '    ```comments\nc1 me 2026-10-05T08:00Z\nHi\n    ```',
  'a[^c1]\n```comments\nweird\n  c1\n```',
  'a[^c1] b[^c1] ==c==[^c1] == d ==[^c1] ==e==f==[^c1]\n\n```comments\nc1 me 2026-10-05T08:00:00Z\nHi\n\n  \n  me 2026-10-05T08:00:00+0100\n  reply\nnot indented\n    deep\nresolved me 2026-10-05T08:00:00Z\nafter\n  x 2026-10-05T08:00:00Z\n  late\nc1 again 2026-10-05T08:00:00Z\ntwice\n```\nafter the fence[^c1]',
  '```comments\nc1 me 2026-10-05T08:00:00Z\nfirst\n```\nbetween[^c1][^c2]\n```comments\nc2 me 2026-10-05T08:00:00Z\nsecond\n```',
  'x[^c1]\r\n\r\n```comments\r\nc1 me 2026-10-05T08:00:00Z\r\nHi\r\n```\r\n',
  'x\n```comments\nc1 \\me 2026-10-05T08:00:00Z\nc2 me 2026-13-45T99:99:99Z   \n\\c3 me 2026-10-05T08:00:00Z\n```',
];
const hand = HAND.map((body) => ({ body, read: read(body) }));

const dice = (tails) => {
  let i = 0;
  return () => Number.parseInt(tails[i++ % tails.length], 36) / 36;
};
const ids = [
  ['nothing', ['0', '0', '0', '0', '1', '1', '1', '1']],
  ['x[^c0000]', ['0', '0', '0', '0', '1', '1', '1', '1']],
  ['```comments\nc0000 me 2026-10-05T08:00:00Z\n```', ['0', '0', '0', '0', '1', '1', '1', '1']],
  ['[^cz9az] and [^note] [^c 1]', ['z', '9', 'a', 'z', 'a', 'b', 'c', 'd']],
].map(([body, tails]) => ({ body, tails, id: freshId(body, dice(tails)) }));
const stamps = [0, 1759654862345, 253402300799999].map((at) => ({ at, stamp: stampNow(new Date(at)) }));

process.stdout.write(`${JSON.stringify({ notes, hand, ids, stamps })}\n`);
