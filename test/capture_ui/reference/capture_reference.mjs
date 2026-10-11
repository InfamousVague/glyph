// The web app's voice recorder, drawn by Chromium, for the Flutter port to be held against. Each state is the web app
// itself on its dev server (../glyph/src/app/capture/CaptureScreen.tsx and its parts, MeetingScreen.tsx), opened as a
// person opens it - the Speak button on the home page's dock - over a seeded library of three notes, with the scripted
// voice speaking (capture/simulated.ts, `?simulate`), at 390 x 844 and at 1200 x 800, two device pixels to the logical
// one, in a plain desktop Chromium (no touch, no Android in the user agent, so `data-platform` is the browser's).
//
//   (cd ../glyph && npx vite --port 5278 --strictPort --host 127.0.0.1) &      # read-only: never `vite build` there
//   node test/capture_ui/reference/capture_reference.mjs [state ...]
//
// The states, and the moment each is read at (`STATES` below has the exact query):
//   rest        listening before the first word: the top line, "Start talking.", the ghost, the hint, Things to say
//   hearing     `?simulate`, two phrases committed and the third a guess five words long ("For the drive we want")
//   chip        "Hey Ghost." committed and "Add bin bags" of the next phrase a guess: the outlined chip with its dots
//   chip-moved  `?simulate=route`, just after "move this to shopping list" commits: the filled chip, the note's page
//   confirm     one phrase that is a command without the keyword, then Done: the confirm card
//   landing     a one-shot mid-take, just after it settles: the list landing with its ticked line, and its chip
//   meeting     MeetingScreen.tsx over a pretended Android host (`window.GlyphHost`), 12:34 into a meeting
//
// How a state is held still. The page's clock is Playwright's (`page.clock`): installed before the page loads at a
// fixed afternoon, left running while the app starts, and stopped once the home page is up. From there time moves only
// when this script moves it, 40 ms at a step (the scripted voice's own tick), until the page shows what the state
// waits for; then two more steps for the editor to draw what it was just given, and no more. The scripted voice's
// words therefore stop exactly where the state says. CSS animations do not run on that clock, so each is then put at
// its end (a finite one: the chip's pop, a card's rise) or held at a named place (an endless one: the chip's dots are
// held with all three showing), and what was done to each is written in the fixture's `animations`.
// The ghostly typing and the voice's ripples are switched off in the seeded preferences (`wisp`, `ripples`): they move
// no box, and letters half out of smoke are not a picture to compare against.
//
// It writes test/capture_ui/fixtures/<state>-<width>x<height>.json:
//   url, viewport, at   where the page was, and what was waited for (with the counter and the lines the page showed)
//   html                `document.documentElement`'s data attributes
//   vars                `--app-safe-top`, `--app-safe-bottom`, `--app-gutter-start`, `--app-gutter-end`, `--app-gutter`
//                       and `--recorder-top` at the screen's root, as written and as pixels: what the Flutter test
//                       must set as its insets
//   rects               each named thing's `getBoundingClientRect()`, unrounded. `line0…` are the editor's `.cm-line`s
//                       (the meeting's are its sentences). A rotated thing (a tick) has the box of its rotated shape;
//                       its own size is in `box`.
//   text                each named thing with words: the words and its computed colour, family, size, weight, line
//                       height and letter spacing; `colorDark` is the same read on the dark page, and each colour
//                       is there again as the sRGB a pixel painted with it has (`colorRgb`), the page's being oklch
//   box                 each named thing's padding, margin, border, radius, ground, gap, opacity and transform, where
//                       they are not nothing; `backgroundDark` and `borderColorDark` from the dark page
//   runs                for each `.cm-line`, each run of text on it with its rectangle and type
//   scroll              the live page's scroll position and heights
//   animations          each CSS animation found and where it was held
// and test/capture_ui/fixtures/<state>-<width>x<height>-<theme>.png, the whole viewport, light and dark. The numbers
// are the light page's; the dark page is measured too and any rectangle that differs is said aloud, since the two
// should be the same page.
//
// Playwright is not this repository's: it is taken from the npx cache, as tool/editor_reference.mjs takes it.
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { mkdirSync, writeFileSync } from 'node:fs';

