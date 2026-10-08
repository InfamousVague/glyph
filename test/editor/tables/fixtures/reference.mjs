// The web app's drawn tables, drawn by Chromium, for lib/editor/tables to be held against
// (test/editor/tables/reference_test.dart). Modelled on tool/editor_reference.mjs: each case is a fixture note on a
// page 390 x 844 at two device pixels to the logical one, the editor's box at the page's corner, so every rectangle
// is in the editor's own coordinates.
//
// The editor measured is the BASE one of tool/editor_reference.mjs (what lib/editor/view ports: language.ts,
// glyphHighlight.ts, glyphLines.ts, extended.ts, glyphTheme.ts, viewMode.ts in the `.editor` host) with
// `drawnTables()` of ../glyph/src/app/editor/tables.ts added and nothing else, so the only thing that moves the
// words is the piece being ported.
//
// For each case it writes test/editor/tables/fixtures/<name>.json:
//   lines   every `.cm-line`: its document range, class list and rectangle
//   tables  every `.cm-glyphTableWrap`: its rectangle, how far it scrolls, the `.cm-glyphTable`'s rectangle, each
//           cell (row, column, th or td, words, alignment, ground, border, its rectangle and each line of its words),
//           the `.cm-tableTools` row and each `.cm-tableGrow` button (rectangle, words' rectangle, ink, border)
// and test/editor/tables/fixtures/<name>.png, the picture.
//
//   node test/editor/tables/fixtures/reference.mjs [name ...]        # GLYPH_DEV=http://127.0.0.1:5272/ by default
//
// Playwright is not this repository's: it is taken from the npx cache, as tool/editor_reference.mjs takes it.
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { writeFileSync } from 'node:fs';

const BASE = process.env.GLYPH_DEV ?? 'http://127.0.0.1:5272/';
const OUT = new URL('./', import.meta.url).pathname;

const LONG = 'The quick brown fox jumps over the lazy dog, then turns round and does it again.';

/** The fixture notes. */
const DOCS = {
  // tables.test.ts's own note.
  simple: ['Before', '', '| Bug | Owner |', '| --- | --- |', '| Seek **bar** | Matt |', '', 'After'].join('\n'),
  // Every alignment, a short row, an escaped pipe, markup that is drawn as words.
  align: ['# Bugs', '', '| Bug | Owner | Status | n |', '| :--- | :---: | ---: | --- |', '| Seek bar \\| drift | Matt | Open | 1 |', '| Login |', '| A `code` and a [link](https://example.com) | _Someone_ else | Closed for good | 22 |', '', 'After'].join('\n'),
  // A cell long enough to wrap at the measure, and a header that never wraps.
  wrap: ['Before', '', '| What happened | When |', '| --- | --- |', `| ${LONG} | Monday |`, '| Short | A header cell never wraps but a body cell does when it is long |', '', 'After'].join('\n'),
  // Wider than the screen: it scrolls sideways in its wrap.
  wide: ['Before', '', '| Monday | Tuesday | Wednesday | Thursday | Friday | Saturday | Sunday |', '| --- | --- | --- | --- | --- | --- | --- |', '| one | two | three | four | five | six | seven |', '| 1 | 2 | 3 | 4 | 5 | 6 | 7 |', '', 'After'].join('\n'),
  // Narrow: held to sixty parts in a hundred of the room.
  narrow: ['| a | b |', '| - | - |', '| 1 | 2 |', '', 'After', '', '| One |', '| --- |', '', 'x | y', '--- | ---', '1 | 2'].join('\n'),
  // As + Column and + Row leave a table: an empty cell on a row with words, and a row of nothing but empty cells.
  grown: ['| Bug | Owner | Column |', '| --- | --- | --- |', '| Seek bar | Matt |  |', '|  |  |  |', '', 'After'].join('\n'),
  // A header longer than the measure (it never wraps), and words that break at a hyphen, or do not at a stroke.
  longhead: ['| A header that is much longer than eighteen ems | b |', '| --- | --- |', '| x | well-known state-of-the-art |', '| y | a/b/c?d=e and on |', '', 'After'].join('\n'),
};

const at = (doc, words) => DOCS[doc].indexOf(words);

