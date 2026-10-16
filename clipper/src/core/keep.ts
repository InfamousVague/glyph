import { fromBase64Url, openBytes, sealBytes, settle, toBase64Url } from '../../../tauri/src/app/core/sync/crypto.ts';

/**
 * Where the clipper keeps a signed-in account between one click and the next, two ways, which the person chooses
 * with "Stay signed in" when they sign in:
 *
 * - **Off (the default):** `chrome.storage.session`, which the browser holds in memory and empties when it closes.
 *   The session token and the account key's bytes are there, and nowhere on the disk. A page, and the clipper's own
 *   script in a page, cannot read that area: only the clipper's popup and its background can.
 * - **On:** the account key and a signing key of the clipper's own are CryptoKey objects in the extension's
 *   IndexedDB, kept the way the web app keeps its keys (core/account/keystore.ts): the browser will not hand their
 *   bytes to any script, the clipper's included. The session (the token, the handle) is sealed under a third such key
 *   and the sealed bytes are in `chrome.storage.local`. When the token lapses, the signing key renews it without the
 *   password, as a phone's does. This keeps the person signed in across restarts; what it protects against is a copy
 *   of the storage file on its own, since the keys are in the same browser profile on the same disk. Anyone who can
 *   run code as the person on that computer could use the profile. That is the trade the box asks about.
 *
 * Neither ever holds the password. The password is turned into the login half and the wrap key the moment it is
 * typed (core/sync/crypto.ts `derive`), in the clipper's background, and only the login half is sent.
 */

export interface SessionInfo {
  v: 1;
  /** The service this session is with: a session from another build's service is not used. */
  api: string;
  handle: string;
  accountId: number;
  token: string;
  stay: boolean;
}

export interface Held {
  info: SessionInfo;
  key: CryptoKey;
}

export interface Keeper {
  load(): Promise<Held | null>;
  /** The session kept; with `key`, the account key too (at sign-in), without it the key already kept stays (a renewed token). */
  save(info: SessionInfo, key?: CryptoKey): Promise<void>;
  clear(): Promise<void>;
  deviceKey(): Promise<CryptoKeyPair | null>;
  setDeviceKey(pair: CryptoKeyPair | null): Promise<void>;
}

/** What `chrome.storage` gives the keeper: one area's get, set and remove. A test hands it a map. */
export interface Area {
  get(key: string): Promise<unknown>;
  set(key: string, value: unknown): Promise<void>;
  remove(key: string): Promise<void>;
}

/** What IndexedDB gives the keeper: keys kept as objects. A test hands it a map, as structured clone would. */
export interface KeyRoom {
  get<T>(name: string): Promise<T | null>;
  put(name: string, value: unknown): Promise<void>;
}

const SESSION = 'ghost-session';
const SEALED = 'ghost-session-sealed';
const CONTEXT = 'clipper-session';

function isInfo(value: unknown): value is SessionInfo {
  const v = value as Partial<SessionInfo> | null;
  return Boolean(v) && v!.v === 1 && typeof v!.api === 'string' && typeof v!.handle === 'string' && typeof v!.accountId === 'number' && typeof v!.token === 'string';
}

