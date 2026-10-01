import { describe, expect, it } from 'vitest';
import { frontMatterEnd, frontMatterValue } from './frontMatter.ts';
import {
  DEFAULT_STATUSES,
  ISSUE_KEY,
  PROJECT_KEY,
  TICKET_PROPERTIES,
  isIssueKey,
  isPropertyKey,
  isTicket,
  issueKeyOf,
  issueNumber,
  linkTargets,
  nextIssueId,
  notebookKey,
  propertiesOf,
  propertyKind,
  propertyList,
  statusCategory,
  statusesOf,
  ticketIdOf,
  ticketOf,
  withProperty,
  yamlList,
  yamlValue,
} from './properties.ts';

/*
 * A ticket is front matter, and front matter is read in one place (core/frontMatter.ts): these are the blocks a
 * properties panel, a ticket's numbering and a query must all read the same way, and the values that must come back
 * from YAML as they went in.
 */

const TICKET = [
  '---',
  'type: ticket',
  'id: GHO-12',
  'status: In progress',
  'assignee: Sam',
  'priority: high',
  'due: 2026-10-03',
  'estimate: 3',
  'blocked-by: "[[GHO-9]]"',
  '---',
  '# Fix the login loop',
  '',
  'It loops.',
].join('\n');

describe('a note’s properties', () => {
  it('are every key in its front matter, in order, the quotes off, with the line each is on', () => {
    expect(propertiesOf(TICKET)).toEqual([
      { key: 'type', value: 'ticket', line: 1 },
      { key: 'id', value: 'GHO-12', line: 2 },
      { key: 'status', value: 'In progress', line: 3 },
      { key: 'assignee', value: 'Sam', line: 4 },
      { key: 'priority', value: 'high', line: 5 },
      { key: 'due', value: '2026-10-03', line: 6 },
      { key: 'estimate', value: '3', line: 7 },
      { key: 'blocked-by', value: '[[GHO-9]]', line: 8 },
    ]);
  });

  it('keep a key as written, an empty value, a value with colons, and skip blank lines', () => {
    expect(propertiesOf('---\nTitle: "A: B"\n\nempty:\nurl: https://a.b/c\nspaced  :   x  \n---\n')).toEqual([
      { key: 'Title', value: 'A: B', line: 1 },
      { key: 'empty', value: '', line: 3 },
      { key: 'url', value: 'https://a.b/c', line: 4 },
      { key: 'spaced', value: 'x', line: 5 },
    ]);
  });

  it('take a value’s quotes off as YAML does, as frontMatterValue does', () => {
    const body = `---\na: 'It''s'\nb: "say \\"hi\\""\nc: '"quoted"'\n---\n`;
    expect(propertiesOf(body).map((p) => p.value)).toEqual(["It's", 'say "hi"', '"quoted"']);
    for (const { key, value } of propertiesOf(body)) expect(frontMatterValue(body, key)).toBe(value);
  });

  it('read the block a `+++` fence opens too', () => {
    expect(propertiesOf('+++\nid: GHO-1\n+++\nWords')).toEqual([{ key: 'id', value: 'GHO-1', line: 1 }]);
  });

  it('leave out an indented key, which belongs to the one above it', () => {
    expect(propertiesOf('---\nmeta:\n  inner: 1\nafter: 2\n---\n').map((p) => p.key)).toEqual(['meta', 'after']);
  });

  it('are none where the note has no front matter, as frontMatterEnd decides it', () => {
    for (const body of ['', '# Note\n\ntype: ticket', '---\ntype: ticket\nwords here\n---\n', '---\ntype: ticket\n', 'Words\n---\ntype: ticket\n---', '---\ntags:\n  - a\n---\n']) {
      expect(frontMatterEnd(body.split('\n')), body).toBe(0);
      expect(propertiesOf(body), body).toEqual([]);
    }
  });
});

