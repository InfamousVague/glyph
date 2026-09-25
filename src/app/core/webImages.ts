/**
 * The browser's own picture store: one IndexedDB database, `glyph-images`, holding each picture as a blob under its
 * name.
 *
 * A browser has no app folder for pictures and no `img` scheme to serve them, and `npm run dev` still has to be a
 * working app (core/store.ts says why), so this is where a browser keeps what a phone keeps under its data.
 * IndexedDB rather than localStorage because a picture is a blob and megabytes. Only the storing is here; the names,
 * the blob URLs the editor draws from and the moment a picture is ready to draw are core/images.ts's, which is the
 * only module that imports this one.
 *
 * A browser without IndexedDB - an old one, or a private window that refuses it - keeps nothing: a save rejects with
 * words a person can read, and a read finds nothing.
 */

const DB = 'glyph-images';
const STORE = 'images';

function db(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    if (typeof indexedDB === 'undefined') {
      reject(new Error('No picture storage in this browser.'));
      return;
    }
    const request = indexedDB.open(DB, 1);
    request.onupgradeneeded = () => request.result.createObjectStore(STORE);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error('No picture storage in this browser.'));
  });
}

/** Keeps `blob` under `name`, replacing any picture of that name. */
export async function webPut(name: string, blob: Blob): Promise<void> {
  const d = await db();
  await new Promise<void>((resolve, reject) => {
    const tx = d.transaction(STORE, 'readwrite');
    tx.objectStore(STORE).put(blob, name);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error ?? new Error('The picture was not saved.'));
  });
}

/** The picture kept under `name`, or null when there is none or no store to look in. */
export async function webGet(name: string): Promise<Blob | null> {
  const d = await db().catch(() => null);
  if (!d) return null;
  return new Promise((resolve) => {
    const request = d.transaction(STORE).objectStore(STORE).get(name);
    request.onsuccess = () => resolve((request.result as Blob | undefined) ?? null);
    request.onerror = () => resolve(null);
  });
}
