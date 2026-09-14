/**
 * A thin, dependency-free bridge to the Tauri runtime.
 *
 * Glyph runs two ways: in a plain browser (which is where most of the editor
 * work actually happens, because `npm run dev` reloads in milliseconds and a
 * phone build does not), and inside a Tauri webview with the Rust store and
 * the Taptic Engine behind it. Every call here degrades to nothing outside the
 * webview, so no page has to know which one it is in.
 *
 * The Tauri modules are pulled in through literal dynamic imports so the
 * bundler can resolve and code-split them; each import is guarded by
 * `isTauri()` and a try/catch.
 */

import type { InvokeArgs } from '@tauri-apps/api/core';

/** True when running inside a Tauri webview. */
export function isTauri(): boolean {
  return typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;
}

/**
 * Call a Rust command, or reject if there is no Rust to call.
 *
 * Callers are expected to have checked `isTauri()` and chosen a different path
 * when it is false - `store.ts` keeps a whole localStorage implementation for
 * exactly that case - so a rejection here is a real failure worth surfacing,
 * not the ordinary browser-dev condition.
 */
export async function invoke<T>(command: string, args?: InvokeArgs): Promise<T> {
  if (!isTauri()) throw new Error(`no Tauri runtime for command "${command}"`);
  const mod = await import('@tauri-apps/api/core');
  return mod.invoke<T>(command, args);
}
