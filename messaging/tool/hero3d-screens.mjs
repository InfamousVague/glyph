#!/usr/bin/env node
/**
 * Draws the page the hero's phone folds away with as a picture: site/art/hero/space-dark.webp and space-light.webp.
 *
 *   PLAYWRIGHT=<a node_modules folder with playwright in it> node tool/hero3d-screens.mjs
 *   node tool/hero3d-screens.mjs --check     fail if the pictures are older than what they are pictures of
 *
 * The phone's screens are the app in HTML, laid over the phone (site-src/hero3d). HTML cannot be folded, nor hidden
 * behind the phone it lies over, so for the moment the phone shuts with its screen still lit (Matt, 2026-11-27: "leave
 * the screen on and fold it inside the phone") the inner page becomes a picture of itself on the phone's own display.
 * This makes that picture from the same markup and the same styles the page uses (the inner screen's last view,
 * site-src/hero3d/views/space.html, on its glass as site/index.html has it), once for each theme, at twice the
 * app's size. Run it again whenever that view, its styles or the kit's change: --check, which needs no browser,
 * says when (it compares what the pictures were made from, kept beside them in space.json).
 *
 * Needs Playwright with its Chromium, and cwebp. Neither is fetched here.
 */
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const site = join(root, 'site');
const outDir = join(site, 'art', 'hero');
const VIEW = 'space';
const fail = (m) => { console.error(m); process.exit(1); };

// What the picture is of: the view's two panes, each on its screen's glass as the landing page has it.
const page = readFileSync(join(site, 'index.html'), 'utf8');
const view = readFileSync(join(root, 'site-src', 'hero3d', 'views', VIEW + '.html'), 'utf8').replace(/<!--[\s\S]*?-->\n?/g, '');
const starts = [...view.matchAll(/^<div class="gm h3-pane"[^>]*data-screen="([^"]+)"/gm)];
const pane = (screen) => {
  const i = starts.findIndex((m) => m[1] === screen);
  if (i < 0) fail(`${VIEW}.html has no pane for ${screen}`);
  return view.slice(starts[i].index, i + 1 < starts.length ? starts[i + 1].index : view.length).trim().replace('class="gm h3-pane"', 'class="gm h3-pane is-on"');
};
const glass = (screen) => {
  const m = page.match(new RegExp(`<div class="gm h3-screen" data-screen="${screen}">\\s*(<div class="h3-paper">.*)\\n<!-- H3:${screen} -->`));
  if (!m) fail(`site/index.html has no glass for ${screen}`);
  return m[1];
};
const styles = ['uplink.css', ...readdirSync(join(site, 'mock')).filter((f) => f.endsWith('.css')).sort().map((f) => 'mock/' + f)];
const body = ['inner-l', 'inner-r'].map((s) => `<div class="gm h3-screen" data-screen="${s}">${glass(s)}\n${pane(s)}</div>`).join('\n');
const html = (theme) => `<!doctype html><html lang="en"${theme === 'light' ? ' data-theme="light"' : ''}><head><meta charset="utf-8">
${styles.map((f) => `<link rel="stylesheet" href="/${f}">`).join('\n')}
<style>html,body{margin:0;background:#000}#shot{display:flex;width:836px;height:588px}
#shot .h3-screen{position:relative;flex:none;width:418px;height:588px}
#shot .h3-pane{position:absolute;inset:0;width:auto;height:auto;background:transparent}</style>
<script src="/mock/mock.js" defer></script></head><body><div id="shot">
${body}
</div></body></html>`;
const made = createHash('sha256').update(html('dark')).update(styles.map((f) => readFileSync(join(site, f), 'utf8')).join('\0')).update(readFileSync(join(site, 'mock', 'mock.js'), 'utf8')).digest('hex');
const notePath = join(outDir, VIEW + '.json');

if (process.argv.includes('--check')) {
  const ok = existsSync(notePath) && JSON.parse(readFileSync(notePath, 'utf8')).from === made && ['dark', 'light'].every((t) => existsSync(join(outDir, `${VIEW}-${t}.webp`)));
  if (!ok) fail(`site/art/hero/${VIEW}-*.webp are not pictures of the ${VIEW} view as it is now: run node tool/hero3d-screens.mjs`);
  console.log(`site/art/hero/${VIEW}-*.webp are current`);
  process.exit(0);
}

let chromium;
for (const from of [process.env.PLAYWRIGHT, join(root, 'build', 'hero3d', 'node_modules'), root].filter(Boolean)) {
  try { ({ chromium } = createRequire(join(from, 'x.js'))('playwright')); break; } catch { /* the next place */ }
}
if (!chromium) fail('No Playwright found: set PLAYWRIGHT to a node_modules folder that has it.');
if (spawnSync('cwebp', ['-version']).status !== 0) fail('No cwebp found.');

const types = { html: 'text/html', js: 'text/javascript', css: 'text/css', svg: 'image/svg+xml', ttf: 'font/ttf', webp: 'image/webp', png: 'image/png' };
mkdirSync(outDir, { recursive: true });
const work = mkdtempSync(join(tmpdir(), 'hero3d-screens-'));
const browser = await chromium.launch();
try {
  for (const theme of ['dark', 'light']) {
    const context = await browser.newContext({ viewport: { width: 900, height: 640 }, deviceScaleFactor: 2, colorScheme: theme });
    const tab = await context.newPage();
    const errors = [];
    tab.on('pageerror', (e) => errors.push(e.message));
    await tab.route('http://uplink.test/**', (route) => {
      const path = new URL(route.request().url()).pathname;
      if (path === '/') return route.fulfill({ status: 200, contentType: 'text/html', body: html(theme) });
      const file = join(site, path);
      if (!existsSync(file)) return route.fulfill({ status: 404, body: '' });
      route.fulfill({ status: 200, contentType: types[path.split('.').pop()] || 'application/octet-stream', body: readFileSync(file) });
    });
    await tab.goto('http://uplink.test/', { waitUntil: 'load' });
    await tab.evaluate(() => document.fonts.ready);
    await tab.waitForTimeout(900);
    if (errors.length) fail(`The ${theme} page threw: ${errors.join('; ')}`);
    const png = join(work, theme + '.png');
    await (await tab.$('#shot')).screenshot({ path: png });
    const out = join(outDir, `${VIEW}-${theme}.webp`);
    const webp = spawnSync('cwebp', ['-quiet', '-q', '92', '-m', '6', png, '-o', out]);
    if (webp.status !== 0) fail(`cwebp failed: ${webp.stderr}`);
    console.log(`${out}: ${(readFileSync(out).length / 1024).toFixed(0)} KB`);
    await context.close();
  }
} finally {
  await browser.close();
  rmSync(work, { recursive: true, force: true });
}
writeFileSync(notePath, JSON.stringify({ view: VIEW, from: made }) + '\n');
