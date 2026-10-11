// The web app's own press-and-hold band, drawn by Chromium, for lib/editor/band to be held against
// (test/editor/band/band_reference_test.dart). Each case is the web `ContextMenu` (tauri/src/app/editor/
// ContextMenu.tsx) over the base editor tool/editor_reference.mjs assembles, on a page 390 x 844 at two device pixels
// (or the case's own window), asked for as a press asks for it: a `contextmenu` on the editor.
//
// For each case it writes test/editor/band/fixtures/<name>.json:
//   caret   `view.coordsAtPos(head)`, where the band is asked for
//   menu    the band's layout box (offsetLeft/Top/Width/Height: its drawn box is smaller while it comes in)
//   row     the scrolling row: its rectangle, scroll width and place, which ends fade, its paper, rule and shadow
//   items   every row of the band: its word, rectangle (in the window, as scrolled), whether it is lit, its ink and
//           paper, its icon's and its word's rectangles, and the word's face
// and <name>.png, the band and the page round it.
//
//   node test/editor/band/fixtures/reference.mjs [name ...]      # the dev server of tauri/ at GLYPH_DEV
//
// Playwright is not this repository's: it is taken from the npx cache, as tool/editor_reference.mjs takes it.
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { writeFileSync } from 'node:fs';

const BASE = process.env.GLYPH_DEV ?? 'http://127.0.0.1:5272/';
const OUT = new URL('./', import.meta.url).pathname;

const DOC = 'First words of the note.\n\nBuy **oat** milk and some bread for the weekend.\n\n- [ ] Fix the login loop\n- [ ] Write it up\n\nlast words';
const LONG = 'Short.\n\nThe quick brown fox jumps over the lazy dog, then turns round and does it again for the sign-in page.';

/**
 * The cases. `top` is the room left above the editor; `inset` the status bar (`--app-inset-top`); `anchor`/`head` the
 * selection; `props` which of the menu's optional words it is given; `press` the rows pressed after it opens;
 * `scroll` where the band is scrolled to ('end').
 */
const CASES = [
  { name: 'caret', top: 200, head: 40 },
  { name: 'selection', top: 200, anchor: 26, head: 37 },
  { name: 'every', top: 200, anchor: 32, head: 35, props: ['comment', 'find', 'image', 'send'] },
  { name: 'every-end', top: 200, anchor: 32, head: 35, props: ['comment', 'find', 'image', 'send'], scroll: 'end' },
  { name: 'every-middle', top: 200, anchor: 32, head: 35, props: ['comment', 'find', 'image', 'send'], scroll: 120 },
  { name: 'task', top: 200, head: 86 },
  { name: 'style', top: 200, anchor: 56, head: 61, press: ['Style'] },
  { name: 'style-lit', top: 200, anchor: 32, head: 35, press: ['Style'] },
  { name: 'style-pressed', top: 200, anchor: 56, head: 61, press: ['Style', 'Italic', 'Quote'] },
  { name: 'style-end', top: 200, anchor: 32, head: 35, press: ['Style'], scroll: 'end' },
  { name: 'top-edge', top: 0, inset: 36, head: 5 },
  { name: 'under-header', top: 110, inset: 36, head: 5 },
  { name: 'short-window', top: 0, inset: 36, head: 5, window: { width: 390, height: 120 } },
  { name: 'wide-centre', top: 200, doc: 'long', head: 60, window: { width: 800, height: 600 }, readOnly: true },
  { name: 'wide-left', top: 200, doc: 'long', head: 0, window: { width: 800, height: 600 }, readOnly: true },
  { name: 'wide-right', top: 200, doc: 'long', head: 85, window: { width: 800, height: 600 }, readOnly: true },
];
for (const one of [...CASES]) if (['caret', 'selection', 'every', 'style', 'style-lit', 'style-pressed', 'task'].includes(one.name)) CASES.push({ ...one, name: `${one.name}-dark`, theme: 'dark' });

