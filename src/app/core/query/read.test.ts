import { describe, expect, it } from 'vitest';
import { fieldName, fieldsNamed, readQuery, type Query, type QueryProblem } from './read.ts';

/*
 * A query's lines, read (core/query/read.ts, docs/QUERIES.md): every clause, its defaults, the words a test compares
 * with, and the one sentence a query that cannot be read is answered with, at its line and column.
 */

function read(body: string): Query {
  const reading = readQuery(body);
  if (reading.problem) throw new Error(`${reading.problem.line}:${reading.problem.column} ${reading.problem.message}`);
  return reading.query;
}

function problem(body: string): QueryProblem {
  const reading = readQuery(body);
  if (!reading.problem) throw new Error('read, when a problem was expected');
  return reading.problem;
}

describe('a query with nothing in it', () => {
  it('reads every note, each clause left for its default', () => {
    expect(read('')).toEqual({ kind: 'notes', from: null, where: null, sort: [], group: null, show: null, columns: [], total: [], limit: null });
    expect(read('\n  \n')).toEqual(read(''));
  });

  it('leaves a clause with nothing after its colon for its default', () => {
    expect(read('from:\nwhere:\nshow:')).toEqual(read(''));
  });
});

describe('from:', () => {
  it('reads the kind of record first, in any of the ways it is said', () => {
    expect(read('from: tickets').kind).toBe('tickets');
    expect(read('from: Issues').kind).toBe('tickets');
    expect(read('from: tasks').kind).toBe('tasks');
    expect(read('from: to-dos').kind).toBe('tasks');
    expect(read('from: notes').kind).toBe('notes');
    expect(read('from: tasks').from).toBeNull();
  });

  it('reads a tag, a notebook, a person and words', () => {
    expect(read('from: #bug').from).toEqual({ kind: 'tag', tag: 'bug' });
    expect(read('from: #Work/Clients').from).toEqual({ kind: 'tag', tag: 'work/clients' });
    expect(read('from: [[Launch plan]]').from).toEqual({ kind: 'link', title: 'Launch plan' });
    expect(read('from: [[Launch plan#Goals|the plan]]').from).toEqual({ kind: 'link', title: 'Launch plan' });
    expect(read('from: @sam').from).toEqual({ kind: 'person', name: 'sam' });
    expect(read('from: "release notes"').from).toEqual({ kind: 'words', words: 'release notes' });
    expect(read('from: “curly quotes”').from).toEqual({ kind: 'words', words: 'curly quotes' });
  });

  it('reads filters side by side, or a comma, as all of them', () => {
    const all = { kind: 'and', all: [{ kind: 'tag', tag: 'bug' }, { kind: 'person', name: 'sam' }] };
    expect(read('from: tasks #bug @sam').from).toEqual(all);
    expect(read('from: tasks #bug, @sam').from).toEqual(all);
    expect(read('from: tasks #bug and @sam').from).toEqual(all);
  });

  it('reads or, not, a dash and brackets', () => {
    expect(read('from: #bug or #ui').from).toEqual({ kind: 'or', any: [{ kind: 'tag', tag: 'bug' }, { kind: 'tag', tag: 'ui' }] });
    expect(read('from: #bug -#wontfix').from).toEqual({ kind: 'and', all: [{ kind: 'tag', tag: 'bug' }, { kind: 'not', of: { kind: 'tag', tag: 'wontfix' } }] });
    expect(read('from: not [[Archive]]').from).toEqual({ kind: 'not', of: { kind: 'link', title: 'Archive' } });
    expect(read('from: (#bug or #ui) @sam').from).toEqual({
      kind: 'and',
      all: [{ kind: 'or', any: [{ kind: 'tag', tag: 'bug' }, { kind: 'tag', tag: 'ui' }] }, { kind: 'person', name: 'sam' }],
    });
  });

  it('says what is wrong with what it cannot read', () => {
    expect(problem('from: #bug tickets').message).toBe('“tickets” goes first in from:, before the #tags, [[notebooks]], @people and "words".');
    expect(problem('from: bugs').message).toContain('“bugs” isn’t something a query reads from');
    expect(problem('from: [[Launch plan').message).toBe('A [[ opened here is never closed with ]].');
    expect(problem('from: "open').message).toBe('A quote opened here is never closed.');
    expect(problem('from: (#bug or #ui').message).toBe('A bracket opened here is never closed.');
    expect(problem('from: #bug)').message).toBe('A bracket closes here that was never opened.');
    expect(problem('from: #bug or').message).toBe('Something to read from is missing after “or”.');
  });

  it('puts a problem at its line and column, counting from 1', () => {
    expect(problem('show: table\nfrom: #bug bugs')).toEqual(expect.objectContaining({ line: 2, column: 12 }));
    expect(problem('  from:   bugs')).toEqual(expect.objectContaining({ line: 1, column: 11 }));
  });
});