describe('a value read as a list', () => {
  it('reads a flow list, its items unquoted', () => {
    expect(propertyList('["[[GHO-9]]", "[[GHO-10]]"]')).toEqual(['[[GHO-9]]', '[[GHO-10]]']);
    expect(propertyList('[bug, ui]')).toEqual(['bug', 'ui']);
    expect(propertyList("['a, b', c]")).toEqual(['a, b', 'c']);
    expect(propertyList('[[[GHO-9]], [[GHO-10]]]')).toEqual(['[[GHO-9]]', '[[GHO-10]]']);
    expect(propertyList('[]')).toEqual([]);
    expect(propertyList('[ , a ,, ]')).toEqual(['a']);
  });

  it('reads names with commas, as authors are written', () => {
    expect(propertyList('Matt, Claude')).toEqual(['Matt', 'Claude']);
    expect(propertyList('Backlog, To do, Won’t do, Won\'t fix')).toEqual(['Backlog', 'To do', 'Won’t do', "Won't fix"]);
    expect(propertyList('one')).toEqual(['one']);
  });

  it('reads note links alone as links, never as a list in a list', () => {
    expect(propertyList('[[GHO-9]]')).toEqual(['[[GHO-9]]']);
    expect(propertyList('[[GHO-9]], [[GHO-10|the loop]]')).toEqual(['[[GHO-9]]', '[[GHO-10|the loop]]']);
  });

  it('keeps a comma inside quotes or brackets in its item', () => {
    expect(propertyList('"Smith, J", [[A, B]]')).toEqual(['Smith, J', '[[A, B]]']);
  });

  it('is empty for nothing', () => {
    expect(propertyList('')).toEqual([]);
    expect(propertyList('   ')).toEqual([]);
    expect(propertyList(null)).toEqual([]);
    expect(propertyList(undefined)).toEqual([]);
  });
});

describe('what a link property points at', () => {
  it('is each note link’s title, its heading or words after it not part of it', () => {
    expect(linkTargets('[[GHO-9]]')).toEqual(['GHO-9']);
    expect(linkTargets('["[[GHO-9]]", "[[GHO-10|the loop]]", "[[Plan#Risks]]"]')).toEqual(['GHO-9', 'GHO-10', 'Plan']);
  });

  it('is an item without brackets as it is, so a hand-written key still points', () => {
    expect(linkTargets('GHO-9, GHO-10')).toEqual(['GHO-9', 'GHO-10']);
    expect(linkTargets('[GHO-9]')).toEqual(['GHO-9']);
  });

  it('is nothing for nothing', () => {
    expect(linkTargets('')).toEqual([]);
    expect(linkTargets(null)).toEqual([]);
    expect(linkTargets('[[ ]]')).toEqual([]);
  });
});

describe('a value written', () => {
  it('is left as it is where YAML reads it as words', () => {
    for (const value of ['In progress', 'GHO-12', '2026-10-03', '3', "Won't do", 'C# notes', 'a:b', 'https://a.b/c', 'x - y', 'true', '50%']) {
      expect(yamlValue(value), value).toBe(value);
    }
  });

  it('is quoted where YAML would misread it', () => {
    for (const value of ['[[GHO-9]]', '[a]', '{a}', '#bug', '@sam', '`code`', 'a: b', 'ends:', 'a #comment', '- item', '-', '? x', ': x', '!tag', '&a', '*a', '|', '>', '%x', ',a', ' padded', 'padded ', '']) {
      expect(yamlValue(value), value).toBe(`"${value}"`);
    }
  });

  it('is quoted in single quotes where the words have a double quote or a backslash, a single one doubled', () => {
    expect(yamlValue('"quoted"')).toBe(`'"quoted"'`);
    expect(yamlValue('say "hi": now')).toBe(`'say "hi": now'`);
    expect(yamlValue('C:\\notes: x')).toBe(`'C:\\notes: x'`);
    expect(yamlValue('"It\'s"')).toBe(`'"It''s"'`);
    expect(yamlValue("'single'")).toBe(`"'single'"`);
  });

  it('is one line', () => {
    expect(yamlValue('two\nlines')).toBe('two lines');
    expect(yamlValue('a:\n b')).toBe('"a: b"');
  });

  it('as a list is written across, each item quoted where it must be', () => {
    expect(yamlList(['bug', 'ui'])).toBe('[bug, ui]');
    expect(yamlList(['[[GHO-9]]', '[[GHO-10]]'])).toBe('["[[GHO-9]]", "[[GHO-10]]"]');
    expect(yamlList(['a, b', 'c]', '{d}', '#e', 'f g'])).toBe('["a, b", "c]", "{d}", "#e", f g]');
    expect(yamlList([])).toBe('[]');
  });

  it('comes back as it went, through the reader', () => {
    for (const value of ['[[GHO-9]]', 'say "hi": now', "It's", '"It\'s"', 'C:\\notes', '@sam', 'a #b', ' padded ', 'In progress']) {
      const body = withProperty('# A', 'x', value);
      expect(frontMatterValue(body, 'x'), value).toBe(value);
      expect(propertiesOf(body)[0]?.value, value).toBe(value);
    }
    for (const list of [['[[GHO-9]]', '[[GHO-10]]'], ['a, b', 'c'], ['bug'], ['"q"', "it's"]]) {
      expect(propertyList(frontMatterValue(withProperty('# A', 'x', list), 'x'))).toEqual(list);
    }
  });
});

