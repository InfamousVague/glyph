// @vitest-environment node
import { describe, expect, it } from 'vitest';
import type { Note } from '../store.ts';
import { newAccountKey, openBytes, seal, type Bytes } from './crypto.ts';
import { ASK_AGAIN_MS, emptyState, fileId, mark, syncNotes, type FileKind, type LocalFiles, type LocalNotes, type NotePayload, type SyncState } from './notes.ts';

/**
 * Pictures reach every device, whatever road they took to the first one. Matt's HelloTrade book: another program wrote
 * the chapters through the MCP and dropped their JPEGs into the Mac's picture folder, so the Mac drew them and the
 * phone showed every one broken - the Mac had marked each as sent without sending it, and the phone, having asked once
 * when the note arrived, never asked again.
 */

interface Stored {
  rev: number;
  deleted: boolean;
  blob: string | null;
}

/** The sync service in memory: the note feed and the file routes, with server/src/sync.rs's revisions and refusals. */
function service({ head = true } = {}) {
  const notes = new Map<string, Stored>();
  const files = new Map<string, { rev: number; bytes: Bytes }>();
  let counter = 0;
  const calls: string[] = [];
  const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
  const fetcher: typeof fetch = async (input, init) => {
    const url = new URL(String(input));
    const method = init?.method ?? 'GET';
    const path = url.pathname.replace(/^.*\/v1\//, '');
    calls.push(`${method} ${path}`);
    if (method === 'GET' && path === 'notes') {
      const since = Number(url.searchParams.get('since') ?? 0);
      const items = [...notes.entries()].filter(([, n]) => n.rev > since).map(([id, n]) => ({ id, ...n }));
      return json(200, { rev: counter, items, more: false });
    }
    const note = /^notes\/(.+)$/.exec(path);
    if (note && (method === 'PUT' || method === 'DELETE')) {
      const id = decodeURIComponent(note[1]!);
      const body = JSON.parse(String(init?.body)) as { base: number; blob?: string };
      const had = notes.get(id);
      if (had && had.rev !== body.base) return json(409, { id, ...had });
      counter += 1;
      notes.set(id, method === 'PUT' ? { rev: counter, deleted: false, blob: body.blob ?? null } : { rev: counter, deleted: true, blob: null });
      return json(200, { rev: counter });
    }
    const file = /^recordings\/([^?]+)$/.exec(path);
    if (file) {
      const id = file[1]!;
      const had = files.get(id);
      if (method === 'HEAD') {
        if (!head) throw new TypeError('Failed to fetch');
        return had ? new Response(null, { status: 200, headers: { 'x-glyph-rev': String(had.rev) } }) : new Response(null, { status: 404 });
      }
      if (method === 'GET') {
        return had ? new Response(had.bytes, { status: 200, headers: { 'x-glyph-rev': String(had.rev) } }) : json(404, { error: 'No recording by that id.' });
      }
      if (method === 'PUT') {
        const base = Number(url.searchParams.get('base') ?? 0);
        if (had && had.rev !== base) return json(409, { rev: had.rev });
        counter += 1;
        files.set(id, { rev: counter, bytes: new Uint8Array(init?.body as Bytes) });
        return json(200, { rev: counter });
      }
    }
    return json(404, { error: `No route ${method} ${path}` });
  };
  return { fetcher, files, calls };
}

/** A device: its notes, its pictures, and what it remembers of the account. */
function device(key: CryptoKey, fetcher: typeof fetch, clock: { at: number }, pictures: Record<string, Bytes> = {}) {
  const notes = new Map<string, Note>();
  const held = new Map(Object.entries(pictures));
  let state: SyncState = emptyState();
  const local: LocalNotes = {
    list: async () => [...notes.values()],
    get: async (id) => notes.get(id) ?? null,
    apply: async (note) => {
      notes.set(note.id, note);
      return note;
    },
    remove: async (id) => {
      notes.delete(id);
    },
  };
  const files: LocalFiles = {
    read: async (kind: FileKind, name: string) => (kind === 'image' ? (held.get(name) ?? null) : null),
    write: async (kind: FileKind, name: string, bytes) => {
      if (kind === 'image') held.set(name, bytes);
    },
  };
  return {
    notes,
    held,
    get state() {
      return state;
    },
    set state(next: SyncState) {
      state = next;
    },
    sync: () => syncNotes({ token: 't', key, notes: local, files, state, save: (s) => (state = s), fetcher, now: () => clock.at }),
  };
}

const PICTURE = 'a1b2c3d4-0000-4000-8000-000000000001.jpg';
const bytes: Bytes = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);
/** What the account holds for a file, opened: it only ever holds it sealed. */
const opened = async (key: CryptoKey, stored: { bytes: Bytes } | undefined, id: string) => (stored ? openBytes(key, stored.bytes, `file:${id}`) : null);
const chapter: Note = { id: 'ch-1', body: `# Signing the order\n\n![The limit price](image/${PICTURE})\n`, createdAt: 1, updatedAt: 2, source: 'editor' } as Note;

