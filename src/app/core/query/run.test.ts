import { describe, expect, it } from 'vitest';
import { NOTES, TODAY } from './library.fixture.ts';
import { readQuery } from './read.ts';
import { libraryOf, noteNamed, recordCache, type QueryNote } from './records.ts';
import { runQuery, type QueryResult, type Row } from './run.ts';

/*
 * A query run over a library (core/query/records.ts, core/query/run.ts, docs/QUERIES.md): what is read from the notes,
 * the defaults that make `from: #bug` alone useful, the tests, the order, the groups a board and a table draw, the
 * totals, and what the drawing is handed. The library is core/query/library.fixture.ts; today is 5 October 2026.
 */

function run(body: string, notes: readonly QueryNote[] = NOTES, today = TODAY): QueryResult {
  const reading = readQuery(body);
  if (reading.problem) throw new Error(reading.problem.message);
  return runQuery(reading.query, libraryOf(notes), today);
}

const rows = (result: QueryResult): Row[] => result.groups.flatMap((group) => group.rows);
const names = (result: QueryResult) => rows(result).map((row) => row.name);

describe('the library', () => {
  const library = libraryOf(NOTES);

  it('reads every note as a record, a ticket as one, and every to-do with words as one of its own', () => {
    const kinds = library.records.map((record) => `${record.kind}:${record.noteId}`);
    expect(kinds.filter((k) => k.startsWith('ticket:'))).toEqual(['ticket:gho1', 'ticket:gho2', 'ticket:gho3']);
    expect(kinds.filter((k) => k.startsWith('note:'))).toEqual(['note:launch', 'note:shop', 'note:ideas', 'note:standup']);
    // Five on the shopping list (the empty box is not one, nor the box in code) and one in a ticket.
    expect(library.records.filter((record) => record.kind === 'task').map((record) => record.text)).toEqual(['Write the failing test', 'Milk #dairy', 'Eggs', 'Bread', 'Coffee beans', 'Butter']);
  });

  it('keeps a to-do’s line, its box, its fields, and its note’s tags', () => {
    const milk = library.records.find((record) => record.text === 'Milk #dairy')!;
    expect(milk).toEqual(expect.objectContaining({ noteId: 'shop', line: 5, done: false, title: 'Groceries', source: '- [ ] Milk 📅 2026-10-04 @sam #dairy' }));
    expect(milk.fields?.due).toBe('2026-10-04');
    expect(milk.fields?.assignees).toEqual(['sam']);
    expect(milk.tags).toEqual(['dairy', 'errands']);
    expect(library.records.find((record) => record.text === 'Eggs')?.done).toBe(true);
  });

  it('knows the notebook a page is in, and the workflow it moves through', () => {
    const ticket = library.records.find((record) => record.noteId === 'gho1' && record.kind === 'ticket')!;
    expect(ticket.notebook).toBe('Launch');
    expect(ticket.workflow).toEqual(['Backlog', 'To do', 'In progress', 'In review', 'Done']);
    expect(ticket.ticket).toEqual(expect.objectContaining({ id: 'GHO-1', status: 'In progress', category: 'doing', estimate: 3 }));
    expect(library.records.find((record) => record.noteId === 'shop')?.notebook).toBeNull();
  });

  it('finds the notes a note links to, by title and by a ticket’s key', () => {
    const standup = library.records.find((record) => record.noteId === 'standup')!;
    expect([...standup.linksTo].sort()).toEqual(['gho1', 'gho2']);
    expect(noteNamed(library, 'gho-1')?.id).toBe('gho1');
    expect(noteNamed(library, 'launch')?.book).toBe(true);
    expect(noteNamed(library, 'Nothing like it')).toBeNull();
  });

  it('reads a note once while its words stay the same, and lets go of a note that is gone', () => {
    const cache = recordCache();
    libraryOf(NOTES, cache);
    const kept = cache.read.get('shop')?.note;
    libraryOf(NOTES, cache);
    expect(cache.read.get('shop')?.note).toBe(kept);
    libraryOf(
      NOTES.map((n) => (n.id === 'shop' ? { ...n, body: `${n.body}- [ ] Jam\n` } : n)),
      cache,
    );
    expect(cache.read.get('shop')?.note).not.toBe(kept);
    libraryOf(
      NOTES.filter((n) => n.id !== 'ideas'),
      cache,
    );
    expect(cache.read.has('ideas')).toBe(false);
  });
});