const BASE = process.env.GLYPH_DEV ?? 'http://127.0.0.1:5278/';
const OUT = new URL('../fixtures/', import.meta.url).pathname;
mkdirSync(OUT, { recursive: true });
const ONLY = process.argv.slice(2);

// A fixed moment (a Thursday afternoon), so every date said is the same on every run and in the Flutter test.
const NOW = new Date(2026, 9, 8, 15, 30, 0).getTime();
/** The clock is stopped here, a minute on, once the home page is up. */
const HELD = NOW + 60_000;
const DAY = 86_400_000;
const note = (id, body, ago, source = 'editor') => ({ id, body, createdAt: NOW - ago * DAY, updatedAt: NOW - ago * 3_600_000, source, starred: false });
/** The library every state but the meeting starts with: what `glyph-notes` holds (core/store.ts, the browser's half). */
export const NOTES = [
  note('shopping', '# Shopping list\n\n- Oat milk\n- Eggs\n- Coffee\n', 1),
  note('house', '# House TODOs\n\n- [ ] Fix the gate\n- [x] Call the plumber\n- [ ] Paint the fence\n', 2),
  note('attackfm', '# AttackFM\n\nThe radio app.\n\n- Fix the seek bar\n- Update the readme\n', 3),
];
/** The meeting: its note, and what the pretended service answers `meetingState()` with, 12:34 in once the clock is read. */
const MEETING_MS = 754_000;
const MEETING_STARTED = HELD + 1000 - MEETING_MS;
const MEETING_NOTE = note('meeting', '# Meeting, 8 Oct 15:18\n', 0, 'capture');
const MEETING_STATE = { recording: true, noteId: 'meeting', title: 'Meeting, 8 Oct 15:18', startedAt: MEETING_STARTED, elapsedMs: MEETING_MS, silenced: false, writingUp: null, discarded: [] };

const seed = (theme, meeting) => ({
  'glyph-preferences': JSON.stringify({ theme, wisp: false, ripples: false, ...(meeting ? { meetings: { meeting: MEETING_STARTED } } : {}) }),
  'glyph-guide-seen': '1',
  'glyph-account-gate-seen': '1',
  'glyph-notes': JSON.stringify(meeting ? [...NOTES, MEETING_NOTE] : NOTES),
});

const say = (...phrases) => `?simulate=say&say=${encodeURIComponent(phrases.join('|'))}`;
const lastLine = (s) => s.doc[s.doc.length - 1] ?? '';
/**
 * The states. `until` is asked of the page (see `look`) after every 40 ms step; `at` says it in words for the fixture.
 * `done` presses Done once `until` holds and a second has passed, and then waits for `after`.
 */
const STATES = [
  { name: 'rest', query: say('Hello there.'), at: 'listening, no time run: before the first guess at 180 ms, the card of things to say naming a note', until: (s) => s.phase === 'listening' && s.sayCard.includes('Shopping list') },
  { name: 'hearing', query: '?simulate', at: 'two phrases committed, the third a guess: its last line reads "For the drive we want"', until: (s) => lastLine(s) === 'For the drive we want' },
  // "Hey Ghost, add bin bags to shopping list." in one phrase shows no chip while it is a guess: the live reader acts
  // only on a committed phrase, and the chip is drawn for a command held across phrases. So the keyword is a phrase.
  { name: 'chip', query: say('Milk and eggs.', 'Hey Ghost.', 'Add bin bags to shopping list.'), at: '"Hey Ghost." committed, the next phrase a guess three words long: the chip reads "Hey Ghost: Add bin bags"', until: (s) => s.route === 'Hey Ghost: Add bin bags' },
  { name: 'chip-moved', query: '?simulate=route', at: '"Hey Ghost, move this to shopping list." committed: the chip is filled, and the page is the list with the words on its end', until: (s) => s.routePhase === 'moved' && lastLine(s) === 'Oat milk, eggs and the good coffee.' },
  { name: 'confirm', query: say('Add to my note labeled Shopping list a list with sunscreen and bin bags.'), at: 'the phrase said whole and a second gone, Done pressed, the confirm card up', until: (s) => lastLine(s).endsWith('bin bags.'), done: true, after: (s) => s.confirm !== null },
  { name: 'landing', query: say('Quick thought before I forget.', 'Hey Ghost, add ship the APK to AttackFM.', 'And more words.'), at: 'the one-shot committed: the landing shows AttackFM\'s last lines and "Ship the APK" ticked', until: (s) => s.landing !== null },
  { name: 'meeting', query: '', at: 'the meeting screen at boot over a pretended host, the clock run one second: 12:34', meeting: true, until: (s) => s.counter === '12:34' },
];
const SIZES = [
  [390, 844],
  [1200, 800],
];

