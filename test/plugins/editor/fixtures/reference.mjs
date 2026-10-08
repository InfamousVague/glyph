// The editor's side of the plugins on the web page, for test/plugins/editor: the web `Editor` itself (every
// extension in it) over a note of linked lines, with a stand-in mark-details provider registered in the page, its
// rows of pills, the quiet words at the ends of lines, the swipe's tile and the drawer measured. Nothing outside
// 127.0.0.1 is reached. Written beside the tests as fixtures/<name>.json and .png.
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { mkdirSync, writeFileSync } from 'node:fs';

const BASE = process.env.GLYPH_DEV ?? 'http://127.0.0.1:5279/';
const OUT = '/Users/matt/Development/Apps/ghost-flutter/test/plugins/editor/fixtures/';
mkdirSync(OUT, { recursive: true });

const T = (n) => `https://www.notion.so/Task-${String(n).repeat(32)}`;
const DOC = [
  '# Tasks',
  `- [ ] Buy milk [notion](${T(1)})`,
  `- [x] Call Sam [notion](${T(2)})`,
  `  - [ ] Nested one [notion](${T(3)})`,
  `- [ ] In the bin [notion](${T(4)})`,
  `- [ ] Being read [notion](${T(5)})`,
  `- [ ] Not read [notion](${T(6)})`,
  `Remember [the task](${T(1)}) tomorrow.`,
  `1. [ ] Numbered [notion](${T(7)})`,
  '- [ ] Plain to-do',
  '- [ ] Another plain one that is long enough to wrap onto a second line of the page',
  'last words',
].join('\n');

const CASES = [
  { name: 'rows', theme: 'light' },
  { name: 'rows-dark', theme: 'dark' },
  { name: 'open', theme: 'light', open: true },
  { name: 'open-dark', theme: 'dark', open: true },
  { name: 'menu', theme: 'light', menu: 'ready' },
  { name: 'menu-dark', theme: 'dark', menu: 'ready' },
  { name: 'menu-unread', theme: 'light', menu: 'unread' },
  { name: 'swipe', theme: 'light', swipe: -60 },
  { name: 'swipe-armed', theme: 'light', swipe: -150 },
  { name: 'swipe-armed-dark', theme: 'dark', swipe: -150 },
  { name: 'swipe-busy', theme: 'light', swipe: -150, release: true },
];

const only = process.argv.slice(2);
const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
const page = await context.newPage();
page.on('pageerror', (error) => console.log('page error:', error.message));
await page.route('**/*', (route) => (new URL(route.request().url()).hostname === '127.0.0.1' ? route.fallback() : route.abort()));
await page.route('**/__editor_reference', (route) =>
  route.fulfill({
    contentType: 'text/html',
    body: '<!doctype html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body style="margin:0"><div id="stage"></div></body></html>',
  }),
);
await page.goto(`${BASE}__editor_reference`);
await page.evaluate(async () => {
  window.$RefreshReg$ = () => {};
  window.$RefreshSig$ = () => (type) => type;
  window.__vite_plugin_react_preamble_installed__ = true;
  const main = await (await fetch('/src/main.tsx')).text();
  for (const found of main.matchAll(/^import "([^"]+\.css)";/gm)) await import(/* @vite-ignore */ found[1]);
  const react = /from "([^"]*\/deps\/react\.js[^"]*)"/.exec(main)[1];
  const dom = /from "([^"]*\/deps\/react-dom_client\.js[^"]*)"/.exec(main)[1];
  window.React = (await import(/* @vite-ignore */ react)).default;
  window.ReactDOM = (await import(/* @vite-ignore */ dom)).default;
  window.EditorModule = await import('/src/app/editor/Editor.tsx');
  window.MenuModule = await import('/src/app/editor/MarkMenu.tsx');
  window.Marks = await import('/src/app/core/markDetails.ts');
  window.Prefs = await import('/src/app/core/preferences.ts');
  await document.fonts.ready;
});