describe('where:', () => {
  it('reads a comparison, its field in Dataview’s form and its value read for what it is', () => {
    expect(read('where: status != Done').where).toEqual({ kind: 'compare', field: 'status', op: '!=', value: { kind: 'words', text: 'Done', quoted: false } });
    expect(read('where: estimate >= 3').where).toEqual({ kind: 'compare', field: 'estimate', op: '>=', value: { kind: 'number', value: 3, text: '3' } });
    expect(read('where: due < 2026-10-03').where).toEqual({ kind: 'compare', field: 'due', op: '<', value: { kind: 'date', day: '2026-10-03' } });
    expect(read('where: Due-Date = today').where).toEqual({ kind: 'compare', field: 'due-date', op: '=', value: { kind: 'today', offset: 0, text: 'today' } });
  });

  it('reads a status of more than one word without quotes, and one with and in it with them', () => {
    expect(read('where: status = In progress').where).toEqual({ kind: 'compare', field: 'status', op: '=', value: { kind: 'words', text: 'In progress', quoted: false } });
    expect(read('where: status = "Won\'t do and done"').where).toEqual({
      kind: 'compare',
      field: 'status',
      op: '=',
      value: { kind: 'words', text: "Won't do and done", quoted: true },
    });
  });

  it('reads today counted on or back, in days or weeks, and tomorrow and yesterday', () => {
    const offset = (body: string) => {
      const where = read(body).where;
      return where?.kind === 'compare' && where.value.kind === 'today' ? where.value.offset : null;
    };
    expect(offset('where: due < today+7')).toBe(7);
    expect(offset('where: due < today + 7 days')).toBe(7);
    expect(offset('where: due > today-2w')).toBe(-14);
    expect(offset('where: due = tomorrow')).toBe(1);
    expect(offset('where: due = yesterday')).toBe(-1);
  });

  it('reads the other ways to write an operator', () => {
    const op = (body: string) => {
      const where = read(body).where;
      return where?.kind === 'compare' ? where.op : null;
    };
    expect(op('where: status == Done')).toBe('=');
    expect(op('where: status ≠ Done')).toBe('!=');
    expect(op('where: due ≤ today')).toBe('<=');
    expect(op('where: due ≥ today')).toBe('>=');
    expect(op('where: status is Done')).toBe('=');
    expect(op('where: status is not Done')).toBe('!=');
    expect(op('where: labels contains ui')).toBe('contains');
    expect(op('where: labels has ui')).toBe('contains');
    expect(op('where: labels not contains ui')).toBe('!contains');
  });

  it('reads is empty, is not empty, and a field alone', () => {
    expect(read('where: due is empty').where).toEqual({ kind: 'empty', field: 'due', empty: true });
    expect(read('where: assignee is not empty').where).toEqual({ kind: 'empty', field: 'assignee', empty: false });
    expect(read('where: due = empty').where).toEqual({ kind: 'compare', field: 'due', op: '=', value: { kind: 'empty' } });
    expect(read('where: blocked-by').where).toEqual({ kind: 'has', field: 'blocked-by' });
  });

  it('reads and before or, not, and brackets', () => {
    expect(read('where: status != Done and (priority >= high or due < today+7)').where).toEqual({
      kind: 'and',
      all: [
        { kind: 'compare', field: 'status', op: '!=', value: { kind: 'words', text: 'Done', quoted: false } },
        {
          kind: 'or',
          any: [
            { kind: 'compare', field: 'priority', op: '>=', value: { kind: 'words', text: 'high', quoted: false } },
            { kind: 'compare', field: 'due', op: '<', value: { kind: 'today', offset: 7, text: 'today+7' } },
          ],
        },
      ],
    });
    const mixed = read('where: a = 1 or b = 2 and c = 3').where;
    expect(mixed?.kind).toBe('or');
    expect(read('where: not checked').where).toEqual({ kind: 'not', of: { kind: 'has', field: 'checked' } });
  });

  it('reads the names a field is also called as the one the app keeps', () => {
    expect(fieldName('Assignees')).toBe('assignee');
    expect(fieldName('completed')).toBe('checked');
    expect(fieldName('completion')).toBe('done');
    expect(fieldName('Blocked By')).toBe('blocked-by');
    expect(read('where: people = Sam').where).toEqual(expect.objectContaining({ field: 'assignee' }));
  });

  it('joins two where: lines with and', () => {
    expect(read('where: status != Done\nwhere: assignee = Sam').where).toEqual({
      kind: 'and',
      all: [expect.objectContaining({ field: 'status' }), expect.objectContaining({ field: 'assignee' })],
    });
  });

  it('says what is wrong with a test it cannot read', () => {
    expect(problem('where: = Done').message).toBe('A field is missing here, like status or due, before “=”.');
    expect(problem('where: status !=').message).toBe('After “status !=”, something to compare it with: a word, a number, a date or empty.');
    expect(problem('where: status Done').message).toBe('After “status”, a comparison: =, !=, <, >, contains, or is empty.');
    expect(problem('where: due < 2026-02-30').message).toBe('“2026-02-30” isn’t a day on the calendar.');
    expect(problem('where: (status = Done').message).toBe('A bracket opened here is never closed.');
    expect(problem('where: status = Done)').message).toBe('A bracket closes here that was never opened.');
  });
});

