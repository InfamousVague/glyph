// The web app's own smoke, drawn by Chromium, for the Flutter shaders to be held against
// (test/art/wisp_parity_test.dart). Every picture is the web filter over test/art/reference/card.png, the one page of
// words both engines bend, at two device pixels to the logical pixel on a touch screen, with nothing behind it.
//
// The boxed filters, the mask's bands and the dock's pictures are made by the web app's own modules, loaded from its
// dev server, so what is drawn is what ships; the page's two bands are art/WispEdgeFilter.tsx's markup written out
// with art/wispEdge.ts's numbers, placed as `placeBand` and `placeFoot` place them. The numbers each picture was
// drawn with go to cases.json, and the test holds the Dart port's own numbers to them before it compares a pixel.
//
//   (cd tauri && npx vite --port 5261 --strictPort --host 127.0.0.1) &     # read-only: never `vite build` there
//   node tool/wisp_reference.mjs
//
// Playwright and pngjs are not this repository's: they are taken from the npx cache, as ../ghost-md-app-store-pack's
// shoot scripts take them.
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { readFileSync, writeFileSync } from 'node:fs';

const BASE = process.env.GLYPH_DEV ?? 'http://127.0.0.1:5261/';
const OUT = new URL('../test/art/reference/', import.meta.url).pathname;
const card = `data:image/png;base64,${readFileSync(`${OUT}card.png`).toString('base64')}`;
const CARD = { width: 390, height: 420 };

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 700, height: 900 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
const page = await context.newPage();
// A page of the dev server's own origin with nothing on it, so the app's modules load and the app does not start.
await page.route('**/__wisp_reference', (route) => route.fulfill({ contentType: 'text/html', body: '<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head><body style="margin:0;background:transparent"></body></html>' }));
await page.goto(`${BASE}__wisp_reference`);

const cases = {};

/** Draws `html` at the page's corner and takes `clip` of it, clear where nothing is drawn. */
async function shot(name, html, clip, note) {
  await page.evaluate((markup) => {
    document.getElementById('stage')?.remove();
    const stage = document.createElement('div');
    stage.id = 'stage';
    stage.innerHTML = markup;
    document.body.append(stage);
  }, html);
  await page.waitForTimeout(250);
  writeFileSync(`${OUT}web-${name}.png`, await page.screenshot({ clip, omitBackground: true }));
  cases[name] = note;
  console.log(name);
}

const edge = await page.evaluate(async () => {
  const m = await import('/src/app/art/wispEdge.ts');
  return {
    ABOVE: m.WISP_EDGE_ABOVE,
    BAND: m.WISP_EDGE_BAND,
    SOFT: m.WISP_EDGE_SOFT,
    REACH: m.WISP_EDGE_REACH,
    FOOT_BAND: m.WISP_EDGE_FOOT_BAND,
    FOOT_SOFT: m.WISP_EDGE_FOOT_SOFT,
    FOOT_LIFT: m.WISP_EDGE_FOOT_LIFT,
    FOOT_CLEAR: m.WISP_EDGE_FOOT_CLEAR,
    EASE: m.WISP_EDGE_EASE,
    SIDE: m.WISP_EDGE_SIDE,
  };
});
const DROP = 12;
const FOOT_REACH = edge.FOOT_BAND + edge.FOOT_SOFT * 4 + 48;

/** art/wispEdge.ts `stepBand` at `t` on the band's clock. */
function drift(t) {
  const x = 0.018 + 0.003 * Math.sin(t / 2600);
  const y = 0.06 + 0.01 * Math.sin(t / 3400 + 1.3);
  return { frequency: `${x.toFixed(4)} ${y.toFixed(4)}`, dx: (4 * Math.sin(t / 2300 + 0.7)).toFixed(2), dy: (10 + 10 * Math.sin(t / 3100)).toFixed(2) };
}
const REST = { frequency: '0.018 0.06', dx: '0', dy: '0' };

