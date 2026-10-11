// The web app's own editor, drawn by Chromium, for the Flutter renderer to be held against
// (test/editor/view/reference_test.dart). Each case is a fixture note on a page 390 x 844 at two device pixels to the
// logical one, with nothing round it: the editor's box starts at the page's corner, so every rectangle is in the
// editor's own coordinates.
//
// Two editors are measured. The BASE one is what lib/editor/view ports and no more: a CodeMirror view assembled here
// as tauri/src/app/editor/Editor.tsx assembles it, from the web app's own modules (language.ts, glyphHighlight.ts,
// glyphLines.ts, extended.ts, glyphTheme.ts, viewMode.ts) inside the same `.editor` host, without the extensions later
// pieces port (short links, heading counts, tags, tables...), which would move the words. The FULL one is the web
// `Editor` component itself, written to fixtures/full/ for those pieces to be held against in their turn.
//
// For each case it writes test/editor/view/fixtures/<name>.json:
//   lines   every `.cm-line`: its document range, class list, style attribute and rectangle, and each run of text
//           on it with the classes over it and its computed colour, family, size, weight, style and decoration
//   blocks  every block widget's class and rectangle
//   coords  `view.coordsAtPos(pos, side)` for every position of the note, side 1 and -1
//   hits    `view.posAtCoords` over a grid of points
// and test/editor/view/fixtures/<name>.png, the picture.
//
// Pieces E and F (lib/editor/marks, lib/editor/items) have cases of their own, drawn by the FULL editor and written
// beside their tests (test/editor/marks/fixtures, test/editor/items/fixtures). Beside the above each has
//   marks   every element the marks and the inline items draw (`DRAWN` below): its classes, attributes, text, the
//           document position under it, its rectangle and client rectangles, and its computed colour, ground, size,
//           weight, decoration, opacity, `top`, filter and text-shadow
//   today   the day the page counted a due date from, and `locale`, the language it named it in
// The `marks-at-*` cases hold the page's clock: the frame loop is told `at` seconds and CSS and SVG animations are
// set to it, so the moving marks can be compared at a moment (test/editor/marks/effects_test.dart). `still` cases
// ask for reduced motion.
//
//   (cd tauri && npx vite --port 5270 --strictPort --host 127.0.0.1) &     # read-only: never `vite build` there
//   node tool/editor_reference.mjs [name ...]
//
// Playwright is not this repository's: it is taken from the npx cache, as tool/wisp_reference.mjs takes it.
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { mkdirSync, writeFileSync } from 'node:fs';

const BASE = process.env.GLYPH_DEV ?? 'http://127.0.0.1:5270/';
const OUT = process.env.GLYPH_OUT ?? new URL('../test/editor/view/fixtures/', import.meta.url).pathname;
mkdirSync(`${OUT}full`, { recursive: true });

const LONG = 'The quick brown fox jumps over the lazy dog, then turns round and does it again for the sign-in page.';

