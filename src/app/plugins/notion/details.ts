import { markDetailsChanged, type MarkAction, type MarkDetails, type MarkDetailsProvider, type Stage } from '../../core/markDetails.ts';
import { shortUrl } from '../../core/shortUrl.ts';
import { detailsCache } from '../detailsCache.ts';
import { notionAvailable, notionRequest } from './client.ts';
import { host } from './manifest.ts';

/**
 * A linked item's task, read back from Notion: its status, its priority, when
 * it's due, for the pill on the item and the card a tap opens
 * (core/markDetails.ts).
 *
 * - **What a task is made of** is read from the page, not assumed: any board
 *   Glyph was shared works. The status is the page's status property (or a
 *   "Done" checkbox), and its stage comes from the board's own status groups
 *   (To-do, In progress, Complete), read once per board, so "Shipped" or
 *   "Blocked" land where the board put them. The pill's facts are a
 *   priority-like select and a due-like date. The card lists every property
 *   with a value.
 * - **Reads are paced**, because Notion allows about three requests a second,
 *   and an answer stays fresh long enough that scrolling a long list doesn't
 *   re-read it. The note coming back to the front reads what it shows again
 *   (editor/markReads.ts), which is how a change made in Notion shows up.
 * - **The last answers are kept** (`glyph-notion-tasks`), so a note opened
 *   offline or before the read finishes shows the status it last had, with
 *   when it was read on the card.
 *
 * The pacing, the freshness and the keeping are the plugins' shared cache
 * (plugins/detailsCache.ts, which has the numbers), keyed by the page's id;
 * what is Notion's is how a page is read and what can be written back to it.
 */

// ---- reading a page (pure) ---------------------------------------------------------------------

/** The page id in a Notion address: the 32 hex digits at the end of its path, dashed or not. */
export function pageIdOf(url: string): string | null {
  let path: string;
  try {
    path = new URL(url).pathname;
  } catch {
    return null;
  }
  const match = /([0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12})\/?$/i.exec(path);
  return match ? (match[1] ?? '').replace(/-/g, '').toLowerCase() : null;
}

interface RichText {
  plain_text?: string;
}

interface PropertyValue {
  type: string;
  title?: RichText[];
  rich_text?: RichText[];
  status?: { id?: string; name?: string } | null;
  select?: { name?: string } | null;
  multi_select?: { name?: string }[];
  date?: { start?: string; end?: string | null } | null;
  people?: { name?: string }[];
  checkbox?: boolean;
  number?: number | null;
  url?: string | null;
  email?: string | null;
  phone_number?: string | null;
}

export interface NotionPage {
  id: string;
  url?: string;
  last_edited_time?: string;
  archived?: boolean;
  in_trash?: boolean;
  parent?: { type?: string; database_id?: string };
  properties?: Record<string, PropertyValue>;
}

/** A board's status groups: which stage each status option is in, by option id and by name. */
export type StageMap = Record<string, Stage>;

/** A board's status options by stage, in the board's order: what "Mark done" and "Reopen" set. */
export type StageOptions = Record<Stage, string[]>;

interface DatabaseSchema {
  properties?: Record<string, { type: string; status?: { options?: { id: string; name: string }[]; groups?: { name: string; option_ids?: string[] }[] } }>;
}

/** Each stage's status options, in the board's order. */
function stageOptionsOf(schema: DatabaseSchema): StageOptions {
  const options: StageOptions = { todo: [], doing: [], done: [] };
  for (const property of Object.values(schema.properties ?? {})) {
    if (property.type !== 'status' || !property.status) continue;
    const names = new Map((property.status.options ?? []).map((option) => [option.id, option.name]));
    for (const group of property.status.groups ?? []) {
      const stage = stageOfGroup(group.name);
      for (const id of group.option_ids ?? []) {
        const name = names.get(id);
        if (name) options[stage].push(name);
      }
    }
  }
  return options;
}

/**
 * What a page's properties are called, for changing them: its title, and what
 * says it's done (a status or a Done checkbox).
 */
function writablesOf(page: NotionPage): { title: string | null; done: { name: string; kind: 'status' | 'checkbox' } | null } {
  const entries = Object.entries(page.properties ?? {});
  const title = entries.find(([, value]) => value.type === 'title')?.[0] ?? null;
  const status = entries.find(([, value]) => value.type === 'status')?.[0];
  const checkbox = entries.find(([name, value]) => value.type === 'checkbox' && /^(done|complete|completed)$/i.test(name.trim()))?.[0];
  return { title, done: status ? { name: status, kind: 'status' } : checkbox ? { name: checkbox, kind: 'checkbox' } : null };
}

/** Where a Notion address points, for links that aren't marks: notion.so, notion.site or app.notion.com, with a page id. */
function isNotionPageUrl(url: string): boolean {
  try {
    const host = new URL(url).hostname.toLowerCase();
    const notion = host === 'notion.so' || host.endsWith('.notion.so') || host.endsWith('.notion.site') || host === 'app.notion.com';
    return notion && pageIdOf(url) !== null;
  } catch {
    return false;
  }
}

