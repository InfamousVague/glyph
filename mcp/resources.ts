import { McpServer, ResourceTemplate } from '@modelcontextprotocol/sdk/server/mcp.js';
import { ErrorCode, McpError, SubscribeRequestSchema, UnsubscribeRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { noteTitle } from '../tauri/src/app/core/noteTitle.ts';
import { failureText } from '../tauri/src/app/core/failure.ts';
import type { GlyphAccount, NoteRecord } from './glyph.ts';

/**
 * The account's notes as MCP resources (docs/CLAUDE_LIVE.md, "Resources, prompts, subscriptions"), so a person can
 * attach a note in Claude's app as they would a file: `ghost://note/{id}`, its markdown as `text/markdown`. Listed
 * newest change first, at most 100, each named by its title with when it changed, its folder and the workspace it is
 * in said beside it; a note in the Trash is not listed, as list_notes leaves it out, but its address still reads it, as read_note
 * finds one by its id.
 *
 * Subscriptions are the local connector's alone (mcp/cli.ts): it is one process with Claude's app on the other end of
 * its pipe, so it can say when a subscribed note changes. While anything is subscribed it reads the account every 20
 * seconds and sends `notifications/resources/updated` for each subscribed note whose words, pin or archive moved, or
 * that went. The hosted server answers each request with one JSON response and has no way to speak between them, so
 * it does not offer them.
 */

/** A note's address. */
export function noteUri(id: string): string {
  return `ghost://note/${encodeURIComponent(id)}`;
}

/** The most notes the list offers: a person attaching one looks among the recent, and search finds the rest. */
export const LISTED = 100;

/** What the resources need of the server's tools: the account read fresh, the trash, and where a note is. */
export interface NoteResourceKit {
  account: GlyphAccount;
  fresh: () => Promise<unknown>;
  trash: () => Promise<Record<string, number>>;
  /** A reader of where each note is, as the tools say it: its workspace's name, or null for none. */
  places: () => Promise<(record: NoteRecord) => string | null>;
}

/**
 * What the list says beside a note's title: when it last changed, and its folder and its workspace when it has
 * either. Every note says something, or the template's own description would stand in for it.
 */
function placeWords(record: NoteRecord, workspace: string | null): string {
  const path = record.note.path;
  const folder = path?.includes('/') ? path.slice(0, path.lastIndexOf('/')) : null;
  const changed = `Changed ${new Date(record.note.updatedAt).toISOString().slice(0, 10)}`;
  return [changed, folder ? `Folder: ${folder}` : null, workspace ? `Workspace: ${workspace}` : null].filter(Boolean).join(' · ');
}

export function registerNoteResources(server: McpServer, kit: NoteResourceKit): void {
  const { account } = kit;
  server.registerResource(
    'note',
    new ResourceTemplate('ghost://note/{id}', {
      list: async () => {
        await kit.fresh();
        const trash = await kit.trash();
        const where = await kit.places();
        const notes = (await account.list()).filter((record) => !(record.note.id in trash)).slice(0, LISTED);
        return {
          resources: notes.map((record) => {
            return { uri: noteUri(record.note.id), name: noteTitle(record.note.body) || 'Untitled', mimeType: 'text/markdown', description: placeWords(record, where(record)) };
          }),
        };
      },
    }),
    { title: 'A Ghost.md note', description: 'A note in this Ghost.md account or one of its organizations, as markdown.', mimeType: 'text/markdown' },
    async (uri, { id }) => {
      const wanted = decodeURIComponent(String(Array.isArray(id) ? id[0] : id));
      await kit.fresh();
      const record = await account.get(wanted);
      if (!record) throw new McpError(ErrorCode.InvalidParams, `No note with the id ${wanted}. Use list_notes to find it.`);
      return { contents: [{ uri: uri.href, mimeType: 'text/markdown', text: record.note.body }] };
    },
  );
}

/** How a note is told from what it was: its words, its pin and its archive. */
function stateOf(record: NoteRecord | null): string {
  return record ? JSON.stringify([record.note.body, Boolean(record.note.starred), record.note.archivedAt ?? null]) : 'gone';
}

/**
 * `resources/subscribe` and `resources/unsubscribe` answered, and a subscribed note's change told: the account read
 * every `everyMs` while anything is subscribed, and not at all while nothing is. Before the server connects.
 */
export function enableSubscriptions(server: McpServer, account: GlyphAccount, { everyMs = 20_000 }: { everyMs?: number } = {}): { poll: () => Promise<void> } {
  server.server.registerCapabilities({ resources: { subscribe: true } });
  /** What each subscribed note was when last looked at, by its address. */
  const watched = new Map<string, string>();
  let timer: ReturnType<typeof setInterval> | null = null;
  let polling: Promise<void> | null = null;
  const idOf = (uri: string): string | null => {
    const match = /^ghost:\/\/note\/(.+)$/.exec(uri);
    return match ? decodeURIComponent(match[1]!) : null;
  };
  const stop = () => {
    if (timer) clearInterval(timer);
    timer = null;
  };
  const poll = async () => {
    if (!watched.size) return;
    await account.pull();
    for (const [uri, was] of [...watched]) {
      const id = idOf(uri);
      const now = stateOf(id ? await account.get(id) : null);
      if (now === was || !watched.has(uri)) continue;
      watched.set(uri, now);
      await server.server.sendResourceUpdated({ uri });
    }
  };
  // One pass at a time; a pass that fails is said on stderr and the next one tries again.
  const tick = () => {
    polling ??= poll()
      .catch((failure: unknown) => {
        process.stderr.write(`glyph-mcp: watching notes: ${failureText(failure)}\n`);
      })
      .finally(() => {
        polling = null;
      });
    return polling;
  };
  server.server.setRequestHandler(SubscribeRequestSchema, async (request) => {
    const { uri } = request.params;
    const id = idOf(uri);
    if (!id) throw new McpError(ErrorCode.InvalidParams, `${uri} is not a note’s address: ghost://note/{id}.`);
    // Read fresh, so what is told later changed after the subscription, not before it.
    await account.pull();
    const record = await account.get(id);
    if (!record) throw new McpError(ErrorCode.InvalidParams, `No note with the id ${id}.`);
    watched.set(uri, stateOf(record));
    if (!timer) {
      timer = setInterval(() => void tick(), everyMs);
      timer.unref?.();
    }
    return {};
  });
  server.server.setRequestHandler(UnsubscribeRequestSchema, async (request) => {
    watched.delete(request.params.uri);
    if (!watched.size) stop();
    return {};
  });
  const closed = server.server.onclose;
  server.server.onclose = () => {
    stop();
    watched.clear();
    closed?.();
  };
  return { poll: tick };
}