/** What the page pretends its Android activity is, for the meeting: enough of `GlyphHostBridge` (core/host.ts) to ask. */
const HOST = `window.GlyphHost = {
  takeLaunch: () => '', isLocked: () => false, endCapture: () => undefined, setCapturing: () => undefined, setLightChrome: () => undefined,
  meetingState: () => ${JSON.stringify(JSON.stringify(MEETING_STATE))}, canNotify: () => true, requestNotifications: () => 'allowed',
  stopMeeting: () => undefined, discardMeeting: () => undefined, forgetDiscarded: () => undefined, takeLink: () => '',
};`;

/** The recorder's root: the screen with a footer of its own (the recorder's and the meeting's both). */
const ROOT = '[class*="_screen_"]:has(> footer)';

/** What the page shows now, small: what `until` reads. */
const look = (page) =>
  page.evaluate((root) => {
    const s = document.querySelector(root);
    if (!s) return null;
    const one = (q) => s.querySelector(q);
    return {
      phase: s.dataset.phase ?? null,
      counter: one('[class*="_counter_"]')?.textContent ?? null,
      doc: [...s.querySelectorAll('.cm-line')].map((l) => l.textContent),
      route: one('[class*="_route_"]')?.textContent ?? null,
      routePhase: one('[class*="_route_"]')?.dataset.phase ?? null,
      landing: one('[class*="_landing_"]')?.textContent ?? null,
      confirm: one('[class*="_confirm_"]')?.textContent ?? null,
      sayCard: one('section[aria-label="Things to say"]')?.textContent ?? '',
      tip: one('[class*="_tip_"]')?.textContent ?? null,
    };
  }, ROOT);

/** Time moved 40 ms at a step until the page answers `until`, at most `most` ms. */
async function stepUntil(page, until, most = 20_000) {
  for (let t = 0; t <= most; t += 40) {
    const seen = await look(page);
    if (seen && until(seen)) return { seen, ran: t };
    await page.clock.runFor(40);
  }
  throw new Error('the page never showed what the state waits for');
}

/** Every CSS animation put where it is to be read: a finite one at its end, an endless one held. */
const holdAnimations = (page) =>
  page.evaluate(() =>
    document.getAnimations().map((a) => {
      const timing = a.effect?.getComputedTiming?.() ?? {};
      const name = a.animationName ?? a.transitionProperty ?? '';
      const target = a.effect?.target?.className?.baseVal ?? a.effect?.target?.className ?? '';
      const endless = timing.endTime === Infinity;
      let heldAt = 'end';
      if (endless) {
        a.pause();
        // The chip's dots with all three showing: the last step of a turn. Anything else endless at its start.
        const dots = /dots/.test(name);
        a.currentTime = dots ? (timing.delay ?? 0) + (Number(timing.duration) || 0) - 1 : 0;
        heldAt = dots ? 'the last step of a turn' : 'start';
      } else a.finish();
      return { name: String(name).replace(/^_|_[a-z0-9]+_\d+$/g, ''), target: String(target).split(' ').map((c) => c.replace(/^_([A-Za-z]+)_.*$/, '$1')).join(' '), endless, heldAt };
    }),
  );

