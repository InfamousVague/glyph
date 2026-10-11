import { describe, expect, it } from 'vitest';
import { noteTitle } from '../noteTitle.ts';
import {
  addReply,
  addThread,
  applyEdits,
  countsBy,
  countWords,
  deleteThread,
  freshId,
  readComments,
  reopenThread,
  resolveThread,
  stampNow,
  threadCounts,
  threadOf,
  withoutAnchors,
} from './format.ts';

/*
 * Comments in the markdown (docs/SHARED.md, S8): the anchor in the prose, the fence at the end, read without rewriting
 * and changed by a few edits, so an unchanged note comes back as the same text and a hand-edited fence keeps its lines.
 */

const SPEC = [
  '# Barn dance',
  '',
  'The ==venue==[^c1] is booked.',
  '',
  '```comments',
  'c1 matt 2026-10-04T19:00:12Z',
  'The venue needs confirming - the hall or the barn?',
  '  sam 2026-10-04T19:05:40Z',
  '  The hall. Confirmed this morning.',
  '  resolved sam 2026-10-04T19:06:02Z',
  '```',
  '',
].join('\n');

const MATT = { by: 'matt', at: '2026-10-05T09:00:00Z' };
const SAM = { by: 'sam', at: '2026-10-05T09:10:00Z' };

/** The note after `edits`, failing the test where an operation answered nothing. */
function after(body: string, edits: ReturnType<typeof addThread>): string {
  expect(edits).not.toBeNull();
  return applyEdits(body, edits!);
}

describe('reading the comments', () => {
  it('reads the example in SHARED.md: a thread, its reply, its resolution and its anchor round a selection', () => {
    const read = readComments(SPEC);
    expect(read.threads).toHaveLength(1);
    const thread = read.threads[0]!;
    expect(thread.id).toBe('c1');
    expect(thread.head).toEqual({ by: 'matt', at: '2026-10-04T19:00:12Z', words: 'The venue needs confirming - the hall or the barn?', line: 6 });
    expect(thread.replies).toEqual([{ by: 'sam', at: '2026-10-04T19:05:40Z', words: 'The hall. Confirmed this morning.', line: 8 }]);
    expect(thread.resolved).toEqual({ by: 'sam', at: '2026-10-04T19:06:02Z', line: 10 });
    expect([thread.from, thread.to]).toEqual([6, 10]);
    expect(read.anchors).toHaveLength(1);
    const anchor = read.anchors[0]!;
    expect(SPEC.slice(anchor.from, anchor.to)).toBe('[^c1]');
    expect(SPEC.slice(anchor.wash!.from, anchor.wash!.to)).toBe('==venue==');
    expect(read.strays).toEqual([]);
  });

  it('reads an anchor after the words with no wash, and words over several lines', () => {
    const body = 'Call the caterer[^c2]\n\n```comments\nc2 me 2026-10-05T08:00:00Z\nWhich one?\nThe cheap one fell through.\n```';
    const read = readComments(body);
    expect(read.anchors[0]!.wash).toBeNull();
    expect(read.threads[0]!.head.words).toBe('Which one?\nThe cheap one fell through.');
    expect(read.fence).toMatchObject({ open: 3, close: 7 });
  });

  it('reads a note with no fence as no comments, and an anchor with no thread as no anchor', () => {
    expect(readComments('Just words[^c1]')).toEqual({ fence: null, threads: [], anchors: [], strays: [] });
    const body = 'a[^c9] b[^c1]\n\n```comments\nc1 me 2026-10-05T08:00:00Z\nHi\n```\n';
    expect(readComments(body).anchors.map((anchor) => anchor.id)).toEqual(['c1']);
  });

  it('keeps lines it does not understand as strays, and a malformed head as the words above it', () => {
    const body = [
      '```comments',
      'a note to self before any thread',
      'c1 me 2026-10-05T08:00:00Z',
      'First.',
      'c2 me yesterday',
      '  sam 2026-10-05T08:01:00Z',
      '  Reply.',
      'unindented after a reply',
      '```',
    ].join('\n');
    const read = readComments(body);
    expect(read.threads.map((thread) => thread.id)).toEqual(['c1']);
    // "c2 me yesterday" has no time it can read, so it is words - kept, never dropped.
    expect(read.threads[0]!.head.words).toBe('First.\nc2 me yesterday');
    expect(read.threads[0]!.replies[0]!.words).toBe('Reply.');
    expect(read.strays).toEqual([2, 8]);
  });

  it('reads a fence never closed to the end of the note', () => {
    const read = readComments('Hi[^c1]\n\n```comments\nc1 me 2026-10-05T08:00:00Z\nStill typing');
    expect(read.fence?.close).toBeNull();
    expect(read.threads[0]!.head.words).toBe('Still typing');
  });

  it('takes the last comments fence, and no anchor inside another code block', () => {
    const body = ['```', 'x[^c1]', '```', 'y[^c1]', '', '```comments', 'c1 me 2026-10-05T08:00:00Z', 'Real', '```'].join('\n');
    const read = readComments(body);
    expect(read.anchors).toHaveLength(1);
    expect(body.slice(read.anchors[0]!.from - 1, read.anchors[0]!.to)).toBe('y[^c1]');
  });

  it('does not read a comments fence shown inside another block, as the Guide shows one', () => {
    const body = ['A comment looks like this:', '', '````', 'The ==venue==[^c1]', '', '```comments', 'c1 me 2026-10-05T08:00:00Z', 'Hi', '```', '````', ''].join('\n');
    expect(readComments(body)).toEqual({ fence: null, threads: [], anchors: [], strays: [] });
  });

  it('does not take a footnote’s definition for an anchor', () => {
    const body = 'a[^c1]\n[^c1]: a footnote\n\n```comments\nc1 me 2026-10-05T08:00:00Z\nHi\n```';
    expect(readComments(body).anchors).toHaveLength(1);
  });
});

