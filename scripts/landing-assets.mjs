#!/usr/bin/env node
/**
 * What ghostmarkdown.com carries of the kit and the app (landing/, docs/LANDING.md), copied in beside its pages so the
 * site is still one directory the deploy tars whole:
 *
 * - Glacier's tokens (`@glacier/tokens` tokens.css): the type scale, spacing, radii, motion, shadows and the three named
 *   themes the app offers, Dawn, Boreal and Ember. The site is drawn from them, as the app is.
 * - The kit's two faces, Inter and JetBrains Mono, as the variable Latin files: served from the site itself, so a visit
 *   asks nothing of a font host.
 *
 *   node scripts/landing-assets.mjs
 *
 * Run after the kit changes, and commit what it writes. The screens are scripts/landing-shots.mjs's.
 */
import { copyFileSync, mkdirSync, rmSync } from 'node:fs';
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
// The page wears no ghosts since 2026-10-01 (Matt: "Remove the two ghost mascot images from the website towards the
// bottom"): a copy left from before goes.
rmSync(join(LANDING, 'ghosts'), { recursive: true, force: true });
