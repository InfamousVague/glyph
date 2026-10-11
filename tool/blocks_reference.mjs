// The web app's fenced code, its maths, its diagrams' boxes and its words too long for a line, drawn by Chromium,
// for the Flutter port to be held against (test/editor/blocks/reference_test.dart). What tool/editor_reference.mjs
// holds of a block of code is its lines' boxes in one theme at a phone's width; what tool/maths_fixtures.mjs holds
// of a formula is KaTeX's own height and depth, with no page; what tool/diagram_reference.mjs holds of a diagram
// is its picture. This holds the DRAWING of them as a person sees it in a note: a block's ground, its corners,
// its padding and its lines in each of the code themes on each side of the page, where a line wraps (and a word
// longer than what is left of its line, an address or a string, goes to the next line before it is cut), a
// formula's place in its line and a set-apart one's room, the source with the caret in it, a formula that cannot
// be read, and a diagram's box as its words, with its mistake said, with nothing to draw it, and with its picture.
//
// Each case is a fixture note on a page 390 wide (a phone) or 704 (the Fold's inner screen) and as tall as the note
// needs, at two device pixels to the logical one, the editor's box at the page's corner, so every rectangle is in
// the editor's own coordinates. A colour is what the page paints for it, read off a canvas: red, green, blue and
// alpha, each of 255. The editor measured is the BASE one of tool/editor_reference.mjs (language, highlighter, line
// classes, extended markdown, theme, view mode) with `drawnMaths()` of ../glyph/src/app/editor/mathsDrawn.ts and
// `drawnMermaid()` of editor/mermaid.ts, each as Editor.tsx adds it.
//
// For each case it writes test/editor/blocks/fixtures/<name>.json:
//   lines    every `.cm-line`: its document range, classes and rectangle; `ground`, what is painted behind it (its
//            computed background, the widths of its transparent borders, its padding and its four corners); `runs`,
//            each stretch of text with the classes over it and its computed colour, weight, style, face and size;
//            `words`, the client rectangles of the line's own text, a visual line each
//   blocks   every block widget (`.cm-mathsBlock`, `.cm-mermaid`): its classes, document position, rectangle,
//            padding, and KaTeX's own boxes (`.katex-display`, `.katex-html`, each `.base` and `.tag` with its
//            strut, which is the formula's height above its baseline and its depth below), or `parts`: a diagram's
//            words (`.cm-mermaidText`, each of its lines), its reason (`.cm-mermaidWhy`) and its picture
//   maths    every formula in a line (`.cm-mathsInline`): its position, its client rectangles, whether it is drawn
//            or could not be, what a long press says, its ink, size, face and decoration, and KaTeX's `.base` boxes
//   coords   for the notes with a word too long for a line in them, `view.coordsAtPos(pos, side)` for every
//            position, side 1 and -1
//   colours  the page's ground and ink, and every `--code-*` property as the page computed it
// and <name>.png, the picture.
//
//   (cd ../glyph && npx vite --port 5291 --strictPort --host 127.0.0.1) &     # read-only: never `vite build` there
//   node tool/blocks_reference.mjs [name ...]                                 # then stop the server by its PID
//
// Playwright is not this repository's: it is taken from the npx cache, as tool/editor_reference.mjs takes it.
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { mkdirSync, writeFileSync } from 'node:fs';

const BASE = process.env.GLYPH_DEV ?? 'http://127.0.0.1:5291/';
const OUT = new URL('../test/editor/blocks/fixtures/', import.meta.url).pathname;
mkdirSync(OUT, { recursive: true });

