// The hero: a foldable phone turning slowly in space, the app on its screens, and now and then a screen lifted apart
// into its layers and drawn back in (Matt, 2026-11-27: "redo the phone blow apart view to have a 3d phone ... have it
// move and pan around slowly and have better breakouts have them suck back in and break out from a few different
// views in the app as well such as plugin pages").
//
// Two pictures share one camera. The phone is WebGL: the model at /model/duo.bin where the site has it (./duo.js),
// and a plain foldable of our own where it has not (./phone.js). What is on its screens is the app's own HTML
// (site/mock), each screen a `.h3-screen` given the phone's own matrix as a CSS transform, each piece of the app a
// `.h3-l` layer that lifts along its screen's normal. HTML is always drawn over the canvas, so the app is shown only
// on a screen that faces the camera with nothing of the phone before it: a screen goes dark before the phone folds
// or turns its back, as a real one's does.
//
// Everything that moves is a function of one clock (see TRACK and SCENES), so any moment can be drawn by itself:
// `?h3=12.5` on the page's address holds the hero at that second, and window.__h3.seek(t) does from the console.
import { ACESFilmicToneMapping, Group, PerspectiveCamera, PMREMGenerator, Scene, SRGBColorSpace, TextureLoader, Vector3, WebGLRenderer } from 'three';
import { loadDuo } from './duo.js';
import { makePhone } from './phone.js';
import { makeStudio } from './studio.js';

const RAD = Math.PI / 180;
const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
const lerp = (a, b, t) => a + (b - a) * t;
const EASE = {
  io: (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2),
  out: (t) => 1 - Math.pow(1 - t, 3),
  lin: (t) => t,
};
const outBack = (t, s = 1.25) => 1 + (s + 1) * Math.pow(t - 1, 3) + s * Math.pow(t - 1, 2);
const inBack = (t, s = 1.15) => (s + 1) * t * t * t - s * t * t;

// --- the clock's score -----------------------------------------------------------------------------------------
/** The loop, in seconds. */
const L = 38.6;
/** A screen lifted apart: when its layers leave (out), when the camera has come round to them (held), when they are
 *  drawn back (back), and when the last has landed (home). */
const SCENES = {
  thread: { screen: 'cover', out: 4.2, held: 5.7, back: 10.7, home: 11.6 },
  plugins: { screen: 'inner', out: 16.2, held: 17.8, back: 22.6, home: 23.5 },
  space: { screen: 'inner', out: 25.6, held: 27.2, back: 31.8, home: 32.7 },
};
/** The conversation on the outer screen plays before it is lifted apart (site/mock/hero.js): the reply is typed
 *  from `play` and has been sent by `sent`; it is as it opened again from `reset`, while that screen is dark. */
