import { quietRanges } from './blanks.ts';
import { isIsoDay } from './days.ts';
import { listLead, wordsEnd } from './itemSyntax.ts';
import { tagsIn } from './tags.ts';

/**
 * The fields on a list item's words: when it is due, how much it matters, who it is for, and anything else a query
 * may ask of it (Matt asked what Notion- and Jira-like features custom Markdown could give the app, "like tickets and
 * such", and picked this one first: docs/DESIGN.md §156).
 *
 *   - [ ] Fix the login loop @sam #bug ⏫ 📅 2026-10-03 ^login-loop
 *
 *   `@sam`            a person, the item's assignee
 *   `⏫`              a priority: 🔺 highest, ⏫ high, 🔼 medium, 🔽 low, ⏬ lowest
 *   `📅 2026-10-03`   a date: 📅 due, 🛫 start, ⏳ scheduled, ✅ done, ➕ created, ❌ cancelled
 *   `🔁 every week`   a recurrence, its rule in words up to the next field
 *   `[effort:: 3]`    any other field, by name
 *
 * The signs are Obsidian Tasks' own, so a to-do written here is a task with a due date in Obsidian, and Dataview reads
 * the dates and the `[key:: value]` fields wherever they are in the words: the guiding rule, plain Markdown that
 * still reads in another app (docs/MARKDOWN.md). Tasks also writes 🆔 an id, ⛔ the ids it waits on and 🏁 what to do
 * when it is done; they are read here and kept where they are, so they are never taken for words, though nothing in
 * the app acts on them yet. The `@sam` is ours: nothing else gives a person to a line of Markdown, and an at sign
 * before a name is what every chat and tracker already writes.
 *
 * Where a field goes. Tasks reads its fields from the end of the line, a block link (`^login-loop`) aside and tags
 * among them, and stops at the first thing that is not one. So the writer here keeps them in a run at the end of the
 * words, in the order Tasks writes them (`TASKS_ORDER`), and puts a person or a named field before that run, never
 * inside it, where Tasks would stop and lose the date: the proposal's `📅 2026-10-03 ⏫ @sam #bug` reads here, but
 * Tasks sees only words in it, so the app writes `@sam #bug ⏫ 📅 2026-10-03`. All of it goes before the item's tail -
 * the bookmark, the mark, a counter, the anchor - which is core/itemSyntax.ts's to say, so `wordsEnd` still finds the
 * words' end, a board's anchor still names the item and a Notion mark is still the mark. (An item with a mark or a
 * counter after its fields is words in Tasks' eyes; it still reads.)
 *
 * Where a field is found. Anywhere in a text, as a tag is (core/tags.ts) and as Dataview finds them, but not in quiet
 * words: code, an address, a note link's title, maths, HTML (core/blanks.ts `quietRanges`), or a redaction's
 * `@@…@@`, whose words are hidden and are no one's to list as an assignee. The editor asks its own parser too
 * (editor/syntax.ts `inQuietText`).
 *
 * One grammar, in one module, as core/itemSyntax.ts says why: the chips (editor/), the voice's "due Friday", a board
 * card's words, a title sent to Notion or GitHub and a query's table all read a field here and nowhere else. Pure, so
 * every shape of line is a test (core/taskFields.test.ts) and the MCP server can bundle it.
 */

// ---- priorities ----------------------------------------------------------------------------------

export type PriorityName = 'highest' | 'high' | 'medium' | 'low' | 'lowest';

export interface Priority {
  /** How a ticket's `priority:` and a query's `where:` write it, lower case. */
  name: PriorityName;
  /** How it is shown. */
  label: string;
  /** How an item's words write it (Obsidian Tasks'). */
  emoji: string;
  /** Its place when sorted, the most urgent first: 0 for highest. An item with none sits at `NO_PRIORITY_RANK`. */
  rank: number;
}

