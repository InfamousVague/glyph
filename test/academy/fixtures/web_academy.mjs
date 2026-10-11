// The web app's Academy, drawn by Chromium on the web app's dev server (read-only), for lib/academy to be held
// against (test/academy/reference_test.dart). 390 x 844, two device pixels to the logical one; nothing but the dev
// server is reached (every other request is aborted).
//
//   node test/academy/fixtures/web_academy.mjs        # the dev server already running on 127.0.0.1:5279
//
// Writes test/academy/fixtures/<page>.json (each named thing's rectangles, words and computed type, light theme) and
// test/academy/fixtures/web/<page>-<theme>.png.
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { mkdirSync, writeFileSync } from 'node:fs';

const BASE = process.env.GLYPH_DEV ?? 'http://127.0.0.1:5279/';
const OUT = process.env.ACADEMY_OUT ?? '/Users/matt/Development/Apps/ghost-flutter/test/academy/fixtures/';
mkdirSync(`${OUT}web`, { recursive: true });

const c = (name) => `[class*="_${name}_"]`;
const A = c('screen');
const THINGS = {
  screen: A, top: c('top'), back: c('back'), backIcon: `${c('back')} svg`, heading: c('heading'), headingIcon: `${c('heading')} svg`, count: c('count'),
  bars: c('bars'), bar: c('bar'), page: `${A} main`, card: c('card'), chapter: c('chapter'), title: `${A} h2`, teach: c('teach'),
  example: c('example'), exampleText: c('exampleText'), showMe: `${c('example')} button`, showMeIcon: `${c('example')} button svg`, task: c('task'),
  playground: c('playground'), part: c('part'), label: c('label'), field: `${A} textarea`, shown: c('shown'), waiting: c('waiting'), editor: `${c('shown')} .cm-editor`, lines: `${c('shown')} .cm-line`,
  foot: c('foot'), footButtons: `${c('foot')} > button`, footIcons: `${c('foot')} > button svg`, praise: c('praise'), praiseIcon: `${c('praise')} svg`, hint: c('hint'),
  go: c('go'), goIcon: `${c('go')} svg`, skip: c('skip'), skipWords: c('skipWords'), skipName: c('skipName'), skipSaid: c('skipSaid'), switch: `${A} [role="switch"]`,
  chapters: c('chapters'), chapterRow: c('chapterRow'), chapterNumber: c('chapterNumber'), chapterWords: c('chapterWords'), chapterTitle: c('chapterTitle'), chapterAbout: c('chapterAbout'), chapterCount: c('chapterCount'),
  list: c('list'), again: c('again'), againTick: c('againTick'), againName: c('againName'), againMark: c('againMark'),
};

const measure = (page) =>
  page.evaluate((list) => {
    const out = {};
    const round = (n) => Math.round(n * 100) / 100;
    const top = window.scrollY;
    for (const [name, selector] of Object.entries(list)) {
      out[name] = [...document.querySelectorAll(selector)].map((el) => {
        const r = el.getBoundingClientRect();
        const s = getComputedStyle(el);
        return { x: round(r.x), y: round(r.y + top), w: round(r.width), h: round(r.height), text: (el.textContent ?? '').trim().slice(0, 90), size: round(parseFloat(s.fontSize)), weight: s.fontWeight, family: s.fontFamily.slice(0, 40), color: s.color, line: s.lineHeight, tracking: s.letterSpacing, bg: s.backgroundColor, radius: s.borderTopLeftRadius, opacity: s.opacity, pad: `${s.paddingTop} ${s.paddingRight} ${s.paddingBottom} ${s.paddingLeft}`, shadow: s.boxShadow.slice(0, 80) };
      });
    }
    out.vars = Object.fromEntries(['--app-gutter-start', '--app-gutter-end', '--app-safe-top', '--app-safe-bottom'].map((name) => {
      const probe = document.createElement('div');
      probe.style.cssText = `position:absolute;inline-size:var(${name});block-size:0`;
      document.querySelector(list.screen).appendChild(probe);
      const w = probe.getBoundingClientRect().width;
      probe.remove();
      return [name, w];
    }));
    return out;
  }, THINGS);

const settle = (page, ms = 700) => page.waitForTimeout(ms);
const CLICK = { timeout: 6000 };
const say = (page, words, exact = true) => page.locator(A).getByRole('button', { name: words, exact }).first().click(CLICK);

async function open(browser, theme, kept = {}) {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, colorScheme: theme, locale: 'en-US' });
  const page = await context.newPage();
  await context.route('**/*', (route) => (new URL(route.request().url()).host === new URL(BASE).host ? route.continue() : route.abort('blockedbyclient')));
  await page.goto(BASE);
  await page.evaluate((entries) => {
    localStorage.clear();
    for (const [k, v] of Object.entries(entries)) localStorage.setItem(k, v);
  }, { 'glyph-preferences': JSON.stringify({ theme }), 'glyph-guide-seen': '1', 'glyph-account-gate-seen': '1', ...kept });
  await page.reload();
  await page.waitForTimeout(2500);
  return { context, page };
}

/** The way in that is always there: Settings, About, Ghost.md Academy (settings/AboutPane.tsx). */
async function enter(page) {
  await page.getByRole('button', { name: 'Settings', exact: true }).first().click(CLICK);
  await settle(page, 1000);
  await page.getByText('About', { exact: true }).first().click(CLICK);
  await settle(page, 1000);
  await page.getByText('Ghost.md Academy', { exact: true }).first().click(CLICK);
  await settle(page, 1500);
}

async function take(page, name, theme) {
  if (theme === 'light') writeFileSync(`${OUT}${name}.json`, JSON.stringify(await measure(page), null, 1));
  await page.screenshot({ path: `${OUT}web/${name}-${theme}.png`, fullPage: true });
}

const browser = await chromium.launch();
try {
  for (const theme of ['light', 'dark']) {
    {
      const { context, page } = await open(browser, theme);
      await enter(page);
      await take(page, 'contents', theme);
      await say(page, 'Start');
      await settle(page);
      await take(page, 'lesson', theme);
      await say(page, 'Show me a hint');
      await settle(page);
      await take(page, 'lesson-hint', theme);
      await say(page, 'Show me');
      await settle(page, 1200);
      await take(page, 'lesson-passed', theme);
      await context.close();
    }
    {
      // Some of it learned: Continue on the contents, a chapter ticked, and the end of a chapter with one skipped.
      const L = ['title', 'heading', 'bold', 'italic', 'both', 'struck', 'code', 'link', 'list', 'number', 'todo', 'quote', 'rule', 'fence', 'wiki', 'bookmark'];
      const { context, page } = await open(browser, theme, { 'glyph-academy': JSON.stringify(L), 'glyph-academy-banner': 'done' });
      await enter(page);
      await take(page, 'contents-begun', theme);
      await say(page, 'Chapter 4, Links and places');
      await settle(page);
      await say(page, 'Skip');
      await settle(page);
      await take(page, 'chapter-end', theme);
      await context.close();
    }
  }
} catch (error) {
  console.log(String(error).split('\n').slice(0, 6).join('\n'));
} finally {
  await browser.close();
}
