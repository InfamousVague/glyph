import { isIsoDay } from '../days.ts';
import { fieldKey } from '../taskFields.ts';

/**
 * A query's lines, read: the grammar of a ```query fence, and the one plain sentence that says what is wrong with one
 * that cannot be read, and where (docs/QUERIES.md is the grammar written down; docs/DESIGN.md §159 why it is this
 * one). Matt asked for "notion and jira like features"; a query is the database view, written as words.
 *
 *   ```query
 *   from: tickets #bug
 *   where: status != Done and (priority >= high or due < today+7)
 *   sort: priority, due
 *   show: table
 *   ```
 *
 * One clause to a line, each a name, a colon and what it says, and each left out for its default, so `from: #bug`
 * alone is a query. The names are Dataview's and Obsidian Tasks' where they have one (`from`, `where`, `sort`,
 * `group`, `limit`), so a person who has written those reads this, and `sort by:` and `group by:` are read too.
 *
 *   from:     notes, tickets or tasks, then what to read them from: `#tag`, `[[A notebook]]` (its pages, or the notes
 *             that link to any other note), `@person`, `"words"`; side by side all of them, `or` for either, `not` or
 *             `-` to leave one out, brackets to say which goes with which
 *   where:    tests on fields: `= != < <= > >=`, `contains`, `is empty`, joined by `and`, `or`, `not` and brackets;
 *             a field alone is a test that it says something
 *   sort:     fields, each `asc` or `desc`
 *   group:    one field
 *   show:     table, list, board, calendar, gantt or count
 *   columns:  the fields a table shows, and a list and a board say beside each record
 *   total:    the fields to add up
 *   limit:    how many records at most
 *
 * A field is written as Dataview keys one: lower case, a space a dash (core/taskFields.ts `fieldKey`), so `Due Date`
 * and `due-date` are one field. A value on the right of a test is words unless it is something else: a number, a day
 * (`2026-10-03`, `today`, `today+7`, `today-2w`), `empty`, or anything in quotes, which is words whatever it says. So
 * `status != Done` needs no quotes, and a status that holds `and` or `or` does. What a word means against a field -
 * a priority's name is its rank, a status its place in the workflow - is the run's to say (core/query/values.ts);
 * this only reads.
 *
 * A query that cannot be read is never half run: it answers the first problem, its line and column, in a sentence a
 * person can act on, and the fence is drawn as its lines with that sentence under them, as a Mermaid diagram that
 * cannot be drawn stays as its text (editor/mermaid.ts). Pure, so every shape of query is a test
 * (core/query/read.test.ts), and the MCP server can bundle it.
 */

export type QueryKind = 'notes' | 'tickets' | 'tasks';

/** The ways a query is shown, in the order docs/QUERIES.md teaches them. */
export const SHOWS = ['table', 'list', 'board', 'calendar', 'gantt', 'count'] as const;
export type ShowAs = (typeof SHOWS)[number];

/** What `from:` reads a record from, after its kind. */
export type Source =
  | { kind: 'tag'; tag: string }
  | { kind: 'link'; title: string }
  | { kind: 'person'; name: string }
  | { kind: 'words'; words: string }
  | { kind: 'not'; of: Source }
  | { kind: 'and'; all: Source[] }
  | { kind: 'or'; any: Source[] };

export type Op = '=' | '!=' | '<' | '<=' | '>' | '>=' | 'contains' | '!contains';

/** What a test compares a field with. */
export type Literal =
  | { kind: 'number'; value: number; text: string }
  | { kind: 'words'; text: string; quoted: boolean }
  /** A day counted from today: 0 for `today`, 7 for `today+7`. */
  | { kind: 'today'; offset: number; text: string }
  | { kind: 'date'; day: string }
  | { kind: 'empty' };