for (const one of CASES) {
  if (only.length && !only.includes(one.name)) continue;
  await page.emulateMedia({ reducedMotion: 'reduce' });
  const result = await page.evaluate(
    async ({ one, doc }) => {
      const { React, ReactDOM, EditorModule, MenuModule, Marks, Prefs } = window;
      const T = (n) => `https://www.notion.so/Task-${String(n).repeat(32)}`;
      const ready = (n, title, status, brief, more = {}) => ({ state: 'ready', loading: false, details: { url: T(n), title, status, brief, fields: [{ label: 'Status', value: status?.label ?? '' }, { label: 'Priority', value: 'P1' }, { label: 'Due', value: 'Sep 20' }, { label: 'Owner', value: 'Sam' }], editedAt: null, readAt: Date.now(), ...more } });
      const known = new Map([
        [T(1), ready(1, 'Buy oat milk', { label: 'In progress', stage: 'doing' }, ['P1', 'Overdue by 2 days'])],
        [T(2), ready(2, 'Call Sam', { label: 'Done', stage: 'done' }, ['Due Sep 20'])],
        [T(3), ready(3, 'Nested one', { label: '', stage: 'todo' }, [])],
        [T(4), ready(4, 'In the bin', null, ['P1'], { gone: true })],
        [T(5), { state: 'loading' }],
        [T(6), { state: 'failed', message: 'Notion said no.' }],
      ]);
      if (one.menu === 'unread') known.clear();
      Marks.provideMarkDetails('notion', () => ({
        peek: (url) => known.get(url) ?? null,
        want: () => undefined,
        open: async () => undefined,
        reads: (url) => url.includes('notion.so/'),
        actions: (url) => (known.get(url)?.state === 'ready' ? [
          { id: 'done', label: 'Mark done in Notion', icon: 'done', busyLabel: 'Marking done…', run: async () => undefined },
          { id: 'rename', label: 'Use these words as its title', icon: 'rename', busyLabel: 'Renaming…', run: async () => undefined },
        ] : []),
      }));
      const theme = one.theme ?? 'light';
      Prefs.applyPreferences({ ...Prefs.DEFAULT_PREFERENCES, theme, noteFace: one.noteFace ?? Prefs.DEFAULT_PREFERENCES.noteFace });
      window.root?.unmount();
      window.root = null;
      document.querySelectorAll('.cm-linkMenu').forEach((el) => el.remove());
      const stage = document.getElementById('stage');
      stage.replaceChildren();
      document.body.style.background = 'var(--glacier-bg)';
      const host = document.createElement('div');
      host.style.cssText = 'inline-size: 390px; display: flex; flex-direction: column;';
      stage.append(host);
      let view = null;
      const wait = (ms) => new Promise((done) => setTimeout(done, ms));
      const frames = () => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));
      const strip = (c) => c.replace(/^_|_[a-z0-9]+_\d+$/gi, '');
      const origin = { left: 0, top: 0 };
      const rect = (r) => ({ left: +(r.left - origin.left).toFixed(3), top: +(r.top - origin.top).toFixed(3), right: +(r.right - origin.left).toFixed(3), bottom: +(r.bottom - origin.top).toFixed(3) });
      const part = (el) => {
        const at = getComputedStyle(el);
        const attrs = {};
        for (const attr of el.attributes) if (attr.name !== 'class' && attr.name !== 'style') attrs[attr.name] = attr.value;
        return { classes: [...el.classList].map(strip), tag: el.tagName.toLowerCase(), text: el.textContent, attrs, rect: rect(el.getBoundingClientRect()), color: at.color, background: at.backgroundColor, border: at.borderTopColor, borderWidth: at.borderTopWidth, borderStyle: at.borderTopStyle, size: parseFloat(at.fontSize), weight: at.fontWeight, family: at.fontFamily.split(',')[0].replace(/['"]/g, ''), decoration: at.textDecorationLine, opacity: at.opacity, letterSpacing: at.letterSpacing, textWidth: (() => { const r = document.createRange(); r.selectNodeContents(el); return +r.getBoundingClientRect().width.toFixed(3); })(), shadow: at.boxShadow, transform: el.style.transform };
      };

      if (one.menu) {
        // The drawer by itself, as editor/markMenuMount.tsx mounts it.
        window.root = ReactDOM.createRoot(host);
        window.root.render(React.createElement(MenuModule.MarkMenu, { name: 'notion', url: T(1), words: 'Buy milk', say: () => {}, close: () => {}, unlink: () => {} }));
        await wait(300);
        await document.fonts.ready;
        await frames();
        const dialog = document.querySelector('[role="dialog"]');
        const parts = [part(dialog), ...[...dialog.querySelectorAll('*')].filter((el) => !(el instanceof SVGElement) || el.tagName === 'svg').map(part)];
        return { theme, menu: one.menu, label: dialog.getAttribute('aria-label'), parts, clip: { x: 0, y: 0, width: 390, height: 844 } };
      }

      window.root = ReactDOM.createRoot(host);
      window.root.render(
        React.createElement(EditorModule.Editor, {
          value: doc,
          onChange: () => {},
          dark: theme === 'dark',
          assist: false,
          display: 'mixed',
          readOnly: false,
          grow: true,
          linkMenus: { say: () => {} },
          suggest: (body) => body.split('\n').map((text, index) => ({ text, line: index + 1 })).filter(({ text }) => /^\s*(?:[-*+]|\d+[.)])\s\[ \]\s/.test(text) && !text.includes('](')).map(({ line }) => ({ line, label: 'Notion', busyLabel: 'Sending', run: () => new Promise(() => {}) })),
          swipeAction: () => ({ label: 'Send to Notion', busyLabel: 'Sending…', run: () => new Promise(() => {}) }),
          onView: (made) => {
            view = made;
          },
        }),
      );
      await wait(200);
      await document.fonts.ready;
      await wait(250);
      view.requestMeasure();
      await frames();
      await frames();

      let swiped = null;
      if (one.swipe) {
        const line = [...view.contentDOM.querySelectorAll('.cm-line')].find((el) => el.textContent.startsWith('- [ ] Plain to-do') || el.textContent.includes('Plain to-do'));
        const box = line.getBoundingClientRect();
        const y = box.top + box.height / 2;
        const fire = (type, x) => line.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y, button: 0, pointerId: 7, pointerType: 'touch' }));
        fire('pointerdown', 320);
        fire('pointermove', 320 - 20);
        fire('pointermove', 320 + one.swipe);
        if (one.release) fire('pointerup', 320 + one.swipe);
        await frames();
        await wait(one.release ? 300 : 30);
        swiped = { lineWidth: line.offsetWidth, lineRect: rect(line.getBoundingClientRect()), transform: line.style.transform, lineFrom: view.posAtDOM(line, 0) };
      }
      if (one.open) {
        document.querySelector('.cm-linkRow .cm-linkPill').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
        await wait(300);
        await frames();
      }

      const lines = [];
      const rows = [];
      for (const el of view.contentDOM.children) {
        const box = rect(el.getBoundingClientRect());
        if (el.classList.contains('cm-linkRow')) {
          const attrs = {};
          for (const attr of el.attributes) if (attr.name !== 'class') attrs[attr.name] = attr.value;
          rows.push({ rect: box, attrs, after: lines.length ? lines[lines.length - 1].from : null, pills: [...el.querySelectorAll('.cm-linkPill')].map(part), stages: [...el.querySelectorAll('.cm-linkStage')].map(part) });
          continue;
        }
        if (!el.classList.contains('cm-line')) continue;
        const from = view.posAtDOM(el, 0);
        const line = view.state.doc.lineAt(from);
        lines.push({ from: line.from, to: line.to, text: line.text, classes: [...el.classList].filter((c) => c !== 'cm-line').map(strip), rect: box });
      }
      const suggests = [...view.contentDOM.querySelectorAll('.cm-suggest')].map((el) => ({ ...part(el), pos: view.posAtDOM(el) }));
      const tile = view.scrollDOM.querySelector('.cm-swipeItem');
      const dialog = document.querySelector('[role="dialog"]');
      return {
        doc,
        theme,
        noteFace: one.noteFace ?? 'maple',
        width: 390,
        lines,
        rows,
        suggests,
        swiped,
        tile: tile ? part(tile) : null,
        dialog: dialog ? { label: dialog.getAttribute('aria-label'), rect: rect(dialog.getBoundingClientRect()) } : null,
        clip: { x: 0, y: 0, width: 390, height: one.open ? 844 : Math.min(844, Math.ceil(view.dom.getBoundingClientRect().bottom)) },
      };
    },
    { one, doc: DOC },
  );
  const { clip, ...kept } = result;
  writeFileSync(`${OUT}${one.name}.json`, `${JSON.stringify(kept)}\n`);
  writeFileSync(`${OUT}${one.name}.png`, await page.screenshot({ clip }));
  console.log(one.name, kept.lines ? `${kept.lines.length} lines, ${kept.rows.length} rows, ${kept.suggests.length} words` : `${kept.parts.length} parts`);
}
await browser.close();
