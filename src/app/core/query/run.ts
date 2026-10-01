import { DEFAULT_STATUSES, statusCategory, type StatusCategory } from '../properties.ts';
import { totalOf } from '../sums.ts';
import { samePerson, type PriorityName } from '../taskFields.ts';
import { titleKey } from '../titleKey.ts';
import { ganttOf } from './gantt.ts';
import { fieldsNamed, type Condition, type Query, type QueryKind, type ShowAs, type SortKey, type Source } from './read.ts';
import { noteNamed, type Library, type LibraryNote, type QueryRecord, type RecordKind } from './records.ts';
import { categoryOf, compareValues, fieldLabel, groupKey, groupValues, isEmpty, matches, says, valueOf, valueText, type Value } from './values.ts';

/**
 * A query run over the library (core/query/records.ts): the records it reads from, those its tests pass, in its order,
 * as many as its limit, in its groups, with its totals, as the cells a table, a list, a board, a calendar, a gantt or
 * a count draws (editor/queries/, docs/QUERIES.md, docs/DESIGN.md §158). Everything a drawing needs is answered here
 * as plain data, so the drawing is only drawing, and a result can be compared by what it says.
 *
 * The defaults are what make `from: #bug` alone a useful query:
 *
 * - **What is read.** Notes, unless `from:` says tickets or tasks. Notes include tickets, which are notes.
 * - **Open to-dos.** A tasks query lists the ones not ticked, unless it asks about being done: a `where:` or a `group:`
 *   that names `checked`, `status`, `done` or `category`, or a board, whose columns are the statuses.
 * - **The order.** Notes the last changed first; tickets the most urgent first, then the soonest due, then by key;
 *   to-dos the soonest due first, then the most urgent. A record with nothing in a field sorts after those that have
 *   something, whichever way; a priority's none sits between medium and low, as Tasks sorts it.
 * - **The way it is shown.** A table for tickets, a list for notes and to-dos.
 * - **The columns.** Tickets: id, title, status, assignee, priority, due. To-dos: the to-do, due, priority, assignee,
 *   and the note it is in. Notes: the title and when it was changed.
 * - **A board's columns** are its `group:`, or the status: for tickets, every status of the workflow, in order, empty
 *   ones and all, as a Jira board has them.
 *
 * Totals are added as a sum of them would be (core/sums.ts `totalOf`), over the records shown, and over each group's.
 */

/** A column: the field it shows and what it is called. */
export interface Column {
  field: string;
  label: string;
}

/** A cell, as the drawing needs it: the value's kind, and what it says. */
export type Cell =
  | { kind: 'empty' }
  | { kind: 'text'; text: string }
  | { kind: 'number'; text: string }
  /** A day; a due day not yet done is `overdue` before today, and `today` on it. */
  | { kind: 'day'; day: string; tone: 'overdue' | 'today' | null }
  | { kind: 'priority'; name: PriorityName }
  | { kind: 'status'; text: string; category: StatusCategory }
  | { kind: 'people'; names: string[] }
  | { kind: 'list'; items: string[]; tags: boolean }
  | { kind: 'bool'; on: boolean };

/** A record, drawn: what it is, how to reach it, and its cells, one for each column. */
export interface Row {
  /** Its note's id, and its line for a to-do: one row's key, whatever else changes. */
  key: string;
  kind: RecordKind;
  noteId: string;
  /** A to-do's line in its note, from 0; -1 for a note. */
  line: number;
  /** A to-do's line as written, to tick it where its note has moved under it. */
  source: string;
  anchor: string | null;
  /** What it is called: a to-do's words, a note's or a ticket's title. */
  name: string;
  /** A ticket's key, `GHO-12`. */
  id: string | null;
  /** A to-do's box; null for a note. */
  done: boolean | null;
  category: StatusCategory;
  cells: Cell[];
  /** The day it is on a calendar: its due day, else its scheduled day, its start, or its note's `date:`. */
  day: string | null;
  start: string | null;
  due: string | null;
  /** Due before today and not done. */
  overdue: boolean;
}

/** A field added up. */
export interface Total {
  field: string;
  label: string;
  text: string;
}

/** Records under one value of `group:`, or all of them under none. */
export interface Group {
  /** '' for the group of records with nothing in the field, and for a query not grouped. */
  key: string;
  /** What the group is called: the value, or "No status"; '' for a query not grouped. */
  label: string;
  /** The value, drawn, for a heading that draws it as a cell does. */
  cell: Cell | null;
  rows: Row[];
  totals: Total[];
}

