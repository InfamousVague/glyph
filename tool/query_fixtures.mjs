// What the web's query core answers, for the Dart port to be held against (lib/core/query,
// test/query/fixtures_test.dart).
//
//   node tool/query_fixtures.mjs
//
// Everything is read from tauri/ and nothing is written there: its src/app/core/query/*.ts as they are (read.ts
// has a constructor's parameter properties, which Node's own type stripping will not take, so each file is put
// through the Tauri app's own TypeScript on its way in, in memory), its test library (core/query/library.fixture.ts), the
// Guide's chapters (src/app/guidebook) and docs/QUERIES.md. One fixture goes to test/query/fixtures/queries.json.
// Nothing here is random, so running it again writes the same file.
//
// The file:
//   today      the day every query is run on (the fixture library's: Monday 5 October 2026)
//   libraries  name -> the notes of a library: [id, body, created day, updated day]. `fixture` is the web tests'
//              own; `guide` is Ghost.md: The Guide as it is added to a library, its index and its chapters; `site`
//              is made to have every edge in it: a notebook with a workflow of its own, tickets written by hand,
//              to-dos with every field, two notes of one title, and four of the Guide's notes beside them.
//   records    name -> every record `libraryOf` reads from that library, a Set written as a sorted list, and a
//              note's words and what `"words"` look through as [length, sum] (`summed` below)
//   cases      every query: [body, reading, {library name -> result}] where reading is `readQuery`'s answer and a
//              result is `runQuery`'s, both as JSON writes them; no results for a query that cannot be read. Every
//              query is run over `fixture`, and over the other two the ones `over` below names.
//   fences     [document name, `queryFencesIn` of it] for each chapter of the Guide and docs/QUERIES.md that has one
//   months     for each query shown as a calendar over `fixture`: [body, `openingMonth`, the weeks of that month as
//              rows of [day, date, inMonth, today, row keys]]
//   drafts     for each query of tickets drawn as a board over `fixture`: [body, lane label, `ticketDraft`]
//   collation  words, and how `localeCompare` orders every pair of them: `plain[i][j]` and `numeric[i][j]` are
//              '<', '=' or '>' for words[i] against words[j], the second with {numeric: true, sensitivity: 'base'}
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { createRequire, registerHooks } from 'node:module';
import { fileURLToPath } from 'node:url';

const GLYPH = new URL('../tauri/', import.meta.url).pathname;
const APP = `${GLYPH}src/app/`;
const OUT = new URL('../test/query/fixtures/', import.meta.url).pathname;
const require = createRequire(`${GLYPH}package.json`);
const ts = require('typescript');

// The web's TypeScript, compiled as it is loaded: nothing is written beside it.
registerHooks({
  load(url, context, nextLoad) {
    if (!url.startsWith('file://') || !url.endsWith('.ts') || !fileURLToPath(url).startsWith(`${GLYPH}src/`)) return nextLoad(url, context);
    const source = readFileSync(fileURLToPath(url), 'utf8');
    const { outputText } = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022, verbatimModuleSyntax: true } });
    return { format: 'module', source: outputText, shortCircuit: true };
  },
});

const { readQuery } = await import(`${APP}core/query/read.ts`);
const { libraryOf } = await import(`${APP}core/query/records.ts`);
const { runQuery } = await import(`${APP}core/query/run.ts`);
const { queryFencesIn } = await import(`${APP}core/query/fence.ts`);
const { monthWeeks, openingMonth } = await import(`${APP}core/query/calendar.ts`);
const { ticketDraft } = await import(`${APP}core/query/draft.ts`);
const { QUERY_TEMPLATES } = await import(`${APP}core/query/templates.ts`);
const { NOTES, TODAY } = await import(`${APP}core/query/library.fixture.ts`);
const { isoDay } = await import(`${APP}core/days.ts`);

// ---- the libraries ------------------------------------------------------------------------------------------------