describe('a property written into a note', () => {
  it('replaces the key where it is, in any case, and keeps the rest', () => {
    expect(withProperty(TICKET, 'status', 'Done')).toBe(TICKET.replace('status: In progress', 'status: Done'));
    expect(withProperty('---\nStatus: To do\ntitle: "A"\n---\nWords', 'status', 'Done')).toBe('---\nstatus: Done\ntitle: "A"\n---\nWords');
  });

  it('adds a key last, and makes front matter where there is none', () => {
    expect(withProperty('---\ntype: ticket\n---\n# A', 'labels', ['bug', 'ui'])).toBe('---\ntype: ticket\nlabels: [bug, ui]\n---\n# A');
    expect(withProperty('# A\n', 'blocked-by', '[[GHO-9]]')).toBe('---\nblocked-by: "[[GHO-9]]"\n---\n# A\n');
  });

  it('takes a key off for null or an empty list, and front matter that held nothing else with it', () => {
    expect(withProperty('---\ntype: ticket\ndue: 2026-10-03\n---\n# A', 'due', null)).toBe('---\ntype: ticket\n---\n# A');
    expect(withProperty('---\nlabels: [bug]\n---\n# A', 'labels', [' ', ''])).toBe('# A');
    expect(withProperty('# A', 'due', null)).toBe('# A');
  });

  it('writes an empty value as two quotes, which reads back as nothing', () => {
    const body = withProperty('# A', 'assignee', '');
    expect(body).toBe('---\nassignee: ""\n---\n# A');
    expect(frontMatterValue(body, 'assignee')).toBe('');
  });

  it('leaves the note as it was for a key front matter cannot hold', () => {
    for (const key of ['', 'two words', 'a:b', '#tag', 'é']) {
      expect(isPropertyKey(key), key).toBe(false);
      expect(withProperty('# A', key, 'x'), key).toBe('# A');
    }
    for (const key of ['due', 'blocked-by', 'a.b', 'x_1']) expect(isPropertyKey(key), key).toBe(true);
  });

  it('leaves front matter the list still reads as front matter', () => {
    let body = '---\ntitle: "Fix it"\n---\n# Fix it';
    body = withProperty(body, 'blocked-by', ['[[GHO-9]]', '[[GHO-10]]']);
    body = withProperty(body, 'labels', ['bug']);
    body = withProperty(body, 'assignee', '@sam');
    expect(frontMatterEnd(body.split('\n'))).toBe(6);
    expect(body).toBe('---\ntitle: "Fix it"\nblocked-by: ["[[GHO-9]]", "[[GHO-10]]"]\nlabels: [bug]\nassignee: "@sam"\n---\n# Fix it');
  });
});