export interface QueryResult {
  kind: QueryKind;
  show: ShowAs;
  columns: Column[];
  /** The column whose cell opens its record: the name's, or the first. */
  opens: number;
  /** The field grouped by: `group:`, or a board's status. */
  group: string | null;
  groups: Group[];
  /** How many records passed, and how many are shown (`limit:`). */
  matched: number;
  shown: number;
  totals: Total[];
  /** A gantt's Mermaid text, and how many records it places; null where it is not shown as one. */
  gantt: { code: string; placed: number } | null;
  /** What the query names that is not there: "No note is called “Q4”." */
  warnings: string[];
  /** The day it was run on. */
  today: string;
}

const DEFAULT_SHOW: Readonly<Record<QueryKind, ShowAs>> = { notes: 'list', tickets: 'table', tasks: 'list' };
/** What each kind of record is called, many of them: a gantt's one section, a count's words. */
export const KIND_WORDS: Readonly<Record<QueryKind, string>> = { notes: 'Notes', tickets: 'Tickets', tasks: 'To-dos' };
const DEFAULT_COLUMNS: Readonly<Record<QueryKind, readonly string[]>> = {
  notes: ['title', 'updated'],
  tickets: ['id', 'title', 'status', 'assignee', 'priority', 'due'],
  tasks: ['text', 'due', 'priority', 'assignee', 'note'],
};
const DEFAULT_SORT: Readonly<Record<QueryKind, readonly SortKey[]>> = {
  notes: [{ field: 'updated', desc: true }],
  tickets: [
    { field: 'priority', desc: false },
    { field: 'due', desc: false },
    { field: 'id', desc: false },
  ],
  tasks: [
    { field: 'due', desc: false },
    { field: 'priority', desc: false },
  ],
};
/** The fields that ask whether something is done, which turn off a tasks query's open-only default. */
const DONE_FIELDS = ['checked', 'status', 'done', 'category'];
/** The fields a calendar places a record by, the first it has. */
const DAY_FIELDS = ['due', 'scheduled', 'start', 'date'];

/** Whether a record is one of the kind asked for. */
function ofKind(record: QueryRecord, kind: QueryKind): boolean {
  if (kind === 'tasks') return record.kind === 'task';
  if (kind === 'tickets') return record.kind === 'ticket';
  return record.kind !== 'task';
}

/** Every `[[title]]` a `from:` names. */
function linksIn(source: Source | null): string[] {
  if (!source) return [];
  if (source.kind === 'link') return [source.title];
  if (source.kind === 'not') return linksIn(source.of);
  if (source.kind === 'and') return source.all.flatMap(linksIn);
  if (source.kind === 'or') return source.any.flatMap(linksIn);
  return [];
}

/** Whether a record is from what `from:` names. */
function fromHolds(source: Source, record: QueryRecord, named: ReadonlyMap<string, LibraryNote | null>): boolean {
  switch (source.kind) {
    case 'tag':
      return record.tags.some((tag) => tag === source.tag || tag.startsWith(`${source.tag}/`));
    case 'link': {
      const note = named.get(source.title) ?? null;
      if (!note) return record.linkKeys.includes(titleKey(source.title));
      // A notebook names its pages; any other note, the notes that link to it, as Dataview reads `FROM [[it]]`.
      return note.book ? record.books.includes(note.key) : record.linksTo.has(note.id);
    }
    case 'person': {
      const said = valueOf(record, 'assignee');
      return said.kind === 'people' && said.names.some((name) => samePerson(name, source.name));
    }
    case 'words':
      return record.haystack.includes(source.words.toLowerCase());
    case 'not':
      return !fromHolds(source.of, record, named);
    case 'and':
      return source.all.every((each) => fromHolds(each, record, named));
    case 'or':
      return source.any.some((each) => fromHolds(each, record, named));
  }
}

/** Whether a record passes `where:`. */
function holds(condition: Condition, record: QueryRecord, today: string): boolean {
  switch (condition.kind) {
    case 'compare':
      return matches(valueOf(record, condition.field), condition.op, condition.value, today);
    case 'empty':
      return isEmpty(valueOf(record, condition.field)) === condition.empty;
    case 'has':
      return says(valueOf(record, condition.field));
    case 'not':
      return !holds(condition.of, record, today);
    case 'and':
      return condition.all.every((each) => holds(each, record, today));
    case 'or':
      return condition.any.some((each) => holds(each, record, today));
  }
}

