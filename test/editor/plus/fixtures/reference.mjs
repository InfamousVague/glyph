// The web app's + beside the line and its list, drawn by Chromium, for lib/editor/plus to be held against
// (test/editor/plus/plus_reference_test.dart). Modelled on tool/editor_reference.mjs: the web `Editor` itself with
// its `plus` hooks, on a page 390 x 844 at two device pixels, the editor's box at the page's corner, and
// `AddList` (../glyph/src/app/editor/AddList.tsx) opened by the +'s own press, by `/`, or by a fine pointer.
//
// For each case, light and dark, it writes <name>.json and <name>.png beside this file:
//   lines   every `.cm-line`'s rectangle
//   plus    the + button: its rectangle, its drawing's (the svg's), its ink, opacity, state and whether it is a ×
//   list    the card: its rectangle, ground, hairline, corner and shadow; `rows` (what scrolls), `head`, `foot`
//   rows    every row, in order: words, rectangle, the icon's, the words' and the chevron's rectangles, inks, the
//           face's size and weight, whether it is lit, dimmed or ringed, and whether it is held (head or foot)
//   field / title / none   a step's or the palette's own parts
// The clock is held at 28 September 2026, 14:05, in en-GB, so the time row says what the Dart test's does.
//
//   node test/editor/plus/fixtures/reference.mjs [name ...]      # the web dev server on GLYPH_DEV (127.0.0.1:5272)
//
// Playwright is not this repository's: it is taken from the npx cache, as tool/editor_reference.mjs takes it.
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { writeFileSync } from 'node:fs';

const BASE = process.env.GLYPH_DEV ?? 'http://127.0.0.1:5272/';
const OUT = new URL('./', import.meta.url).pathname;

const MANY = Array.from({ length: 14 }, (_, i) => `Line ${i + 1}`).join('\n');
const LOW = Array.from({ length: 26 }, (_, i) => `Line ${i + 1}`).join('\n');

/**
 * The cases: a note, where the caret is, and what is done once the + has come: `open` is how the list is opened
 * ('touch' the +'s own press, 'pointer' a mouse's, 'slash' the key), `steps` the rows pressed after, by their words,
 * `keys` the editor's keys sent after that, `type` what is typed into a step's or the palette's field.
 */
const CASES = [
  { name: 'plus', doc: 'Lunch\n' },
  { name: 'plus-lead', doc: 'Lunch\n- ' },
  { name: 'plus-todo', doc: 'Lunch\n- [ ] ' },
  { name: 'plus-quote', doc: 'Lunch\n> ' },
  { name: 'plus-empty', doc: '' },
  { name: 'list', doc: 'Lunch\n', open: 'touch' },
  { name: 'list-lead', doc: 'Lunch\n- ', open: 'touch' },
  { name: 'list-pointer', doc: 'Lunch\n', open: 'pointer' },
  { name: 'list-keys', doc: 'Lunch\n', open: 'pointer', keys: ['ArrowDown', 'ArrowDown'] },
  { name: 'list-video', doc: 'Lunch\n', open: 'touch', video: true },
  { name: 'list-bare', doc: 'Lunch\n', open: 'touch', bare: true },
  { name: 'list-dimmed', doc: 'Lunch\n', open: 'touch', localOnly: true },
  { name: 'more', doc: 'Lunch\n', open: 'touch', steps: ['More'] },
  { name: 'board', doc: 'Lunch\n', open: 'touch', steps: ['A board'] },
  { name: 'database', doc: 'Lunch\n', open: 'touch', steps: ['A database'] },
  { name: 'note', doc: 'Lunch\n', open: 'touch', steps: ['A note'] },
  { name: 'note-found', doc: 'Lunch\n', open: 'touch', steps: ['A note'], type: 'lis' },
  { name: 'note-none', doc: 'Lunch\n', open: 'touch', steps: ['A note'], type: 'zzz' },
  { name: 'canvas', doc: 'Lunch\n', open: 'touch', steps: ['More', 'A canvas'] },
  { name: 'palette', doc: 'Lunch\n', open: 'slash' },
  { name: 'palette-found', doc: 'Lunch\n', open: 'slash', type: 'to-do' },
  { name: 'palette-none', doc: 'Lunch\n', open: 'slash', type: 'nothing at all' },
  // The + low on the page: the list opens above its row.
  { name: 'above', doc: `${LOW}\n`, open: 'touch' },
  // The + in the middle: neither side holds the list, so it takes the larger, capped, and its rows scroll under a fade.
  { name: 'cramped', doc: `${MANY}\n`, open: 'touch' },
  { name: 'cramped-more', doc: `${MANY}\n`, open: 'touch', steps: ['More'] },
];

