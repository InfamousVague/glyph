// The web app's own note screen, drawn by Chromium, for lib/note to be held against (test/note/note_frame_test.dart).
// A seeded note is opened from the home page at 390 x 844 and at 840 x 900, two device pixels to the logical one, and
// the rectangles of the bar's tools, the header pane, the page, the byline, the editor's first lines and, with More
// pressed, every block of the sheet are written to test/note/reference/note_<size>.json, with a picture of each in
// light and dark beside them.
//
//   (cd tauri && npx vite --port 5273 --strictPort --host 127.0.0.1) &     # read-only: never `vite build` there
//   node test/note/reference/note_reference.mjs
//
// Playwright is not this repository's: it is taken from the npx cache, as tool/editor_reference.mjs takes it.
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { writeFileSync } from 'node:fs';

const BASE = process.env.GLYPH_DEV ?? 'http://127.0.0.1:5273/';
const OUT = new URL('./', import.meta.url).pathname;
const NOW = Date.UTC(2026, 9, 7, 12, 0, 0);

export const BODY = [
  '---',
  'authors: matt, Claude',
  '---',
  '# Trip to Lisbon',
  '',
  'Pack the **charger** and the _good_ shoes.',
  '',
  '- [ ] Book the tram',
  '- [x] Print tickets',
  '',
  'A longer paragraph of words that runs on past the edge of a phone so that it wraps onto a second line at least.',
].join('\n');

const NOTES = [
  { id: 'lisbon', body: BODY, createdAt: NOW - 86400000, updatedAt: NOW - 3600000, source: 'editor', starred: false, archivedAt: null, revision: 1 },
  { id: 'plain', body: '# Plain\n\nwords', createdAt: NOW - 86400000 * 2, updatedAt: NOW - 7200000, source: 'editor', starred: false, archivedAt: null, revision: 1 },
];

const rect = (r) => ({ x: r.x, y: r.y, w: r.width, h: r.height });

async function measure(browser, size, theme, shots) {
  const context = await browser.newContext({ viewport: size, deviceScaleFactor: 2, colorScheme: theme, hasTouch: size.width < 600, isMobile: false });
  await context.addInitScript(
    ([notes, theme]) => {
      if (localStorage.getItem('glyph-notes')) return;
      localStorage.setItem('glyph-notes', JSON.stringify(notes));
      localStorage.setItem('glyph-preferences', JSON.stringify({ theme, tagNewNotes: false }));
      localStorage.setItem('glyph-sample-note', '1');
      localStorage.setItem('glyph-account-gate-seen', '1');
      localStorage.setItem('glyph-guide-seen', '1');
    },
    [NOTES, theme],
  );
  const page = await context.newPage();
  await page.goto(BASE);
  await page.getByText('Trip to Lisbon').first().waitFor({ timeout: 20000 });
  await page.waitForTimeout(2500);
  await page.getByText('Trip to Lisbon').first().click();
  await page.locator('.cm-content').first().waitFor({ timeout: 10000 });
  await page.waitForTimeout(1200);
  const frame = await page.evaluate(() => {
    const r = (el) => {
      if (!el) return null;
      const b = el.getBoundingClientRect();
      return { x: b.x, y: b.y, w: b.width, h: b.height };
    };
    const q = (sel) => document.querySelector(sel);
    const all = (sel) => [...document.querySelectorAll(sel)];
    const cls = (part) => `[class*="${part}"]`;
    const pageEl = q(cls('NoteScreen_page') + ',' + cls('_page_'));
    const style = pageEl ? getComputedStyle(pageEl) : null;
    return {
      root: { tabs: document.documentElement.dataset.tabs, split: document.documentElement.dataset.split, platform: document.documentElement.dataset.platform, topbar: document.documentElement.dataset.topbar },
      safeTop: getComputedStyle(document.documentElement).getPropertyValue('--app-safe-top'),
      header: r(q('header.app-headerPane')),
      page: r(pageEl),
      pagePaddingTop: style?.paddingTop,
      wispUnder: pageEl ? getComputedStyle(pageEl).getPropertyValue('--wisp-under') : null,
      tools: all('button' + cls('cog')).map((b) => ({ label: b.getAttribute('aria-label'), tool: b.dataset.tool ?? null, on: b.dataset.on ?? null, rect: r(b), icon: r(b.querySelector('svg')), color: getComputedStyle(b).color })),
      toolsBox: r(q(cls('_tools_'))),
      byline: r(q('p[aria-label^="Written by"]')),
      bylineMarks: all('p[aria-label^="Written by"] span[title]').map((m) => ({ title: m.title, rect: r(m) })),
      bylineNames: r(q('p[aria-label^="Written by"] > span:last-child')),
      editor: r(q('.cm-editor')),
      scroller: r(q('.cm-scroller')),
      content: r(q('.cm-content')),
      lines: all('.cm-line').map((l) => ({ text: l.textContent, rect: r(l) })),
      body: all(cls('_body_')).map((b) => ({ hidden: b.hidden, rect: r(b) })),
    };
  });
  if (shots) await page.screenshot({ path: `${OUT}web-note-${size.width}-${theme}.png` });
  await page.getByLabel('More for this note').click();
  await page.waitForTimeout(900);
  const sheet = await page.evaluate(() => {
    const r = (el) => {
      const b = el.getBoundingClientRect();
      return { x: b.x, y: b.y, w: b.width, h: b.height };
    };
    const dialog = document.querySelector('[role="dialog"]');
    const blocks = [];
    for (const el of dialog.children) {
      const name = [...el.classList].map((c) => c.replace(/^_/, '').replace(/_[^_]+_\d+$/, '').replace(/_.*$/, '')).join(' ');
      const rows = [...el.children].map((row) => ({
        text: (row.querySelector('[class*="_label_"]')?.firstChild?.textContent ?? row.textContent ?? '').trim().slice(0, 60),
        hint: row.querySelector('[class*="_hint_"]')?.textContent ?? null,
        rect: r(row),
        icon: row.querySelector('[class*="_icon_"]') ? r(row.querySelector('[class*="_icon_"]')) : null,
        label: row.querySelector('[class*="_label_"]') ? r(row.querySelector('[class*="_label_"]')) : null,
      }));
      blocks.push({ tag: el.tagName, cls: name, text: el.children.length ? null : el.textContent, rect: r(el), rows: el.matches('[class*="_group_"]') ? rows : undefined });
    }
    const choice = dialog.querySelector('[role="radiogroup"]');
    return { dialog: r(dialog), scrollHeight: dialog.scrollHeight, blocks, look: choice ? { box: r(choice), options: [...choice.children].map((b) => ({ text: b.textContent, on: b.dataset.on ?? null, rect: r(b) })) } : null };
  });
  if (shots) await page.screenshot({ path: `${OUT}web-sheet-${size.width}-${theme}.png` });
  await context.close();
  return { size, frame, sheet };
}

const browser = await chromium.launch();
for (const size of [{ width: 390, height: 844 }, { width: 840, height: 900 }]) {
  const light = await measure(browser, size, 'light', true);
  await measure(browser, size, 'dark', true);
  writeFileSync(`${OUT}note_${size.width}.json`, JSON.stringify({ body: BODY, ...light }, null, 1));
  console.log(size.width, 'written');
}
await browser.close();