const CUE = { play: 0.4, sent: 1.9, reset: 12.9 };
/** When the phone begins to shut. */
const SHUT = 33.5;
/** Each a list of [second, value, ease into it]. Angles in degrees. */
const TRACK = {
  // 0 shut, 1 open: it opens after the conversation, and shuts as it turns once round at the end.
  fold: [[0, 0], [12.7, 0], [14.9, 1], [SHUT, 1], [36.4, 0], [L, 0]],
  // The outer screen and the inner one, lit (1) or dark (0). A screen lights as an iPhone's does: what is on it comes
  // in blurred and a little large and settles sharp (Matt, 2026-11-27: "mimick the iphone blur animation when it
  // opens"), the inner one while the phone is still opening its last few degrees.
  cover: [[0, 1], [12.3, 1], [12.7, 0, 'lin'], [36.9, 0], [37.8, 1, 'out'], [L, 1]],
  inner: [[0, 0], [14.15, 0], [15.35, 1, 'out'], [SHUT - 0.3, 1], [SHUT - 0.05, 0, 'lin'], [L, 0]],
  // The inner screen stays lit as the phone shuts and is folded away inside it (Matt, 2026-11-27: "leave the screen
  // on and fold it inside the phone instead of making the screen go black before it's folded shut"). HTML cannot be
  // folded, nor hidden behind the phone, so from just before it shuts the page is a picture of itself on the phone's
  // own display (1 here), under the HTML as that goes; where there is no such picture the screen goes dark instead.
  glass: [[0, 0], [SHUT - 0.4, 0], [SHUT - 0.35, 1, 'lin'], [36.7, 1], [36.75, 0, 'lin'], [L, 0]],
  // What the inner screen shows: 0 the plugins, 1 the space.
  swap: [[0, 0], [23.8, 0], [24.8, 1], [36.8, 1], [36.85, 0, 'lin'], [L, 0]],
  // The phone before the camera: leaning back (tilt), turned in its own plane (spin), turned about the upright
  // (yaw); how large (zoom, 1 fits it to the stage), and moved across the stage (pan, in stage widths and heights).
  tilt: [[0, 6], [4.2, 7], [5.7, 44], [10.7, 40], [11.6, 8], [12.7, 9], [13.8, 15], [15.1, 8], [16.2, 8], [17.8, 35], [22.6, 31], [23.5, 9], [25.6, 9], [27.2, 37], [31.8, 33], [32.7, 10], [33.4, 10], [35.2, 18], [37.4, 6], [L, 6]],
  spin: [[0, 0], [4.2, 0], [5.7, 25], [10.7, 19], [11.6, 0], [16.2, 0], [17.8, -13], [22.6, -8], [23.5, 0], [25.6, 0], [27.2, 12], [31.8, 7], [32.7, 0], [L, 0]],
  yaw: [[0, 16], [4.2, 12], [5.7, -5], [10.7, 8], [11.6, -10], [12.7, -16], [13.8, -34], [15.1, -6], [16.2, -2], [17.8, 7], [22.6, -5], [23.5, 0], [25.6, 4], [27.2, -8], [31.8, 5], [32.7, 3], [33.4, 0], [37.4, -344], [L, -344]],
  zoom: [[0, 1], [4.2, 1], [5.7, 0.86], [10.7, 0.88], [11.6, 1], [16.2, 1], [17.8, 1.07], [22.6, 1.1], [23.5, 1], [25.6, 1], [27.2, 1.07], [31.8, 1.1], [32.7, 1], [33.4, 1], [35.2, 0.9], [37.4, 1], [L, 1]],
  panX: [[0, 0], [4.2, 0], [5.7, 0.03], [10.7, 0.03], [11.6, 0], [16.2, 0], [17.8, 0.075], [22.6, 0.075], [23.5, 0], [25.6, 0], [27.2, 0.075], [31.8, 0.075], [32.7, 0], [L, 0]],
  panY: [[0, 0], [4.2, 0], [5.7, 0.07], [10.7, 0.06], [11.6, 0], [16.2, 0], [17.8, 0.05], [22.6, 0.04], [23.5, 0], [25.6, 0], [27.2, 0.05], [31.8, 0.04], [32.7, 0], [L, 0]],
};
function at(keys, t) {
  if (t <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    const k = keys[i];
    if (t <= k[0]) { const p = keys[i - 1]; return lerp(p[1], k[1], EASE[k[2] || 'io']((t - p[0]) / (k[0] - p[0]))); }
  }
  return keys[keys.length - 1][1];
}
/** How far a lift is apart (a layer's data-z times this, in the app's pixels): more on the inner screen, which is the larger. */
const GAP = { cover: 62, inner: 76 };