/** The fixture notes. */
const DOCS = {
  // Every kind of token the themes colour (test/editor/code/code_shots_test.dart's note): a keyword, a name defined
  // and called, a property, a type, a string, a number, a comment, a decorator, a label, punctuation; HTML in a
  // line; a block with no language.
  kinds:
    'A block of JavaScript:\n\n```js\n// Adds up.\n@logged\nclass Sum extends Base {\n  static total = 0;\n  add(n) { return this.total += n * 2; }\n}\nloop: for (const x of [1, "two", null]) {\n  if (typeof x === \'number\') new Sum().add(x);\n}\n```\n\nHTML in a line, <b class="x">bold</b> and <br/>, and a block with no language:\n\n```\nplain code\n```\n',
  // Where a block can stand: first in the note, in an item, in a quote, with tabs, with a word too long for the
  // line, under tildes, a fence in a fence, one block straight after another, an empty one, an indented one, and
  // one that never closes.
  places:
    '```sh\necho "first in the note"\n```\n- an item\n  ```sh\n  echo "in a list"\n  ```\n- the next\n\n> quoted\n> ```py\n> print("in a quote")\n> ```\n\n```ts\nfunction tabbed() {\n\treturn 1;\n\t\tdeeper();\n}\nconst unbroken = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";\n```\n~~~\ntildes\n~~~\n````md\n```js\nnested\n```\n````\n```\n```\nwords\n\n    indented code\n    on two lines\n\n```json\n{ "never": "closed" }\n',
  // Words too long for a line, where a note has them: an address after a word and at a line's start, in an item,
  // in a quote, in a heading, a word with a hyphen in it, and a long run of one letter.
  long: 'See https://example.com/a/very/long/path/that/goes/on/and/on/and/on/for/ever/and/does/not/stop/here.html for more.\n\nhttps://example.com/another/very/long/path/that/goes/on/and/on/and/on/for/ever/and/does/not/stop.html\n\n- An item, then https://example.com/a/very/long/path/that/goes/on/and/on/and/on/for/ever/and/ever.html\n- [ ] A box with Supercalifragilisticexpialidocious-and-then-some-more-of-it-all-the-way-along in it\n\n> Quoted: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa end.\n\n## A heading https://example.com/with/an/address/in/it/that/is/long.html\n\nTwo of them: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb and the end.\n',
  maths:
    '## Energy, $E = mc^2$\n\nThe roots are $x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}$, where $a \\neq 0$, and it costs $5 or $6.\n\n$$\n\\int_0^\\infty e^{-x^2}\\,dx = \\frac{\\sqrt{\\pi}}{2}\n$$\n\n> A quote with $\\alpha + \\beta$ in it.\n\n$$\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}$$\n\n- An item with $a_1 + a_2$ in it\n- [ ] A box with $\\sqrt{2}$\n\nOne that cannot be read: $\\frac{a$ here.\n\n$$\n\\frac{a\n$$\n\nAfter a block the words go on, with $e^{i\\pi} + 1 = 0$ near the end of a long line that wraps round to the next.\n',
  // A short formula set apart (no taller than a line of KaTeX's own type, where the line is the faces' boxes and
  // not the formula's: beside the page on a phone this one stood three device pixels short), numbered rows, a row
  // numbered by hand, one formula straight after another, and a tall one in a line.
  'maths-rows':
    'Before\n\n$$\nE = mc^2\n$$\n\nThen\n\n$$\n\\begin{align} a &= b + c \\\\ d &= e \\end{align}\n$$\n$$\nx \\tag{9}\n$$\n\nBetween, a tall one in the line: $\\sum_{i=1}^{n} \\frac{1}{i^2}$ and after it, and words enough to wrap round.\n\n$$\n\\begin{cases} x^2 & x \\ge 0 \\\\ -x & \\text{otherwise} \\end{cases}\n$$\nAfter\n',
  // A formula wider than the page.
  'maths-overwide':
    'Before\n\n$$\na_1 + a_2 + a_3 + a_4 + a_5 + a_6 + a_7 + a_8 + a_9 + a_{10} + a_{11} + a_{12} + a_{13} + a_{14} + a_{15} + a_{16} = b\n$$\n\nAfter, with words enough to reach the end of the line and wrap round to the next.\n',
  mermaid: 'Before\n\n```mermaid\ngraph TD\n  A[Start] --> B{Ready?}\n  B -->|yes| C[Go]\n  B -->|no| D[Wait]\n```\n\nBetween\n\n```mermaid\ngraph TD\n  A -->\n```\n\nAfter\n',
};

// As tall as the longest note here: CodeMirror draws the lines its window shows and leaves a gap for the rest.
const PHONE = { width: 390, height: 2600 };
const FOLD = { width: 704, height: 2600 };

