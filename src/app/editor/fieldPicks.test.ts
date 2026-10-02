import { describe, expect, it, vi } from 'vitest';
import { DEFAULT_STATUSES } from '../core/properties.ts';
import type { Cell, Row } from '../core/query/run.ts';
import { HUES, hueOf, pickOf, picksField, statusLook } from './fieldPicks.ts';

/*
 * Which sheet a query's value opens, with what it holds now (editor/fieldPicks.ts; docs/DESIGN.md §169), and the marks
 * a status and a person wear in it.
 */

const row = (over: Partial<Row> = {}): Row => ({
  key: 'k',
  kind: 'ticket',
  noteId: 'n',
  line: -1,
  source: '',
  anchor: null,
  name: 'Fix the login loop',
  id: 'GHO-1',
  done: null,
  category: 'doing',
  workflow: DEFAULT_STATUSES,
  cells: [],
  day: null,
  start: null,
  due: null,
  overdue: false,
  ...over,
});
const EMPTY: Cell = { kind: 'empty' };
const TODAY = '2026-10-05';

describe('the sheet a value opens', () => {
  it('opens a ticket’s status on its workflow, with the status it has', () => {
    const workflow = ['Open', 'Doing', 'Shipped'];
    expect(pickOf(row({ workflow }), 'status', { kind: 'status', text: 'Doing', category: 'doing' }, TODAY, () => [])).toEqual({ kind: 'status', value: 'Doing', workflow });
    expect(pickOf(row(), 'status', EMPTY, TODAY, () => [])).toEqual({ kind: 'status', value: null, workflow: DEFAULT_STATUSES });
  });

  it('opens a to-do’s status as its box, To do or Done', () => {
    expect(pickOf(row({ kind: 'task', done: true }), 'status', EMPTY, TODAY, () => [])).toEqual({ kind: 'box', done: true });
    expect(pickOf(row({ kind: 'task', done: null }), 'status', EMPTY, TODAY, () => [])).toBeNull();
  });

  it('opens a priority, a person and a day with what each holds', () => {
    expect(pickOf(row(), 'priority', { kind: 'priority', name: 'high' }, TODAY, () => [])).toEqual({ kind: 'priority', value: 'high' });
    expect(pickOf(row(), 'Assignee', { kind: 'people', names: ['Sam'] }, TODAY, () => ['Sam', 'Alex'])).toEqual({ kind: 'person', value: 'Sam', people: ['Sam', 'Alex'] });
    expect(pickOf(row(), 'due', { kind: 'day', day: '2026-10-03', tone: 'overdue' }, TODAY, () => [])).toEqual({ kind: 'day', value: '2026-10-03', today: TODAY });
    expect(pickOf(row({ kind: 'task', done: false }), 'scheduled', EMPTY, TODAY, () => [])).toEqual({ kind: 'day', value: null, today: TODAY });
  });

  it('reads the people only for a person, since that reads every note', () => {
    const people = vi.fn(() => ['Sam']);
    pickOf(row(), 'priority', EMPTY, TODAY, people);
    pickOf(row(), 'status', EMPTY, TODAY, people);
    expect(people).not.toHaveBeenCalled();
  });

  it('opens nothing for what is not picked: a title, a tag, a ticket’s scheduled day', () => {
    for (const field of ['title', 'tags', 'note', 'estimate', 'updated']) expect(pickOf(row(), field, EMPTY, TODAY, () => []), field).toBeNull();
    expect(pickOf(row(), 'scheduled', EMPTY, TODAY, () => [])).toBeNull();
    expect(picksField(row(), 'title')).toBe(false);
    expect(picksField(row(), 'status')).toBe(true);
    expect(picksField(row({ kind: 'task', done: false }), 'scheduled')).toBe(true);
  });
});

describe('the marks', () => {
  it('marks a status by where it stands, a backlog and a review by name', () => {
    expect(DEFAULT_STATUSES.map((status) => statusLook(status, DEFAULT_STATUSES))).toEqual(['backlog', 'todo', 'doing', 'review', 'done']);
    expect(statusLook('Won’t do')).toBe('done');
  });

  it('gives a person one hue, however they are written', () => {
    expect(hueOf('sam')).toBe(hueOf('@Sam'));
    expect(HUES).toContain(hueOf('Priya Shah'));
  });
});