/** The fixture notes, one per feature. */
const DOCS = {
  headings: '# One\n## Two\n### Three\n#### Four\n##### Five\n###### Six\nplain words\n\n## A second heading that is long enough to wrap onto another line\nafter',
  paragraphs: `First words.\n\n${LONG} ${LONG}\n\nTrailing spaces   \nand a line after.\n\nSupercalifragilisticexpialidociousSupercalifragilisticexpialidocious and on.\n\nlast`,
  bullets: `- one\n- two words here\n  - nested item\n    - deeper still\n* star\n+ plus\n- ${LONG}\n  - nested: ${LONG}\nafter the list`,
  ordered: `1. first\n2. second\n10. tenth\n11. ${LONG}\n    1. nested number\n3) paren\nafter`,
  tasks: `- [ ] to do\n- [x] done\n- [ ] ${LONG}\n  - [ ] nested box\n1. [ ] numbered box\nafter`,
  quotes: `before\n> a quote\n> on two lines\n\n> ${LONG}\n\n> # heading in a quote\n> - item in a quote\n> - ${LONG}\n\nafter`,
  code: 'before\n```js\nconst a = 1;\n\n  indented(line);\nconst long = "The quick brown fox jumps over the lazy dog, then turns round";\n```\nbetween\n```\nplain\n```\n\n    indented code\n\nafter',
  rules: 'above\n\n---\n\nbelow\n\n***\n\n- - -\nend',
  inline: `Some **bold** and _italic_ and ~~struck~~ and \`code\` here.\nA [link](https://example.com/a/path) and <https://auto.link> too.\n**bold _both_ bold** and \`code with  spaces\` and ***all three***.\nAn escaped \\* star and a trailing \`tick\`\n# Heading with \`code\` and **bold** and _em_\n${LONG} **${LONG}**`,
  mixed: `# Title\n\nA paragraph of words with **bold** in it.\n\n## List\n- one\n- [ ] two\n- [x] three\n\n> quoted _words_\n\n\`\`\`\ncode\n\`\`\`\n\n1. first\n2. second\n\n---\nend`,
  extended: `H~2~O and x^2^ and $a+b$ here.\n\n> [!NOTE]\n> a callout\n> of three lines\n\n> [!WARNING] Careful\n> now\n\nTerm\n: the meaning of it\n\nlast`,
  front: `---\ntitle: A note\nplace: Lisbon\n---\n# After the front matter\nwords`,
  empty: '',
  blank: 'one\n\n\n\nfive',
  // Pieces E and F (lib/editor/marks, lib/editor/items): the twelve marks, and the items drawn in the words.
  marks: 'A ||secret|| here and ==the key== and ==green==(green) words.\nAn %%aside%% and ??unsure??(Sam said so) and @@redacted@@ text.\nA ^^shout^^ and ++added++ and plain.\nThe line above the heat, which wavers.\n🔥🔥too hot🔥🔥 and ❄️❄️frozen❄️❄️ here.\n🌊🌊out to sea🌊🌊 and ✨✨silver✨✨ and 👻👻nobody there👻👻.\n>| the answer is hidden\n# Heading ==lit== and @@bar@@',
  items: '# Packing\n- [x] Tent #gear\n- [ ] Stove @sam ⏫ 📅 2026-10-03\n- [ ] Food 🔁 every week [effort:: 3] 🛫 2026-12-25\n- [ ] Later 📅 2027-03-09 🔽 @ana-ortiz\n## Counts\n- Water [3/8] and [8/8] and [0/50]\n= 450 + 120 * 2\n- ( ) Tent\n- (x) Cabin\nA footnote[^sam] and a [[Known note]] and a [[New note]].\nA bookmarked line §§\n- [ ] Ship the page ^ship-page\nSee [[#^ship-page]] and [[#^gone]] and :tada: here.\n\n[^sam]: Sam said so.',
  open: '# ',
};

/** What pieces E and F draw in the words: every one of these on the page is written to a case's `marks`. */
const DRAWN = '.cm-tag, .cm-field, .cm-fieldInitial, .cm-fieldName, .cm-fieldWords, .cm-field > svg, .cm-counter, .cm-sumAnswer, .cm-headingCount, .cm-choiceBox, .cm-footMark, .cm-wiki, .cm-bookmarkMark, .cm-itemAnchor, .cm-itemRef, .cm-formatLook, .cm-textEffect, .cm-textEffectAbove, .cm-wispFormat, .cm-openHint, .cm-emoji';