const only = process.argv.slice(2);
const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, locale: 'en-GB', timezoneId: 'Europe/London' });
const page = await context.newPage();
page.on('pageerror', (error) => console.log('page error:', error.message));
await page.clock.setFixedTime(new Date('2026-09-28T14:05:00+01:00'));
await page.route('**/__plus_reference', (route) =>
  route.fulfill({
    contentType: 'text/html',
    body: '<!doctype html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body style="margin:0"><div id="stage"></div><div id="over"></div></body></html>',
  }),
);
await page.goto(`${BASE}__plus_reference`);

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
  window.AddModule = await import('/src/app/editor/AddList.tsx');
  window.PlusModule = await import('/src/app/editor/insertPlus.ts');
  window.Prefs = await import('/src/app/core/preferences.ts');
  await document.fonts.ready;
});

for (const base of CASES) {
  for (const theme of ['light', 'dark']) {
    const one = { ...base, name: theme === 'dark' ? `${base.name}-dark` : base.name, theme };
    if (only.length && !only.includes(one.name) && !only.includes(base.name)) continue;
    await page.emulateMedia({ reducedMotion: 'no-preference' });
    const result = await page.evaluate(async (one) => {
      const { React, ReactDOM, EditorModule, AddModule, Prefs } = window;
      const wait = (ms) => new Promise((done) => setTimeout(done, ms));
      // Kept as well as applied: the place row reads Local only from what is kept (core/preferences.ts `preferences`).
      Prefs.setPreferences({ ...Prefs.DEFAULT_PREFERENCES, theme: one.theme, localOnly: one.localOnly ?? false });
      Prefs.applyPreferences({ ...Prefs.DEFAULT_PREFERENCES, theme: one.theme, localOnly: one.localOnly ?? false });
      window.root?.unmount();
      window.listRoot?.unmount();
      window.root = null;
      window.listRoot = null;
      const stage = document.getElementById('stage');
      const over = document.getElementById('over');
      stage.replaceChildren();
      over.replaceChildren();
      document.body.style.background = 'var(--glacier-bg)';
      const host = document.createElement('div');
      host.style.cssText = 'inline-size: 390px; display: flex; flex-direction: column;';
      stage.append(host);
      let view = null;
      const keys = { current: null };
      const showList = (opening) => {
        window.listRoot?.unmount();
        window.listRoot = null;
        if (!opening) return;
        window.listRoot = ReactDOM.createRoot(over);
        window.listRoot.render(
          React.createElement(AddModule.AddList, {
            view,
            opening,
            pane: () => host.getBoundingClientRect(),
            onClose: () => showList(null),
            keys,
            onPicture: one.bare ? undefined : () => {},
            onPlace: one.bare ? undefined : () => {},
            onVideo: one.video ? () => {} : undefined,
            titles: one.bare ? undefined : () => ['Lisbon', 'Lisbon, day two', 'Porto'],
            canvases: one.bare ? undefined : () => ['Cabin weekend'],
            own: 'Lisbon, day two',
          }),
        );
      };
      window.root = ReactDOM.createRoot(host);
      window.root.render(
        React.createElement(EditorModule.Editor, {
          value: one.doc,
          onChange: () => {},
          dark: one.theme === 'dark',
          assist: false,
          display: 'mixed',
          grow: true,
          plus: { allowed: () => true, onOpen: showList, onClose: () => showList(null), onKey: (key) => keys.current?.(key) ?? false },
          onView: (made) => {
            view = made;
          },
        }),
      );
      await wait(150);
      await document.fonts.ready;
      view.focus();
      view.dispatch({ selection: { anchor: one.doc.length } });
      // The settle, and the +'s arrival.
      await wait(700);
      const button = view.scrollDOM.querySelector('.cm-plus');
      if (one.open === 'slash') {
        view.contentDOM.dispatchEvent(new KeyboardEvent('keydown', { key: '/', bubbles: true, cancelable: true }));
      } else if (one.open) {
        const down = new Event('pointerdown', { bubbles: true, cancelable: true });
        Object.defineProperty(down, 'pointerType', { value: one.open === 'pointer' ? 'mouse' : 'touch' });
        button.dispatchEvent(down);
        button.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, detail: 1 }));
      }
      await wait(300);
      const said = (text) => [...document.querySelectorAll('#add-list button')].find((row) => row.textContent?.startsWith(text));
      for (const step of one.steps ?? []) {
        said(step).click();
        await wait(350);
      }
      for (const key of one.keys ?? []) {
        view.contentDOM.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }));
        await wait(60);
      }
      if (one.type !== undefined) {
        const input = document.querySelector('#add-list input');
        Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set.call(input, one.type);
        input.dispatchEvent(new Event('input', { bubbles: true }));
        await wait(120);
      }
      // The ×'s turn (420ms) and the card's rise.
      await wait(600);

      const origin = host.getBoundingClientRect();
      const rect = (r) => (r ? { left: +(r.left - origin.left).toFixed(3), top: +(r.top - origin.top).toFixed(3), right: +(r.right - origin.left).toFixed(3), bottom: +(r.bottom - origin.top).toFixed(3) } : null);
      const box = (el) => (el ? rect(el.getBoundingClientRect()) : null);
      const lines = [...view.contentDOM.querySelectorAll('.cm-line')].map((el) => ({ rect: box(el), text: el.textContent }));
      const plusStyle = getComputedStyle(button);
      const svg = button.querySelector('svg');
      const plus = {
        rect: box(button),
        // The drawing's own box before its turn: its layout box, which a rotation does not change.
        svg: (() => {
          const was = svg.style.transform;
          svg.style.transition = 'none';
          svg.style.transform = 'none';
          const r = box(svg);
          svg.style.transform = was;
          return r;
        })(),
        color: plusStyle.color,
        opacity: plusStyle.opacity,
        state: button.dataset.state,
        lead: button.hasAttribute('data-lead'),
        expanded: button.getAttribute('aria-expanded') === 'true',
        turn: getComputedStyle(svg).transform,
        hidden: button.hidden,
      };
      const card = document.getElementById('add-list');
      let list = null;
      const rows = [];
      let field = null;
      let title = null;
      let none = null;
      if (card) {
        const at = getComputedStyle(card);
        const scroller = card.querySelector('[data-rows]');
        list = {
          rect: box(card),
          role: card.getAttribute('role'),
          label: card.getAttribute('aria-label'),
          keys: card.hasAttribute('data-keys'),
          background: at.backgroundColor,
          border: at.borderTopColor,
          borderWidth: at.borderTopWidth,
          radius: at.borderTopLeftRadius,
          shadow: at.boxShadow,
          color: at.color,
          rows: box(scroller),
          more: scroller.getAttribute('data-more') ?? '',
          scrollHeight: scroller.scrollHeight,
          clientHeight: scroller.clientHeight,
          maxBlockSize: scroller.style.maxBlockSize,
          head: box(card.querySelector('[class*="head"]')),
          foot: box(card.querySelector('[class*="foot"]')),
        };
        for (const row of card.querySelectorAll('button')) {
          const style = getComputedStyle(row);
          const icon = row.querySelector('[class*="icon"]');
          const words = row.querySelector('[class*="words"]');
          const why = row.querySelector('[class*="why"]');
          const onward = row.querySelector('[class*="onward"]');
          // The words themselves, as a range: the span stretches to the row's end, the letters do not.
          const range = document.createRange();
          range.selectNodeContents(words.firstChild ?? words);
          rows.push({
            id: row.id,
            words: words.firstChild?.textContent ?? '',
            why: why?.textContent ?? null,
            label: row.getAttribute('aria-label'),
            rect: box(row),
            icon: box(icon),
            drawing: box(icon?.querySelector('svg')),
            wordsBox: box(words),
            letters: rect(range.getBoundingClientRect()),
            whyBox: box(why),
            onward: box(onward?.querySelector('svg')),
            color: style.color,
            iconColor: icon ? getComputedStyle(icon).color : null,
            whyColor: why ? getComputedStyle(why).color : null,
            whySize: why ? parseFloat(getComputedStyle(why).fontSize) : null,
            background: style.backgroundColor,
            radius: style.borderTopLeftRadius,
            outline: style.outlineStyle === 'none' ? null : `${style.outlineWidth} ${style.outlineColor} ${style.outlineOffset}`,
            size: parseFloat(style.fontSize),
            weight: style.fontWeight,
            family: style.fontFamily.split(',')[0].replace(/['"]/g, ''),
            lineHeight: style.lineHeight,
            lit: row.hasAttribute('data-active'),
            dimmed: row.getAttribute('aria-disabled') === 'true',
            held: !scroller.contains(row),
          });
        }
        const input = card.querySelector('input');
        if (input) {
          const style = getComputedStyle(input);
          field = { rect: box(input), placeholder: input.placeholder, value: input.value, background: style.backgroundColor, border: style.borderTopColor, radius: style.borderTopLeftRadius, size: parseFloat(style.fontSize), color: style.color, focused: document.activeElement === input };
        }
        const heading = card.querySelector('p[class*="title"]');
        if (heading) title = { rect: box(heading), words: heading.textContent, color: getComputedStyle(heading).color, size: parseFloat(getComputedStyle(heading).fontSize), weight: getComputedStyle(heading).fontWeight };
        const nothing = card.querySelector('[class*="none"]');
        if (nothing) none = { rect: box(nothing), words: nothing.textContent, color: getComputedStyle(nothing).color, size: parseFloat(getComputedStyle(nothing).fontSize) };
      }
      const root = getComputedStyle(document.documentElement);
      return {
        name: one.name,
        doc: one.doc,
        theme: one.theme,
        open: one.open ?? null,
        steps: one.steps ?? [],
        keys: one.keys ?? [],
        type: one.type ?? null,
        video: one.video ?? false,
        bare: one.bare ?? false,
        localOnly: one.localOnly ?? false,
        width: origin.width,
        gutter: root.getPropertyValue('--app-gutter'),
        content: rect(view.contentDOM.getBoundingClientRect()),
        contentLeft: view.contentDOM.offsetLeft,
        now: new Date().toISOString(),
        locale: navigator.language,
        lines,
        plus,
        list,
        rows,
        field,
        title,
        none,
      };
    }, one);
    writeFileSync(`${OUT}${one.name}.json`, `${JSON.stringify(result)}\n`);
    writeFileSync(`${OUT}${one.name}.png`, await page.screenshot({ clip: { x: 0, y: 0, width: 390, height: 844 } }));
    console.log(one.name, result.plus.state, result.rows.length, 'rows', result.list ? JSON.stringify(result.list.rect) : '');
  }
}

await browser.close();
