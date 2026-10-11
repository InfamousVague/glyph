// What the web app's canvas files answer, for the Dart port to be held against byte for byte (lib/canvas,
// test/canvas/fixtures_test.dart).
//
//   node tool/canvas_fixtures.mjs
//
// Everything is read from tauri/ and nothing is written there: Node (22.18 or later) runs the web's TypeScript as
// it is, types struck off, and the one thing in reach of these files that is not code (sampleNote.ts imports an
// SVG) is answered with an empty string. One fixture goes to test/canvas/fixtures/canvas.json. Seeded, so running
// it again writes the same file.
//
// The file:
//   parse   texts read by `parseCanvas` and written back by `serializeCanvas` (null where it is not a canvas):
//           the tests' samples, what the reader leaves out, strings a JSON writer may escape its own way
//   made    the two example canvases as `serializeCanvas` writes them, and as notes (`canvasNoteBody`)
//   notes   bodies with and without front matter: `isCanvasBody`, and `withCanvas(body, <the view sample>)`
//   edits   a canvas, then steps: each an edit by name with its arguments (the Dart test makes the same edit), the
//           canvas written after it, and every line's path after it
//   paths   canvases laid out to crowd their lines, and every line's path: `d`, the heads, the label's place
//           and its lines, string for string. Numbers are written as JavaScript prints them.
//   calls   the small pure functions by name, their arguments and what they answered: `brokenInto`, `wordBars`,
//           `noteBars`, `roundedBox`, `fitted`, `fittedTo`, `zoomedAt`, `shown`, `clearSpot`, `heldBy`, `sidesOf`
import { mkdirSync, writeFileSync } from 'node:fs';
import { registerHooks } from 'node:module';

const WEB = new URL('../tauri/src/', import.meta.url).pathname;
const OUT = new URL('../test/canvas/fixtures/', import.meta.url).pathname;

// A picture or a stylesheet imported by a module on the way: nothing here draws one.
registerHooks({
  load(url, context, nextLoad) {
    if (/\.(svg|png|jpe?g|webp|css|woff2?)(\?.*)?$/.test(url)) return { format: 'module', source: 'export default "";', shortCircuit: true };
    return nextLoad(url, context);
  },
});

const from = (path) => import(`${WEB}${path}`);
const J = await from('app/canvas/jsonCanvas.ts');
const L = await from('app/canvas/lines.ts');
const E = await from('app/canvas/edits.ts');
const G = await from('app/canvas/geometry.ts');
const C = await from('app/canvas/comments.ts');
const M = await from('app/canvas/mapDetail.ts');
const V = await from('app/canvas/viewport.ts');
const S = await from('app/canvas/sampleCanvas.ts');
const H = await from('app/canvas/howCanvas.ts');
const T = await from('test/canvas.ts');

// ---- A seeded die ------------------------------------------------------------------------------------------------

