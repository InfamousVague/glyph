import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { isBookBody, isJournalBody } from '../src/app/book/book.ts';
import { entryBody, entryTitle, isEntryTitle, localStamp, templateOf, uniqueTitle, withEntry } from '../src/app/book/journal.ts';
import { fillTemplate, openEnd } from '../src/app/core/template.ts';
import { placeWords } from '../src/app/capture/listAppend.ts';
import { placeTake } from '../src/app/capture/place.ts';
import { aiName, authorsOf, withAuthor } from '../src/app/core/authors.ts';
import { failureText } from '../src/app/core/failure.ts';
import { frontMatterEnd, frontMatterValue, withFrontMatterValue } from '../src/app/core/frontMatter.ts';
import { geoTagOf, withGeoTag } from '../src/app/core/geotag.ts';
import { plainFills } from '../src/app/core/blanks.ts';
import { noteTitle, withoutFrontMatter } from '../src/app/core/noteTitle.ts';
import { issueKeyOf, isTicket, ticketIdOf, TICKET_PROPERTIES } from '../src/app/core/properties.ts';
import { titleKey } from '../src/app/core/titleKey.ts';
import { Conflict, GlyphApiError, type GlyphAccount, type NoteRecord } from './glyph.ts';

/**
 * The MCP server: Glyph's notes as tools for Claude (docs/MCP.md). Matt: "make an MCP plugin for Claude so I can use
 * Claude to remote control my account and add and update notes as well as read them".
 *
 * Every tool reads the account fresh before it acts, so what Claude sees is what the phone last wrote; a write goes
 * from the revision just read and is refused, never applied, when another device got there first - the tool then
 * says so and shows that device's words. "Append" places words the way a spoken "add task" does (capture/
 * listAppend.ts): into the note's own list, in its style.
 *
 * A journal's entries are written as the app writes them (docs/DESIGN.md §142): `add_journal_entry` makes the entry
 * named by its minute from the journal's template, with the words on from its time, and puts its line in the journal's
 * index, from the app's own modules (book/journal.ts, core/template.ts). `append_to_note` turns a journal down, since
 * its words are the list of its entries, and a rewrite keeps a notebook's keys as it keeps the authors and the place.
 *
 * A ticket is a note whose front matter says `type: ticket` (docs/DESIGN.md §157, docs/TICKETS.md): its properties are
 * that front matter, which a rewrite keeps as the app reads it (`keepKeys`), and `read_note` finds one by its key,
 * `GHO-12`, as a `[[GHO-12]]` in the app does.
 *
 * Each write is told to the account once it has landed (docs/TEAMS.md; Matt: "we see things like claude creating a
 * new note or making edits"): a sealed notification of its kind - note-created, note-edited with a line diff,
 * note-appended, journal-entry, rule-added - naming the note and who wrote it, posted after the write and never
 * after a refusal (`GlyphAccount.postNotification`, best effort). The "Claude rules" note is told of only when it is
 * made, not each time a connection finds it.
 */

/**
 * What a blank is, told to Claude in the two tools that write a body (docs/DESIGN.md §145): left alone unless asked, and
 * answered in the form the app reads back, so a note says where each answer came from.
 */
const BLANKS = 'A {?question} is a blank for Ghost.md’s model to fill on the phone. Leave it as it is unless asked to answer it. To answer one, write ??answer??(Claude from memory, YYYY-MM-DD. Asked: question) in its place, so the note says where the answer came from.';

export const VERSION = '1.0.0';

/**
 * The note that holds the person's standing instructions for Claude on this account (Matt: "bake in the Claude rules as
 * a note once we connect MCP and have Claude add repeated requests to rules"). It is made the first time Claude connects
 * (`ensureRulesNote`), handed to Claude as the server's MCP instructions at connect (`rulesInstructions`), read back on
 * demand (get_rules), and added to when the person makes a standing request (add_rule, `withRule`).
 */
export const RULES_TITLE = 'Claude rules';