/** How far out a layer is at `t`: 0 on the glass, 1 lifted. `r` is its rank (1 the highest), `j` its own small lag. */
function lifted(sc, t, r, j) {
  if (t <= sc.out || t >= sc.home) return 0;
  if (t < sc.back) {
    // Leaving: the highest first, each past its place and back to it.
    const u = clamp01((t - sc.out - (1 - r) * 0.32 - j * 0.08) / (0.9 + 0.3 * r));
    return u <= 0 ? 0 : outBack(u);
  }
  // Drawn back in: a breath further out, then all of it at once, quickening, the nearest landing last.
  const u = clamp01((t - sc.back - (1 - r) * 0.14 - j * 0.04) / (0.42 + 0.26 * r));
  return u >= 1 ? 0 : 1 - inBack(u);
}

// --- matrices for CSS, as three's CSS3DRenderer writes them ------------------------------------------------------
const eps = (v) => (Math.abs(v) < 1e-10 ? 0 : v);
const camCSS = (m) => { const e = m.elements; return `matrix3d(${eps(e[0])},${eps(-e[1])},${eps(e[2])},${eps(e[3])},${eps(e[4])},${eps(-e[5])},${eps(e[6])},${eps(e[7])},${eps(e[8])},${eps(-e[9])},${eps(e[10])},${eps(e[11])},${eps(e[12])},${eps(-e[13])},${eps(e[14])},${eps(e[15])})`; };
const objCSS = (m) => { const e = m.elements; return `translate(-50%,-50%) matrix3d(${eps(e[0])},${eps(e[1])},${eps(e[2])},${eps(e[3])},${eps(-e[4])},${eps(-e[5])},${eps(-e[6])},${eps(-e[7])},${eps(e[8])},${eps(e[9])},${eps(e[10])},${eps(e[11])},${eps(e[12])},${eps(e[13])},${eps(e[14])},${eps(e[15])})`; };