/** The stages of a board's status options, from its groups. */
export function stagesOf(schema: DatabaseSchema): StageMap {
  const stages: StageMap = {};
  for (const property of Object.values(schema.properties ?? {})) {
    if (property.type !== 'status' || !property.status) continue;
    const names = new Map((property.status.options ?? []).map((option) => [option.id, option.name]));
    for (const group of property.status.groups ?? []) {
      const stage = stageOfGroup(group.name);
      for (const id of group.option_ids ?? []) {
        stages[id] = stage;
        const name = names.get(id);
        if (name) stages[name.toLowerCase()] = stage;
      }
    }
  }
  return stages;
}

function stageOfGroup(name: string): Stage {
  const lower = name.toLowerCase();
  if (lower.includes('complete') || lower.includes('done')) return 'done';
  if (lower.includes('progress')) return 'doing';
  return 'todo';
}

/** A stage from a status's name alone, for a board whose groups couldn't be read. */
export function guessStage(name: string): Stage {
  const lower = name.toLowerCase().trim();
  if (/^(not started|to ?do|backlog|new|open|todo|up next|planned|triage)/.test(lower)) return 'todo';
  if (/(done|complete|shipped|closed|resolved|finished|released|merged)/.test(lower)) return 'done';
  return 'doing';
}

const text = (rich: RichText[] | undefined) => (rich ?? []).map((r) => r.plain_text ?? '').join('').trim();

function dayText(iso: string, now: number): string {
  const dateOnly = /^\d{4}-\d{2}-\d{2}$/.test(iso);
  const when = new Date(dateOnly ? `${iso}T12:00:00` : iso);
  if (Number.isNaN(when.getTime())) return iso;
  const sameYear = when.getFullYear() === new Date(now).getFullYear();
  const day = when.toLocaleDateString('en-US', { month: 'short', day: 'numeric', ...(sameYear ? {} : { year: 'numeric' }) });
  return dateOnly ? day : `${day}, ${when.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}`;
}

/** A property's value as a line of words, or null when it has none worth showing. */
function valueText(value: PropertyValue, now: number): string | null {
  switch (value.type) {
    case 'rich_text': {
      const words = text(value.rich_text);
      return words ? (words.length > 140 ? `${words.slice(0, 139)}…` : words) : null;
    }
    case 'status':
      return value.status?.name ?? null;
    case 'select':
      return value.select?.name ?? null;
    case 'multi_select': {
      const names = (value.multi_select ?? []).map((option) => option.name).filter(Boolean);
      return names.length ? names.join(', ') : null;
    }
    case 'date': {
      if (!value.date?.start) return null;
      const start = dayText(value.date.start, now);
      return value.date.end ? `${start} – ${dayText(value.date.end, now)}` : start;
    }
    case 'people': {
      const names = (value.people ?? []).map((person) => person.name).filter(Boolean);
      return names.length ? names.join(', ') : null;
    }
    case 'checkbox':
      return value.checkbox ? 'Yes' : null;
    case 'number':
      return typeof value.number === 'number' ? String(value.number) : null;
    case 'url':
      return value.url ? shortUrl(value.url) : null;
    case 'email':
      return value.email ?? null;
    case 'phone_number':
      return value.phone_number ?? null;
    default:
      // Formulas, rollups, relations, files, and the times Notion sets itself: noise on a small card.
      return null;
  }
}

/** A page as details: its title, its status and stage, the pill's facts and the card's fields. */
export function detailsOf(page: NotionPage, stages: StageMap | null, now = Date.now()): MarkDetails {
  const entries = Object.entries(page.properties ?? {});
  const title = text(entries.find(([, value]) => value.type === 'title')?.[1].title) || 'Untitled';

  let status: MarkDetails['status'] = null;
  const statusProperty = entries.find(([, value]) => value.type === 'status' && value.status?.name);
  if (statusProperty) {
    const chosen = statusProperty[1].status ?? {};
    const label = chosen.name ?? '';
    const stage = (chosen.id && stages?.[chosen.id]) || stages?.[label.toLowerCase()] || guessStage(label);
    status = { label, stage };
  } else {
    const done = entries.find(([name, value]) => value.type === 'checkbox' && /^(done|complete|completed)$/i.test(name.trim()));
    if (done) status = done[1].checkbox ? { label: 'Done', stage: 'done' } : { label: 'Not done', stage: 'todo' };
  }

  const brief: string[] = [];
  const priority = entries.find(([name, value]) => /prio/i.test(name) && (value.type === 'select' || value.type === 'status'));
  const priorityText = priority ? valueText(priority[1], now) : null;
  if (priorityText) brief.push(priorityText);
  const due = entries.find(([name, value]) => value.type === 'date' && /due|deadline|date/i.test(name) && value.date?.start);
  if (due?.[1].date?.start) {
    const start = due[1].date.start;
    const late = status?.stage !== 'done' && new Date(/^\d{4}-\d{2}-\d{2}$/.test(start) ? `${start}T23:59:59` : start).getTime() < now;
    brief.push(`${late ? 'Overdue' : 'Due'} ${dayText(start, now).replace(/, .*$/, '')}`);
  }

  const fields = entries
    .filter(([, value]) => value.type !== 'title')
    .map(([label, value]) => ({ label, value: valueText(value, now) }))
    .filter((field): field is { label: string; value: string } => field.value !== null);

  const edited = page.last_edited_time ? Date.parse(page.last_edited_time) : NaN;
  return {
    url: page.url ?? '',
    title,
    status,
    brief: brief.slice(0, 2),
    fields,
    editedAt: Number.isNaN(edited) ? null : edited,
    readAt: now,
    gone: Boolean(page.archived || page.in_trash) || undefined,
  };
}

