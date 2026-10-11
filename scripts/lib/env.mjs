/**
 * The deploy scripts' .env, for the scripts at the repository's root.
 *
 * There is one .env and it is the Tauri app's, tauri/.env: Vite reads its VITE_* keys from beside tauri/package.json,
 * and tauri/scripts/deploy-ota.mjs reads the box's address from the same file. So that is where these look too. A
 * .env at the repository's root is read instead when tauri/.env is absent, which is what a checkout that was pulled
 * across the move has until its .env is moved (git does not move an untracked file).
 *
 * The parse and the checks are tauri/scripts/lib/env.mjs's own.
 */
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { loadEnv as loadEnvAt } from '../../tauri/scripts/lib/env.mjs';
import { ROOT, TAURI } from './paths.mjs';

/** The .env, with every key in `required` present and not empty, or the deploy stops here naming what is missing. */
export function loadEnv(required) {
  return loadEnvAt(required, existsSync(join(TAURI, '.env')) || !existsSync(join(ROOT, '.env')) ? TAURI : ROOT);
}