/** art/WispEdgeFilter.tsx `TopBand`, placed under a header `under` px tall as `placeBand` places it. */
function topBand(under, lift, at) {
  const drop = under > 0 ? DROP : 0;
  const strip = edge.ABOVE + under + drop + edge.BAND - lift;
  const reach = 40 + under + drop + edge.REACH;
  return `<svg width="0" height="0" style="position:absolute"><filter id="wispEdge" filterUnits="userSpaceOnUse" x="-40" y="${-(edge.ABOVE + 40)}" width="${CARD.width + 80}" height="${CARD.height + 280}" color-interpolation-filters="sRGB">
    <feTurbulence type="fractalNoise" baseFrequency="${at.frequency}" numOctaves="2" seed="3" x="-40" y="-40" width="4000" height="${reach}" result="rawNoise"/>
    <feOffset in="rawNoise" dx="${at.dx}" dy="${at.dy}" result="slid"/>
    <feColorMatrix in="slid" type="matrix" values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 0 1" result="noise"/>
    <feFlood flood-color="#000" result="black"/>
    <feFlood flood-color="#fff" x="-40" y="${-edge.ABOVE}" width="4000" height="${strip}" result="strip"/>
    <feMerge result="stripOnBlack"><feMergeNode in="black"/><feMergeNode in="strip"/></feMerge>
    <feGaussianBlur in="stripOnBlack" stdDeviation="0 ${edge.SOFT}" result="band"/>
    <feComposite in="noise" in2="band" operator="arithmetic" k1="1" k2="0" k3="-0.5" k4="0.5" result="field"/>
    <feDisplacementMap in="SourceGraphic" in2="field" scale="24" xChannelSelector="R" yChannelSelector="G" x="-40" y="-40" width="4000" height="${reach}" result="bent"/>
    <feGaussianBlur in="bent" stdDeviation="3.4" x="-40" y="-40" width="4000" height="${reach}" result="soft"/>
    <feMorphology in="bent" operator="dilate" radius="2.5" x="-40" y="-40" width="4000" height="${reach}" result="near"/>
    <feComposite in="soft" in2="near" operator="in" result="softNear"/>
    <feColorMatrix in="band" type="luminanceToAlpha" result="bandAlpha"/>
    <feComposite in="softNear" in2="bandAlpha" operator="in" result="smoke"/>
    <feComposite in="SourceGraphic" in2="bandAlpha" operator="out" result="rest"/>
    <feComposite in="bent" in2="bandAlpha" operator="in" result="bentIn"/>
    <feMerge><feMergeNode in="rest"/><feMergeNode in="bentIn"/><feMergeNode in="smoke"/></feMerge>
  </filter></svg>`;
}