describe('a ticket', () => {
  it('is a note whose type is ticket, in any case', () => {
    expect(isTicket(TICKET)).toBe(true);
    expect(isTicket('---\ntype: Ticket\n---\n')).toBe(true);
    expect(isTicket('---\ntype: "ticket"\n---\n')).toBe(true);
    expect(isTicket('---\ntype: note\n---\n')).toBe(false);
    expect(isTicket('# Ticket\n\ntype: ticket')).toBe(false);
    expect(isTicket('')).toBe(false);
  });

  it('is read whole: its id, its status and where it stands, its person, priority, days, estimate and links', () => {
    expect(ticketOf(TICKET)).toEqual({
      id: 'GHO-12',
      status: 'In progress',
      category: 'doing',
      assignee: 'Sam',
      priority: 'high',
      due: '2026-10-03',
      start: null,
      estimate: 3,
      blockedBy: ['GHO-9'],
      parent: null,
      labels: [],
    });
  });

  it('reads what a person may write by hand the way they meant it', () => {
    const body = ['---', 'type: ticket', 'id: gho-7', 'assignee: "@sam"', 'priority: ⏫', 'due: Friday', 'start: 2026-10-01', 'estimate: 2.5 days', 'blocked-by: ["[[GHO-5]]", "[[GHO-6|the cache]]"]', 'parent: "[[GHO-1]]"', 'labels: ["#bug", ui]', '---', ''].join('\n');
    expect(ticketOf(body)).toEqual({
      id: 'GHO-7',
      status: null,
      category: 'todo',
      assignee: 'sam',
      priority: 'high',
      due: null,
      start: '2026-10-01',
      estimate: 2.5,
      blockedBy: ['GHO-5', 'GHO-6'],
      parent: 'GHO-1',
      labels: ['bug', 'ui'],
    });
  });

  it('reads nothing it cannot use as nothing', () => {
    const ticket = ticketOf('---\ntype: ticket\nid: twelve\nassignee:\npriority: urgent\nestimate: some\n---\n');
    expect(ticket).toMatchObject({ id: null, assignee: null, priority: null, estimate: null, blockedBy: [], parent: null });
  });

  it('places its status in its notebook’s workflow', () => {
    const body = '---\ntype: ticket\nstatus: Live\n---\n';
    expect(ticketOf(body)?.category).toBe('todo');
    expect(ticketOf(body, ['Ideas', 'Building', 'Live'])?.category).toBe('done');
  });

  it('is no ticket for a note that is not one', () => {
    expect(ticketOf('---\nid: GHO-1\n---\n')).toBeNull();
  });

  it('has its properties named once, for a panel and a query to share', () => {
    expect(TICKET_PROPERTIES.map((p) => `${p.key}:${p.kind}`)).toEqual([
      'type:text',
      'id:id',
      'status:status',
      'assignee:person',
      'priority:priority',
      'due:date',
      'start:date',
      'estimate:number',
      'blocked-by:links',
      'parent:link',
      'labels:list',
    ]);
    expect(TICKET_PROPERTIES.find((p) => p.key === 'blocked-by')?.label).toBe('Blocked by');
    expect(propertyKind('Due')).toBe('date');
    expect(propertyKind(' assignee ')).toBe('person');
    expect(propertyKind('title')).toBe('text');
  });
});

describe('statuses', () => {
  it('are the default workflow where a notebook names none', () => {
    expect(DEFAULT_STATUSES).toEqual(['Backlog', 'To do', 'In progress', 'In review', 'Done']);
    expect(statusesOf(null)).toEqual([...DEFAULT_STATUSES]);
    expect(statusesOf('---\nbook: true\n---\n# Book')).toEqual([...DEFAULT_STATUSES]);
    expect(statusesOf('---\nbook: true\nstatuses: []\n---\n')).toEqual([...DEFAULT_STATUSES]);
  });

  it('are a notebook’s own, as a flow list or with commas, each once', () => {
    expect(statusesOf('---\nbook: true\nstatuses: [Ideas, Building, Live]\n---\n')).toEqual(['Ideas', 'Building', 'Live']);
    expect(statusesOf('---\nbook: true\nstatuses: To do, Doing, Done, done\n---\n')).toEqual(['To do', 'Doing', 'Done']);
  });

  it('stand where their words say: done, under way, or not started', () => {
    for (const status of ['Done', 'done', 'DONE', 'Closed', 'Resolved', 'Complete', "Won't do", 'Won’t do', 'Wont fix', "won't-fix", 'Cancelled', 'Canceled', 'Duplicate', 'Shipped', 'All done', 'Done this week']) {
      expect(statusCategory(status), status).toBe('done');
    }
    for (const status of ['In progress', 'in-progress', 'In review', 'In QA', 'In design', 'Doing', 'Review', 'Blocked', 'WIP']) {
      expect(statusCategory(status), status).toBe('doing');
    }
    for (const status of ['Backlog', 'To do', 'To-Do', 'todo', 'Open', 'New', 'Ready', '', null, undefined, 'Inbox']) {
      expect(statusCategory(status), String(status)).toBe('todo');
    }
  });

  it('stand by their place in a workflow where their words say nothing: first not started, last done, between under way', () => {
    const workflow = ['Ideas', 'Building', 'Polishing', 'Live'];
    expect(statusCategory('Ideas', workflow)).toBe('todo');
    expect(statusCategory('building', workflow)).toBe('doing');
    expect(statusCategory('Polishing', workflow)).toBe('doing');
    expect(statusCategory('Live', workflow)).toBe('done');
    expect(statusCategory('Live')).toBe('todo');
    expect(statusCategory('Elsewhere', workflow)).toBe('todo');
    expect(statusCategory('Only', ['Only'])).toBe('todo');
    // What the words say wins over the place: a workflow that ends in Backlog does not finish there.
    expect(statusCategory('Backlog', ['Doing', 'Backlog'])).toBe('todo');
  });
});