/** The rules a fresh account starts with: what the note is for, and one sensible default a person can keep or change. */
export const DEFAULT_RULES = `# ${RULES_TITLE}

Your standing instructions when you work on this Ghost.md account through the connector. Read them and follow them in everything you do here. When the person asks you to always, again, or from now on do something, add it here with add_rule so it sticks.

## Ticket management
- Track work in Ghost: file it as a ticket (a note whose front matter says \`type: ticket\`) in the tickets notebook, and move its status as the work goes.
- When a ticket is finished, set its status to **In review** and assign it to the account's owner — leave Done to them, so they review it first.

## Standing requests

_Claude adds repeated requests here._
`;

/** The heading a standing request is added under, so add_rule's lines gather in one place rather than scatter. */
const RULES_SECTION = '## Standing requests';

/**
 * `body` with `rule` added as a line under the Standing requests heading, the heading made the first time. The
 * placeholder line the default note carries is dropped once there is a real rule under it.
 */
export function withRule(body: string, rule: string): string {
  const line = `- ${rule.trim().replace(/\s+/g, ' ')}`;
  const trimmed = body.replace(/\s+$/, '');
  const cleaned = trimmed.replace(/\n_Claude adds repeated requests here\._\s*$/, '');
  if (new RegExp(`^${RULES_SECTION.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*$`, 'm').test(cleaned)) return `${cleaned}\n${line}\n`;
  return `${cleaned}\n\n${RULES_SECTION}\n\n${line}\n`;
}

/** At most this many characters of a line ride in a notification: the first changed line, shown under its sentence. */
const FIRST_CHARS = 120;

/** The first line of `text` that says anything, trimmed, cut to what a notification carries. */
function firstLine(text: string): string {
  return (text.split('\n').find((line) => line.trim()) ?? '').trim().slice(0, FIRST_CHARS);
}

/** What a note-edited notification says of a rewrite (core/notifications/kinds.ts `Details`). */
export interface LineDiff {
  added: number;
  removed: number;
  first: string;
  /** Where the first change is, as the note screen lands on it: `line:<n>`, counting the written body's lines from 1. */
  at: string;
}

/**
 * A rewrite as a line diff: the lines that came and went between `before` and `after`, with the lines both share at
 * the top and the bottom left out, the first changed line that says anything (an added one, else a removed one), and
 * its place in `after` as the app's note screen takes one (editor/useLandAt.ts `line:<n>`, the body's lines from 1,
 * front matter included: a query's to-do opens its note the same way). The `authors:` line is the connector's own
 * signature (core/authors.ts), not an edit, so it is taken off both sides first; a status moved in a ticket's front
 * matter is an edit, and counts. "Claude edited Trip to Lisbon · 2 lines changed" is this diff's two counts added.
 */
export function lineDiff(before: string, after: string): LineDiff {
  const lines = after.split('\n');
  const was = withFrontMatterValue(before, 'authors', null).split('\n');
  const now = withFrontMatterValue(after, 'authors', null).split('\n');
  // The signature off `after` took a run of lines out of its top (the one line, or the whole block it alone made):
  // a line of `now` from there on is that many further down the written body.
  const dropped = lines.length - now.length;
  let shift = 0;
  while (shift < now.length && lines[shift] === now[shift]) shift += 1;
  const place = (index: number) => `line:${(index < shift ? index : index + dropped) + 1}`;
  let head = 0;
  while (head < was.length && head < now.length && was[head] === now[head]) head += 1;
  let tail = 0;
  while (tail < was.length - head && tail < now.length - head && was[was.length - 1 - tail] === now[now.length - 1 - tail]) tail += 1;
  const came = now.slice(head, now.length - tail);
  const went = was.slice(head, was.length - tail);
  const telling = came.findIndex((line) => line.trim());
  const first = telling >= 0 ? came[telling]! : (went.find((line) => line.trim()) ?? '');
  // A pure removal lands where the lines were, which is now the next line, or the last when they were the end.
  const at = place(telling >= 0 ? head + telling : Math.min(head, Math.max(0, now.length - 1)));
  return { added: came.length, removed: went.length, first: first.trim().slice(0, FIRST_CHARS), at };
}

/**
 * The "Claude rules" note, made (pinned) the first time it is wanted. Reads the account fresh first, so a note made on
 * the phone is seen rather than a second one created. `seedAuthor` names the AI as its co-author when it is made new.
 */