describe('a new thread', () => {
  it('washes a selection and anchors it, and makes the fence at the end with a blank line before it', () => {
    const body = '# Plan\n\nBook the barn for Saturday.\n';
    const from = body.indexOf('the barn');
    const next = after(body, addThread(body, { from, to: from + 'the barn'.length }, MATT, 'Which barn?', 'c1'));
    expect(next).toBe('# Plan\n\nBook ==the barn==[^c1] for Saturday.\n\n```comments\nc1 matt 2026-10-05T09:00:00Z\nWhich barn?\n```\n');
    expect(readComments(next).anchors[0]!.wash).not.toBeNull();
  });

  it('anchors after a line’s words, its trailing spaces aside', () => {
    const body = '# Plan  \nwords';
    expect(after(body, addThread(body, { line: 1 }, MATT, 'Rename it?', 'c1'))).toBe('# Plan[^c1]  \nwords\n\n```comments\nc1 matt 2026-10-05T09:00:00Z\nRename it?\n```\n');
  });

  it('adds a second thread at the end of the fence that is there', () => {
    const next = after(SPEC, addThread(SPEC, { line: 1 }, SAM, 'Good title.', 'c2'));
    const read = readComments(next);
    expect(read.threads.map((thread) => thread.id)).toEqual(['c1', 'c2']);
    expect(next.endsWith('  resolved sam 2026-10-04T19:06:02Z\nc2 sam 2026-10-05T09:10:00Z\nGood title.\n```\n')).toBe(true);
  });

  it('anchors a selection over several lines after its last line’s words, with no wash', () => {
    const body = 'one\ntwo\nthree';
    const next = after(body, addThread(body, { from: 1, to: 6 }, MATT, 'Hm', 'c1'));
    expect(next.startsWith('one\ntwo[^c1]\nthree')).toBe(true);
  });

  it('trims the selection’s spaces, and takes a highlight inside or whole as the wash', () => {
    const body = 'a ==big words== here';
    // Inside the highlight: anchored after its closing marks, no highlight opened inside another.
    const inside = body.indexOf('words');
    expect(after(body, addThread(body, { from: inside, to: inside + 5 }, MATT, 'x', 'c1')).split('\n')[0]).toBe('a ==big words==[^c1] here');
    // The highlight picked whole, with a space either side.
    const whole = body.indexOf(' ==big');
    expect(after(body, addThread(body, { from: whole, to: whole + ' ==big words== '.length }, MATT, 'x', 'c1')).split('\n')[0]).toBe('a ==big words==[^c1] here');
  });

  it('writes words over several lines, drops empty ones, and escapes a line that would read as a head', () => {
    const body = 'x';
    const next = after(body, addThread(body, { line: 1 }, MATT, 'First line\n\n  c9 sam 2026-10-04T19:00:00Z\n```\n\\back', 'c1'));
    expect(next).toContain('c1 matt 2026-10-05T09:00:00Z\nFirst line\n\\c9 sam 2026-10-04T19:00:00Z\n\\```\n\\\\back\n```');
    expect(readComments(next).threads).toHaveLength(1);
    expect(readComments(next).threads[0]!.head.words).toBe('First line\nc9 sam 2026-10-04T19:00:00Z\n```\n\\back');
  });

  it('says no to empty words, a line past the note, and a place inside the fence', () => {
    expect(addThread('x', { line: 1 }, MATT, '  \n ')).toBeNull();
    expect(addThread('x', { line: 4 }, MATT, 'hi')).toBeNull();
    const inFence = SPEC.indexOf('The venue needs');
    expect(addThread(SPEC, { from: inFence, to: inFence + 3 }, MATT, 'hi')).toBeNull();
  });

  it('writes a handle with no space in it, so the head reads back', () => {
    const next = after('x', addThread('x', { line: 1 }, { by: 'two words', at: MATT.at }, 'hi', 'c1'));
    expect(readComments(next).threads[0]!.head.by).toBe('two-words');
  });
});