/** The foot's filter of art/WispEdgeFilter.tsx, placed at a view `height` tall as `placeFoot` places it. */
function footBand(height, at) {
  const reach = FOOT_REACH + 40 + edge.FOOT_LIFT;
  const top = height - edge.FOOT_LIFT - FOOT_REACH;
  return `<svg width="0" height="0" style="position:absolute"><filter id="wispEdgeFoot" filterUnits="userSpaceOnUse" x="-40" y="${-(edge.ABOVE + 40)}" width="${CARD.width + 80}" height="${CARD.height + 280}" color-interpolation-filters="sRGB">
    <feTurbulence type="fractalNoise" baseFrequency="${at.frequency}" numOctaves="2" seed="3" x="-40" y="${top}" width="4000" height="${reach}" result="rawFootNoise"/>
    <feOffset in="rawFootNoise" dx="${at.dx}" dy="${at.dy}" result="footSlid"/>
    <feColorMatrix in="footSlid" type="matrix" values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 0 1" result="footNoise"/>
    <feFlood flood-color="#000" result="black"/>
    <feFlood flood-color="#fff" x="-40" y="${height - edge.FOOT_LIFT - edge.FOOT_BAND}" width="4000" height="${edge.ABOVE + edge.FOOT_BAND}" result="footStrip"/>
    <feMerge result="footOnBlack"><feMergeNode in="black"/><feMergeNode in="footStrip"/></feMerge>
    <feGaussianBlur in="footOnBlack" stdDeviation="0 ${edge.FOOT_SOFT}" result="footBand"/>
    <feComposite in="footNoise" in2="footBand" operator="arithmetic" k1="1" k2="0" k3="-0.5" k4="0.5" result="footField"/>
    <feDisplacementMap in="SourceGraphic" in2="footField" scale="23" xChannelSelector="R" yChannelSelector="G" x="-40" y="${top}" width="4000" height="${reach}" result="footBent"/>
    <feGaussianBlur in="footBent" stdDeviation="3.4" x="-40" y="${top}" width="4000" height="${reach}" result="footSoft"/>
    <feMorphology in="footBent" operator="dilate" radius="2.5" x="-40" y="${top}" width="4000" height="${reach}" result="footNear"/>
    <feComposite in="footSoft" in2="footNear" operator="in" result="footSoftNear"/>
    <feColorMatrix in="footBand" type="luminanceToAlpha" result="footAlpha"/>
    <feComposite in="footSoftNear" in2="footAlpha" operator="in" result="footSmoke"/>
    <feComposite in="SourceGraphic" in2="footAlpha" operator="out" result="rest"/>
    <feComposite in="footBent" in2="footAlpha" operator="in" result="footBentIn"/>
    <feMerge><feMergeNode in="rest"/><feMergeNode in="footBentIn"/><feMergeNode in="footSmoke"/></feMerge>
  </filter></svg>`;
}

/** art/wisp.css's mask on a smoking view. */
const edgeMask = (topFade, footFade) =>
  `-webkit-mask-image:linear-gradient(to bottom, transparent 0, #000 ${topFade}px, #000 calc(100% - ${footFade}px), transparent 100%);mask-image:linear-gradient(to bottom, transparent 0, #000 ${topFade}px, #000 calc(100% - ${footFade}px), transparent 100%)`;
const view = (style, { width = CARD.width, height = CARD.height, x = 0, y = 0 } = {}) =>
  `<div style="position:absolute;left:0;top:0;width:${width}px;height:${height}px;background:url(${card}) ${-x}px ${-y}px / ${CARD.width}px ${CARD.height}px no-repeat;${style}"></div>`;
const whole = { x: 0, y: 0, ...CARD };

// The noise alone, made opaque as the filters make it: what lib/art/turbulence.dart is held to, number for number.
for (const [name, frequency, octaves, seed, stitch] of [
  ['turbulence', '0.018 0.06', 2, 3, false],
  ['turbulence-sides', '0.07 0.035', 2, 5, false],
  ['turbulence-stitched', '0.035', 3, 7, true],
]) {
  const box = { width: 256, height: 128 };
  await shot(
    name,
    `<svg width="${box.width}" height="${box.height}" style="position:absolute;left:0;top:0"><filter id="t" x="0" y="0" width="1" height="1" color-interpolation-filters="sRGB">
      <feTurbulence type="fractalNoise" baseFrequency="${frequency}" numOctaves="${octaves}" seed="${seed}" ${stitch ? 'stitchTiles="stitch"' : ''} result="raw"/>
      <feColorMatrix in="raw" type="matrix" values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 0 1"/></filter>
      <rect width="${box.width}" height="${box.height}" filter="url(#t)"/></svg>`,
    { x: 0, y: 0, ...box },
    { ...box, frequency, octaves, seed, stitch },
  );
}

