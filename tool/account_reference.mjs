// The web app's account and organization pages, drawn by Chromium, for the Flutter ports to be held against
// (test/account_ui/reference_test.dart). Each page is the web app itself on its dev server, signed in by a seeded
// session as a member of two organizations, at 390 x 844 and 1280 x 800, two device pixels to the logical one.
//
// NOTHING LEAVES THE MACHINE (docs/STAGE7.md): the server is started with a dead API base, and every request the
// page makes is routed here - the page's own server answers, an organization's members and links are answered from
// this file, and anything else is refused and written down. The run fails if anything was refused that was not the
// dead API.
//
//   (cd ../glyph && VITE_GLYPH_API=http://127.0.0.1:1/api VITE_GLYPH_API_URL=http://127.0.0.1:1/format \
//      npx vite --port 5274 --strictPort --host 127.0.0.1) &      # read-only: never `vite build` there
//   node tool/account_reference.mjs
//
// It writes test/account_ui/fixtures/<page>-<width>.json - for each named thing on the page its rectangle
// (`getBoundingClientRect`) and its words - and test/account_ui/fixtures/web/<page>-<width>-<theme>.png, the picture.
//
// Playwright is not this repository's: it is taken from the npx cache, as tool/editor_reference.mjs takes it.
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { mkdirSync, writeFileSync } from 'node:fs';

const BASE = process.env.GLYPH_DEV ?? 'http://127.0.0.1:5274/';
const OUT = new URL('../test/account_ui/fixtures/', import.meta.url).pathname;
mkdirSync(`${OUT}web`, { recursive: true });

// A fixed moment, so "2 hr ago" and the days are the same on every run and in the Flutter test.
const NOW = Date.UTC(2026, 9, 7, 16, 0, 0);
const DAY = 86400000;
const ORG = 'org1';
const members = [
  { handle: 'matt', role: 'owner', state: 'member', since: NOW - 3 * DAY, invitedBy: null, colour: null },
  { handle: 'sam', role: 'member', state: 'member', since: NOW - 2 * DAY, invitedBy: 'matt', colour: 'rose' },
  { handle: 'lee', role: 'member', state: 'invited', since: NOW - 3600000, invitedBy: 'matt', colour: null },
];
const row = { id: ORG, name: 'Ghost', hue: 'sea', role: 'owner', state: 'member', members: 2, invitedBy: null, createdAt: NOW - 3 * DAY, colour: null, keys: { generation: 0, mine: false, missing: 0, stale: false } };
const seed = (theme, signedIn) => ({
  'glyph-preferences': JSON.stringify({ theme }),
  'glyph-guide-seen': '1',
  ...(signedIn ? { 'glyph-account-gate-seen': '1', 'glyph-account-session': JSON.stringify({ token: 't', handle: 'matt', accountId: 7 }) } : {}),
  'glyph-sync-7-orgs': JSON.stringify({ list: [row, { ...row, id: 'org2', name: 'Studio', hue: 'rose', role: 'member', members: 3 }], at: NOW, colour: null }),
  'glyph-workspaces': JSON.stringify({ list: [{ id: 'org-org1', name: 'Ghost', hue: 'sea', org: 'org1' }, { id: 'org-org2', name: 'Studio', hue: 'rose', org: 'org2' }], notes: { a: 'org-org1', b: 'org-org1' }, current: null }),
  'glyph-notes': JSON.stringify([
    { id: 'a', body: '# Roadmap\n- ship', createdAt: NOW - DAY, updatedAt: NOW - 7200000, source: 'editor', starred: false },
    { id: 'b', body: '# Standup\nyesterday: shipped', createdAt: NOW - DAY, updatedAt: NOW - 3600000, source: 'editor', starred: false },
  ]),
  'glyph-sync-7-notifications': JSON.stringify({
    cursor: 2,
    items: {
      n1: { id: 'n1', rev: 1, kind: 'member-joined', at: NOW - 2 * DAY, readAt: NOW, hidden: false, from: 'sam', org: { id: ORG, name: 'Ghost' }, body: { name: 'Ghost' } },
      n2: { id: 'n2', rev: 2, kind: 'role-changed', at: NOW - 3600000, readAt: null, hidden: false, from: 'matt', org: { id: ORG, name: 'Ghost' }, body: { name: 'Ghost', role: 'admin' } },
    },
    marks: [],
    unsent: [],
  }),
});