const only = process.argv.slice(2);
const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
await context.grantPermissions(['clipboard-read', 'clipboard-write']).catch(() => {});
const page = await context.newPage();
page.on('pageerror', (error) => console.log('page error:', error.message));
await page.route('**/__band_reference', (route) =>
  route.fulfill({
    contentType: 'text/html',
    body: '<!doctype html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body style="margin:0"><div id="stage"></div><div id="menu"></div></body></html>',
  }),
);
await page.goto(`${BASE}__band_reference`);

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
  const source = await (await fetch('/src/app/editor/Editor.tsx')).text();
  const dep = (name) => new RegExp(`from "([^"]*/deps/${name}\\.js[^"]*)"`).exec(source)[1];
  window.CM = {
    state: await import(/* @vite-ignore */ dep('@codemirror_state')),
    view: await import(/* @vite-ignore */ dep('@codemirror_view')),
    language: await import(/* @vite-ignore */ dep('@codemirror_language')),
  };
  window.Base = {
    language: await import('/src/app/editor/language.ts'),
    highlight: await import('/src/app/editor/glyphHighlight.ts'),
    lines: await import('/src/app/editor/glyphLines.ts'),
    extended: await import('/src/app/editor/extended.ts'),
    theme: await import('/src/app/editor/glyphTheme.ts'),
    viewMode: await import('/src/app/editor/viewMode.ts'),
    styles: (await import('/src/app/editor/markdown.module.css')).default,
  };
  window.Menu = await import('/src/app/editor/ContextMenu.tsx');
  window.Prefs = await import('/src/app/core/preferences.ts');
  await document.fonts.ready;
});

