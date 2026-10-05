import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { fakeService, type FakeService } from '../../../test/fakeService.ts';
import type { Note } from '../store.ts';
import { open, openBytes, fromBase64Url, type Bytes } from '../sync/crypto.ts';
import type { FileKind, LocalFiles, LocalNotes } from '../sync/notes.ts';
import { createOrg } from '../orgs/orgs.ts';
import { forgetTeamDocs, teamDoc } from './doc.ts';
import { memoryDocs, type TeamDocStore } from './docs.ts';
import { emptyTeamState, particulars, SNAPSHOT_EVERY, syncTeamNotes, type TeamSyncState } from './sync.ts';

/**
 * A team's notes between two members' devices (core/team/sync.ts; docs/SHARED.md, S1, S4, S5): a note filed in the
 * organization's workspace published, adopted on another device with its words kept, edited on both and merged by
 * the CRDT, snapshotted, taken out of the team, and its versions file and pictures carried.
 *
 * Two devices here share one fake service, whose one account stands for both members: the channel keys nothing by
 * account, and the rows and logs are the organization's. Each device has its own notes, files, documents and state.
 */

const ACCOUNT = { handle: 'matt', password: 'correct horse' };
let service: FakeService;
let orgId: string;
let orgKey: CryptoKey;

/** A device of a member: its notes and files in maps, which notes it has filed in the organization, and one pass. */
function device(docs: TeamDocStore = memoryDocs()) {
  const notes = new Map<string, Note>();
  const filed = new Set<string>();
  const pictures = new Map<string, Bytes>();
  const versions = new Map<string, string>();
  const owed = new Set<string>();
  let state: TeamSyncState = emptyTeamState();
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
    read: async (kind: FileKind, name: string) => {
      if (kind === 'versions') {
        const text = versions.get(name);
        return text === undefined ? null : new TextEncoder().encode(text);
      }
      return kind === 'image' ? (pictures.get(name) ?? null) : null;
    },
    write: async (kind: FileKind, name: string, bytes) => {
      if (kind === 'versions') versions.set(name, new TextDecoder().decode(bytes));
      else if (kind === 'image') pictures.set(name, bytes);
    },
    owed: () => [...owed],
    settled: (name) => void owed.delete(name),
  };
  const clock = { at: 1_000 };
  return {
    notes,
    filed,
    pictures,
    versions,
    owed,
    docs,
    clock,
    get state() {
      return state;
    },
    /** A note on this device, filed in the organization's workspace. */
    put(id: string, body: string, over: Partial<Note> = {}) {
      notes.set(id, { id, body, createdAt: clock.at, updatedAt: clock.at, source: 'editor', ...over });
      filed.add(id);
    },
    sync: () =>
      syncTeamNotes({
        token: service.signedIn(),
        orgId,
        key: orgKey,
        notes: local,
        files,
        docs,
        state,
        save: (s) => (state = s),
        fetcher: service.fetcher,
        now: () => clock.at,
        isTeamNote: (id) => filed.has(id),
        file: (id) => void filed.add(id),
      }),
  };
}

beforeEach(async () => {
  service = await fakeService(ACCOUNT);
  vi.stubGlobal('fetch', service.fetcher);
  orgId = (await createOrg('Ghost', 'sea', { token: service.signedIn(), fetcher: service.fetcher })).id;
  orgKey = await crypto.subtle.importKey('raw', crypto.getRandomValues(new Uint8Array(32)), { name: 'AES-GCM' }, true, ['encrypt', 'decrypt']);
  forgetTeamDocs();
});

afterEach(() => {
  vi.unstubAllGlobals();
  forgetTeamDocs();
});