// ---- the provider -----------------------------------------------------------------------------

/** Each board's statuses, by the database's id: read once, and null for a board whose schema would not read. */
const boards = new Map<string, { stages: StageMap; options: StageOptions } | null>();
/** Per page: its property names for writing back, and its board. Kept in memory; a read fills it. */
const writables = new Map<string, ReturnType<typeof writablesOf> & { board: string | null }>();

/**
 * A board's statuses by stage and by option, read once per database. Not client.ts's `boardFor`, which answers the
 * board a note sends its list to.
 */
async function boardStatusesOf(databaseId: string | undefined | null): Promise<{ stages: StageMap; options: StageOptions } | null> {
  if (!databaseId) return null;
  if (boards.has(databaseId)) return boards.get(databaseId) ?? null;
  const schema = await notionRequest<DatabaseSchema>('GET', `databases/${databaseId}`).catch(() => null);
  const board = schema ? { stages: stagesOf(schema), options: stageOptionsOf(schema) } : null;
  boards.set(databaseId, board);
  return board;
}

/** Reads a task's page, and its board's statuses the first time the board is met; keeps what can be written back. */
async function read(id: string, url: string): Promise<MarkDetails> {
  const page = await notionRequest<NotionPage>('GET', `pages/${id}`);
  const databaseId = page.parent?.type === 'database_id' ? (page.parent.database_id ?? null) : null;
  const board = await boardStatusesOf(databaseId);
  writables.set(id, { ...writablesOf(page), board: databaseId });
  return { ...detailsOf(page, board?.stages ?? null), url: page.url ?? url };
}

// Nothing is asked of Notion until the binary is known to reach it: the answer lands a moment after the page loads.
let usable = false;
void notionAvailable().then((yes) => {
  usable = yes;
  if (yes) markDetailsChanged();
});

const tasks = detailsCache({ host, storageKey: 'glyph-notion-tasks', read, ready: () => usable });

export const notionDetails: MarkDetailsProvider = {
  peek(url) {
    const id = pageIdOf(url);
    return id ? tasks.peek(id) : null;
  },
  want(url, fresh = false) {
    const id = pageIdOf(url);
    if (id) tasks.want(id, url, fresh);
  },
  open: (url) => host.openUrl(url),
  reads: isNotionPageUrl,
  actions(url, words) {
    const id = pageIdOf(url);
    const details = id ? tasks.details(id) : undefined;
    const write = id ? writables.get(id) : undefined;
    if (!id || !details || !write || details.gone) return [];
    const actions: MarkAction[] = [];
    if (write.done) {
      const done = details.status?.stage === 'done';
      actions.push({
        id: done ? 'reopen' : 'done',
        label: done ? 'Reopen in Notion' : 'Mark done in Notion',
        busyLabel: done ? 'Reopening…' : 'Marking done…',
        icon: done ? 'reopen' : 'done',
        run: () => setDone(id, url, !done),
      });
    }
    const said = words.trim();
    if (write.title && said && said !== details.title.trim()) {
      actions.push({
        id: 'rename',
        label: 'Use these words as its title',
        busyLabel: 'Renaming…',
        icon: 'rename',
        run: async () => {
          await notionRequest('PATCH', `pages/${id}`, { properties: { [write.title!]: { title: [{ type: 'text', text: { content: said.slice(0, 2000) } }] } } });
          await tasks.reread(id, url);
          return 'Renamed in Notion.';
        },
      });
    }
    return actions;
  },
};

/** Moves a task to the board's first done status, or back to its first to-do one (or ticks its Done box). */
async function setDone(id: string, url: string, done: boolean): Promise<string> {
  const write = writables.get(id);
  if (!write?.done) throw new Error('This task has nothing that says it’s done.');
  let value: unknown;
  if (write.done.kind === 'checkbox') {
    value = { checkbox: done };
  } else {
    const board = await boardStatusesOf(write.board);
    const name = done ? board?.options.done[0] : (board?.options.todo[0] ?? board?.options.doing[0]);
    if (!name) throw new Error('Ghost.md couldn’t read this board’s statuses.');
    value = { status: { name } };
  }
  await notionRequest('PATCH', `pages/${id}`, { properties: { [write.done.name]: value } });
  await tasks.reread(id, url);
  return done ? 'Marked done in Notion.' : 'Reopened in Notion.';
}

/** Forgets what was read, for signing out: another workspace's tasks aren't this one's. */
export function forgetTaskDetails(): void {
  boards.clear();
  writables.clear();
  tasks.forget();
}
