#!/usr/bin/env node
/**
 * ghostmarkdown.com's icons (landing/icons.svg, docs/LANDING.md): every Lucide icon the site's pages name, as one
 * sprite of <symbol>s, so a page draws one as `<svg class="i"><use href="icons.svg#i-folder"/></svg>` and asks nothing
 * of an icon host. Lucide is the app's own set (@glacier/icons proxies lucide-react), so the site's folder is the app's
 * folder.
 *
 *   node scripts/landing-icons.mjs
 *
 * The names are read from the pages themselves (every `icons.svg#i-<name>` in landing/*.html), so an icon added to a
 * page is in the sprite the next time this runs, and one no page uses any more leaves it. A name Lucide does not have
 * stops the run. The shapes are lucide-react's own data (`__iconData`); the strokes are the page's (.i in home.css).
 */
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const LANDING = join(ROOT, 'landing');
const ICONS = join(ROOT, 'node_modules', 'lucide-react', 'dist', 'esm', 'icons');

const names = new Set();
for (const file of readdirSync(LANDING).filter((name) => name.endsWith('.html'))) {
  for (const found of readFileSync(join(LANDING, file), 'utf8').matchAll(/icons\.svg#i-([a-z0-9-]+)/g)) names.add(found[1]);
}

const attrs = (props) =>
  Object.entries(props)
    .filter(([key]) => key !== 'key')
    .map(([key, value]) => `${key.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}="${String(value).replace(/"/g, '&quot;')}"`)
    .join(' ');

const symbols = [];
for (const name of [...names].sort()) {
  let data;
  try {
    ({ __iconData: data } = await import(pathToFileURL(join(ICONS, `${name}.mjs`)).href));
  } catch {
    console.error(`Lucide has no icon called "${name}".`);
    process.exit(1);
  }
  const shapes = data.node.map(([tag, props]) => `<${tag} ${attrs(props)}/>`).join('');
  symbols.push(`<symbol id="i-${name}" viewBox="0 0 24 24">${shapes}</symbol>`);
}

writeFileSync(
  join(LANDING, 'icons.svg'),
  `<svg xmlns="http://www.w3.org/2000/svg">\n<!-- Lucide (ISC), written by scripts/landing-icons.mjs from the names landing/*.html use. -->\n${symbols.join('\n')}\n</svg>\n`,
);
console.log(`landing/icons.svg: ${symbols.length} icons`);
