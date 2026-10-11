/**
 * Where a device keeps a team note's document (docs/SHARED.md, S5): the CRDT's state, how far along the note's log on
 * the service it has read (`seq`), the seq its last snapshot covered, and the updates made here that the service has
 * not been given yet. IndexedDB where there is one, as the account's keys are kept (core/account/keystore.ts);
 * memory in a browser without it and in the tests, where a document lost with the page is read again from the
 * organization's row on the next pass, nothing of the team's lost with it.
 */

export interface TeamDocRecord {
  /** The document as `Y.encodeStateAsUpdate` gives it. */
  state: Uint8Array;
  /** The last seq of the note's log applied here. */
  seq: number;
  /** The seq the organization's row for this note covered when this device last put or read it. */
  snapshotSeq: number;
  /** Updates made here, in order, not yet posted to the log. */
  pending: Uint8Array[];
}

export interface TeamDocStore {
  read(noteId: string): Promise<TeamDocRecord | null>;
  write(noteId: string, record: TeamDocRecord): Promise<void>;
  remove(noteId: string): Promise<void>;
}

const DB = 'glyph-team';
const STORE = 'docs';

function request<T>(req: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error ?? new Error('IndexedDB failed'));
  });
}

let opened: Promise<IDBDatabase> | null = null;

function database(): Promise<IDBDatabase> {
  opened ??= new Promise((resolve, reject) => {
    const req = indexedDB.open(DB, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error ?? new Error('IndexedDB would not open'));
  });
  return opened;
}

const indexedDocs: TeamDocStore = {
  async read(noteId) {
    const db = await database();
    return ((await request(db.transaction(STORE, 'readonly').objectStore(STORE).get(noteId))) as TeamDocRecord | undefined) ?? null;
  },
  async write(noteId, record) {
    const db = await database();
    await request(db.transaction(STORE, 'readwrite').objectStore(STORE).put(record, noteId));
  },
  async remove(noteId) {
    const db = await database();
    await request(db.transaction(STORE, 'readwrite').objectStore(STORE).delete(noteId));
  },
};

/** The same, in memory: for tests, and for a browser with no IndexedDB. */
export function memoryDocs(): TeamDocStore {
  const docs = new Map<string, TeamDocRecord>();
  return {
    read: async (noteId) => docs.get(noteId) ?? null,
    write: async (noteId, record) => {
      docs.set(noteId, record);
    },
    remove: async (noteId) => {
      docs.delete(noteId);
    },
  };
}

const fallback = memoryDocs();

/** Where this device keeps its team documents. */
export function deviceDocs(): TeamDocStore {
  return typeof indexedDB === 'undefined' ? fallback : indexedDocs;
}
