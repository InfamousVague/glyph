import { describe, expect, it } from 'vitest';
import { ganttOf, ganttWords, ticksFor } from './gantt.ts';
import type { Group, Row } from './run.ts';

/*
 * A query as a gantt (core/query/gantt.ts): the bars Mermaid draws, and a record's words made safe for Mermaid's own
 * grammar, since they are whatever a person wrote.
 */

const row = (over: Partial<Row>): Row => ({
  key: 'k',
  kind: 'task',
  noteId: 'n',
  line: 0,
  source: '',
  anchor: null,
  name: 'Ship it',
  id: null,
  done: false,
  category: 'todo',
  workflow: [],
  cells: [],
  day: null,
  start: null,
  due: null,
  overdue: false,
  ...over,
});
const group = (label: string, rows: Row[]): Group => ({ key: label, label, cell: null, rows, totals: [] });

describe('a record’s words in a gantt', () => {
  it('keeps them one line Mermaid reads as words', () => {
    expect(ganttWords('Fix: the login; loop #2', 'x')).toBe('Fix the login loop 2');
    expect(ganttWords('Line one\nline two', 'x')).toBe('Line one line two');
    expect(ganttWords('100%% done', 'x')).toBe('100% done');
  });

  it('sets apart words that start like one of Mermaid’s lines', () => {
    expect(ganttWords('section of the fence', 'x')).toBe(' section of the fence');
    expect(ganttWords('Title page', 'x')).toBe(' Title page');
    expect(ganttWords('Sectional sofa', 'x')).toBe('Sectional sofa');
  });

  it('falls back where nothing is left, and keeps a long name short', () => {
    expect(ganttWords(' :;# ', 'Untitled')).toBe('Untitled');
    expect(ganttWords('a'.repeat(200), 'x')).toHaveLength(80);
  });
});

describe('the bars', () => {
  it('runs a bar from its start to the end of its due day, and a bar of one day where it has one of them', () => {
    const { code, placed } = ganttOf([group('', [row({ start: '2026-10-01', due: '2026-10-03' }), row({ name: 'Due only', due: '2026-10-07' }), row({ name: 'Start only', start: '2026-10-09' })])], 'To-dos');
    expect(placed).toBe(3);
    // Not grouped: no section, so the bars have the room a section's name would take.
    expect(code.split('\n').slice(5)).toEqual(['  Ship it :2026-10-01, 2026-10-04', '  Due only :2026-10-07, 2026-10-08', '  Start only :2026-10-09, 2026-10-10']);
  });

  it('is laid out for a phone, in a directive any Mermaid reads, its ticks as far apart as the bars span', () => {
    const { code } = ganttOf([group('', [row({ start: '2026-10-01', due: '2026-10-03' })])]);
    const lines = code.split('\n');
    expect(lines[0]).toMatch(/^%%\{init: \{"gantt":\{"leftPadding":8,"rightPadding":16,/);
    expect(lines.slice(1, 5)).toEqual(['gantt', '  dateFormat YYYY-MM-DD', '  axisFormat %e', '  tickInterval 1day']);
    expect(ganttOf([group('Doing', [row({ due: '2026-10-01' })]), group('Done', [row({ due: '2026-11-20' })])]).code).toContain('"leftPadding":80');
  });

  it('spaces its ticks a day, a week or a month apart', () => {
    expect(ticksFor(7)).toEqual({ tick: '1day', axis: '%e' });
    expect(ticksFor(30)).toEqual({ tick: '1week', axis: '%e %b' });
    expect(ticksFor(200)).toEqual({ tick: '1month', axis: '%b' });
    expect(ticksFor(900)).toEqual({ tick: '3month', axis: '%b %Y' });
  });

  it('turns a start after the due day round, and leaves out a record with neither', () => {
    const { code, placed } = ganttOf([group('', [row({ start: '2026-10-05', due: '2026-10-02' }), row({ name: 'Undated' })])]);
    expect(placed).toBe(1);
    expect(code).toContain('Ship it :2026-10-02, 2026-10-06');
    expect(code).not.toContain('Undated');
  });

  it('marks done, under way and overdue in Mermaid’s own words, and names a ticket by its key', () => {
    const { code } = ganttOf([
      group('Doing', [row({ id: 'GHO-4', name: 'Pricing', category: 'doing', due: '2026-10-01', overdue: true }), row({ name: 'Old', done: true, category: 'done', due: '2026-09-01' })]),
    ]);
    expect(code).toContain('  section Doing');
    expect(code).toContain('  GHO-4 Pricing :active, crit, 2026-10-01, 2026-10-02');
    expect(code).toContain('  Old :done, 2026-09-01, 2026-09-02');
  });

  it('leaves out a group with no bars, and is empty with none at all', () => {
    expect(ganttOf([group('Empty', [row({})]), group('Some', [row({ due: '2026-10-01' })])]).code).not.toContain('Empty');
    expect(ganttOf([group('', [row({})])])).toEqual({ code: '', placed: 0 });
  });
});
