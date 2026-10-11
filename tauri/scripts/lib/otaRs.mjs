/**
 * Numbers the JavaScript side reads out of src-tauri/src/ota.rs, so the Rust
 * that defines them stays the only place they are written.
 *
 * Two readers today: the build stamps BUNDLE_REQUIRES into ota.json as the
 * native generation the page needs (vite.config.ts), and deploy-ota writes
 * NATIVE_GENERATION into apk.json as the generation the APK provides. Which
 * of the two belongs where is argued in the header of ota.rs, and getting it
 * backwards is the mistake that header records; this module only reads.
 *
 * The constant is matched as the literal `pub const NAME: u32 = <digits>;`,
 * and a file that no longer declares it that way is an error rather than a
 * zero or a guess: a manifest stamped with the wrong generation either locks
 * older apps out of every update or hands them a page that calls commands
 * they do not have.
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { ROOT } from './paths.mjs';

/** The Rust file the constants are read from. */
export const OTA_RS = join(ROOT, 'src-tauri/src/ota.rs');

/** The value of `pub const <name>: u32 = <n>;` in ota.rs (or the file given), or a throw naming it. */
export function rustU32Const(name, path = OTA_RS) {
  if (!/^[A-Z][A-Z0-9_]*$/.test(name)) throw new Error(`${name} is not the name of a Rust constant`);
  const source = readFileSync(path, 'utf8');
  const match = new RegExp(`pub const ${name}: u32 = (\\d+);`).exec(source);
  if (!match) throw new Error(`${path === OTA_RS ? 'src-tauri/src/ota.rs' : path} no longer declares ${name} as a literal`);
  return Number(match[1]);
}
