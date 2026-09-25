import { invoke, isTauri } from './tauri.ts';

/**
 * Which native generation this binary is (src-tauri/src/ota.rs
 * `NATIVE_GENERATION`), asked of Rust once per page load.
 *
 * A bundle that arrives over the air runs on binaries older than itself, so a
 * page that calls a command added in generation N first asks whether the
 * binary it landed on has it. Each feature keeps its own `*_GENERATION` beside
 * the command it gates; the question is the same everywhere, and its answer
 * cannot change while the page is loaded - a new binary is a reinstall, which
 * is a new page. So it is asked once and the one promise is shared. Ten
 * modules used to keep a copy each, and two of them (the recorder's
 * `capture_stop` check and Reset) asked again every time.
 *
 * 0 in a browser, where there is no binary, and 0 when the question fails: a
 * binary that cannot answer `ota_status` is treated as one with nothing newer,
 * which hides a feature rather than calling a command that is not there. What
 * a browser should do instead is the caller's decision, not this module's -
 * sync (core/sync/engine.ts) runs there regardless, with the page's own store.
 * `core/ota.ts` asks `ota_status` itself, for the whole status the Updates
 * page shows, and does not come through here.
 *
 * Its own module rather than a line in tauri.ts, deliberately: tests stand in
 * for tauri.ts with a factory (`vi.mock('../core/tauri.ts', () => ({ isTauri,
 * invoke }))`), and a factory hands importers only the names it lists, so a
 * helper living there would vanish from under every module those tests load.
 * Importing tauri.ts from here instead means the same factory answers for it.
 */

let asked: Promise<number> | null = null;

/** This binary's native generation, or 0 in a browser or when the binary will not say. */
export function nativeGeneration(): Promise<number> {
  if (!isTauri()) return Promise.resolve(0);
  asked ??= invoke<{ nativeGeneration?: number } | null>('ota_status').then(
    (status) => status?.nativeGeneration ?? 0,
    () => 0,
  );
  return asked;
}

/** Whether this binary is generation `wanted` or newer: false in a browser, for any generation above 0. */
export async function hasNativeGeneration(wanted: number): Promise<boolean> {
  return (await nativeGeneration()) >= wanted;
}
