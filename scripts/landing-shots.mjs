#!/usr/bin/env node
/**
 * The app's screens for ghostmarkdown.com (landing/shots/, docs/LANDING.md): the web build, seeded with a handful of
 * notes, drawn at a phone's size in the dark page it opens on, and kept as WebP.
 *
 *   npm run build && npx vite preview --port 4173 &
 *   node scripts/landing-shots.mjs [http://localhost:4173]
 *
 * Needs Playwright and a Chromium (`npx playwright install chromium` where there is none). Chromium itself encodes the
 * WebP, from a canvas, so nothing else is needed to make the files small.
 */
/* global Image, document -- the WebP is made inside the page (`shot`), where these are its own. */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const { chromium } = await import('playwright').catch(async () => {
  const { execSync } = await import('node:child_process');
  return import(join(execSync('npm root -g').toString().trim(), 'playwright', 'index.mjs'));
});

const BASE = process.argv[2] ?? 'http://localhost:4173';
const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', 'landing', 'shots');
mkdirSync(OUT, { recursive: true });

const now = Date.now();
const min = 60_000;
const day = 24 * 60 * min;
const note = (id, body, ago, extra = {}) => ({ id, body, createdAt: now - ago, updatedAt: now - ago, source: 'editor', ...extra });
const entry = (title, date, words) => note(title, `---\ntitle: "${title}"\ndate: ${date}\n---\n${words}`, 45 * day);
const stamp = (daysAgo, hh, mm) => {
  const d = new Date(now - daysAgo * day);
  const pad = (n) => String(n).padStart(2, '0');
  const date = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  return { title: `${date} ${pad(hh)}.${pad(mm)}`, date: `${date}T${pad(hh)}:${pad(mm)}` };
};
const e1 = stamp(0, 8, 12);
const e2 = stamp(1, 21, 40);
const e3 = stamp(3, 7, 55);

