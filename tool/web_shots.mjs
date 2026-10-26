// The web build walked in a real browser (docs/WEB.md): build/web served by tool/serve_web.mjs, opened in Playwright's
// Chromium (or WebKit, Safari's engine) at a desktop's width and a phone's, every screen it reaches pictured into
// build/feature-shots/web/, the first frame timed, a scroll's frames counted, the typed words looked for in
// IndexedDB after a reload, and every console error said.
//
//   node tool/serve_web.mjs 8790 /glyph/ &               build/web, built with GHOST_WEB_API at a dead address
//   node tool/web_shots.mjs [--gpu] [--engine webkit] [--url http://localhost:8790/glyph/] [--only phone]
//
// It signs in nowhere: "Use without an account", and the library the page makes itself.
//
// The presses land where a person's finger would, at the places in [places] (CSS pixels, measured from the
// semantics tree on 2026-10-26 and from these pictures). Flutter's semantics stay off: with them on, the page takes
// its gestures from the tree and not the canvas, so a press places no caret and the toolbar's icons take no tap. A
// place that moves shows in the pictures, which are what the walk is for.
//
// Playwright is not a dependency of the repository: it is found in npx's cache (`npx playwright@1.59 --version`
// puts it there), or where PLAYWRIGHT names its folder.
import { mkdirSync, readdirSync, existsSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const flag = (name, otherwise) => {
  const at = args.indexOf(`--${name}`);
  return at < 0 ? otherwise : args[at + 1];
};
const url = flag('url', 'http://localhost:8790/glyph/');
const engine = flag('engine', 'chromium');
const only = flag('only', null);
const out = join(root, 'build/feature-shots/web');
mkdirSync(out, { recursive: true });

function findPlaywright() {
  if (process.env.PLAYWRIGHT) return process.env.PLAYWRIGHT;
  const npx = join(homedir(), '.npm/_npx');
  for (const one of existsSync(npx) ? readdirSync(npx) : []) {
    const at = join(npx, one, 'node_modules/playwright');
    if (existsSync(join(at, 'package.json'))) return at;
  }
  throw new Error('No Playwright in npx\'s cache: run `npx playwright@1.59 --version` once, or set PLAYWRIGHT.');
}
const playwright = createRequire(import.meta.url)(findPlaywright());

const sizes = {
  desktop: { viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 },
  phone: {
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 3,
    isMobile: engine === 'chromium',
    hasTouch: true,
    // A phone's browser, so the app takes the browser for the phone it is (and the page is no Android app).
    userAgent: 'Mozilla/5.0 (Linux; Android 15; SM-F966B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36',
  },
};

/** Where each thing is pressed, by size. */
const places = {
  desktop: {
    withoutAccount: [720, 697],
    skip: [1388, 38],
    card: [324, 313],
    paragraph: [640, 262],
    market: [1383, 784],
    settings: [1395, 26],
    about: null,
    settingsSearch: [150, 100],
    firstFound: [210, 170],
  },
  phone: {
    withoutAccount: [196, 641],
    skip: [346, 32],
    card: [194, 253],
    paragraph: [200, 205],
    market: [342, 748],
    settings: [352, 22],
    about: [150, 789],
  },
};

const report = { engine, url, runs: [] };
// `--gpu`: the Mac's GPU for the page, where headless Chromium otherwise draws WebGL in software (SwiftShader), and
// counts a scroll's frames at a tenth of what a person's browser draws.
const browser = await playwright[engine].launch(args.includes('--gpu') && engine === 'chromium' ? { args: ['--enable-gpu', '--ignore-gpu-blocklist', '--use-angle=metal'] } : {});

async function walk(size) {
  const name = `${size}${engine === 'chromium' ? '' : `-${engine}`}`;
  const at = places[size];
  const context = await browser.newContext({ ...sizes[size], colorScheme: 'dark' });
  const page = await context.newPage();
  const errors = [];
  page.on('console', (message) => {
    if (message.type() === 'error') errors.push(message.text());
  });
  page.on('pageerror', (error) => errors.push(`pageerror: ${error.message}`));
  await page.addInitScript(() => {
    window.__ghostFirstFrame = null;
    window.addEventListener('flutter-first-frame', () => (window.__ghostFirstFrame = performance.now()));
  });
  const opened = async () => {
    await page.waitForFunction(() => window.__ghostFirstFrame !== null, null, { timeout: 60000 });
    // The launch screen gives way to the first page in a few seconds: nothing is pressed before.
    await page.waitForTimeout(5000);
  };
  const began = Date.now();
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForFunction(() => window.__ghostFirstFrame !== null, null, { timeout: 60000 });
  const firstFrame = await page.evaluate(() => window.__ghostFirstFrame);
  const loaded = await page.evaluate(() => {
    const all = performance.getEntriesByType('resource');
    return { files: all.length, kb: Math.round(all.reduce((sum, e) => sum + (e.transferSize || 0), 0) / 1024) };
  });
  await page.waitForTimeout(5000);
  const shot = (what) => page.screenshot({ path: join(out, `${name}-${what}.png`) });
  const press = async (where, wait = 1500) => {
    const [x, y] = at[where];
    if (sizes[size].hasTouch) await page.touchscreen.tap(x, y);
    else await page.mouse.click(x, y);
    await page.waitForTimeout(wait);
  };
  const steps = [];
  const step = async (what, run) => {
    try {
      await run();
      steps.push(`ok ${what}`);
    } catch (failure) {
      steps.push(`x ${what}: ${String(failure.message).split('\n')[0]}`);
      await shot(`failed-${what.replace(/\W+/g, '-')}`).catch(() => {});
    }
  };

  await step('sign-in screen', () => shot('sign-in'));
  await step('use without an account, skip the walkthrough', async () => {
    await press('withoutAccount');
    await shot('walkthrough');
    await press('skip');
    await shot('home');
  });
  await step('open the sample note and type in it', async () => {
    // The note's page comes in over a moment: the press that places the caret waits for it.
    await press('card', 2500);
    await shot('note');
    await press('paragraph', 800);
    await page.keyboard.type('Typed in the browser, kept in IndexedDB. ', { delay: 25 });
    await page.waitForTimeout(2000);
    await shot('note-typed');
  });
  await step('a scroll of the note, its frames counted', async () => {
    // The browser's frames for two seconds, and the longest gap between two: what a scroll feels like.
    const count = () =>
      page.evaluate(async () => {
        let frames = 0;
        let longest = 0;
        let last = performance.now();
        let on = true;
        const tick = (now) => {
          frames += 1;
          longest = Math.max(longest, now - last);
          last = now;
          if (on) requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
        await new Promise((done) => setTimeout(done, 2000));
        on = false;
        return { frames, longest: Math.round(longest) };
      });
    const box = sizes[size].viewport;
    await page.mouse.move(box.width / 2, box.height / 2);
    const scrolling = count();
    for (let i = 0; i < 40; i += 1) {
      await page.mouse.wheel(0, i < 20 ? 120 : -120);
      await page.waitForTimeout(45);
    }
    const during = await scrolling;
    steps.push(`   scrolling: ${during.frames} frames in 2 s, the longest gap ${during.longest} ms`);
    await shot('note-scrolled');
  });
  await step('reload: the typed words are still there', async () => {
    await page.reload({ waitUntil: 'load' });
    await opened();
    const kept = await page.evaluate(async () => {
      const db = await new Promise((ok, no) => {
        const asked = indexedDB.open('ghost-md');
        asked.onsuccess = () => ok(asked.result);
        asked.onerror = no;
      });
      const all = await new Promise((ok) => {
        const asked = db.transaction('notes').objectStore('notes').getAll();
        asked.onsuccess = () => ok(asked.result);
      });
      db.close();
      return all.map((text) => JSON.parse(text)).map((note) => ({ path: note.path, revision: note.revision, typed: note.body.includes('Typed in the browser') }));
    });
    steps.push(`   kept: ${JSON.stringify(kept)}`);
    if (!kept.some((note) => note.typed)) throw new Error('the typed words are not kept');
    await shot('reloaded');
  });
  await step('the Market', async () => {
    await page.goto(url, { waitUntil: 'load' });
    await opened();
    await press('market');
    await shot('market');
  });
  await step('Settings, and About with its web card', async () => {
    await page.goto(url, { waitUntil: 'load' });
    await opened();
    await press('settings');
    await shot('settings');
    if (at.about) {
      // The phone's list has About in view.
      await press('about');
    } else {
      // The desktop's sidebar does not: found by Settings' own search, and its one row pressed.
      await press('settingsSearch', 600);
      await page.keyboard.type('About', { delay: 25 });
      await page.waitForTimeout(1200);
      await shot('settings-search');
      await press('firstFound');
    }
    await shot('about');
  });
  report.runs.push({ name, firstFrameMs: Math.round(firstFrame), wallMs: Date.now() - began, loaded, steps, errors });
  await context.close();
}

for (const size of only ? [only] : ['desktop', 'phone']) await walk(size);
await browser.close();

writeFileSync(join(out, `report-${engine}.json`), `${JSON.stringify(report, null, 2)}\n`);
for (const run of report.runs) {
  console.log(`\n${run.name}: first frame ${run.firstFrameMs} ms after navigation, ${run.loaded.files} files, ${run.loaded.kb} KB`);
  for (const line of run.steps) console.log(`  ${line}`);
  console.log(run.errors.length ? `  console errors:\n${run.errors.map((e) => `    ${e}`).join('\n')}` : '  console: no errors');
}
console.log(`\npictures in ${out}`);
