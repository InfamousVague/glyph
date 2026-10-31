#!/usr/bin/env node
/*
 * ghost-publish (publish/README.md): runs the built bundle, dist/ghost-publish.js, and builds it first when it is not
 * there and this is the repository (vite is beside us in tauri/node_modules). A vendored copy ships with its dist/.
 */
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const bundle = join(here, '..', 'dist', 'ghost-publish.js');

if (!existsSync(bundle)) {
  const tauri = join(here, '..', '..');
  const vite = join(tauri, 'node_modules', '.bin', 'vite');
  if (!existsSync(vite)) {
    console.error(`ghost-publish: the bundle at ${bundle} is missing, and there is no vite to build it. From tauri/: npm install, then vite build --config publish/vite.config.ts`);
    process.exit(1);
  }
  console.error('ghost-publish: building the bundle first…');
  const made = spawnSync(vite, ['build', '--config', 'publish/vite.config.ts'], { cwd: tauri, stdio: 'inherit' });
  if (made.status !== 0) process.exit(made.status ?? 1);
}

process.env.GHOST_PUBLISH_MAIN = '1';
await import(pathToFileURL(bundle).href);
