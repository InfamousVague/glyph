// The web app's drawn boards, drawn by Chromium, for lib/editor/boards to be held against
// (test/editor/boards/reference_test.dart). Modelled on test/editor/tables/fixtures/reference.mjs: each case is a
// fixture note on a page 390 x 844 at two device pixels to the logical one, the editor's box at the page's corner, so
// every rectangle is in the editor's own coordinates.
//
// The editor measured is the BASE one of tool/editor_reference.mjs with `drawnBoards()` of
// ../glyph/src/app/editor/boards.ts and the chips' stylesheet (`fieldChipTheme` of fieldChips.ts, which the app's
// own editor has from taskFields.ts) added and nothing else. Unlike the tables' page the editor keeps the screen's
// width (`.cm-scroller` scrolls): a board is told its room from the scroller's width (boards.ts `boardRoom`).
//
// For each case it writes test/editor/boards/fixtures/<name>.json:
//   lines   every `.cm-line`: its document range and rectangle
//   boards  every `.cm-boardWrap`: its rectangle, the `.cm-board`'s (and how far it scrolls), the line under it and
//           its grip, and each column: its rectangle and ground, its head (words, count, +), its stack, each card
//           (rectangle, ground, the tick or the dot, the words line by line, the chips, the plugin's mark, the more
//           button and the two arrows), the empty place (picture, words, the drop words), and the + field if open
//   ghost   the card in the air, where a case holds one
// and test/editor/boards/fixtures/<name>.png, the picture.
//
//   (cd ../glyph && npx vite --port 5275 --strictPort --host 127.0.0.1) &     # read-only: never `vite build` there
//   node test/editor/boards/fixtures/reference.mjs [name ...]
//
// Playwright is not this repository's: it is taken from the npx cache, as tool/editor_reference.mjs takes it.
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { mkdirSync, writeFileSync } from 'node:fs';

const BASE = process.env.GLYPH_DEV ?? 'http://127.0.0.1:5275/';
const OUT = new URL('./', import.meta.url).pathname;

/** The day the page counts a due date from. */
const TODAY = '2026-10-08';

/** The fixture notes. */
const DOCS = {
  // boards.test.ts's own note.
  simple: ['# Launch week', '', '```board', 'To do: ship-page', 'Done: pick-date', '```', '', '- [ ] Ship the pricing page ^ship-page', '- [x] Pick a launch date ^pick-date', ''].join('\n'),
  // Every kind of card and every kind of empty lane.
  cards: [
    'Before',
    '',
    '```board',
    'To do: long-one, fields, linked, step, gone-card, plain',
    'Doing:',
    'Done: done-one',
    'Ideas:',
    '```',
    '',
    '- [ ] The quick brown fox jumps over the lazy dog, then turns round and does it again for the sign-in page, and once more for the people at the back of the hall ^long-one',
    '- [ ] Fix the login loop @sam ⏫ 📅 2026-10-03 ^fields',
    '- [ ] Ask about the copy [notion](https://www.notion.so/abc) ^linked',
    '- A bullet with no box ^step',
    '- [ ] Short ^plain',
    '- [x] Pick a launch date 🔼 📅 2026-10-08 @matt-w ^done-one',
    '',
    'After',
  ].join('\n'),
  // A height from the fence, and a lane with more cards than it shows.
  sized: [
    '```board height=9',
    'To do: a, b, c, d, e, f',
    'Doing: g',
    'Done:',
    '```',
    '',
    '- [ ] Card a ^a',
    '- [ ] Card b ^b',
    '- [ ] Card c ^c',
    '- [ ] Card d ^d',
    '- [ ] Card e ^e',
    '- [ ] Card f ^f',
    '- [ ] Card g 🔽 ^g',
    '',
    'After',
  ].join('\n'),
  // One lane much longer than the others, left to its own height: the board is pinned at it.
  tall: ['```board', 'To do: a, b, c', 'Doing:', 'Done: d', '```', '', '- [ ] Card a ^a', '- [ ] Card b ^b', '- [ ] Card c ^c', '- [x] Card d ^d'].join('\n'),
};

const at = (doc, words) => DOCS[doc].indexOf(words);