const refused = [];
async function open(browser, { width, height, theme, signedIn = true }) {
  const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 2, colorScheme: theme });
  // The page's clock starts at the fixture's moment and runs from there: stopped, the launch screen never leaves.
  await context.addInitScript(`{ const Real = Date; const shift = ${NOW} - Real.now(); Date = class extends Real { constructor(...a) { super(...(a.length ? a : [Real.now() + shift])); } static now() { return Real.now() + shift; } }; }`);
  const page = await context.newPage();
  await context.route('**/*', async (route) => {
    const url = new URL(route.request().url());
    if (url.host === new URL(BASE).host) return route.continue();
    if (url.host === '127.0.0.1:1') {
      const path = url.pathname.replace('/api/v1/', '');
      const method = route.request().method();
      if (method === 'GET' && path === `orgs/${ORG}`) return route.fulfill({ json: { org: { ...row, members } } });
      if (method === 'GET' && path === `orgs/${ORG}/links`) return route.fulfill({ json: { links: [{ id: 'l1', code: 'abcdefghijk12345', createdAt: NOW, expiresAt: NOW + 7 * DAY, maxUses: null, uses: 0, by: 'matt' }] } });
      return route.abort('connectionrefused');
    }
    refused.push(route.request().url());
    return route.abort('blockedbyclient');
  });
  await page.goto(BASE);
  await page.evaluate((entries) => {
    localStorage.clear();
    for (const [k, v] of Object.entries(entries)) localStorage.setItem(k, v);
  }, seed(theme, signedIn));
  await page.reload();
  await page.waitForTimeout(2500);
  return { context, page };
}

/** Each named selector's rectangles and words: `name` → [{ x, y, w, h, text }]. */
const measure = (page, things) =>
  page.evaluate((list) => {
    const out = {};
    for (const [name, selector] of Object.entries(list)) {
      out[name] = [...document.querySelectorAll(selector)].map((el) => {
        const r = el.getBoundingClientRect();
        const round = (n) => Math.round(n * 100) / 100;
        return { x: round(r.x), y: round(r.y), w: round(r.width), h: round(r.height), text: (el.getAttribute('aria-label') ?? el.textContent ?? '').trim().slice(0, 80) };
      });
    }
    return out;
  }, things);

const settle = (page) => page.waitForTimeout(1200);
const CLICK = { timeout: 6000 };
const settingsRow = (page, label) => page.locator('.settingsScreen__row', { has: page.locator('.settingsScreen__rowLabel', { hasText: new RegExp(`^${label}$`) }) }).first().click(CLICK);

const SETK = {
  display: '.settingsScreen__display',
  headWord: '.settingsScreen__headWord',
  titles: '.settingsScreen__pane .setk__title',
  cards: '.settingsScreen__pane .setk__card',
  rows: '.settingsScreen__pane .setk-row',
  labels: '.settingsScreen__pane .setk-row__label',
  heroTitle: '.setk-hero__title',
  heroMeta: '.setk-hero__meta',
  heroGlyph: '.setk-hero__glyph',
  footers: '.settingsScreen__pane .setk__footer',
  inputs: '.settingsScreen__pane input:not([type=checkbox]):not([type=radio])',
  submits: '.settingsScreen__pane .setk-form__submit',
  chips: '.settingsScreen__pane [data-role]',
  actions: '.settingsScreen__pane .setk-action',
  swatchDots: '.settingsScreen__pane [role=radiogroup][aria-label=Colour] [role=radio]',
  linkRows: '.settingsScreen__pane ul[aria-label="Invite links"] li',
  linkButtons: '.settingsScreen__pane [class*="_buttons_"] button',
  inviteWords: '.settingsScreen__pane [class*="_words_"] button',
};