const NOTES = [
  note('trip', '# Weekend trip\n\n## Before we go\n\n- [x] Book the cabin\n- [ ] Pick up the ==rental car== (green)\n- [ ] Charge the ||good speaker||\n\nWe need snacks, water, a charger and the good playlist:\n\n- Snacks\n- Water\n- A charger\n- The good playlist\n\n> [!TIP]\n> Leave by ten and the road is ours.\n\n| Day | Where |\n| --- | --- |\n| Sat | The lake |\n| Sun | The ridge walk |\n\nThe code for the gate is @@4417@@ and the wifi is ??probably?? the same as last year. 🔥🔥Hot springs on Sunday.🔥🔥\n', 3 * min, { starred: true }),
  note('wifi', '# Wifi password\n\nThe long one on the router.', 9 * day, { starred: true }),
  note('standup', '# Standup\n\n## Summary\n\nWe agreed to ship the home page on Friday.\n\n- [ ] Write the release notes\n- [ ] Ask Sam about the screenshots\n\n**0:04** Morning, everyone. Quick one today.', 20 * min, { source: 'capture', recordingMs: 40_000 }),
  note('launch', '# Launch plan\n\n- [ ] Ship the pricing page ^ship-page\n- [x] Pick a launch date ^pick-date\n- [ ] Ask Sam which photos are cleared ^ask-sam\n- [ ] Record the demo ^record-demo\n- [ ] Write the release notes ^release-notes\n\n```board\nTo do: ship-page, ask-sam\nIn progress: record-demo, release-notes\nDone: pick-date\n```\n', 40 * min),
  note(
    'map',
    `---\ntitle: "How a note is made"\n---\n${JSON.stringify(
      {
        nodes: [
          { id: 'a', type: 'text', text: '## You speak\n"Heading, before we go"', x: 0, y: 0, width: 240, height: 110 },
          { id: 'b', type: 'text', text: '## Whisper hears it\nOn the phone, as you talk', x: 320, y: 0, width: 240, height: 110 },
          { id: 'c', type: 'text', text: '## The cues shape it\n`## Before we go`', x: 160, y: 190, width: 240, height: 110 },
          { id: 'd', type: 'text', text: '## One .md file\nYours, readable anywhere', x: 160, y: 380, width: 240, height: 110 },
        ],
        edges: [
          { id: 'e1', fromNode: 'a', toNode: 'b', label: 'live' },
          { id: 'e2', fromNode: 'b', toNode: 'c' },
          { id: 'e3', fromNode: 'c', toNode: 'd', label: 'at Done' },
        ],
      },
      null,
      2,
    )}\n`,
    2 * day,
  ),
  note('diary', `---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n\n- [[${e3.title}]]\n- [[${e2.title}]]\n- [[${e1.title}]]\n`, 30 * min),
  entry(e1.title, e1.date, '**08:12** Coffee on the step. The fog lifted by nine and the lake came out of it all at once.'),
  entry(e2.title, e2.date, '**21:40** Finished the book. The last chapter earns the whole thing.'),
  entry(e3.title, e3.date, '**07:55** First swim of the year. Cold enough to laugh at.'),
  note('grocery', '# Grocery run\n\nMilk, eggs, sourdough, and coffee beans.', 5 * min),
  note('ideas', '# Book ideas\n\nA ghost who writes notes for people who forget.', 4 * day),
  note('recipes', '# Recipes\n\nMiso soup: dashi, tofu, wakame.', 40 * day),
];

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM ?? undefined }).catch(() => chromium.launch({ executablePath: '/opt/pw-browsers/chromium' }));

/** A fresh device, seeded, at a phone's size or a desk's: each screen starts from nothing, so it shows one tab. */
async function device(desk = false) {
  const context = await browser.newContext(
    desk
      ? { viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1.5, colorScheme: 'dark' }
      : { viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, colorScheme: 'dark' },
  );
  const page = await context.newPage();
  page.on('pageerror', (error) => console.warn('page:', error.message));
  await page.addInitScript((notes) => {
    if (sessionStorage.getItem('seeded')) return;
    localStorage.clear();
    localStorage.setItem('glyph-guide-seen', '1');
    localStorage.setItem('glyph-notes', JSON.stringify(notes));
    localStorage.setItem('glyph-preferences', JSON.stringify({ theme: 'dark', noteView: 'formatted' }));
    sessionStorage.setItem('seeded', '1');
  }, NOTES);
  await page.goto(BASE);
  await page.waitForTimeout(2500);
  return { page, close: () => context.close() };
}

/** The page as it is now, as a WebP beside the others. */
async function shot(page, name) {
  await page.waitForTimeout(900);
  const png = await page.screenshot({ type: 'png' });
  const webp = await page.evaluate(async (b64) => {
    const img = new Image();
    img.src = `data:image/png;base64,${b64}`;
    await img.decode();
    const canvas = document.createElement('canvas');
    canvas.width = img.naturalWidth;
    canvas.height = img.naturalHeight;
    canvas.getContext('2d').drawImage(img, 0, 0);
    return canvas.toDataURL('image/webp', 0.86).split(',')[1];
  }, png.toString('base64'));
  writeFileSync(join(OUT, `${name}.webp`), Buffer.from(webp, 'base64'));
  console.log(`landing/shots/${name}.webp`);
}

{
  const { page, close } = await device();
  await shot(page, 'home');
  await page.getByRole('button', { name: /^Filters/ }).click();
  await shot(page, 'filters');
  await close();
}
for (const [title, name] of [
  ['Weekend trip', 'note'],
  ['Launch plan', 'board'],
  ['How a note is made', 'canvas'],
  ['Diary', 'journal'],
]) {
  const { page, close } = await device();
  await page.getByText(title, { exact: true }).first().click();
  await page.waitForTimeout(1800);
  await shot(page, name);
  await close();
}
{
  const { page, close } = await device(true);
  await shot(page, 'desk');
  await close();
}
await browser.close();