/** The cases: a note, whether it can be edited, and where the caret is (which focuses the editor). */
const CASES = [];
for (const name of Object.keys(DOCS)) {
  CASES.push({ name, doc: name });
  CASES.push({ name: `${name}-readonly`, doc: name, readOnly: true });
}
// The caret in the table: its pipes, to edit. And outside it, in a focused view: drawn.
CASES.push({ name: 'simple-inside', doc: 'simple', caret: at('simple', '| Bug') + 3 });
CASES.push({ name: 'simple-outside', doc: 'simple', caret: 2 });
CASES.push({ name: 'align-inside', doc: 'align', caret: at('align', '| Login') });
CASES.push({ name: 'narrow-inside', doc: 'narrow', caret: 3 });
// The formatted view, which can be typed in too.
CASES.push({ name: 'align-formatted', doc: 'align', display: 'formatted' });
// Dark, for the pictures and the colours.
for (const name of ['simple', 'align', 'wrap']) CASES.push({ name: `${name}-dark`, doc: name, theme: 'dark' });
CASES.push({ name: 'simple-inside-dark', doc: 'simple', caret: at('simple', '| Bug') + 3, theme: 'dark' });
// The larger text, and the note in the interface's face.
CASES.push({ name: 'align-larger', doc: 'align', textSize: 'larger' });
CASES.push({ name: 'align-inter', doc: 'align', noteFace: 'inter' });
CASES.push({ name: 'wrap-inter', doc: 'wrap', noteFace: 'inter' });

const only = process.argv.slice(2);
const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
const page = await context.newPage();
page.on('pageerror', (error) => console.log('page error:', error.message));
// A page of the dev server's own origin with nothing on it, so the app's modules load and the app does not start.
await page.route('**/__tables_reference', (route) =>
  route.fulfill({
    contentType: 'text/html',
    body: '<!doctype html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body style="margin:0"><div id="stage"></div></body></html>',
  }),
);
await page.goto(`${BASE}__tables_reference`);

await page.evaluate(async () => {
  window.$RefreshReg$ = () => {};
  window.$RefreshSig$ = () => (type) => type;
  window.__vite_plugin_react_preamble_installed__ = true;
  const main = await (await fetch('/src/main.tsx')).text();
  for (const found of main.matchAll(/^import "([^"]+\.css)";/gm)) await import(/* @vite-ignore */ found[1]);
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
    tables: await import('/src/app/editor/tables.ts'),
    styles: (await import('/src/app/editor/markdown.module.css')).default,
  };
  window.Prefs = await import('/src/app/core/preferences.ts');
  await document.fonts.ready;
});

