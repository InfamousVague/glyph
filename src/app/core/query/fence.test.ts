import { describe, expect, it } from 'vitest';
import { queryFence, queryFencesIn } from './fence.ts';

/* Where a note's query fences are (core/query/fence.ts). */

describe('query fences', () => {
  it('finds each closed fence, its lines and its body', () => {
    const doc = '# Plan\n\n```query\nfrom: tickets\nshow: board\n```\n\nWords.\n\n~~~~QUERY\nfrom: tasks\n~~~~\n';
    expect(queryFencesIn(doc)).toEqual([
      { from: 3, to: 6, body: 'from: tickets\nshow: board' },
      { from: 10, to: 12, body: 'from: tasks' },
    ]);
  });

  it('is closed only by the same character, at least as long', () => {
    expect(queryFencesIn('````query\nfrom: tasks\n```\nstill in it\n````')).toEqual([{ from: 1, to: 5, body: 'from: tasks\n```\nstill in it' }]);
    expect(queryFencesIn('~~~query\nfrom: tasks\n```\n~~~')).toEqual([{ from: 1, to: 4, body: 'from: tasks\n```' }]);
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
    expect(queryFencesIn('```query\n```')).toEqual([{ from: 1, to: 2, body: '' }]);
  });

  it('writes one as the + does', () => {
    expect(queryFence('from: tasks\nshow: list\n')).toBe('```query\nfrom: tasks\nshow: list\n```');
    expect(queryFencesIn(queryFence('from: tasks'))[0]?.body).toBe('from: tasks');
  });
});