/** Whether a value sorts last, whichever way: nothing in it. A priority's none sorts between medium and low. */
const sortsLast = (value: Value) => isEmpty(value) && value.kind !== 'priority';

/** Records in the order `keys` asks, then by note and line, so two runs of one query agree. */
function sorted(records: readonly QueryRecord[], keys: readonly SortKey[]): QueryRecord[] {
  const decorated = records.map((record) => ({ record, values: keys.map((key) => valueOf(record, key.field)) }));
  decorated.sort((a, b) => {
    for (let i = 0; i < keys.length; i += 1) {
      const one = a.values[i]!;
      const two = b.values[i]!;
      const last = Number(sortsLast(one)) - Number(sortsLast(two));
      if (last) return last;
      if (sortsLast(one)) continue;
      const order = compareValues(one, two);
      if (order) return keys[i]!.desc ? -order : order;
    }
    return (
      a.record.title.localeCompare(b.record.title, undefined, { numeric: true, sensitivity: 'base' }) ||
      a.record.noteId.localeCompare(b.record.noteId) ||
      a.record.line - b.record.line
    );
  });
  return decorated.map((each) => each.record);
}

/** A value as a cell; `open` says whether its record is still to be done, which a due day's tone hangs on. */
function cellOf(value: Value, field: string, today: string, open: boolean): Cell {
  switch (value.kind) {
    case 'empty':
      return { kind: 'empty' };
    case 'text':
      return { kind: 'text', text: value.text };
    case 'number':
      return { kind: 'number', text: value.text };
    case 'day': {
      const tone = field === 'due' && open ? (value.day < today ? 'overdue' : value.day === today ? 'today' : null) : null;
      return { kind: 'day', day: value.day, tone };
    }
    case 'priority':
      return value.name ? { kind: 'priority', name: value.name } : { kind: 'empty' };
    case 'status':
      return { kind: 'status', text: value.text, category: value.category };
    case 'people':
      return { kind: 'people', names: value.names };
    case 'list':
      return { kind: 'list', items: value.items, tags: value.tags };
    case 'bool':
      return { kind: 'bool', on: value.on };
  }
}

/** A day field's day, where it is one. */
function dayOf(record: QueryRecord, field: string): string | null {
  const value = valueOf(record, field);
  return value.kind === 'day' ? value.day : null;
}

function rowOf(record: QueryRecord, columns: readonly Column[], today: string): Row {
  const category = categoryOf(record);
  const due = dayOf(record, 'due');
  const done = category === 'done' || record.done === true;
  const id = record.kind === 'ticket' ? (record.ticket?.id ?? null) : null;
  return {
    key: record.kind === 'task' ? `${record.noteId}:${record.line}` : record.noteId,
    kind: record.kind,
    noteId: record.noteId,
    line: record.line,
    source: record.source,
    anchor: record.anchor,
    name: record.kind === 'task' ? record.text : record.title,
    id,
    done: record.done,
    category,
    cells: columns.map((column) => cellOf(valueOf(record, column.field), column.field, today, !done)),
    day: DAY_FIELDS.map((field) => dayOf(record, field)).find((found) => found !== null) ?? null,
    start: dayOf(record, 'start'),
    due,
    overdue: due !== null && due < today && !done,
  };
}

/** The totals of `fields` over `records`, each added as a sum would be. */
function totalsOf(fields: readonly string[], records: readonly QueryRecord[]): Total[] {
  return fields.map((field) => {
    const written = records.flatMap((record) => {
      const value = valueOf(record, field);
      return value.kind === 'number' || value.kind === 'text' ? [value.text] : [];
    });
    return { field, label: fieldLabel(field), text: totalOf(written) ?? '0' };
  });
}

/** What a group of records with nothing in the field is called: "No status", "No due". */
const noneLabel = (field: string) => `No ${fieldLabel(field).toLowerCase()}`;

/** A group's heading, as words: the value, a ticked to-do's "Done", a status's own words. */
function groupLabel(value: Value, field: string): string {
  if (isEmpty(value)) return noneLabel(field);
  if (value.kind === 'bool') return value.on ? 'Done' : 'Not done';
  if (value.kind === 'list' && value.tags) return `#${value.items[0]}`;
  return valueText(value);
}