/** The cases: a note, the page's side, its code themes, how it is shown, where the caret is, and how wide. */
const CASES = [];
for (const codeLight of ['pastel', 'ink', 'github', 'solarized']) CASES.push({ name: `code-light-${codeLight}`, doc: 'kinds', theme: 'light', codeLight });
for (const codeDark of ['pastel', 'ink', 'one-dark', 'dracula', 'nord']) CASES.push({ name: `code-dark-${codeDark}`, doc: 'kinds', theme: 'dark', codeDark });
CASES.push({ name: 'code-fold', doc: 'kinds', theme: 'light', size: FOLD });
CASES.push({ name: 'code-fold-dark', doc: 'kinds', theme: 'dark', size: FOLD });
CASES.push({ name: 'code-formatted', doc: 'kinds', theme: 'light', display: 'formatted' });
CASES.push({ name: 'code-larger', doc: 'kinds', theme: 'light', textSize: 'larger' });
// With `coords`: a word too long for its line is in this note, and where the caret stands either side of the
// place it wraps at is part of how it wraps.
CASES.push({ name: 'code-places', doc: 'places', theme: 'light', coords: true });
CASES.push({ name: 'code-places-dark', doc: 'places', theme: 'dark' });
CASES.push({ name: 'code-places-fold', doc: 'places', theme: 'light', size: FOLD, coords: true });
CASES.push({ name: 'code-places-formatted', doc: 'places', theme: 'light', display: 'formatted' });
// The same note with its block of prose: a long address after a word, where a phone's line and the Fold's end.
CASES.push({ name: 'long-words', doc: 'long', theme: 'light', coords: true });
CASES.push({ name: 'long-words-fold', doc: 'long', theme: 'light', size: FOLD, coords: true });
// The caret in a block, and a selection across two of its lines.
CASES.push({ name: 'code-caret', doc: 'kinds', theme: 'light', caret: DOCS.kinds.indexOf('static') + 3 });
CASES.push({ name: 'code-selection', doc: 'kinds', theme: 'dark', caret: DOCS.kinds.indexOf('add(n)') + 3, anchor: DOCS.kinds.indexOf('@logged') + 2 });

CASES.push({ name: 'maths', doc: 'maths', theme: 'light' });
CASES.push({ name: 'maths-dark', doc: 'maths', theme: 'dark' });
CASES.push({ name: 'maths-fold', doc: 'maths', theme: 'light', size: FOLD });
CASES.push({ name: 'maths-fold-dark', doc: 'maths', theme: 'dark', size: FOLD });
CASES.push({ name: 'maths-formatted', doc: 'maths', theme: 'light', display: 'formatted' });
CASES.push({ name: 'maths-readonly', doc: 'maths', theme: 'light', readOnly: true });
CASES.push({ name: 'maths-larger', doc: 'maths', theme: 'light', textSize: 'larger' });
// The caret on a line with formulas in it, and in a block: what was typed, to edit.
CASES.push({ name: 'maths-caret-line', doc: 'maths', theme: 'light', caret: DOCS.maths.indexOf('The roots') + 4 });
CASES.push({ name: 'maths-caret-block', doc: 'maths', theme: 'light', caret: DOCS.maths.indexOf('\\int_0') + 2 });
CASES.push({ name: 'maths-caret-block-dark', doc: 'maths', theme: 'dark', caret: DOCS.maths.indexOf('\\int_0') + 2 });
CASES.push({ name: 'maths-rows', doc: 'maths-rows', theme: 'light' });
CASES.push({ name: 'maths-rows-dark', doc: 'maths-rows', theme: 'dark' });
CASES.push({ name: 'maths-rows-fold', doc: 'maths-rows', theme: 'light', size: FOLD });
CASES.push({ name: 'maths-rows-larger', doc: 'maths-rows', theme: 'dark', textSize: 'larger' });
CASES.push({ name: 'maths-overwide', doc: 'maths-overwide', theme: 'light' });

