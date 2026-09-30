#!/usr/bin/env node
/**
 * What ghostmarkdown.com carries of the kit and the app (landing/, docs/LANDING.md), copied in beside its pages so the
 * site is still one directory the deploy tars whole:
 *
 * - Glacier's tokens (`@glacier/tokens` tokens.css): the type scale, spacing, radii, motion, shadows and the three named
 *   themes the app offers, Dawn, Boreal and Ember. The site is drawn from them, as the app is.
 * - The kit's two faces, Inter and JetBrains Mono, as the variable Latin files: served from the site itself, so a visit
 *   asks nothing of a font host.
 * - The app's ghosts (src/app/art/ghosts), which are masks: the site paints them in its own ink, light or dark.
 *
 *   node scripts/landing-assets.mjs
 *
 * Run after the kit or the ghosts change, and commit what it writes. The screens are scripts/landing-shots.mjs's.
 */
import { copyFileSync, mkdirSync, readdirSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const LANDING = join(ROOT, 'landing');
const copy = (from, to) => {
  mkdirSync(dirname(join(LANDING, to)), { recursive: true });
  copyFileSync(join(ROOT, from), join(LANDING, to));
  console.log(`landing/${to}`);
};

copy('node_modules/@glacier/tokens/css/tokens.css', 'glacier/tokens.css');
copy('node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2', 'fonts/inter.woff2');
copy('node_modules/@fontsource-variable/jetbrains-mono/files/jetbrains-mono-latin-wght-normal.woff2', 'fonts/jetbrains-mono.woff2');
// The ghosts the home page wears (home.css `.ghost-*`), and no more: each is a large mask, and the site stays small.
const GHOSTS = ['signed-out-not-syncing', 'an-update-is-ready'];
rmSync(join(LANDING, 'ghosts'), { recursive: true, force: true });
for (const file of readdirSync(join(ROOT, 'src/app/art/ghosts'))) {
  const name = file.replace(/^\d+-/, '').replace(/\.webp$/, '');
  if (GHOSTS.includes(name)) copy(`src/app/art/ghosts/${file}`, `ghosts/${name}.webp`);
}