const noon = (day) => new Date(`${day}T12:00:00`).getTime();
const chapters = readdirSync(`${APP}guidebook/chapters`).filter((name) => name.endsWith('.md')).sort();
/** A day in September 2026 for each note of the Guide, so "the last changed first" has something to order. */
const dayFor = (n) => `2026-09-${String(1 + ((n * 7) % 28)).padStart(2, '0')}`;
const GUIDE = [
  { id: 'guide', body: readFileSync(`${APP}guidebook/index.md`, 'utf8'), createdAt: noon('2026-08-01'), updatedAt: noon('2026-10-02') },
  ...chapters.map((name, n) => ({ id: `ch${String(n + 1).padStart(2, '0')}`, body: readFileSync(`${APP}guidebook/chapters/${name}`, 'utf8'), createdAt: noon('2026-08-01'), updatedAt: noon(dayFor(n)) })),
];
/** A library made to have every edge in it: the Guide's index and its chapters on lists, boards and books, and
 * a notebook with a workflow of its own and tickets in it, some by its index and one by its key alone. */
const SITE = [
  ...GUIDE.filter((note) => ['guide', 'ch12', 'ch13', 'ch14'].includes(note.id)),
  {
    id: 'web',
    body: '---\ntitle: "Website"\nbook: true\nkey: WEB\nstatuses: [Ideas, Building, "Won\'t do", Live]\n---\n# Website\n\n1. [[Home page]]\n2. [[Résumé page]]\n   - [[Footer]]\n- [[A bullet beside the numbers]]\n',
    createdAt: noon('2026-09-10'),
    updatedAt: noon('2026-10-03'),
  },
  {
    id: 'web1',
    body: '---\ntype: ticket\nid: WEB-1\nstatus: Building\nassignee: "@Priya-Shah"\npriority: medium\ndue: 2026-10-05\nstart: 2026-10-07\nestimate: 2.5 days\nlabels: ["#design", ui]\nparent: "[[WEB-10|the site]]"\ncost: $1,200\n---\n# Home page\n\n- [ ] Pick a typeface ⏫ 🛫 2026-10-01 ⏳ 2026-10-02 [stage:: Doing] ^typeface\n- [x] Draw the header ✅ 2026-09-30 #design/header\n- [ ] Ask @sam and @Priya-Shah 🔁 every week 🆔 ask1 ⛔ typeface\n- [-] not a box\n',
    createdAt: noon('2026-09-11'),
    updatedAt: noon('2026-10-05'),
  },
  {
    id: 'web2',
    body: '---\ntype: Ticket\nid: web-2\nstatus: Live\nassignee: Sam, Alex\npriority: ⏬\ndue: next week\nestimate: about 3\nblocked-by: WEB-1, [[Home page]]\ntags: Site, #launch\ndate: 2026-10-20\n---\n# Résumé page\n\nSee [[web-1]] and [[Nothing here]].\n',
    createdAt: noon('2026-09-12'),
    updatedAt: noon('2026-09-12'),
  },
  { id: 'web3', body: '---\ntype: ticket\nid: WEB-10\nstatus: Won’t do\nestimate: 0\n---\n# Footer\n\n> - [ ] A to-do in a quote 📅 2026-10-09\n', createdAt: noon('2026-09-13'), updatedAt: noon('2026-10-01') },
  { id: 'web4', body: '---\ntype: ticket\nid: WEB-11\nstatus: Triage\npriority: high\ndue: 2026-09-01\n---\n# Made from the blank page\n', createdAt: noon('2026-09-14'), updatedAt: noon('2026-09-14') },
  { id: 'dup1', body: '# Twice\n\nThe first of two with one title. #Work/Clients\n', createdAt: noon('2026-09-15'), updatedAt: noon('2026-09-15') },
  { id: 'dup2', body: '# Twice\n\nThe second. status: none of it is front matter.\n\n- [ ] Call “the bank” [cost:: 40] [due:: 2026-10-06]\n- [ ] 10 apples\n- [ ] 9 pears\n', createdAt: noon('2026-09-16'), updatedAt: noon('2026-09-16') },
  { id: 'props', body: '---\nstatus: Doing\npriority: urgent\nrating: 4.5\nwhen: 2026-10-05\nseen: [a, b]\nlinks: "[[Twice]]"\nempty:\n---\nWords first, no heading.\n', createdAt: noon('2026-09-17'), updatedAt: noon('2026-10-05') },
];

const LIBRARIES = { fixture: NOTES, guide: GUIDE, site: SITE };
const BUILT = Object.fromEntries(Object.entries(LIBRARIES).map(([name, notes]) => [name, libraryOf(notes)]));

// ---- the queries --------------------------------------------------------------------------------------------------