describe('issue keys', () => {
  it('are a notebook’s key, a dash and a number, as Jira writes them', () => {
    for (const key of ['GHO-1', 'GHO-12', 'AB-999999', 'A1-3', 'ABCDEFGHIJ-1']) expect(ISSUE_KEY.test(key), key).toBe(true);
    for (const key of ['GHO-0', 'GHO-012', 'G-1', '1GH-1', 'GHO-1234567', 'ABCDEFGHIJK-1', 'GHO12', 'GHO-', 'gho-12', 'GHO_12']) expect(ISSUE_KEY.test(key), key).toBe(false);
    for (const key of ['GH', 'GHO', 'A1', 'ABCDEFGHIJ']) expect(PROJECT_KEY.test(key), key).toBe(true);
    for (const key of ['G', '1G', 'GHO-', 'ABCDEFGHIJK', 'gho']) expect(PROJECT_KEY.test(key), key).toBe(false);
  });

  it('are read in any case, as a link’s title matches, and give their number', () => {
    expect(issueKeyOf(' gho-12 ')).toBe('GHO-12');
    expect(issueKeyOf('GHO-12 the loop')).toBeNull();
    expect(issueKeyOf(null)).toBeNull();
    expect(isIssueKey('Gho-3')).toBe(true);
    expect(isIssueKey('Fix it')).toBe(false);
    expect(issueNumber('GHO-12')).toBe(12);
    expect(issueNumber('gho-9')).toBe(9);
    expect(issueNumber('GHO')).toBeNull();
  });

  it('take a notebook’s key from its key property, upper-cased, where it is one', () => {
    expect(notebookKey('---\nbook: true\nkey: GHO\n---\n')).toBe('GHO');
    expect(notebookKey('---\nbook: true\nkey: gho\n---\n')).toBe('GHO');
    expect(notebookKey('---\nbook: true\nkey: "ops2"\n---\n')).toBe('OPS2');
    for (const said of ['G', '12', 'GHO-1', 'TOO-LONG-KEY', 'two words', '']) expect(notebookKey(`---\nbook: true\nkey: ${said}\n---\n`), said).toBeNull();
    expect(notebookKey('---\nbook: true\n---\n')).toBeNull();
    expect(notebookKey('# key: GHO')).toBeNull();
  });

  it('give a ticket its id from its id property', () => {
    expect(ticketIdOf(TICKET)).toBe('GHO-12');
    expect(ticketIdOf('---\nid: gho-3\n---\n')).toBe('GHO-3');
    expect(ticketIdOf('---\nid: 20260930\n---\n')).toBeNull();
    expect(ticketIdOf('# GHO-3')).toBeNull();
  });
});

describe('the next id', () => {
  it('is one more than the highest the notes give the key, in an id or anywhere in their words', () => {
    const notes = ['---\ntype: ticket\nid: GHO-3\n---\n', '---\ntype: ticket\nid: GHO-12\n---\nBlocked by [[GHO-9]]', 'see gho-14 in passing'];
    expect(nextIssueId('GHO', notes)).toBe('GHO-15');
    expect(nextIssueId('gho', notes.slice(0, 2))).toBe('GHO-13');
  });

  it('never fills a gap, so a number once given is not given again', () => {
    expect(nextIssueId('GHO', ['id: GHO-1', 'id: GHO-7'])).toBe('GHO-8');
  });

  it('is the first where nothing names the key, and counts no other key’s numbers', () => {
    expect(nextIssueId('GHO', [])).toBe('GHO-1');
    expect(nextIssueId('GHO', ['XGHO-40 and GHO_2 and GHOST-5 and AGHO-9', 'GHO-1234567'])).toBe('GHO-1');
    expect(nextIssueId('OPS', ['GHO-40'])).toBe('OPS-1');
  });

  it('is nothing for a key that is not one, or past the last number a key can have', () => {
    expect(nextIssueId('G', [])).toBeNull();
    expect(nextIssueId('GHO-1', [])).toBeNull();
    expect(nextIssueId('GHO', ['GHO-999999'])).toBeNull();
    expect(nextIssueId('GHO', ['GHO-999998'])).toBe('GHO-999999');
  });
});