describe('replies, resolving and reopening', () => {
  const OPEN = 'x[^c1]\n\n```comments\nc1 matt 2026-10-05T09:00:00Z\nWhich?\n```\n';

  it('puts a reply under the thread’s last comment, indented two', () => {
    const next = after(OPEN, addReply(OPEN, 'c1', SAM, 'This one.\nAnd that.'));
    expect(next).toBe('x[^c1]\n\n```comments\nc1 matt 2026-10-05T09:00:00Z\nWhich?\n  sam 2026-10-05T09:10:00Z\n  This one.\n  And that.\n```\n');
    expect(readComments(next).threads[0]!.replies[0]!.words).toBe('This one.\nAnd that.');
  });

  it('escapes a reply’s line that would read as a reply’s head', () => {
    const next = after(OPEN, addReply(OPEN, 'c1', SAM, 'matt 2026-10-05T09:00:00Z'));
    const thread = readComments(next).threads[0]!;
    expect(thread.replies).toHaveLength(1);
    expect(thread.replies[0]!.words).toBe('matt 2026-10-05T09:00:00Z');
  });

  it('resolves, reopens, and puts a reply to a closed thread before its resolution', () => {
    const resolved = after(OPEN, resolveThread(OPEN, 'c1', SAM));
    expect(resolved).toContain('Which?\n  resolved sam 2026-10-05T09:10:00Z\n```');
    expect(readComments(resolved).threads[0]!.resolved?.by).toBe('sam');
    expect(resolveThread(resolved, 'c1', SAM)).toBeNull();
    const replied = after(resolved, addReply(resolved, 'c1', MATT, 'Late word'));
    expect(replied).toContain('Which?\n  matt 2026-10-05T09:00:00Z\n  Late word\n  resolved sam');
    expect(after(resolved, reopenThread(resolved, 'c1'))).toBe(OPEN);
    expect(reopenThread(OPEN, 'c1')).toBeNull();
  });

  it('answers nothing for a thread that is not there', () => {
    expect(addReply(OPEN, 'c7', SAM, 'hi')).toBeNull();
    expect(resolveThread(OPEN, 'c7', SAM)).toBeNull();
    expect(deleteThread(OPEN, 'c7')).toBeNull();
  });
});

