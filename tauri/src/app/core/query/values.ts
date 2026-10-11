import { isIsoDay, isoDayAfter } from '../days.ts';
import { linkTargets, propertyKind, propertyList, statusCategory, TICKET_PROPERTIES, type StatusCategory } from '../properties.ts';
import { writtenNumber } from '../sums.ts';
import { DATE_KEYS, PRIORITIES, priorityOf, priorityRank, samePerson, type PriorityName } from '../taskFields.ts';
import type { Literal, Op } from './read.ts';
import type { QueryRecord } from './records.ts';

/**
 * What a field says on a record, and how a query compares it, sorts it and groups by it (docs/QUERIES.md). A query's
 * words are read in core/query/read.ts; what they mean against a note, a ticket or a to-do is here.
 *
 * A field is found the way the record keeps it. Every record has the built-ins: `title` (its note's), `note` (the
 * same, read better for a to-do), `notebook`, `tags`, `created`, `updated`, `kind`, `status` and `category`, where its
 * status stands (core/properties.ts `statusCategory`). A note has its front matter, by key, and a ticket its ticket's
 * properties read as core/properties.ts reads them; a to-do has `text`, `checked`, `line` and its fields as
 * core/taskFields.ts reads them, a `[key:: value]` by its key. Nothing is inherited: a to-do in a ticket is not the
 * ticket, so a to-do's `status` is its own, Done where it is ticked.
 *
 * A value has a kind, and the kind says how it compares, so the words of a query mean what a person meant by them:
 *
 * - **A priority** compares by its rank, the most urgent the greatest: `priority >= high` is high and highest. A
 *   record with none sits between medium and low, as Obsidian Tasks puts it, so `priority < high` includes it.
 * - **A status** compares by its place in the workflow, so `status < Done` is every status before it.
 * - **A day** compares as its ten characters (core/days.ts), against `today`, `today+7` or a date.
 * - **A number** compares as a number, read as a sum reads one (core/sums.ts), so `$1,200 > 1000`.
 * - **A person** is the same person however they are written (core/taskFields.ts `samePerson`).
 * - **A list** - tags, labels, what blocks a ticket, the people on a to-do - is equal to anything it holds, so
 *   `labels = ui` and `tags contains work` read alike, and a tag holds the tags inside it (`#work/clients`).
 * - **Words** are equal whatever their case and punctuation; `contains` looks inside them.
 *
 * Anything compared with a field that says nothing is false but `!=`, as Dataview has it, so `due < today` never lists
 * what has no due date. A field written wrong is not an error: a query names any front matter key there may be, and
 * one no record has is empty on every record. Pure (core/query/values.test.ts).
 */

export type Value =
  | { kind: 'empty' }
  | { kind: 'text'; text: string }
  | { kind: 'number'; value: number; text: string }
  | { kind: 'day'; day: string }
  /** A priority, or none (`name` null), which still sorts and compares, between medium and low. */
  | { kind: 'priority'; name: PriorityName | null }
  /** A status, its place in the workflow it is in (`rank`), and where it stands. */
  | { kind: 'status'; text: string; rank: number; category: StatusCategory; workflow: readonly string[] }
  | { kind: 'people'; names: string[] }
  /** Tags, labels, links: `tags` for a list of tags, which hold the tags inside them. */
  | { kind: 'list'; items: string[]; tags: boolean }
  | { kind: 'bool'; on: boolean };

export const EMPTY: Value = { kind: 'empty' };

const text = (said: string | null | undefined): Value => (said?.trim() ? { kind: 'text', text: said.trim() } : EMPTY);
const day = (said: string | null | undefined): Value => (said && isIsoDay(said) ? { kind: 'day', day: said } : text(said));
const people = (names: readonly string[]): Value => {
  const kept = names.map((name) => name.replace(/^@+/, '').trim()).filter(Boolean);
  return kept.length ? { kind: 'people', names: kept } : EMPTY;
};
const list = (items: readonly string[], tags = false): Value => (items.length ? { kind: 'list', items: [...items], tags } : EMPTY);