for (const one of CASES) {
  if (only.length && !only.includes(one.name)) continue;
  const size = one.window ?? { width: 390, height: 844 };
  await page.setViewportSize(size);
  const doc = one.doc === 'long' ? LONG : DOC;
  const result = await page.evaluate(
    async ({ one, doc, size }) => {
      const { React, ReactDOM, CM, Base, Menu, Prefs } = window;
      const wait = (ms) => new Promise((done) => setTimeout(done, ms));
      const theme = one.theme ?? 'light';
      Prefs.applyPreferences({ ...Prefs.DEFAULT_PREFERENCES, theme });
      if (one.inset) document.documentElement.style.setProperty('--app-inset-top', `${one.inset}px`);
      else document.documentElement.style.removeProperty('--app-inset-top');
      window.root?.unmount();
      window.madeView?.destroy();
      const stage = document.getElementById('stage');
      stage.replaceChildren();
      document.body.style.background = 'var(--glacier-bg)';
      const host = document.createElement('div');
      host.style.cssText = `inline-size: ${size.width}px; display: flex; flex-direction: column; margin-block-start: ${one.top}px;`;
      stage.append(host);
      const editorHost = document.createElement('div');
      editorHost.className = Base.styles.editor;
      editorHost.setAttribute('data-grow', 'true');
      editorHost.setAttribute('data-view', 'mixed');
      host.append(editorHost);
      const grow = CM.view.EditorView.theme({
        '&.cm-editor': { height: 'auto', minHeight: '100%', flex: '1 0 auto' },
        '&.cm-editor .cm-scroller': { overflowY: 'visible', overscrollBehavior: 'auto', flex: '1 0 auto' },
      });
      const readOnly = one.readOnly || false;
      const view = new CM.view.EditorView({
        parent: editorHost,
        state: CM.state.EditorState.create({
          doc,
          selection: { anchor: one.anchor ?? one.head, head: one.head },
          extensions: [
            Base.language.glyphMarkdown([]),
            CM.language.syntaxHighlighting(Base.highlight.glyphHighlight),
            Base.lines.glyphLines,
            Base.extended.extendedMarkdown(),
            CM.view.EditorView.lineWrapping,
            Base.theme.glyphTheme(theme === 'dark'),
            [CM.state.EditorState.readOnly.of(readOnly), CM.view.EditorView.editable.of(!readOnly)],
            Base.viewMode.noteView('mixed'),
            CM.state.Prec.highest(grow),
          ],
        }),
      });
      window.madeView = view;
      const has = (name) => (one.props ?? []).includes(name);
      window.root = ReactDOM.createRoot(document.getElementById('menu'));
      window.root.render(
        React.createElement(Menu.ContextMenu, {
          view,
          onAddImage: has('image') ? () => {} : undefined,
          onFind: has('find') ? () => {} : undefined,
          onComment: has('comment') ? () => {} : undefined,
          send: has('send') ? { label: 'Notion', run: () => {} } : null,
        }),
      );
      await wait(150);
      await document.fonts.ready;
      view.requestMeasure();
      await new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));
      view.dom.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 20, clientY: one.top + 20 }));
      await wait(250);
      const menu = () => document.querySelector('[role="menu"]');
      for (const label of one.press ?? []) {
        const button = [...menu().querySelectorAll('button')].find((b) => b.textContent === label);
        button.click();
        await wait(200);
      }
      const row = menu().firstElementChild;
      if (one.scroll === 'end') row.scrollLeft = row.scrollWidth;
      else if (typeof one.scroll === 'number') row.scrollLeft = one.scroll;
      // Past the menu's entrance and the styles' (260ms, 22ms apart).
      await wait(900);
      const rect = (r) => ({ left: +r.left.toFixed(3), top: +r.top.toFixed(3), right: +r.right.toFixed(3), bottom: +r.bottom.toFixed(3) });
      const el = menu();
      const rowStyle = getComputedStyle(row);
      const items = [...row.children].map((b) => {
        const style = getComputedStyle(b);
        const word = b.querySelector('span');
        const wordStyle = getComputedStyle(word);
        const icon = b.querySelector('svg');
        return {
          label: b.textContent,
          role: b.getAttribute('role'),
          name: b.getAttribute('aria-label'),
          lit: b.getAttribute('aria-checked') === 'true',
          group: b.hasAttribute('data-group'),
          rect: rect(b.getBoundingClientRect()),
          icon: rect(icon.getBoundingClientRect()),
          iconName: [...icon.classList].find((c) => c.startsWith('lucide-') && c !== 'lucide-icon')?.slice(7) ?? '',
          stroke: icon.getAttribute('stroke-width'),
          word: rect(word.getBoundingClientRect()),
          color: style.color,
          background: style.backgroundColor,
          borderLeft: `${style.borderLeftWidth} ${style.borderLeftColor}`,
          font: { family: wordStyle.fontFamily.split(',')[0].replace(/['"]/g, ''), size: parseFloat(wordStyle.fontSize), weight: wordStyle.fontWeight, lineHeight: wordStyle.lineHeight, letterSpacing: wordStyle.letterSpacing },
        };
      });
      const { head, from, to } = view.state.selection.main;
      const box = rect(el.getBoundingClientRect());
      return {
        doc,
        theme,
        window: size,
        top: one.top,
        inset: one.inset ?? 0,
        readOnly,
        props: one.props ?? [],
        press: one.press ?? [],
        scroll: one.scroll ?? null,
        anchor: one.anchor ?? one.head,
        head: one.head,
        selection: { from, to, head },
        text: view.state.doc.toString(),
        caret: rect(view.coordsAtPos(head)),
        label: el.getAttribute('aria-label'),
        menu: { left: el.offsetLeft, top: el.offsetTop, width: el.offsetWidth, height: el.offsetHeight, drawn: box },
        row: {
          rect: rect(row.getBoundingClientRect()),
          scrollWidth: row.scrollWidth,
          scrollLeft: row.scrollLeft,
          clientWidth: row.clientWidth,
          more: row.getAttribute('data-more') ?? '',
          background: rowStyle.backgroundColor,
          border: `${rowStyle.borderTopWidth} ${rowStyle.borderTopColor}`,
          radius: rowStyle.borderTopLeftRadius,
          shadow: rowStyle.boxShadow,
        },
        items,
        clip: { x: 0, y: Math.max(0, Math.floor(box.top - 40)), width: size.width, height: Math.min(size.height - Math.max(0, Math.floor(box.top - 40)), Math.ceil(box.bottom - box.top) + 110) },
      };
    },
    { one, doc, size },
  );
  const { clip, ...kept } = result;
  writeFileSync(`${OUT}${one.name}.json`, `${JSON.stringify(kept)}\n`);
  writeFileSync(`${OUT}${one.name}.png`, await page.screenshot({ clip }));
  console.log(one.name, kept.label, kept.items.map((i) => i.label).join(' | '), `at ${kept.menu.left},${kept.menu.top} ${kept.menu.width}x${kept.menu.height}`);
}

await browser.close();
