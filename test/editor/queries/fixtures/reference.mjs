// The web app's drawn queries and its ticket panel, drawn by Chromium, for lib/editor/queries and lib/editor/tickets
// to be held against (test/editor/queries/reference_test.dart, test/editor/tickets/reference_test.dart). Modelled on
// test/editor/boards/fixtures/reference.mjs: each case is a fixture note on a page 390 x 844 at two device pixels to
// the logical one, the editor's box at the page's corner, so every rectangle is in the editor's own coordinates.
//
// The editor measured is the BASE one of tool/editor_reference.mjs with `drawnBoards()` (for the room it tells a
// block, boards.ts `boardRoom`), `drawnMermaid()` (a note's editor always has it, Editor.tsx, and its theme's
// `.cm-mermaid` is the timeline's block too: the 0.6em above and under Mermaid's gantt in a card are that rule's),
// `tags()`, `wikiLinks()`, `queries()` of ../glyph/src/app/editor/queries.ts over the fixed library below, and
// `tickets()` of editor/tickets.ts over its tickets.
//
// For each case it writes <name>.json beside this file (a query's) or in ../../tickets/fixtures (a ticket's):
//   lines   every `.cm-line`: its document range and rectangle
//   blocks  every `.cm-query` and `.cm-ticketPanel`: its rectangle, and `parts`, every element inside it in the
//           order the page has them: the names its stylesheet gives it (QueryView.module.css's or
//           TicketPanel.module.css's own, and the editor's `cm-field`, `cm-tag`…), its tag, its rectangle, its
//           colours, its type, what it says, and the boxes of the words that are its own
//   titles  every `.cm-ticketTitle` after a `[[GHO-12]]`: its rectangle, its words, its dot
// and <name>.png, the picture.
//
//   (cd ../glyph && npx vite --port 5280 --strictPort --host 127.0.0.1) &     # read-only: never `vite build` there
//   node test/editor/queries/fixtures/reference.mjs [name ...]
//
// Playwright is not this repository's: it is taken from the npx cache, as tool/editor_reference.mjs takes it.
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { mkdirSync, writeFileSync } from 'node:fs';

const BASE = process.env.GLYPH_DEV ?? 'http://127.0.0.1:5280/';
const OUT = new URL('./', import.meta.url).pathname;
const TICKETS_OUT = new URL('../../tickets/fixtures/', import.meta.url).pathname;

/** The day the page counts a due date from. */
const TODAY = '2026-10-08';

/** The library every query reads: a notebook, its four tickets, and a note of to-dos. */
const LIBRARY = [
  { id: 'shop', body: '# Groceries\n\n- [ ] Milk 📅 2026-10-07 @sam\n- [x] Eggs\n- [ ] Bread ⏫ 📅 2026-10-08\n- [ ] Butter for the #dairy shelf 📅 2026-10-12\n- [ ] Call the plumber about the tap in the upstairs bathroom before the weekend 🔽\n' },
  { id: 'launch', body: '---\nbook: true\nkey: GHO\n---\n# Launch\n\n- [[Fix the login loop]]\n- [[Ship the pricing page]]\n- [[Write the changelog]]\n- [[Draw the icons]]\n' },
  { id: 'gho1', body: '---\ntype: ticket\nid: GHO-1\nstatus: In progress\nassignee: Sam\npriority: high\nestimate: 3\nstart: 2026-10-01\ndue: 2026-10-06\n---\n# Fix the login loop\n' },
  { id: 'gho2', body: '---\ntype: ticket\nid: GHO-2\nstatus: To do\nassignee: Priya Shah\npriority: medium\nestimate: 2\ndue: 2026-10-12\n---\n# Ship the pricing page\n' },
  { id: 'gho3', body: '---\ntype: ticket\nid: GHO-3\nstatus: Done\npriority: low\nestimate: 1\nstart: 2026-09-28\ndue: 2026-10-02\n---\n# Write the changelog\n' },
  { id: 'gho4', body: '---\ntype: ticket\nid: GHO-4\nstatus: In review\nlabels: [bug, ui]\nstart: 2026-10-08\ndue: 2026-10-20\n---\n# Draw the icons, every one of them, in the three sizes the phone asks for\n' },
].map((note) => ({ ...note, createdAt: Date.parse('2026-10-01T09:00:00'), updatedAt: Date.parse('2026-10-06T09:00:00') }));

