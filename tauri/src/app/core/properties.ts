import { isIsoDay } from './days.ts';
import { frontMatterEnd, frontMatterValue, unquoted, withFrontMatterValue } from './frontMatter.ts';
import { isDoneName } from './itemSyntax.ts';
import { priorityOf, type PriorityName } from './taskFields.ts';

/**
 * A note's properties - its front matter read as named values, the way Notion shows a page's - and a ticket's
 * vocabulary (Matt asked what Notion- and Jira-like features custom Markdown could give the app, "like tickets and
 * such", and picked tickets as notes: docs/DESIGN.md §156).
 *
 *   ---
 *   type: ticket
 *   id: GHO-12
 *   status: In progress
 *   assignee: Sam
 *   priority: high
 *   due: 2026-10-03
 *   estimate: 3
 *   blocked-by: "[[GHO-9]]"
 *   ---
 *
 * A ticket is a note with `type: ticket`, and its fields are front matter, which Obsidian shows as properties, Jekyll
 * and Hugo read, and GitHub draws as a table over the file: nothing about it needs the app. A notebook (book/book.ts)
 * gives its tickets a key, `key: GHO`, and each new one the next number, `GHO-13`, as Jira does; `[[GHO-12]]` then
 * links to it by that key. The notebook may name its own workflow, `statuses: [Ideas, Building, Live]`.
 *
 * Where the front matter ends is core/frontMatter.ts's `frontMatterEnd`, and nothing here has a second rule for it; a
 * value's quotes come off by its `unquoted`. That rule takes no YAML list written down the page (`  - GHO-9` is not a
 * `key:` line, so the block is not front matter), so a list here is written across, `["[[GHO-9]]", "[[GHO-10]]"]`, and
 * read either that way or with commas, as `authors: Matt, Claude` is (core/authors.ts). A priority's names are
 * core/taskFields.ts's, so a ticket and a to-do sort as one. Pure: the MCP server can bundle it, and every front
 * matter edge is a test (core/properties.test.ts).
 */

// ---- reading -------------------------------------------------------------------------------------

/** One property: its key as written, its value with its quotes off, and the line of the body it is on (from 0). */
export interface Property {
  key: string;
  value: string;
  line: number;
}

/**
 * A property's line: a key at the start of the line, its colon, and its value. An indented `key:` belongs to the one
 * above it in YAML, and is not a property of the note's own.
 */
const PROPERTY_LINE = /^([\w.-]+)[ \t]*:(.*)$/;

/** Every property in the note's front matter, in order; none where it has no front matter. */
export function propertiesOf(body: string): Property[] {
  const lines = body.split('\n');
  const end = frontMatterEnd(lines);
  const found: Property[] = [];
  for (let line = 1; line < end - 1; line += 1) {
    const said = PROPERTY_LINE.exec(lines[line] ?? '');
    if (said) found.push({ key: said[1] ?? '', value: unquoted((said[2] ?? '').trim()), line });
  }
  return found;
}

/** A value that is note links and nothing else, `[[GHO-9]], [[GHO-10]]`: a list with commas, never a flow list. */
const LINKS_ONLY = /^\[\[[^\]\n]*\]\](?:\s*,\s*\[\[[^\]\n]*\]\])*$/;

/**
 * `text` cut at its commas, but not at one inside quotes that open an item, or inside brackets: an item may be a note
 * link, `[[GHO-9]]`, or say "Won't do", with an apostrophe that is not a quote.
 */
function cutAtCommas(text: string): string[] {
  const parts: string[] = [];
  let start = 0;
  let depth = 0;
  let quote: string | null = null;
  for (let at = 0; at < text.length; at += 1) {
    const char = text[at];
    if (quote) {
      if (char === '\\' && quote === '"') at += 1;
      else if (char === quote && quote === "'" && text[at + 1] === "'") at += 1;
      else if (char === quote) quote = null;
      continue;
    }
    if ((char === '"' || char === "'") && !text.slice(start, at).trim()) quote = char;
    else if (char === '[') depth += 1;
    else if (char === ']') depth = Math.max(0, depth - 1);
    else if (char === ',' && depth === 0) {
      parts.push(text.slice(start, at));
      start = at + 1;
    }
  }
  parts.push(text.slice(start));
  return parts;
}

/**
 * A value as a list: a flow list, `["[[GHO-9]]", "[[GHO-10]]"]` or `[bug, ui]`, or names with commas, `Matt, Claude`.
 * Each item with its quotes off and trimmed, empty ones dropped. A value of note links alone, `[[GHO-9]]`, is that
 * link, not a list inside a list, which is how YAML would read it and nobody meant.
 */