/** The priorities, the most urgent first: Tasks' five and Jira's, the same names. */
export const PRIORITIES: readonly Priority[] = [
  { name: 'highest', label: 'Highest', emoji: '🔺', rank: 0 },
  { name: 'high', label: 'High', emoji: '⏫', rank: 1 },
  { name: 'medium', label: 'Medium', emoji: '🔼', rank: 2 },
  { name: 'low', label: 'Low', emoji: '🔽', rank: 4 },
  { name: 'lowest', label: 'Lowest', emoji: '⏬', rank: 5 },
];

/**
 * Where an item with no priority sorts: between medium and low, as Tasks sorts it, since an item nobody has ranked is
 * an ordinary one, not the least of them.
 */
export const NO_PRIORITY_RANK = 3;

/** The emoji's variation selector, which a keyboard may put after any of them. */
const VS = '\u{FE0F}';

/**
 * A priority from what was said or written: its name in any case ("High", "highest"), or its emoji, with or without
 * the variation selector. Null for anything else, "normal" and "none" included: no priority is no field.
 */
export function priorityOf(said: string | null | undefined): Priority | null {
  const clean = (said ?? '').trim().replace(VS, '').toLowerCase();
  return PRIORITIES.find((p) => p.name === clean || p.emoji === clean) ?? null;
}

/** A priority's place when sorted, the most urgent first; an item with none between medium and low. */
export function priorityRank(name: PriorityName | null | undefined): number {
  return PRIORITIES.find((p) => p.name === name)?.rank ?? NO_PRIORITY_RANK;
}

// ---- the fields' names -----------------------------------------------------------------------------

/** The dates an item may carry. */
export type DateKey = 'created' | 'start' | 'scheduled' | 'due' | 'cancelled' | 'done';
/** Every field Obsidian Tasks writes as an emoji. */
export type TasksKey = 'id' | 'dependsOn' | 'priority' | 'recurs' | 'onCompletion' | DateKey;
/** A field the writer can set: one of Tasks', or any other name, which is written `[name:: value]`. */
export type FieldKey = TasksKey | (string & {});

/** The dates, in the order Tasks writes them. */
export const DATE_KEYS: readonly DateKey[] = ['created', 'start', 'scheduled', 'due', 'cancelled', 'done'];

/** Tasks' fields in the order Tasks writes them after an item's words: the order the writer keeps. */
export const TASKS_ORDER: readonly TasksKey[] = ['id', 'dependsOn', 'priority', 'recurs', 'onCompletion', 'created', 'start', 'scheduled', 'due', 'cancelled', 'done'];

/** Each emoji field's sign as the app writes it; a priority's is its own (`PRIORITIES`). */
export const FIELD_EMOJI: Readonly<Record<Exclude<TasksKey, 'priority'>, string>> = {
  id: '🆔',
  dependsOn: '⛔',
  recurs: '🔁',
  onCompletion: '🏁',
  created: '➕',
  start: '🛫',
  scheduled: '⏳',
  due: '📅',
  cancelled: '❌',
  done: '✅',
};

/** The other signs Tasks reads for a field, read here too and never written. */
const ALSO_READ: Partial<Record<TasksKey, readonly string[]>> = { scheduled: ['⌛'], due: ['📆', '🗓'] };

export function isDateKey(key: string): key is DateKey {
  return (DATE_KEYS as readonly string[]).includes(key);
}

export function isTasksKey(key: string): key is TasksKey {
  return (TASKS_ORDER as readonly string[]).includes(key);
}

/**
 * A named field's key as it is compared and kept: trimmed, lower case, each run of spaces a dash, as Dataview reads
 * one, so `[Due Date:: …]` and `[due-date:: …]` are one field.
 */
export function fieldKey(key: string): string {
  return key.trim().toLowerCase().replace(/\s+/g, '-');
}

// ---- people ----------------------------------------------------------------------------------------

/**
 * A person as written: an at sign after the line's start, a space or an opening bracket, then a letter, then letters,
 * digits, `_`, `.` or `-`. So `sam@example.com` is an address, `@@redacted@@` is a redaction, `@ 2pm` and `@2pm` are a
 * time, and a lone `@` is a word. A trailing `.` or `-` is punctuation: "Ask @sam." is Sam.
 */