// A diagram before its picture (Mermaid held back), with nothing to draw it (Mermaid refused), and drawn: the
// first as its picture, the second, written wrong, as its words with what Mermaid said.
for (const [suffix, more] of [['', {}], ['-dark', { theme: 'dark' }], ['-fold', { size: FOLD }]]) {
  CASES.push({ name: `mermaid-words${suffix}`, doc: 'mermaid', theme: 'light', mermaid: 'held', ...more });
  CASES.push({ name: `mermaid-missing${suffix}`, doc: 'mermaid', theme: 'light', mermaid: 'refused', ...more });
  CASES.push({ name: `mermaid-drawn${suffix}`, doc: 'mermaid', theme: 'light', ...more });
}
CASES.push({ name: 'mermaid-caret', doc: 'mermaid', theme: 'light', caret: DOCS.mermaid.indexOf('graph TD') + 3 });

// IN A PHONE'S OWN PIXELS. `GLYPH_RATIO=2.625 node tool/blocks_reference.mjs` draws the cases marked `phone` again
// as a phone lays them out (Chromium launched at that scale lays out in device pixels; told a scale by Playwright
// it lays out in whole CSS ones: docs/REFERENCES.md) and writes them to fixtures/phone/, a window of 475, the
// Fold's cover screen.
const RATIO = Number(process.env.GLYPH_RATIO ?? 0);
const PHONE_PIXELS = { width: Math.floor(1248 / (RATIO || 1)), height: 2600 };
if (RATIO) mkdirSync(`${OUT}phone`, { recursive: true });
/** The cases drawn again in a phone's pixels: each kind of note, light, and one dark. */
const PHONE_CASES = new Set(['code-light-pastel', 'code-dark-pastel', 'code-places', 'long-words', 'maths', 'maths-rows', 'mermaid-missing']);
const only = process.argv.slice(2);
const browser = await chromium.launch(RATIO ? { args: [`--force-device-scale-factor=${RATIO}`, `--window-size=${PHONE_PIXELS.width},${PHONE_PIXELS.height}`] } : {});

/** A page of the dev server's own origin with nothing on it, the app's modules loaded and the app not started. */
async function open(size, mermaid) {
  const context = await browser.newContext(RATIO ? { viewport: null, hasTouch: true } : { viewport: size, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const page = await context.newPage();
  page.on('pageerror', (error) => console.log('page error:', error.message));
  await page.route('**/__blocks_reference', (route) =>
    route.fulfill({
      contentType: 'text/html',
      body: '<!doctype html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body style="margin:0"><div id="stage"></div></body></html>',
    }),
  );
  // Mermaid is a module of its own, asked for the first time a diagram is drawn (mermaid.ts `library`): held back,
  // the block is its words; refused, it says it could not be drawn here.
  let release = () => {};
  if (mermaid) {
    const gate = new Promise((done) => (release = done));
    await page.route(/\/deps\/mermaid\.js/, async (route) => {
      if (mermaid === 'refused') return route.abort();
      await gate;
      return route.continue();
    });
  }
  await page.goto(`${BASE}__blocks_reference`);
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
      maths: await import('/src/app/editor/mathsDrawn.ts'),
      mermaid: await import('/src/app/editor/mermaid.ts'),
      styles: (await import('/src/app/editor/markdown.module.css')).default,
    };
    window.Prefs = await import('/src/app/core/preferences.ts');
    await document.fonts.ready;
  });
  return { context, page, release };
}

/** One page for each window and each way Mermaid answers, made when a case first wants it. */
const pages = new Map();
async function pageFor(one) {
  const size = one.size ?? PHONE;
  const key = `${size.width}/${one.mermaid ?? ''}`;
  if (!pages.has(key)) pages.set(key, await open(size, one.mermaid));
  return pages.get(key);
}