export async function ensureRulesNote(account: GlyphAccount, seedAuthor = 'Claude'): Promise<NoteRecord> {
  await account.pull();
  const found = await account.byTitle(RULES_TITLE);
  if (found) return found;
  const made = await account.create(withAuthor(DEFAULT_RULES, seedAuthor, account.handle), { pinned: true });
  // Told of once, when it is made: a connection that finds it has written nothing.
  await account.postNotification('note-created', { noteId: made.note.id, title: RULES_TITLE, by: seedAuthor });
  return made;
}

/** The MCP instructions a connection carries: what the connector is, that a rules note governs it, and the rules themselves. */
export function rulesInstructions(rulesBody: string): string {
  return [
    'Ghost.md connector — these tools read and change the notes in this person’s Ghost.md account (list, search, read, create, update, append, journal entries, pin and archive). Each tool reads the account fresh, and a write is refused, never applied, if another device changed the note first.',
    '',
    `This account keeps a “${RULES_TITLE}” note: the person’s standing instructions for you here. Follow them in everything you do, and re-read them any time with get_rules. When the person asks you to always, again, or from now on do something — a repeated or standing request — record it with add_rule so it is not lost.`,
    '',
    'Their rules right now:',
    '',
    rulesBody.trim(),
  ].join('\n');
}

function iso(ms: number): string {
  return new Date(ms).toISOString();
}

/** A note as the tools describe it: what a list needs, and never the whole body unless asked. */
function summary(record: NoteRecord) {
  const { note } = record;
  const title = noteTitle(note.body);
  // The front matter goes first, as the list's title and the app's peek take it off: a note that opened with it
  // previewed as its keys ("title: … authors: …"). Its `title:` comes back as the first line, and a heading of the
  // same name under it is the title again, so it goes too.
  const lines = withoutFrontMatter(note.body.split('\n')).map((l) => l.trim()).filter(Boolean);
  const first = lines.findIndex((l) => !/^!\[[^\]]*\]\([^)]*\)$/.test(l));
  const rest = lines.slice(first + 1);
  if (title && rest[0] && noteTitle(rest[0]).toLowerCase() === title.toLowerCase()) rest.shift();
  const after = rest.slice(0, 2).join(' ');
  return {
    id: note.id,
    title: title || 'Untitled',
    updated: iso(note.updatedAt),
    created: iso(note.createdAt),
    pinned: Boolean(note.starred),
    archived: Boolean(note.archivedAt),
    folder: note.path?.includes('/') ? note.path.slice(0, note.path.lastIndexOf('/')) : null,
    hasRecording: Boolean(note.recordingMs),
    preview: after.length > 140 ? `${after.slice(0, 139)}…` : after,
  };
}

function whole(record: NoteRecord) {
  return { ...summary(record), rev: record.rev, body: record.note.body };
}

function text(value: unknown) {
  return { content: [{ type: 'text' as const, text: typeof value === 'string' ? value : JSON.stringify(value, null, 2) }] };
}

function failed(message: string) {
  return { isError: true, content: [{ type: 'text' as const, text: message }] };
}

/** A tool's work, with the account's refusals turned into words rather than a crash. */
async function guarded(run: () => Promise<ReturnType<typeof text> | ReturnType<typeof failed>>) {
  try {
    return await run();
  } catch (failure) {
    if (failure instanceof Conflict) {
      return failed(
        failure.theirs
          ? `${failure.message}\n\nTheir version (read it with read_note and try again):\n${JSON.stringify(whole(failure.theirs), null, 2)}`
          : failure.message,
      );
    }
    if (failure instanceof GlyphApiError) return failed(`Ghost.md's sync service refused: ${failure.message}`);
    return failed(failureText(failure));
  }
}

/** `next` with the authors `before` named: an AI's whole-body rewrite that dropped the line gets it back. */
function keepAuthors(before: string, next: string): string {
  let out = next;
  for (const name of authorsOf(before)) out = withAuthor(out, name);
  return out;
}