/** Whether a value says nothing: no value, no priority, a list with nothing in it. */
export function isEmpty(value: Value): boolean {
  switch (value.kind) {
    case 'empty':
      return true;
    case 'priority':
      return value.name === null;
    case 'people':
      return value.names.length === 0;
    case 'list':
      return value.items.length === 0;
    default:
      return false;
  }
}

/** Words as two of them are compared: lower case, no apostrophes, nothing but letters and numbers. */
const norm = (words: string) =>
  words
    .toLowerCase()
    .replace(/['’]/g, '')
    .replace(/[^\p{L}\p{N}]+/gu, '');

/** A status's place in its workflow, the most finished last; a status the workflow has not got, by where it stands. */
function statusRank(status: string, workflow: readonly string[]): { rank: number; category: StatusCategory } {
  const category = statusCategory(status, workflow);
  const at = workflow.findIndex((each) => norm(each) === norm(status));
  if (at >= 0) return { rank: at, category };
  return { rank: category === 'todo' ? -0.5 : category === 'doing' ? (workflow.length - 1) / 2 : workflow.length - 0.5, category };
}

const status = (said: string | null | undefined, workflow: readonly string[]): Value => {
  const clean = said?.trim();
  return clean ? { kind: 'status', text: clean, ...statusRank(clean, workflow), workflow } : EMPTY;
};

/** A value written as words, read for what it is: a day, a number, links, a list, or words. */
function inferred(said: string | null | undefined): Value {
  const clean = said?.trim() ?? '';
  if (!clean) return EMPTY;
  if (isIsoDay(clean)) return { kind: 'day', day: clean };
  const number = writtenNumber(clean);
  if (number !== null) return { kind: 'number', value: number, text: clean };
  if (clean.includes('[[')) return list(linkTargets(clean));
  if (clean.startsWith('[') && clean.endsWith(']')) return list(propertyList(clean));
  return { kind: 'text', text: clean };
}

/** A property's value, read as what its key holds (core/properties.ts `propertyKind`). */
function typed(key: string, said: string | null | undefined, workflow: readonly string[]): Value {
  const clean = said?.trim() ?? '';
  if (!clean) return EMPTY;
  switch (propertyKind(key)) {
    case 'date':
      return day(clean);
    case 'priority':
      return priorityOf(clean) ? { kind: 'priority', name: priorityOf(clean)!.name } : text(clean);
    case 'number': {
      const number = writtenNumber(clean) ?? Number.parseFloat(clean);
      return Number.isFinite(number) ? { kind: 'number', value: number, text: clean } : text(clean);
    }
    case 'person':
      return people(propertyList(clean));
    case 'links':
      return list(linkTargets(clean));
    case 'link':
      return text(linkTargets(clean)[0]);
    case 'list':
      return list(propertyList(clean).map((item) => item.replace(/^#+/, '')));
    case 'status':
      return status(clean, workflow);
    case 'id':
      return text(clean);
    default:
      return inferred(clean);
  }
}

/** Where a record stands: a ticket's or a note's status's, and for a to-do, ticked or not. */
export function categoryOf(record: QueryRecord): StatusCategory {
  const said = valueOf(record, 'status');
  return said.kind === 'status' ? said.category : 'todo';
}

/** A to-do's status: its own `[status:: …]`, or Done where it is ticked, Cancelled where it has ❌, else To do. */
function taskStatus(record: QueryRecord): Value {
  const named = record.fields?.fields.status;
  if (named?.trim()) return status(named, record.workflow);
  if (record.done) return status('Done', record.workflow);
  if (record.fields?.cancelled) return status('Cancelled', record.workflow);
  return status('To do', record.workflow);
}

function taskValue(record: QueryRecord, field: string): Value {
  const fields = record.fields!;
  const named = Object.hasOwn(fields.fields, field) ? fields.fields[field] : undefined;
  if (field === 'status') return taskStatus(record);
  if (field === 'checked') return { kind: 'bool', on: record.done === true };
  if (field === 'line') return { kind: 'number', value: record.line + 1, text: String(record.line + 1) };
  if (field === 'created') return day(fields.created ?? record.created);
  if ((DATE_KEYS as readonly string[]).includes(field)) return day(fields[field as (typeof DATE_KEYS)[number]]);
  if (field === 'priority') return { kind: 'priority', name: fields.priority };
  if (field === 'assignee') return people([...fields.assignees, ...propertyList(named)]);
  if (field === 'recurs') return text(fields.recurs);
  if (field === 'id') return text(fields.id ?? named);
  if (field === 'depends-on') return list(fields.dependsOn);
  return typed(field, named, record.workflow);
}

function noteValue(record: QueryRecord, field: string): Value {
  const said = Object.hasOwn(record.props, field) ? record.props[field] : undefined;
  const ticket = record.ticket;
  if (field === 'created') return said && isIsoDay(said.trim()) ? day(said.trim()) : day(record.created);
  if (field === 'checked') return ticket ? { kind: 'bool', on: ticket.category === 'done' } : EMPTY;
  if (field === 'status') return status(ticket ? ticket.status : said, record.workflow);
  if (ticket) {
    if (field === 'id') return text(ticket.id ?? said);
    if (field === 'priority') return ticket.priority ? { kind: 'priority', name: ticket.priority } : typed(field, said, record.workflow);
    if (field === 'assignee') return people(propertyList(said));
    if (field === 'estimate' && ticket.estimate !== null) return { kind: 'number', value: ticket.estimate, text: said?.trim() || String(ticket.estimate) };
    if (field === 'blocked-by') return list(ticket.blockedBy);
    if (field === 'parent') return text(ticket.parent);
    if (field === 'labels') return list(ticket.labels);
  }
  if (field === 'priority') return said?.trim() ? typed(field, said, record.workflow) : { kind: 'priority', name: null };
  return typed(field, said, record.workflow);
}

/** What `field` (as core/query/read.ts `fieldName` keeps it) says on `record`. */
export function valueOf(record: QueryRecord, field: string): Value {
  switch (field) {
    case 'title':
    case 'note':
      return text(record.title);
    case 'text':
      return text(record.text);
    case 'notebook':
      return text(record.notebook);
    case 'tags':
      return list(record.tags, true);
    case 'updated':
      return day(record.updated);
    case 'kind':
      return text(record.kind);
    case 'category': {
      const said = record.kind === 'task' ? taskStatus(record) : noteValue(record, 'status');
      return said.kind === 'status' ? text(CATEGORY_WORDS[said.category]) : record.kind === 'note' ? EMPTY : text(CATEGORY_WORDS.todo);
    }
    default:
      return record.kind === 'task' ? taskValue(record, field) : noteValue(record, field);
  }
}

/** Where a status stands, in words: what `category` says, and a group of it is called. */
export const CATEGORY_WORDS: Readonly<Record<StatusCategory, string>> = { todo: 'To do', doing: 'In progress', done: 'Done' };

// ---- comparing ------------------------------------------------------------------------------------

/** What a literal says as words. */
function literalText(literal: Literal, today: string): string {
  if (literal.kind === 'number' || literal.kind === 'words') return literal.text;
  if (literal.kind === 'today') return isoDayAfter(today, literal.offset) ?? today;
  if (literal.kind === 'date') return literal.day;
  return '';
}

/** A literal as a day, where it is one. */
function literalDay(literal: Literal, today: string): string | null {
  if (literal.kind === 'today') return isoDayAfter(today, literal.offset);
  if (literal.kind === 'date') return literal.day;
  if (literal.kind === 'words' && isIsoDay(literal.text.trim())) return literal.text.trim();
  return null;
}

/** A literal as a number, where it is one. */
function literalNumber(literal: Literal): number | null {
  if (literal.kind === 'number') return literal.value;
  if (literal.kind === 'words') return writtenNumber(literal.text);
  return null;
}

/** An order, as `op` asks of it: how the value stands to what it is compared with. */
function ordered(order: number, op: Op): boolean {
  if (op === '=' || op === 'contains') return order === 0;
  if (op === '!=' || op === '!contains') return order !== 0;
  if (op === '<') return order < 0;
  if (op === '<=') return order <= 0;
  if (op === '>') return order > 0;
  return order >= 0;
}

const sign = (n: number) => (n < 0 ? -1 : n > 0 ? 1 : 0);
const textOrder = (a: string, b: string) => sign(a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' }));

/** Words that say yes to a ticked to-do, and no. */
const YES = new Set(['yes', 'true', 'done', 'ticked', 'checked', 'x', '1', 'y']);
const NO = new Set(['no', 'false', 'open', 'unticked', 'unchecked', 'not done', '0', 'n']);

/** An item of a list as it is compared: its `#`, its `@` and its link's brackets off. */
const itemWords = (item: string) => norm(item.replace(/^[#@]+/, '').replace(/^\[\[(.*)\]\]$/, '$1'));

/** Whether `value` passes `op` against `literal`, `today` being the day `today` names. */
export function matches(value: Value, op: Op, literal: Literal, today: string): boolean {
  if (literal.kind === 'empty') {
    if (op === '=' || op === 'contains') return isEmpty(value);
    if (op === '!=' || op === '!contains') return !isEmpty(value);
    return false;
  }
  const words = literalText(literal, today);
  const negative = op === '!=' || op === '!contains';
  if (value.kind === 'priority') {
    const other = priorityOf(words);
    if (!other) return negative;
    // The most urgent the greatest: highest is 0 in rank, so the order is turned round.
    return ordered(sign(other.rank - priorityRank(value.name)), op);
  }
  if (isEmpty(value)) return negative;
  switch (value.kind) {
    case 'day': {
      const other = literalDay(literal, today);
      if (op === 'contains' || op === '!contains') return value.day.includes(words) !== negative;
      if (other === null) return negative;
      return ordered(sign(value.day < other ? -1 : value.day > other ? 1 : 0), op);
    }
    case 'number': {
      const other = literalNumber(literal);
      if (op === 'contains' || op === '!contains') return value.text.toLowerCase().includes(words.toLowerCase()) !== negative;
      if (other === null) return op === '=' ? norm(value.text) === norm(words) : negative;
      return ordered(sign(value.value - other), op);
    }
    case 'bool': {
      const said = words.trim().toLowerCase();
      const other = YES.has(said) ? true : NO.has(said) ? false : null;
      if (other === null || (op !== '=' && op !== '!=')) return negative;
      return (value.on === other) !== negative;
    }
    case 'status': {
      if (op === 'contains' || op === '!contains') return value.text.toLowerCase().includes(words.toLowerCase()) !== negative;
      if (op === '=' || op === '!=') return (norm(value.text) === norm(words)) !== negative;
      // Before or after in the workflow: the other status's place in the value's, or where it stands if it has none.
      return ordered(sign(value.rank - statusRank(words, value.workflow).rank), op);
    }
    case 'people': {
      const has = value.names.some((name) => samePerson(name, words));
      if (op === '=' || op === 'contains') return has;
      if (negative) return !has;
      return ordered(textOrder(value.names[0]!, words), op);
    }
    case 'list': {
      const want = itemWords(words);
      const has = value.items.some((item) => {
        const mine = itemWords(item);
        if (mine === want) return true;
        // A tag holds the tags inside it: #work has #work/clients.
        return value.tags && item.toLowerCase().replace(/^#+/, '').startsWith(`${words.toLowerCase().replace(/^#+/, '')}/`);
      });
      if (op === '=' || op === 'contains') return has;
      if (negative) return !has;
      return ordered(textOrder(value.items[0]!, words), op);
    }
    case 'text': {
      if (op === '=' || op === '!=') return (norm(value.text) === norm(words)) !== negative;
      if (op === 'contains' || op === '!contains') return value.text.toLowerCase().includes(words.toLowerCase()) !== negative;
      const mine = writtenNumber(value.text);
      const other = literalNumber(literal);
      if (mine !== null && other !== null) return ordered(sign(mine - other), op);
      return ordered(textOrder(value.text, words), op);
    }
    default:
      return negative;
  }
}

/** Whether a field says something, and not "no": a field alone in `where:`. */
export function says(value: Value): boolean {
  if (isEmpty(value)) return false;
  if (value.kind === 'bool') return value.on;
  if (value.kind === 'number') return value.value !== 0;
  return true;
}

// ---- sorting and grouping -------------------------------------------------------------------------

/** Each kind's place among the others, for a field that is one kind on some records and another on others. */
const KIND_ORDER: readonly Value['kind'][] = ['priority', 'status', 'day', 'number', 'bool', 'people', 'list', 'text', 'empty'];

/**
 * Two values in order: priorities the most urgent first, statuses in the workflow's order, days and numbers from the
 * least, words as a person sorts them (`GHO-9` before `GHO-10`). A record with no value is the caller's to put last.
 */
export function compareValues(a: Value, b: Value): number {
  if (a.kind === 'priority' && b.kind === 'priority') return priorityRank(a.name) - priorityRank(b.name);
  if (a.kind === 'status' && b.kind === 'status') return a.rank - b.rank || textOrder(a.text, b.text);
  if (a.kind === 'day' && b.kind === 'day') return a.day < b.day ? -1 : a.day > b.day ? 1 : 0;
  if (a.kind === 'number' && b.kind === 'number') return a.value - b.value;
  if (a.kind === 'bool' && b.kind === 'bool') return Number(a.on) - Number(b.on);
  if (a.kind !== b.kind && a.kind !== 'text' && b.kind !== 'text') return KIND_ORDER.indexOf(a.kind) - KIND_ORDER.indexOf(b.kind);
  return textOrder(valueText(a), valueText(b));
}

/** A value as words: what a group is called and a cell says where it has nothing better. */
export function valueText(value: Value): string {
  switch (value.kind) {
    case 'empty':
      return '';
    case 'text':
    case 'number':
    case 'status':
      return value.text;
    case 'day':
      return value.day;
    case 'priority':
      return PRIORITIES.find((p) => p.name === value.name)?.label ?? '';
    case 'people':
      return value.names.join(', ');
    case 'list':
      return value.items.join(', ');
    case 'bool':
      return value.on ? 'Yes' : 'No';
  }
}

/** The groups a value puts its record in: one for most, one for each thing a list holds, none-group for nothing. */
export function groupValues(value: Value): Value[] {
  if (value.kind === 'people') return value.names.map((name) => ({ kind: 'people', names: [name] }) as Value);
  if (value.kind === 'list') return value.items.map((item) => ({ kind: 'list', items: [item], tags: value.tags }) as Value);
  return [value];
}

/** A group's key: two values in one group have one key. */
export function groupKey(value: Value): string {
  if (isEmpty(value)) return '';
  if (value.kind === 'people') return `@${value.names[0]!.toLowerCase().replace(/[\s_-]+/g, '-')}`;
  if (value.kind === 'priority') return `!${value.name}`;
  return `${value.kind}:${norm(valueText(value)) || valueText(value)}`;
}

// ---- names --------------------------------------------------------------------------------------------

/** What a field is called at the head of a column, a group or a total. */
const LABELS: Readonly<Record<string, string>> = {
  title: 'Title',
  note: 'Note',
  text: 'To-do',
  notebook: 'Notebook',
  tags: 'Tags',
  created: 'Created',
  updated: 'Updated',
  kind: 'Kind',
  category: 'Category',
  checked: 'Ticked',
  line: 'Line',
  done: 'Done',
  due: 'Due',
  start: 'Start',
  scheduled: 'Scheduled',
  cancelled: 'Cancelled',
  recurs: 'Repeats',
  'depends-on': 'Depends on',
};

export function fieldLabel(field: string): string {
  const own = LABELS[field] ?? TICKET_PROPERTIES.find((property) => property.key === field)?.label;
  if (own) return own;
  const words = field.replace(/[-_]+/g, ' ').trim();
  return words ? `${words.charAt(0).toUpperCase()}${words.slice(1)}` : field;
}
