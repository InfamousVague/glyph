// The web app's notebook and journal pages, drawn by Chromium, for the Flutter ports to be held against
// (test/book_ui/reference_test.dart). Each page is the web app itself on its dev server over a seeded library (a
// notebook with a preface, a nested page and one not written; a notebook with a key and a ticket; a journal of five
// months and a page planned), at 390 x 844 and 1280 x 800, two device pixels to the logical one.
//
//   (cd ../glyph && npx vite --port 5277 --strictPort --host 127.0.0.1) &      # read-only: never `vite build` there
//   node tool/book_reference.mjs
//
// It writes test/book_ui/fixtures/<page>-<width>.json - for each named thing on the page its rectangle
// (`getBoundingClientRect`), its words and its computed type - and test/book_ui/fixtures/web/<page>-<width>-<theme>.png.
//
// Playwright is not this repository's: it is taken from the npx cache, as tool/editor_reference.mjs takes it.
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { mkdirSync, writeFileSync } from 'node:fs';

const BASE = process.env.GLYPH_DEV ?? 'http://127.0.0.1:5277/';
const OUT = new URL('../test/book_ui/fixtures/', import.meta.url).pathname;
mkdirSync(`${OUT}web`, { recursive: true });
const ONLY = process.argv.slice(2);

// A fixed moment (a Thursday afternoon), so every date said is the same on every run and in the Flutter test.
const NOW = new Date(2026, 9, 8, 15, 30, 0).getTime();
const DAY = 86400000;
const two = (n) => String(n).padStart(2, '0');
const note = (id, body, ago = 1) => ({ id, body, createdAt: NOW - ago * DAY, updatedAt: NOW - ago * 3600000, source: 'editor', starred: false });
const entry = (y, m, d, h, min, words) => {
  const title = `${y}-${two(m)}-${two(d)} ${two(h)}.${two(min)}`;
  return { title, note: { id: `e-${title}`, body: `---\ntitle: "${title}"\ndate: ${y}-${two(m)}-${two(d)}T${two(h)}:${two(min)}\n---\n# Day\n\n**${two(h)}:${two(min)}** ${words}`, createdAt: new Date(y, m - 1, d, h, min).getTime(), updatedAt: new Date(y, m - 1, d, h, min).getTime(), source: 'editor', starred: false } };
};
const ENTRIES = [
  entry(2026, 10, 8, 9, 12, 'Coffee on the step before anyone was up, and the long list for the week written out.'),
  entry(2026, 10, 7, 21, 40, 'Dinner with Sam.'),
  entry(2026, 10, 7, 8, 10, 'Rain.'),
  entry(2026, 9, 28, 14, 5, 'Walked along the river after lunch.'),
  entry(2026, 8, 30, 10, 0, 'Packed the car.'),
  entry(2026, 7, 15, 9, 0, 'Words.'),
  entry(2026, 6, 15, 9, 0, 'Words.'),
];
export const BOOK = '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\nWhat lives on the **coast path**, a page each.\n\n- [[Introduction]]\n- [[Trees]]\n  - [[Oaks]]\n- [[Birds]]\n- [[Route map]]\n\nSee also the tide tables.\n';
export const KEYED = '---\ntitle: "Ghost.md"\nbook: true\nkey: GHO\n---\n# Ghost.md\n\n- [[Fix the login loop]]\n- [[Write the docs]]\n';
export const JOURNAL = `---\ntitle: "Diary"\nbook: true\njournal: true\ntemplate: ${JSON.stringify('# {{date}}\n\n**{{time}}** ')}\n---\n# Diary\n\n${[...ENTRIES].reverse().map((e) => `- [[${e.title}]]`).join('\n')}\n- [[Packing list]]\n`;
const NOTES = [
  note('book', BOOK),
  note('intro', '# Introduction\n\nStart here. The path runs north from the harbour.\n', 2),
  note('trees', '# Trees\n\nThe wind bends them all one way.\n\n- Oak\n- Ash\n', 3),
  note('oaks', '# Oaks\n\nOld ones by the wall.\n', 4),
  note('map', '---\ntitle: "Route map"\n---\n{"nodes":[],"edges":[]}', 5),
  note('rivers', '# Rivers\n\nTwo of them.\n', 6),
  note('keyed', KEYED, 7),
  note('t1', '---\ntype: ticket\nid: GHO-12\nstatus: In progress\n---\n# Fix the login loop\n', 8),
  note('t2', '# Write the docs\n', 9),
  note('diary', JOURNAL, 10),
  ...ENTRIES.map((e) => e.note),
];
const seed = (theme) => ({ 'glyph-preferences': JSON.stringify({ theme }), 'glyph-guide-seen': '1', 'glyph-account-gate-seen': '1', 'glyph-notes': JSON.stringify(NOTES) });

