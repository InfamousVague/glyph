import type { Note } from '../app/core/store.ts';
import type { Bytes } from '../app/core/sync/crypto.ts';
import { emptyState, syncNotes, type FileKind, type LocalFiles, type LocalNotes, type SyncContext, type SyncState } from '../app/core/sync/notes.ts';
import type { FakeService } from './fakeService.ts';

/**
 * A device signed in to the service in memory (src/test/fakeService.ts), for a test of the note sync pass
 * (core/sync/notes.ts): its notes, its pictures, its recordings and its versions files in maps behind the LocalNotes and LocalFiles the
 * pass is given, what it remembers of the account, and a `sync` that runs one pass.
 *
 * The pictures test built this by hand; the notes test shares it, since a device is the same thing in both.
 * `clock` is the device's time, for the waits the pass keeps (a picture not asked for again for a while); a test
 * moves it by hand. `fetcher` stands between this device and the service, for a test that has another device write
 * at a moment of its choosing - between this one's pull and its push, say.
 */
export function syncDevice(
  api: FakeService,
  {
    clock = { at: 0 },
    pictures = {},
    fetcher = api.fetcher,
    digest,
  }: { clock?: { at: number }; pictures?: Record<string, Bytes>; fetcher?: typeof fetch; digest?: LocalFiles['digest'] } = {},
) {
  const key = api.accountKey;
  const token = api.signedIn();
  const notes = new Map<string, Note>();
  /** Pictures by name. */
  const held = new Map(Object.entries(pictures));
  /** Recordings by note id. */
  const tapes = new Map<string, Bytes>();
  /** Versions files by note id, as text, and the notes whose file changed here since it was sent. */
  const versions = new Map<string, string>();
  const owed = new Set<string>();
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
    read: async (kind: FileKind, name: string) => {
      if (kind === 'versions') {
        const text = versions.get(name);
        return text === undefined ? null : new TextEncoder().encode(text);
      }
      return (kind === 'image' ? held : tapes).get(name) ?? null;
    },
    write: async (kind: FileKind, name: string, bytes) => {
      if (kind === 'versions') versions.set(name, new TextDecoder().decode(bytes));
      else (kind === 'image' ? held : tapes).set(name, bytes);
    },
    owed: () => [...owed],
    settled: (name) => void owed.delete(name),
    ...(digest ? { digest } : {}),
  };
  return {
    notes,
    held,
    tapes,
    versions,
    /** Keeps a versions file here as the app does when a version is kept: owed to the account until sent. */
    keepVersions(noteId: string, text: string) {
      versions.set(noteId, text);
      owed.add(noteId);
    },
    owed,
    get state() {
      return state;
    },
    set state(next: SyncState) {
      state = next;
    },
    /** One pass; `extra` is what the app hands the pass besides its stores (which notes are meetings, and whether their audio goes). */
    sync: (extra: Pick<SyncContext, 'meetings' | 'syncMeetingRecordings' | 'teamNote'> = {}) =>
      syncNotes({ token, key, notes: local, files, state, save: (s) => (state = s), fetcher, now: () => clock.at, ...extra }),
  };
}

export type SyncDevice = ReturnType<typeof syncDevice>;