function start(stage, phone) {
  const host = stage.querySelector('.h3');
  const canvas = host.querySelector('.h3-gl'), cam = host.querySelector('.h3-cam');
  const still = matchMedia('(prefers-reduced-motion: reduce)');
  const query = new URLSearchParams(location.search);
  const held = query.get('h3');

  // --- the phone, and a camera looking at it ------------------------------------------------------------------
  const DIM = phone.dim;
  const scene = new Scene();
  const rig = new Group(); // turned and moved before the camera
  const body = new Group(); // the phone, moved so that what the camera looks at is the rig's middle
  body.add(phone.group);
  rig.add(body);
  scene.add(rig);
  const camera = new PerspectiveCamera(22, 1, 200, 30000);
  let gl = null;
  try {
    if (query.has('h3flat')) throw new Error('asked to go without WebGL'); // for seeing what a browser with none shows
    gl = new WebGLRenderer({ canvas, alpha: true, antialias: true, powerPreference: 'high-performance' });
    gl.setClearColor(0x000000, 0);
    gl.outputColorSpace = SRGBColorSpace;
    gl.toneMapping = ACESFilmicToneMapping;
    gl.toneMappingExposure = 1.15;
    const pmrem = new PMREMGenerator(gl);
    scene.environment = pmrem.fromScene(makeStudio(), 0.03).texture;
    pmrem.dispose();
  } catch (_) {
    // No WebGL: the screens still turn and lift, each with a plain edge of its own for a body (.h3-flat).
    gl = null;
    host.classList.add('h3-flat');
  }

  // --- the screens and their layers ---------------------------------------------------------------------------
  const screens = {};
  for (const el of cam.querySelectorAll('.h3-screen')) {
    const key = { cover: 'cover', 'inner-l': 'innerL', 'inner-r': 'innerR' }[el.dataset.screen];
    const [w, h] = phone.screens[key];
    el.style.width = w + 'px';
    el.style.height = h + 'px';
    screens[key] = { el, anchor: phone.anchors[key], w, h, inner: key !== 'cover', side: key === 'innerL' ? -1 : key === 'innerR' ? 1 : 0, last: '', on: -1 };
  }
  host.classList.add('h3-live'); // from here the screens are laid out for 3D; measured below as they lie flat
  const views = {};
  for (const [key, s] of Object.entries(screens)) {
    for (const pane of s.el.querySelectorAll(':scope > .h3-pane')) {
      const view = (views[pane.dataset.view] ||= { name: pane.dataset.view, panes: [], layers: [], on: null, lit: -1 });
      view.panes.push(pane);
      for (const el of pane.querySelectorAll(':scope > .h3-l')) {
        const z = parseFloat(el.dataset.z) || 1;
        const cx = el.offsetLeft + el.offsetWidth / 2, cy = el.offsetTop + el.offsetHeight / 2;
        const zn = Math.min(1, z / 2.4);
        // Lifted, a layer also moves a little away from its screen's middle, and from the fold.
        const dx = (cx - s.w / 2) * 0.13 * zn + s.side * 18 * zn, dy = (cy - s.h / 2) * 0.1 * zn;
        // And leans a few degrees, as a card thrown up does: those above the middle back, those below forward.
        const rx = (-(cy - s.h / 2) / s.h) * 7 * zn, ry = ((cx - s.w / 2) / s.w) * 7 * zn;
        // A faint outline left on the glass where the layer lay.
        const ghost = document.createElement('i');
        ghost.className = 'h3-ghost';
        Object.assign(ghost.style, { left: el.offsetLeft + 'px', top: el.offsetTop + 'px', width: el.offsetWidth + 'px', height: el.offsetHeight + 'px', borderRadius: radiusOf(el) });
        pane.insertBefore(ghost, pane.firstChild);
        view.layers.push({ el, z, dx, dy, rx, ry, gap: s.inner ? GAP.inner : GAP.cover, name: el.dataset.name, last: '' });
      }
    }
  }
  for (const v of Object.values(views)) {
    const zs = v.layers.map((l) => l.z), lo = Math.min(...zs), hi = Math.max(...zs);
    v.layers.forEach((l, i) => { l.r = hi > lo ? (l.z - lo) / (hi - lo) : 1; l.j = ((i * 7919) % 13) / 13; l.ph = ((i * 104729) % 17) / 17; });
    v.scene = SCENES[v.name];
  }
  // The callouts: each a tag beside a named layer of a view, with a line to it.
  const lines = host.querySelector('.h3-lines');
  const tags = [...host.querySelectorAll('.h3-tag')].map((el, i) => {
    const view = views[el.dataset.view], layer = view && view.layers.find((l) => l.name === el.dataset.for);
    const line = document.createElementNS('http://www.w3.org/2000/svg', 'line'), dot = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
    dot.setAttribute('r', '2.6');
    lines.append(line, dot);
    const nums = (v) => (v ? v.split(',').map(Number) : null);
    return { el, view, layer, wide: nums(el.dataset.at), narrow: nums(el.dataset.atS), at: null, pin: nums(el.dataset.pin) || [0.5, 0.5], order: view ? [...host.querySelectorAll(`.h3-tag[data-view="${el.dataset.view}"]`)].indexOf(el) : i, line, dot, shown: false };
  }).filter((t) => t.layer);

  // --- sizes ---------------------------------------------------------------------------------------------------
  let W = 1, H = 1, fovPx = 1, fitShut = 1, fitOpen = 1, stageW = 1, stageH = 1, small = false;
  function size() {
    W = host.clientWidth; H = host.clientHeight;
    stageW = stage.clientWidth; stageH = stage.clientHeight;
    small = stageW < 480;
    camera.aspect = W / H;
    camera.updateProjectionMatrix();
    fovPx = camera.projectionMatrix.elements[5] * H / 2;
    // Fitted to the stage: shut it is as tall as the stage allows, open as wide.
    fitShut = Math.min((stageW * 0.8) / DIM.PW, (stageH * 0.86) / DIM.PH);
    fitOpen = Math.min((stageW * 0.98) / (2 * DIM.PW), (stageH * 0.86) / DIM.PH);
    if (gl) { gl.setPixelRatio(Math.min(devicePixelRatio || 1, 2)); gl.setSize(W, H, false); }
    lines.setAttribute('viewBox', `0 0 ${W} ${H}`);
    for (const g of tags) g.at = small ? g.narrow : g.wide; // a tag with no place for a narrow stage is not shown there
    dirty = true;
  }

  // --- one moment ------------------------------------------------------------------------------------------------
  const look = new Vector3();
  const lean = { x: 0, y: 0, tx: 0, ty: 0 }; // the pointer's small say in where the phone faces
  let dirty = true, intro = held != null || still.matches ? 1 : 0;
  function draw(t) {
    const fold = at(TRACK.fold, t);
    phone.setFold(fold);
    const k = EASE.io(intro); // the first second eases out of the page's own flat picture of the phone
    const drift = small ? 0.6 : 1;
    const tilt = (at(TRACK.tilt, t) + 1.6 * Math.sin((2 * Math.PI * 5 * t) / L + 1) * drift) * k - lean.y * 5;
    const spin = at(TRACK.spin, t) * k;
    const yaw = (at(TRACK.yaw, t) + 3.2 * Math.sin((2 * Math.PI * 4 * t) / L) * drift) * k + lean.x * 7;
    rig.rotation.set(-tilt * RAD, yaw * RAD, spin * RAD, 'YXZ');
    let knock = 0;
    for (const sc of Object.values(SCENES)) {
      const u = t - (sc.back + 0.7), v = t - (sc.out + 0.05);
      if (u > 0 && u < 0.7) knock += Math.exp(-7 * u) * Math.sin(20 * u);
      if (v > 0 && v < 0.6) knock -= 0.5 * Math.exp(-8 * v) * Math.sin(16 * v);
    }
    // On a narrow stage the open phone already fills the width: it comes no nearer there.
    let near = at(TRACK.zoom, t);
    if (small && near > 0.94) near = 0.94;
    const zoom = lerp(fitShut, fitOpen, EASE.io(fold)) * lerp(1, near, k) * (1 - 0.022 * knock);
    phone.centre(fold, look);
    body.position.copy(look).negate();
    rig.position.set(((small ? 0 : at(TRACK.panX, t)) * stageW * k) / zoom, (-at(TRACK.panY, t) * stageH * k) / zoom, 0); // pan is down the page, as CSS counts
    camera.position.set(0, 0, fovPx / zoom);
    // The inner page as a picture on the phone's own display, for folding: true once it is there. Before the phone
    // is drawn, since a moment held still is drawn once.
    const glass = pictured(at(TRACK.glass, t) > 0.5);
    scene.updateMatrixWorld();
    camera.updateMatrixWorld();
    if (gl) gl.render(scene, camera);

    cam.style.transform = `perspective(${fovPx}px) translateZ(${fovPx}px) ${camCSS(camera.matrixWorldInverse)} translate(${W / 2}px,${H / 2}px)`;
    const lit = { cover: at(TRACK.cover, t), inner: at(TRACK.inner, t) };
    const swap = at(TRACK.swap, t), changing = swap > 0.004 && swap < 0.996;
    for (const s of Object.values(screens)) {
      const on = s.inner ? lit.inner : lit.cover;
      // With the picture under it, the HTML only has to go: no blur, or the picture would be seen sharp through it.
      const handed = s.inner && glass, key = on + (handed ? 1000 : 0);
      if (key !== s.on) {
        s.on = key;
        s.el.style.visibility = on > 0.004 ? 'visible' : 'hidden';
        // Lighting: the glass comes up at once, and what is on it out of a blur, from a tenth larger.
        const waking = !handed && on > 0.004 && on < 0.996;
        s.el.classList.toggle('is-waking', waking);
        s.el.style.opacity = handed ? (on < 0.996 ? on.toFixed(3) : '') : waking ? Math.min(1, on * 2.6).toFixed(3) : '';
        s.el.style.setProperty('--wake-blur', waking ? (24 * Math.pow(1 - on, 1.5)).toFixed(2) + 'px' : '0px');
        s.el.style.setProperty('--wake-size', waking ? (1 + 0.1 * Math.pow(1 - on, 2)).toFixed(4) : '1');
      }
      if (s.inner && changing !== s.changing) { s.changing = changing; s.el.classList.toggle('is-changing', changing); }
      if (on > 0.004) { const m = objCSS(s.anchor.matrixWorld); if (m !== s.last) s.el.style.transform = s.last = m; }
    }
    // Which view each screen shows, and how far apart its layers are.
    for (const v of Object.values(views)) {
      // One page gives way to the next as a page changes on the phone: the one leaving falls back into a blur and
      // the one coming rises out of one, the two meeting only while both are blurred, so neither is read through
      // the other and the glass is never bare between them.
      const show = v.name === 'thread' ? 1 : v.name === 'plugins' ? clamp01(1 - swap / 0.62) : clamp01((swap - 0.38) / 0.62);
      if (show !== v.lit) {
        v.lit = show;
        const mid = show > 0.004 && show < 0.996, away = 1 - show;
        for (const p of v.panes) {
          p.classList.toggle('is-on', show > 0.004);
          p.style.opacity = mid ? Math.min(1, show * 1.6).toFixed(3) : '';
          p.style.filter = mid ? `blur(${(16 * away * away).toFixed(2)}px)` : '';
          p.style.transform = mid ? `scale(${(v.name === 'plugins' ? 1 - 0.05 * away : 1 + 0.06 * away).toFixed(4)})` : '';
        }
      }
      const sc = v.scene;
      if (!sc || show <= 0.004) continue;
      const out = t > sc.out && t < sc.home;
      if (out !== v.on) { v.on = out; for (const p of v.panes) p.classList.toggle('is-out', out); }
      const hold = out && t > sc.held && t < sc.back;
      for (const l of v.layers) {
        let o = lifted(sc, t, l.r, l.j);
        if (hold) o += 0.035 * Math.sin(2 * Math.PI * (t * 0.22 + l.ph)); // held, each rides a little on its own
        const m = o === 0 ? '' : `translate3d(${(o * l.dx).toFixed(2)}px,${(o * l.dy).toFixed(2)}px,${(o * l.z * l.gap).toFixed(2)}px) rotateX(${(o * l.rx).toFixed(2)}deg) rotateY(${(o * l.ry).toFixed(2)}deg)`;
        if (m !== l.last) l.el.style.transform = l.last = m;
      }
      // The glass answers as they land.
      const thud = clamp01(1 - Math.abs(t - (sc.back + 0.72)) / 0.26);
      for (const p of v.panes) p.parentNode.style.setProperty('--thud', (thud * thud).toFixed(3));
    }
    callouts(t);
    dirty = false;
  }

  function callouts(t) {
    if (!tags.length) return;
    const box = host.getBoundingClientRect(), sb = stage.getBoundingClientRect();
    for (const g of tags) {
      const sc = g.view.scene, lag = g.order * 0.22;
      const a = clamp01((t - (sc.held - 0.5 + lag)) / 0.5) * (1 - clamp01((t - (sc.back - 0.5)) / 0.35));
      if (a <= 0.004 || !g.at) { if (g.shown) { g.shown = false; g.el.style.opacity = '0'; g.line.style.opacity = g.dot.style.opacity = '0'; } continue; }
      g.shown = true;
      // The tag keeps its own place on the stage; only the line follows the layer as the phone turns.
      const w = g.el.offsetWidth, h = g.el.offsetHeight;
      const x = Math.max(4, Math.min(W - w - 4, sb.left - box.left + (g.at[0] / 100) * sb.width - w / 2));
      const y = Math.max(4, Math.min(H - h - 4, sb.top - box.top + (g.at[1] / 100) * sb.height - h / 2));
      g.el.style.transform = `translate(${x.toFixed(1)}px,${(y + (1 - a) * 8).toFixed(1)}px)`;
      g.el.style.opacity = a.toFixed(3);
      const r = g.layer.el.getBoundingClientRect();
      const ax = r.left + r.width * g.pin[0] - box.left, ay = r.top + r.height * g.pin[1] - box.top;
      // From the tag's edge that faces the layer.
      const cx = x + w / 2, cy = y + h / 2;
      let lx, ly;
      if (Math.abs(ax - cx) > w / 2 + 4) { lx = ax < cx ? x : x + w; ly = cy; } else { lx = cx; ly = ay < cy ? y : y + h; }
      g.line.setAttribute('x1', lx.toFixed(1)); g.line.setAttribute('y1', ly.toFixed(1));
      g.line.setAttribute('x2', ax.toFixed(1)); g.line.setAttribute('y2', ay.toFixed(1));
      g.dot.setAttribute('cx', ax.toFixed(1)); g.dot.setAttribute('cy', ay.toFixed(1));
      g.line.style.opacity = g.dot.style.opacity = (a * 0.75).toFixed(3);
    }
  }

  // --- the inner page as a picture, for the fold ----------------------------------------------------------------
  // /art/hero/space-<dark|light>.webp is the last inner page as the page's theme draws it (tool/hero3d-screens.mjs
  // makes both). It is fetched once the phone is up, long before it is wanted; a phone that cannot show it (our own
  // plain one) or a picture that has not come leaves the screen to go dark before the fold, as it used to.
  const root = document.documentElement;
  const pictures = {};
  let shown = null;
  const picture = () => {
    const theme = root.dataset.theme === 'light' ? 'light' : 'dark';
    if (!gl || !phone.showInner) return null;
    if (!pictures[theme]) {
      const entry = (pictures[theme] = { tex: null });
      new TextureLoader().load(`/art/hero/space-${theme}.webp`, (tex) => {
        tex.colorSpace = SRGBColorSpace;
        tex.flipY = false; // laid out as the file's own coordinates are: left to right, top to bottom
        tex.anisotropy = gl.capabilities.getMaxAnisotropy();
        entry.tex = tex;
        wake();
      }, undefined, () => {});
    }
    return pictures[theme].tex;
  };
  function pictured(want) {
    const tex = want ? picture() : null;
    if (tex !== shown) { phone.showInner(tex); shown = tex; }
    return !!tex;
  }

  // --- running ---------------------------------------------------------------------------------------------------
  // The conversation's scene (site/mock/hero.js), told when by this clock.
  const talk = views.thread && views.thread.panes[0];
  const say = (what) => talk && talk.dispatchEvent(new CustomEvent('h3:cue', { detail: what }));
  let told = -1;
  // Still where motion is asked to be reduced: the conversation, lifted apart.
  const REST = 8;
  let clock = held != null ? parseFloat(held) || 0 : still.matches ? REST : 0, prev = 0, raf = 0, seen = true, frozen = held != null;
  function tick(now) {
    raf = 0;
    const dt = prev ? Math.min(0.1, (now - prev) / 1000) : 0;
    prev = now;
    if (!frozen && !still.matches) {
      const before = clock + dt >= L ? -1 : clock; // round the loop's end, every cue is ahead again
      clock = (clock + dt) % L;
      if (intro < 1) intro = Math.min(1, intro + dt / 1.3);
      if (before < CUE.play && clock >= CUE.play) say('play');
      if (before < CUE.reset && clock >= CUE.reset) say('reset');
      told = -1;
    } else if (clock !== told) {
      // Held at one moment: the conversation as that moment has it, without the playing.
      told = clock;
      say(clock >= CUE.sent && clock < CUE.reset ? 'finish' : 'reset');
    }
    lean.x += (lean.tx - lean.x) * Math.min(1, dt * 4);
    lean.y += (lean.ty - lean.y) * Math.min(1, dt * 4);
    draw(clock);
    const moving = !frozen && !still.matches;
    const leaning = Math.abs(lean.tx - lean.x) + Math.abs(lean.ty - lean.y) > 0.002;
    if (seen && !document.hidden && (moving || leaning)) raf = requestAnimationFrame(tick);
    else prev = 0;
  }
  const wake = () => { if (!raf) raf = requestAnimationFrame(tick); };
  size();
  if ('ResizeObserver' in window) new ResizeObserver(() => { size(); wake(); }).observe(host);
  else addEventListener('resize', () => { size(); wake(); });
  if ('IntersectionObserver' in window) new IntersectionObserver((es) => { seen = es[es.length - 1].isIntersecting; if (seen) wake(); }, { rootMargin: '120px' }).observe(stage);
  document.addEventListener('visibilitychange', wake);
  still.addEventListener?.('change', () => { if (still.matches) { clock = REST; intro = 1; } wake(); });
  // The page's dark and light: the phone is the other, white on the dark page and dark on the light one (Matt,
  // 2026-11-27: "use the white model of the phone on dark mode and the black model of the phone on light mode").
  const finish = () => { phone.setFinish(root.dataset.theme !== 'light'); picture(); wake(); };
  new MutationObserver(finish).observe(root, { attributes: true, attributeFilter: ['data-theme'] });
  finish();
  // The pointer leans it a little, anywhere over the hero.
  const hero = stage.closest('.hero') || stage;
  if (matchMedia('(hover: hover)').matches) {
    hero.addEventListener('pointermove', (e) => {
      const r = hero.getBoundingClientRect();
      lean.tx = ((e.clientX - r.left) / r.width - 0.5) * 2;
      lean.ty = ((e.clientY - r.top) / r.height - 0.5) * 2;
      wake();
    }, { passive: true });
    hero.addEventListener('pointerleave', () => { lean.tx = lean.ty = 0; wake(); });
  }
  window.__h3 = {
    seek(t) { frozen = true; clock = ((t % L) + L) % L; intro = 1; wake(); },
    play() { frozen = false; wake(); },
    get time() { return clock; },
    length: L,
  };
  // Drawn once now, so the phone is there in the same frame the page's flat picture of it goes.
  draw(clock);
  wake();
}

