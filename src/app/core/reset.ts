import { plugins } from '../plugins/registry.ts';
import { accountState, signOut } from './account/account.ts';
import { storedKeys, writeStored } from './stored.ts';
import { invoke, isTauri } from './tauri.ts';

/**
 * Starting over: everything a person made or chose on this phone goes, and
 * Glyph reloads on the welcome guide. Developer settings, from where this is
 * reached, stay on. The downloaded models stay unless asked to go too: they
 * are gigabytes a person waited for, and a reset to test the app is not a
 * reason to fetch them again.
 *
 * On the phone the notes, recordings and pictures are Rust's (`reset.rs`,
 * native generation 11); the page clears what it keeps itself. In a browser
 * everything is the page's.
 *
 * What the page keeps is every key named `glyph-` (core/stored.ts) and every
 * plugin's, switched on or not - found by asking storage what it holds, not
 * from a list. The list this replaced named fourteen keys, two of them no
 * longer written by anything, and had fallen twenty-four behind:
 * bookmarks and places pointing at notes that were gone, the workspace
 * filter, the tape ids, and the account's session with the sync bookkeeping
 * beside it. That last pair was the dangerous one. The bookkeeping says which
 * notes this device last saw on the account, so a device whose notes were
 * wiped under it would read every one as deleted here and, on its next sync,
 * send the deletions to the account and so to every other device. A reset now
 * signs the device out as well (the keys in IndexedDB with the session), so
 * nothing is left that could sync, and the account is as it was.
 */

/** The binary generation that has `reset_local_data`. */
const RESET_GENERATION = 11;

/**
 * What a reset leaves behind: developer mode, and the two smoke overrides a
 * developer sets from its bench or by hand (art/wispMask.ts). Every other key
 * goes, so a key added later is cleared without anybody remembering to list
 * it; one that should survive has to be named here, on purpose.
 */
export const SPARED: ReadonlySet<string> = new Set(['glyph-developer', 'glyph-wisp-draw', 'glyph-wisp-head']);

/**
 * Everything the page keeps itself, gone: the account signed out here, then
 * every stored key but the spared. Not the notes' store on the phone, which
 * is Rust's, and no reload - `resetLocalData` does both.
 */
export async function clearPageData(): Promise<void> {
  // Keys IndexedDB would not give up are no account once the session beside them is gone below.
  if (accountState().session) await signOut().catch(() => undefined);
  const owned = new Set(plugins.storageKeys());
  for (const key of storedKeys()) {
    if ((key.startsWith('glyph-') || owned.has(key)) && !SPARED.has(key)) writeStored(key, null);
  }
}

export async function resetLocalData({ models }: { models: boolean }): Promise<void> {
  if (isTauri()) {
    const generation = await invoke<{ nativeGeneration?: number }>('ota_status').then(
      (status) => status.nativeGeneration ?? 0,
      () => 0,
    );
    if (generation < RESET_GENERATION) throw new Error('Resetting needs the newest Ghost.md. Install it from Settings > Updates.');
    await invoke<void>('reset_local_data', { models });
  } else {
    await new Promise<void>((resolve) => {
      if (typeof indexedDB === 'undefined') {
        resolve();
        return;
      }
      const request = indexedDB.deleteDatabase('glyph-images');
      request.onsuccess = () => resolve();
      request.onerror = () => resolve();
      request.onblocked = () => resolve();
    });
  }
  await clearPageData();
  window.location.reload();
}