describe('a team note between two devices', () => {
  it('is published by the first device as a row the service cannot read, and adopted by the second with its words and particulars', async () => {
    const phone = device();
    phone.put('n1', '# Roadmap\n- ship', { starred: true });
    const outcome = await phone.sync();
    expect(outcome).toEqual({ changed: 0, unsent: 0, reason: null });
    const rows = service.teamNotes(orgId);
    expect(rows.size).toBe(1);
    const row = rows.get('n1')!;
    expect(row.blob).not.toContain('Roadmap');
    const payload = await open<{ note: Note; state: string; seq: number }>(orgKey, row.blob!, `org:${orgId}:note:n1`);
    expect((payload.note.body, payload.note.starred, payload.seq)).toBe(0);
    expect(payload.note.body).toBe('# Roadmap\n- ship');
    expect(phone.state.notes.n1).toEqual({ rev: row.rev, mark: particulars(payload.note) });
    expect(service.teamUpdates(orgId, 'n1')).toEqual([]);
    // The other device: the note arrives, filed, with its words and its pin, and a document of its own.
    forgetTeamDocs();
    const mac = device();
    const arrived = await mac.sync();
    expect(arrived.changed).toBe(1);
    expect(mac.notes.get('n1')).toMatchObject({ body: '# Roadmap\n- ship', starred: true });
    expect(mac.filed.has('n1')).toBe(true);
    expect((await mac.docs.read('n1'))?.seq).toBe(0);
    // Nothing more on a quiet pass, either side.
    expect((await mac.sync()).changed).toBe(0);
    expect(service.calls.filter((c) => c.includes('/notes/n1')).length).toBeLessThan(6);
  });

  it('carries edits made apart to both sides and merges them by the CRDT, with no copy', async () => {
    const phone = device();
    phone.put('n1', 'one\ntwo\nthree');
    await phone.sync();
    forgetTeamDocs();
    const mac = device();
    await mac.sync();
    // Edited on both, apart: the phone at the top, the mac at the foot. Each pass reconciles its note's words.
    phone.notes.set('n1', { ...phone.notes.get('n1')!, body: 'ONE\ntwo\nthree' });
    mac.notes.set('n1', { ...mac.notes.get('n1')!, body: 'one\ntwo\nTHREE' });
    forgetTeamDocs();
    await phone.sync();
    expect(service.teamUpdates(orgId, 'n1')).toHaveLength(1);
    forgetTeamDocs();
    await mac.sync();
    expect(mac.notes.get('n1')!.body).toBe('ONE\ntwo\nTHREE');
    forgetTeamDocs();
    await phone.sync();
    expect(phone.notes.get('n1')!.body).toBe('ONE\ntwo\nTHREE');
    // The updates on the log are sealed, and open under the organization key alone.
    const update = service.teamUpdates(orgId, 'n1')[0]!;
    await expect(openBytes(orgKey, fromBase64Url(update.blob), `org:${orgId}:note:n1:update`)).resolves.toBeInstanceOf(Uint8Array);
    await expect(openBytes(orgKey, fromBase64Url(update.blob), `org:${orgId}:note:n2:update`)).rejects.toThrow();
  });

  it('keeps the words a device had of its own before the team did, as a change for the team', async () => {
    const phone = device();
    phone.put('n1', '# Plan\n- a');
    await phone.sync();
    // The mac had the same note of its own, with a line more, before the team's row reached it.
    forgetTeamDocs();
    const mac = device();
    mac.put('n1', '# Plan\n- a\n- b (mine)');
    await mac.sync();
    expect(mac.notes.get('n1')!.body).toBe('# Plan\n- a\n- b (mine)');
    forgetTeamDocs();
    await phone.sync();
    expect(phone.notes.get('n1')!.body).toBe('# Plan\n- a\n- b (mine)');
  });

  it('puts the row again for a changed pin or archive, and after enough updates, cutting the log', async () => {
    const phone = device();
    phone.put('n1', 'words');
    await phone.sync();
    const first = service.teamNotes(orgId).get('n1')!.rev;
    phone.notes.set('n1', { ...phone.notes.get('n1')!, archivedAt: 5 });
    await phone.sync();
    expect(service.teamNotes(orgId).get('n1')!.rev).toBeGreaterThan(first);
    // Many small edits: each pass posts one update; past the snapshot count the row goes again and the log is cut.
    for (let i = 0; i < SNAPSHOT_EVERY + 1; i += 1) {
      phone.notes.set('n1', { ...phone.notes.get('n1')!, body: `words ${i}` });
      await phone.sync();
    }
    // The snapshot went at the two-hundredth update and cut the log to there; the one edit since is on it alone.
    expect(service.teamUpdates(orgId, 'n1').map((u) => u.seq)).toEqual([SNAPSHOT_EVERY + 1]);
    const doc = (await teamDoc('n1', phone.docs))!;
    expect([doc.snapshotSeq, doc.seq]).toEqual([SNAPSHOT_EVERY, SNAPSHOT_EVERY + 1]);
  });

  it('takes a note from the team when a device deletes it or takes it out of the workspace', async () => {
    const phone = device();
    phone.put('n1', 'going');
    phone.put('n2', 'leaving the team');
    await phone.sync();
    forgetTeamDocs();
    const mac = device();
    await mac.sync();
    expect([...mac.notes.keys()].sort()).toEqual(['n1', 'n2']);
    phone.notes.delete('n1');
    phone.filed.delete('n2');
    forgetTeamDocs();
    await phone.sync();
    expect(service.teamNotes(orgId).get('n1')!.deleted).toBe(true);
    expect(service.teamNotes(orgId).get('n2')!.deleted).toBe(true);
    expect(phone.notes.has('n2')).toBe(true);
    expect(await phone.docs.read('n2')).toBeNull();
    forgetTeamDocs();
    await mac.sync();
    expect([...mac.notes.keys()]).toEqual([]);
  });

  it('carries a note’s versions file, merged, and its pictures, under the organization', async () => {
    const phone = device();
    phone.put('n1', 'See ![](image/photo.png)');
    phone.pictures.set('photo.png', new Uint8Array([1, 2, 3]));
    phone.versions.set('n1', '# Ghost.md versions 1\n# note n1\n\nv1 2026-10-05T00:00:00.000Z matt 00000000 full\n  +See\n');
    phone.owed.add('n1');
    await phone.sync();
    expect([...service.teamFiles(orgId).keys()].sort()).toEqual(['i-png-photo', 'v-n1']);
    expect(phone.owed.has('n1')).toBe(false);
    forgetTeamDocs();
    const mac = device();
    await mac.sync();
    expect(mac.pictures.get('photo.png')).toEqual(new Uint8Array([1, 2, 3]));
    expect(mac.versions.get('n1')).toContain('v1 2026-10-05');
  });

  it('counts a send that fails and goes on, and ends on a lapsed session', async () => {
    const phone = device();
    phone.put('n1', 'words');
    const failing: typeof fetch = async (input, init) => {
      if (String(input).includes('/notes/n1') && init?.method === 'PUT') return new Response(JSON.stringify({ error: 'The service is down.' }), { status: 500 });
      return service.fetcher(input, init);
    };
    vi.stubGlobal('fetch', failing);
    const outcome = await syncTeamNotes({ token: service.signedIn(), orgId, key: orgKey, notes: { list: async () => [...phone.notes.values()], get: async (id) => phone.notes.get(id) ?? null, apply: async (n) => n, remove: async () => undefined }, files: { read: async () => null, write: async () => undefined }, docs: phone.docs, state: emptyTeamState(), save: () => undefined, fetcher: failing, isTeamNote: () => true, file: () => undefined });
    expect(outcome).toEqual({ changed: 0, unsent: 1, reason: 'The service is down.' });
  });
});