describe('the defaults', () => {
  it('lists notes, the last changed first, with their title and when they changed', () => {
    const result = run('');
    expect(result.show).toBe('list');
    expect(result.columns.map((column) => column.field)).toEqual(['title', 'updated']);
    expect(names(result)).toEqual(['Groceries', 'Fix the login loop', 'Pricing page', 'Standup', 'Dark mode', 'Launch', 'Book ideas']);
  });

  it('shows tickets as a table, the most urgent first, then the soonest due', () => {
    const result = run('from: tickets');
    expect(result.show).toBe('table');
    expect(result.columns.map((column) => column.label)).toEqual(['ID', 'Title', 'Status', 'Assignee', 'Priority', 'Due']);
    expect(rows(result).map((row) => row.id)).toEqual(['GHO-2', 'GHO-1', 'GHO-3']);
    expect(result.opens).toBe(1);
  });

  it('lists the open to-dos, the soonest due first, and those with no due date after', () => {
    const result = run('from: tasks');
    expect(names(result)).toEqual(['Milk #dairy', 'Bread', 'Write the failing test', 'Coffee beans', 'Butter']);
    expect(result.columns.map((column) => column.field)).toEqual(['text', 'due', 'priority', 'assignee', 'note']);
  });

  it('lists ticked to-dos too where the query asks about being done', () => {
    expect(names(run('from: tasks\nwhere: checked'))).toEqual(['Eggs']);
    expect(names(run('from: tasks\nwhere: checked = no'))).toHaveLength(5);
    expect(names(run('from: tasks\nwhere: status = Done'))).toEqual(['Eggs']);
  });
});

describe('from:', () => {
  it('reads a tag, the tags inside it, and a note’s tags on its to-dos', () => {
    expect(names(run('from: #writing'))).toEqual(['Book ideas']);
    expect(names(run('from: tasks #dairy'))).toEqual(['Milk #dairy']);
    expect(names(run('from: tasks #errands'))).toEqual(['Milk #dairy', 'Bread', 'Coffee beans', 'Butter']);
    expect(names(run('from: tickets #bug'))).toEqual(['Fix the login loop']);
  });

  it('reads a notebook as its pages, and any other note as the notes that link to it', () => {
    expect(names(run('from: tickets [[Launch]]'))).toEqual(['Pricing page', 'Fix the login loop', 'Dark mode']);
    expect(names(run('from: [[GHO-1]]'))).toEqual(expect.arrayContaining(['Standup', 'Pricing page']));
  });

  it('warns of a note that is not there, and reads only what links to it by name', () => {
    const result = run('from: [[Q4 plan]]');
    expect(result.warnings).toEqual(['No note is called “Q4 plan”.']);
    expect(rows(result)).toEqual([]);
  });

  it('reads a person on a ticket and on a to-do, however they are written', () => {
    expect(names(run('from: tickets @sam'))).toEqual(['Fix the login loop']);
    expect(names(run('from: tasks @Sam'))).toEqual(['Milk #dairy']);
  });

  it('reads words, or, and not', () => {
    expect(names(run('from: "ghost who writes"'))).toEqual(['Book ideas']);
    expect(names(run('from: tickets @sam or @alex'))).toEqual(['Pricing page', 'Fix the login loop']);
    expect(names(run('from: tickets [[Launch]] -#bug'))).toEqual(['Pricing page', 'Dark mode']);
  });
});