const fence = (lines, settings = '') => `# This week\n\n\`\`\`query${settings}\n${lines}\n\`\`\`\n\nAfter\n`;

/** The fixture notes, each a query, or a ticket. */
const DOCS = {
  list: fence('from: tasks'),
  'list-grouped': fence('from: tickets\ngroup: status\nshow: list'),
  'list-notes': fence('from: notes'),
  table: fence('from: tickets\ntotal: estimate'),
  'table-tasks': fence('from: tasks\nshow: table'),
  'table-grouped': fence('from: tickets\ngroup: status\ncolumns: id, title, priority, estimate\ntotal: estimate'),
  board: fence('from: tickets\nshow: board'),
  'board-sized': fence('from: tickets\nshow: board', ' height=12'),
  'board-tasks': fence('from: tasks\nshow: board\ngroup: priority'),
  calendar: fence('from: tasks\nshow: calendar'),
  'calendar-tickets': fence('from: tickets\nshow: calendar'),
  count: fence('from: tickets\nshow: count\ntotal: estimate'),
  gantt: fence('from: tickets\nshow: gantt\ngroup: status'),
  problem: fence('from: tickets\nwhere: status ='),
  empty: fence('from: tickets\nwhere: status = Nope'),
  warning: fence('from: tickets [[Nowhere]]'),
  ticket: '---\ntype: ticket\nid: GHO-12\nstatus: In progress\nassignee: Sam\npriority: high\ndue: 2026-10-06\nblocked-by: "[[GHO-2]]"\nauthors: Matt\n---\n# Fix the login loop\n\nSee [[GHO-1]], [[GHO-3]] and [[GHO-404]].\n',
  'ticket-bare': '---\ntype: ticket\nstatus: To do\n---\n# A new one\n',
  'ticket-full': '---\ntype: ticket\nid: GHO-12\nstatus: Done\nassignee: Priya Shah\npriority: lowest\ndue: 2026-10-08\nstart: 2026-10-01\nestimate: 3\nblocked-by: ["[[GHO-2]]", "[[GHO-3]]"]\nparent: "[[GHO-1]]"\nlabels: [bug, ui]\n---\n# Fix the login loop\n',
};

const CASES = [];
for (const name of Object.keys(DOCS)) {
  CASES.push({ name, doc: name });
  CASES.push({ name: `${name}-dark`, doc: name, theme: 'dark' });
}
CASES.push({ name: 'table-readonly', doc: 'table', readOnly: true });
CASES.push({ name: 'board-readonly', doc: 'board', readOnly: true });
CASES.push({ name: 'list-readonly', doc: 'list', readOnly: true });
CASES.push({ name: 'ticket-readonly', doc: 'ticket', readOnly: true });
CASES.push({ name: 'ticket-full-readonly', doc: 'ticket-full', readOnly: true });
CASES.push({ name: 'ticket-more', doc: 'ticket', more: true });
// The caret in the fence: its lines, to edit.
CASES.push({ name: 'list-inside', doc: 'list', caret: DOCS.list.indexOf('from:') + 2 });
CASES.push({ name: 'ticket-inside', doc: 'ticket', caret: 6 });
// The + pressed on a lane (the screen can make a ticket): the field, empty.
CASES.push({ name: 'board-compose', doc: 'board', add: true, compose: 'In progress' });
CASES.push({ name: 'board-add', doc: 'board', add: true });
// The board scrolled to its end.
CASES.push({ name: 'board-end', doc: 'board', scroll: 99999 });
CASES.push({ name: 'table-end', doc: 'table', scroll: 99999 });