export type Condition =
  | { kind: 'compare'; field: string; op: Op; value: Literal }
  /** `is empty` (`empty` true) and `is not empty`. */
  | { kind: 'empty'; field: string; empty: boolean }
  /** A field on its own: it says something, and not "no". */
  | { kind: 'has'; field: string }
  | { kind: 'not'; of: Condition }
  | { kind: 'and'; all: Condition[] }
  | { kind: 'or'; any: Condition[] };

export interface SortKey {
  field: string;
  desc: boolean;
}

export interface Query {
  /** What the records are: notes (tickets among them), tickets alone, or to-dos. Notes, where `from:` does not say. */
  kind: QueryKind;
  from: Source | null;
  where: Condition | null;
  /** As written; empty for the kind's own order. */
  sort: SortKey[];
  group: string | null;
  /** As written; null for the kind's own way. */
  show: ShowAs | null;
  /** As written; empty for the kind's own columns. */
  columns: string[];
  total: string[];
  limit: number | null;
}

/** Why a query cannot be read: the line and column, counting from 1 within the fence, and the sentence. */
export interface QueryProblem {
  line: number;
  column: number;
  message: string;
}

export type Reading = { query: Query; problem: null } | { query: null; problem: QueryProblem };

/** A query's lines, by name, and what each is called where it is written. */
type Clause = 'from' | 'where' | 'sort' | 'group' | 'show' | 'columns' | 'total' | 'limit';
const CLAUSES: Readonly<Record<string, Clause>> = {
  from: 'from',
  where: 'where',
  sort: 'sort',
  'sort by': 'sort',
  group: 'group',
  'group by': 'group',
  show: 'show',
  columns: 'columns',
  column: 'columns',
  total: 'total',
  totals: 'total',
  limit: 'limit',
};
/** The names, as a sentence lists them. */
export const QUERY_LINES: readonly Clause[] = ['from', 'where', 'sort', 'group', 'show', 'columns', 'total', 'limit'];

/** A kind as `from:` may write it. */
const KINDS: Readonly<Record<string, QueryKind>> = {
  notes: 'notes',
  note: 'notes',
  pages: 'notes',
  tickets: 'tickets',
  ticket: 'tickets',
  issues: 'tickets',
  tasks: 'tasks',
  task: 'tasks',
  todos: 'tasks',
  'to-dos': 'tasks',
};

/** Another way of saying a way to show, read as that way. */
const SHOW_ALSO: Readonly<Record<string, ShowAs>> = { kanban: 'board', timeline: 'gantt', number: 'count', cards: 'board' };

/**
 * The names a field is also called, by Dataview, Tasks or a person, read as the one the app keeps: `completed` is
 * Dataview's word for a ticked to-do, `completion` its done date.
 */
const ALIASES: Readonly<Record<string, string>> = {
  assignees: 'assignee',
  people: 'assignee',
  person: 'assignee',
  tag: 'tags',
  label: 'labels',
  ticked: 'checked',
  completed: 'checked',
  completion: 'done',
  modified: 'updated',
  edited: 'updated',
  file: 'note',
  page: 'note',
  dependson: 'depends-on',
};

/** A field's name as a query keeps it: Dataview's form (`fieldKey`), and the name the app keeps for an alias. */
export function fieldName(written: string): string {
  const key = fieldKey(written);
  return ALIASES[key] ?? key;
}

/** What a field's name may be: a letter, digit or `_`, then those, `.`, `/` and `-`. */
const FIELD = /^[\p{L}\p{N}_][\p{L}\p{N}_./-]*$/u;
const KEYWORDS = new Set(['and', 'or', 'not']);

// ---- the words of a clause ------------------------------------------------------------------------

interface Token {
  kind: 'word' | 'quoted' | 'tag' | 'link' | 'person' | 'op' | 'open' | 'close' | 'comma' | 'minus';
  /** As written, quotes and all. */
  raw: string;
  /** What it says: a quoted value's words, a tag's or a person's name, a link's title, an operator. */
  text: string;
  at: number;
}