/** The cases: a note, whether it can be edited, where the caret is, and what is done to the board first. */
const CASES = [];
for (const name of Object.keys(DOCS)) {
  CASES.push({ name, doc: name });
  CASES.push({ name: `${name}-dark`, doc: name, theme: 'dark' });
}
CASES.push({ name: 'cards-readonly', doc: 'cards', readOnly: true });
// The caret in the fence: its lines, to edit. And outside it, in a focused view: drawn.
CASES.push({ name: 'simple-inside', doc: 'simple', caret: at('simple', 'To do:') + 2 });
CASES.push({ name: 'simple-outside', doc: 'simple', caret: 2 });
// The larger text, and the note in the interface's face.
CASES.push({ name: 'cards-larger', doc: 'cards', textSize: 'larger' });
CASES.push({ name: 'cards-inter', doc: 'cards', noteFace: 'inter' });
CASES.push({ name: 'simple-formatted', doc: 'simple', display: 'formatted' });
// Scrolled along: the second lane at the start, and the last at the end.
CASES.push({ name: 'cards-second', doc: 'cards', scroll: 1 });
CASES.push({ name: 'cards-end', doc: 'cards', scroll: 99999 });
// The + pressed on a lane: the field a card is typed into, empty, and with words.
CASES.push({ name: 'simple-compose', doc: 'simple', compose: 0 });
CASES.push({ name: 'simple-compose-dark', doc: 'simple', compose: 0, theme: 'dark' });
CASES.push({ name: 'simple-composed', doc: 'simple', compose: 1, typed: 'Book the ferry' });
// A card held: the gap it leaves, every lane a target, and the copy in the air.
CASES.push({ name: 'cards-held', doc: 'cards', hold: 'fields' });
CASES.push({ name: 'cards-held-dark', doc: 'cards', hold: 'fields', theme: 'dark' });
// Held and carried over the empty second lane.
CASES.push({ name: 'cards-carried', doc: 'cards', hold: 'plain', carry: { dx: 150, dy: -60 } });
// A lane scrolled to its foot: no more below.
CASES.push({ name: 'sized-foot', doc: 'sized', lane: 99999 });

const only = process.argv.slice(2);
// IN A PHONE'S OWN PIXELS. `GLYPH_RATIO=2.625 node …/reference.mjs` draws each note again as a phone lays it out
// (Chromium launched at that scale lays out in device pixels; told a scale by Playwright it lays out in whole CSS
// ones: test/editor/tables/fixtures/reference.mjs, docs/REFERENCES.md) and writes them to fixtures/phone/, a
// window of 475, the Fold's cover screen.
const RATIO = Number(process.env.GLYPH_RATIO ?? 0);
const WIDTH = RATIO ? Math.floor(1248 / RATIO) : 390;
if (RATIO) mkdirSync(`${OUT}phone`, { recursive: true });
const browser = await chromium.launch(RATIO ? { args: [`--force-device-scale-factor=${RATIO}`, `--window-size=${WIDTH},2400`] } : {});
const context = await browser.newContext(RATIO ? { viewport: null, hasTouch: true } : { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
const page = await context.newPage();
page.on('pageerror', (error) => console.log('page error:', error.message));
// A page of the dev server's own origin with nothing on it, so the app's modules load and the app does not start.
await page.route('**/__boards_reference', (route) =>
  route.fulfill({
    contentType: 'text/html',
    body: '<!doctype html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body style="margin:0"><div id="stage"></div></body></html>',
  }),
);
// The page's clock says TODAY at noon, so a due day reads the same whenever this is run.
await page.clock.install({ time: new Date(`${TODAY}T12:00:00`) });
await page.goto(`${BASE}__boards_reference`);
await page.clock.resume();

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
    boards: await import('/src/app/editor/boards.ts'),
    chips: await import('/src/app/editor/fieldChips.ts'),
    styles: (await import('/src/app/editor/markdown.module.css')).default,
  };
  window.Prefs = await import('/src/app/core/preferences.ts');
  await document.fonts.ready;
});