/** The cases: a note, how it is shown, and where the caret is (which focuses the editor). */
const CASES = [];
for (const name of Object.keys(DOCS)) {
  // The marks' and the items' notes are drawn by the whole editor only, further down.
  if (['marks', 'items', 'open'].includes(name)) continue;
  CASES.push({ name: `${name}-mixed`, doc: name, display: 'mixed' });
  CASES.push({ name: `${name}-formatted`, doc: name, display: 'formatted' });
}
// Read-only, as a card's preview is: the front matter is shown as its lines.
CASES.push({ name: 'front-readonly', doc: 'front', display: 'mixed', readOnly: true });
// The caret's line shows its marks: a heading, an item, a quote, a line of inline marks.
CASES.push({ name: 'headings-caret', doc: 'headings', display: 'formatted', caret: 9 });
CASES.push({ name: 'inline-caret', doc: 'inline', display: 'formatted', caret: 5 });
CASES.push({ name: 'quotes-caret', doc: 'quotes', display: 'formatted', caret: 12 });
CASES.push({ name: 'tasks-caret', doc: 'tasks', display: 'formatted', caret: 3 });
CASES.push({ name: 'mixed-selection', doc: 'mixed', display: 'formatted', caret: 20, anchor: 60 });
CASES.push({ name: 'extended-caret', doc: 'extended', display: 'mixed', caret: 3 });
// Dark, for the pictures and the colours.
for (const name of ['mixed', 'inline', 'code', 'quotes', 'extended']) CASES.push({ name: `${name}-dark`, doc: name, display: 'mixed', theme: 'dark' });
CASES.push({ name: 'mixed-formatted-dark', doc: 'mixed', display: 'formatted', theme: 'dark' });
// The note in the interface's face: a proportional one, with its optical sizes and its headings' tightening.
for (const name of ['headings', 'bullets', 'ordered', 'tasks', 'inline', 'paragraphs', 'mixed']) CASES.push({ name: `${name}-inter`, doc: name, display: 'mixed', noteFace: 'inter' });
CASES.push({ name: 'mixed-formatted-inter', doc: 'mixed', display: 'formatted', noteFace: 'inter' });
// The larger text sizes.
CASES.push({ name: 'mixed-larger', doc: 'mixed', display: 'mixed', textSize: 'larger' });
// A card's preview: `peek`, formatted, read-only, in NotePeek's box.
CASES.push({ name: 'mixed-peek', doc: 'mixed', display: 'formatted', peek: true });
CASES.push({ name: 'tasks-peek', doc: 'tasks', display: 'formatted', peek: true });
CASES.push({ name: 'mixed-peek-whole', doc: 'mixed', display: 'formatted', peek: true, whole: true });
// The web `Editor` itself, every extension in it, for the pieces after this one.
for (const one of [...CASES]) if (/^(mixed|inline|tasks|headings)-(mixed|formatted|peek)$/.test(one.name)) CASES.push({ ...one, name: `full/${one.name}`, full: true });

// Pieces E and F: the web `Editor` itself over their notes, written beside their own tests.
const MARKS_OUT = new URL('../test/editor/marks/fixtures/', import.meta.url).pathname;
const ITEMS_OUT = new URL('../test/editor/items/fixtures/', import.meta.url).pathname;
mkdirSync(MARKS_OUT, { recursive: true });
mkdirSync(ITEMS_OUT, { recursive: true });
for (const display of ['mixed', 'formatted']) {
  CASES.push({ name: `marks-${display}`, doc: 'marks', display, full: true, out: MARKS_OUT, still: true });
  CASES.push({ name: `items-${display}`, doc: 'items', display, full: true, out: ITEMS_OUT, wiki: true });
}
CASES.push({ name: 'marks-dark', doc: 'marks', display: 'mixed', theme: 'dark', full: true, out: MARKS_OUT, still: true });
CASES.push({ name: 'marks-readonly', doc: 'marks', display: 'mixed', readOnly: true, full: true, out: MARKS_OUT, still: true });
// The caret in the redaction (the bar lifts) and on the fields' line (the chips are their characters again).
CASES.push({ name: 'marks-caret', doc: 'marks', display: 'mixed', caret: 112, full: true, out: MARKS_OUT, still: true });
CASES.push({ name: 'items-caret', doc: 'items', display: 'mixed', caret: 40, full: true, out: ITEMS_OUT, wiki: true });
CASES.push({ name: 'items-readonly', doc: 'items', display: 'formatted', readOnly: true, full: true, out: ITEMS_OUT, wiki: true });
CASES.push({ name: 'items-inter', doc: 'items', display: 'mixed', noteFace: 'inter', full: true, out: ITEMS_OUT, wiki: true });
CASES.push({ name: 'items-peek', doc: 'items', display: 'formatted', peek: true, full: true, out: ITEMS_OUT });
CASES.push({ name: 'open-mixed', doc: 'open', display: 'mixed', full: true, out: ITEMS_OUT, openHeading: true });
// The moving marks at fixed times, for pictures: the page's clock is held at `at` seconds (test/editor/marks).
// Formatted, so the effects' own delimiters (emoji, which no test has a face for) are not on the line.
for (const at of [0, 0.7, 1.9]) CASES.push({ name: `marks-at-${String(at).replace('.', '_')}`, doc: 'marks', display: 'formatted', full: true, out: MARKS_OUT, at });
// And on the dark page, where the shimmer is a glow and not a sheen.
CASES.push({ name: 'marks-dark-at-0', doc: 'marks', display: 'formatted', theme: 'dark', full: true, out: MARKS_OUT, at: 0 });

