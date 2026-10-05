import { describe, expect, it } from 'vitest';
import { readQuery } from './read.ts';
import { ticketDraft } from './draft.ts';

/** What a lane's new ticket must say for its board to list it there (core/query/draft.ts). */
const draft = (lines: string, lane: string | null, group: string | null = 'status') => {
  const { query } = readQuery(lines);
  if (!query) throw new Error(`unreadable: ${lines}`);
  return ticketDraft(query, query.group ?? group, lane);
};

describe('a ticket drafted from a lane of a query’s board', () => {
  it('takes the lane’s value for the field the board groups by', () => {
    expect(draft('from: tickets\nshow: board', 'In review')).toEqual({ link: null, fields: [['status', 'In review']], labels: [] });
    expect(draft('from: tickets\ngroup: assignee\nshow: board', 'sam')).toEqual({ link: null, fields: [['assignee', 'sam']], labels: [] });
  });

  it('takes the notebook, the tags and the person every record must come from, never one of several', () => {
    expect(draft('from: tickets [[GHST]] #bug @kebim\nshow: board', 'To do')).toEqual({
      link: 'GHST',
      fields: [['assignee', 'kebim'], ['status', 'To do']],
      labels: ['bug'],
    });
    expect(draft('from: tickets [[GHST]] or [[Other]]\nshow: board', 'To do')?.link).toBeNull();
    expect(draft('from: tickets not #bug\nshow: board', 'To do')?.labels).toEqual([]);
  });

  it('takes the equal tests every record must pass, and leaves the rest', () => {
    const made = draft('from: tickets\nwhere: priority = high and estimate = 3 and due < today and (assignee = sam or assignee = kebim) and status = Done\nshow: board', 'To do');
    // The lane's status wins over the query's own; a test under `or`, or not an equal, is the person's to meet.
    expect(made?.fields).toEqual([['priority', 'high'], ['estimate', '3'], ['status', 'To do']]);
  });

  it('never copies a field the ticket’s maker sets', () => {
    expect(draft('from: tickets\nwhere: type = ticket and id = GHO-4 and title = Plan\nshow: board', 'To do')?.fields).toEqual([['status', 'To do']]);
  });

  it('drafts nothing for a board of to-dos or of notes', () => {
    expect(draft('from: tasks\nshow: board', null)).toBeNull();
    expect(draft('from: notes\nshow: board', null)).toBeNull();
  });
});
