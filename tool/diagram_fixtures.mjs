// The pictures a test's screens show for their diagrams (test/editor/diagrams/support.dart `PicturedBridge`): each
// ask a test wrote down (test/editor/diagrams/fixtures/<name>.ask.json) drawn by the app's own page
// (assets/diagrams/index.html) in Chromium, as the phone's web view draws it, and kept beside it the way the
// phone's half of the channel answers (android/…/ghost_md/DiagramRenderer.kt): <name>.png, the picture's part of
// the page out to whole pixels with nothing behind it, and <name>.json, `{blockWidth, blockHeight, x, y, width,
// height, scale}` or `{failed}`.
//
//     DIAGRAM_FIXTURES=want flutter test <the test>      # writes the asks it had no picture for
//     node tool/diagram_fixtures.mjs [--all]             # draws them (--all: every ask again)
//     flutter test --update-goldens <the test>           # and the test's own pictures with them
//
// A picture's name is its key's (lib/editor/diagrams/store.dart `diagramFile`), and the key has the page's version
// in it (`diagramPage`): a page that draws differently asks for its pictures again under other names, and the old
// ones are to be deleted.
//
// Playwright is not this repository's: it is taken from the npx cache, as tool/editor_reference.mjs takes it.
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';

const FOLDER = new URL('../test/editor/diagrams/fixtures/', import.meta.url).pathname;
const PAGE = new URL('../assets/diagrams/index.html', import.meta.url).href;
const all = process.argv.includes('--all');

const asks = readdirSync(FOLDER)
  .filter((file) => file.endsWith('.ask.json'))
  .map((file) => file.slice(0, -'.ask.json'.length))
  .filter((name) => all || !existsSync(`${FOLDER}${name}.json`));
if (!asks.length) {
  console.log('nothing to draw');
  process.exit(0);
}

const browser = await chromium.launch();
let n = 0;
for (const name of asks) {
  const ask = JSON.parse(readFileSync(`${FOLDER}${name}.ask.json`, 'utf8'));
  const ratio = ask.ratio ?? 2;
  // A window as wide as the app's, and tall enough for anything, as the phone's web view is laid out.
  const context = await browser.newContext({ viewport: { width: Math.round(ask.viewport), height: 4000 }, deviceScaleFactor: ratio });
  const page = await context.newPage();
  await page.goto(PAGE);
  await page.waitForFunction(() => (window.ghostSaid ?? []).some((said) => said.ready));
  n += 1;
  await page.evaluate((ask) => window.ghostDiagram.draw(ask), { ...ask, n });
  const said = await (await page.waitForFunction((n) => (window.ghostSaid ?? []).find((said) => said.n === n), n)).jsonValue();
  if (!said.ok) {
    writeFileSync(`${FOLDER}${name}.json`, `${JSON.stringify({ failed: said.failed ?? '' }, null, 2)}\n`);
    console.log(`${name}: ${said.failed || 'could not be drawn'}`);
  } else {
    // The picture's box on the page, out to whole pixels (DiagramRenderer.kt `photograph`).
    const left = Math.floor(said.picture.x * ratio), top = Math.floor(said.picture.y * ratio);
    const wide = Math.ceil((said.picture.x + said.picture.width) * ratio) - left, tall = Math.ceil((said.picture.y + said.picture.height) * ratio) - top;
    const png = await page.screenshot({ clip: { x: left / ratio, y: top / ratio, width: wide / ratio, height: tall / ratio }, omitBackground: true });
    writeFileSync(`${FOLDER}${name}.png`, png);
    const answer = { blockWidth: said.block.width, blockHeight: said.block.height, x: left / ratio - said.origin.x, y: top / ratio - said.origin.y, width: wide / ratio, height: tall / ratio, scale: ratio };
    writeFileSync(`${FOLDER}${name}.json`, `${JSON.stringify(answer, null, 2)}\n`);
    console.log(`${name}: ${wide} x ${tall} px, a block ${said.block.width} x ${said.block.height} (${ask.code.split('\n')[0]})`);
  }
  await context.close();
}
await browser.close();