/** `next` with where `before` was written, the same way (core/geotag.ts): a rewrite that dropped the tag keeps it. */
function keepPlace(before: string, next: string): string {
  const tag = geoTagOf(before);
  return tag && !geoTagOf(next) ? withGeoTag(next, tag) : next;
}

/**
 * The keys a notebook, a journal and an entry are made of (book/book.ts, book/journal.ts), how a note looks
 * (core/look.ts), and what makes a notebook the one your templates are kept in (notes/ownTemplates.ts).
 */
const KEPT_KEYS = ['title', 'book', 'journal', 'template', 'entry-place', 'date', 'look', 'templates'] as const;

/** A notebook's keys for its tickets (book/tickets.ts): the key they are numbered by and the workflow they move through. */
const NOTEBOOK_KEYS = ['key', 'statuses'] as const;

/**
 * A ticket's own keys (core/properties.ts `TICKET_PROPERTIES`). Its `type:` and `id:` are what make it a ticket and
 * what its `[[GHO-12]]`s find, so they come back whenever a rewrite leaves them out. Its status, assignee and the rest
 * come back only when the rewrite dropped the front matter whole: one that wrote front matter of its own, without a
 * `blocked-by:`, took the wait off, and that is Claude's to do.
 */
const TICKET_KEYS = TICKET_PROPERTIES.map((property) => property.key);

/**
 * `next` with every key of `before`'s that it lacks entirely put back, as it was written: a rewrite that dropped the
 * front matter would otherwise turn a notebook into a note with a list of links, and a journal's entry lose its name.
 * A value `next` gives is kept, so Claude can still rename a note. `title:` and `date:` only for a notebook or an
 * entry, whose names they are: a plain note the app renamed keeps its `title:` too, and put back it outranked the
 * heading Claude wrote the new name in, so a rewrite could no longer rename it as it could before.
 */
export function keepKeys(before: string, next: string): string {
  let out = next;
  const lines = before.split('\n');
  const keys = lines.slice(1, Math.max(1, frontMatterEnd(lines) - 1));
  const named = isBookBody(before) || isEntryTitle(frontMatterValue(before, 'title') ?? '');
  const dropped = frontMatterEnd(next.split('\n')) === 0;
  const ticket = isTicket(before) ? (dropped ? TICKET_KEYS : ['type', 'id']) : [];
  for (const key of [...KEPT_KEYS, ...(isBookBody(before) ? NOTEBOOK_KEYS : []), ...ticket]) {
    if (!named && (key === 'title' || key === 'date')) continue;
    const line = keys.find((each) => new RegExp(`^\\s*${key}\\s*:`, 'i').test(each));
    if (line === undefined || frontMatterValue(before, key) === null || frontMatterValue(out, key) !== null) continue;
    out = withFrontMatterValue(out, key, line.replace(/^\s*[\w.-]+\s*:\s*/, '').trim());
  }
  return out;
}

/** `YYYY-MM-DDTHH:MM`, the wall clock an entry is written at. */
const WALL = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/;

/** The note `id` or, failing that, the one titled `title`; a clear complaint when neither finds one. */
async function find(account: GlyphAccount, id: string | undefined, title: string | undefined): Promise<NoteRecord> {
  if (id) {
    const found = await account.get(id);
    if (found) return found;
    throw new Error(`No note with the id ${id}. Use list_notes to find it.`);
  }
  if (title) {
    const found = await account.byTitle(title);
    if (found) return found;
    // A ticket's key finds the ticket, as `[[GHO-12]]` does in the app (docs/DESIGN.md §157).
    const key = issueKeyOf(title);
    const ticket = key ? (await account.list({ archived: true })).find((r) => ticketIdOf(r.note.body) === key) : undefined;
    if (ticket) return ticket;
    const near = (await account.list({ archived: true })).filter((r) => noteTitle(r.note.body).toLowerCase().includes(title.trim().toLowerCase()));
    if (near.length === 1) return near[0]!;
    throw new Error(
      near.length
        ? `Several notes could be "${title}": ${near.map((r) => `${noteTitle(r.note.body)} (${r.note.id})`).join(', ')}. Say which by id.`
        : `No note titled "${title}". Use list_notes or search_notes to find it.`,
    );
  }
  throw new Error('Say which note: its id (from list_notes) or its title.');
}