/** The pages: how to get to each from the home page, and what to measure on it. */
const PAGES = {
  account: {
    go: async (page) => {
      await page.getByRole('button', { name: 'Settings', exact: true }).click(CLICK);
      await settle(page);
      await settingsRow(page, 'Account');
      await settle(page);
    },
    things: SETK,
  },
  organizations: {
    go: async (page) => {
      await page.getByRole('button', { name: 'Settings', exact: true }).click(CLICK);
      await settle(page);
      await settingsRow(page, 'Organizations');
      await settle(page);
    },
    things: SETK,
  },
  'organization-members': {
    go: async (page) => {
      await page.getByRole('button', { name: 'Settings', exact: true }).click(CLICK);
      await settle(page);
      await settingsRow(page, 'Organizations');
      await settle(page);
      await page.locator('.settingsScreen__pane .setk-row', { hasText: 'Ghost' }).first().click(CLICK);
      await settle(page);
      await settle(page);
    },
    things: SETK,
  },
  dashboard: {
    go: async (page) => {
      await page.locator('button', { hasText: 'Ghost2 members' }).first().click(CLICK);
      await settle(page);
      await settle(page);
    },
    things: {
      bar: 'header[class*="_topBar_"]',
      back: 'header[class*="_topBar_"] [class*="_back_"]',
      titleHue: '[class*="_titleHue_"]',
      title: '[class*="_titleName_"]',
      cogs: 'header [class*="_cog_"]',
      pills: 'nav[aria-label="Your organizations"] > *',
      hero: 'section[class*="_hero_"]',
      heroHue: 'section[class*="_hero_"] [class*="_heroHue_"]',
      heroName: '[class*="_heroName_"]',
      heroMeta: '[class*="_heroMeta_"]',
      heroNote: '[class*="_heroNote_"]',
      heroActions: '[class*="_heroActions_"] button',
      headings: 'h2[class*="_heading_"]',
      mores: '[class*="_headRow_"] [class*="_more_"]',
      cards: 'ol[aria-label="Notes in this organization"] > li',
      members: 'ul[aria-label="Members"] > li',
      avatars: 'ul[aria-label="Members"] [class*="_avatar_"]',
      handles: 'ul[aria-label="Members"] [class*="_handle_"]',
      roles: 'ul[aria-label="Members"] [data-role]',
      sinces: 'ul[aria-label="Members"] [class*="_since_"]',
      yourColour: '[class*="_yourColour_"]',
      inviteInput: 'input[aria-label="Invite by handle"]',
      inviteButton: 'form[class*="_invite_"] button',
      linkRows: 'ul[aria-label="Invite links"] li',
      newLink: '[class*="_buttons_"] button',
      news: 'ol[aria-label="Activity"] > li',
    },
  },
  log: {
    go: async (page) => {
      await page.locator('button', { hasText: 'Ghost2 members' }).first().click(CLICK);
      await settle(page);
      await page.locator('header button[aria-label="Audit log"]').click(CLICK);
      await settle(page);
      await settle(page);
    },
    things: {
      bar: 'header[class*="_topBar_"]',
      title: '[class*="_titleName_"]',
      titleWhat: '[class*="_titleWhat_"]',
      search: '[class*="_search_"]',
      pills: '[role=group][aria-label="What the log shows"] button',
      figures: '[role=status]',
      dayNames: '[class*="_dayName_"]',
      entries: '[class*="_timeline_"] li',
      rings: '[class*="_timeline_"] [class*="_author_"]',
    },
  },
  gate: {
    signedIn: false,
    go: async (page) => settle(page),
    things: {
      card: '.setk-signIn',
      title: '.setk-signIn__title',
      line: '.setk-signIn__line',
      segmented: '.setk-signIn [role=radiogroup], .setk-signIn [class*="segmented" i]',
      inputs: '.setk-signIn input:not([type=radio])',
      submit: '.setk-signIn .setk-form__submit',
      other: '.setk-signIn__other',
      skip: '[class*="_skip_"]',
    },
  },
};

const only = process.argv.slice(2);
const browser = await chromium.launch();
for (const [name, spec] of Object.entries(PAGES)) {
  if (only.length && !only.includes(name)) continue;
  for (const [width, height] of [[390, 844], [1280, 800]]) {
    for (const theme of ['light', 'dark']) {
      const { context, page } = await open(browser, { width, height, theme, signedIn: spec.signedIn ?? true });
      try {
        await spec.go(page);
        if (theme === 'light') writeFileSync(`${OUT}${name}-${width}.json`, `${JSON.stringify({ now: NOW, width, height, things: await measure(page, spec.things) }, null, 1)}\n`);
        await page.screenshot({ path: `${OUT}web/${name}-${width}-${theme}.png` });
        console.log(`${name} ${width} ${theme}`);
      } catch (failure) {
        console.error(`${name} ${width} ${theme}: ${failure.message.split('\n')[0]}`);
      }
      await context.close();
    }
  }
}
await browser.close();
if (refused.length) {
  console.error(`REFUSED ${refused.length} request(s) that were neither the page's server nor the dead API:\n${[...new Set(refused)].join('\n')}`);
  process.exit(1);
}