// IN A PHONE'S OWN PIXELS. `GLYPH_RATIO=2.625 node …/reference.mjs` draws each note again as a phone lays it out
// (Chromium launched at that scale lays out in device pixels; told a scale by Playwright it lays out in whole CSS
// ones: test/editor/tables/fixtures/reference.mjs, docs/REFERENCES.md) and writes them to fixtures/phone/, a
// window of 475, the Fold's cover screen.
const RATIO = Number(process.env.GLYPH_RATIO ?? 0);
const WIDTH = RATIO ? Math.floor(1248 / RATIO) : 390;
if (RATIO) for (const out of [OUT, TICKETS_OUT]) mkdirSync(`${out}phone`, { recursive: true });
const only = process.argv.slice(2);
const browser = await chromium.launch(RATIO ? { args: [`--force-device-scale-factor=${RATIO}`, `--window-size=${WIDTH},2400`] } : {});
const context = await browser.newContext(RATIO ? { viewport: null, hasTouch: true } : { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
const page = await context.newPage();
page.on('pageerror', (error) => console.log('page error:', error.message));
await page.route('**/__queries_reference', (route) =>
  route.fulfill({
    contentType: 'text/html',
    body: '<!doctype html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body style="margin:0"><div id="stage"></div></body></html>',
  }),
);
await page.clock.install({ time: new Date(`${TODAY}T12:00:00`) });
await page.goto(`${BASE}__queries_reference`);
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
    mermaid: await import('/src/app/editor/mermaid.ts'),
    tags: await import('/src/app/editor/tags.ts'),
    wiki: await import('/src/app/editor/wikiLinks.ts'),
    queries: await import('/src/app/editor/queries.ts'),
    tickets: await import('/src/app/editor/tickets.ts'),
    book: await import('/src/app/book/tickets.ts'),
    props: await import('/src/app/core/properties.ts'),
    styles: (await import('/src/app/editor/markdown.module.css')).default,
    query: (await import('/src/app/editor/QueryView.module.css')).default,
    panel: (await import('/src/app/editor/TicketPanel.module.css')).default,
  };
  window.Prefs = await import('/src/app/core/preferences.ts');
  await document.fonts.ready;
});