/** Every body the web's own tests read or run (core/query/read.test.ts, run.test.ts, draft.test.ts). */
const FROM_TESTS = [
  '', '\n  \n', 'from:\nwhere:\nshow:', 'from: tickets', 'from: Issues', 'from: tasks', 'from: to-dos', 'from: notes', 'from: #bug', 'from: #Work/Clients',
  'from: [[Launch plan]]', 'from: [[Launch plan#Goals|the plan]]', 'from: @sam', 'from: "release notes"', 'from: “curly quotes”', 'from: tasks #bug @sam',
  'from: tasks #bug, @sam', 'from: tasks #bug and @sam', 'from: #bug or #ui', 'from: #bug -#wontfix', 'from: not [[Archive]]', 'from: (#bug or #ui) @sam',
  'from: #bug tickets', 'from: bugs', 'from: [[Launch plan', 'from: "open', 'from: (#bug or #ui', 'from: #bug)', 'from: #bug or', 'show: table\nfrom: #bug bugs',
  '  from:   bugs', 'where: status != Done', 'where: estimate >= 3', 'where: due < 2026-10-03', 'where: Due-Date = today', 'where: status = In progress',
  'where: status = "Won\'t do and done"', 'where: due < today+7', 'where: due < today + 7 days', 'where: due > today-2w', 'where: due = tomorrow',
  'where: due = yesterday', 'where: status == Done', 'where: status ≠ Done', 'where: due ≤ today', 'where: due ≥ today', 'where: status is Done',
  'where: status is not Done', 'where: labels contains ui', 'where: labels has ui', 'where: labels not contains ui', 'where: due is empty',
  'where: assignee is not empty', 'where: due = empty', 'where: blocked-by', 'where: status != Done and (priority >= high or due < today+7)',
  'where: a = 1 or b = 2 and c = 3', 'where: not checked', 'where: people = Sam', 'where: status != Done\nwhere: assignee = Sam', 'where: = Done',
  'where: status !=', 'where: status Done', 'where: due < 2026-02-30', 'where: (status = Done', 'where: status = Done)', 'sort: priority desc, due',
  'sort by: Due Date descending', 'sort: by updated', 'group: status', 'group by: assignee', 'group: by priority', 'group: status, assignee', 'show: table',
  'show: list', 'show: board', 'show: calendar', 'show: gantt', 'show: count', 'show: Kanban', 'show: timeline', 'show: pie', 'columns: id, Title, Blocked By',
  'total: estimate, cost', 'columns: id, ti@tle', 'limit: 20', 'limit: twenty', 'limit: 0', 'FROM: tickets\nSort  By: due', 'form: #bug', 'shwo: table',
  'colour: red', 'just some words', 'show: table\nfrom: #a\nshow: list', 'where: status != Done and (not checked or due < today)',
  'from: tasks\nwhere: checked', 'from: tasks\nwhere: checked = no', 'from: tasks\nwhere: status = Done', 'from: #writing', 'from: tasks #dairy',
  'from: tasks #errands', 'from: tickets #bug', 'from: tickets [[Launch]]', 'from: [[GHO-1]]', 'from: [[Q4 plan]]', 'from: tickets @sam', 'from: tasks @Sam',
  'from: "ghost who writes"', 'from: tickets @sam or @alex', 'from: tickets [[Launch]] -#bug', 'from: tickets\nwhere: status != Done',
  'from: tickets\nwhere: status < In review', 'from: tickets\nwhere: status >= In progress', 'from: tickets\nwhere: category = done',
  'from: tickets\nwhere: priority >= high', 'from: tasks\nwhere: priority = high', 'from: tasks\nwhere: priority < medium', 'from: tasks\nwhere: due < today',
  'from: tasks\nwhere: due = today', 'from: tasks\nwhere: due <= today+1', 'from: tickets\nwhere: due > 2026-10-04', 'from: tickets\nwhere: due < 2027-01-01',
  'from: tickets\nwhere: due is empty', 'from: tickets\nwhere: assignee != Sam', 'from: tickets\nwhere: estimate >= 3', 'from: tasks\nwhere: cost > 10',
  'from: tickets\nwhere: labels = auth', 'from: tickets\nwhere: blocked-by contains GHO-1', 'from: tickets\nwhere: blocked-by',
  'from: tickets\nwhere: title = "pricing PAGE"', 'from: tickets\nwhere: title contains login', 'from: tickets\nwhere: notebook = Launch',
  'from: tickets\nsort: estimate desc', 'from: tickets\nsort: due desc', 'from: tickets\nsort: due', 'from: tickets\nsort: id', 'from: tasks\nlimit: 2',
  'from: tickets\ncolumns: id, status, assignee, priority, due, labels, estimate, blocked-by', 'from: tickets @alex', 'from: tickets\nshow: board',
  'from: tasks\ngroup: assignee', 'from: tickets\ngroup: labels', 'from: tasks\nshow: board', 'from: tickets\ngroup: status\ntotal: estimate',
  'from: tasks\ntotal: cost', 'from: tasks\ntotal: nothing-here', 'from: tasks\nshow: count', 'from: tickets\nshow: gantt', 'from: notes #writing\nshow: gantt',
  'from: tickets\ngroup: assignee\nshow: board', 'from: tickets [[GHST]] #bug @kebim\nshow: board', 'from: tickets [[GHST]] or [[Other]]\nshow: board',
  'from: tickets not #bug\nshow: board',
  'from: tickets\nwhere: priority = high and estimate = 3 and due < today and (assignee = sam or assignee = kebim) and status = Done\nshow: board',
  'from: tickets\nwhere: type = ticket and id = GHO-4 and title = Plan\nshow: board', 'from: notes\nshow: board',
];

