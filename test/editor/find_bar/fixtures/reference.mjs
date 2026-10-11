// The web app's own find bar, drawn by Chromium over its own editor, for the Flutter one to be held against
// (test/editor/find_bar/reference_test.dart). Modelled on tool/editor_reference.mjs: a page 390 x 844 at two device
// pixels to the logical one, the editor's box at the page's corner (the BASE editor of that file, with find.ts's
// `findExtension()` added) and ../glyph/src/app/editor/FindBar.tsx mounted over it, resting on the page's foot.
//
// For each case it writes test/editor/find_bar/fixtures/<name>.json:
//   bar       the bar's rectangle, its ground and its hairline
//   rows      each row's rectangle
//   controls  every control by name (find, count, previous, next, replace, done, replaceWith, replaceOne, all, said):
//             its rectangle, its words, ink, ground, border, size and weight, whether it is disabled, its icon's box
//             and a field's placeholder ink
//   marks     every `.cm-findMatch` / `.cm-findCurrent` span in the note: its document range, whether it is the
//             current one, its client rects, its ground and its ink
//   lines     every `.cm-line`'s rectangle, to know the note was laid out the same before the marks are compared
// and <name>.png, the picture of the whole page.
//
//   node test/editor/find_bar/fixtures/reference.mjs [name ...]      # GLYPH_DEV=http://127.0.0.1:5272/ by default
//
// The dev server is ../glyph's own (`npx vite --port 5272 --strictPort --host 127.0.0.1`), read-only: never built.
// Playwright is not this repository's: it is taken from the npx cache, as tool/editor_reference.mjs takes it.
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { writeFileSync } from 'node:fs';

const BASE = process.env.GLYPH_DEV ?? 'http://127.0.0.1:5272/';
const OUT = new URL('./', import.meta.url).pathname;

/** The note searched: a heading, plain words in two cases, a bold run, an item, and a match that wraps a line. */
const DOC = '# Milk run\n\nmilk, eggs, Milk and more milk.\n\n- buy **milk** today\n- oat milk too\n\nThe quick brown fox jumps over the lazy dog and brings milk home.\n\nlast';

/** The cases: the words the bar opens on, then what is done to it. */
const CASES = [
  { name: 'empty', initial: '' },
  { name: 'matches', initial: 'milk' },
  { name: 'stepped', initial: 'milk', steps: [['click', 'Next match'], ['click', 'Next match'], ['click', 'Next match']] },
  { name: 'none', initial: 'bread' },
  { name: 'replace', initial: 'milk', steps: [['click', 'Replace']] },
  { name: 'replace-typed', initial: 'milk', steps: [['click', 'Replace'], ['fill', 'Replace with', 'cream'], ['focus', 'Find']] },
  { name: 'replaced-all', initial: 'eggs', steps: [['click', 'Replace'], ['fill', 'Replace with', 'ham'], ['clickText', 'All']] },
  { name: 'wide', initial: 'fox jumps over the lazy' },
];
for (const one of [...CASES]) CASES.push({ ...one, name: `${one.name}-dark`, theme: 'dark' });

const only = process.argv.slice(2);
const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
const page = await context.newPage();
page.on('pageerror', (error) => console.log('page error:', error.message));
await page.route('**/__find_reference', (route) =>
  route.fulfill({
    contentType: 'text/html',
    body: '<!doctype html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body style="margin:0"><div id="stage"></div><div id="over"></div></body></html>',
  }),
);
await page.goto(`${BASE}__find_reference`);

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
  window.Find = await import('/src/app/editor/find.ts');
  window.Bar = await import('/src/app/editor/FindBar.tsx');
  window.Prefs = await import('/src/app/core/preferences.ts');
  await document.fonts.ready;
});

const settle = () => page.evaluate(() => new Promise((done) => setTimeout(() => requestAnimationFrame(() => requestAnimationFrame(done)), 260)));