/**
 * The records in groups by `field`, in the order the field's values sort, the group with nothing last. A list puts
 * its record in a group for each thing it holds. `columns` are the groups to have whether or not anything is in them:
 * a ticket board's workflow.
 */
function grouped(records: readonly QueryRecord[], field: string, columns: readonly string[], workflow: readonly string[]): { key: string; value: Value; records: QueryRecord[] }[] {
  const groups = new Map<string, { key: string; value: Value; records: QueryRecord[] }>();
  for (const status of columns) {
    const value: Value = { kind: 'status', text: status, rank: workflow.indexOf(status), category: statusCategory(status, workflow), workflow };
    groups.set(groupKey(value), { key: groupKey(value), value, records: [] });
  }
  for (const record of records) {
    const value = valueOf(record, field);
    const each = isEmpty(value) ? [value] : groupValues(value);
    for (const one of each) {
      const key = groupKey(one);
      const group = groups.get(key) ?? { key, value: one, records: [] };
      group.records.push(record);
      groups.set(key, group);
    }
  }
  return [...groups.values()].sort((a, b) => {
    const none = Number(a.key === '') - Number(b.key === '');
    return none || compareValues(a.value, b.value);
  });
}

/** The workflow a board of these records has: a notebook's named in `from:`, the one they all share, or the default. */
function workflowOf(query: Query, library: Library, records: readonly QueryRecord[]): readonly string[] {
  for (const title of linksIn(query.from)) {
    const note = noteNamed(library, title);
    if (note?.statuses) return note.statuses;
  }
  const flows = [...new Set(records.map((record) => record.workflow))];
  return flows.length === 1 ? flows[0]! : DEFAULT_STATUSES;
}

/**
 * `query` run over `library` on `today` (a day, core/days.ts): every record of its kind that is from what `from:`
 * names and passes `where:`, sorted, limited, grouped and totalled, as the rows the drawing draws.
 */
export function runQuery(query: Query, library: Library, today: string): QueryResult {
  const show = query.show ?? DEFAULT_SHOW[query.kind];
  const named = new Map<string, LibraryNote | null>();
  const warnings: string[] = [];
  for (const title of linksIn(query.from)) {
    if (named.has(title)) continue;
    const note = noteNamed(library, title);
    named.set(title, note);
    if (!note) warnings.push(`No note is called “${title}”.`);
  }
  const groupField = query.group ?? (show === 'board' ? 'status' : null);
  const asksDone = [...fieldsNamed(query.where), ...(groupField ? [groupField] : [])].some((field) => DONE_FIELDS.includes(field));
  const passed = library.records.filter(
    (record) =>
      ofKind(record, query.kind) &&
      (!query.from || fromHolds(query.from, record, named)) &&
      (query.kind !== 'tasks' || asksDone || record.done === false) &&
      (!query.where || holds(query.where, record, today)),
  );
  const ordered = sorted(passed, query.sort.length ? query.sort : DEFAULT_SORT[query.kind]);
  const shown = query.limit ? ordered.slice(0, query.limit) : ordered;

  const fields = query.columns.length ? query.columns : DEFAULT_COLUMNS[query.kind];
  const columns = fields.map((field) => ({ field, label: fieldLabel(field) }));
  const nameField = query.kind === 'tasks' ? 'text' : 'title';
  const opens = Math.max(0, fields.indexOf(nameField));

  let groups: Group[];
  if (groupField) {
    const workflow = workflowOf(query, library, shown);
    // A ticket board has every status of its workflow as a column, as a Jira board does, whether or not anything is in it.
    const always = show === 'board' && groupField === 'status' && query.kind === 'tickets' ? workflow : [];
    groups = grouped(shown, groupField, always, workflow).map((group) => ({
      key: group.key,
      label: groupLabel(group.value, groupField),
      cell: isEmpty(group.value) ? null : cellOf(group.value, groupField, today, true),
      rows: group.records.map((record) => rowOf(record, columns, today)),
      totals: totalsOf(query.total, group.records),
    }));
  } else {
    groups = [{ key: '', label: '', cell: null, rows: shown.map((record) => rowOf(record, columns, today)), totals: totalsOf(query.total, shown) }];
  }

  return {
    kind: query.kind,
    show,
    columns,
    opens,
    group: groupField,
    groups,
    matched: passed.length,
    shown: shown.length,
    totals: totalsOf(query.total, shown),
    gantt: show === 'gantt' ? ganttOf(groups, KIND_WORDS[query.kind]) : null,
    warnings,
    today,
  };
}