for (const one of CASES) {
  if (only.length && !only.includes(one.name)) continue;
  const doc = DOCS[one.doc];
  const result = await page.evaluate(
    async ({ one, doc }) => {
      const { CM, Base, Prefs } = window;
      const theme = one.theme ?? 'light';
      const display = one.display ?? 'mixed';
      Prefs.applyPreferences({ ...Prefs.DEFAULT_PREFERENCES, theme, noteFace: one.noteFace ?? Prefs.DEFAULT_PREFERENCES.noteFace, textSize: one.textSize ?? Prefs.DEFAULT_PREFERENCES.textSize });
      window.madeView?.destroy();
      window.madeView = null;
      const stage = document.getElementById('stage');
      stage.replaceChildren();
      document.body.style.background = 'var(--glacier-bg)';
      const host = document.createElement('div');
      host.style.cssText = 'inline-size: 390px; display: flex; flex-direction: column;';
      stage.append(host);
      const readOnly = one.readOnly || false;
      // Editor.tsx's host: `<div className={styles.editor} data-grow data-view={display}>`.
      const editorHost = document.createElement('div');
      editorHost.className = Base.styles.editor;
      editorHost.setAttribute('data-grow', 'true');
      editorHost.setAttribute('data-view', display);
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
            Base.tables.drawnTables(),
            CM.view.EditorView.lineWrapping,
            CM.view.EditorView.contentAttributes.of({ autocorrect: 'off', autocapitalize: 'off', spellcheck: 'false', inputmode: 'text', enterkeyhint: 'enter' }),
            Base.theme.glyphTheme(theme === 'dark'),
            [CM.state.EditorState.readOnly.of(readOnly), CM.view.EditorView.editable.of(!readOnly)],
            Base.viewMode.noteView(display),
            CM.state.Prec.highest(grow),
          ],
        }),
      });
      window.madeView = view;
      // The whole note parsed, as the app's own test helper sees to (test/syntaxTree.ts).
      CM.language.forceParsing(view, view.state.doc.length, 1000);
      await new Promise((done) => setTimeout(done, 120));
      await document.fonts.ready;
      if (one.caret !== undefined) {
        view.focus();
        view.dispatch({ selection: { anchor: one.anchor ?? one.caret, head: one.caret } });
      }
      await new Promise((done) => setTimeout(done, 250));
      view.requestMeasure();
      await new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));
      const origin = host.getBoundingClientRect();
      const rect = (r) => (r ? { left: +(r.left - origin.left).toFixed(3), top: +(r.top - origin.top).toFixed(3), right: +(r.right - origin.left).toFixed(3), bottom: +(r.bottom - origin.top).toFixed(3) } : null);
      const wordsOf = (el) => {
        const range = document.createRange();
        range.selectNodeContents(el);
        return [...range.getClientRects()].map(rect);
      };
      const lines = [];
      const tables = [];
      for (const el of view.contentDOM.children) {
        if (el.classList.contains('cm-line')) {
          const from = view.posAtDOM(el, 0);
          const line = view.state.doc.lineAt(from);
          lines.push({ from: line.from, to: line.to, text: line.text, classes: [...el.classList].filter((c) => c !== 'cm-line').map((c) => c.replace(/^_|_[a-z0-9]+_\d+$/gi, '')), rect: rect(el.getBoundingClientRect()) });
          continue;
        }
        if (!el.classList.contains('cm-glyphTableWrap')) continue;
        const table = el.querySelector('.cm-glyphTable');
        const cells = [];
        [...(table?.rows ?? [])].forEach((row, r) => {
          [...row.cells].forEach((cell, c) => {
            const style = getComputedStyle(cell);
            cells.push({
              row: r,
              column: c,
              head: cell.tagName === 'TH',
              text: cell.textContent,
              align: style.textAlign,
              background: style.backgroundColor,
              border: style.borderTopColor,
              color: style.color,
              size: parseFloat(style.fontSize),
              weight: style.fontWeight,
              family: style.fontFamily.split(',')[0].replace(/['"]/g, ''),
              rect: rect(cell.getBoundingClientRect()),
              words: wordsOf(cell),
            });
          });
        });
        const tools = el.querySelector('.cm-tableTools');
        const grows = [...el.querySelectorAll('.cm-tableGrow')].map((button) => {
          const style = getComputedStyle(button);
          return { text: button.textContent, rect: rect(button.getBoundingClientRect()), words: wordsOf(button), color: style.color, border: style.borderTopColor, radius: style.borderTopLeftRadius, size: parseFloat(style.fontSize), family: style.fontFamily.split(',')[0].replace(/['"]/g, ''), weight: style.fontWeight };
        });
        tables.push({
          from: view.posAtDOM(el),
          rect: rect(el.getBoundingClientRect()),
          scrollWidth: el.scrollWidth,
          clientWidth: el.clientWidth,
          table: table ? rect(table.getBoundingClientRect()) : null,
          cells,
          tools: tools ? rect(tools.getBoundingClientRect()) : null,
          grows,
        });
      }
      const root = getComputedStyle(document.documentElement);
      return {
        doc,
        display,
        theme,
        noteFace: one.noteFace ?? 'maple',
        textSize: one.textSize ?? 'large',
        readOnly,
        caret: one.caret ?? null,
        width: origin.width,
        content: rect(view.contentDOM.getBoundingClientRect()),
        page: root.getPropertyValue('--glacier-bg'),
        lines,
        tables,
        clip: { x: 0, y: 0, width: Math.ceil(origin.width), height: Math.min(844, Math.ceil(view.dom.getBoundingClientRect().bottom - origin.top)) },
      };
    },
    { one, doc },
  );
  const { clip, ...kept } = result;
  writeFileSync(`${OUT}${one.name}.json`, `${JSON.stringify(kept)}\n`);
  // The room under the last line (the content's own padding) is left out of the picture: it is only paper.
  const last = Math.max(...kept.lines.map((l) => l.rect.bottom), ...kept.tables.map((t) => t.rect.bottom), 1);
  writeFileSync(`${OUT}${one.name}.png`, await page.screenshot({ clip: { ...clip, height: Math.max(1, Math.min(clip.height, Math.ceil(last) + 24)) } }));
  console.log(one.name, kept.lines.length, 'lines', kept.tables.length, 'tables', kept.tables.map((t) => t.cells.length).join(','));
}

await browser.close();
