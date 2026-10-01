import { describe, expect, it } from 'vitest';
import { queryFence, queryFencesIn, withQueryHeight } from './fence.ts';

/* Where a note's query fences are (core/query/fence.ts). */

describe('query fences', () => {
  it('finds each closed fence, its lines and its body', () => {
    const doc = '# Plan\n\n```query\nfrom: tickets\nshow: board\n```\n\nWords.\n\n~~~~QUERY\nfrom: tasks\n~~~~\n';
    expect(queryFencesIn(doc)).toEqual([
      { from: 3, to: 6, body: 'from: tickets\nshow: board', height: null },
      { from: 10, to: 12, body: 'from: tasks', height: null },
    ]);
  });

  it('is closed only by the same character, at least as long', () => {
    expect(queryFencesIn('````query\nfrom: tasks\n```\nstill in it\n````')).toEqual([{ from: 1, to: 5, body: 'from: tasks\n```\nstill in it', height: null }]);
    expect(queryFencesIn('~~~query\nfrom: tasks\n```\n~~~')).toEqual([{ from: 1, to: 4, body: 'from: tasks\n```', height: null }]);
  });

  it('is not a fence with other words on its line, or another kind', () => {
    expect(queryFencesIn('```query notes\nfrom: tasks\n```')).toEqual([]);
    expect(queryFencesIn('```board\nTo do: a\n```')).toEqual([]);
    expect(queryFencesIn('```js\nquery\n```')).toEqual([]);
  });

  it('draws nothing for a fence still being typed', () => {
    expect(queryFencesIn('```query\nfrom: tasks\n')).toEqual([]);
  });

  it('finds an empty query', () => {
    expect(queryFencesIn('```query\n```')).toEqual([{ from: 1, to: 2, body: '', height: null }]);
  });

  it('writes one as the + does', () => {
    expect(queryFence('from: tasks\nshow: list\n')).toBe('```query\nfrom: tasks\nshow: list\n```');
    expect(queryFencesIn(queryFence('from: tasks'))[0]?.body).toBe('from: tasks');
  });

  it('reads a board\'s height from the fence, kept within what a board can be', () => {
    expect(queryFencesIn('```query height=18\nshow: board\n```')[0]?.height).toBe(18);
    expect(queryFencesIn('```query height=900\nshow: board\n```')[0]?.height).toBe(60);
    expect(queryFencesIn('```query height=12.3em\n```')[0]?.height).toBe(12.5);
  });

  it('sets and takes off the height on the opening line, leaving the rest', () => {
    expect(withQueryHeight('```query', 20)).toBe('```query height=20');
    expect(withQueryHeight('```query height=20', 31.5)).toBe('```query height=31.5');
    expect(withQueryHeight('~~~query height=20 wide=yes', null)).toBe('~~~query wide=yes');
    expect(withQueryHeight('```board', 20)).toBe('```board');
  });
});