/** Every field a record may have, as the columns of one table: what `valueOf` says of each, through its cell. */
const WIDE = 'title, note, text, notebook, tags, created, updated, kind, category, status, checked, line, due, start, scheduled, done, cancelled, priority, assignee, recurs, id, depends-on, estimate, blocked-by, parent, labels, cost, stage, type, book, key, rating, when, seen, links, empty, date, nothing';

/** The edges the tests leave: every operator on every kind of value, the orders, the groups, the sentences. */
const MORE = [
  ...['notes', 'tickets', 'tasks'].map((kind) => `from: ${kind}\ncolumns: ${WIDE}\ntotal: estimate, cost, rating, line, title`),
  ...['notes', 'tickets', 'tasks'].flatMap((kind) =>
    ['status', 'category', 'priority', 'assignee', 'tags', 'labels', 'due', 'notebook', 'kind', 'checked', 'estimate', 'cost', 'updated', 'blocked-by', 'title', 'stage', 'seen'].map(
      (field) => `from: ${kind}\ngroup: ${field}\ntotal: estimate, cost`,
    ),
  ),
  ...['notes', 'tickets', 'tasks'].flatMap((kind) =>
    ['title', 'title desc', 'status desc, title', 'priority desc', 'due desc, priority', 'assignee, due', 'tags', 'estimate, cost desc', 'updated, created desc', 'kind, line desc', 'checked desc', 'notebook, id desc', 'category, text'].map(
      (sort) => `from: ${kind}\nsort: ${sort}\nwhere: checked or not checked`,
    ),
  ),
  ...['=', '!=', '<', '<=', '>', '>=', 'contains', 'not contains'].flatMap((op) => [
    `from: tickets\nwhere: status ${op} Building`,
    `from: tickets\nwhere: status ${op} wont do`,
    `from: tickets\nwhere: status ${op} Elsewhere`,
    `from: tickets\nwhere: priority ${op} medium`,
    `from: tickets\nwhere: priority ${op} 🔼`,
    `from: tickets\nwhere: priority ${op} soon`,
    `from: tasks\nwhere: priority ${op} high`,
    `from: tickets\nwhere: due ${op} today`,
    `from: tickets\nwhere: due ${op} 2026-10`,
    `from: tickets\nwhere: estimate ${op} 2.5`,
    `from: tickets\nwhere: estimate ${op} 2.5 days`,
    `from: tickets\nwhere: estimate ${op} empty`,
    `from: tickets\nwhere: assignee ${op} sam`,
    `from: tickets\nwhere: assignee ${op} "Priya Shah"`,
    `from: tickets\nwhere: labels ${op} #UI`,
    `from: notes\nwhere: tags ${op} work`,
    `from: notes\nwhere: tags ${op} design`,
    `from: notes\nwhere: title ${op} twice`,
    `from: notes\nwhere: title ${op} 10`,
    `from: notes\nwhere: rating ${op} 4`,
    `from: notes\nwhere: rating ${op} four`,
    `from: notes\nwhere: when ${op} today`,
    `from: notes\nwhere: seen ${op} b`,
    `from: notes\nwhere: links ${op} [[Twice]]`,
    `from: notes\nwhere: updated ${op} today-7`,
    `from: tasks\nwhere: checked ${op} yes`,
    `from: tasks\nwhere: checked ${op} maybe`,
    `from: tasks\nwhere: text ${op} 9 pears`,
    `from: tasks\nwhere: cost ${op} $12`,
    `from: tasks\nwhere: line ${op} 6`,
    `from: tasks\nwhere: status ${op} to do`,
    `from: tasks\nwhere: stage ${op} doing`,
    `from: tasks\nwhere: depends-on ${op} typeface`,
    `from: tasks\nwhere: note ${op} Home page`,
    `from: tasks\nwhere: kind ${op} task`,
  ]),
  'from: tasks\nwhere: status\nshow: board\ngroup: status', 'from: tasks\nwhere: done', 'from: tasks\nwhere: done is not empty', 'from: tasks\nwhere: category = done',
  'from: tasks\nwhere: recurs', 'from: tasks\nwhere: id = ask1', 'from: tasks\nwhere: scheduled <= today', 'from: tasks\nwhere: start < today and not checked',
  'from: tasks\nshow: calendar', 'from: tickets\nshow: calendar', 'from: notes\nshow: calendar', 'from: tasks\nwhere: due > today+30\nshow: calendar',
  'from: tickets [[Website]]', 'from: tickets [[Website]]\nshow: board', 'from: tickets [[website]]\nshow: board\ntotal: estimate', 'from: [[Website]] or [[Launch]]\nshow: board',
  'from: tickets\nshow: board\ngroup: priority', 'from: tickets\nshow: gantt\ngroup: status', 'from: tickets\nshow: gantt\ngroup: assignee', 'from: tasks\nshow: gantt',
  'from: tasks\nwhere: checked or not checked\nshow: gantt\ngroup: note', 'from: notes\nshow: gantt\nlimit: 3', 'from: notes\nshow: count', 'from: tickets\nshow: list',
  'from: tasks\nshow: table\nlimit: 4', 'from: [[Twice]]', 'from: [[web-1]]', 'from: [[WEB-10]] or "typeface"', 'from: [[Nothing here]]', 'from: not [[Website]] tickets',
  'from: tickets not [[Website]]', 'from: tasks [[Website]]', 'from: tasks "PEARS"', 'from: #design', 'from: tasks #design', 'from: #work', 'from: @priya-shah', 'from: tasks @Priya_Shah',
  'from: tasks (@sam or #design/header), "a"', 'from: tasks -@sam', 'from: [[ ]]', 'from: [[]]', 'from: tasks tickets', 'from: and #a', 'from: #a and', 'from: #a,,#b', 'from: ()',
  'from: (#a', 'from: #a (', 'from: -', 'from: #a - b', 'from: "a" "b" or not "c"', 'from: ‘single’ \'straight’', 'from: "😀 emoji" #tag', 'from: #-x', 'from: #tag-/ @name.-',
  'from: @', 'from: #', 'from: # tag', 'from: pages', 'from: NOTE #a', 'from: todos', 'from: task', 'from: ticket',
  'where: a', 'where: a and', 'where: a or', 'where: and a', 'where: (a', 'where: a)', 'where: ()', 'where: not', 'where: a = (b)', 'where: a = b c d and e',
  'where: a = "b" c', 'where: a="b"and c', 'where: a!=b', 'where: a! = b', 'where: a<=1', 'where: a=>1', 'where: a = -1.50', 'where: a = 1.', 'where: a = 1e3', 'where: a = 007',
  'where: a = TODAY', 'where: a = today +3w', 'where: a = today-1 week', 'where: a = today+', 'where: a = today+123456', 'where: a = Tomorrow', 'where: a = 2026-13-01',
  'where: a = 2026-10-3', 'where: a = EMPTY', 'where: a is', 'where: a is not', 'where: a is not empty and b is empty or c', 'where: a is nt empty', 'where: a not b',
  'where: a not has b', 'where: a includes "x y"', 'where: a contains', 'where: a has and b', 'where: a.b/c-d = 1', 'where: -a = 1', 'where: a@b = 1', 'where: "a" = 1',
  'where: #a = 1', 'where: [[a]] = 1', 'where: a = [[b]]', 'where: a = #b', 'where: a = @b', 'where: a = b, c', 'where: a = b = c', 'where: Completed', 'where: FILE = x',
  'where: Depends On = x', 'where: dependsOn = x', 'where: a = “open', 'where: a = [[open',
  'sort: a b c', 'sort: a up, b down, c reverse, d reversed, e ascending', 'sort: desc', 'sort: , a,, b', 'sort: a@b', 'sort: a@b desc', 'sort: by by', 'sort: BY a DESC',
  'group: a b', 'group: by', 'group: ,', 'group: a,', 'group: a@b', 'group: Tag', 'columns: , a,, b ,', 'columns: a b, c', 'columns:   a@b', 'total: Label, people', 'totals: a',
  'column: a', 'limit: 1234567', 'limit: 5 ', 'limit: -1', 'limit: 1.5', 'limit: 999999', 'show: CARDS', 'show: number', 'show: table list', 'show table', 'show : list',
  'sho: list', 'sorted: a', 'fro: x', 'wher: x', 'grup: x', 'limits: 1', 'x: y', 'ab: y', 'a b c: d', 'from tickets', ': x', ' : x', '1: x', 'from: #a\nfrom: #b', 'group: a\ngroup by: b',
  'where: a\nwhere: b\nwhere: c', 'from: tickets\n\n  where:   status = Done  \n\tshow:\ttable', 'from: tasks\r\nshow: list', 'sort by : a', 'Group  BY: a', 'from: tickets: more',
  'where: url = https://a.b/c', 'where: a = b: c',
];