/**
 * What only the hosted server knows (mcp/hosted.ts): how many Claude connections an account has right now, and how to
 * end them all. The local server is one connection and has nothing to end but itself, so it hands nothing in.
 */
export interface HostedHooks {
  /** Live connections to this account, this one included. */
  connections: () => number;
  /** Ends every connection to this account, this one included; answers how many it ended. */
  signOutEverywhere: () => number;
  /** What the AI's app called itself when it connected, kept across the requests that each build a fresh server. */
  client?: () => { name?: string; title?: string } | undefined;
}

export function buildServer(account: GlyphAccount, hosted?: HostedHooks, options?: { instructions?: string }): McpServer {
  const server = new McpServer({ name: 'glyph', version: VERSION }, options?.instructions ? { instructions: options.instructions } : undefined);
  /**
   * This AI's name (core/authors.ts): the name it gave, else what its app called itself when it connected (Claude's
   * is "claude-ai"); null with nothing to go on.
   */
  const authorName = (said: string | undefined): string | null => aiName(said, server.server.getClientVersion() ?? hosted?.client?.());
  /**
   * The words with this AI among the note's authors, after the account's own handle on a note that named nobody. With
   * no name to go on the words are left as they came.
   */
  const authored = (body: string, said: string | undefined): string => {
    const name = authorName(said);
    return name ? withAuthor(body, name, account.handle) : body;
  };
  /** Who a notification says wrote: the author's name, or Claude when a connection gave none (docs/TEAMS.md). */
  const by = (said: string | undefined): string => authorName(said) ?? 'Claude';
  /** A note's title as a notification names it, as the list does. */
  const titled = (record: NoteRecord): string => noteTitle(record.note.body) || 'Untitled';
  const authorField = z
    .string()
    .optional()
    .describe('Your name, as this note’s co-author: it is listed with the account’s own on the note, its notebook and a shared page. Left out, the name your app connected with is used (Claude for Claude).');

  server.registerTool(
    'list_notes',
    {
      title: 'List notes',
      description:
        'The notes in this Ghost.md account, newest change first: id, title, dates, pinned, archived, folder and a line of preview. Optionally only those whose title contains `query`. Reads the account fresh first.',
      inputSchema: {
        query: z.string().optional().describe('Only notes whose title contains this (case-insensitive).'),
        include_archived: z.boolean().optional().describe('Include archived notes. Off by default.'),
        limit: z.number().int().min(1).max(500).optional().describe('At most this many, default 50.'),
      },
    },
    async ({ query, include_archived, limit }) =>
      guarded(async () => {
        await account.pull();
        const want = query?.trim().toLowerCase();
        const notes = (await account.list({ archived: Boolean(include_archived) })).filter((r) => !want || noteTitle(r.note.body).toLowerCase().includes(want));
        return text({ count: notes.length, notes: notes.slice(0, limit ?? 50).map(summary) });
      }),
  );

  server.registerTool(
    'read_note',
    {
      title: 'Read a note',
      description: 'A note in full: its markdown body and what the account knows about it. Give its id (from list_notes) or its exact title, or a ticket’s key (GHO-12).',
      inputSchema: {
        id: z.string().optional().describe('The note’s id.'),
        title: z.string().optional().describe('The note’s title, when the id is not known, or a ticket’s key.'),
      },
    },
    async ({ id, title }) =>
      guarded(async () => {
        await account.pull();
        return text(whole(await find(account, id, title)));
      }),
  );

  server.registerTool(
    'search_notes',
    {
      title: 'Search notes',
      description: 'Notes whose words contain `query` (case-insensitive), each with a snippet around the first match. Titles and bodies both count.',
      inputSchema: {
        query: z.string().min(1).describe('What to look for.'),
        include_archived: z.boolean().optional(),
        limit: z.number().int().min(1).max(200).optional().describe('At most this many, default 20.'),
      },
    },
    async ({ query, include_archived, limit }) =>
      guarded(async () => {
        await account.pull();
        const want = query.trim().toLowerCase();
        const hits = (await account.list({ archived: Boolean(include_archived) }))
          .map((record) => {
            // A filled blank's hidden bracket is not the note's words (docs/DESIGN.md §145): its answer is found, the
            // bracket's "memory" and "Asked" are not, as in the app's own search.
            const words = plainFills(record.note.body);
            const at = words.toLowerCase().indexOf(want);
            if (at < 0) return null;
            const from = Math.max(0, at - 80);
            const snippet = `${from > 0 ? '…' : ''}${words.slice(from, at + want.length + 80).replace(/\s+/g, ' ')}${at + want.length + 80 < words.length ? '…' : ''}`;
            return { ...summary(record), snippet };
          })
          .filter((hit): hit is NonNullable<typeof hit> => hit !== null);
        return text({ count: hits.length, notes: hits.slice(0, limit ?? 20) });
      }),
  );

  server.registerTool(
    'create_note',
    {
      title: 'Create a note',
      description:
        'A new note in the account, as if typed in the app: markdown, with the first line as its title. Give a `title` and it becomes a `# Title` heading above the body. It appears on every signed-in device at its next sync.',
      inputSchema: {
        body: z.string().describe(`The note’s markdown. Ghost.md’s marks all work: headings, lists, \`- [ ]\` to-dos, tables, \`\`\`board fences. ${BLANKS}`),
        title: z.string().optional().describe('A title to put above the body as a heading, if the body does not start with one.'),
        pinned: z.boolean().optional().describe('Pin it to the top of the list.'),
        author: authorField,
      },
    },
    async ({ body, title, pinned, author }) =>
      guarded(async () => {
        const heading = title?.trim();
        const words = heading && !/^#\s/.test(body.trimStart()) ? `# ${heading}\n\n${body.trim()}` : body;
        if (!words.trim()) return failed('A note needs some words.');
        const made = await account.create(authored(words, author), { pinned: Boolean(pinned) });
        await account.postNotification('note-created', { noteId: made.note.id, title: titled(made), by: by(author) });
        return text({ created: whole(made) });
      }),
  );

  server.registerTool(
    'update_note',
    {
      title: 'Replace a note’s body',
      description:
        'The whole markdown body of a note replaced with `body`. Read the note first and send it back changed: this writes from the version last read, and if another device changed the note meanwhile the write is refused and their version shown, never overwritten. For adding a line or a task to the end of a note, prefer append_to_note. A notebook’s or a journal’s list of [[links]] is its pages: a link left out of the new body takes that page or entry out of it, though its note stays. For a new journal entry use add_journal_entry. A ticket’s properties are its front matter (type: ticket, id, status, assignee, priority, due, blocked-by…): keep the block and change a value to change it.',
      inputSchema: {
        id: z.string().describe('The note’s id.'),
        body: z.string().describe(`The new markdown body, whole. ${BLANKS}`),
        author: authorField,
      },
    },
    async ({ id, body, author }) =>
      guarded(async () => {
        await account.pull();
        if (!body.trim()) return failed('A note needs some words. To remove a note, archive it with set_note_flags.');
        // The authors the note had stay, whatever the new body says: a rewrite doesn't take anyone off. Nor where
        // it was written, nor the keys that make it a notebook, a journal or an entry.
        let before = '';
        const written = await account.edit(id, (note) => {
          before = note.body;
          return { ...note, body: authored(keepPlace(note.body, keepAuthors(note.body, keepKeys(note.body, body))), author) };
        });
        await account.postNotification('note-edited', { noteId: id, title: titled(written), by: by(author), ...lineDiff(before, written.note.body) });
        return text({ updated: whole(written) });
      }),
  );

  server.registerTool(
    'append_to_note',
    {
      title: 'Add to a note',
      description:
        'Words added to a note the way the app’s own "add task" does: a task or an item joins the note’s list, in the list’s own style, or starts one; a paragraph goes on the end. Safe against another device editing at the same time. Not for a journal: write an entry in one with add_journal_entry.',
      inputSchema: {
        id: z.string().optional().describe('The note’s id.'),
        title: z.string().optional().describe('Or its title.'),
        text: z.string().min(1).describe('What to add. Several items may be given with commas.'),
        as: z.enum(['task', 'item', 'paragraph', 'auto']).optional().describe('`task` for a `- [ ]` to-do, `item` for a bullet, `paragraph` for a line of its own, `auto` (default) to put it where it fits.'),
        author: authorField,
      },
    },
    async ({ id, title, text: words, as, author }) =>
      guarded(async () => {
        await account.pull();
        const target = await find(account, id, title);
        // A journal's words are the list of its entries: an entry is a note of its own, with its line (below).
        if (isJournalBody(target.note.body)) return failed(`“${noteTitle(target.note.body)}” is a journal: its words are the list of its entries. Use add_journal_entry to write one.`);
        const how = as === 'task' || as === 'item' ? 'item' : as === 'paragraph' ? 'paragraph' : 'leave';
        let added: string[] = [];
        const written = await account.edit(target.note.id, (note) => {
          const placed = placeWords(note.body, words, { how, task: as === 'task', many: false });
          added = placed.added;
          return { ...note, body: authored(placed.body, author) };
        });
        await account.postNotification('note-appended', { noteId: written.note.id, title: titled(written), by: by(author), lines: added.length, first: firstLine(added[0] ?? '') });
        return text({ added, note: summary(written) });
      }),
  );

  server.registerTool(
    'add_journal_entry',
    {
      title: 'Write a journal entry',
      description:
        'A new entry in a journal (a Ghost.md notebook kept as a journal, dated entries in its index): a note named by the minute, "2026-09-28 14.05", started from the journal’s own template, with `text` going on from its time line or into its to-do list, and its line added to the journal. Where it was written is never set. Safe against another device editing the journal at the same time.',
      inputSchema: {
        journal: z.string().min(1).describe('The journal’s id or its title.'),
        text: z.string().min(1).describe('What the entry says, as markdown.'),
        at: z
          .string()
          .regex(WALL)
          .optional()
          .describe(
            hosted
              ? 'When, as YYYY-MM-DDTHH:MM: the person’s local time for the entry. Needed: this server’s clock is not the person’s, and an entry is named and filed by its time.'
              : 'When, as YYYY-MM-DDTHH:MM: the person’s local time for the entry. Left out, the time where this server runs.',
          ),
        author: authorField,
      },
    },
    async ({ journal, text: words, at, author }) =>
      guarded(async () => {
        await account.pull();
        const target = (await account.get(journal)) ?? (await find(account, undefined, journal));
        if (!isJournalBody(target.note.body)) return failed(`“${noteTitle(target.note.body)}” is not a journal. Use append_to_note or create_note for it.`);
        // The hosted server's clock is the box's, not the person's: an entry named and filed by it would be an hour or a
        // day out. The local one (`npm run mcp`) runs on the person's own computer.
        if (!at && hosted) return failed('Say when, as `at`: the person’s local time, YYYY-MM-DDTHH:MM. This server’s clock is not theirs.');
        const said = at ? WALL.exec(at) : null;
        const [year, month, day, hour, minute] = said ? said.slice(1).map(Number) : [];
        const when = said ? new Date(year!, month! - 1, day!, hour!, minute!) : new Date();
        // A date rolls a month of 13 or a minute of 99 on into another day rather than failing: read back, it must say
        // what was asked.
        const kept = !said || (when.getFullYear() === year && when.getMonth() === month! - 1 && when.getDate() === day && when.getHours() === hour && when.getMinutes() === minute);
        if (Number.isNaN(when.getTime()) || !kept) return failed(`${at} is not a time. Give it as YYYY-MM-DDTHH:MM.`);
        const name = noteTitle(target.note.body);
        const taken = new Set((await account.list({ archived: true })).map((r) => titleKey(noteTitle(r.note.body))));
        const title = uniqueTitle(entryTitle(when.getTime()), taken);
        const { base, placing } = openEnd(fillTemplate(templateOf(target.note.body), { at: when, title, journal: name }));
        const body = placeTake(entryBody(title, localStamp(when.getTime()), base), words.trim(), placing).body;
        // The line first: refused because another device changed the journal, nothing is made and a second try is
        // clean. The entry first, it was left with no line, and the second try made it again with " (2)". A line whose
        // entry never came is an entry's name with no note, which the journal does not draw.
        const listed = await account.edit(target.note.id, (note) => ({ ...note, body: withEntry(note.body, title) }));
        const made = await account.create(authored(body, author));
        await account.postNotification('journal-entry', { noteId: made.note.id, title, by: by(author), journal: name, first: firstLine(words) });
        return text({ created: whole(made), journal: summary(listed) });
      }),
  );

  server.registerTool(
    'set_note_flags',
    {
      title: 'Pin or archive a note',
      description: 'Pin a note to the top of the list, or archive it (out of the list, kept). Either can be undone by setting it back.',
      inputSchema: {
        id: z.string().describe('The note’s id.'),
        pinned: z.boolean().optional(),
        archived: z.boolean().optional(),
      },
    },
    async ({ id, pinned, archived }) =>
      guarded(async () => {
        await account.pull();
        if (pinned === undefined && archived === undefined) return failed('Say what to set: pinned, archived, or both.');
        const written = await account.edit(id, (note) => ({
          ...note,
          ...(pinned === undefined ? {} : { starred: pinned }),
          ...(archived === undefined ? {} : { archivedAt: archived ? (note.archivedAt ?? Date.now()) : null }),
        }));
        return text({ note: summary(written) });
      }),
  );

  server.registerTool(
    'get_rules',
    {
      title: 'Read the Claude rules',
      description:
        'The “Claude rules” note: the person’s standing instructions for you on this account. Read it to follow their conventions; it is also handed to you when you connect. Made, pinned, if it does not exist yet.',
      inputSchema: {},
    },
    async () =>
      guarded(async () => {
        const note = await ensureRulesNote(account, by(undefined));
        return text(whole(note));
      }),
  );

  server.registerTool(
    'add_rule',
    {
      title: 'Add a standing rule',
      description:
        'Record a standing or repeated request into the “Claude rules” note, so you keep doing it on this account. Use it when the person asks you to always, from now on, or again do something. One instruction per call, written in your own words as a rule for yourself; it is added under the note’s Standing requests.',
      inputSchema: {
        rule: z.string().min(1).describe('The standing instruction to remember, as one line.'),
        author: authorField,
      },
    },
    async ({ rule, author }) =>
      guarded(async () => {
        if (!rule.trim()) return failed('Say the rule to remember.');
        const note = await ensureRulesNote(account, by(undefined));
        const written = await account.edit(note.note.id, (n) => ({ ...n, body: authored(withRule(n.body, rule), author) }));
        const added = rule.trim().replace(/\s+/g, ' ');
        await account.postNotification('rule-added', { noteId: note.note.id, title: RULES_TITLE, by: by(author), first: added.slice(0, FIRST_CHARS) });
        return text({ added, note: summary(written) });
      }),
  );

  server.registerTool(
    'account_status',
    {
      title: 'Account status',
      description: 'Which Ghost.md account this is signed in to, where its sync service is, and how many notes it holds.',
      inputSchema: {},
    },
    async () =>
      guarded(async () => {
        const { changed } = await account.pull();
        const notes = await account.list({ archived: true });
        return text({
          handle: account.handle,
          service: account.api,
          notes: notes.length,
          archived: notes.filter((r) => r.note.archivedAt).length,
          pinned: notes.filter((r) => r.note.starred).length,
          changedSinceLastRead: changed,
          // Several Claude accounts, or Claude on several computers, can be signed in to one Ghost.md account (docs/
          // MCP.md); this says how many are, so a person can tell (Matt: "can I connect multiple Claude accounts").
          connections: hosted ? hosted.connections() : 1,
        });
      }),
  );

  if (hosted) {
    server.registerTool(
      'sign_out_everywhere',
      {
        title: 'Sign out everywhere',
        description:
          'Ends every Claude connection to this Ghost.md account - every Claude account and every computer signed in to it, this one included. Each signs in again on the page. For a connection you no longer want, or a key you no longer trust here.',
        inputSchema: {},
      },
      async () => text({ endedConnections: hosted.signOutEverywhere() }),
    );
  }

  return server;
}
