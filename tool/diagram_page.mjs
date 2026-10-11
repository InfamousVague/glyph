// What the diagram page (assets/diagrams/index.html, lib/editor/diagrams/) is handed that this repository does not
// write: Mermaid itself, the version tauri/ pins, with its licence, and the page's fonts as the web app declares
// them.
//
//     node tool/diagram_page.mjs tauri/
//
// - assets/diagrams/mermaid.min.js and MERMAID-LICENSE: tauri/node_modules/mermaid/dist/mermaid.min.js and its
//   LICENSE, byte for byte. The web app imports `mermaid` and Vite splits it into chunks; this is the same release
//   built as one file by Mermaid's own build.
// - assets/diagrams/fonts.css: the @font-face rules the web app loads (src/main.tsx, the kit's fonts.css and
//   src/app/typefaces.css), each kept as it is written there (family, style, weight, unicode-range) with its file
//   named as tool/fonts.py names the TrueType it makes of it in assets/fonts. A face the app does not ship as
//   TrueType is left out, as Flutter's own text has none for it either.
import { copyFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const glyph = process.argv[2] ?? join(here, '..', '..', 'glyph');
const modules = join(glyph, 'node_modules');
const out = join(here, '..', 'assets', 'diagrams');
const fonts = join(here, '..', 'assets', 'fonts');

copyFileSync(join(modules, 'mermaid', 'dist', 'mermaid.min.js'), join(out, 'mermaid.min.js'));
copyFileSync(join(modules, 'mermaid', 'LICENSE'), join(out, 'MERMAID-LICENSE'));
const version = JSON.parse(readFileSync(join(modules, 'mermaid', 'package.json'), 'utf8')).version;

/** The stylesheets the web app loads its faces from, in the order it loads them. */
const sheets = [
  '@fontsource-variable/inter/opsz.css',
  '@fontsource-variable/noto-sans/index.css',
  '@fontsource/ibm-plex-sans/index.css',
  '@fontsource/maple-mono/400.css',
  '@fontsource/maple-mono/500.css',
  '@fontsource/maple-mono/600.css',
  '@fontsource/maple-mono/700.css',
  '@fontsource/maple-mono/400-italic.css',
  '@fontsource/maple-mono/700-italic.css',
  '@fontsource-variable/fira-code/index.css',
];

/** A woff2's name as tool/fonts.py names the TrueType made of it, or null where it makes none. */
function ttfOf(woff2) {
  let m;
  if ((m = /^maple-mono-latin-(\d+)-(normal|italic)\.woff2$/.exec(woff2))) return `MapleMono-${m[1]}${m[2] === 'italic' ? '-Italic' : ''}.ttf`;
  if ((m = /^inter-([a-z-]+)-opsz-(normal|italic)\.woff2$/.exec(woff2))) return `InterVariable-${m[1]}${m[2] === 'italic' ? '-Italic' : ''}.ttf`;
  if ((m = /^fira-code-([a-z0-9-]+)-wght-normal\.woff2$/.exec(woff2))) return `FiraCodeVariable-${m[1]}.ttf`;
  if ((m = /^noto-sans-([a-z-]+)-wght-(normal|italic)\.woff2$/.exec(woff2))) return `NotoSansVariable-${m[1]}${m[2] === 'italic' ? '-Italic' : ''}.ttf`;
  if ((m = /^ibm-plex-sans-([a-z-]+)-(\d+)-normal\.woff2$/.exec(woff2))) return `IBMPlexSans-${m[1]}-${m[2]}.ttf`;
  return null;
}

const rules = [];
for (const sheet of sheets) {
  const css = readFileSync(join(modules, sheet), 'utf8');
  for (const face of css.matchAll(/@font-face\s*\{([^}]*)\}/g)) {
    const body = face[1];
    const woff2 = /url\(\.\/files\/([^)]+\.woff2)\)/.exec(body)?.[1];
    const ttf = woff2 ? ttfOf(woff2) : null;
    if (!ttf || !existsSync(join(fonts, ttf))) continue;
    const kept = body
      .split(';')
      .map((line) => line.trim())
      .filter((line) => line && !line.startsWith('src') && !line.startsWith('font-display'));
    // `block`, not the page's `swap`: a diagram is measured once, and must not be measured in a stand-in face.
    rules.push(`@font-face {\n  ${kept.join(';\n  ')};\n  font-display: block;\n  src: url(../fonts/${ttf}) format('truetype');\n}`);
  }
}
writeFileSync(
  join(out, 'fonts.css'),
  `/* Made by tool/diagram_page.mjs from the web app's own @font-face rules: not to be changed by hand. */\n${rules.join('\n')}\n`,
);
console.log(`mermaid ${version}, ${rules.length} faces`);