describe('the other lines', () => {
  it('reads sort, each field asc or desc, with or without by', () => {
    expect(read('sort: priority desc, due').sort).toEqual([
      { field: 'priority', desc: true },
      { field: 'due', desc: false },
    ]);
    expect(read('sort by: Due Date descending').sort).toEqual([{ field: 'due-date', desc: true }]);
    expect(read('sort: by updated').sort).toEqual([{ field: 'updated', desc: false }]);
  });

  it('reads group by one field', () => {
    expect(read('group: status').group).toBe('status');
    expect(read('group by: assignee').group).toBe('assignee');
    expect(read('group: by priority').group).toBe('priority');
    expect(problem('group: status, assignee').message).toBe('A query groups by one field, like status.');
  });

  it('reads show as any of its ways, and the other words for them', () => {
    for (const way of ['table', 'list', 'board', 'calendar', 'gantt', 'count']) expect(read(`show: ${way}`).show).toBe(way);
    expect(read('show: Kanban').show).toBe('board');
    expect(read('show: timeline').show).toBe('gantt');
    expect(problem('show: pie').message).toBe('“pie” isn’t a way to show a query: table, list, board, calendar, gantt or count.');
  });

  it('reads columns and totals as lists of fields', () => {
    expect(read('columns: id, Title, Blocked By').columns).toEqual(['id', 'title', 'blocked-by']);
    expect(read('total: estimate, cost').total).toEqual(['estimate', 'cost']);
    expect(problem('columns: id, ti@tle').message).toBe('“ti@tle” isn’t a field’s name: a name is letters, numbers and dashes, like blocked-by.');
  });

  it('reads a limit, and says when it is not a whole number', () => {
    expect(read('limit: 20').limit).toBe(20);
    expect(problem('limit: twenty').message).toBe('A limit is a whole number, like 20.');
    expect(problem('limit: 0').message).toBe('A limit is a whole number, like 20.');
  });

  it('reads names in any case, and two words as one space', () => {
    expect(read('FROM: tickets\nSort  By: due').sort).toEqual([{ field: 'due', desc: false }]);
  });
});

describe('a line a query has not got', () => {
  it('says which it might have meant', () => {
    expect(problem('form: #bug').message).toBe('“form” isn’t a line a query has: did you mean “from”?');
    expect(problem('shwo: table').message).toBe('“shwo” isn’t a line a query has: did you mean “show”?');
  });

  it('lists them all where nothing is near', () => {
    expect(problem('colour: red').message).toBe('“colour” isn’t a line a query has: it has from, where, sort, group, show, columns, total and limit.');
  });

  it('says how a line is written where it has no colon', () => {
    expect(problem('just some words').message).toBe('A query’s line is a name, a colon and what it says, like “where: status != Done”.');
  });

  it('says when a line is written twice, and where the first is', () => {
    expect(problem('show: table\nfrom: #a\nshow: list')).toEqual({ line: 3, column: 1, message: '“show:” is written twice: a query has one, on line 1.' });
  });
});

describe('the fields a condition names', () => {
  it('walks and, or and not', () => {
    const where = read('where: status != Done and (not checked or due < today)').where;
    expect([...fieldsNamed(where)].sort()).toEqual(['checked', 'due', 'status']);
    expect(fieldsNamed(null).size).toBe(0);
  });
});
