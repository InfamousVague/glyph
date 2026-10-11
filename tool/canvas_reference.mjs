// The web app's own canvas, drawn by Chromium, for the Flutter canvas to be held against
// (test/canvas/reference_test.dart). The example canvas (sampleCanvas.ts, without its picture) fills a page at
// 390 x 844 (a phone: touch, a coarse pointer) and at 1280 x 800 (a window: a mouse), light and dark, on a canvas
// that can change, so the toolbar has its making tools and a tap picks a card.
//
// For each it writes test/canvas/fixtures/reference_<width>_<theme>.json:
//   view     the world's transform as the camera wrote it
//   cards    every `[data-card]`: its kind, its rectangle, and its title's, its hint's and its group name's
//   tools    the toolbar and each of its buttons; `map` the minimap
//   picked   for a card of words, a note, a link and the group, each tapped in turn: the ring's box
//            (`[data-handles]`), each handle's 44px box and the dot drawn in it, the bar and its buttons, and
//            whether the bar went under the card
//   labels   each line's label: the box of its text
// and test/canvas/reference/<width>_<theme>.png, the picture, with `<width>_<theme>_picked.png` (the card of words
// picked).
//
//   (cd tauri && npx vite --port 5276 --strictPort --host 127.0.0.1) &     # read-only: never `vite build` there
//   node tool/canvas_reference.mjs
//
// Playwright is not this repository's: it is taken from the npx cache, as tool/editor_reference.mjs takes it.
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { mkdirSync, writeFileSync } from 'node:fs';

const BASE = process.env.GLYPH_DEV ?? 'http://127.0.0.1:5276/';
const OUT = new URL('../test/canvas/fixtures/', import.meta.url).pathname;
const SHOTS = new URL('../test/canvas/reference/', import.meta.url).pathname;
mkdirSync(OUT, { recursive: true });
mkdirSync(SHOTS, { recursive: true });

/** The notes the example canvas's two note cards open, as the Flutter test hands them too. */
const NOTES = {
  'Launch week': '# Launch week\n\n- [ ] Get the photos back\n- [x] Book the hall\n\nSome words about the week.',
  'How to format a note': '# How to format a note\n\nEvery mark a note can hold, one after another.',
};

const SCREENS = [
  { width: 390, height: 844, phone: true },
  { width: 1280, height: 800, phone: false },
];