describe('where:', () => {
  it('compares a status by its place in the workflow', () => {
    expect(names(run('from: tickets\nwhere: status != Done'))).toEqual(['Pricing page', 'Fix the login loop']);
    expect(names(run('from: tickets\nwhere: status < In review'))).toEqual(['Pricing page', 'Fix the login loop']);
    expect(names(run('from: tickets\nwhere: status >= In progress'))).toEqual(['Fix the login loop', 'Dark mode']);
    expect(names(run('from: tickets\nwhere: category = done'))).toEqual(['Dark mode']);
  });

  it('compares a priority by its rank, the most urgent the greatest', () => {
    expect(names(run('from: tickets\nwhere: priority >= high'))).toEqual(['Pricing page', 'Fix the login loop']);
    expect(names(run('from: tasks\nwhere: priority = high'))).toEqual(['Bread']);
    // None sits between medium and low, as Tasks has it.
    expect(names(run('from: tasks\nwhere: priority < medium'))).toEqual(['Milk #dairy', 'Write the failing test', 'Coffee beans', 'Butter']);
  });

  it('compares days with today, counted on or back', () => {
    expect(names(run('from: tasks\nwhere: due < today'))).toEqual(['Milk #dairy']);
    expect(names(run('from: tasks\nwhere: due = today'))).toEqual(['Bread']);
    expect(names(run('from: tasks\nwhere: due <= today+1'))).toEqual(['Milk #dairy', 'Bread', 'Write the failing test']);
    expect(names(run('from: tickets\nwhere: due > 2026-10-04'))).toEqual(['Pricing page']);
  });

  it('never lists what has no value for a comparison, but does for is empty and !=', () => {
    expect(names(run('from: tickets\nwhere: due < 2027-01-01'))).toEqual(['Pricing page', 'Fix the login loop']);
    expect(names(run('from: tickets\nwhere: due is empty'))).toEqual(['Dark mode']);
    expect(names(run('from: tickets\nwhere: assignee != Sam'))).toEqual(['Pricing page', 'Dark mode']);
  });

  it('compares numbers as a sum reads them, a currency and all', () => {
    expect(names(run('from: tickets\nwhere: estimate >= 3'))).toEqual(['Pricing page', 'Fix the login loop']);
    expect(names(run('from: tasks\nwhere: cost > 10'))).toEqual(['Coffee beans']);
  });

  it('reads a list as equal to anything it holds', () => {
    expect(names(run('from: tickets\nwhere: labels = auth'))).toEqual(['Fix the login loop']);
    expect(names(run('from: tickets\nwhere: blocked-by contains GHO-1'))).toEqual(['Pricing page']);
    expect(names(run('from: tickets\nwhere: blocked-by'))).toEqual(['Pricing page']);
  });

  it('compares words whatever their case, and looks inside them with contains', () => {
    expect(names(run('from: tickets\nwhere: title = "pricing PAGE"'))).toEqual(['Pricing page']);
    expect(names(run('from: tickets\nwhere: title contains login'))).toEqual(['Fix the login loop']);
    expect(names(run('from: tickets\nwhere: notebook = Launch'))).toHaveLength(3);
  });
});

describe('the order and the limit', () => {
  it('sorts by the fields asked, either way, with nothing last whichever way', () => {
    expect(rows(run('from: tickets\nsort: estimate desc')).map((row) => row.id)).toEqual(['GHO-2', 'GHO-1', 'GHO-3']);
    expect(rows(run('from: tickets\nsort: due desc')).map((row) => row.id)).toEqual(['GHO-2', 'GHO-1', 'GHO-3']);
    expect(rows(run('from: tickets\nsort: due')).map((row) => row.id)).toEqual(['GHO-1', 'GHO-2', 'GHO-3']);
    expect(rows(run('from: tickets\nsort: id')).map((row) => row.id)).toEqual(['GHO-1', 'GHO-2', 'GHO-3']);
  });

  it('shows as many as its limit, and counts how many passed', () => {
    const result = run('from: tasks\nlimit: 2');
    expect(names(result)).toEqual(['Milk #dairy', 'Bread']);
    expect(result.matched).toBe(5);
    expect(result.shown).toBe(2);
  });
});