// The page's top band under a header 60px tall, drifted five seconds into a scroll.
const moved = drift(5000);
await shot('top', topBand(60, 0, moved) + view(`filter:url(#wispEdge);${edgeMask(0, 0)}`), whole, { under: 60, lift: 0, ...moved, topFade: 0, footFade: 0 });
// With no header, under a status bar 36px tall, at rest: the lip a drop under the bar, and the short fade into it.
await shot('bare', topBand(36, 0, REST) + view(`filter:url(#wispEdge);${edgeMask(36 + 8, 0)}`), whole, { under: 36, lift: 0, ...REST, topFade: 44, footFade: 0 });
// The foot, at rest, with its 32px fade.
await shot('foot', footBand(CARD.height, REST) + view(`filter:url(#wispEdgeFoot);${edgeMask(0, 32)}`), whole, { height: CARD.height, ...REST, topFade: 0, footFade: 32 });
// The foot drifted, to see the slide move the cloud the same way.
await shot('foot-moved', footBand(CARD.height, moved) + view(`filter:url(#wispEdgeFoot);${edgeMask(0, 32)}`), whole, { height: CARD.height, ...moved, topFade: 0, footFade: 32 });

// A board lane's foot (art/wispFoot.ts), a tall lane and a short one, each under the fade the lane wears with it.
for (const [name, height] of [
  ['lane', 300],
  ['lane-short', 96],
]) {
  const made = await page.evaluate(async ([h, w]) => {
    const m = await import('/src/app/art/wispFoot.ts');
    const value = m.wispFoot(h, w);
    const id = /url\(#(.+)\)/.exec(value ?? '')?.[1];
    return { value, fade: m.wispFootFade(h), filter: id ? document.getElementById(id).outerHTML : null };
  }, [height, CARD.width]);
  const fade = `-webkit-mask-image:linear-gradient(to bottom, #000 calc(100% - ${made.fade}px), transparent);mask-image:linear-gradient(to bottom, #000 calc(100% - ${made.fade}px), transparent)`;
  await shot(name, view(`filter:${made.value};${fade}`, { height }), { ...whole, height }, { height, width: CARD.width, fade: made.fade, filter: made.filter });
}

// The tab row's ends (art/wispSides.ts): both open, then the start alone, under the row's own 12px fades.
for (const [name, start, end] of [
  ['sides', true, true],
  ['sides-start', true, false],
]) {
  const row = { width: CARD.width, height: 48 };
  const made = await page.evaluate(async ([w, h, s, e]) => {
    const m = await import('/src/app/art/wispSides.ts');
    const value = m.wispSides(w, h, s, e);
    const id = /url\(#(.+)\)/.exec(value ?? '')?.[1];
    return { value, filter: id ? document.getElementById(id).outerHTML : null };
  }, [row.width, row.height, start, end]);
  const fade = `linear-gradient(to right, transparent 0, #000 ${start ? 12 : 0}px, #000 calc(100% - ${end ? 12 : 0}px), transparent 100%)`;
  await shot(name, view(`filter:${made.value};-webkit-mask-image:${fade};mask-image:${fade}`, { ...row, y: 100 }), { x: 0, y: 0, ...row }, { ...row, start, end, cardY: 100, filter: made.filter });
}

// A letter of art/WispText.tsx part way through setting: the second filter of the pool, bent 18 and blurred 1.5.
{
  const box = { width: 44, height: 44 };
  const at = { x: 160, y: 120 };
  const filter = `<svg width="0" height="0" style="position:absolute"><filter id="wispLetter" x="-300%" y="-150%" width="700%" height="400%" color-interpolation-filters="sRGB">
    <feTurbulence type="fractalNoise" baseFrequency="0.018 0.06" numOctaves="2" seed="8" result="n"/>
    <feDisplacementMap in="SourceGraphic" in2="n" scale="18" xChannelSelector="R" yChannelSelector="G" result="d"/>
    <feGaussianBlur in="d" stdDeviation="1.5"/></filter></svg>`;
  const letter = `<div style="position:absolute;left:${at.x}px;top:${at.y}px;width:${box.width}px;height:${box.height}px;background:url(${card}) -18px -4px / ${CARD.width}px ${CARD.height}px no-repeat;filter:url(#wispLetter)"></div>`;
  const clip = { x: at.x - 3 * box.width, y: at.y - 1.5 * box.height, width: 7 * box.width, height: 4 * box.height };
  await shot('letter', filter + letter, clip, { ...box, cardX: 18, cardY: 4, seed: 8, bend: 18, blur: 1.5 });
  const crisp = filter.replace('scale="18"', 'scale="34"').replace('stdDeviation="1.5"', 'stdDeviation="0"');
  await shot('letter-bent', crisp + letter, clip, { ...box, cardX: 18, cardY: 4, seed: 8, bend: 34, blur: 0 });
}

// The mask's bands (art/wispMask.ts) and the dock's pictures (art/dockSmoke.ts), each as the image the page makes.
{
  const made = await page.evaluate(async () => {
    const mask = await import('/src/app/art/wispMask.ts');
    const dock = await import('/src/app/art/dockSmoke.ts');
    const src = (css) => css.slice('url("'.length, -2);
    return {
      maskTop: src(mask.wispMaskImage('top')),
      maskFoot: src(mask.wispMaskImage('foot')),
      tile: src(dock.dockSmokeTile()),
      core: src(dock.dockSmokeCore(240, 150)),
      ramp: src(dock.dockSmokeRamp(240, 150)),
      sizes: { TILE: mask.WISP_MASK_TILE, ABOVE: mask.WISP_MASK_ABOVE, HEIGHT: mask.WISP_MASK_HEIGHT, REACH: dock.DOCK_SMOKE_REACH, DOCK_TILE: dock.DOCK_SMOKE_TILE },
    };
  });
  const img = (src, w, h) => `<img src='${src}' width="${w}" height="${h}" style="position:absolute;left:0;top:0;display:block">`;
  await shot('mask-top', img(made.maskTop, 512, 256), { x: 0, y: 0, width: 512, height: 256 }, made.sizes);
  await shot('mask-foot', img(made.maskFoot, 512, 256), { x: 0, y: 0, width: 512, height: 256 }, made.sizes);
  await shot('dock-tile', img(made.tile, 256, 256), { x: 0, y: 0, width: 256, height: 256 }, made.sizes);
  await shot('dock-core', img(made.core, 240, 150), { x: 0, y: 0, width: 240, height: 150 }, { width: 240, height: 150 });
  await shot('dock-ramp', img(made.ramp, 240, 150), { x: 0, y: 0, width: 240, height: 150 }, { width: 240, height: 150 });
}

// The dock's halo bending what lies behind it (`#dockWisp`), over the card on the dark paper: a backdrop has to have
// something behind it, so this one picture is not clear.
{
  const filter = `<svg width="0" height="0" style="position:absolute"><filter id="dockWisp" x="0" y="0" width="1" height="1" color-interpolation-filters="sRGB">
    <feTurbulence type="fractalNoise" baseFrequency="0.018 0.06" numOctaves="2" seed="3" result="rawDockNoise"/>
    <feColorMatrix in="rawDockNoise" type="matrix" values="1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 0 1" result="dockNoise"/>
    <feDisplacementMap in="SourceGraphic" in2="dockNoise" scale="23" xChannelSelector="R" yChannelSelector="G" result="dockBent"/>
    <feGaussianBlur in="dockBent" stdDeviation="1.6"/></filter></svg>`;
  const halo = { x: 40, y: 90, width: 300, height: 180 };
  const html = `<div style="position:absolute;left:0;top:0;width:${CARD.width}px;height:${CARD.height}px;background:#0d0d0d">${view('')}
    <div style="position:absolute;left:${halo.x}px;top:${halo.y}px;width:${halo.width}px;height:${halo.height}px;backdrop-filter:url('#dockWisp')"></div></div>`;
  await shot('dock-bend', filter + html, whole, { halo, paper: '#0d0d0d' });
}

writeFileSync(`${OUT}cases.json`, `${JSON.stringify({ edge: { ...edge, DROP, FOOT_REACH }, cases }, null, 2)}\n`);
await browser.close();
