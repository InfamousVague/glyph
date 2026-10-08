// The web app's links, pictures and media, drawn by Chromium, for lib/editor/media to be held against
// (test/editor/media/reference_test.dart). Modelled on tool/editor_reference.mjs: each case is a fixture note on a
// page 390 x 844 at two device pixels to the logical one, the editor's box at the page's corner.
//
// The editor measured is the BASE one of tool/editor_reference.mjs (language, highlighter, line classes, extended
// markdown, theme, view mode) with this piece's web modules added, each as Editor.tsx adds it: links.ts, linkCards.ts,
// images.ts, placeCards.ts, videos.ts and clips.ts. What the page would fetch is stubbed where the page itself lets it
// be: a link's preview is put in the page's own store (localStorage `glyph-link-previews`) before the first card is
// drawn, pictures are lent (core/images.ts `lendImages`) from PNGs drawn here on a canvas and written beside the
// fixtures for the Flutter side to draw the same bytes, and the map's tiles are never asked for (the quiet card and
// the reader's "Show the map").
//
// For each case it writes test/editor/media/fixtures/<name>.json:
//   lines   every `.cm-line`: its document range, class list and rectangle
//   blocks  every block widget's classes and rectangle
//   parts   every element this piece draws (a short link, a pill, a card and what is in it, a figure's picture, a
//           chip, a player): its name, rectangle, text, colour, ground and font size
// and <name>.png, the picture.
//
//   node test/editor/media/fixtures/reference.mjs [name ...]      (GLYPH_DEV names the dev server; 5272 by default)
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { writeFileSync } from 'node:fs';

const BASE = process.env.GLYPH_DEV ?? 'http://127.0.0.1:5272/';
const OUT = new URL('./', import.meta.url).pathname;

const NOTION = 'https://www.notion.so/attackfm/Buy-milk-1a2b3c4d5e6f';
const CABIN = 'https://www.airbnb.com/rooms/1234';
// Short enough to fit its card: a `where` line too long for the card is never cut on the page, it widens the whole
// editor past the screen (its `nowrap` is the card's least width, and the card's is `.cm-content`'s).
const LAKE = 'https://example.com/cabins/lake?w=32';

const DOCS = {
  links: `See [the board](${NOTION}) and https://example.com/a/long/path/to/the/page now.\n- [ ] Buy milk [notion](${NOTION})\n- [ ] Pack socks [notion](${NOTION}) ^pack-socks\n## Read https://github.com/InfamousVague/glyph/issues/1234\nA short one https://a.co/x stays, <https://example.org/the/rest/of/it> too.\nlast`,
  cards: `The trip\n${CABIN}\n- [The cabin](${LAKE})\nsee ${CABIN} for more\nlast`,
  images: 'Cabin\n![the porch](image/porch.png)\nafter\n![](image/missing.png)\nlast',
  imagesTall: 'Tall\n- ![tall](image/tall.png) and words\nlast',
  places: 'Lisbon notes\n\nwords before\n[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)\nafter\n- [Roughly 38.71, -9.14](geo:38.71,-9.14)\nlast',
  placeTop: '# Lisbon\n[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)\nwords after',
  videos: 'Film\n[![video 0:12](image/poster.png)](video/0a1b2c3d.mp4)\nafter',
  videosUpright: 'Film\n- [![video 1:02:03](image/upright.png)](video/4e5f6a7b.mp4)\nlast',
  // A memo's mark is short here, so that where a line wraps with the mark written out (the caret's line) it wraps before
  // the player and nowhere inside the mark: where a line may break inside `tape:12000-24000` is the view's business.
  clips: '- ![voice 0:12](tape:1-12000)\nI ![voice 1:05](tape:1-65000@k3) there.\n## Said ![voice 0:03](tape:1000-4000@other)\nlast',
};

/** The pictures lent to the page: name, size and the two colours of its gradient. */
const PICTURES = { 'porch.png': [600, 400, '#8aa1b4', '#d9c7a3'], 'tall.png': [300, 900, '#444', '#bbb'], 'poster.png': [640, 360, '#203040', '#c06040'], 'upright.png': [360, 640, '#305030', '#e0e0c0'] };

