/**
 * The deploy scripts' .env: the box's address and account, and the few
 * secrets that travel with a deploy.
 *
 * Read into an object of its own rather than into process.env, which is what
 * a dotenv package or Node's --env-file would do: every child a deploy spawns
 * inherits process.env, and the box password is meant to reach exactly one
 * of them, sshpass, through SSHPASS (box.mjs). A key that is missing stops
 * the deploy here, by name, before anything is built.
 *
 * The parse was copied into three deploy scripts and is kept exactly: an
 * optional `export`, NAME=value, one pair of surrounding quotes stripped,
 * and nothing else interpreted - no escapes, no ${} expansion, no comments
 * after a value.
 */
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { ROOT } from './paths.mjs';
import { fail } from './say.mjs';

/** NAME=value pairs from the text of a .env file. Lines that are not one are ignored. */
export function parseEnv(text) {
  const env = {};
  for (const line of text.split('\n')) {
    const match = /^\s*(?:export\s+)?([A-Z0-9_]+)\s*=\s*(.*)\s*$/.exec(line);
    if (match) env[match[1]] = match[2].trim().replace(/^['"]|['"]$/g, '');
  }
  return env;
}

/**
 * The repository's .env, with every key in `required` present and not empty,
 * or the deploy stops here naming what is missing.
 */
export function loadEnv(required, root = ROOT) {
  const path = join(root, '.env');
  if (!existsSync(path)) fail(`No .env at ${path} (needs ${required.join(' / ')}).`);
  const env = parseEnv(readFileSync(path, 'utf8'));
  for (const key of required) {
    if (!env[key]) fail(`.env is missing ${key}.`);
  }
  return env;
}
