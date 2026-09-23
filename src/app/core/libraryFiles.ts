import { invoke } from '@tauri-apps/api/core';
import { isTauri } from './tauri.ts';

/**
 * The notes' folder, shown where the device shows folders (Matt: "add a browse local files button somewhere to open the
 * folder on the phones file browser"): the Files app on the phone, where Ghost.md lists its library as a place of its
 * own (files/LibraryDocuments.kt, read-only), and Finder on a Mac (src-tauri commands.rs `library_reveal`). Both came
 * with native generation 18, and an update over the air reaches older binaries, so the button is only offered where
 * the binary has them. In a browser there is no folder to show.
 */

/** The native generation that has `library_reveal` and the activity's `browseFiles`. */
const FILES_GENERATION = 18;
let generation: Promise<number> | null = null;

function nativeGeneration(): Promise<number> {
  generation ??= invoke<{ nativeGeneration?: number }>('ota_status').then(
    (status) => status.nativeGeneration ?? 0,
    () => 0,
  );
  return generation;
}

/** Whether this device can show the notes' folder. */
export async function canBrowseFiles(): Promise<boolean> {
  if (typeof window === 'undefined') return false;
  if (window.GlyphHost) return typeof window.GlyphHost.browseFiles === 'function';
  if (!isTauri()) return false;
  return (await nativeGeneration()) >= FILES_GENERATION;
}

/** Shows the notes' folder: the Files app on the phone, Finder on a Mac. */
export async function browseFiles(): Promise<void> {
  if (window.GlyphHost?.browseFiles) {
    window.GlyphHost.browseFiles();
    return;
  }
  await invoke('library_reveal');
}
