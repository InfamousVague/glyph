#!/usr/bin/env node
// The clipper built into dist/chrome and dist/firefox (or the one named), ready to load unpacked:
//
//   node build.mjs                      both, for the live service (https://ghostmarkdown.com/api)
//   node build.mjs chrome --api=http://127.0.0.1:5555/api --out=e2e/out/ext     a local service, for tests and proofs
//
// The service's address is fixed at build time (`VITE_GLYPH_API`, which core/account/api.ts reads) and named in the
// manifest as the one host the clipper may reach. Only https, or a service on this computer, is accepted.
import { build } from 'esbuild';
import { copyFileSync, cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { manifest, RELEASE_API } from './src/manifest.ts';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const option = (name) => args.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3);
const targets = args.filter((a) => !a.startsWith('--'));
const api = (option('api') ?? process.env.CLIPPER_API ?? RELEASE_API).replace(/\/+$/, '');
const out = option('out') ?? join(here, 'dist');

const where = new URL(api);
if (!(where.protocol === 'https:' || (where.protocol === 'http:' && ['127.0.0.1', 'localhost'].includes(where.hostname)))) {
  console.error(`build: the service must be https, or on this computer; ${api} is neither.`);
  process.exit(2);
}

const { version } = JSON.parse(readFileSync(join(here, 'package.json'), 'utf8'));

for (const target of targets.length ? targets : ['chrome', 'firefox']) {
  if (target !== 'chrome' && target !== 'firefox') {
    console.error(`build: no such browser "${target}"`);
    process.exit(2);
  }
  const dir = join(out, target);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(join(dir, 'fonts'), { recursive: true });
  await build({
    entryPoints: { background: 'src/background.ts', content: 'src/content.ts', popup: 'src/popup/popup.ts' },
    absWorkingDir: here,
    outdir: dir,
    bundle: true,
    format: 'iife',
    target: target === 'chrome' ? 'chrome120' : 'firefox128',
    // Readable, so a store's reviewer reads what runs.
    minify: false,
    legalComments: 'inline',
    define: { 'import.meta.env.VITE_GLYPH_API': JSON.stringify(api) },
    logLevel: 'warning',
  });
  copyFileSync(join(here, 'src/popup/popup.html'), join(dir, 'popup.html'));
  copyFileSync(join(here, 'src/popup/popup.css'), join(dir, 'popup.css'));
  const inter = join(here, 'node_modules/@fontsource-variable/inter');
  copyFileSync(join(inter, 'files/inter-latin-wght-normal.woff2'), join(dir, 'fonts/inter-latin-wght-normal.woff2'));
  copyFileSync(join(inter, 'LICENSE'), join(dir, 'fonts/INTER-LICENSE.txt'));
  cpSync(join(here, 'icons'), join(dir, 'icons'), { recursive: true });
  writeFileSync(join(dir, 'manifest.json'), `${JSON.stringify(manifest(target, { api, version }), null, 2)}\n`);
  console.log(`build: ${dir} (${target}, ${api})`);
}