describe('deleting a thread', () => {
  it('takes the last thread, its anchor and its wash, and the fence with it, back to the words as they were', () => {
    const body = '# Plan\n\nBook the barn for Saturday.\n';
    const from = body.indexOf('the barn');
    const commented = after(body, addThread(body, { from, to: from + 8 }, MATT, 'Which barn?', 'c1'));
    expect(after(commented, deleteThread(commented, 'c1'))).toBe(body);
    const onLine = after(body, addThread(body, { line: 1 }, MATT, 'Name?', 'c1'));
    expect(after(onLine, deleteThread(onLine, 'c1'))).toBe(body);
  });

  it('takes one thread of two, leaving the other and the fence', () => {
    const two = after(SPEC, addThread(SPEC, { line: 1 }, SAM, 'Good title.', 'c2'));
    const next = after(two, deleteThread(two, 'c1'));
    expect(next).toBe('# Barn dance[^c2]\n\nThe venue is booked.\n\n```comments\nc2 sam 2026-10-05T09:10:00Z\nGood title.\n```\n');
    expect(after(next, deleteThread(next, 'c2'))).toBe('# Barn dance\n\nThe venue is booked.\n');
  });

  it('keeps the fence while lines that are no thread’s are in it', () => {
    const body = 'x[^c1]\n\n```comments\nmy own note\nc1 me 2026-10-05T08:00:00Z\nHi\n```';
    expect(after(body, deleteThread(body, 'c1'))).toBe('x\n\n```comments\nmy own note\n```');
  });
});

describe('ids, counts and labels', () => {
  it('makes a fresh id this note has not used, for a thread, an anchor or a footnote', () => {
    const tails = ['0', '0', '0', '0', '1', '1', '1', '1'];
    let i = 0;
    const random = () => Number.parseInt(tails[i++ % tails.length]!, 36) / 36;
    expect(freshId('nothing', random)).toBe('c0000');
    i = 0;
    expect(freshId('x[^c0000]', random)).toBe('c1111');
    i = 0;
    expect(freshId('```comments\nc0000 me 2026-10-05T08:00:00Z\n```', random)).toBe('c1111');
    expect(freshId('')).toMatch(/^c[0-9a-z]{4}$/);
  });

  it('round-trips an unchanged note exactly, by never writing what it read', () => {
    for (const body of [SPEC, '', 'x', 'a[^c1]\n```comments\nweird\n  c1\n```']) expect(applyEdits(body, [])).toBe(body);
  });

  it('counts threads and the open ones, and says them', () => {
    const two = after(SPEC, addThread(SPEC, { line: 1 }, SAM, 'Good title.', 'c2'));
    const threads = readComments(two).threads;
    expect(threadCounts(threads)).toEqual({ threads: 2, open: 1 });
    expect(countWords(threads)).toBe('2 comments, 1 open');
    expect(countWords(readComments(SPEC).threads)).toBe('1 comment, resolved');
    expect(countWords([])).toBeNull();
  });

  it('counts each person’s comments and replies from parsed threads', () => {
    const two = after(SPEC, addThread(SPEC, { line: 1 }, SAM, 'Good title.', 'c2'));
    const counts = countsBy(readComments(two).threads);
    expect(counts.get('matt')).toEqual({ comments: 1, replies: 0 });
    expect(counts.get('sam')).toEqual({ comments: 1, replies: 1 });
  });

  it('stamps the time to the second, in UTC', () => {
    expect(stampNow(new Date(Date.UTC(2026, 9, 5, 9, 1, 2, 345)))).toBe('2026-10-05T09:01:02Z');
  });

  it('keeps a title commented on called what it was', () => {
    expect(withoutAnchors('Plan[^c1] and ==this==[^c22]')).toBe('Plan and ==this==');
    expect(noteTitle('# Plan[^c1]\n\nwords')).toBe('Plan');
    expect(threadOf(readComments(SPEC), 'c1')?.id).toBe('c1');
  });
});