for (const one of CASES) {
  if (only.length && !only.includes(one.name)) continue;
  // In a phone's pixels: each note as it is, in the dark, and one that cannot be changed.
  if (RATIO && !(one.name === one.doc || one.name === `${one.doc}-dark` || one.name === 'cards-readonly')) continue;
  const doc = DOCS[one.doc];
  const result = await page.evaluate(
    async ({ one, doc, WIDTH }) => {
      const { CM, Base, Prefs } = window;
      const theme = one.theme ?? 'light';
      const display = one.display ?? 'mixed';
      Prefs.applyPreferences({ ...Prefs.DEFAULT_PREFERENCES, theme, noteFace: one.noteFace ?? Prefs.DEFAULT_PREFERENCES.noteFace, textSize: one.textSize ?? Prefs.DEFAULT_PREFERENCES.textSize });
      window.madeView?.destroy();
      window.madeView = null;
      document.querySelectorAll('.cm-boardGhost').forEach((ghost) => ghost.parentElement?.remove());
      const stage = document.getElementById('stage');
      stage.replaceChildren();
      document.body.style.background = 'var(--glacier-bg)';
      const host = document.createElement('div');
      // The note's own scroller is the page: the editor is as tall as its words, and as wide as the screen.
      host.style.cssText = `inline-size: ${WIDTH}px; display: flex; flex-direction: column;`;
      stage.append(host);
      const readOnly = one.readOnly || false;
      const editorHost = document.createElement('div');
      editorHost.className = Base.styles.editor;
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
            Base.boards.drawnBoards(),
            Base.chips.fieldChipTheme,
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
      CM.language.forceParsing(view, view.state.doc.length, 1000);
      const frames = () => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));
      const wait = (ms) => new Promise((done) => setTimeout(done, ms));
      await wait(120);
      await document.fonts.ready;
      if (one.caret !== undefined) {
        view.focus();
        view.dispatch({ selection: { anchor: one.anchor ?? one.caret, head: one.caret } });
      }
      await wait(250);
      view.requestMeasure();
      await frames();
      const board0 = view.dom.querySelector('.cm-board');
      if (one.scroll !== undefined && board0) {
        board0.style.scrollSnapType = 'none';
        if (one.scroll === 1) board0.scrollLeft = board0.children[1].offsetLeft - parseFloat(getComputedStyle(board0).paddingLeft);
        else board0.scrollLeft = one.scroll;
        await frames();
      }
      if (one.lane !== undefined && board0) {
        const stack = board0.querySelector('.cm-boardStack');
        stack.scrollTop = one.lane;
        await frames();
        await wait(60);
      }
      if (one.compose !== undefined) {
        const plus = view.dom.querySelectorAll('.cm-boardAdd')[one.compose];
        plus.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
        await frames();
        const field = view.dom.querySelector('.cm-boardComposeField');
        if (one.typed) {
          field.value = one.typed;
          field.dispatchEvent(new Event('input', { bubbles: true }));
        }
        field.blur();
        await frames();
      }
      let held = null;
      if (one.hold) {
        const card = view.dom.querySelector(`.cm-boardCard[data-card="${one.hold}"]`);
        const box = card.getBoundingClientRect();
        const x = box.left + 40;
        const y = box.top + 14;
        const fire = (target, type, px, py) => target.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, pointerId: 7, pointerType: 'touch', button: 0, clientX: px, clientY: py }));
        fire(card.querySelector('.cm-boardWords'), 'pointerdown', x, y);
        await wait(300);
        held = { x, y };
        if (one.carry) {
          held = { x: x + one.carry.dx, y: y + one.carry.dy };
          fire(window, 'pointermove', held.x, held.y);
        }
        await frames();
      }
      const origin = host.getBoundingClientRect();
      const rect = (r) => (r ? { left: +(r.left - origin.left).toFixed(3), top: +(r.top - origin.top).toFixed(3), right: +(r.right - origin.left).toFixed(3), bottom: +(r.bottom - origin.top).toFixed(3) } : null);
      const box = (el) => (el ? rect(el.getBoundingClientRect()) : null);
      const wordsOf = (el) => {
        if (!el) return [];
        const range = document.createRange();
        range.selectNodeContents(el);
        return [...range.getClientRects()].map(rect);
      };
      const face = (el) => {
        const style = getComputedStyle(el);
        return { color: style.color, size: parseFloat(style.fontSize), weight: style.fontWeight, family: style.fontFamily.split(',')[0].replace(/['"]/g, ''), style: style.fontStyle, decoration: style.textDecorationLine, opacity: style.opacity, spacing: style.letterSpacing };
      };
      const lines = [];
      const boards = [];
      const cardOf = (card) => {
        const style = getComputedStyle(card);
        const tick = card.querySelector('.cm-boardTick');
        const dot = card.querySelector('.cm-boardDot');
        const words = card.querySelector('.cm-boardWords');
        const fields = card.querySelector('.cm-boardFields');
        const linked = card.querySelector('.cm-boardLinked');
        return {
          id: card.dataset.card,
          done: card.dataset.done !== undefined,
          gone: card.dataset.gone !== undefined,
          empty: card.dataset.empty !== undefined,
          lifted: card.dataset.lifted !== undefined,
          rect: box(card),
          background: style.backgroundColor,
          shadow: style.boxShadow,
          opacity: style.opacity,
          radius: style.borderTopLeftRadius,
          tick: tick ? { rect: box(tick), border: getComputedStyle(tick).borderTopColor, background: getComputedStyle(tick).backgroundColor, disabled: tick.disabled, label: tick.getAttribute('aria-label'), check: box(tick.querySelector('svg')), shown: getComputedStyle(tick.querySelector('svg')).visibility, color: getComputedStyle(tick).color } : null,
          dot: dot ? { rect: box(dot), background: getComputedStyle(dot).backgroundColor } : null,
          words: { text: words.textContent, rect: box(words), lines: wordsOf(words), label: words.getAttribute('aria-label'), ...face(words) },
          fields: fields ? { rect: box(fields), chips: [...fields.children].map((chip) => ({ rect: box(chip), text: chip.textContent, tone: chip.dataset.tone ?? null, label: chip.getAttribute('aria-label'), tag: chip.tagName, ...face(chip) })) } : null,
          linked: linked ? { rect: box(linked), icon: box(linked.querySelector('svg')), name: linked.querySelector('svg').dataset.icon, label: linked.getAttribute('aria-label'), color: getComputedStyle(linked).color, opacity: getComputedStyle(linked).opacity } : null,
          more: (() => {
            const more = card.querySelector('.cm-boardMore');
            return { rect: box(more), icon: box(more.querySelector('svg')), color: getComputedStyle(more).color, opacity: getComputedStyle(more).opacity, label: more.getAttribute('aria-label') };
          })(),
          moves: [...card.querySelectorAll('.cm-boardMove')].map((move) => ({ rect: box(move), icon: box(move.querySelector('svg')), disabled: move.disabled, opacity: getComputedStyle(move).opacity, label: move.getAttribute('aria-label') })),
        };
      };
      for (const el of view.contentDOM.children) {
        if (el.classList.contains('cm-line')) {
          const from = view.posAtDOM(el, 0);
          const line = view.state.doc.lineAt(from);
          lines.push({ from: line.from, to: line.to, text: line.text, rect: rect(el.getBoundingClientRect()) });
          continue;
        }
        if (!el.classList.contains('cm-boardWrap')) continue;
        const board = el.querySelector(':scope > .cm-board');
        const split = el.querySelector(':scope > .cm-boardSplit');
        const grip = split.querySelector('.cm-boardGrip');
        const columns = [...board.querySelectorAll(':scope > .cm-boardColumn')].map((pane) => {
          const head = pane.querySelector(':scope > .cm-boardName');
          const name = head.querySelector('.cm-boardNameWords');
          const count = head.querySelector('.cm-boardCount');
          const add = head.querySelector('.cm-boardAdd');
          const stack = pane.querySelector(':scope > .cm-boardStack');
          const empty = stack.querySelector('.cm-boardEmpty');
          const rest = empty.querySelector('.cm-boardEmptyRest');
          const drop = empty.querySelector('.cm-boardEmptyDrop');
          const form = pane.querySelector(':scope > .cm-boardCompose');
          const emptyStyle = getComputedStyle(empty);
          return {
            label: pane.getAttribute('aria-label'),
            rect: box(pane),
            background: getComputedStyle(pane).backgroundColor,
            radius: getComputedStyle(pane).borderTopLeftRadius,
            head: box(head),
            name: { text: name.textContent, rect: box(name), lines: wordsOf(name), ...face(name) },
            count: { text: count.textContent, rect: box(count), lines: wordsOf(count), background: getComputedStyle(count).backgroundColor, ...face(count) },
            add: { rect: box(add), icon: box(add.querySelector('svg')), background: getComputedStyle(add).backgroundColor, color: getComputedStyle(add).color, label: add.getAttribute('aria-label') },
            stack: { rect: box(stack), scrollHeight: stack.scrollHeight, clientHeight: stack.clientHeight, scrollTop: stack.scrollTop, more: stack.hasAttribute('data-more'), over: stack.hasAttribute('data-over'), smoke: stack.dataset.smoke ?? null, fade: stack.style.getPropertyValue('--cm-lane-fade') || null },
            cards: [...stack.querySelectorAll('.cm-boardCard')].map(cardOf),
            empty: {
              shown: emptyStyle.display !== 'none',
              none: empty.dataset.none !== undefined,
              rect: emptyStyle.display === 'none' ? null : box(empty),
              border: emptyStyle.borderTopColor,
              borderStyle: emptyStyle.borderTopStyle,
              color: emptyStyle.color,
              size: parseFloat(emptyStyle.fontSize),
              icon: getComputedStyle(rest).display === 'none' ? null : { rect: box(rest.querySelector('svg')), name: rest.querySelector('svg').dataset.icon, opacity: getComputedStyle(rest.querySelector('svg')).opacity },
              words: getComputedStyle(rest).display === 'none' ? null : { text: rest.querySelector('span').textContent, lines: wordsOf(rest.querySelector('span')) },
              drop: getComputedStyle(drop).display === 'none' ? null : { text: drop.textContent, lines: wordsOf(drop) },
            },
            compose: form
              ? (() => {
                  const tick = form.querySelector('.cm-boardComposeTick');
                  const field = form.querySelector('.cm-boardComposeField');
                  const button = form.querySelector('.cm-boardComposeAdd');
                  return {
                    rect: box(form),
                    background: getComputedStyle(form).backgroundColor,
                    shadow: getComputedStyle(form).boxShadow,
                    tick: { rect: box(tick), border: getComputedStyle(tick).borderTopColor },
                    field: { rect: box(field), value: field.value, placeholder: field.placeholder, placeholderColor: getComputedStyle(field, '::placeholder').color, ...face(field) },
                    add: { rect: box(button), lines: wordsOf(button), disabled: button.disabled, background: getComputedStyle(button).backgroundColor, radius: getComputedStyle(button).borderTopLeftRadius, ...face(button) },
                  };
                })()
              : null,
          };
        });
        boards.push({
          from: view.posAtDOM(el),
          rect: box(el),
          board: box(board),
          scrollLeft: board.scrollLeft,
          scrollWidth: board.scrollWidth,
          clientWidth: board.clientWidth,
          sized: board.hasAttribute('data-sized'),
          pinned: board.dataset.pinned !== undefined,
          pin: board.style.getPropertyValue('--cm-board-pin') || null,
          laneHeight: board.style.getPropertyValue('--cm-lane-height') || null,
          holding: board.hasAttribute('data-holding'),
          wisp: board.dataset.wisp ?? null,
          size: parseFloat(getComputedStyle(board).fontSize),
          color: getComputedStyle(board).color,
          split: { rect: box(split), background: getComputedStyle(split).backgroundColor, now: split.getAttribute('aria-valuenow') },
          grip: { rect: box(grip), background: getComputedStyle(grip).backgroundColor },
          columns,
        });
      }
      const ghostEl = document.querySelector('.cm-boardGhost');
      const ghost = ghostEl ? { rect: box(ghostEl), shadow: getComputedStyle(ghostEl).boxShadow, opacity: getComputedStyle(ghostEl).opacity, card: ghostEl.dataset.card } : null;
      const root = getComputedStyle(document.documentElement);
      return {
        doc,
        display,
        theme,
        noteFace: one.noteFace ?? 'maple',
        textSize: one.textSize ?? 'large',
        readOnly,
        caret: one.caret ?? null,
        scroll: one.scroll ?? null,
        lane: one.lane ?? null,
        compose: one.compose ?? null,
        typed: one.typed ?? null,
        hold: one.hold ?? null,
        held,
        width: origin.width,
        content: rect(view.contentDOM.getBoundingClientRect()),
        page: root.getPropertyValue('--glacier-bg'),
        lines,
        boards,
        ghost,
        clip: { x: 0, y: 0, width: WIDTH, height: Math.min(2300, Math.ceil(view.dom.getBoundingClientRect().bottom - origin.top)) },
      };
    },
    { one, doc, WIDTH },
  );
  const { clip, ...kept } = result;
  if (RATIO) Object.assign(kept, { ratio: RATIO, screen: WIDTH });
  const out = RATIO ? `${OUT}phone/` : OUT;
  kept.today = TODAY;
  kept.locale = await page.evaluate(() => navigator.language);
  writeFileSync(`${out}${one.name}.json`, `${JSON.stringify(kept)}\n`);
  const last = Math.max(...kept.lines.map((l) => l.rect.bottom), ...kept.boards.map((b) => b.rect.bottom), 1);
  writeFileSync(`${out}${one.name}.png`, await page.screenshot({ clip: { ...clip, height: Math.max(1, Math.min(clip.height, Math.ceil(last) + 24)) } }));
  // A held card is let go again, so the next case starts with nothing in the air.
  if (one.hold) await page.evaluate(() => window.dispatchEvent(new PointerEvent('pointercancel', { pointerId: 7, pointerType: 'touch' })));
  console.log(one.name, kept.lines.length, 'lines', kept.boards.length, 'boards', kept.boards.map((b) => b.columns.map((c) => c.cards.length).join('/')).join(' '));
}

await browser.close();
