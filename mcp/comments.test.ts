// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { readComments } from '../tauri/src/app/core/comments/format.ts';
import { commentOn, replyTo, resolve, stampOf, threadsIn } from './comments.ts';

/**
 * The connector's comments (docs/CLAUDE_LIVE.md, "Comments"), in the format tauri/docs/SHARED.md (S8) defines and the
 * app's own module reads: what a thread is answered as, and what a comment, a reply and a resolution write.
 */

const AT = new Date('2026-10-17T09:30:00.000Z');
const claude = stampOf('Claude', AT);

const NOTE = `# Trip

The venue needs confirming before Friday.

\`\`\`comments
c1 matt 2026-10-04T19:00:12Z
The hall or the barn?
  sam 2026-10-04T19:05:40Z
  The hall.
  resolved sam 2026-10-04T19:06:02Z
c2 sam 2026-10-05T08:00:00Z
Budget?
\`\`\`
`;

describe('reading threads', () => {
  it('answers each thread: its id, the words it is on, its messages and its resolution', () => {
    const body = NOTE.replace('The venue needs confirming', '==The venue==[^c1] needs confirming').replace('before Friday.', 'before Friday.[^c2]');
    expect(threadsIn(body)).toEqual([
      {
        id: 'c1',
        on: 'The venue',
        resolved: { by: 'sam', at: '2026-10-04T19:06:02Z' },
        messages: [
          { author: 'matt', at: '2026-10-04T19:00:12Z', text: 'The hall or the barn?' },
          { author: 'sam', at: '2026-10-04T19:05:40Z', text: 'The hall.' },
        ],
      },
      { id: 'c2', on: '==The venue== needs confirming before Friday.', resolved: null, messages: [{ author: 'sam', at: '2026-10-05T08:00:00Z', text: 'Budget?' }] },
    ]);
  });

  it('says a thread with no anchor is on nothing in particular, and a note with no fence has none', () => {
    expect(threadsIn(NOTE).map((thread) => thread.on)).toEqual([null, null]);
    expect(threadsIn('# Plain\n\nWords.')).toEqual([]);
  });
});

describe('writing', () => {
  it('comments on exact words, round them, with a fresh id and the fence made at the end', () => {
    const made = commentOn('# Trip\n\nWe leave on Monday.\n', 'on Monday', claude, 'Which Monday?', 'c9');
    expect(made).toEqual({ body: '# Trip\n\nWe leave ==on Monday==[^c9].\n\n```comments\nc9 Claude 2026-10-17T09:30:00Z\nWhich Monday?\n```\n', id: 'c9' });
  });

  it('never reuses an id the note has used', () => {
    const made = commentOn(NOTE, 'venue', claude, 'Booked?');
    if (!('body' in made)) throw new Error(made.refused);
    expect(['c1', 'c2']).not.toContain(made.id);
    expect(made.id).toMatch(/^c[0-9a-z]{4,}$/);
    expect(readComments(made.body).threads.map((thread) => thread.id)).toEqual(['c1', 'c2', made.id]);
  });

  it('puts a comment on the whole note after its first line of words, past the front matter', () => {
    const made = commentOn('---\nauthors: matt\n---\n# Trip\n\nWords.', undefined, claude, 'Looks good.', 'c7');
    expect('body' in made && made.body).toBe('---\nauthors: matt\n---\n# Trip[^c7]\n\nWords.\n\n```comments\nc7 Claude 2026-10-17T09:30:00Z\nLooks good.\n```\n');
  });

  it('refuses words the note does not have where a comment can go', () => {
    expect(commentOn(NOTE, 'nowhere', claude, 'x')).toMatchObject({ refused: expect.stringContaining('do not read “nowhere”') });
    // In a fence (here the comments fence itself) is no place for one.
    expect(commentOn(NOTE, 'The hall or the barn?', claude, 'x')).toMatchObject({ refused: expect.stringContaining('do not read') });
    expect(commentOn('a\n```\ncode here\n```\ncode here', 'code here', claude, 'x', 'c5')).toEqual({ body: 'a\n```\ncode here\n```\n==code here==[^c5]\n\n```comments\nc5 Claude 2026-10-17T09:30:00Z\nx\n```\n', id: 'c5' });
    expect(commentOn(NOTE, 'venue', claude, '  ')).toEqual({ refused: 'Say what the comment says.' });
  });

  it('replies under a thread’s last message, before its resolution', () => {
    const replied = replyTo(NOTE, 'c1', claude, 'Noted, thanks.');
    if (!('body' in replied)) throw new Error(replied.refused);
    expect(replied.body).toContain('  The hall.\n  Claude 2026-10-17T09:30:00Z\n  Noted, thanks.\n  resolved sam');
    const open = replyTo(NOTE, 'c2', claude, 'About 2,000.');
    expect('body' in open && open.body).toContain('Budget?\n  Claude 2026-10-17T09:30:00Z\n  About 2,000.\n```');
    expect(replyTo(NOTE, 'c3', claude, 'x')).toEqual({ refused: 'The note has no comment c3. Its threads are: c1, c2.' });
  });

  it('resolves an open thread, and says so of one already resolved', () => {
    const done = resolve(NOTE, 'c2', claude);
    expect('body' in done && done.body).toContain('Budget?\n  resolved Claude 2026-10-17T09:30:00Z\n```');
    expect(resolve(NOTE, 'c1', claude)).toEqual({ refused: 'The comment c1 was already resolved by sam at 2026-10-04T19:06:02Z.' });
    expect(resolve('# None', 'c1', claude)).toEqual({ refused: 'The note has no comment c1. It has no comments.' });
  });

  it('writes an author with a space in it as one handle', () => {
    const made = commentOn('Words.', 'Words', stampOf('Claude Code', AT), 'Hi', 'c4');
    expect('body' in made && threadsIn(made.body)[0]!.messages[0]!.author).toBe('Claude-Code');
  });
});