for (const one of CASES) {
  if (only.length && !only.includes(one.name)) continue;
  // In a phone's pixels: each note as it is, and the timeline left (its picture is Mermaid's, made for a width).
  if (RATIO && (one.name !== one.doc || one.doc === 'gantt')) continue;
  const doc = DOCS[one.doc];
  const result = await page.evaluate(
    async ({ one, doc, library, WIDTH }) => {
      const { CM, Base, Prefs } = window;
      const theme = one.theme ?? 'light';
      // Chosen, not only painted: a timeline is drawn in the colours `preferences().theme` names (mermaid.ts
      // `darkNow`), and the app's own default is dark.
      Prefs.setPreferences({ ...Prefs.DEFAULT_PREFERENCES, theme });
      window.madeView?.destroy();
      window.madeView = null;
      const stage = document.getElementById('stage');
      stage.replaceChildren();
      document.body.style.background = 'var(--glacier-bg)';
      const host = document.createElement('div');
      host.style.cssText = `inline-size: ${WIDTH}px; display: flex; flex-direction: column;`;
      stage.append(host);
      const readOnly = one.readOnly || false;
      const editorHost = document.createElement('div');
      editorHost.className = Base.styles.editor;
      editorHost.setAttribute('data-view', 'mixed');
      host.append(editorHost);
      const grow = CM.view.EditorView.theme({
        '&.cm-editor': { height: 'auto', minHeight: '100%', flex: '1 0 auto' },
        '&.cm-editor .cm-scroller': { overflowY: 'visible', overscrollBehavior: 'auto', flex: '1 0 auto' },
      });
      // The tickets of the library, as the screen hands them to a ticket's panel (shell/useTickets.ts).
      const choices = library
        .filter((note) => Base.props.isTicket(note.body))
        .map((note) => {
          const ticket = Base.props.ticketOf(note.body, Base.props.DEFAULT_STATUSES);
          return { key: ticket.id, title: /^# (.*)$/m.exec(note.body)[1], status: ticket.status, category: ticket.category };
        });
      const find = (target) => choices.find((choice) => choice.key === target.toUpperCase() || choice.title.toLowerCase() === target.toLowerCase()) ?? null;
      const queryOptions = { notes: () => library, noteId: 'here', open() {}, tick() {}, move() {}, ...(one.add ? { add: async () => false } : {}) };
      const ticketOptions = { statuses: () => Base.props.DEFAULT_STATUSES, people: () => ['Sam', 'Priya Shah'], choices: () => choices, find, open() {}, nextId: () => 'GHO-14' };
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
            Base.mermaid.drawnMermaid(),
            Base.tags.tags(),
            Base.wiki.wikiLinks({ known: (title) => find(title) !== null, open() {} }),
            Base.queries.queries(() => queryOptions),
            Base.tickets.tickets(() => ticketOptions),
            CM.view.EditorView.lineWrapping,
            CM.view.EditorView.contentAttributes.of({ autocorrect: 'off', autocapitalize: 'off', spellcheck: 'false', inputmode: 'text', enterkeyhint: 'enter' }),
            Base.theme.glyphTheme(theme === 'dark'),
            [CM.state.EditorState.readOnly.of(readOnly), CM.view.EditorView.editable.of(!readOnly)],
            Base.viewMode.noteView('mixed'),
            CM.state.Prec.highest(grow),
          ],
        }),
      });
      window.madeView = view;
      CM.language.forceParsing(view, view.state.doc.length, 1000);
      const frames = () => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));
      const wait = (ms) => new Promise((done) => setTimeout(done, ms));
      await wait(150);
      await document.fonts.ready;
      if (one.caret !== undefined) {
        view.focus();
        view.dispatch({ selection: { anchor: one.caret } });
      }
      await wait(one.doc.startsWith('gantt') ? 1500 : 300);
      view.requestMeasure();
      await frames();
      if (one.more) {
        [...view.dom.querySelectorAll('.cm-ticketPanel button')].find((button) => button.textContent.includes('Start'))?.click();
        await frames();
      }
      if (one.compose) {
        view.dom.querySelector(`button[aria-label="Add a ticket to ${one.compose}"]`).click();
        await frames();
        view.dom.querySelector('.cm-query input')?.blur();
        await frames();
      }
      if (one.scroll !== undefined) {
        const scroller = view.dom.querySelector(`.${Base.query.board}`) ?? view.dom.querySelector(`.${Base.query.tableScroll}`);
        if (scroller) {
          scroller.style.scrollSnapType = 'none';
          scroller.scrollLeft = one.scroll;
        }
        await frames();
      }
      await wait(80);
      const origin = host.getBoundingClientRect();
      const rect = (r) => (r ? { left: +(r.left - origin.left).toFixed(3), top: +(r.top - origin.top).toFixed(3), right: +(r.right - origin.left).toFixed(3), bottom: +(r.bottom - origin.top).toFixed(3) } : null);
      const box = (el) => (el ? rect(el.getBoundingClientRect()) : null);
      // A stylesheet's own name for a class the bundler has renamed.
      const named = new Map();
      for (const sheet of [Base.query, Base.panel]) for (const [name, made] of Object.entries(sheet)) named.set(made, name);
      const partsOf = (root) => {
        const parts = [];
        const walk = (el) => {
          const style = getComputedStyle(el);
          if (style.display === 'none') return;
          const names = [...el.classList].map((each) => named.get(each) ?? each);
          // The words that are this element's own, each run's boxes.
          const words = [];
          let said = '';
          for (const node of el.childNodes) {
            if (node.nodeType !== 3 || !node.textContent.trim()) continue;
            said += node.textContent;
            const range = document.createRange();
            range.selectNodeContents(node);
            for (const each of range.getClientRects()) words.push(rect(each));
          }
          const data = {};
          for (const attr of el.attributes) if (attr.name.startsWith('data-') || attr.name.startsWith('aria-') || attr.name === 'role' || attr.name === 'disabled') data[attr.name] = attr.value;
          parts.push({
            tag: el.tagName.toLowerCase(),
            names,
            rect: box(el),
            display: style.display,
            color: style.color,
            background: style.backgroundColor,
            border: style.borderTopWidth !== '0px' ? `${style.borderTopWidth} ${style.borderTopStyle} ${style.borderTopColor}` : null,
            radius: style.borderTopLeftRadius,
            size: parseFloat(style.fontSize),
            weight: style.fontWeight,
            family: style.fontFamily.split(',')[0].replace(/['"]/g, ''),
            decoration: style.textDecorationLine,
            shadow: style.boxShadow === 'none' ? null : style.boxShadow,
            opacity: style.opacity,
            said: said || null,
            text: el.children.length ? null : el.textContent,
            value: el.tagName === 'INPUT' ? el.value : undefined,
            placeholder: el.tagName === 'INPUT' ? el.placeholder : undefined,
            words,
            data,
            scroll: el.scrollWidth > el.clientWidth + 1 || el.scrollHeight > el.clientHeight + 1 ? { left: el.scrollLeft, top: el.scrollTop, width: el.scrollWidth, height: el.scrollHeight, clientWidth: el.clientWidth, clientHeight: el.clientHeight } : null,
          });
          if (el.tagName.toLowerCase() === 'svg') return;
          for (const child of el.children) walk(child);
        };
        for (const child of root.children) walk(child);
        return parts;
      };
      const lines = [];
      const blocks = [];
      for (const el of view.contentDOM.children) {
        if (el.classList.contains('cm-line')) {
          const from = view.posAtDOM(el, 0);
          const line = view.state.doc.lineAt(from);
          lines.push({ from: line.from, to: line.to, text: line.text, rect: rect(el.getBoundingClientRect()) });
          continue;
        }
        const kind = el.classList.contains('cm-query') ? 'query' : el.classList.contains('cm-ticketPanel') ? 'ticket' : null;
        if (!kind) continue;
        blocks.push({ kind, from: view.posAtDOM(el), rect: box(el), parts: partsOf(el) });
      }
      const titles = [...view.contentDOM.querySelectorAll('.cm-ticketTitle')].map((el) => {
        const dot = el.querySelector('.cm-ticketDot');
        const style = getComputedStyle(el);
        const range = document.createRange();
        range.selectNodeContents(el.lastChild);
        return { rect: box(el), text: el.textContent, category: el.dataset.category, color: style.color, decoration: style.textDecorationLine, size: parseFloat(style.fontSize), dot: { rect: box(dot), background: getComputedStyle(dot).backgroundColor }, words: [...range.getClientRects()].map(rect) };
      });
      const root = getComputedStyle(document.documentElement);
      return {
        doc,
        theme,
        readOnly,
        caret: one.caret ?? null,
        more: one.more ?? false,
        add: one.add ?? false,
        compose: one.compose ?? null,
        scroll: one.scroll ?? null,
        width: origin.width,
        page: root.getPropertyValue('--glacier-bg'),
        lines,
        blocks,
        titles,
        clip: { x: 0, y: 0, width: WIDTH, height: Math.min(2300, Math.ceil(view.dom.getBoundingClientRect().bottom - origin.top)) },
      };
    },
    { one, doc, library: LIBRARY, WIDTH },
  );
  const { clip, ...kept } = result;
  kept.today = TODAY;
  kept.library = LIBRARY;
  kept.locale = await page.evaluate(() => navigator.language);
  const out = `${one.doc.startsWith('ticket') ? TICKETS_OUT : OUT}${RATIO ? 'phone/' : ''}`;
  if (RATIO) Object.assign(kept, { ratio: RATIO, screen: WIDTH });
  writeFileSync(`${out}${one.name}.json`, `${JSON.stringify(kept)}\n`);
  const last = Math.max(...kept.lines.map((l) => l.rect.bottom), ...kept.blocks.map((b) => b.rect.bottom), 1);
  writeFileSync(`${out}${one.name}.png`, await page.screenshot({ clip: { ...clip, height: Math.max(1, Math.min(clip.height, Math.ceil(last) + 24)) } }));
  console.log(one.name, kept.lines.length, 'lines', kept.blocks.map((b) => `${b.kind}:${b.parts.length}`).join(' '), kept.titles.length, 'titles');
}

await browser.close();