/** Each named thing under the recorder's root: rectangles, words and type, boxes, the editor's runs. */
const measure = (page) =>
  page.evaluate((rootSel) => {
    const root = document.querySelector(rootSel);
    const c = (name) => `[class*="_${name}_"]`;
    const sayCard = 'section[aria-label="Things to say"]';
    const one = {
      top: c('top'), mic: c('mic'), micIcon: `${c('mic')} svg`, where: c('where'), newNote: c('newNote'), counter: c('counter'), headerBlur: '.app-headerBlur',
      body: c('body'), livePage: c('livePage'), editor: '.cm-editor', content: '.cm-content', placeholder: '.cm-placeholder', ghost: c('listenGhost'), pageHint: c('pageHint'),
      sayCard, sayTitle: `${sayCard} ${c('title')}`, sayFoot: `${sayCard} ${c('foot')}`,
      route: c('route'), routeDots: c('routeDots'), routeTick: c('routeTick'), routeText: c('routeText'), routeStrong: `${c('route')} strong`, routeUndo: c('routeUndo'), tip: c('tip'),
      landing: c('landing'), contextTitle: c('contextTitle'), landingUndo: c('landingUndo'),
      confirm: c('confirm'), confirmHeading: `${c('confirm')} ${c('heading')}`, confirmDetail: `${c('confirm')} ${c('detail')}`, confirmActions: `${c('confirm')} ${c('actions')}`,
      confirmCancel: `${c('confirm')} ${c('actions')} .app-word`, confirmAction: `${c('confirm')} ${c('actions')} .app-pill`, choices: c('choices'), diagnostics: c('diagnostics'),
      footer: 'footer', discard: 'footer .app-word', done: 'footer .app-pill', doneIcon: 'footer .app-pill svg', meter: c('meter'), tape: c('tape'),
    };
    const many = {
      line: root.querySelector('.cm-line') ? '.cm-line' : `${c('body')} > ${c('line')}`,
      sayGroup: `${sayCard} ${c('group')}`, sayHeading: `${sayCard} ${c('heading')}`, sayHeadingIcon: `${sayCard} ${c('heading')} svg`,
      sayLine: `${sayCard} li`, sayLineSay: `${sayCard} li strong`, sayLineDoes: `${sayCard} li span`,
      contextLine: c('contextLine'), landed: c('landed'), landedTick: c('landedTick'), confirmLine: `${c('confirm')} ${c('line')}`, choice: `${c('choices')} > button`,
    };
    const rect = (r) => ({ x: r.x, y: r.y, width: r.width, height: r.height });
    // A colour as the screen has it: the page's are oklch, and a pixel painted with one says its sRGB.
    const ink = document.createElement('canvas').getContext('2d', { willReadFrequently: true });
    const rgb = (colour) => {
      ink.clearRect(0, 0, 1, 1);
      ink.fillStyle = colour;
      ink.fillRect(0, 0, 1, 1);
      const [r, g, b, a] = ink.getImageData(0, 0, 1, 1).data;
      return a === 255 ? `rgb(${r}, ${g}, ${b})` : `rgba(${r}, ${g}, ${b}, ${(a / 255).toFixed(3)})`;
    };
    const type = (el) => {
      const s = getComputedStyle(el);
      return { color: s.color, colorRgb: rgb(s.color), fontFamily: s.fontFamily, fontSize: s.fontSize, fontWeight: s.fontWeight, lineHeight: s.lineHeight, letterSpacing: s.letterSpacing };
    };
    const NOTHING = new Set(['0px', 'none', 'normal', 'rgba(0, 0, 0, 0)', '1', '0px 0px 0px 0px', 'matrix(1, 0, 0, 1, 0, 0)']);
    const boxOf = (el) => {
      const s = getComputedStyle(el);
      const four = (p) => `${s[`${p}Top`]} ${s[`${p}Right`]} ${s[`${p}Bottom`]} ${s[`${p}Left`]}`;
      const all = {
        padding: four('padding'), margin: four('margin'),
        borderWidth: `${s.borderTopWidth} ${s.borderRightWidth} ${s.borderBottomWidth} ${s.borderLeftWidth}`,
        borderStyle: s.borderTopWidth === '0px' && s.borderRightWidth === '0px' && s.borderBottomWidth === '0px' ? 'none' : `${s.borderTopStyle} ${s.borderRightStyle} ${s.borderBottomStyle} ${s.borderLeftStyle}`,
        borderColor: s.borderTopWidth === '0px' && s.borderRightWidth === '0px' && s.borderBottomWidth === '0px' ? 'none' : s.borderBottomColor,
        borderRadius: s.borderTopLeftRadius, background: s.backgroundColor, gap: s.rowGap === s.columnGap ? s.rowGap : `${s.rowGap} ${s.columnGap}`,
        opacity: s.opacity, transform: s.transform,
        // Its own size before any transform: a rotated tick's rectangle is the rotated shape's.
        ...(s.transform !== 'none' && el.offsetWidth !== undefined ? { ownWidth: el.offsetWidth, ownHeight: el.offsetHeight } : {}),
      };
      const kept = Object.fromEntries(Object.entries(all).filter(([, v]) => !NOTHING.has(v)));
      if (kept.background) kept.backgroundRgb = rgb(kept.background);
      if (kept.borderColor) kept.borderColorRgb = rgb(kept.borderColor);
      return kept;
    };
    const out = { rects: { screen: rect(root.getBoundingClientRect()) }, text: {}, box: { screen: boxOf(root) }, runs: {} };
    const take = (name, el) => {
      out.rects[name] = rect(el.getBoundingClientRect());
      const box = boxOf(el);
      if (Object.keys(box).length) out.box[name] = box;
      const words = el.textContent ?? '';
      if (words.trim() && !(el instanceof SVGElement)) out.text[name] = { text: words, ...type(el) };
    };
    for (const [name, q] of Object.entries(one)) {
      const el = root.querySelector(q);
      if (el) take(name, el);
    }
    for (const [name, q] of Object.entries(many)) [...root.querySelectorAll(q)].forEach((el, i) => take(`${name}${i}`, el));
    // The editor's lines, run by run: a heading's size and a faint guess are on the spans, not the line.
    [...root.querySelectorAll('.cm-line')].forEach((line, i) => {
      const walker = document.createTreeWalker(line, NodeFilter.SHOW_TEXT);
      const runs = [];
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (!node.data) continue;
        const range = document.createRange();
        range.selectNodeContents(node);
        runs.push({ text: node.data, classes: node.parentElement.className, ...rect(range.getBoundingClientRect()), ...type(node.parentElement) });
      }
      out.runs[`line${i}`] = runs;
    });
    const scroller = root.querySelector(c('livePage'));
    if (scroller) out.scroll = { scrollTop: scroller.scrollTop, scrollHeight: scroller.scrollHeight, clientHeight: scroller.clientHeight };
    // The insets, as written and as pixels (a probe as tall as each).
    out.vars = {};
    const probe = document.createElement('div');
    probe.style.cssText = 'position:absolute; inline-size:0; visibility:hidden; pointer-events:none;';
    root.append(probe);
    for (const name of ['--app-safe-top', '--app-safe-bottom', '--app-gutter-start', '--app-gutter-end', '--app-gutter', '--recorder-top']) {
      probe.style.blockSize = `var(${name}, 0px)`;
      out.vars[name] = { written: getComputedStyle(root).getPropertyValue(name).trim(), px: probe.getBoundingClientRect().height };
    }
    probe.remove();
    out.html = Object.fromEntries([...document.documentElement.attributes].filter((a) => a.name.startsWith('data-')).map((a) => [a.name, a.value]));
    out.rootData = { ...root.dataset };
    return out;
  }, ROOT);