const browser = await chromium.launch();
for (const screen of SCREENS) {
  const context = await browser.newContext({ viewport: { width: screen.width, height: screen.height }, deviceScaleFactor: 2, isMobile: screen.phone, hasTouch: screen.phone });
  const page = await context.newPage();
  page.on('pageerror', (error) => console.log('page error:', error.message));
  await page.route('**/__canvas_reference', (route) =>
    route.fulfill({
      contentType: 'text/html',
      body: '<!doctype html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body style="margin:0"><div id="stage"></div></body></html>',
    }),
  );
  await page.goto(`${BASE}__canvas_reference`);
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
    window.CanvasModule = await import('/src/app/canvas/CanvasView.tsx');
    window.Sample = await import('/src/app/canvas/sampleCanvas.ts');
    window.Prefs = await import('/src/app/core/preferences.ts');
    await document.fonts.ready;
  });

  for (const theme of ['light', 'dark']) {
    await page.evaluate(
      async ({ theme, NOTES }) => {
        const { React, ReactDOM, CanvasModule, Sample, Prefs } = window;
        Prefs.applyPreferences({ ...Prefs.DEFAULT_PREFERENCES, theme, canvasSnap: true });
        window.root?.unmount();
        const stage = document.getElementById('stage');
        stage.replaceChildren();
        document.body.style.background = 'var(--glacier-bg)';
        const host = document.createElement('div');
        host.style.cssText = 'position: fixed; inset: 0;';
        stage.append(host);
        window.root = ReactDOM.createRoot(host);
        const wiki = { known: (title) => title in NOTES, open: () => {}, body: (title) => NOTES[title] ?? null, titles: () => Object.keys(NOTES) };
        const Holder = () => {
          const [canvas, setCanvas] = React.useState(() => Sample.sampleCanvas());
          return React.createElement(CanvasModule.CanvasView, { canvas, dark: theme === 'dark', wiki, onChange: setCanvas });
        };
        window.root.render(React.createElement(Holder));
        await new Promise((done) => setTimeout(done, 900));
        await document.fonts.ready;
      },
      { theme, NOTES },
    );

    const measure = () =>
      page.evaluate(() => {
        const box = (el) => {
          if (!el) return null;
          const r = el.getBoundingClientRect();
          return [r.left, r.top, r.width, r.height];
        };
        const one = (root, selector) => root.querySelector(selector);
        const world = one(document, '[class*="world"]');
        const m = /translate\(([-\d.e]+)px, ([-\d.e]+)px\) scale\(([-\d.e]+)\)/.exec(world.style.transform);
        const cards = [...document.querySelectorAll('[data-card]')].map((el) => ({
          id: el.dataset.card,
          kind: el.className.includes('group') ? 'group' : el.className.includes('linkCard') ? 'link' : el.className.includes('fileCard') ? 'file' : 'text',
          box: box(el),
          title: box(one(el, '[data-card-title]')),
          hint: box(one(el, '[class*="cardHint"]')),
          name: box(one(el, '[class*="groupLabel"]')),
          peek: box(one(el, '[class*="cardPeek"]')),
          words: box(one(el, '[class*="words"]')),
          ground: getComputedStyle(el).backgroundColor,
          line: getComputedStyle(el).borderTopColor,
          lineWidth: getComputedStyle(el).borderTopWidth,
          round: getComputedStyle(el).borderTopLeftRadius,
        }));
        const tools = one(document, '[role="toolbar"][aria-label="Canvas tools"]');
        const map = one(document, 'svg[aria-label^="A map of the canvas"]');
        return {
          view: m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null,
          cards,
          tools: { box: box(tools), buttons: [...tools.querySelectorAll('button')].map((b) => ({ label: b.getAttribute('aria-label'), box: box(b), icon: box(b.querySelector('svg')) })), rule: box(one(tools, '[class*="toolRule"]')), ground: getComputedStyle(tools).backgroundColor },
          map: map ? { box: box(map), seen: box(one(map, '[class*="mapSeen"]')), ground: getComputedStyle(map).backgroundColor } : null,
          labels: [...document.querySelectorAll('[class*="edges"] text')].map((t) => ({ words: [...t.querySelectorAll('tspan')].map((s) => s.textContent), box: box(t) })),
          lines: [...document.querySelectorAll('[class*="edges"] g')].map((g) => ({ id: g.getAttribute('data-line'), color: getComputedStyle(g).color })),
          ink: getComputedStyle(document.body).getPropertyValue('--app-ink'),
        };
      });

    const result = await measure();
    await page.screenshot({ path: `${SHOTS}${screen.width}_${theme}.png` });

    // A card of words, a note, a link and the group, each picked by a tap as a finger or a mouse makes one.
    result.picked = {};
    for (const id of ['book', 'pack', 'board', 'site', 'there', 'before']) {
      const at = await page.evaluate((id) => {
        const el = document.querySelector(`[data-card="${id}"]`);
        const r = el.getBoundingClientRect();
        // A group is picked by its border: its ground is the page's. Just inside the top-left corner.
        return el.className.includes('group') ? [r.left + 3, r.top + r.height / 2] : [r.left + r.width / 2, r.top + r.height / 2];
      }, id);
      if (screen.phone) await page.touchscreen.tap(at[0], at[1]);
      else await page.mouse.click(at[0], at[1]);
      await page.waitForTimeout(250);
      result.picked[id] = await page.evaluate((id) => {
        const box = (el) => {
          if (!el) return null;
          const r = el.getBoundingClientRect();
          return [r.left, r.top, r.width, r.height];
        };
        const ring = document.querySelector(`[data-handles="${id}"]`);
        const bar = document.querySelector(`[data-card-bar="${id}"]`);
        if (!ring || !bar) return null;
        const style = getComputedStyle(ring);
        return {
          card: box(document.querySelector(`[data-card="${id}"]`)),
          ring: box(ring),
          outline: [style.outlineWidth, style.outlineOffset, style.borderTopLeftRadius],
          handles: [...ring.querySelectorAll('[data-handle]')]
            .filter((h) => getComputedStyle(h).display !== 'none')
            .map((h) => {
              const dot = getComputedStyle(h, '::after');
              return { handle: h.dataset.handle, box: box(h), dot: [dot.width, dot.height, dot.borderTopWidth] };
            }),
          bar: box(bar),
          below: bar.hasAttribute('data-below'),
          buttons: [...bar.querySelectorAll('button')].map((b) => ({ label: b.getAttribute('aria-label'), box: box(b) })),
        };
      }, id);
      if (id === 'book') await page.screenshot({ path: `${SHOTS}${screen.width}_${theme}_picked.png` });
      // Let it go again, with a tap on open canvas: the bottom of the page, clear of the tools and the map.
      const clear = [screen.width / 2, screen.height - 120];
      if (screen.phone) await page.touchscreen.tap(clear[0], clear[1]);
      else await page.mouse.click(clear[0], clear[1]);
      await page.waitForTimeout(450);
    }
    writeFileSync(`${OUT}reference_${screen.width}_${theme}.json`, `${JSON.stringify(result, null, 1)}\n`);
    console.log(`${screen.width} ${theme}: view ${result.view}, ${result.cards.length} cards, tools ${result.tools.box}, map ${result.map?.box}, picked ${Object.entries(result.picked).map(([id, p]) => `${id}:${p ? p.handles.length : 'none'}`).join(' ')}`);
  }
  await context.close();
}
await browser.close();