const CASES = [];
const add = (name, doc, more = {}) => {
  CASES.push({ name, doc, ...more });
  CASES.push({ name: `${name}-dark`, doc, ...more, theme: 'dark' });
};
add('links', 'links', { use: ['links'] });
add('links-formatted', 'links', { use: ['links'], display: 'formatted' });
CASES.push({ name: 'links-caret', doc: 'links', use: ['links'], caret: 4 });
add('cards', 'cards', { use: ['links', 'cards'] });
add('images', 'images', { use: ['images'] });
CASES.push({ name: 'images-tall', doc: 'imagesTall', use: ['images'] });
add('places-quiet', 'places', { use: ['places'], places: 'live', prefs: { mapTiles: false } });
add('places-local', 'places', { use: ['places'], places: 'live', prefs: { localOnly: true } });
add('places-ask', 'places', { use: ['places'], places: 'ask' });
CASES.push({ name: 'places-off', doc: 'places', use: ['places'], places: 'off' });
CASES.push({ name: 'places-caret', doc: 'places', use: ['places'], places: 'ask', caret: 30 });
add('place-top', 'placeTop', { use: ['places'], places: 'ask' });
add('videos-still', 'videos', { use: ['images', 'videos'], videos: 'still' });
add('videos-shared', 'videos', { use: ['images', 'videos'], videos: 'shared' });
CASES.push({ name: 'videos-upright', doc: 'videosUpright', use: ['images', 'videos'], videos: 'still' });
CASES.push({ name: 'videos-caret', doc: 'videos', use: ['images', 'videos'], videos: 'still', caret: 8 });
add('clips', 'clips', { use: ['clips'], tape: { src: 'tape.wav', id: 'k3' } });
add('clips-quiet', 'clips', { use: ['clips'] });
CASES.push({ name: 'clips-caret', doc: 'clips', use: ['clips'], tape: { src: 'tape.wav', id: 'k3' }, caret: 34 });

const only = process.argv.slice(2);
const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
const page = await context.newPage();
page.on('pageerror', (error) => console.log('page error:', error.message));
// The map's tiles are never fetched from here.
await page.route('**://tile.openstreetmap.org/**', (route) => route.abort());
await page.route('**/__media_reference', (route) =>
  route.fulfill({
    contentType: 'text/html',
    body: '<!doctype html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body style="margin:0"><div id="stage"></div></body></html>',
  }),
);
await page.goto(`${BASE}__media_reference`);

const pictures = await page.evaluate(
  async ({ CABIN, PICTURES }) => {
    // What the previews know, before anything reads them (core/linkPreview.ts keeps what it read for the page's life).
    localStorage.setItem('glyph-link-previews', JSON.stringify({ [CABIN]: { title: 'The cabin by the lake, with a porch that looks over the water and a stove', site: 'Airbnb', description: 'Sleeps four. A wood stove, a canoe and no signal, an hour from the nearest town on a gravel road.', at: Date.now() } }));
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
      styles: (await import('/src/app/editor/markdown.module.css')).default,
    };
    window.Media = {
      links: await import('/src/app/editor/links.ts'),
      cards: await import('/src/app/editor/linkCards.ts'),
      images: await import('/src/app/editor/images.ts'),
      places: await import('/src/app/editor/placeCards.ts'),
      videos: await import('/src/app/editor/videos.ts'),
      clips: await import('/src/app/editor/clips.ts'),
      core: await import('/src/app/core/images.ts'),
    };
    window.Prefs = await import('/src/app/core/preferences.ts');
    // The card's component, which placeCards.ts fetches lazily: here already, so a card is drawn when it is measured.
    await import('/src/app/editor/MapCard.tsx');
    await document.fonts.ready;
    // The pictures: a gradient corner to corner, as a PNG, lent to the page and handed back to be written to disk.
    const lent = {};
    const out = {};
    for (const [name, [width, height, from, to]] of Object.entries(PICTURES)) {
      const canvas = document.createElement('canvas');
      canvas.width = width;
      canvas.height = height;
      const pen = canvas.getContext('2d');
      const fill = pen.createLinearGradient(0, 0, width, height);
      fill.addColorStop(0, from);
      fill.addColorStop(1, to);
      pen.fillStyle = fill;
      pen.fillRect(0, 0, width, height);
      const blob = await new Promise((done) => canvas.toBlob(done, 'image/png'));
      const bytes = new Uint8Array(await blob.arrayBuffer());
      lent[name] = bytes;
      out[name] = Array.from(bytes);
    }
    window.Media.core.lendImages(lent);
    return out;
  },
  { CABIN, PICTURES },
);
for (const [name, bytes] of Object.entries(pictures)) writeFileSync(`${OUT}${name}`, Buffer.from(bytes));