for (const one of CASES) {
  if (only.length && !only.includes(one.name)) continue;
  await page.evaluate(
    async ({ one, doc }) => {
      const { React, ReactDOM, CM, Base, Find, Bar, Prefs } = window;
      const theme = one.theme ?? 'light';
      Prefs.applyPreferences({ ...Prefs.DEFAULT_PREFERENCES, theme });
      window.root?.unmount();
      window.root = null;
      window.madeView?.destroy();
      const stage = document.getElementById('stage');
      stage.replaceChildren();
      document.body.style.background = 'var(--glacier-bg)';
      const host = document.createElement('div');
      host.style.cssText = 'inline-size: 390px; display: flex; flex-direction: column;';
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
      const view = new CM.view.EditorView({
        parent: editorHost,
        state: CM.state.EditorState.create({
          doc,
          extensions: [
            Base.language.glyphMarkdown([]),
            CM.language.syntaxHighlighting(Base.highlight.glyphHighlight),
            Base.lines.glyphLines,
            Base.extended.extendedMarkdown(),
            Find.findExtension(),
            CM.view.EditorView.lineWrapping,
            Base.theme.glyphTheme(theme === 'dark'),
            Base.viewMode.noteView('mixed'),
            CM.state.Prec.highest(grow),
          ],
        }),
      });
      window.madeView = view;
      window.root = ReactDOM.createRoot(document.getElementById('over'));
      window.root.render(React.createElement(Bar.FindBar, { view, initial: one.initial, onClose: () => {} }));
    },
    { one, doc: DOC },
  );
  await settle();
  for (const [what, label, text] of one.steps ?? []) {
    if (what === 'click') await page.click(`[role="search"] button[aria-label="${label}"]`);
    if (what === 'clickText') await page.click(`[role="search"] button:text-is("${label}")`);
    if (what === 'fill') await page.fill(`[role="search"] input[aria-label="${label}"]`, text);
    if (what === 'focus') await page.focus(`[role="search"] input[aria-label="${label}"]`);
    await settle();
  }
  await page.evaluate(() => window.scrollTo(0, 0));
  await settle();
  const result = await page.evaluate(
    ({ one, doc }) => {
      const view = window.madeView;
      const rect = (r) => ({ left: +r.left.toFixed(3), top: +r.top.toFixed(3), right: +r.right.toFixed(3), bottom: +r.bottom.toFixed(3) });
      const bar = document.querySelector('[role="search"]');
      const barStyle = getComputedStyle(bar);
      const said = (el) => {
        if (!el) return null;
        const style = getComputedStyle(el);
        const icon = el.querySelector('svg');
        // The words' own box: where the text itself was set, inside the control.
        let words = null;
        if (el.childNodes.length && [...el.childNodes].every((n) => n.nodeType === 3) && el.textContent.trim()) {
          const range = document.createRange();
          range.selectNodeContents(el);
          words = rect(range.getBoundingClientRect());
        }
        return {
          rect: rect(el.getBoundingClientRect()),
          text: el.tagName === 'INPUT' ? el.value : el.textContent,
          placeholder: el.getAttribute('placeholder'),
          placeholderColor: el.tagName === 'INPUT' ? getComputedStyle(el, '::placeholder').color : null,
          color: style.color,
          background: style.backgroundColor,
          border: style.borderTopColor,
          borderWidth: parseFloat(style.borderTopWidth),
          radius: style.borderTopLeftRadius,
          size: parseFloat(style.fontSize),
          weight: style.fontWeight,
          family: style.fontFamily.split(',')[0].replace(/['"]/g, ''),
          lineHeight: style.lineHeight,
          tracking: style.letterSpacing,
          disabled: el.disabled === true,
          pressed: el.getAttribute('aria-pressed'),
          focused: document.activeElement === el,
          words,
          icon: icon ? rect(icon.getBoundingClientRect()) : null,
        };
      };
      const rows = [...bar.querySelectorAll(':scope > div')];
      const second = rows[1];
      const controls = {
        find: said(bar.querySelector('input[aria-label="Find"]')),
        count: said(bar.querySelector('[aria-live="polite"]')),
        previous: said(bar.querySelector('button[aria-label="Previous match"]')),
        next: said(bar.querySelector('button[aria-label="Next match"]')),
        replace: said(bar.querySelector('button[aria-label="Replace"]')),
        done: said([...rows[0].querySelectorAll('button')].at(-1)),
        replaceWith: said(bar.querySelector('input[aria-label="Replace with"]')),
        replaceOne: second ? said(second.querySelectorAll('button')[0]) : null,
        all: second ? said(second.querySelectorAll('button')[1]) : null,
        said: said(bar.querySelector(':scope > p')),
      };
      const marks = [];
      for (const el of view.contentDOM.querySelectorAll('.cm-findMatch, .cm-findCurrent')) {
        const style = getComputedStyle(el);
        const from = view.posAtDOM(el, 0);
        // The ink of the words inside, which `.cm-findCurrent *` turns round whatever they wore.
        const inks = [];
        const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
        for (let node = walker.nextNode(); node; node = walker.nextNode()) inks.push(getComputedStyle(node.parentElement).color);
        marks.push({
          from,
          to: from + el.textContent.length,
          text: el.textContent,
          current: el.classList.contains('cm-findCurrent'),
          rects: [...el.getClientRects()].map(rect),
          background: style.backgroundColor,
          color: style.color,
          inks,
          radius: style.borderTopLeftRadius,
        });
      }
      const lines = [...view.contentDOM.querySelectorAll('.cm-line')].map((el) => ({ from: view.posAtDOM(el, 0), rect: rect(el.getBoundingClientRect()) }));
      const find = window.Find.findOf(view.state);
      const root = getComputedStyle(document.documentElement);
      return {
        doc,
        now: view.state.doc.toString(),
        theme: one.theme ?? 'light',
        initial: one.initial,
        steps: one.steps ?? [],
        query: find.query,
        current: find.current,
        matches: find.matches.map((m) => [m.from, m.to]),
        page: { width: innerWidth, height: innerHeight, ground: root.getPropertyValue('--glacier-bg') },
        bar: { rect: rect(bar.getBoundingClientRect()), background: barStyle.backgroundColor, border: barStyle.borderTopColor, borderWidth: parseFloat(barStyle.borderTopWidth), paddingTop: parseFloat(barStyle.paddingTop), paddingBottom: parseFloat(barStyle.paddingBottom), paddingLeft: parseFloat(barStyle.paddingLeft), gap: parseFloat(barStyle.rowGap) },
        rows: rows.map((row) => rect(row.getBoundingClientRect())),
        controls,
        marks,
        lines,
      };
    },
    { one, doc: DOC },
  );
  writeFileSync(`${OUT}${one.name}.json`, `${JSON.stringify(result)}\n`);
  writeFileSync(`${OUT}${one.name}.png`, await page.screenshot({ clip: { x: 0, y: 0, width: 390, height: 844 } }));
  console.log(one.name, result.matches.length, 'matches,', result.marks.length, 'marks, bar', JSON.stringify(result.bar.rect));
}

await browser.close();