/** A note written as the MCP writes one: sealed, naming its pictures, with no file sent. */
async function writtenElsewhere(key: CryptoKey, fetcher: typeof fetch, note: Note): Promise<void> {
  const payload: NotePayload = { v: 1, note, images: [PICTURE] };
  await fetcher('https://x/glyph/api/v1/notes/' + note.id, { method: 'PUT', body: JSON.stringify({ base: 0, blob: await seal(key, payload, `note:${note.id}`) }) });
}

describe('pictures that reached a device some other way than sync', () => {
  it('are sent by the Mac that holds them, and fetched by a phone that asked before they were there', async () => {
    const key = await newAccountKey();
    const clock = { at: 1_000_000 };
    const api = service();
    const phone = device(key, api.fetcher, clock);
    const mac = device(key, api.fetcher, clock, { [PICTURE]: bytes });
    await writtenElsewhere(key, api.fetcher, chapter);

    // The phone reads the chapter first: the picture is not in the account, so it has nothing to draw.
    await phone.sync();
    expect(phone.notes.has('ch-1')).toBe(true);
    expect(phone.held.has(PICTURE)).toBe(false);

    // The Mac reads it, finds the picture in its own folder, and sends it.
    await mac.sync();
    const id = fileId('image', PICTURE)!;
    expect(api.files.get(id)).toBeTruthy();
    expect(mac.state.files[id]?.rev).toBeGreaterThan(0);

    // The phone's next pass a keystroke later does not ask again; the next timed pass does, and gets it.
    await phone.sync();
    expect(phone.held.has(PICTURE)).toBe(false);
    clock.at += ASK_AGAIN_MS;
    await phone.sync();
    expect(phone.held.get(PICTURE)).toEqual(bytes);
    expect(phone.state.files[id]?.rev).toBeGreaterThan(0);
  });

  it('repairs a Mac that marked a picture sent without sending it, as the older app did', async () => {
    const key = await newAccountKey();
    const clock = { at: 5_000_000 };
    const api = service();
    const mac = device(key, api.fetcher, clock, { [PICTURE]: bytes });
    await writtenElsewhere(key, api.fetcher, chapter);
    await mac.sync();
    // Put back as the older app left it: the note seen, the picture at revision 0, nothing in the account.
    const id = fileId('image', PICTURE)!;
    api.files.clear();
    mac.state = { ...mac.state, files: { [id]: { rev: 0 } } };
    await mac.sync();
    expect(await opened(key, api.files.get(id), id)).toEqual(bytes);
  });

  it('does not send a picture the account already holds, and settles it by asking for its head', async () => {
    const key = await newAccountKey();
    const clock = { at: 9_000_000 };
    const api = service();
    const first = device(key, api.fetcher, clock, { [PICTURE]: bytes });
    first.notes.set('ch-1', chapter);
    await first.sync();
    const id = fileId('image', PICTURE)!;
    expect(api.files.get(id)).toBeTruthy();

    // Signed in again with nothing remembered, holding the same picture: one HEAD, no upload.
    api.calls.length = 0;
    first.state = emptyState();
    await first.sync();
    expect(api.calls.filter((c) => c === `PUT recordings/${id}`)).toEqual([]);
    expect(api.calls).toContain(`HEAD recordings/${id}`);
    expect(first.state.files[id]?.rev).toBeGreaterThan(0);
    // Settled: the pass after asks nothing about it.
    api.calls.length = 0;
    await first.sync();
    expect(api.calls.some((c) => c.includes(id))).toBe(false);
  });

  it('sends anyway where a HEAD cannot be asked, and a picture already there is taken as there', async () => {
    const key = await newAccountKey();
    const clock = { at: 13_000_000 };
    const api = service({ head: false });
    const mac = device(key, api.fetcher, clock, { [PICTURE]: bytes });
    await writtenElsewhere(key, api.fetcher, chapter);
    await mac.sync();
    const id = fileId('image', PICTURE)!;
    expect(await opened(key, api.files.get(id), id)).toEqual(bytes);
    // Asked again with nothing remembered: the upload meets the one already there, and that settles it.
    mac.state = { ...mac.state, files: {} };
    await mac.sync();
    expect(mac.state.files[id]?.rev).toBe(api.files.get(id)?.rev);
    expect(mark(mac.notes.get('ch-1')!)).toBe(mark(chapter));
  });
});
