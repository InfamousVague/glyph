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
import { noteTitle, withoutFrontMatter } from '../src/app/core/noteTitle.ts';
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
 */

export const VERSION = '1.0.0';

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

/** The keys a notebook, a journal and an entry are made of (book/book.ts, book/journal.ts). */
const KEPT_KEYS = ['title', 'book', 'journal', 'template', 'entry-place', 'date'] as const;

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
  for (const key of KEPT_KEYS) {
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

export function buildServer(account: GlyphAccount, hosted?: HostedHooks): McpServer {
  const server = new McpServer({ name: 'glyph', version: VERSION });
  /**
   * The words with this AI among the note's authors (core/authors.ts): the name it gave, else what its app called itself
   * when it connected (Claude's is "claude-ai"), after the account's own handle on a note that named nobody. With no
   * name to go on the words are left as they came.
   */
  const authored = (body: string, said: string | undefined): string => {
    const name = aiName(said, server.server.getClientVersion() ?? hosted?.client?.());
    return name ? withAuthor(body, name, account.handle) : body;
  };
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
      description: 'A note in full: its markdown body and what the account knows about it. Give its id (from list_notes) or its exact title.',
      inputSchema: {
        id: z.string().optional().describe('The note’s id.'),
        title: z.string().optional().describe('The note’s title, when the id is not known.'),
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
            const at = record.note.body.toLowerCase().indexOf(want);
            if (at < 0) return null;
            const from = Math.max(0, at - 80);
            const snippet = `${from > 0 ? '…' : ''}${record.note.body.slice(from, at + want.length + 80).replace(/\s+/g, ' ')}${at + want.length + 80 < record.note.body.length ? '…' : ''}`;
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
        body: z.string().describe('The note’s markdown. Ghost.md’s marks all work: headings, lists, `- [ ]` to-dos, tables, ```board fences.'),
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
        return text({ created: whole(made) });
      }),
  );

  server.registerTool(
    'update_note',
    {
      title: 'Replace a note’s body',
      description:
        'The whole markdown body of a note replaced with `body`. Read the note first and send it back changed: this writes from the version last read, and if another device changed the note meanwhile the write is refused and their version shown, never overwritten. For adding a line or a task to the end of a note, prefer append_to_note. A notebook’s or a journal’s list of [[links]] is its pages: a link left out of the new body takes that page or entry out of it, though its note stays. For a new journal entry use add_journal_entry.',
      inputSchema: {
        id: z.string().describe('The note’s id.'),
        body: z.string().describe('The new markdown body, whole.'),
        author: authorField,
      },
    },
    async ({ id, body, author }) =>
      guarded(async () => {
        await account.pull();
        if (!body.trim()) return failed('A note needs some words. To remove a note, archive it with set_note_flags.');
        // The authors the note had stay, whatever the new body says: a rewrite doesn't take anyone off. Nor where
        // it was written, nor the keys that make it a notebook, a journal or an entry.
        const written = await account.edit(id, (note) => ({ ...note, body: authored(keepPlace(note.body, keepAuthors(note.body, keepKeys(note.body, body))), author) }));
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
