/**
 * Where the repository is, for every script under scripts/.
 *
 * Twelve scripts each worked it out from their own file with
 * `dirname(dirname(fileURLToPath(import.meta.url)))`, which is right only as
 * long as the script sits directly in scripts/: move one into a folder and it
 * quietly reads package.json, .env and dist/ from the wrong place. Worked out
 * once here instead, from this file's own position, so a script can live at
 * any depth and still name the same root.
 */
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * The Tauri app's root: the directory holding package.json. Since the repository's root became the Flutter app
 * (docs/CUTOVER.md §5 there) this is `tauri/`, not the repository: every script under tauri/scripts/ still reads
 * package.json, .env, dist/ and src-tauri/ from here.
 */
export const ROOT = dirname(dirname(dirname(fileURLToPath(import.meta.url))));

/**
 * The repository: one up. The service (server/), the connector (mcp/), the landing page (landing/) and the scripts
 * that deploy them (scripts/) stayed there when this tree moved into tauri/.
 */
export const REPO = dirname(ROOT);
