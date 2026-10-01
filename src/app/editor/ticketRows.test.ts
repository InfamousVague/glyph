import { describe, expect, it } from 'vitest';
import { inLocale } from '../../test/locale.ts';
import { dayLabel, dueState, hiddenRows, linksValue, linkTo, otherKeys, panelRows } from './ticketRows.ts';

/**
 * What a ticket's panel shows (editor/ticketRows.ts; docs/DESIGN.md §157): the rows a ticket has, the keys left to the
 * quiet line, a day in words, a due day passed, and another ticket as a property links it.
 */

const FRONT = '---\ntype: ticket\nid: GHO-12\nstatus: In progress\nestimate: 3\nlabels: []\ntitle: "Login"\nlook: reading\nauthors: Matt\n---';

describe('the rows', () => {
  it('are Status, Assignee, Priority and Due always, then each of the rest a ticket has, in the panel’s order', () => {
    expect(panelRows(FRONT)).toEqual(['status', 'assignee', 'priority', 'due', 'estimate']);
    // An empty list is not a value: Labels waits behind More.
    expect(hiddenRows(FRONT)).toEqual(['start', 'blocked-by', 'parent', 'labels']);
    expect(panelRows(FRONT, true)).toEqual(['status', 'assignee', 'priority', 'due', 'start', 'estimate', 'blocked-by', 'parent', 'labels']);
  });

  it('leave the keys a ticket does not have to the quiet line, not its type, its id or its look', () => {
    expect(otherKeys(FRONT)).toEqual(['title', 'authors']);
    expect(otherKeys('---\ntype: ticket\n---')).toEqual([]);
  });
});

describe('a day', () => {
  const say = (iso: string) => inLocale('en-GB', () => dayLabel(iso, '2026-10-01'));

  it('is said as today, tomorrow or yesterday, else its weekday and date, with the year only when it is another', () => {
    expect(say('2026-10-01')).toBe('Today');
    expect(say('2026-10-02')).toBe('Tomorrow');
    expect(say('2026-09-30')).toBe('Yesterday');
    expect(say('2026-10-03')).toBe('Sat 3 Oct');
    expect(say('2027-01-04')).toBe('Mon, 4 Jan 2027');
    // A day written by hand that is not one is said as it was written.
    expect(say('soon')).toBe('soon');
  });

  it('is overdue once it has passed with the ticket not done, and due today on the day', () => {
    expect(dueState('2026-09-30', '2026-10-01', 'doing')).toBe('overdue');
    expect(dueState('2026-10-01', '2026-10-01', 'todo')).toBe('today');
    expect(dueState('2026-10-03', '2026-10-01', 'todo')).toBeNull();
    expect(dueState('2026-09-30', '2026-10-01', 'done')).toBeNull();
    expect(dueState(null, '2026-10-01', 'todo')).toBeNull();
  });
});

describe('a link to another ticket', () => {
  it('is its key where it has one, else its title', () => {
    expect(linkTo({ key: 'GHO-9', title: 'Fix the cookie', status: 'To do', category: 'todo' })).toBe('[[GHO-9]]');
    expect(linkTo({ key: null, title: 'Fix the cookie', status: null, category: 'todo' })).toBe('[[Fix the cookie]]');
  });

  it('is written as nothing, one quoted value, or a list across', () => {
    expect(linksValue([])).toBeNull();
    expect(linksValue(['[[GHO-9]]'])).toBe('[[GHO-9]]');
    expect(linksValue(['[[GHO-9]]', '[[GHO-10]]'])).toEqual(['[[GHO-9]]', '[[GHO-10]]']);
  });
});