const fenced = [];
const DOCS = [
  ['docs/QUERIES.md', readFileSync(`${GLYPH}docs/QUERIES.md`, 'utf8')],
  ['guidebook/index.md', readFileSync(`${APP}guidebook/index.md`, 'utf8')],
  ...chapters.map((name) => [`guidebook/chapters/${name}`, readFileSync(`${APP}guidebook/chapters/${name}`, 'utf8')]),
  // The shapes a fence takes that neither has: tildes, a longer fence, settings, one never closed.
  ['shapes', '~~~~QUERY height=900 wide=yes\nfrom: tasks\n```\n~~~~\n\n```query height=12.3em\n```\n\n````query\nshow: board\n```\n````\n```query notes\n```\n\n```query\nfrom: never closed\n'],
];
const fences = [];
for (const [name, doc] of DOCS) {
  const found = queryFencesIn(doc);
  if (!found.length) continue;
  fences.push([name, found]);
  for (const fence of found) fenced.push(fence.body);
}
/** A line of docs/QUERIES.md written as an example of a clause, `from: …` in backticks, is a query too. */
const inline = [...readFileSync(`${GLYPH}docs/QUERIES.md`, 'utf8').matchAll(/`((?:from|where|sort|group|show|columns|total|limit)(?: by)?: [^`\n]+)`/g)].map((found) => found[1]);

const bodies = [...new Set([...FROM_TESTS, ...QUERY_TEMPLATES.map((template) => template.lines), ...fenced, ...inline, ...MORE])];

// ---- running them -------------------------------------------------------------------------------------------------

/**
 * Every query is run over the web tests' library. Over `site` the ones written for it and the ones that lay
 * something out; over the whole Guide, forty-five notes, only what a person would put in a note: the ready-made
 * databases, the queries the Guide and docs/QUERIES.md write, and every field of every record once.
 */
const written_ = new Set([...QUERY_TEMPLATES.map((template) => template.lines), ...fenced, ...inline]);
const over = {
  fixture: () => true,
  site: (body) => !FROM_TESTS.includes(body) || /board|gantt|calendar|group|total/.test(body) || written_.has(body),
  guide: (body) => written_.has(body) || body.includes(WIDE),
};

const cases = [];
const months = [];
const drafts = [];
let read = 0;
for (const body of bodies) {
  const reading = readQuery(body);
  const results = {};
  if (reading.query) {
    read += 1;
    for (const name of Object.keys(LIBRARIES)) {
      if (!over[name](body)) continue;
      results[name] = runQuery(reading.query, BUILT[name], TODAY);
    }
    const result = results.fixture;
    if (result.show === 'calendar') {
      const rows = result.groups.flatMap((group) => group.rows);
      const month = openingMonth(rows, TODAY);
      months.push([body, month, monthWeeks(month, rows, TODAY).map((week) => week.map((day) => [day.day, day.date, day.inMonth, day.today, day.rows.map((row) => row.key)]))]);
    }
    if (result.show === 'board') {
      for (const lane of [...result.groups.map((group) => (group.key === '' ? null : group.label)), null]) drafts.push([body, lane, ticketDraft(reading.query, result.group, lane)]);
    }
  }
  cases.push([body, reading, results]);
}

/** Long words as their length and a sum of them, which says as much about whether two agree and is a line, not a chapter. */
const summed = (text) => {
  let sum = 0;
  for (let i = 0; i < text.length; i += 1) sum = (Math.imul(sum, 31) + text.charCodeAt(i)) >>> 0;
  return [text.length, sum];
};
const records = Object.fromEntries(
  Object.entries(BUILT).map(([name, library]) => [
    name,
    library.records.map((record) => ({ ...record, linksTo: [...record.linksTo].sort(), text: record.kind === 'task' ? record.text : summed(record.text), haystack: summed(record.haystack) })),
  ]),
);

// ---- the order of words -------------------------------------------------------------------------------------------

const WORDS = [
  ...new Set([
    ...Object.values(BUILT).flatMap((library) => library.records.flatMap((record) => [record.title, record.noteId, ...(record.kind === 'task' ? [record.text] : [])])),
    '', ' ', 'a', 'A', 'b', 'B', 'ab', 'Ab', 'AB', 'a b', 'a-b', 'a_b', 'a.b', 'a,b', 'a1', 'a01', 'a2', 'a10', 'a1b', 'a 1', '1', '01', '2', '10', '9', '1.5', '1.10', '10 apples', '9 pears',
    'GHO-9', 'GHO-10', 'gho-10', 'GHO-010', 'résumé', 'resume', 'Resume', 'Résumé', 'RESUME', 'e', 'é', 'É', 'f', 'z', 'Z', 'ß', 'ss', 'æ', 'ae', 'af', 'ø', 'o', 'p', 'ñ', 'n',
    '#tag', '@sam', 'sam', 'Sam', '(a)', '[a]', '"a"', '“a”', '’a', "'a", '-a', '–a', '—a', '_a', '$5', '£5', '€5', '5', 'To do', 'to-do', 'todo', 'To-dos', 'In progress', 'in review',
    'Done', 'done', 'Won’t do', "Won't do", 'wont do', 'x', 'X', 'y', 'ch1', 'ch01', 'ch02', 'ch10', 'ch2',
  ]),
];
const mark = (order) => (order < 0 ? '<' : order > 0 ? '>' : '=');
const collation = {
  words: WORDS,
  plain: WORDS.map((one) => WORDS.map((two) => mark(one.localeCompare(two))).join('')),
  numeric: WORDS.map((one) => WORDS.map((two) => mark(one.localeCompare(two, undefined, { numeric: true, sensitivity: 'base' }))).join('')),
};

// ---- written down -------------------------------------------------------------------------------------------------

const written = {
  made: 'tool/query_fixtures.mjs',
  locale: new Intl.Collator().resolvedOptions().locale,
  today: TODAY,
  libraries: Object.fromEntries(Object.entries(LIBRARIES).map(([name, notes]) => [name, notes.map((note) => [note.id, note.body, isoDay(new Date(note.createdAt)), isoDay(new Date(note.updatedAt))])])),
  records,
  cases,
  fences,
  months,
  drafts,
  collation,
};
mkdirSync(OUT, { recursive: true });
const text = JSON.stringify(written);
writeFileSync(`${OUT}queries.json`, text);
const run = cases.reduce((sum, [, , results]) => sum + Object.keys(results).length, 0);
console.log(`${cases.length} queries (${read} read, ${cases.length - read} with a problem), ${run} runs, ${Object.values(records).reduce((sum, list) => sum + list.length, 0)} records, ${fences.length} documents with fences, ${months.length} months, ${drafts.length} drafts, ${WORDS.length} words: ${(text.length / 1e6).toFixed(2)} MB`);