// The corner radius of what a layer holds, for its outline on the glass: the first thing inside it that is drawn
// with a radius of its own.
function radiusOf(layer) {
  let el = layer, r = '';
  for (let depth = 0; depth < 5 && el; depth++) {
    const s = getComputedStyle(el);
    if (parseFloat(s.borderTopLeftRadius) > 0) { r = s.borderRadius; break; }
    if (el.childElementCount !== 1) { const first = [...el.children].find((c) => parseFloat(getComputedStyle(c).borderTopLeftRadius) > 0); if (first && el.childElementCount <= 2) r = getComputedStyle(first).borderRadius; break; }
    el = el.firstElementChild;
  }
  return r || '14px';
}

const stage = document.getElementById('stage');
if (stage && stage.querySelector('.h3-screen')) {
  // After the app's own font has come (or 2.5 s at most), so no piece is measured before it has its width.
  const go = (phone) => { try { start(stage, phone); } catch (e) { stage.querySelector('.h3')?.classList.remove('h3-live'); console.error('hero3d', e); } };
  const fonts = document.fonts ? document.fonts.ready : Promise.resolve();
  // The phone's model, where the site has one; our own plain foldable where it has not, or it cannot be read.
  const model = new URLSearchParams(location.search).has('h3plain') ? Promise.reject() : loadDuo('/model/duo.bin');
  const phone = model.catch(() => makePhone());
  Promise.all([phone, Promise.race([fonts, new Promise((r) => setTimeout(r, 2500))])]).then(([p]) => go(p));
}