/** One state at one size in one theme: the app opened, brought to the state, held, measured and pictured. */
async function capture(browser, state, [width, height], theme) {
  const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 2, colorScheme: theme, locale: 'en-US' });
  if (state.meeting) await context.addInitScript(HOST);
  const page = await context.newPage();
  page.on('pageerror', (error) => console.log(`${state.name} ${width} ${theme}: page error: ${error.message}`));
  // Nothing but the dev server: no update check, no sync, no map tiles.
  await context.route('**/*', (route) => (new URL(route.request().url()).host === new URL(BASE).host ? route.continue() : route.abort('blockedbyclient')));
  await page.clock.install({ time: NOW });
  const url = `${BASE}${state.query}`;
  try {
    await page.goto(url);
    await page.evaluate((entries) => {
      localStorage.clear();
      for (const [k, v] of Object.entries(entries)) localStorage.setItem(k, v);
    }, seed(theme, state.meeting));
    await page.reload();
    if (state.meeting) {
      // The shell shows a meeting being recorded as the app opens (shell/useCaptureRoute.ts `showMeeting`).
      await page.locator(ROOT).waitFor({ timeout: 15_000 });
      await page.waitForTimeout(1000);
      await page.clock.pauseAt(HELD);
    } else {
      const speak = page.getByRole('button', { name: 'Speak a voice note' });
      await speak.waitFor({ timeout: 15_000 });
      await page.waitForTimeout(1500);
      await page.clock.pauseAt(HELD);
      // The element's own click: the pointer stays off the page, so nothing is drawn hovered.
      await speak.evaluate((button) => button.click());
      await page.locator(ROOT).waitFor({ timeout: 10_000 });
    }
    let { seen, ran } = await stepUntil(page, state.until);
    if (state.done) {
      await page.clock.runFor(1000);
      await page.getByRole('button', { name: 'Stop and save' }).evaluate((button) => button.click());
      ({ seen } = await stepUntil(page, state.after, 6000));
      ran += 1000;
    }
    // Two steps more: the editor draws what it was given on the next frame, and frames are on the held clock.
    await page.clock.runFor(40);
    await page.clock.runFor(40);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(250);
    const animations = await holdAnimations(page);
    await page.waitForTimeout(250);
    seen = await look(page);
    const measured = await measure(page);
    const size = `${width}x${height}`;
    await page.screenshot({ path: `${OUT}${state.name}-${size}-${theme}.png` });
    return { url, viewport: { width, height, deviceScaleFactor: 2 }, at: { waitedFor: state.at, ranMs: ran + 80, counter: seen.counter, lines: seen.doc, chip: seen.route, chipPhase: seen.routePhase }, ...measured, animations };
  } finally {
    await context.close();
  }
}

