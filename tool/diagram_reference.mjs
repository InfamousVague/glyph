// The diagram page held to the web app (assets/diagrams/, lib/editor/diagrams/): the same diagrams drawn by the web
// app's own editor (tauri/src/app/editor/Editor.tsx with its `drawnMermaid()`) and by this app's page, in the
// same browser, and what differs between the two.
//
// For each case the web editor is given a note that is one ```mermaid fence, read-only, and once its block is drawn
// the block's box and the picture's box in it are measured and photographed. The page is then asked for the same
// diagram the way the app asks it (`ghostDiagram.draw`), with what the app would read off its own tokens read here
// off the web page's computed styles, and measured and photographed the same way. A case passes when the two
// blocks are the same size, the pictures sit in the same place, and every pixel of one photograph is the other's
// own or, where an edge was drawn a part of a pixel across (a pie's rim, a letter's stem: the same browser does it
// to the same page in two tabs), between the lightest and the darkest of the other's round the same place. Nothing is written but what is said on the terminal (and, with
// --keep <folder>, the photographs).
//
//   (cd tauri && npx vite --port 5270 --strictPort --host 127.0.0.1) &     # read-only: never `vite build` there
//   node tool/diagram_reference.mjs [--webkit] [--keep folder] [--width px] [--ratio n] [--asks] [name ...]
//
// --width and --ratio draw every set at one window's width and one device's ratio (a phone's, to hold a picture
// taken on it to the web app's); --asks says what each case asked the page, to be read beside what the phone's
// debug build says it asked (`adb logcat -s GhostDiagram`).
//
// Chromium is the phone's engine (Android's web view); --webkit holds the page to the web app in the Mac's and the
// iPhone's. Playwright and pngjs are not this repository's: they are taken from the npx cache, as
// tool/editor_reference.mjs takes them.
import { chromium, webkit } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { mkdirSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';

const { PNG } = createRequire(import.meta.url)('/Users/matt/.npm/_npx/249ca9fcd30c476a/node_modules/pngjs/lib/png.js');

const BASE = process.env.GLYPH_DEV ?? 'http://127.0.0.1:5270/';
const PAGE = new URL('../assets/diagrams/index.html', import.meta.url).href;

const args = process.argv.slice(2);
const engine = args.includes('--webkit') ? webkit : chromium;
const keep = args.includes('--keep') ? args[args.indexOf('--keep') + 1] : null;
const valued = ['--keep', '--width', '--ratio'];
const valueOf = (name) => (args.includes(name) ? Number(args[args.indexOf(name) + 1]) : null);
const width = valueOf('--width'), ratio = valueOf('--ratio') ?? 2.625;
const asks = args.includes('--asks');
const only = args.filter((arg, index) => !arg.startsWith('--') && !valued.includes(args[index - 1]));
if (keep) mkdirSync(keep, { recursive: true });

/** The diagrams: the app's own (the sample note's, a new chart card's, the sample canvas's, the Academy's), and one of each of the kinds a note is likeliest to hold. */
const CODES = {
  sample: 'flowchart LR\n  A[Say it] --> B[A note]',
  chart: 'flowchart LR\n  A[Start] --> B[Then]\n  B --> C[Done]',
  cabin: 'flowchart LR\n  F[Friday: drive up] --> S[Saturday: the lake]\n  S --> U[Sunday: the long walk]\n  U --> H[Home by dark]',
  lesson: 'flowchart TD\n  A[Speak] --> B[Note]',
  guide: 'flowchart TD\n  A[Speak] --> B[Note]\n  B --> C[Board]',
  shapes: 'flowchart TD\n  A([Round]) --> B{Which?}\n  B -->|yes| C[(Kept)]\n  B -->|no| D((Gone))\n  subgraph Later\n    C --> E[/Sent/]\n  end',
  sequence: 'sequenceDiagram\n  participant P as Phone\n  participant B as The box\n  P->>B: The note, sealed\n  B-->>P: Kept\n  Note over P,B: Nothing read on the way',
  gantt: 'gantt\n  title A plan\n  dateFormat YYYY-MM-DD\n  section One\n  Write it :done, a1, 2026-10-01, 3d\n  Ship it :active, a2, after a1, 4d\n  Late :crit, a3, 2026-10-02, 2d',
  classes: 'classDiagram\n  class Note {\n    +String title\n    +save()\n  }\n  class Board\n  Note <|-- Board',
  state: 'stateDiagram-v2\n  [*] --> Draft\n  Draft --> Kept: save\n  Kept --> [*]',
  pie: 'pie title Notes\n  "Typed" : 42\n  "Spoken" : 58',
  tall: `flowchart TD\n${Array.from({ length: 12 }, (_, i) => `  S${i}[Step ${i + 1}] --> S${i + 1}[Step ${i + 2}]`).join('\n')}`,
};

/** How the app is set for a run of cases: which way it is painted, the note's face, and how wide the window is. */
const SETS = [
  { name: 'light', theme: 'light', noteFace: 'maple', width: 412 },
  { name: 'dark', theme: 'dark', noteFace: 'maple', width: 412 },
  { name: 'inter', theme: 'light', noteFace: 'inter', width: 412 },
  { name: 'wide', theme: 'light', noteFace: 'maple', width: 884 },
];

const browser = await engine.launch();
let failed = 0;

for (const set of SETS) {
  if (width && set.name === 'wide') continue;
  // Tall enough for the tallest case whole: a photograph is cut off where the window ends.
  const context = await browser.newContext({ viewport: { width: width ?? set.width, height: 3000 }, deviceScaleFactor: ratio });
  // The web app's editor.
  const web = await context.newPage();
  web.on('pageerror', (error) => console.log('page error (web):', error.message));
  await web.route('**/__diagram_reference', (route) =>
    route.fulfill({
      contentType: 'text/html',
      body: '<!doctype html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body><div id="stage"></div></body></html>',
    }),
  );
  await web.goto(`${BASE}__diagram_reference`);
  await web.evaluate(async (set) => {
    // What @vitejs/plugin-react's preamble sets on the app's own page: its modules ask for it before they run.
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
    window.Prefs = await import('/src/app/core/preferences.ts');
    // The setting, kept and stamped on the root as the app does it: a diagram reads which way the app is painted
    // from the preferences themselves (mermaid.ts `darkNow`).
    window.Prefs.setPreferences({ theme: set.theme, noteFace: set.noteFace });
    document.body.style.background = 'var(--glacier-bg)';
    await document.fonts.ready;
  }, set);

  // This app's page.
  const mine = await context.newPage();
  mine.on('pageerror', (error) => console.log('page error (page):', error.message));
  await mine.goto(PAGE);
  await mine.waitForFunction(() => (window.ghostSaid ?? []).some((said) => said.ready));

  let n = 0;
  for (const [name, code] of Object.entries(CODES)) {
    if (only.length && !only.includes(name) && !only.includes(set.name) && !only.includes(`${set.name}-${name}`)) continue;
    n += 1;
    const theirs = await web.evaluate(
      async ({ code, set }) => {
        const { React, ReactDOM, EditorModule } = window;
        window.root?.unmount();
        const stage = document.getElementById('stage');
        stage.replaceChildren();
        const host = document.createElement('div');
        host.style.cssText = 'display: flex; flex-direction: column;';
        stage.append(host);
        window.root = ReactDOM.createRoot(host);
        window.root.render(
          React.createElement(EditorModule.Editor, { value: `\`\`\`mermaid\n${code}\n\`\`\``, onChange: () => {}, dark: set.theme === 'dark', assist: false, display: 'formatted', readOnly: true, grow: true }),
        );
        let wrap = null;
        for (let tries = 0; tries < 400; tries += 1) {
          wrap = host.querySelector('.cm-mermaid');
          if (wrap && (wrap.hasAttribute('data-drawn') || wrap.querySelector('.cm-mermaidWhy'))) break;
          await new Promise((done) => setTimeout(done, 25));
        }
        if (!wrap) return { missing: true };
        const why = wrap.querySelector('.cm-mermaidWhy');
        if (why) return { failed: why.textContent };
        await document.fonts.ready;
        // The block on whole device pixels, as the page's is (16px down, which is whole at any ratio a phone has):
        // the editor's own room over its first line puts it part of a pixel down, and a photograph cut there is the
        // same picture a row off.
        const top = wrap.getBoundingClientRect().top;
        host.style.marginTop = `${Math.ceil(top / 8) * 8 - top}px`;
        await new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));
        const block = wrap.getBoundingClientRect();
        const picture = wrap.querySelector('svg').getBoundingClientRect();
        const style = getComputedStyle(wrap);
        const face = document.documentElement.getAttribute('data-note-font');
        return {
          block: { x: block.left, y: block.top, width: block.width, height: block.height },
          picture: { x: picture.left - block.left, y: picture.top - block.top, width: picture.width, height: picture.height },
          // What the app reads off its tokens, read off the page.
          ask: {
            viewport: window.innerWidth,
            room: block.width,
            gutter: parseFloat(style.paddingLeft),
            em: parseFloat(style.fontSize),
            ui: getComputedStyle(document.body).fontFamily,
            note: getComputedStyle(wrap.closest('.cm-scroller')).fontFamily,
            coding: face === null || face === 'maple' || face === 'fira',
            ink: getComputedStyle(wrap.closest('.cm-content')).color,
          },
          ground: getComputedStyle(document.body).backgroundColor,
        };
      },
      { code, set },
    );
    const label = `${set.name}-${name}`;
    if (theirs.missing || theirs.failed) {
      console.log(`${label}: the web app did not draw it (${theirs.failed ?? 'no block'})`);
      failed += 1;
      continue;
    }
    const theirShot = await web.screenshot({ clip: theirs.block });

    const ask = { n, code, dark: set.theme === 'dark', ...theirs.ask };
    if (asks) console.log(`${label} asks ${JSON.stringify({ ...ask, code: undefined })}`);
    await mine.evaluate(
      ({ ask, ground }) => {
        document.body.style.background = ground;
        window.ghostDiagram.draw(ask);
      },
      { ask, ground: theirs.ground },
    );
    const said = await (await mine.waitForFunction((n) => (window.ghostSaid ?? []).find((said) => said.n === n), n)).jsonValue();
    if (!said.ok) {
      console.log(`${label}: the page did not draw it (${said.failed || said.why})`);
      failed += 1;
      continue;
    }
    const myShot = await mine.screenshot({ clip: { x: said.origin.x, y: said.origin.y, width: said.block.width, height: said.block.height } });
    if (keep) {
      writeFileSync(`${keep}/${label}-web.png`, theirShot);
      writeFileSync(`${keep}/${label}-page.png`, myShot);
    }

    const problems = [];
    const off = (a, b) => Math.abs(a - b) > 0.01;
    if (off(theirs.block.width, said.block.width) || off(theirs.block.height, said.block.height)) problems.push(`block ${said.block.width} x ${said.block.height}, the web app's ${theirs.block.width} x ${theirs.block.height}`);
    const picture = { x: said.picture.x - said.origin.x, y: said.picture.y - said.origin.y, width: said.picture.width, height: said.picture.height };
    for (const side of ['x', 'y', 'width', 'height']) if (off(theirs.picture[side], picture[side])) problems.push(`picture ${side} ${picture[side]}, the web app's ${theirs.picture[side]}`);
    const a = PNG.sync.read(theirShot), b = PNG.sync.read(myShot);
    let differ = 0, apart = 0, worst = 0;
    if (a.width !== b.width || a.height !== b.height) {
      problems.push(`photograph ${b.width} x ${b.height}, the web app's ${a.width} x ${a.height}`);
    } else {
      const off = (p, i, q, j) => Math.max(Math.abs(p.data[i] - q.data[j]), Math.abs(p.data[i + 1] - q.data[j + 1]), Math.abs(p.data[i + 2] - q.data[j + 2]));
      // Whether the pixel at `i` of `p` is no lighter than the lightest and no darker than the darkest of `q`'s
      // pixels round the same place: the edge of a curve or of a letter, drawn a part of a pixel across, which the
      // same browser does to the same page in two tabs. A line in another place is outside what is round it.
      const within = (p, i, q, x, y) => {
        for (let c = 0; c < 3; c += 1) {
          let lo = 255, hi = 0;
          for (let dy = -1; dy <= 1; dy += 1) {
            for (let dx = -1; dx <= 1; dx += 1) {
              const nx = x + dx, ny = y + dy;
              if (nx < 0 || ny < 0 || nx >= q.width || ny >= q.height) continue;
              const v = q.data[(ny * q.width + nx) * 4 + c];
              if (v < lo) lo = v;
              if (v > hi) hi = v;
            }
          }
          if (p.data[i + c] < lo - 8 || p.data[i + c] > hi + 8) return false;
        }
        return true;
      };
      for (let y = 0; y < a.height; y += 1) {
        for (let x = 0; x < a.width; x += 1) {
          const i = (y * a.width + x) * 4;
          // The photograph's own last row or column where the block ends part of a pixel in: not the diagram's.
          if (a.data[i + 3] !== 255 || b.data[i + 3] !== 255) continue;
          const d = off(a, i, b, i);
          if (d > worst) worst = d;
          if (d <= 8) continue;
          differ += 1;
          if (!(within(a, i, b, x, y) && within(b, i, a, x, y))) apart += 1;
        }
      }
      if (apart > 0) problems.push(`${apart} of ${a.width * a.height} pixels are another picture's (${differ} differ, the worst by ${worst} of 255)`);
    }
    if (problems.length) failed += 1;
    const edges = differ ? `, ${differ} pixels of an edge drawn a part of a pixel across, the worst off by ${worst}` : `, no pixel off by more than ${worst}`;
    console.log(`${label}: ${problems.length ? problems.join('; ') : `the same (${said.block.width} x ${said.block.height}, ${a.width * a.height} pixels${edges})`}`);
  }
  await context.close();
}
await browser.close();
if (failed) {
  console.log(`${failed} differ`);
  process.exit(1);
}