let seed = 20261008;
function random() {
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const pick = (list) => list[Math.floor(random() * list.length)];
const whole = (from, to) => from + Math.floor(random() * (to - from + 1));
/** A place that is sometimes a whole pixel, sometimes a half (which way a half rounds is the point), sometimes neither. */
const place = (from, to) => whole(from, to) + pick([0, 0, 0.5, -0.5, 0.25, 0.49999, 0.7]);

// ---- What is written about a canvas --------------------------------------------------------------------------------

const num = (n) => String(n);
function pathsOf(canvas) {
  const out = {};
  for (const [id, path] of L.edgePaths(canvas)) out[id] = { d: path.d, fromHead: path.fromHead, toHead: path.toHead, mid: [num(path.mid.x), num(path.mid.y)], lines: path.lines };
  return out;
}

// ---- parse ------------------------------------------------------------------------------------------------------

const ODD = 'naïve "quoted" \\ back\tslash\nnew line \u{1f389}     \u0007 \u001f \u007f </script> \ud83d';
const WITH_COMMENTS = `{
  "nodes": [ { "id": "book", "type": "text", "x": 0, "y": 0, "width": 260, "height": 100, "text": "# Book the cabin" } ],
  "edges": [],
  "comments": [
    { "id": "c1", "node": "book", "by": "matt", "at": "2026-10-05T14:00:00Z", "text": "Which Friday?", "replies": [ { "by": "sam", "at": "2026-10-05T14:05:00Z", "text": "The 10th." } ], "resolved": { "by": "sam", "at": "2026-10-05T14:06:00Z" } },
    { "id": "c2", "node": "gone", "by": "lee", "at": "2026-10-05T14:07:00Z", "text": "On a card that is not there", "replies": [] },
    { "id": "c3", "node": "book", "by": "lee", "at": "2026-10-05T14:08:00Z", "text": "Open", "replies": [ { "by": "x" }, 4 ], "resolved": { "by": 1 } },
    { "id": "c1", "node": "book", "by": "twice", "at": "2026-10-05T14:09:00Z", "text": "The same id again", "replies": [] }
  ]
}`;
const PARSE = {
  spec: T.SPEC_SAMPLE,
  view: T.VIEW_SAMPLE,
  comments: WITH_COMMENTS,
  lenient: `{
    "nodes": [
      { "id": "a", "type": "text", "x": 0, "y": 0, "width": 10, "height": 10, "text": "one" },
      { "id": "a", "type": "text", "x": 5, "y": 5, "width": 10, "height": 10, "text": "again" },
      { "id": "b", "type": "text", "x": 0, "y": 0, "width": 10, "height": 10 },
      { "id": "c", "type": "sticker", "x": 0, "y": 0, "width": 10, "height": 10 },
      { "id": "d", "type": "link", "x": "0", "y": 0, "width": 10, "height": 10, "url": "https://x" },
      { "id": "e", "type": "text", "x": 0, "y": 0, "width": 10, "height": 10, "text": "", "color": "9" },
      { "id": "", "type": "text", "x": 0, "y": 0, "width": 10, "height": 10, "text": "no id" },
      { "id": 7, "type": "text", "x": 0, "y": 0, "width": 10, "height": 10, "text": "a number for an id" },
      null, 4, "words", [1]
    ],
    "edges": [
      { "id": "ok", "fromNode": "a", "toNode": "e", "fromSide": "middle" },
      { "id": "gone", "fromNode": "a", "toNode": "zz" },
      { "id": "ok", "fromNode": "e", "toNode": "a" },
      null
    ]
  }`,
  kept: `{ "nodes": [
    { "id": "g", "type": "group", "x": 0, "y": 0, "width": 10, "height": 10, "background": "sky.png", "backgroundStyle": "ratio", "color": "#f80", "label": "Sky", "extra": true },
    { "id": "h", "type": "group", "x": 0, "y": 0, "width": 10, "height": 10, "background": "", "backgroundStyle": "stretch", "label": "" },
    { "id": "f", "type": "file", "x": 0, "y": 0, "width": 10, "height": 10, "file": "Trip.md", "subpath": "^friday" },
    { "id": "f2", "type": "file", "x": 0, "y": 0, "width": 10, "height": 10, "file": "Trip.md", "subpath": "#^friday", "color": "#FF8800" },
    { "id": "e", "type": "file", "x": 0, "y": 0, "width": 10, "height": 10, "file": "" },
    { "id": "u", "type": "link", "x": 0, "y": 0, "width": 10, "height": 10, "url": "" },
    { "id": "c", "type": "text", "x": 0, "y": 0, "width": 10, "height": 10, "text": "hi", "color": "#ff88" }
  ], "edges": [ { "id": "e", "fromNode": "g", "toNode": "f", "fromSide": "top", "toSide": "under", "fromEnd": "arrow", "toEnd": "dot", "label": "", "color": "7" } ] }`,
  numbers: `{ "nodes": [
    { "id": "half", "type": "text", "x": 0.5, "y": -0.5, "width": 2.5, "height": -2.5, "text": "" },
    { "id": "near", "type": "text", "x": 0.49999999999999994, "y": -0.49999999999999994, "width": 1e3, "height": 1.5e2, "text": "" },
    { "id": "zero", "type": "text", "x": -0, "y": -0.2, "width": 0, "height": 0, "text": "" },
    { "id": "big", "type": "text", "x": 1e21, "y": 123456789012345680000, "width": 9007199254740993, "height": 1e300, "text": "" },
    { "id": "inf", "type": "text", "x": 1e999, "y": 0, "width": 1, "height": 1, "text": "" }
  ] }`,
  strings: JSON.stringify({ nodes: [{ id: ODD, type: 'text', x: 0, y: 0, width: 10, height: 10, text: ODD }, { id: 'g', type: 'group', x: 0, y: 0, width: 1, height: 1, label: ODD }], edges: [{ id: 'e', fromNode: ODD, toNode: 'g', label: ODD }] }),
  onlyEdges: '{ "edges": [] }',
  onlyNodes: '{"nodes": []}',
  empty: '{}',
  list: '[1, 2]',
  words: '# A note',
  nothing: '',
  spaced: '  \n {"nodes": [], "edges": []} \n ',
};
const parse = Object.entries(PARSE).map(([name, text]) => {
  const canvas = J.parseCanvas(text);
  return { name, text, out: canvas ? J.serializeCanvas(canvas) : null };
});

// ---- made, notes ---------------------------------------------------------------------------------------------------

const made = {
  sample: J.serializeCanvas(S.sampleCanvas()),
  samplePicture: J.serializeCanvas(S.sampleCanvas('view.jpg')),
  how: J.serializeCanvas(H.howCanvas()),
  sampleBody: S.sampleCanvasBody(),
  samplePictureBody: S.sampleCanvasBody('view.jpg'),
  howBody: H.howCanvasBody(),
  titled: [['Cabin plan: the weekend'], ['He said "go"\nand went'], ['   ']].map(([title]) => ({ title, body: J.canvasNoteBody(title, { nodes: [], edges: [] }) })),
};

const view = J.parseCanvas(T.VIEW_SAMPLE);
const small = J.serializeCanvas({ nodes: [{ id: 'a', type: 'text', x: 0, y: 0, width: 100, height: 50, text: 'hi' }], edges: [] });
const BODIES = [
  `---\ntitle: "Cabin"\ntags: [trip]\n---\n{ "nodes": [] }\n`,
  '{ "nodes": [] }',
  '# Groceries\n\n- milk',
  '---\ntitle: Plans\n---\n# Plans\n\n{ not a canvas }',
  '',
  '---\nA rule, then words\n---\n{ "nodes": [] }',
  '---\ntitle: "Plan"\n\ntags: [trip]\n---\n{ "nodes": [] }',
  `+++\ntitle: "Plan"\n+++\n${small}`,
  `---\ntitle: "Plan"\n${small}`,
  ['---', ...Array.from({ length: 40 }, (_, i) => `key${i}: ${i}`), '---', small].join('\n'),
  ['---', ...Array.from({ length: 37 }, (_, i) => `key${i}: ${i}`), '---', small].join('\n'),
  `---\r\ntitle: "Windows"\r\n---\r\n${small}`,
];
const notes = BODIES.map((body) => ({ body, isCanvas: J.isCanvasBody(body), written: J.withCanvas(body, view) }));

// ---- edits --------------------------------------------------------------------------------------------------------

const LABELS = ['then', 'and then', 'every mark a note can hold', 'the long way round the lake', '  ', '', ODD, 'who brings what'];
const TEXTS = ['', '# Plan\n\n- [ ] One thing', '| a | b |\n| - | - |\n| 1 | 2 |', ODD];
const HANDLES = ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w'];
const stampOf = () => ({ by: pick(['matt', 'sam', 'lee']), at: `2026-10-0${whole(1, 9)}T1${whole(0, 9)}:0${whole(0, 9)}:00Z` });

/** One edit, by name: what the Dart test does too (test/canvas/fixtures_test.dart `apply`). */
function apply(canvas, op) {
  const [name, ...a] = op;
  const node = (id) => canvas.nodes.find((n) => n.id === id);
  const edge = (id) => canvas.edges.find((e) => e.id === id);
  switch (name) {
    case 'text':
      return E.withNode(canvas, E.newTextNode(a[0], a[1], a[2]));
    case 'file':
      return E.withNode(canvas, E.newFileNode(a[0], a[1], a[2], a[3]));
    case 'picture':
      return E.withNode(canvas, E.newPictureNode(a[0], a[1], a[2], a[3]));
    case 'link': {
      const made = E.newLinkNode(a[0], a[1], a[2], a[3]);
      return made ? E.withNode(canvas, made) : canvas;
    }
    case 'place': {
      // CanvasView.tsx `place`: on a dot with the magnet on, and never exactly on a card already there.
      const card = E.newTextNode(a[0], a[1], a[3]);
      const dot = a[2] ? E.atDot(card.x, card.y) : card;
      const at = E.clearSpot(canvas, dot.x, dot.y);
      return E.withNode(canvas, { ...card, x: at.x, y: at.y });
    }
    case 'started': {
      // CanvasView.tsx `addStartedCard`.
      return E.withNode(canvas, { ...E.newTextNode(a[0], a[1], a[3]), text: a[2], height: 180 });
    }
    case 'move':
      return E.movedWithHeld(canvas, node(a[0]), a[1], a[2]);
    case 'resize':
      return E.withNode(canvas, E.resizedBy(node(a[0]), a[1], a[2], a[3], a[4]));
    case 'size':
      return E.withNode(canvas, E.resizedNode(node(a[0]), a[1], a[2]));
    case 'colour':
      return E.withNode(canvas, E.colouredNode(node(a[0]), a[1]));
    case 'name':
      return E.withNode(canvas, E.labelledGroup(node(a[0]), a[1]));
    case 'write':
      return E.withNode(canvas, { ...node(a[0]), text: a[1] });
    case 'edge':
      return E.withEdge(canvas, E.newEdge(a[0], a[1], a[2]));
    case 'label':
      return E.withEdge(canvas, E.labelledEdge(edge(a[0]), a[1]));
    case 'unedge':
      return E.withoutEdge(canvas, a[0]);
    case 'remove':
      return E.withoutNode(canvas, a[0]);
    case 'copy': {
      const copy = E.duplicated(canvas, node(a[0]), a[1]);
      return node(a[0]).type === 'group' ? E.withGroup(canvas, copy) : E.withNode(canvas, copy);
    }
    case 'group':
      return E.withGroup(canvas, E.newGroupNode(a[0] === null ? null : node(a[0]), a[1], a[2], a[3]));
    case 'thread':
      return C.withThread(canvas, a[0], { by: a[1], at: a[2] }, a[3], a[4]) ?? canvas;
    case 'reply':
      return C.withReply(canvas, a[0], { by: a[1], at: a[2] }, a[3]) ?? canvas;
    case 'resolve':
      return C.resolvedThread(canvas, a[0], { by: a[1], at: a[2] }) ?? canvas;
    case 'reopen':
      return C.reopenedThread(canvas, a[0]) ?? canvas;
    case 'unthread':
      return C.withoutThread(canvas, a[0]) ?? canvas;
    default:
      throw new Error(`no edit called ${name}`);
  }
}

let made_ids = 0;
const fresh = (kind) => `${kind}${(made_ids += 1)}`;

/** An edit the canvas can take, chosen by the die. */
function someEdit(canvas) {
  const nodes = canvas.nodes;
  const cards = nodes.filter((n) => n.type !== 'group');
  const groups = nodes.filter((n) => n.type === 'group');
  const words = nodes.filter((n) => n.type === 'text');
  const threads = canvas.comments ?? [];
  const any = () => pick(nodes).id;
  for (;;) {
    const kind = pick(['text', 'file', 'picture', 'link', 'place', 'place', 'started', 'move', 'move', 'move', 'resize', 'resize', 'resize', 'size', 'colour', 'colour', 'name', 'write', 'edge', 'edge', 'edge', 'label', 'label', 'unedge', 'remove', 'copy', 'group', 'thread', 'thread', 'reply', 'resolve', 'reopen', 'unthread']);
    switch (kind) {
      case 'text':
        return ['text', place(-400, 900), place(-300, 700), fresh('t')];
      case 'file':
        return ['file', pick(['Cabin trip', '  ', 'Plans/Cabin', 'A\\B']), place(-400, 900), place(-300, 700), fresh('f')];
      case 'picture':
        return ['picture', 'abc.jpg', place(-400, 900), place(-300, 700), fresh('p')];
      case 'link':
        return ['link', pick(['attack.fm/glyph', 'https://x.y', 'mailto:a@b.c', '   ']), place(-400, 900), place(-300, 700), fresh('l')];
      case 'place':
        return ['place', cards.length && random() < 0.5 ? pick(cards).x : place(-400, 900), cards.length && random() < 0.5 ? pick(cards).y : place(-300, 700), random() < 0.5, fresh('n')];
      case 'started':
        return ['started', place(-400, 900), place(-300, 700), pick([E.CHART_CARD, E.TABLE_CARD]), fresh('s')];
      case 'move':
        if (!nodes.length) continue;
        return ['move', any(), place(-500, 1000), place(-400, 800)];
      case 'resize':
        if (!nodes.length) continue;
        return ['resize', any(), pick(HANDLES), place(-300, 300), place(-300, 300), random() < 0.5];
      case 'size':
        if (!nodes.length) continue;
        return ['size', any(), place(0, 600), place(0, 400)];
      case 'colour':
        if (!nodes.length) continue;
        return ['colour', any(), pick(['1', '2', '3', '4', '5', '6', null, null])];
      case 'name':
        if (!nodes.length) continue;
        return ['name', groups.length && random() < 0.8 ? pick(groups).id : any(), pick(LABELS)];
      case 'write':
        if (!words.length) continue;
        return ['write', pick(words).id, pick(TEXTS)];
      case 'edge':
        if (cards.length < 2) continue;
        return ['edge', pick(cards).id, pick(cards).id, fresh('e')];
      case 'label':
        if (!canvas.edges.length) continue;
        return ['label', pick(canvas.edges).id, pick(LABELS)];
      case 'unedge':
        if (!canvas.edges.length || random() < 0.6) continue;
        return ['unedge', pick(canvas.edges).id];
      case 'remove':
        if (nodes.length < 4 || random() < 0.6) continue;
        return ['remove', any()];
      case 'copy':
        if (!nodes.length) continue;
        return ['copy', any(), fresh('d')];
      case 'group':
        return ['group', cards.length && random() < 0.6 ? pick(cards).id : null, place(-400, 900), place(-300, 700), fresh('g')];
      case 'thread': {
        if (!nodes.length) continue;
        const stamp = stampOf();
        return ['thread', random() < 0.9 ? any() : 'nobody', stamp.by, stamp.at, pick(['  Which Friday?  ', 'And where?', '   ', ODD]), fresh('c')];
      }
      case 'reply': {
        if (!threads.length) continue;
        const stamp = stampOf();
        return ['reply', pick(threads).id, stamp.by, stamp.at, pick(['The 10th.', '  ', 'Fine']) ];
      }
      case 'resolve': {
        if (!threads.length) continue;
        const stamp = stampOf();
        return ['resolve', pick(threads).id, stamp.by, stamp.at];
      }
      case 'reopen':
        if (!threads.length) continue;
        return ['reopen', pick(threads).id];
      case 'unthread':
        if (!threads.length || random() < 0.5) continue;
        return ['unthread', pick(threads).id];
    }
  }
}

const BASES = {
  spec: T.SPEC_SAMPLE,
  view: T.VIEW_SAMPLE,
  comments: WITH_COMMENTS,
  sample: J.serializeCanvas(S.sampleCanvas('view.jpg')),
  how: J.serializeCanvas(H.howCanvas()),
  empty: '{"nodes": []}',
};
const edits = [];
for (const [name, text] of Object.entries(BASES)) {
  for (let run = 0; run < 2; run += 1) {
    let canvas = J.parseCanvas(text);
    const steps = [];
    for (let n = 0; n < 32; n += 1) {
      const op = someEdit(canvas);
      canvas = apply(canvas, op);
      steps.push({ op, out: J.serializeCanvas(canvas), paths: pathsOf(canvas) });
    }
    edits.push({ name: `${name} ${run}`, base: text, steps });
  }
}
// The example canvases as they are made, not as they are read: their fields are in the order the code wrote them.
for (const [name, start] of [['sample made', S.sampleCanvas('view.jpg')], ['how made', H.howCanvas()]]) {
  let canvas = start;
  const steps = [];
  for (let n = 0; n < 32; n += 1) {
    const op = someEdit(canvas);
    canvas = apply(canvas, op);
    steps.push({ op, out: J.serializeCanvas(canvas), paths: pathsOf(canvas) });
  }
  edits.push({ name, made: name.split(' ')[0], steps });
}

// ---- paths --------------------------------------------------------------------------------------------------------

const paths = [];
for (const text of [T.SPEC_SAMPLE, T.VIEW_SAMPLE, made.sample, made.samplePicture, made.how]) paths.push({ text, paths: pathsOf(J.parseCanvas(text)) });
// Cards on a loose grid with gaps of every size, and more lines than sides: ends share sides and heads meet.
for (let n = 0; n < 60; n += 1) {
  const nodes = [];
  const count = whole(3, 9);
  for (let i = 0; i < count; i += 1) {
    const tight = random() < 0.5;
    nodes.push({ id: `n${i}`, type: 'text', text: '', x: whole(0, 4) * (tight ? 340 : 420) + whole(-30, 30), y: whole(0, 3) * (tight ? 240 : 330) + whole(-30, 30), width: pick([300, 260, 120, 200]), height: pick([200, 60, 120, 90]) });
  }
  if (random() < 0.5) nodes.unshift({ id: 'g', type: 'group', x: -40, y: -40, width: whole(300, 1400), height: whole(200, 900), label: 'Group' });
  const edges = [];
  const lines = whole(2, 14);
  const sides = ['top', 'right', 'bottom', 'left'];
  for (let i = 0; i < lines; i += 1) {
    const edge = { id: `e${i}`, fromNode: pick(nodes).id, toNode: pick(nodes).id };
    if (random() < 0.25) edge.fromSide = pick(sides);
    if (random() < 0.25) edge.toSide = pick(sides);
    if (random() < 0.3) edge.fromEnd = pick(['none', 'arrow']);
    if (random() < 0.3) edge.toEnd = pick(['none', 'arrow']);
    if (random() < 0.6) edge.label = pick(LABELS.filter(Boolean).filter((l) => l.trim()));
    edges.push(edge);
  }
  const text = JSON.stringify({ nodes, edges });
  paths.push({ text, paths: pathsOf(J.parseCanvas(text)) });
}

// ---- calls --------------------------------------------------------------------------------------------------------

const calls = [];
const bars = (list) => list.map((b) => [num(b.x), num(b.y), num(b.width), num(b.height), !!b.strong]);
const viewOut = (v) => [num(v.x), num(v.y), num(v.scale)];
const boxOut = (b) => (b ? [num(b.x), num(b.y), num(b.width), num(b.height)] : null);
for (const words of ['every mark a note can hold', 'the long way round the lake', 'one', '  ', 'a  b\tc\nd', ODD]) for (const count of [1, 2, 3]) calls.push(['brokenInto', [words, count], L.brokenInto(words, count)]);
const CARD_TEXTS = [
  '# Plan\n\n- [ ] One thing\n\nA paragraph long enough that it runs on to a second line of the card.',
  '| a | b |\n| --- | --- |\n| 1 | 2 |',
  '```mermaid\nflowchart LR\n```',
  Array.from({ length: 40 }, (_, n) => `line ${n}`).join('\n'),
  'words',
  '1. one\n2) two\n* three\n+ [x] four\n\n\n###### Small\n~~~\ncode\n~~~',
  ...S.sampleCanvas().nodes.filter((n) => n.type === 'text').map((n) => n.text),
];
for (const text of CARD_TEXTS) for (const [w, h] of [[260, 220], [200, 120], [200, 100], [40, 100], [200, 4000], [61.5, 77.25]]) calls.push(['wordBars', [text, w, h], bars(M.wordBars(text, w, h))]);
for (const title of ['Launch week', '', 'A very long title that runs past the card it is on']) for (const [w, h] of [[200, 80], [200, 30], [260, 150], [70, 60], [50, 200]]) calls.push(['noteBars', [title, w, h], bars(M.noteBars(title, w, h))]);
for (const a of [[10, 20, 100, 50, 5], [0, 0, 6, 20, 5], [1.5, -2.25, 33.3, 12.1, 5], [0, 0, 0, 0, 5], [3, 4, 10, 10, 0]]) calls.push(['roundedBox', a, M.roundedBox(...a)]);
for (const text of [T.VIEW_SAMPLE, T.SPEC_SAMPLE, '{"nodes": []}']) {
  const canvas = J.parseCanvas(text);
  calls.push(['bounds', [text], boxOut(G.bounds(canvas))]);
  for (const [w, h] of [[1000, 600], [300, 300], [0, 600], [390, 844], [1280, 800]]) calls.push(['fitted', [text, w, h], viewOut(V.fitted(canvas, w, h))]);
}
for (const a of [[100, 50, 200, 80, 400, 300], [0, 0, 2000, 1000, 400, 300], [5, 5, 10, 10, 400, -1], [0, 0, 1000000, 10, 400, 300], [10, 20, 0, 0, 400, 300]]) calls.push(['fittedTo', a, viewOut(V.fittedTo({ x: a[0], y: a[1], width: a[2], height: a[3] }, a[4], a[5]))]);
for (const a of [[100, 50, 1, 300, 250, 2], [100, 50, 1, 0, 0, 99], [100, 50, 1, 0, 0, 0.001], [32, 32, 1, 122, 62, Math.E], [-13.7, 44.1, 0.37, 201.5, 99.25, 0.37 * 1.3]]) calls.push(['zoomedAt', a, viewOut(V.zoomedAt({ x: a[0], y: a[1], scale: a[2] }, a[3], a[4], a[5]))]);
for (const a of [[-100, -50, 0.5, 400, 300], [32, 32, 1, 390, 844], [-13.7, 44.1, 0.37, 1280, 800]]) calls.push(['shown', a, boxOut(V.shown({ x: a[0], y: a[1], scale: a[2] }, a[3], a[4]))]);
{
  const canvas = J.parseCanvas(T.SPEC_SAMPLE);
  for (const node of canvas.nodes) calls.push(['heldBy', [T.SPEC_SAMPLE, node.id], E.heldBy(canvas, node).map((n) => n.id)]);
  for (const [x, y] of [[400, 400], [0, 0], [0.5, 150.4], [-40, -40], [300, 0], [11.9, -11.9]]) {
    const at = E.clearSpot(canvas, x, y);
    calls.push(['clearSpot', [T.SPEC_SAMPLE, x, y], [num(at.x), num(at.y)]]);
  }
  for (const from of canvas.nodes) for (const to of canvas.nodes) {
    const sides = G.sidesOf(from, to, {});
    calls.push(['sidesOf', [T.SPEC_SAMPLE, from.id, to.id], [sides.from, sides.to]]);
  }
  for (const id of ['t1', 'g1', 'l1', 'f1', 'nobody']) calls.push(['quoteOf', [T.SPEC_SAMPLE, id], C.quoteOf(canvas, id)]);
}
for (const place of [0, 11, 12, -11, -12, -13, 331, 36, -36, 35.99, 12.000001, -12.000001]) calls.push(['onGrid', [place], num(E.onGrid(place))]);

mkdirSync(OUT, { recursive: true });
const written = JSON.stringify({ parse, made, notes, edits, paths, calls });
writeFileSync(`${OUT}canvas.json`, written);
const lines = edits.reduce((sum, run) => sum + run.steps.reduce((s, step) => s + Object.keys(step.paths).length, 0), 0) + paths.reduce((sum, each) => sum + Object.keys(each.paths).length, 0);
console.log(`canvas.json: ${parse.length} parsed, ${notes.length} notes, ${edits.length} runs of ${edits.reduce((sum, run) => sum + run.steps.length, 0)} edits, ${paths.length} laid out, ${lines} lines' paths, ${calls.length} calls, ${(written.length / 1024).toFixed(0)} kB`);