for (const one of CASES) {
  if (only.length && !only.includes(one.name)) continue;
  if (RATIO && !PHONE_CASES.has(one.name)) continue;
  const doc = DOCS[one.doc];
  const size = RATIO ? PHONE_PIXELS : (one.size ?? PHONE);
  const { page } = await pageFor(one);
  const result = await page.evaluate(
    async ({ one, doc, size }) => {
      const { CM, Base, Prefs } = window;
      const theme = one.theme ?? 'light';
      const codeLight = one.codeLight ?? Prefs.DEFAULT_PREFERENCES.codeLight, codeDark = one.codeDark ?? Prefs.DEFAULT_PREFERENCES.codeDark;
      const textSize = one.textSize ?? Prefs.DEFAULT_PREFERENCES.textSize;
      // Chosen, not only painted: a diagram is drawn in the colours `preferences().theme` names (mermaid.ts).
      Prefs.setPreferences({ ...Prefs.DEFAULT_PREFERENCES, theme, codeLight, codeDark, codeChosen: true, textSize });
      window.madeView?.destroy();
      window.madeView = null;
      const stage = document.getElementById('stage');
      stage.replaceChildren();
      document.body.style.background = 'var(--glacier-bg)';
      const host = document.createElement('div');
      host.style.cssText = `inline-size: ${size.width}px; display: flex; flex-direction: column;`;
      stage.append(host);
      const display = one.display ?? 'mixed';
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
            Base.maths.drawnMaths(),
            Base.mermaid.drawnMermaid(),
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
      const frames = () => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));
      const wait = (ms) => new Promise((done) => setTimeout(done, ms));
      // A block's language is a module of its own, loaded when the block is first parsed: the whole note parsed,
      // until two looks a while apart see the same classes on it.
      let before = '';
      for (let tries = 0; tries < 40; tries += 1) {
        CM.language.forceParsing(view, view.state.doc.length, 1000);
        await wait(120);
        const now = [...view.contentDOM.querySelectorAll('.cm-line span')].map((el) => el.className).join('|');
        if (tries > 2 && now === before) break;
        before = now;
      }
      await document.fonts.ready;
      if (one.caret !== undefined) {
        view.focus();
        view.dispatch({ selection: { anchor: one.anchor ?? one.caret, head: one.caret } });
      }
      // KaTeX is a module of its own too, and Mermaid: every formula drawn or refused, every diagram drawn or its
      // reason said (or, held back, still its words).
      for (let tries = 0; tries < 80; tries += 1) {
        await wait(100);
        const formulas = [...view.contentDOM.querySelectorAll('.cm-mathsInline, .cm-mathsBlock')];
        const diagrams = [...view.contentDOM.querySelectorAll('.cm-mermaid')];
        const mathsDone = formulas.every((el) => 'drawn' in el.dataset || 'failed' in el.dataset);
        const diagramsDone = one.mermaid === 'held' || diagrams.every((el) => 'drawn' in el.dataset || el.querySelector('.cm-mermaidWhy'));
        if (mathsDone && diagramsDone) break;
      }
      await document.fonts.ready;
      await wait(200);
      view.requestMeasure();
      await frames();
      await wait(80);

      const origin = host.getBoundingClientRect();
      const rect = (r) => (r ? { left: +(r.left - origin.left).toFixed(3), top: +(r.top - origin.top).toFixed(3), right: +(r.right - origin.left).toFixed(3), bottom: +(r.bottom - origin.top).toFixed(3) } : null);
      const box = (el) => (el ? rect(el.getBoundingClientRect()) : null);
      const plain = (name) => name.replace(/^_|_[a-z0-9]+_\d+$/gi, '');
      // A colour as it is painted: `getComputedStyle` answers in the space the stylesheet wrote it in (`oklch(…)`).
      const canvas = document.createElement('canvas');
      canvas.width = canvas.height = 1;
      const ink = canvas.getContext('2d', { willReadFrequently: true });
      const painted = new Map();
      const rgb = (color) => {
        if (!painted.has(color)) {
          ink.clearRect(0, 0, 1, 1);
          ink.fillStyle = color;
          ink.fillRect(0, 0, 1, 1);
          painted.set(color, [...ink.getImageData(0, 0, 1, 1).data]);
        }
        return painted.get(color);
      };
      const face = (style) => ({ color: rgb(style.color), size: parseFloat(style.fontSize), weight: style.fontWeight, style: style.fontStyle, family: style.fontFamily.split(',')[0].replace(/['"]/g, ''), decoration: style.textDecorationLine, decorationStyle: style.textDecorationStyle });
      /** What KaTeX laid out: each base box (its struts make it the formula's height and depth), and a number. */
      const katex = (el) => ({
        display: box(el.querySelector('.katex-display')),
        html: box(el.querySelector('.katex-html')),
        // A base's first strut is KaTeX's own measure of it: from its height above the baseline to its depth below.
        bases: [...el.querySelectorAll('.katex-html > .base, .katex-html > .tag')].map((each) => ({ tag: each.classList.contains('tag'), rect: box(each), strut: box(each.querySelector('.strut')) })),
        size: el.querySelector('.katex') ? parseFloat(getComputedStyle(el.querySelector('.katex')).fontSize) : null,
      });

      const lines = [];
      const blocks = [];
      const maths = [];
      for (const el of view.contentDOM.children) {
        const style = getComputedStyle(el);
        if (!el.classList.contains('cm-line')) {
          const parts = [];
          if (el.classList.contains('cm-mermaid')) {
            const text = el.querySelector('.cm-mermaidText');
            if (text && getComputedStyle(text).display !== 'none') {
              const range = document.createRange();
              range.selectNodeContents(text);
              parts.push({ name: 'cm-mermaidText', rect: box(text), ...face(getComputedStyle(text)), lineHeight: getComputedStyle(text).lineHeight, said: text.textContent, words: [...range.getClientRects()].map(rect) });
            }
            const why = el.querySelector('.cm-mermaidWhy');
            if (why) {
              const range = document.createRange();
              range.selectNodeContents(why);
              parts.push({ name: 'cm-mermaidWhy', rect: box(why), ...face(getComputedStyle(why)), said: why.textContent, words: [...range.getClientRects()].map(rect) });
            }
            const svg = el.querySelector('svg');
            if (svg) parts.push({ name: 'svg', rect: box(svg) });
          }
          let from = null;
          try {
            from = view.posAtDOM(el);
          } catch {
            from = null;
          }
          blocks.push({
            classes: [...el.classList],
            from,
            rect: box(el),
            padding: [style.paddingTop, style.paddingRight, style.paddingBottom, style.paddingLeft].map(parseFloat),
            drawn: 'drawn' in el.dataset,
            failed: 'failed' in el.dataset,
            title: el.getAttribute('title'),
            said: el.classList.contains('cm-mathsBlock') && !('drawn' in el.dataset) ? el.textContent : null,
            ...face(style),
            scroll: el.scrollWidth > el.clientWidth + 1 ? { width: el.scrollWidth, clientWidth: el.clientWidth } : null,
            katex: el.classList.contains('cm-mathsBlock') && 'drawn' in el.dataset ? katex(el) : null,
            parts,
          });
          continue;
        }
        const from = view.posAtDOM(el, 0);
        const line = view.state.doc.lineAt(from);
        const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT, { acceptNode: (node) => (node.parentElement.closest('.cm-mathsInline, .cm-mathsBlock') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT) });
        const runs = [];
        const words = [];
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          const at = getComputedStyle(node.parentElement);
          const over = [];
          for (let up = node.parentElement; up && up !== el; up = up.parentElement) over.push(...up.classList);
          runs.push({ text: node.textContent, classes: over.map(plain), ...face(at) });
          const range = document.createRange();
          range.selectNodeContents(node);
          for (const each of range.getClientRects()) words.push(rect(each));
        }
        for (const formula of el.querySelectorAll('.cm-mathsInline, .cm-mathsBlock')) {
          const at = getComputedStyle(formula);
          maths.push({
            line: line.from,
            // Set apart though it is in a line: `$$…$$` alone on its line.
            display: formula.classList.contains('cm-mathsBlock'),
            box: box(formula),
            pos: view.posAtDOM(formula),
            rects: [...formula.getClientRects()].map(rect),
            drawn: 'drawn' in formula.dataset,
            failed: 'failed' in formula.dataset,
            title: formula.getAttribute('title'),
            said: 'drawn' in formula.dataset ? null : formula.textContent,
            ...face(at),
            katex: 'drawn' in formula.dataset ? katex(formula) : null,
          });
        }
        lines.push({
          from: line.from,
          to: line.to,
          text: line.text,
          classes: [...el.classList].filter((c) => c !== 'cm-line').map(plain),
          rect: box(el),
          ground: {
            color: rgb(style.backgroundColor),
            // A quote's bar: an image painted down the start of the padding box, this wide.
            bar: style.backgroundImage === 'none' ? null : parseFloat(style.backgroundSize),
            borders: [style.borderTopWidth, style.borderRightWidth, style.borderBottomWidth, style.borderLeftWidth].map(parseFloat),
            padding: [style.paddingTop, style.paddingRight, style.paddingBottom, style.paddingLeft].map(parseFloat),
            margins: [style.marginLeft, style.marginRight].map(parseFloat),
            // Each corner, across then down.
            corners: [style.borderTopLeftRadius, style.borderTopRightRadius, style.borderBottomRightRadius, style.borderBottomLeftRadius].map((each) => each.split(' ').map(parseFloat)),
          },
          ...face(style),
          lineHeight: style.lineHeight,
          tabSize: style.tabSize,
          runs,
          words,
        });
      }
      const root = getComputedStyle(document.documentElement);
      // Colours as the page paints them: a probe wearing each, read back as rgb.
      const probe = document.createElement('span');
      document.body.append(probe);
      const colours = {};
      for (const name of ['--glacier-bg', '--glacier-text', '--glacier-text-muted', '--glacier-text-subtle', '--glacier-accent-text', '--app-ink-2', '--app-ink-3', '--code-bg', '--code-fg', '--code-keyword', '--code-string', '--code-comment', '--code-type', '--code-property', '--code-name', '--code-literal', '--code-punctuation', '--code-macro', '--code-meta']) {
        probe.style.color = `var(${name})`;
        colours[name] = rgb(getComputedStyle(probe).color);
      }
      probe.remove();
      // `view.coordsAtPos(pos, side)` for every position of the note, side 1 and -1.
      const coords = [];
      if (one.coords) {
        for (let pos = 0; pos <= view.state.doc.length; pos += 1) coords.push({ pos, after: rect(view.coordsAtPos(pos, 1)), before: rect(view.coordsAtPos(pos, -1)) });
      }
      const selection = [...view.dom.querySelectorAll('.cm-selectionBackground')].map((el) => ({ rect: box(el), color: rgb(getComputedStyle(el).backgroundColor) }));
      const caret = view.dom.querySelector('.cm-cursor-primary');
      return {
        doc,
        theme,
        codeLight,
        codeDark,
        display,
        readOnly,
        textSize,
        noteFace: 'maple',
        caret: one.caret ?? null,
        anchor: one.anchor ?? null,
        mermaid: one.mermaid ?? null,
        width: origin.width,
        window: size,
        content: box(view.contentDOM),
        editor: box(view.dom),
        gutter: root.getPropertyValue('--app-gutter'),
        colours,
        lines,
        blocks,
        maths,
        coords,
        selection,
        caretRect: one.caret !== undefined && caret ? box(caret) : null,
        clip: { x: 0, y: 0, width: Math.ceil(origin.width), height: Math.floor(view.dom.getBoundingClientRect().bottom - origin.top) },
      };
    },
    { one, doc, size },
  );
  const { clip, ...kept } = result;
  const out = RATIO ? `${OUT}phone/` : OUT;
  if (RATIO) Object.assign(kept, { ratio: RATIO });
  writeFileSync(`${out}${one.name}.json`, `${JSON.stringify(kept)}\n`);
  writeFileSync(`${out}${one.name}.png`, await page.screenshot({ clip: { ...clip, height: Math.max(1, Math.min(size.height, clip.height)) } }));
  console.log(one.name, kept.lines.length, 'lines,', kept.blocks.map((b) => `${b.classes[0]}${b.drawn ? '' : b.failed ? ' (failed)' : ' (words)'}`).join(', ') || 'no blocks', `, ${kept.maths.length} in lines`);
}

for (const { context, release } of pages.values()) {
  release();
  await context.close();
}
await browser.close();
