/**
 * Where things are, for the scripts at the repository's root: the ones that deploy what stayed here when the Tauri
 * app moved into tauri/ (docs/CUTOVER.md §5) - the service (server/), the connector (mcp/), the landing page
 * (landing/) and the Android app's release (build/cutover).
 *
 * Everything else these scripts share - the box's one login (box.mjs), run.mjs, say.mjs, the .env parser - is
 * imported from tauri/scripts/lib/, where deploy-ota.mjs and deploy-windows.mjs use the same files: one copy, so the
 * two sides cannot come to disagree about the shared connection.
 */
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

/** The repository root: the directory holding server/, mcp/, landing/, tauri/ and the Flutter app. */
export const ROOT = dirname(dirname(dirname(fileURLToPath(import.meta.url))));

/** The Tauri app: its package.json, its node_modules (esbuild and the connector's packages) and its .env. */
export const TAURI = join(ROOT, 'tauri');