/** A problem at `at` in a clause's value, before it has a line. */
class Trouble extends Error {
  constructor(
    readonly at: number,
    message: string,
  ) {
    super(message);
  }
}

/** The quotes a phone or a keyboard may type, and what closes each. */
const QUOTES: Readonly<Record<string, string>> = { '"': '"”', '“': '”"', "'": "'’", '‘': '’\'' };
const OPS = ['!=', '==', '<=', '>=', '≠', '≤', '≥', '=', '<', '>'];
const OP_READ: Readonly<Record<string, Op>> = { '==': '=', '≠': '!=', '≤': '<=', '≥': '>=' };

/** A clause's value as tokens. In `from:` a comma parts two filters and a dash leaves one out; in `where:` both are words. */
function scan(value: string, from: boolean): Token[] {
  const tokens: Token[] = [];
  let at = 0;
  const push = (kind: Token['kind'], raw: string, text = raw) => {
    tokens.push({ kind, raw, text, at });
    at += raw.length;
  };
  while (at < value.length) {
    const rest = value.slice(at);
    const char = rest[0]!;
    if (/\s/.test(char)) {
      at += 1;
      continue;
    }
    if (char === '(') push('open', char);
    else if (char === ')') push('close', char);
    else if (char === ',' && from) push('comma', char);
    else if (QUOTES[char]) {
      const close = [...rest.slice(1)].findIndex((each) => QUOTES[char]!.includes(each));
      if (close < 0) throw new Trouble(at, 'A quote opened here is never closed.');
      const raw = rest.slice(0, close + 2);
      push('quoted', raw, raw.slice(1, -1));
    } else if (rest.startsWith('[[')) {
      const close = rest.indexOf(']]');
      if (close < 0) throw new Trouble(at, 'A [[ opened here is never closed with ]].');
      const raw = rest.slice(0, close + 2);
      push('link', raw, raw.slice(2, -2).split(/[#|]/)[0]!.trim());
    } else if (/^#\p{L}/u.test(rest)) {
      const raw = /^#\p{L}[\p{L}\p{N}_/-]*/u.exec(rest)![0].replace(/[-/]+$/, '');
      push('tag', raw, raw.slice(1).toLowerCase());
    } else if (/^@\p{L}/u.test(rest)) {
      const raw = /^@\p{L}[\p{L}\p{N}_.-]*/u.exec(rest)![0].replace(/[.-]+$/, '');
      push('person', raw, raw.slice(1));
    } else if (from && char === '-' && /^-[#@["“'‘([]/.test(rest)) push('minus', char);
    else {
      const op = OPS.find((each) => rest.startsWith(each));
      if (op) push('op', op, OP_READ[op] ?? op);
      else {
        // A word runs to a space, a bracket, an operator, or (in from:) a comma.
        const raw = (from ? /^[^\s(),=<>≠≤≥]+/ : /^[^\s()=<>≠≤≥]+/).exec(rest)?.[0] ?? char;
        const word = raw.endsWith('!') && rest[raw.length] === '=' ? raw.slice(0, -1) : raw;
        push('word', word || char);
      }
    }
  }
  return tokens;
}

/** Whether a token is the keyword `word`, in any case. */
const isWord = (token: Token | undefined, ...words: string[]) => token?.kind === 'word' && words.includes(token.text.toLowerCase());

/** `“text”`, for a sentence. */
const said = (text: string) => `“${text}”`;

/** Reads tokens in order, with what each grammar asks of the next one. */
class Reader {
  at = 0;

  constructor(
    readonly tokens: readonly Token[],
    /** Where the value ends, for a problem with nothing after it. */
    readonly end: number,
  ) {}

  peek(by = 0): Token | undefined {
    return this.tokens[this.at + by];
  }

  take(): Token {
    return this.tokens[this.at++]!;
  }

  /** Where the next token is, or the end. */
  here(): number {
    return this.peek()?.at ?? this.end;
  }

  done(): boolean {
    return this.at >= this.tokens.length;
  }
}

// ---- from: --------------------------------------------------------------------------------------------

const FROM_HELP = 'write notes, tickets or tasks first, then #tags, [[notebooks]], @people or "words"';

function readFrom(value: string): { kind: QueryKind | null; source: Source | null } {
  const reader = new Reader(scan(value, true), value.length);
  let kind: QueryKind | null = null;
  const first = reader.peek();
  if (first?.kind === 'word' && KINDS[first.text.toLowerCase()]) {
    kind = KINDS[first.text.toLowerCase()]!;
    reader.take();
  }
  if (reader.done()) return { kind, source: null };
  const source = fromOr(reader);
  if (!reader.done()) {
    const left = reader.peek()!;
    throw new Trouble(left.at, left.kind === 'close' ? 'A bracket closes here that was never opened.' : `${said(left.raw)} is left over: ${FROM_HELP}.`);
  }
  return { kind, source };
}

function fromOr(reader: Reader): Source {
  const any = [fromAnd(reader)];
  while (isWord(reader.peek(), 'or')) {
    const or = reader.take();
    if (reader.done() || reader.peek()?.kind === 'close') throw new Trouble(or.at, `Something to read from is missing after ${said(or.raw)}.`);
    any.push(fromAnd(reader));
  }
  return any.length === 1 ? any[0]! : { kind: 'or', any };
}

function fromAnd(reader: Reader): Source {
  const all = [fromUnary(reader)];
  for (;;) {
    while (reader.peek()?.kind === 'comma' || isWord(reader.peek(), 'and')) reader.take();
    const next = reader.peek();
    if (!next || next.kind === 'close' || isWord(next, 'or')) break;
    all.push(fromUnary(reader));
  }
  return all.length === 1 ? all[0]! : { kind: 'and', all };
}

function fromUnary(reader: Reader): Source {
  const next = reader.peek();
  if (!next) throw new Trouble(reader.end, `Something to read from is missing here: ${FROM_HELP}.`);
  if (next.kind === 'minus' || isWord(next, 'not')) {
    reader.take();
    return { kind: 'not', of: fromUnary(reader) };
  }
  if (next.kind === 'open') {
    reader.take();
    const inner = fromOr(reader);
    if (reader.peek()?.kind !== 'close') throw new Trouble(next.at, 'A bracket opened here is never closed.');
    reader.take();
    return inner;
  }
  reader.take();
  if (next.kind === 'tag') return { kind: 'tag', tag: next.text };
  if (next.kind === 'link') {
    if (!next.text) throw new Trouble(next.at, 'A [[link]] here names no note.');
    return { kind: 'link', title: next.text };
  }
  if (next.kind === 'person') return { kind: 'person', name: next.text };
  if (next.kind === 'quoted') return { kind: 'words', words: next.text };
  if (next.kind === 'word' && KINDS[next.text.toLowerCase()]) {
    throw new Trouble(next.at, `${said(next.raw)} goes first in from:, before the #tags, [[notebooks]], @people and "words".`);
  }
  if (next.kind === 'close') throw new Trouble(next.at, 'A bracket closes here that was never opened.');
  throw new Trouble(next.at, `${said(next.raw)} isn’t something a query reads from: ${FROM_HELP}.`);
}

// ---- where: -------------------------------------------------------------------------------------------

function readWhere(value: string): Condition {
  const reader = new Reader(scan(value, false), value.length);
  const condition = whereOr(reader);
  if (!reader.done()) {
    const left = reader.peek()!;
    throw new Trouble(left.at, left.kind === 'close' ? 'A bracket closes here that was never opened.' : `${said(left.raw)} is left over: join two tests with and or or.`);
  }
  return condition;
}

function whereOr(reader: Reader): Condition {
  const any = [whereAnd(reader)];
  while (isWord(reader.peek(), 'or')) {
    reader.take();
    any.push(whereAnd(reader));
  }
  return any.length === 1 ? any[0]! : { kind: 'or', any };
}

function whereAnd(reader: Reader): Condition {
  const all = [whereUnary(reader)];
  while (isWord(reader.peek(), 'and')) {
    reader.take();
    all.push(whereUnary(reader));
  }
  return all.length === 1 ? all[0]! : { kind: 'and', all };
}

function whereUnary(reader: Reader): Condition {
  const next = reader.peek();
  if (isWord(next, 'not')) {
    reader.take();
    return { kind: 'not', of: whereUnary(reader) };
  }
  if (next?.kind === 'open') {
    reader.take();
    const inner = whereOr(reader);
    if (reader.peek()?.kind !== 'close') throw new Trouble(next.at, 'A bracket opened here is never closed.');
    reader.take();
    return inner;
  }
  return test(reader);
}

/** One test: a field, and what is asked of it. */
function test(reader: Reader): Condition {
  const token = reader.peek();
  if (!token || token.kind !== 'word' || KEYWORDS.has(token.text.toLowerCase())) {
    throw new Trouble(reader.here(), `A field is missing here, like status or due${token ? `, before ${said(token.raw)}` : ''}.`);
  }
  if (!FIELD.test(token.text)) throw new Trouble(token.at, `${said(token.raw)} isn’t a field’s name: a name is letters, numbers and dashes, like blocked-by.`);
  reader.take();
  const field = fieldName(token.text);
  const next = reader.peek();
  if (!next || next.kind === 'close' || isWord(next, 'and', 'or')) return { kind: 'has', field };
  if (next.kind === 'op') {
    reader.take();
    return { kind: 'compare', field, op: next.text as Op, value: literal(reader, `${token.raw} ${next.raw}`) };
  }
  if (isWord(next, 'is')) {
    reader.take();
    const negated = isWord(reader.peek(), 'not');
    if (negated) reader.take();
    if (isWord(reader.peek(), 'empty')) {
      reader.take();
      return { kind: 'empty', field, empty: !negated };
    }
    return { kind: 'compare', field, op: negated ? '!=' : '=', value: literal(reader, `${token.raw} is${negated ? ' not' : ''}`) };
  }
  if (isWord(next, 'contains', 'has', 'includes')) {
    reader.take();
    return { kind: 'compare', field, op: 'contains', value: literal(reader, `${token.raw} ${next.raw}`) };
  }
  if (isWord(next, 'not') && isWord(reader.peek(1), 'contains', 'has', 'includes')) {
    reader.take();
    const verb = reader.take();
    return { kind: 'compare', field, op: '!contains', value: literal(reader, `${token.raw} not ${verb.raw}`) };
  }
  throw new Trouble(next.at, `After ${said(token.raw)}, a comparison: =, !=, <, >, contains, or is empty.`);
}

const TODAY = /^today\s*(?:([+-])\s*(\d{1,5})\s*(d|days?|w|weeks?)?)?$/i;
const NUMBER = /^-?\d+(?:\.\d+)?$/;

/** What a test compares with: quoted words, or the words up to the next `and`, `or` or bracket, read for what they are. */
function literal(reader: Reader, after: string): Literal {
  const first = reader.peek();
  if (!first || first.kind === 'close' || first.kind === 'open' || first.kind === 'op' || isWord(first, 'and', 'or')) {
    throw new Trouble(reader.here(), `After ${said(after)}, something to compare it with: a word, a number, a date or empty.`);
  }
  if (first.kind === 'quoted') {
    reader.take();
    return { kind: 'words', text: first.text, quoted: true };
  }
  const words: Token[] = [];
  for (let next = reader.peek(); next && next.kind !== 'close' && next.kind !== 'open' && next.kind !== 'op' && next.kind !== 'quoted' && !isWord(next, 'and', 'or'); next = reader.peek()) {
    words.push(reader.take());
  }
  const text = words.map((word) => word.raw).join(' ');
  if (/^empty$/i.test(text)) return { kind: 'empty' };
  const today = TODAY.exec(text);
  if (today) {
    const count = Number(today[2] ?? 0) * (/^w/i.test(today[3] ?? '') ? 7 : 1);
    return { kind: 'today', offset: today[1] === '-' ? -count : count, text };
  }
  if (/^tomorrow$/i.test(text)) return { kind: 'today', offset: 1, text };
  if (/^yesterday$/i.test(text)) return { kind: 'today', offset: -1, text };
  if (/^\d{4}-\d{2}-\d{2}$/.test(text)) {
    if (!isIsoDay(text)) throw new Trouble(first.at, `${said(text)} isn’t a day on the calendar.`);
    return { kind: 'date', day: text };
  }
  if (NUMBER.test(text)) return { kind: 'number', value: Number(text), text };
  return { kind: 'words', text, quoted: false };
}

// ---- the lines ------------------------------------------------------------------------------------

/** A list of fields, `id, title, status`: each a name, in Dataview's form. */
function fieldList(value: string, at: number): string[] {
  const fields: string[] = [];
  let offset = 0;
  for (const part of value.split(',')) {
    const name = part.trim();
    if (name) {
      const key = fieldName(name);
      if (!FIELD.test(key)) throw new Trouble(at + offset + part.indexOf(name), `${said(name)} isn’t a field’s name: a name is letters, numbers and dashes, like blocked-by.`);
      fields.push(key);
    }
    offset += part.length + 1;
  }
  return fields;
}

const ASCENDING = new Set(['asc', 'ascending', 'up']);
const DESCENDING = new Set(['desc', 'descending', 'down', 'reverse', 'reversed']);

function sortList(value: string): SortKey[] {
  const keys: SortKey[] = [];
  let offset = 0;
  for (const part of value.split(',')) {
    const words = part.trim().replace(/^by\s+/i, '').split(/\s+/).filter(Boolean);
    if (words.length) {
      const last = words[words.length - 1]!.toLowerCase();
      const way = words.length > 1 && (ASCENDING.has(last) || DESCENDING.has(last)) ? words.pop()!.toLowerCase() : null;
      const name = words.join(' ');
      const key = fieldName(name);
      if (!FIELD.test(key)) {
        const where = offset + part.indexOf(words[words.length - 1] ?? name);
        throw new Trouble(where, words.length > 1 ? `${said(words[words.length - 1]!)} isn’t a way to sort: write asc or desc after the field.` : `${said(name)} isn’t a field’s name: a name is letters, numbers and dashes, like blocked-by.`);
      }
      keys.push({ field: key, desc: way !== null && DESCENDING.has(way) });
    }
    offset += part.length + 1;
  }
  return keys;
}

/** The distance from one word to another, in letters changed, added or taken away: for "did you mean". */
function distance(one: string, two: string): number {
  const row = Array.from({ length: two.length + 1 }, (_, i) => i);
  for (let i = 1; i <= one.length; i += 1) {
    let previous = row[0]!;
    row[0] = i;
    for (let j = 1; j <= two.length; j += 1) {
      const kept = row[j]!;
      row[j] = Math.min(row[j]! + 1, row[j - 1]! + 1, previous + (one[i - 1] === two[j - 1] ? 0 : 1));
      previous = kept;
    }
  }
  return row[two.length]!;
}

/** A line a query has: its name, a colon, and what it says. */
const LINE = /^(\s*)([^:]*?)\s*:(\s*)(.*?)\s*$/;

/** A fence's body read as a query, or the first problem with it. */
export function readQuery(body: string): Reading {
  const query: Query = { kind: 'notes', from: null, where: null, sort: [], group: null, show: null, columns: [], total: [], limit: null };
  const seen = new Map<Clause, number>();
  const wheres: Condition[] = [];
  const lines = body.split('\n');
  for (let index = 0; index < lines.length; index += 1) {
    const text = lines[index] ?? '';
    if (!text.trim()) continue;
    const line = index + 1;
    const problem = (column: number, message: string): Reading => ({ query: null, problem: { line, column, message } });
    const found = LINE.exec(text);
    const lead = /^\s*/.exec(text)![0].length;
    if (!found || !/^[A-Za-z][A-Za-z ]*$/.test(found[2] ?? '')) {
      if (found && found[2]) {
        const near = QUERY_LINES.find((name) => distance(name, (found[2] ?? '').toLowerCase()) <= 2);
        if (near) return problem(lead + 1, `${said(found[2])} isn’t a line a query has: did you mean ${said(near)}?`);
      }
      return problem(lead + 1, 'A query’s line is a name, a colon and what it says, like “where: status != Done”.');
    }
    const name = (found[2] ?? '').toLowerCase().replace(/\s+/g, ' ');
    const clause = CLAUSES[name];
    if (!clause) {
      const near = QUERY_LINES.find((each) => name.length > 2 && distance(each, name) <= 2);
      return problem(
        lead + 1,
        near
          ? `${said(found[2] ?? '')} isn’t a line a query has: did you mean ${said(near)}?`
          : `${said(found[2] ?? '')} isn’t a line a query has: it has from, where, sort, group, show, columns, total and limit.`,
      );
    }
    if (clause !== 'where' && seen.has(clause)) return problem(lead + 1, `${said(`${clause}:`)} is written twice: a query has one, on line ${seen.get(clause)}.`);
    seen.set(clause, line);
    const value = found[4] ?? '';
    // Where the value starts in the line, counting from 0, for a problem's column.
    const valueAt = (found[1] ?? '').length + (found[2] ?? '').length + (text.slice((found[1] ?? '').length + (found[2] ?? '').length).indexOf(':') + 1) + (found[3] ?? '').length;
    if (!value) continue;
    try {
      if (clause === 'from') {
        const from = readFrom(value);
        if (from.kind) query.kind = from.kind;
        query.from = from.source;
      } else if (clause === 'where') wheres.push(readWhere(value));
      else if (clause === 'sort') query.sort = sortList(value);
      else if (clause === 'group') {
        const words = value.replace(/^by\s+/i, '');
        const fields = fieldList(words, value.length - words.length);
        if (fields.length > 1 || /\s/.test(words.trim())) throw new Trouble(0, 'A query groups by one field, like status.');
        query.group = fields[0] ?? null;
      } else if (clause === 'show') {
        const way = value.toLowerCase();
        const show = (SHOWS as readonly string[]).includes(way) ? (way as ShowAs) : (SHOW_ALSO[way] ?? null);
        if (!show) throw new Trouble(0, `${said(value)} isn’t a way to show a query: table, list, board, calendar, gantt or count.`);
        query.show = show;
      } else if (clause === 'columns') query.columns = fieldList(value, 0);
      else if (clause === 'total') query.total = fieldList(value, 0);
      else if (clause === 'limit') {
        if (!/^\d{1,6}$/.test(value) || Number(value) < 1) throw new Trouble(0, 'A limit is a whole number, like 20.');
        query.limit = Number(value);
      }
    } catch (trouble) {
      if (!(trouble instanceof Trouble)) throw trouble;
      return problem(valueAt + trouble.at + 1, trouble.message);
    }
  }
  if (wheres.length) query.where = wheres.length === 1 ? wheres[0]! : { kind: 'and', all: wheres };
  return { query, problem: null };
}

/**
 * Every field a condition names, for what a query's defaults hang on: a tasks query reads the open ones unless its
 * `where:` says something about whether they are done.
 */
export function fieldsNamed(condition: Condition | null): Set<string> {
  const names = new Set<string>();
  const walk = (each: Condition) => {
    if (each.kind === 'and') each.all.forEach(walk);
    else if (each.kind === 'or') each.any.forEach(walk);
    else if (each.kind === 'not') walk(each.of);
    else names.add(each.field);
  };
  if (condition) walk(condition);
  return names;
}