async function open(browser, { width, height, theme }) {
  const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 2, colorScheme: theme, locale: 'en-US' });
  await context.addInitScript(`{ const Real = Date; const shift = ${NOW} - Real.now(); Date = class extends Real { constructor(...a) { super(...(a.length ? a : [Real.now() + shift])); } static now() { return Real.now() + shift; } }; }`);
  const page = await context.newPage();
  await context.route('**/*', (route) => (new URL(route.request().url()).host === new URL(BASE).host ? route.continue() : route.abort('blockedbyclient')));
  await page.goto(BASE);
  await page.evaluate((entries) => {
    localStorage.clear();
    for (const [k, v] of Object.entries(entries)) localStorage.setItem(k, v);
  }, seed(theme));
  await page.reload();
  await page.waitForTimeout(2500);
  return { context, page };
}

/** Each named selector's rectangles, words and type: `name` -> [{ x, y, w, h, text, size, weight, color, line }]. */
const measure = (page, things) =>
  page.evaluate((list) => {
    const out = {};
    const round = (n) => Math.round(n * 100) / 100;
    for (const [name, selector] of Object.entries(list)) {
      out[name] = [...document.querySelectorAll(selector)].map((el) => {
        const r = el.getBoundingClientRect();
        const s = getComputedStyle(el);
        return { x: round(r.x), y: round(r.y), w: round(r.width), h: round(r.height), text: (el.textContent ?? '').trim().slice(0, 80), size: round(parseFloat(s.fontSize)), weight: s.fontWeight, color: s.color, line: s.lineHeight, bg: s.backgroundColor, border: s.borderTopWidth + ' ' + s.borderBottomWidth, radius: s.borderTopLeftRadius };
      });
    }
    return out;
  }, things);

const c = (name) => `[class*="_${name}_"]`;
const INDEX = { book: c('book'), byline: '[class*="byline" i]', preface: c('preface'), index: c('index'), rows: `${c('index')} > li`, grips: c('grip'), gripIcons: `${c('grip')} svg`, numbers: `${c('index')} ${c('number')}`, chapters: c('chapter'), titles: c('chapterTitle'), waiting: c('waiting'), tools: c('tools'), tool: c('tool'), marks: `${c('index')} [data-category]`, statusButtons: 'button[aria-label^="Status:"]', canvasMarks: c('canvasMark'), adds: c('adds'), actions: c('action'), empty: c('empty') };
const FORM = { add: c('add'), field: c('field'), starts: c('starts'), startsTitle: c('startsTitle'), start: c('start'), startName: c('startName'), startLine: c('startLine'), actions: c('action'), quiet: c('quiet'), picker: c('picker'), pick: c('pick'), pickMark: c('pickMark'), none: c('none') };
const READ = { book: c('book'), readBar: c('readBar'), actions: c('action'), rail: c('rail'), railItems: c('railItem'), sections: c('chapterRead'), readTitle: c('readTitle'), readTitleButton: c('readTitleButton'), numbers: `${c('readTitleButton')} ${c('number')}`, readNote: c('readNote'), readBody: c('readBody'), lines: `${c('readBody')} .cm-line` };
const NAV = { bar: c('bar'), ends: c('end'), endTitles: c('endTitle'), middle: c('middle'), bookTitle: c('bookTitle'), count: c('count'), barIcons: `${c('bar')} svg`, foot: c('foot'), steps: c('step'), stepLabels: c('stepLabel'), stepTitles: c('stepTitle') };
const JOURNALK = { journal: c('journal'), adds: c('adds'), actions: c('action'), months: c('month'), monthNames: c('monthName'), entries: c('entry'), items: `${c('entries')} > li`, days: c('day'), dates: c('date'), weekdays: c('weekday'), metas: c('meta'), firsts: c('first'), folded: c('folded'), planned: c('planned'), plannedTitle: c('plannedTitle'), tool: c('tool'), choose: c('choose'), chooseTitle: c('chooseTitle'), start: c('start'), startName: c('startName'), usual: c('usual'), startLine: c('startLine'), cancel: c('cancel'), empty: c('empty') };
const SHEET = { sheet: '[role="dialog"]', title: `[role="dialog"] ${c('title')}`, fields: `[role="dialog"] label`, inputs: `[role="dialog"] input`, kind: c('kind'), choice: c('viewChoice'), radios: `${c('viewChoice')} button`, note: `[role="dialog"] ${c('note')}`, pages: c('pages'), page: c('page'), pageTitle: c('pageTitle'), grips: `[role="dialog"] ${c('grip')}`, numbers: `[role="dialog"] ${c('number')}`, tools: `[role="dialog"] ${c('tool')}`, found: c('found'), pick: c('pick'), pickMark: c('pickMark'), pickTitle: c('pickTitle'), none: c('none'), groups: `[role="dialog"] ${c('group')}`, rows: `[role="dialog"] ${c('row')}`, labels: `[role="dialog"] ${c('label')}`, hints: `[role="dialog"] ${c('hint')}`, headings: `[role="dialog"] ${c('heading')}`, picker: c('picker'), layout: c('layout'), choiceCol: c('choice'), preview: c('preview'), where: c('where'), previewPage: `${c('preview')} ${c('page')}`, previewLines: `${c('preview')} .cm-line`, place: c('place'), switchRow: c('switchRow'), own: c('own'), box: c('box'), chips: c('chips'), chip: c('chip'), rule: c('rule') };