async function importRaw(raw: string): Promise<CryptoKey> {
  const bytes = fromBase64Url(raw);
  try {
    return await crypto.subtle.importKey('raw', bytes, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
  } finally {
    bytes.fill(0);
  }
}

/** The keeper over a memory area (storage.session), a disk area (storage.local) and a key room (IndexedDB). */
export function keeper({ memory, disk, keys, api }: { memory: Area; disk: Area; keys: KeyRoom; api: string }): Keeper {
  const sealKey = async (make: boolean): Promise<CryptoKey | null> => {
    const known = await keys.get<CryptoKey>('seal');
    if (known || !make) return known;
    const made = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
    await keys.put('seal', made);
    return made;
  };
  const self: Keeper = {
    async load() {
      const held = (await memory.get(SESSION)) as (SessionInfo & { accountKey?: string }) | undefined;
      if (isInfo(held) && held.api === api) {
        if (!held.stay && held.accountKey) return { info: stripped(held), key: await importRaw(held.accountKey) };
        const key = await keys.get<CryptoKey>('account');
        if (held.stay && key) return { info: stripped(held), key };
      }
      // After a restart: the sealed session, opened with the key that sealed it, and the account key beside it.
      const sealed = await disk.get(SEALED);
      if (typeof sealed !== 'string') return null;
      const [seal, key] = [await sealKey(false), await keys.get<CryptoKey>('account')];
      if (!seal || !key) return null;
      try {
        const info = JSON.parse(new TextDecoder().decode(await openBytes(seal, fromBase64Url(sealed), CONTEXT))) as unknown;
        if (!isInfo(info) || info.api !== api) return null;
        await memory.set(SESSION, info);
        return { info, key };
      } catch {
        return null;
      }
    },
    async save(info, key) {
      if (!info.stay) {
        // In memory only: the key's bytes have to be written out to be kept there, so it must still be extractable.
        let raw = ((await memory.get(SESSION)) as { accountKey?: string } | undefined)?.accountKey;
        if (key) {
          if (!key.extractable) throw new Error('The account key must be readable once to be kept for this browser session.');
          const bytes = new Uint8Array(await crypto.subtle.exportKey('raw', key));
          raw = toBase64Url(bytes);
          bytes.fill(0);
        }
        await memory.set(SESSION, { ...info, accountKey: raw });
        return;
      }
      if (key) await keys.put('account', await settle(key));
      const seal = (await sealKey(true))!;
      const sealed = await sealBytes(seal, new TextEncoder().encode(JSON.stringify(info)) as Uint8Array<ArrayBuffer>, CONTEXT);
      await disk.set(SEALED, toBase64Url(sealed));
      await memory.set(SESSION, info);
    },
    async clear() {
      await memory.remove(SESSION);
      await disk.remove(SEALED);
      await keys.put('account', null);
      await keys.put('seal', null);
      await keys.put('device', null);
    },
    deviceKey: () => keys.get<CryptoKeyPair>('device'),
    setDeviceKey: (pair) => keys.put('device', pair),
  };
  return self;
}

function stripped(held: SessionInfo & { accountKey?: string }): SessionInfo {
  const { accountKey: _key, ...info } = held;
  return info;
}

/** A map for each, for the tests: what a browser keeps, without a browser. */
export function memoryRooms(): { memory: Area & { data: Map<string, unknown> }; disk: Area & { data: Map<string, unknown> }; keys: KeyRoom & { data: Map<string, unknown> } } {
  const area = () => {
    const data = new Map<string, unknown>();
    return { data, get: async (k: string) => data.get(k), set: async (k: string, v: unknown) => void data.set(k, structuredClone(v)), remove: async (k: string) => void data.delete(k) };
  };
  const data = new Map<string, unknown>();
  return {
    memory: area(),
    disk: area(),
    keys: { data, get: async <T>(name: string) => (data.get(name) as T | undefined) ?? null, put: async (name: string, value: unknown) => void (value === null ? data.delete(name) : data.set(name, value)) },
  };
}

/** The extension's own rooms: `chrome.storage.session`, `chrome.storage.local`, and an IndexedDB database of keys. */
export function extensionRooms(): { memory: Area; disk: Area; keys: KeyRoom } {
  const area = (store: chrome.storage.StorageArea): Area => ({
    get: async (key) => (await store.get(key))[key],
    set: (key, value) => store.set({ [key]: value }),
    remove: (key) => store.remove(key),
  });
  let opened: Promise<IDBDatabase> | null = null;
  const db = () =>
    (opened ??= new Promise((resolve, reject) => {
      const req = indexedDB.open('ghost-clipper', 1);
      req.onupgradeneeded = () => req.result.createObjectStore('keys');
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error ?? new Error('IndexedDB would not open'));
    }));
  const done = <T>(req: IDBRequest<T>) =>
    new Promise<T>((resolve, reject) => {
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error ?? new Error('IndexedDB failed'));
    });
  return {
    memory: area(chrome.storage.session),
    disk: area(chrome.storage.local),
    keys: {
      async get<T>(name: string) {
        return ((await done((await db()).transaction('keys', 'readonly').objectStore('keys').get(name))) as T | undefined) ?? null;
      },
      async put(name, value) {
        const store = (await db()).transaction('keys', 'readwrite').objectStore('keys');
        if (value === null) await done(store.delete(name));
        else await done(store.put(value, name));
      },
    },
  };
}