for (const one of CASES) {
  if (only.length && !only.includes(one.name)) continue;
  const doc = DOCS[one.doc];
  const result = await page.evaluate(
    async ({ one, doc }) => {
      const { CM, Base, Media, Prefs } = window;
      const theme = one.theme ?? 'light';
      const prefs = { ...Prefs.DEFAULT_PREFERENCES, theme, ...(one.prefs ?? {}) };
      Prefs.setPreferences(prefs);
      window.madeView?.destroy();
      window.madeView = null;
      const stage = document.getElementById('stage');
      stage.replaceChildren();
      document.body.style.background = 'var(--glacier-bg)';
      const host = document.createElement('div');
      host.style.cssText = 'inline-size: 390px; display: flex; flex-direction: column;';
      stage.append(host);
      const editorHost = document.createElement('div');
      editorHost.className = Base.styles.editor;
      editorHost.setAttribute('data-grow', 'true');
      editorHost.setAttribute('data-view', one.display ?? 'mixed');
      host.append(editorHost);
      const grow = CM.view.EditorView.theme({
        '&.cm-editor': { height: 'auto', minHeight: '100%', flex: '1 0 auto' },
        '&.cm-editor .cm-scroller': { overflowY: 'visible', overscrollBehavior: 'auto', flex: '1 0 auto' },
      });
      const dark = theme === 'dark';
      const use = (name) => one.use.includes(name);
      // In Editor.tsx's order.
      const media = [
        use('images') ? Media.images.inlineImages() : [],
        use('places') ? Media.places.placeCards(one.places ?? 'off', { dark: () => dark }) : [],
        use('videos') ? Media.videos.videoCards(one.videos ?? 'still') : [],
        use('links') ? Media.links.shortLinks() : [],
        use('cards') ? Media.cards.linkCards() : [],
        use('clips') ? [Media.clips.clips(), Media.clips.tapeSource.of(one.tape ?? { src: null, id: null })] : [],
      ];
      const view = new CM.view.EditorView({
        parent: editorHost,
        state: CM.state.EditorState.create({
          doc,
          extensions: [
            Base.language.glyphMarkdown([]),
            CM.language.syntaxHighlighting(Base.highlight.glyphHighlight),
            Base.lines.glyphLines,
            Base.extended.extendedMarkdown(),
            media,
            CM.view.EditorView.lineWrapping,
            CM.view.EditorView.contentAttributes.of({ autocorrect: 'off', autocapitalize: 'off', spellcheck: 'false', inputmode: 'text', enterkeyhint: 'enter' }),
            Base.theme.glyphTheme(dark),
            [CM.state.EditorState.readOnly.of(false), CM.view.EditorView.editable.of(true)],
            Base.viewMode.noteView(one.display ?? 'mixed'),
            CM.state.Prec.highest(grow),
          ],
        }),
      });
      window.madeView = view;
      await new Promise((done) => setTimeout(done, 200));
      await document.fonts.ready;
      if (one.caret !== undefined) {
        view.focus();
        view.dispatch({ selection: { anchor: one.caret } });
      }
      // Pictures decode, the map card's component mounts, a video card hears which device this is.
      await new Promise((done) => setTimeout(done, 500));
      for (const img of view.dom.querySelectorAll('img')) if (img.getAttribute('src')) await img.decode().catch(() => undefined);
      view.requestMeasure();
      await new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));
      const origin = host.getBoundingClientRect();
      const rect = (r) => ({ left: +(r.left - origin.left).toFixed(3), top: +(r.top - origin.top).toFixed(3), right: +(r.right - origin.left).toFixed(3), bottom: +(r.bottom - origin.top).toFixed(3) });
      // CSS-module names are `_name_hash_n` in the dev server: the name alone.
      const names = (el) => [...el.classList].map((c) => c.replace(/^_|_[a-z0-9]+_\d+$/gi, ''));
      const lines = [];
      const blocks = [];
      for (const el of view.contentDOM.children) {
        const box = rect(el.getBoundingClientRect());
        if (!el.classList.contains('cm-line')) {
          blocks.push({ classes: el.tagName === 'FIGURE' ? ['figure', ...(el.hasAttribute('data-waiting') ? ['waiting'] : [])] : names(el), rect: box });
          continue;
        }
        const from = view.posAtDOM(el, 0);
        const line = view.state.doc.lineAt(from);
        lines.push({ from: line.from, to: line.to, text: line.text, shown: el.textContent, classes: names(el).filter((c) => c !== 'cm-line'), rect: box });
      }
      // What this piece draws, by the class it wears on the page.
      const WANTED = ['cm-shortLink', 'cm-itemMark', 'cm-itemMark-name', 'cm-linkCard', 'cm-linkCard-badge', 'cm-linkCard-body', 'cm-linkCard-title', 'cm-linkCard-about', 'cm-linkCard-where', 'cm-placeCardBox', 'card', 'quiet', 'mark', 'chip', 'frame', 'poster', 'length', 'words', 'cm-clip', 'cm-clipMark', 'cm-clipLength'];
      const parts = [];
      const seen = (el) => {
        const own = names(el);
        let name = WANTED.find((w) => own.includes(w));
        if (el.tagName === 'IMG' && el.parentElement?.tagName === 'FIGURE') name = 'figure-img';
        // The card's own names are a stylesheet's too (`mark`, `words`): only outside the lines of text.
        if (name && !name.startsWith('cm-') && el.closest('.cm-line')) name = undefined;
        if (name === 'chip') name = own.includes('where') ? 'chip-where' : own.includes('credit') ? 'chip-credit' : own.includes('show') ? 'chip-show' : own.includes('why') ? 'chip-why' : own.includes('length') ? 'length' : 'chip';
        if (name === 'cm-clip' && own.includes('cm-clipQuiet')) name = 'cm-clipQuiet';
        if (!name) return;
        const box = el.getBoundingClientRect();
        // `.words:empty { display: none }` and the like: not drawn, not a part.
        if (!box.width && !box.height) return;
        const at = getComputedStyle(el);
        parts.push({ name, rect: rect(box), text: el.children.length && !['cm-shortLink', 'cm-linkCard-title', 'cm-linkCard-about', 'cm-linkCard-where', 'cm-linkCard-badge', 'cm-itemMark-name', 'cm-clipLength', 'cm-clipQuiet', 'chip-show'].includes(name) ? '' : el.textContent, color: at.color, background: at.backgroundColor, size: parseFloat(at.fontSize), weight: at.fontWeight, family: at.fontFamily.split(',')[0].replace(/['"]/g, '') });
      };
      for (const el of view.contentDOM.querySelectorAll('*')) seen(el);
      const scroller = getComputedStyle(view.scrollDOM);
      return {
        doc,
        display: one.display ?? 'mixed',
        theme,
        use: one.use,
        places: one.places ?? 'off',
        videos: one.videos ?? 'still',
        tape: one.tape ?? null,
        prefs: one.prefs ?? {},
        caret: one.caret ?? null,
        width: origin.width,
        face: { family: scroller.fontFamily, size: parseFloat(scroller.fontSize) },
        lines,
        blocks,
        parts,
        clip: { x: 0, y: 0, width: Math.ceil(origin.width), height: Math.min(844, Math.ceil(view.dom.getBoundingClientRect().bottom - origin.top)) },
      };
    },
    { one, doc },
  );
  const { clip, ...kept } = result;
  writeFileSync(`${OUT}${one.name}.json`, `${JSON.stringify(kept)}\n`);
  writeFileSync(`${OUT}${one.name}.png`, await page.screenshot({ clip: { ...clip, height: Math.max(1, clip.height) } }));
  console.log(one.name, kept.lines.length, 'lines', kept.blocks.length, 'blocks', kept.parts.length, 'parts');
}

await browser.close();