const PERSON = /(^|[\s([{])@(\p{L}[\p{L}\p{N}_.-]*)/gu;

/**
 * A name as an item writes it after its at sign, or null where nothing of it can be: "Sam" is `Sam`, "Sam Ortiz" is
 * `Sam-Ortiz`, "@sam" is `sam`. What a spoken "for Sam" and a person picker write (editor/, voice).
 */
export function personHandle(name: string): string | null {
  const handle = name
    .trim()
    .replace(/^@+/, '')
    .replace(/\s+/g, '-')
    .replace(/[^\p{L}\p{N}_.-]/gu, '')
    .replace(/^[^\p{L}]+/u, '')
    .replace(/[.-]+$/, '');
  return handle ? handle : null;
}

/**
 * A person as two mentions of them are compared: the handle, lower case. So `@sam`, "Sam" and a ticket's
 * `assignee: Sam` are one person, and so are `@sam-ortiz` and "Sam Ortiz".
 */
export function personKey(name: string): string {
  return (personHandle(name) ?? name.trim()).toLowerCase();
}

/** Whether two mentions name one person. */
export function samePerson(one: string, two: string): boolean {
  const key = personKey(one);
  return key !== '' && key === personKey(two);
}

// ---- reading -------------------------------------------------------------------------------------

/**
 * What kind of field a span is: a date, a priority, a recurrence, a person, a named `[key:: value]` field, or one of
 * Tasks' others (🆔, ⛔, 🏁), read and kept.
 */
export type FieldKind = 'date' | 'priority' | 'recurs' | 'person' | 'inline' | 'tasks';

/** One field in a text, as tagsIn gives a tag (core/tags.ts): where it is, and what it says. */
export interface FieldSpan {
  kind: FieldKind;
  /** The sign or the bracket that opens it, counted from the offset given. */
  from: number;
  /** The end of its value. */
  to: number;
  /**
   * What it is: a `DateKey` for a date; `priority`, `recurs`, `assignee`; `id`, `dependsOn` or `onCompletion` for
   * Tasks' others; a named field's key as `fieldKey` keeps it.
   */
  key: string;
  /**
   * What it says: the day (`2026-10-03`, as written), the priority's name, the rule's words, the person's name
   * without the at sign (as written), or the value as written, trimmed.
   */
  value: string;
}

/** One grammar of fields: a pattern, and what a match of it is. */
interface Reader {
  pattern: RegExp;
  read: (found: RegExpExecArray) => Omit<FieldSpan, 'from' | 'to'> & { at: number; length: number };
}

/** Any of the signs given, and the variation selector after it, as a pattern: each sign its own alternative. */
const signs = (...all: readonly string[]) => `(?:${all.join('|')})${VS}?`;
const signOf = (key: Exclude<TasksKey, 'priority'>) => signs(FIELD_EMOJI[key], ...(ALSO_READ[key] ?? []));
/** The spaces Tasks allows between a sign and its value: any, on the line. */
const GAP = '[ \\t]*';

/** A recurrence's rule: words, numbers, commas and `!`, as Tasks reads one, to the next thing that is not. */
const RULE = String.raw`[\p{L}\p{N}][\p{L}\p{N}, !]*`;
/** Tasks' ids: letters, digits, `_` and `-`. */
const TASK_ID = '[A-Za-z0-9_-]+';
/**
 * A named field, `[key:: value]`: the key a letter or a digit and then words, the value any words and note links. Not
 * a link's words (`[a:: b](…)`), and not inside a note link or after a picture's `!`.
 */
const INLINE = String.raw`(?<![[!])\[([\p{L}\p{N}][\p{L}\p{N} _./-]*?)[ \t]*::[ \t]*((?:\[\[[^\]\n]*\]\]|[^[\]\n])*?)[ \t]*\](?!\()`;

const READERS: readonly Reader[] = [
  ...DATE_KEYS.map(
    (key): Reader => ({
      pattern: new RegExp(`${signOf(key)}${GAP}(\\d{4}-\\d{2}-\\d{2})(?!\\d)`, 'gu'),
      read: (found) => ({ kind: 'date', key, value: found[1] ?? '', at: found.index, length: found[0].length }),
    }),
  ),
  {
    pattern: new RegExp(`(${PRIORITIES.map((p) => p.emoji).join('|')})${VS}?`, 'gu'),
    read: (found) => ({ kind: 'priority', key: 'priority', value: priorityOf(found[1])?.name ?? '', at: found.index, length: found[0].length }),
  },
  {
    pattern: new RegExp(`${signOf('recurs')}${GAP}(${RULE})`, 'gu'),
    read: (found) => {
      // The rule ends at its last word: the spaces and commas after it are the gap before what comes next.
      const rule = (found[1] ?? '').replace(/[\s,]+$/, '');
      const length = found[0].length - ((found[1] ?? '').length - rule.length);
      return { kind: 'recurs', key: 'recurs', value: rule, at: found.index, length };
    },
  },
  {
    pattern: new RegExp(`${signOf('id')}${GAP}(${TASK_ID})`, 'gu'),
    read: (found) => ({ kind: 'tasks', key: 'id', value: found[1] ?? '', at: found.index, length: found[0].length }),
  },
  {
    pattern: new RegExp(`${signOf('dependsOn')}${GAP}(${TASK_ID}(?:[ \\t]*,[ \\t]*${TASK_ID})*)`, 'gu'),
    read: (found) => ({ kind: 'tasks', key: 'dependsOn', value: found[1] ?? '', at: found.index, length: found[0].length }),
  },
  {
    pattern: new RegExp(`${signOf('onCompletion')}${GAP}([A-Za-z]+)`, 'gu'),
    read: (found) => ({ kind: 'tasks', key: 'onCompletion', value: found[1] ?? '', at: found.index, length: found[0].length }),
  },
  {
    pattern: PERSON,
    read: (found) => {
      const lead = (found[1] ?? '').length;
      const name = (found[2] ?? '').replace(/[.-]+$/, '');
      return { kind: 'person', key: 'assignee', value: name, at: found.index + lead, length: name.length + 1 };
    },
  },
  {
    pattern: new RegExp(INLINE, 'gu'),
    read: (found) => ({ kind: 'inline', key: fieldKey(found[1] ?? ''), value: (found[2] ?? '').trim(), at: found.index, length: found[0].length }),
  },
];

/** A redaction, `@@…@@`: its words are hidden, so nothing in them is a field. */
const REDACTION = /@@[^\s@](?:[^\n@]|@(?!@))*?@@/g;

/**
 * Every field in `text`, in order, counting positions from `offset`: anywhere in it but quiet words and a redaction.
 * Where two would overlap - a person in a named field's value, `[owner:: @sam]` - the one that starts first is the
 * field, and the other is its words.
 */
export function fieldsIn(text: string, offset = 0): FieldSpan[] {
  if (!text) return [];
  const quiet = quietRanges(text);
  for (const found of text.matchAll(REDACTION)) quiet.push({ from: found.index, to: found.index + found[0].length });
  const all: FieldSpan[] = [];
  for (const reader of READERS) {
    const pattern = new RegExp(reader.pattern.source, reader.pattern.flags);
    for (let found = pattern.exec(text); found; found = pattern.exec(text)) {
      // A name run on into an at sign (`@sam@mastodon.social`) is an address, not a person.
      if (reader.pattern === PERSON && text[found.index + found[0].length] === '@') continue;
      const { at, length, ...field } = reader.read(found);
      if (quiet.some((q) => at >= q.from && at < q.to)) continue;
      all.push({ ...field, from: at, to: at + length });
    }
  }
  all.sort((a, b) => a.from - b.from || b.to - a.to);
  const kept: FieldSpan[] = [];
  for (const span of all) if (!kept.length || span.from >= kept[kept.length - 1]!.to) kept.push(span);
  return kept.map((span) => ({ ...span, from: span.from + offset, to: span.to + offset }));
}

/** What an item's fields say, read together. */
export interface TaskFields {
  due: string | null;
  start: string | null;
  scheduled: string | null;
  done: string | null;
  created: string | null;
  cancelled: string | null;
  /** The recurrence's rule in words, "every week on Monday"; kept, not yet acted on. */
  recurs: string | null;
  priority: PriorityName | null;
  /** The people, as written without their at signs, each once, in order. */
  assignees: string[];
  /** Tasks' own id (🆔), the ids it waits on (⛔) and what to do when it is done (🏁): read and kept, not yet acted on. */
  id: string | null;
  dependsOn: string[];
  onCompletion: string | null;
  /** Every named field, by its key as `fieldKey` keeps it, the first of a repeated one winning. */
  fields: Record<string, string>;
}

/**
 * Dataview's own names for a task's dates, and a priority by name: what an item written for Dataview says in
 * `[due:: 2026-10-03]`. Read as the emoji's where the item has no emoji for it, as Dataview reads them both.
 */
const DATAVIEW_NAMES: Readonly<Record<string, DateKey | 'priority'>> = {
  due: 'due',
  start: 'start',
  scheduled: 'scheduled',
  created: 'created',
  completion: 'done',
  cancelled: 'cancelled',
  priority: 'priority',
};

/**
 * What `text`'s fields say: an item's line or its words, as `fieldsIn` finds them. The first of a repeated field wins,
 * as a reader of the line in another app would take it. A date is as written; a named `[due:: …]` stands for the
 * date where there is no `📅`, when it is a day.
 */
export function fieldsOf(text: string): TaskFields {
  const out: TaskFields = {
    due: null,
    start: null,
    scheduled: null,
    done: null,
    created: null,
    cancelled: null,
    recurs: null,
    priority: null,
    assignees: [],
    id: null,
    dependsOn: [],
    onCompletion: null,
    fields: Object.create(null) as Record<string, string>,
  };
  const people = new Set<string>();
  for (const span of fieldsIn(text)) {
    if (span.kind === 'date' && isDateKey(span.key)) out[span.key] ??= span.value;
    else if (span.kind === 'priority') out.priority ??= priorityOf(span.value)?.name ?? null;
    else if (span.kind === 'recurs') out.recurs ??= span.value;
    else if (span.kind === 'person' && !people.has(personKey(span.value))) {
      people.add(personKey(span.value));
      out.assignees.push(span.value);
    } else if (span.kind === 'tasks' && span.key === 'id') out.id ??= span.value;
    else if (span.kind === 'tasks' && span.key === 'dependsOn') {
      for (const id of span.value.split(',').map((each) => each.trim())) if (id && !out.dependsOn.includes(id)) out.dependsOn.push(id);
    }
    else if (span.kind === 'tasks' && span.key === 'onCompletion') out.onCompletion ??= span.value;
    else if (span.kind === 'inline' && !Object.hasOwn(out.fields, span.key)) out.fields[span.key] = span.value;
  }
  for (const [name, key] of Object.entries(DATAVIEW_NAMES)) {
    const said = Object.hasOwn(out.fields, name) ? out.fields[name]! : null;
    if (said === null) continue;
    if (key === 'priority') out.priority ??= priorityOf(said)?.name ?? null;
    else if (isIsoDay(said)) out[key] ??= said;
  }
  return out;
}

/**
 * `text` with every field taken out, each with the space before it, and the spaces tidied: what an item says, for a
 * title sent to Notion or GitHub and a board card's words. "Fix the login loop @sam #bug ⏫ 📅 2026-10-03" is "Fix the
 * login loop #bug": a tag is words, and what a field says is the field's to show. Give it the words (core/itemSyntax.ts
 * `lineWords`, core/boards/items.ts `itemWords`), not the line.
 */
export function withoutFields(text: string): string {
  let out = text;
  for (const span of fieldsIn(text).reverse()) out = removed(out, span, 0);
  return out.replace(/[ \t]{2,}/g, ' ').trim();
}

// ---- writing -------------------------------------------------------------------------------------

/** Where a line's words are, as core/itemSyntax.ts reads them: after the lead, before the tail. */
function wordsOf(line: string): { from: number; to: number } {
  const from = listLead(line)?.wordsAt ?? 0;
  return { from, to: Math.max(from, wordsEnd(line)) };
}

/** Whether a span is one of Tasks' emoji fields, which keep to the run at the end of the words. */
const isEmojiField = (span: FieldSpan) => span.kind !== 'person' && span.kind !== 'inline';

/**
 * The run of Tasks' fields at the end of the words, tags among them: where it starts, and its fields in order. A
 * line with no field at the end of its words has none, and starts where its words end.
 */
function tasksRun(line: string, spans: readonly FieldSpan[], words: { from: number; to: number }): { at: number; fields: FieldSpan[] } {
  const tags = tagsIn(line).filter((tag) => tag.from >= words.from && tag.to <= words.to);
  const fields: FieldSpan[] = [];
  let at = words.to;
  let cursor = words.to;
  for (;;) {
    while (cursor > words.from && /\s/.test(line[cursor - 1] ?? '')) cursor -= 1;
    const field = spans.find((span) => span.to === cursor && isEmojiField(span));
    if (field) {
      fields.unshift(field);
      at = field.from;
      cursor = field.from;
      continue;
    }
    const tag = tags.find((each) => each.to === cursor);
    if (!tag) break;
    cursor = tag.from;
  }
  return { at, fields };
}

/** `line` with `text` put in at `at`, a space either side where the words there would otherwise touch it. */
function inserted(line: string, at: number, text: string): string {
  const before = line.slice(0, at);
  const after = line.slice(at);
  const left = before && !/\s$/.test(before) ? ' ' : '';
  const right = after && !/^\s/.test(after) ? ' ' : '';
  return `${before}${left}${text}${right}${after}`;
}

/**
 * `line` without one field and the space before it; a field that opens the words takes the space after it instead,
 * so `- [ ] 📅 2026-10-03 Fix` is `- [ ] Fix` and the box keeps its space.
 */
function removed(line: string, span: FieldSpan, wordsFrom: number): string {
  let from = span.from;
  let to = span.to;
  while (from > wordsFrom && /[ \t]/.test(line[from - 1] ?? '')) from -= 1;
  if (from === wordsFrom) {
    from = span.from;
    while (to < line.length && /[ \t]/.test(line[to] ?? '')) to += 1;
  }
  return `${line.slice(0, from)}${line.slice(to)}`;
}

/** A named field's key as it may be written: a letter or digit, then letters, digits, spaces, `_`, `.`, `/` or `-`. */
const INLINE_KEY = /^[\p{L}\p{N}][\p{L}\p{N} _./-]*$/u;
/** A named field's value as it may be written: one line, and no bracket but a note link's. */
const INLINE_VALUE = /^(?:\[\[[^\]\n]*\]\]|[^[\]\n])*$/;

/** A Tasks field as the app writes it, or null for a value it cannot hold. */
function emojiField(key: TasksKey, value: string): string | null {
  const clean = value.replace(/\s+/g, ' ').trim();
  if (key === 'priority') return priorityOf(clean)?.emoji ?? null;
  const sign = FIELD_EMOJI[key];
  if (isDateKey(key)) return isIsoDay(clean) ? `${sign} ${clean}` : null;
  if (key === 'recurs') return new RegExp(`^${RULE}$`, 'u').test(clean) ? `${sign} ${clean}` : null;
  if (key === 'dependsOn') {
    const ids = clean.split(',').map((id) => id.trim());
    return ids.every((id) => new RegExp(`^${TASK_ID}$`).test(id)) ? `${sign} ${ids.join(',')}` : null;
  }
  if (key === 'onCompletion') return /^[A-Za-z]+$/.test(clean) ? `${sign} ${clean}` : null;
  return new RegExp(`^${TASK_ID}$`).test(clean) ? `${sign} ${clean}` : null;
}

/** A named field as written: `[key:: value]`, or null for a key or a value it cannot hold. */
function inlineField(key: string, value: string): string | null {
  const name = key.trim();
  const clean = value.replace(/\s+/g, ' ').trim();
  return INLINE_KEY.test(name) && INLINE_VALUE.test(clean) ? `[${name}:: ${clean}]` : null;
}

/**
 * The line with one field set, replaced or taken off: `value` null takes it off. A date is a day (`2026-10-03`, see
 * core/days.ts), a priority a name or its emoji, `recurs` its rule in words; any name that is not one of Tasks' is
 * written `[name:: value]`. A field the item has is changed where it is, in the form it is written in (a Dataview
 * `[due:: …]` stays one), and a second of the same is taken off. A new one goes at the end of the words, before the
 * tail: one of Tasks' into the run of them in Tasks' order, a named one before that run. A value the field cannot hold
 * - a date that is not a day, a priority that is not one - leaves the line as it was. People are `withAssignee`'s.
 */
export function withField(line: string, key: FieldKey, value: string | null): string {
  const tasks = isTasksKey(key) ? key : null;
  const named = tasks ? null : fieldKey(key);
  if (named !== null && !INLINE_KEY.test(key.trim())) return line;
  const words = wordsOf(line);
  const spans = fieldsIn(line).filter((span) => span.from >= words.from && span.to <= words.to);
  const mine = spans.filter((span) =>
    tasks ? (isEmojiField(span) && span.key === tasks) || (span.kind === 'inline' && DATAVIEW_NAMES[span.key] === tasks) : span.kind === 'inline' && span.key === named,
  );
  if (value === null) return mine.reduceRight((out, span) => removed(out, span, words.from), line);
  const first = mine[0];
  if (first) {
    let text: string | null;
    if (first.kind === 'inline') {
      // Kept in the form it is written in, its key as the person wrote it.
      const writtenKey = /^\[([^:\]]*?)[ \t]*::/.exec(line.slice(first.from, first.to))?.[1] ?? key;
      const said = tasks === 'priority' ? (priorityOf(value)?.name ?? null) : tasks && isDateKey(tasks) && !isIsoDay(value.trim()) ? null : value;
      text = said === null ? null : inlineField(writtenKey, said);
    } else {
      text = emojiField(first.key as TasksKey, value);
    }
    if (text === null) return line;
    const rest = mine.slice(1).reduceRight((out, span) => removed(out, span, words.from), line);
    return `${rest.slice(0, first.from)}${text}${rest.slice(first.to)}`;
  }
  const text = tasks ? emojiField(tasks, value) : inlineField(key, value);
  if (text === null) return line;
  const run = tasksRun(line, spans, words);
  if (!tasks) return inserted(line, run.fields.length ? run.at : words.to, text);
  const order = TASKS_ORDER.indexOf(tasks);
  const later = run.fields.find((field) => TASKS_ORDER.indexOf(field.key as TasksKey) > order);
  if (later) return inserted(line, later.from, text);
  const last = run.fields[run.fields.length - 1];
  return inserted(line, last ? last.to : words.to, text);
}

/**
 * The line with a person added to its people (`on`), or taken off them: `@sam` before the run of Tasks' fields, so
 * Tasks still reads its dates, after any person already there. A person already on it is not added again, and one
 * not on it is not taken off; a name with nothing a handle can be made of (`personHandle`) leaves the line alone.
 */
export function withAssignee(line: string, name: string, on = true): string {
  const handle = personHandle(name);
  if (!handle) return line;
  const words = wordsOf(line);
  const spans = fieldsIn(line).filter((span) => span.from >= words.from && span.to <= words.to);
  const theirs = spans.filter((span) => span.kind === 'person' && samePerson(span.value, handle));
  if (!on) return theirs.reduceRight((out, span) => removed(out, span, words.from), line);
  if (theirs.length) return line;
  const run = tasksRun(line, spans, words);
  return inserted(line, run.fields.length ? run.at : words.to, `@${handle}`);
}