const settle = (page, ms = 900) => page.waitForTimeout(ms);
const CLICK = { timeout: 6000 };
const say = (page, words) => page.getByRole('button', { name: words, exact: true }).first().click(CLICK);

const results = {};
async function take(page, name, width, theme, things) {
  if (theme === 'light') {
    results[`${name}-${width}`] = await measure(page, things);
    writeFileSync(`${OUT}${name}-${width}.json`, JSON.stringify(results[`${name}-${width}`], null, 1));
  }
  await page.screenshot({ path: `${OUT}web/${name}-${width}-${theme}.png` });
}

const browser = await chromium.launch();
const want = (name) => !ONLY.length || ONLY.includes(name);
/** Opens the note whose card on the home page says `title` (the `nth` thing that says exactly that). */
async function openCard(page, title, nth = 0) {
  await page.getByText(title, { exact: true }).nth(nth < 0 ? (await page.getByText(title, { exact: true }).count()) + nth : nth).click(CLICK);
  await settle(page, 1500);
}
for (const [width, height] of [[390, 844], [1280, 800]]) {
  for (const theme of ['light', 'dark']) {
    const run = async (name, card, nth, steps) => {
      if (!want(name)) return;
      const { context, page } = await open(browser, { width, height, theme });
      try {
        if (card) await openCard(page, card, nth);
        await steps(page);
      } catch (error) {
        console.log(`${name} ${width} ${theme}: ${String(error).split('\n')[0]}`);
        await page.screenshot({ path: `${OUT}web/FAILED-${name}-${width}-${theme}.png` });
      }
      await context.close();
    };
    await run('index', 'Field guide', 0, async (page) => {
      await take(page, 'index', width, theme, INDEX);
      await say(page, 'Add a page');
      await page.locator('input[aria-label="New page\'s title"]').fill('Rivers of the north');
      await settle(page);
      await take(page, 'add-page', width, theme, FORM);
      await say(page, 'Cancel');
      await say(page, 'Add a note you have');
      await settle(page);
      await page.locator(`${c('pick')}`).first().click(CLICK);
      await settle(page);
      await take(page, 'add-existing', width, theme, FORM);
      await say(page, 'Cancel');
      await say(page, 'Read straight through');
      await settle(page, 1500);
      await take(page, 'reading', width, theme, READ);
    });
    await run('page', 'Field guide', 0, async (page) => {
      await page.locator(`${c('chapter')}`).nth(1).click(CLICK);
      await settle(page, 1500);
      await take(page, 'page', width, theme, NAV);
    });
    await run('tickets', 'Ghost.md', 0, async (page) => {
      await take(page, 'tickets', width, theme, INDEX);
      await say(page, 'New ticket');
      await page.locator('input[aria-label="New ticket’s title"]').fill('Session cookie expires');
      await settle(page);
      await take(page, 'new-ticket', width, theme, FORM);
    });
    await run('journal', '7 entries', 0, async (page) => {
      await take(page, 'journal', width, theme, JOURNALK);
      await say(page, 'New entry');
      await settle(page);
      await take(page, 'journal-choose', width, theme, JOURNALK);
    });
    await run('sheet', null, 0, async (page) => {
      await page.locator('button[aria-label="Write a note"]').first().click(CLICK);
      await settle(page);
      await page.locator('[role="dialog"] button', { hasText: 'Notes in an order' }).first().click(CLICK);
      await settle(page);
      await take(page, 'sheet-notebook', width, theme, SHEET);
      await page.locator('[role="dialog"] input').first().fill('Cabin trip');
      for (const title of ['Trees', 'Route map', 'Rivers']) await page.locator(`[role="dialog"] ${c('pick')}`, { hasText: title }).first().click(CLICK);
      await settle(page);
      await take(page, 'sheet-pages', width, theme, SHEET);
      await page.locator(`${c('viewChoice')} button`).nth(1).click(CLICK);
      await settle(page, 1200);
      await take(page, 'sheet-journal', width, theme, SHEET);
      await page.locator('[role="dialog"] button', { hasText: 'My own' }).first().click(CLICK);
      await settle(page, 1200);
      await take(page, 'sheet-own', width, theme, SHEET);
    });
  }
}
// The index's writers themselves, run by the page's own module over a few books, for the Dart ports to be held to
// string for string (test/book_ui/book_rules_test.dart): test/book_ui/fixtures/rules.json.
if (want('rules')) {
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto(BASE);
  const rules = await page.evaluate(async (books) => {
    const b = await import('/src/app/book/book.ts');
    const j = await import('/src/app/book/journal.ts');
    const out = [];
    for (const body of books) {
      const chapters = b.chaptersOf(body);
      const titles = chapters.map((c) => c.title);
      const one = { body, numbered: b.numbered(chapters), words: b.bookWords(body), without: {}, moved: {}, at: {}, added: b.withChapter(body, 'A new page'), addedAfter: titles.length ? b.withChapter(body, 'A new page', titles[0]) : null, entry: j.withEntry(body, '2026-10-08 15.30') };
      for (const title of titles) {
        one.without[title] = b.withoutChapter(body, title);
        one.moved[title] = [b.withChapterMoved(body, title, -1), b.withChapterMoved(body, title, 1)];
        one.at[title] = titles.map((_, to) => b.withChapterAt(body, title, to)).concat([b.withChapterAt(body, title, 99)]);
      }
      out.push(one);
    }
    const made = {
      book: b.bookNoteBody('Cabin trip', ['Packing', 'Days']),
      empty: b.bookNoteBody('  '),
      journal: j.journalNoteBody('Diary', j.PRESETS[3].text, true),
      journalPlain: j.journalNoteBody('Log: "the" one', 'Dear {{journal}},\n', false),
      read: [['---\ntitle: "Oaks"\n---\n# Oaks\n\nTall, and *old*.\n', 'Oaks'], ['# Oaks\n\n# Oaks\n\nTwice.', 'Oaks'], ['Oaks\n\nwords', 'oaks']].map(([body, title]) => [body, title, b.bodyWithoutTitle(body, title)]),
    };
    return { books: out, made };
  }, [BOOK, KEYED, JOURNAL, '---\nbook: true\n---\n# Numbered\n\nLead.\n\n---\n\n## Part I\n\n1. [[One]]\n2. [[Two]] — twice\n   - [[Two and a half]]\n\n## Part II\n\n3. [[Three]]\n\n- [[A side list]]\n\nAfter.\n', '---\ntitle: Empty\nbook: true\n---\n# Empty\n\nJust words.\n\n***\n']);
  writeFileSync(`${OUT}rules.json`, JSON.stringify(rules, null, 1));
  await context.close();
}
await browser.close();
