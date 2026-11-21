#!/usr/bin/env node
// The extension built into dist/chrome (or dist/firefox), ready to load unpacked:
//
//   node build.mjs                       chrome, for the live hub (wss://gogho.st/hub)
//   node build.mjs chrome --hub=wss://127.0.0.1:8787/hub --out=.verify/ext   a local relay, for tests
//
// The hub is fixed at build time (`__GHOST_HUB__`, which ghost/relay.ts reads). Only wss, or a relay on this
// computer, is accepted.
import { build } from 'esbuild';
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { existsSync } from 'node:fs';
import { manifest, RELEASE_HUB } from './src/manifest.ts';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const option = (name) => args.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3);
const targets = args.filter((a) => !a.startsWith('--'));
const hub = (option('hub') ?? process.env.GHOST_HUB ?? RELEASE_HUB).replace(/\/+$/, '');
const out = option('out') ?? join(here, 'dist');

const where = new URL(hub);
if (!(where.protocol === 'wss:' || (where.protocol === 'ws:' && ['127.0.0.1', 'localhost'].includes(where.hostname)))) {
  console.error(`build: the hub must be wss, or on this computer; ${hub} is neither.`);
  process.exit(2);
}

const { version } = JSON.parse(readFileSync(join(here, 'package.json'), 'utf8'));

for (const target of targets.length ? targets : ['chrome']) {
  if (target !== 'chrome' && target !== 'firefox') {
    console.error(`build: no such browser "${target}"`);
    process.exit(2);
  }
  const dir = join(out, target);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  await build({
    entryPoints: { background: 'src/background.ts', popup: 'src/popup/popup.ts' },
    absWorkingDir: here,
    outdir: dir,
    bundle: true,
    format: 'iife',
    target: target === 'chrome' ? 'chrome120' : 'firefox128',
    minify: false, // readable, so a store reviewer reads what runs
    legalComments: 'inline',
    define: { __GHOST_HUB__: JSON.stringify(hub) },
    logLevel: 'warning',
  });
  writeFileSync(join(dir, 'popup.html'), readFileSync(join(here, 'src/popup/popup.html')));
  writeFileSync(join(dir, 'popup.css'), readFileSync(join(here, 'src/popup/popup.css')));
  if (existsSync(join(here, 'icons'))) cpSync(join(here, 'icons'), join(dir, 'icons'), { recursive: true });
  writeFileSync(join(dir, 'manifest.json'), `${JSON.stringify(manifest(target, { version }), null, 2)}\n`);
  console.log(`build: ${dir} (${target}, ${hub})`);
}