const only = process.argv.slice(2);
// GLYPH_DSF=2.625 draws the page as a PHONE's WebView does, for test/editor/view/fixtures/device: the browser itself
// is at that many device pixels to one (not emulating it), so the page is laid out in device pixels, a face's
// ascent and a line's top rounded to them, as on a screen of that density. The emulated two of the other cases
// scales the picture of a page laid out at one. GLYPH_OUT says where the base cases are written.
const DSF = Number(process.env.GLYPH_DSF ?? 0);
const browser = await chromium.launch(DSF ? { args: [`--force-device-scale-factor=${DSF}`, '--window-size=390,844'] } : {});
const context = await browser.newContext(DSF ? { viewport: null, hasTouch: true } : { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
const page = await context.newPage();
page.on('pageerror', (error) => console.log('page error:', error.message));
// A page of the dev server's own origin with nothing on it, so the app's modules load and the app does not start.
await page.route('**/__editor_reference', (route) =>
  route.fulfill({
    contentType: 'text/html',
    body: '<!doctype html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body style="margin:0"><div id="stage"></div></body></html>',
  }),
);
await page.goto(`${BASE}__editor_reference`);

// The stylesheets main.tsx loads, in its order, and React as the dev server hands it out.
await page.evaluate(async () => {
  // What @vitejs/plugin-react's preamble sets on the app's own page: its modules ask for it before they run.
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
  // CodeMirror as the dev server hands it to Editor.tsx, and the modules the base editor is made of.
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
  window.PeekModule = await import('/src/app/notes/NotePeek.tsx');
  window.Prefs = await import('/src/app/core/preferences.ts');
  await document.fonts.ready;
});

// Where Blink may break a line between two ASCII characters: its own table (`kAsciiLineBreakTable`), read off the
// engine itself. Each pair is set between letters in a box with no width, where a line breaks at every place it may
// and nowhere else. Written as lib/editor/view/blink_breaks.g.dart, for `PaintText` to tell the paragraph where the
// page's lines may break and where they may not. `node tool/editor_reference.mjs --breaks` writes this alone.
{
  const rows = await page.evaluate(() => {
    const first = 0x21, last = 0x7e;
    const box = document.createElement('div');
    box.style.cssText = 'position:absolute; left:0; top:0; font: 16px monospace; white-space: normal; line-break: auto; word-break: normal; overflow-wrap: normal;';
    const cells = [];
    for (let a = first; a <= last; a += 1) {
      for (let b = first; b <= last; b += 1) {
        const cell = document.createElement('div');
        cell.style.cssText = 'inline-size: 0; white-space: normal;';
        cell.textContent = `xx${String.fromCharCode(a)}${String.fromCharCode(b)}xx`;
        box.append(cell);
        cells.push(cell);
      }
    }
    document.body.append(box);
    const rows = [];
    const range = document.createRange();
    let at = 0;
    for (let a = first; a <= last; a += 1) {
      let row = '';
      for (let b = first; b <= last; b += 1) {
        const text = cells[at].firstChild;
        at += 1;
        range.setStart(text, 2);
        range.setEnd(text, 3);
        const one = range.getBoundingClientRect().top;
        range.setStart(text, 3);
        range.setEnd(text, 4);
        row += range.getBoundingClientRect().top > one + 1 ? '1' : '0';
      }
      rows.push(row);
    }
    box.remove();
    return rows;
  });
  const dart = `// Written by tool/editor_reference.mjs from Chromium itself: do not edit by hand.
//
// Where Blink may break a line between two ASCII characters, '!' (0x21) to '~' (0x7E): a row for the character
// before, a column for the character after, '1' where a line may break between them. Blink's own table
// (\`kAsciiLineBreakTable\`, third_party/blink/renderer/platform/text/text_break_iterator.cc), which it uses in
// place of the Unicode algorithm for these pairs. Each was read with a letter either side of the pair.
const List<String> blinkAsciiBreaks = <String>[
${rows.map((row) => `  '${row}',`).join('\n')}
];
`;
  writeFileSync(new URL('../lib/editor/view/blink_breaks.g.dart', import.meta.url).pathname, dart);
  console.log('breaks', rows.reduce((n, row) => n + [...row].filter((c) => c === '1').length, 0), 'pairs may break');
}
if (only.includes('--breaks')) {
  await browser.close();
  process.exit(0);
}

for (const one of CASES) {
  if (only.length && !only.includes(one.name)) continue;
  const doc = DOCS[one.doc];
  // `still` is reduced motion, which the app reads from the media query (core/motion.ts `prefersStill`).
  await page.emulateMedia({ reducedMotion: one.still ? 'reduce' : 'no-preference' });
  const result = await page.evaluate(
    async ({ one, doc, DRAWN }) => {
      const { React, ReactDOM, EditorModule, PeekModule, Prefs } = window;
      const theme = one.theme ?? 'light';
      Prefs.applyPreferences({ ...Prefs.DEFAULT_PREFERENCES, theme, noteFace: one.noteFace ?? Prefs.DEFAULT_PREFERENCES.noteFace, textSize: one.textSize ?? Prefs.DEFAULT_PREFERENCES.textSize });
      window.root?.unmount();
      window.root = null;
      window.madeView?.destroy();
      window.madeView = null;
      const stage = document.getElementById('stage');
      stage.replaceChildren();
      // A held clock for the moving marks: the frame loop is told `at` seconds, and CSS and SVG animations are set
      // to it below.
      window.realRaf ??= window.requestAnimationFrame.bind(window);
      window.requestAnimationFrame = one.at === undefined ? window.realRaf : (run) => window.realRaf(() => run(one.at * 1000));
      document.body.style.background = 'var(--glacier-bg)';
      const host = document.createElement('div');
      // The page's width, and as tall as the note: the editor grows, as on the note screen.
      host.style.cssText = one.peek ? 'inline-size: 300px; display: flex; flex-direction: column;' : 'inline-size: 390px; display: flex; flex-direction: column;';
      stage.append(host);
      let view = null;
      const peekStyles = (await import('/src/app/notes/NotePeek.module.css')).default;
      const readOnly = one.readOnly || one.peek || false;
      if (one.full) {
        window.root = ReactDOM.createRoot(host);
        const editor = React.createElement(EditorModule.Editor, {
          value: doc,
          onChange: () => {},
          dark: theme === 'dark',
          assist: false,
          display: one.display,
          readOnly,
          peek: one.peek || false,
          grow: true,
          openHeading: one.openHeading || false,
          wiki: one.wiki ? { known: (title) => /^known/i.test(title), open: () => {} } : undefined,
          onView: (made) => {
            view = made;
          },
        });
        // A card's preview is the editor inside NotePeek's box (notes/NotePeek.tsx), without the wait for the screen.
        window.root.render(one.peek ? React.createElement('span', { className: peekStyles.peek, 'data-whole': one.whole ? '' : undefined, style: one.whole ? undefined : { maxBlockSize: 'none' } }, editor) : editor);
      } else {
        const { CM, Base } = window;
        let parent = host;
        if (one.peek) {
          parent = document.createElement('span');
          parent.className = peekStyles.peek;
          if (one.whole) parent.setAttribute('data-whole', '');
          else parent.style.maxBlockSize = 'none';
          host.append(parent);
        }
        // Editor.tsx's host: `<div className={styles.editor} data-grow data-view={display}>`.
        const editorHost = document.createElement('div');
        editorHost.className = Base.styles.editor;
        editorHost.setAttribute('data-grow', 'true');
        editorHost.setAttribute('data-view', one.display);
        parent.append(editorHost);
        const grow = CM.view.EditorView.theme({
          '&.cm-editor': { height: 'auto', minHeight: '100%', flex: '1 0 auto' },
          '&.cm-editor .cm-scroller': { overflowY: 'visible', overscrollBehavior: 'auto', flex: '1 0 auto' },
        });
        view = new CM.view.EditorView({
          parent: editorHost,
          state: CM.state.EditorState.create({
            doc,
            extensions: [
              Base.language.glyphMarkdown([]),
              CM.language.syntaxHighlighting(Base.highlight.glyphHighlight),
              Base.lines.glyphLines,
              Base.extended.extendedMarkdown(),
              CM.view.EditorView.lineWrapping,
              CM.view.EditorView.contentAttributes.of({ autocorrect: 'off', autocapitalize: 'off', spellcheck: 'false', inputmode: 'text', enterkeyhint: 'enter' }),
              Base.theme.glyphTheme(theme === 'dark'),
              [CM.state.EditorState.readOnly.of(readOnly), CM.view.EditorView.editable.of(!readOnly)],
              Base.viewMode.noteView(one.display),
              CM.state.Prec.highest(grow),
            ],
          }),
        });
        window.madeView = view;
      }
      await new Promise((done) => setTimeout(done, 120));
      await document.fonts.ready;
      if (one.caret !== undefined) {
        view.focus();
        view.dispatch({ selection: { anchor: one.anchor ?? one.caret, head: one.caret } });
      }
      await new Promise((done) => setTimeout(done, 250));
      // CodeMirror measured its lines before glyphLines gave the items their hang, which can wrap one a line
      // further; it finds that out at its next measure, which on the page is the first scroll or keystroke.
      // Asked for here, so `posAtCoords` (which looks a line up by its measured height) is the settled page's.
      view.requestMeasure();
      await new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));
      if (one.at !== undefined) {
        for (const svg of document.querySelectorAll('svg')) {
          svg.pauseAnimations?.();
          svg.setCurrentTime?.(one.at);
        }
        for (const animation of document.getAnimations()) {
          animation.pause();
          // A letter's negative delay is its phase: the clock's time is laid over it.
          animation.currentTime = one.at * 1000;
        }
        await new Promise((done) => window.realRaf(() => window.realRaf(done)));
      }
      const origin = host.getBoundingClientRect();
      const rect = (r) => (r ? { left: +(r.left - origin.left).toFixed(3), top: +(r.top - origin.top).toFixed(3), right: +(r.right - origin.left).toFixed(3), bottom: +(r.bottom - origin.top).toFixed(3) } : null);
      const lines = [];
      const blocks = [];
      for (const el of view.contentDOM.children) {
        const box = rect(el.getBoundingClientRect());
        if (!el.classList.contains('cm-line')) {
          blocks.push({ classes: [...el.classList], rect: box });
          continue;
        }
        const from = view.posAtDOM(el, 0);
        const line = view.state.doc.lineAt(from);
        const style = getComputedStyle(el);
        // The line's first run of text, for its ink and its face.
        const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
        const runs = [];
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          const at = getComputedStyle(node.parentElement);
          // Every class between the text and its line: a mark inside a mark is two elements.
          const over = [];
          for (let up = node.parentElement; up && up !== el; up = up.parentElement) over.push(...up.classList);
          runs.push({ text: node.textContent, classes: over.map((c) => c.replace(/^_|_[a-z0-9]+_\d+$/gi, '')), color: at.color, family: at.fontFamily.split(',')[0].replace(/['"]/g, ''), size: parseFloat(at.fontSize), weight: at.fontWeight, style: at.fontStyle, decoration: at.textDecorationLine });
        }
        lines.push({
          from: line.from,
          to: line.to,
          text: line.text,
          // CSS-module names are `_name_hash_n` in the dev server: the name alone.
          classes: [...el.classList].filter((c) => c !== 'cm-line').map((c) => c.replace(/^_|_[a-z0-9]+_\d+$/gi, '')),
          style: el.getAttribute('style') ?? '',
          rect: box,
          background: style.backgroundColor,
          color: style.color,
          runs,
        });
      }
      const marks = [];
      for (const el of view.contentDOM.querySelectorAll(DRAWN)) {
        const at = getComputedStyle(el);
        const attrs = {};
        for (const attr of el.attributes) if (attr.name !== 'class') attrs[attr.name] = attr.value;
        let pos = null;
        try {
          pos = view.posAtDOM(el);
        } catch {
          pos = null;
        }
        marks.push({
          classes: [...(el.classList ?? [])].map((c) => c.replace(/^_|_[a-z0-9]+_\d+$/gi, '')),
          tag: el.tagName.toLowerCase(),
          text: el.textContent,
          attrs,
          pos,
          rect: rect(el.getBoundingClientRect()),
          rects: [...el.getClientRects()].map(rect),
          color: at.color,
          background: at.backgroundColor,
          size: parseFloat(at.fontSize),
          weight: at.fontWeight,
          family: at.fontFamily.split(',')[0].replace(/['"]/g, ''),
          decoration: at.textDecoration,
          opacity: at.opacity,
          top: at.top,
          filter: at.filter,
          shadow: at.textShadow,
        });
      }
      const now = new Date();
      const today = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
      const coords = [];
      for (let pos = 0; pos <= view.state.doc.length; pos += 1) {
        coords.push({ pos, after: rect(view.coordsAtPos(pos, 1)), before: rect(view.coordsAtPos(pos, -1)) });
      }
      const hits = [];
      const content = view.contentDOM.getBoundingClientRect();
      for (let y = content.top + 3; y < Math.min(content.bottom, 840); y += 11) {
        for (let x = 4; x < 390; x += 17) {
          hits.push({ x: +(x - origin.left).toFixed(2), y: +(y - origin.top).toFixed(2), pos: view.posAtCoords({ x, y }, false), precise: view.posAtCoords({ x, y }) });
        }
      }
      const root = getComputedStyle(document.documentElement);
      const scroller = getComputedStyle(view.scrollDOM);
      return {
        doc,
        display: one.display,
        theme,
        noteFace: one.noteFace ?? 'maple',
        textSize: one.textSize ?? 'large',
        readOnly: one.readOnly || one.peek || false,
        full: one.full || false,
        peek: one.peek || false,
        whole: one.whole || false,
        caret: one.caret ?? null,
        anchor: one.anchor ?? null,
        width: origin.width,
        content: rect(content),
        editor: rect(view.dom.getBoundingClientRect()),
        face: { family: scroller.fontFamily, size: parseFloat(scroller.fontSize), lineHeight: scroller.lineHeight, color: getComputedStyle(view.dom).color, page: root.getPropertyValue('--glacier-bg') },
        lines,
        blocks,
        marks,
        today,
        locale: navigator.language,
        ratio: window.devicePixelRatio,
        at: one.at ?? null,
        coords,
        hits,
        clip: { x: 0, y: 0, width: Math.ceil(origin.width), height: Math.min(844, Math.ceil(view.dom.getBoundingClientRect().bottom - origin.top)) },
      };
    },
    { one, doc, DRAWN },
  );
  const { clip, ...kept } = result;
  const out = one.out ?? OUT;
  writeFileSync(`${out}${one.name}.json`, `${JSON.stringify(kept)}\n`);
  writeFileSync(`${out}${one.name}.png`, await page.screenshot({ clip: { ...clip, height: Math.max(1, clip.height) } }));
  console.log(one.name, kept.lines.length, 'lines');
}

await browser.close();