const browser = await chromium.launch();
let failed = 0;
for (const state of STATES) {
  if (ONLY.length && !ONLY.includes(state.name)) continue;
  for (const size of SIZES) {
    const name = `${state.name}-${size[0]}x${size[1]}`;
    try {
      const light = await capture(browser, state, size, 'light');
      const dark = await capture(browser, state, size, 'dark');
      // The dark page is the same page: say so where it is not, and keep its colours beside the light ones.
      const moved = Object.keys(light.rects).filter((key) => JSON.stringify(light.rects[key]) !== JSON.stringify(dark.rects[key]));
      if (moved.length || Object.keys(dark.rects).length !== Object.keys(light.rects).length) console.log(`${name}: dark differs from light in ${moved.join(', ') || 'what is there'}`);
      for (const [key, value] of Object.entries(light.text)) if (dark.text[key]) Object.assign(value, { colorDark: dark.text[key].color, colorDarkRgb: dark.text[key].colorRgb });
      for (const [key, value] of Object.entries(light.box)) {
        if (dark.box[key]?.background) Object.assign(value, { backgroundDark: dark.box[key].background, backgroundDarkRgb: dark.box[key].backgroundRgb });
        if (dark.box[key]?.borderColor) Object.assign(value, { borderColorDark: dark.box[key].borderColor, borderColorDarkRgb: dark.box[key].borderColorRgb });
      }
      writeFileSync(`${OUT}${name}.json`, `${JSON.stringify(light, null, 1)}\n`);
      console.log(`${name}: ${Object.keys(light.rects).length} things, counter ${light.at.counter}, ${light.at.ranMs} ms run`);
    } catch (error) {
      failed += 1;
      console.log(`${name}: FAILED: ${String(error).split('\n')[0]}`);
    }
  }
}
await browser.close();
process.exitCode = failed ? 1 : 0;