export function propertyList(value: string | null | undefined): string[] {
  const text = (value ?? '').trim();
  if (!text) return [];
  const flow = text.startsWith('[') && text.endsWith(']') && !LINKS_ONLY.test(text);
  return cutAtCommas(flow ? text.slice(1, -1) : text)
    .map((item) => unquoted(item.trim()).trim())
    .filter(Boolean);
}

/** A note link as a whole item: `[[GHO-9]]`, a `#heading` or `|words` after the title not part of it. */
const LINK_ITEM = /^\[\[([^\]\n|#]*)(?:[#|][^\]\n]*)?\]\]$/;

/**
 * What a `blocked-by:` or `parent:` points at: the title in each note link of the list (`GHO-9` from `[[GHO-9]]` and
 * from `[[GHO-9|the login loop]]`), and an item written without brackets as it is, so a hand-written `blocked-by:
 * GHO-9` still points.
 */
export function linkTargets(value: string | null | undefined): string[] {
  return propertyList(value)
    .map((item) => (LINK_ITEM.exec(item)?.[1] ?? item).trim())
    .filter(Boolean);
}

// ---- writing -------------------------------------------------------------------------------------

/** A key front matter can hold, as core/frontMatter.ts reads a key's line: letters, digits, `_`, `.` and `-`. */
export function isPropertyKey(key: string): boolean {
  return /^[\w.-]+$/.test(key);
}

/**
 * What YAML would take for something other than the words: spaces at either end; a sign that opens something else
 * (`[` a list or a note link, `{` a map, `#` a comment, `@` and a backtick reserved, a quote, `&`, `*`, `!`, `|`, `>`,
 * `%`, `,`), or a `-`, `?` or `:` with a space after it; a colon that would end a key, `a: b`; a ` #` that would start
 * a comment.
 */
const MISREAD = /^\s|\s$|^[[\]{}#&*!|>'"%@`,]|^[-?:](?:\s|$)|:(?:\s|$)|\s#/;

/** Quoted: in double quotes, or in single ones where the words have a double quote or a backslash, which YAML escapes. */
function quoted(value: string): string {
  return /["\\]/.test(value) ? `'${value.replace(/'/g, "''")}'` : `"${value}"`;
}

/** A value as front matter writes it: as it is, or quoted where YAML would misread it. One line. */
export function yamlValue(value: string): string {
  const line = value.replace(/\s*\n\s*/g, ' ');
  return line === '' || MISREAD.test(line) ? quoted(line) : line;
}

/** A list as front matter writes it, across: `[bug, ui]`, `["[[GHO-9]]", "[[GHO-10]]"]`, an item quoted where needed. */
export function yamlList(items: readonly string[]): string {
  const written = items.map((item) => {
    const line = item.replace(/\s*\n\s*/g, ' ').trim();
    return line === '' || MISREAD.test(line) || /[,[\]{}]/.test(line) ? quoted(line) : line;
  });
  return `[${written.join(', ')}]`;
}

/**
 * The body with one property set (core/frontMatter.ts `withFrontMatterValue`): replaced where it is, added last where
 * it is not, front matter made where there is none. A string is written as `yamlValue` writes it, a list across as
 * `yamlList` does, and null - or a list with nothing in it - takes the property off. A key front matter cannot hold
 * leaves the body as it was.
 */
export function withProperty(body: string, key: string, value: string | readonly string[] | null): string {
  if (!isPropertyKey(key)) return body;
  if (value === null) return withFrontMatterValue(body, key, null);
  if (typeof value === 'string') return withFrontMatterValue(body, key, yamlValue(value));
  const items = value.map((item) => item.trim()).filter(Boolean);
  return withFrontMatterValue(body, key, items.length ? yamlList(items) : null);
}

// ---- tickets -------------------------------------------------------------------------------------

/** What a property holds, for a panel to pick it with and a query to compare it by. */
export type PropertyKind = 'text' | 'id' | 'status' | 'person' | 'priority' | 'date' | 'number' | 'link' | 'links' | 'list';

export type TicketKey = 'type' | 'id' | 'status' | 'assignee' | 'priority' | 'due' | 'start' | 'estimate' | 'blocked-by' | 'parent' | 'labels';

export interface TicketProperty {
  key: TicketKey;
  kind: PropertyKind;
  /** How a panel names it. */
  label: string;
}

/** A ticket's properties, in the order a new ticket writes them and a panel shows them. */
export const TICKET_PROPERTIES: readonly TicketProperty[] = [
  { key: 'type', kind: 'text', label: 'Type' },
  { key: 'id', kind: 'id', label: 'ID' },
  { key: 'status', kind: 'status', label: 'Status' },
  { key: 'assignee', kind: 'person', label: 'Assignee' },
  { key: 'priority', kind: 'priority', label: 'Priority' },
  { key: 'due', kind: 'date', label: 'Due' },
  { key: 'start', kind: 'date', label: 'Start' },
  { key: 'estimate', kind: 'number', label: 'Estimate' },
  { key: 'blocked-by', kind: 'links', label: 'Blocked by' },
  { key: 'parent', kind: 'link', label: 'Parent' },
  { key: 'labels', kind: 'list', label: 'Labels' },
];

/** What a property holds by its key, any case: a ticket's own kind, and `text` for any other. */
export function propertyKind(key: string): PropertyKind {
  const clean = key.trim().toLowerCase();
  return TICKET_PROPERTIES.find((property) => property.key === clean)?.kind ?? 'text';
}

/** The `type:` that makes a note a ticket. */
export const TICKET_TYPE = 'ticket';

/** Whether a note is a ticket: its front matter says `type: ticket`, in any case. */
export function isTicket(body: string): boolean {
  return frontMatterValue(body, 'type')?.trim().toLowerCase() === TICKET_TYPE;
}

// ---- statuses ------------------------------------------------------------------------------------

/** The workflow a ticket moves through when its notebook names none: Jira's, with a backlog before it. */
export const DEFAULT_STATUSES: readonly string[] = ['Backlog', 'To do', 'In progress', 'In review', 'Done'];

/** A notebook's own workflow, its `statuses:` list, each once; the default where it names none or there is no notebook. */
export function statusesOf(notebook: string | null | undefined): string[] {
  const seen = new Set<string>();
  const own = propertyList(notebook ? frontMatterValue(notebook, 'statuses') : null).filter((status) => {
    const key = status.toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  return own.length ? own : [...DEFAULT_STATUSES];
}

/** Where a status stands, as Jira groups them: not started, under way, or finished with. */
export type StatusCategory = 'todo' | 'doing' | 'done';

/** A status as its words are compared: lower case, no apostrophes, a space between words. "Won't do" is "wont do". */
const statusWords = (status: string) =>
  status
    .toLowerCase()
    .replace(/['’]/g, '')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();

/** Finished with, whether it was done or is not to be: Jira's Done. */
const DONE = new Set(
  'done closed resolved complete completed finished shipped released merged fixed cancelled canceled duplicate rejected declined abandoned obsolete archived'
    .split(' ')
    .concat(['wont do', 'wont fix']),
);
/** Not started. */
const TODO = new Set(['backlog', 'to do', 'todo', 'open', 'new', 'ready', 'planned', 'triage', 'icebox', 'inbox', 'next', 'later', 'not started']);
/** Under way: these, and any status that starts "In …" ("In progress", "In review", "In QA"). */
const DOING = new Set(['doing', 'review', 'reviewing', 'testing', 'qa', 'started', 'active', 'blocked', 'wip', 'ongoing', 'working', 'building']);

/**
 * Where a status stands, by its words and in any case: "Done", "Closed", "Won't do" and "Cancelled" are done, as is a
 * name a board's Done lane would be (core/itemSyntax.ts `isDoneName`, "All done"); "In progress", "In review" and
 * "Doing" are under way; "Backlog", "To do" and no status at all are not started. A name none of those know is
 * placed by the workflow it is in, where one is given: its first status not started, its last done, any between under
 * way. Otherwise it is not started.
 */
export function statusCategory(status: string | null | undefined, workflow?: readonly string[]): StatusCategory {
  const words = statusWords(status ?? '');
  if (!words) return 'todo';
  if (DONE.has(words) || isDoneName(words)) return 'done';
  if (TODO.has(words)) return 'todo';
  if (DOING.has(words) || words.startsWith('in ')) return 'doing';
  const at = workflow?.findIndex((each) => statusWords(each) === words) ?? -1;
  if (!workflow || at < 0) return 'todo';
  return at === workflow.length - 1 && at > 0 ? 'done' : at === 0 ? 'todo' : 'doing';
}

// ---- issue keys ----------------------------------------------------------------------------------

/** A notebook's key: a capital letter, then two to ten capitals and digits in all, as Jira's project keys are. */
export const PROJECT_KEY = /^[A-Z][A-Z0-9]{1,9}$/;
/** A ticket's id: its notebook's key, a dash, and a number from 1, up to six figures. `GHO-12`. */
export const ISSUE_KEY = /^[A-Z][A-Z0-9]{1,9}-[1-9]\d{0,5}$/;

/** `text` as an issue key, trimmed and upper-cased (`gho-12` is `GHO-12`, as a link matches in any case), or null. */
export function issueKeyOf(text: string | null | undefined): string | null {
  const key = (text ?? '').trim().toUpperCase();
  return ISSUE_KEY.test(key) ? key : null;
}

/** Whether `text` is an issue key, in any case. */
export function isIssueKey(text: string): boolean {
  return issueKeyOf(text) !== null;
}

/** An issue key's number: 12 for `GHO-12`, for sorting `GHO-9` before `GHO-10`; null for what is not a key. */
export function issueNumber(text: string): number | null {
  const key = issueKeyOf(text);
  return key ? Number(key.slice(key.lastIndexOf('-') + 1)) : null;
}

/** A notebook's key, its `key:` upper-cased, `GHO`; null where it has none or one that is not a key (`G`, `12`). */
export function notebookKey(notebook: string): string | null {
  const key = frontMatterValue(notebook, 'key')?.trim().toUpperCase() ?? '';
  return PROJECT_KEY.test(key) ? key : null;
}

/** A ticket's id, its `id:` as an issue key (`issueKeyOf`); null where it has none or it is not one. */
export function ticketIdOf(body: string): string | null {
  return issueKeyOf(frontMatterValue(body, 'id'));
}

/**
 * The id the next ticket under `key` gets: one more than the highest number any of `bodies` gives that key, in an
 * `id:` or anywhere in their words (`[[GHO-12]]`, "see GHO-12"), in any case. Never the lowest free number: a number a
 * ticket had is never given to another while anything still names it, so a link to a deleted ticket never finds a new
 * one. `GHO-1` where nothing names the key yet; null for a key that is not one, or past `KEY-999999`. Give it every
 * note it must not collide with: the notebook's, the Trash's too.
 */
export function nextIssueId(key: string, bodies: readonly string[]): string | null {
  const prefix = key.trim().toUpperCase();
  if (!PROJECT_KEY.test(prefix)) return null;
  const named = new RegExp(String.raw`(?<![A-Za-z0-9_])${prefix}-([1-9]\d{0,5})(?!\d)`, 'gi');
  let highest = 0;
  for (const body of bodies) for (const found of body.matchAll(named)) highest = Math.max(highest, Number(found[1]));
  return highest >= 999_999 ? null : `${prefix}-${highest + 1}`;
}

// ---- a ticket, read --------------------------------------------------------------------------------

/** A ticket's properties, read: what a panel shows, a board lays out and a query sorts. */
export interface Ticket {
  id: string | null;
  /** As written; null where it has none. */
  status: string | null;
  /** Where the status stands (`statusCategory`), in the workflow given. */
  category: StatusCategory;
  /** As written, without an at sign. */
  assignee: string | null;
  priority: PriorityName | null;
  /** A day (core/days.ts), or null where it is none or not one. */
  due: string | null;
  start: string | null;
  /** The number it starts with: 3 for `3`, 2.5 for `2.5 days`. */
  estimate: number | null;
  /** What it waits on (`linkTargets`): `GHO-9`. */
  blockedBy: string[];
  parent: string | null;
  /** Its labels, a `#` before one taken off. */
  labels: string[];
}

/** A ticket's properties, or null where the note is not one. `statuses` is its notebook's workflow (`statusesOf`). */
export function ticketOf(body: string, statuses?: readonly string[]): Ticket | null {
  if (!isTicket(body)) return null;
  const said = (key: string) => {
    const value = frontMatterValue(body, key)?.trim();
    return value ? value : null;
  };
  const day = (key: string) => {
    const value = said(key);
    return value && isIsoDay(value) ? value : null;
  };
  const status = said('status');
  const estimate = Number.parseFloat(said('estimate') ?? '');
  return {
    id: ticketIdOf(body),
    status,
    category: statusCategory(status, statuses),
    assignee: said('assignee')?.replace(/^@+/, '').trim() || null,
    priority: priorityOf(said('priority'))?.name ?? null,
    due: day('due'),
    start: day('start'),
    estimate: Number.isFinite(estimate) ? estimate : null,
    blockedBy: linkTargets(said('blocked-by')),
    parent: linkTargets(said('parent'))[0] ?? null,
    labels: propertyList(said('labels'))
      .map((label) => label.replace(/^#+/, '').trim())
      .filter(Boolean),
  };
}