describe('the cells', () => {
  it('says what kind of value each is, a due day overdue or today while it is still open', () => {
    const result = run('from: tickets\ncolumns: id, status, assignee, priority, due, labels, estimate, blocked-by');
    const [pricing, login, dark] = rows(result);
    expect(login!.cells).toEqual([
      { kind: 'text', text: 'GHO-1' },
      { kind: 'status', text: 'In progress', category: 'doing' },
      { kind: 'people', names: ['Sam'] },
      { kind: 'priority', name: 'high' },
      { kind: 'day', day: '2026-10-03', tone: 'overdue' },
      { kind: 'list', items: ['bug', 'auth'], tags: false },
      { kind: 'number', text: '3' },
      { kind: 'empty' },
    ]);
    expect(login!.overdue).toBe(true);
    expect(pricing!.cells[7]).toEqual({ kind: 'list', items: ['GHO-1'], tags: false });
    expect(dark!.cells[3]).toEqual({ kind: 'priority', name: 'low' });
    expect(dark!.cells[4]).toEqual({ kind: 'empty' });
  });

  it('gives a to-do its line, its note and its box, and a ticket its key, to open and tick them', () => {
    const milk = rows(run('from: tasks #dairy'))[0]!;
    expect(milk).toEqual(expect.objectContaining({ key: 'shop:5', kind: 'task', noteId: 'shop', line: 5, done: false, id: null, due: '2026-10-04', day: '2026-10-04', overdue: true }));
    const ticket = rows(run('from: tickets @alex'))[0]!;
    expect(ticket).toEqual(expect.objectContaining({ key: 'gho2', kind: 'ticket', id: 'GHO-2', line: -1, category: 'todo' }));
  });
});

describe('groups, boards and totals', () => {
  it('lays a ticket board out as the whole workflow, empty statuses and all', () => {
    const result = run('from: tickets\nshow: board');
    expect(result.group).toBe('status');
    expect(result.groups.map((group) => `${group.label}:${group.rows.map((row) => row.id).join(',')}`)).toEqual([
      'Backlog:',
      'To do:GHO-2',
      'In progress:GHO-1',
      'In review:',
      'Done:GHO-3',
    ]);
  });

  it('groups by any field, a record in each group its list holds, the group with nothing last', () => {
    const result = run('from: tasks\ngroup: assignee');
    expect(result.groups.map((group) => `${group.label}:${group.rows.length}`)).toEqual(['alex:1', 'sam:1', 'No assignee:3']);
    const labels = run('from: tickets\ngroup: labels');
    expect(labels.groups.map((group) => group.label)).toEqual(['auth', 'bug', 'No labels']);
  });

  it('groups a board of to-dos by whether they are done, and lists the done ones too', () => {
    const result = run('from: tasks\nshow: board');
    expect(result.groups.map((group) => `${group.label}:${group.rows.length}`)).toEqual(['To do:5', 'Done:1']);
  });

  it('adds up totals as a sum would, over all and over each group', () => {
    const result = run('from: tickets\ngroup: status\ntotal: estimate');
    expect(result.totals).toEqual([{ field: 'estimate', label: 'Estimate', text: '10' }]);
    expect(result.groups.map((group) => group.totals[0]!.text)).toEqual(['5', '3', '2']);
    expect(run('from: tasks\ntotal: cost').totals[0]!.text).toBe('$16.50');
    expect(run('from: tasks\ntotal: nothing-here').totals[0]!.text).toBe('0');
  });

  it('counts', () => {
    const result = run('from: tasks\nshow: count');
    expect(result.show).toBe('count');
    expect(result.matched).toBe(5);
  });
});

describe('a gantt', () => {
  it('is Mermaid’s gantt text, a bar from start to due, done and overdue marked', () => {
    const result = run('from: tickets\nshow: gantt');
    expect(result.gantt?.placed).toBe(2);
    expect(result.gantt?.code).toBe(
      ['gantt', '  dateFormat YYYY-MM-DD', '  axisFormat %e %b', '  section Tickets', '  GHO-2 Pricing page :2026-10-10, 2026-10-11', '  GHO-1 Fix the login loop :active, crit, 2026-09-28, 2026-10-04'].join('\n'),
    );
  });

  it('is nothing where no record has a day', () => {
    expect(run('from: notes #writing\nshow: gantt').gantt).toEqual({ code: '', placed: 0 });
    expect(run('from: tickets').gantt).toBeNull();
  });
});
