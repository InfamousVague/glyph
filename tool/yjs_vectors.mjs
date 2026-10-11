#!/usr/bin/env node
// The Yjs fixtures of stage 7 (docs/STAGE7.md, "Live typing and team notes"): documents, updates, state vectors,
// relative positions and awareness made by the WEB app's own `yjs` and `y-protocols` (../glyph/node_modules, the
// versions it ships), for native/src/crdt.rs to read; and those same libraries reading what `yrs` wrote.
//
//   node tool/yjs_vectors.mjs make     writes native/tests/fixtures/yjs_web.json
//   node tool/yjs_vectors.mjs check    opens native/target/vectors/yjs_from_rust.json, which
//                                      `cargo test --test yjs_vectors` writes (tool/build-native.sh test)
//
// ../glyph is only read: its node_modules through `createRequire`, and core/team/textDiff.ts imported as it is, so
// a reconcile here is the web's own `applyTextDiff`. Nothing here touches a network.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const glyph = resolve(root, '../glyph');
const FIXTURE = join(root, 'native/tests/fixtures/yjs_web.json');
const FROM_RUST = join(root, 'native/target/vectors/yjs_from_rust.json');

const require = createRequire(join(glyph, 'package.json'));
const Y = require('yjs');
const { Awareness, applyAwarenessUpdate, encodeAwarenessUpdate } = require('y-protocols/awareness');
const { applyTextDiff } = await import(pathToFileURL(join(glyph, 'src/app/core/team/textDiff.ts')).href);
const version = (name) => JSON.parse(readFileSync(join(glyph, 'node_modules', name, 'package.json'), 'utf8')).version;

const FIELD = 'body';
const b64 = (bytes) => Buffer.from(bytes).toString('base64url');
const unb64 = (text) => new Uint8Array(Buffer.from(text, 'base64url'));
const sorted = (value) =>
  Array.isArray(value) ? value.map(sorted) : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map((key) => [key, sorted(value[key])])) : value;
const same = (a, b) => JSON.stringify(sorted(a)) === JSON.stringify(sorted(b));

/** A document with a client id of the test's choosing, and every update it makes written down. */
function device(client, from = []) {
  const doc = new Y.Doc();
  doc.clientID = client;
  const text = doc.getText(FIELD);
  const made = [];
  for (const update of from) Y.applyUpdate(doc, update, 'remote');
  doc.on('update', (update, origin) => {
    if (origin !== 'remote') made.push(update);
  });
  return { doc, text, made, client };
}
const take = (to, updates) => updates.forEach((update) => Y.applyUpdate(to.doc, update, 'remote'));
const vector = (doc) => Object.fromEntries([...Y.decodeStateVector(Y.encodeStateVector(doc))].map(([client, clock]) => [String(client), clock]));
const vectorOf = (bytes) => Object.fromEntries([...Y.decodeStateVector(bytes)].map(([client, clock]) => [String(client), clock]));

/** A small generator with a seed, so a fixture's shape is the same every time it is made. */
function seeded(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Whether `index` falls between the two halves of a character of `text`. */
const splits = (text, index) => index > 0 && index < text.length && text.charCodeAt(index - 1) >= 0xd800 && text.charCodeAt(index - 1) < 0xdc00;

// ---- make ------------------------------------------------------------------------------------------------

function make() {
  const out = { made: new Date().toISOString(), by: 'tool/yjs_vectors.mjs make, with ../glyph/node_modules', yjs: version('yjs'), protocols: version('y-protocols') };

  // doc.ts `make`: a note's words seeded into a new document, the whole of it one update.
  {
    const a = device(1001);
    const words = '# Weekend trip\n\nBook the cabin.\n- [ ] día ✓ 😀\n';
    a.text.insert(0, words);
    out.seed = { client: 1001, words, update: b64(Y.encodeStateAsUpdate(a.doc)), vector: b64(Y.encodeStateVector(a.doc)), clocks: vector(a.doc) };
  }

  // Two members change one note at the same moment, each by the web's own `applyTextDiff`.
  {
    const a = device(1001);
    a.text.insert(0, 'Plan\n\nFirst we pack.\nThen we drive.\n');
    const base = Y.encodeStateAsUpdate(a.doc);
    const b = device(1002, [base]);
    const c = device(1003, [base]);
    const edit = (who, to) => applyTextDiff(who.text, who.text.toString(), to);
    edit(b, 'Plan\n\nFirst we pack the car.\nThen we drive.\n');
    edit(b, 'Plan for Saturday\n\nFirst we pack the car.\nThen we drive.\n');
    edit(c, 'Plan\n\nFirst we pack.\nThen we drive north.\n- bring 😀\n');
    edit(c, 'Plan\n\nFirst we pack.\nThen we drive north.\n- bring 😀 and ☕\n');
    edit(c, 'Plan\n\nThen we drive north.\n- bring 😀 and ☕\n');
    const afterB = { text: b.text.toString(), vector: b64(Y.encodeStateVector(b.doc)), clocks: vector(b.doc) };
    const afterC = { text: c.text.toString(), vector: b64(Y.encodeStateVector(c.doc)) };
    // What C would send B in answer to B's state vector (live/team.ts, a `Query` answered with a `State`).
    take(c, b.made);
    const diffForB = Y.encodeStateAsUpdate(c.doc, Y.encodeStateVector(b.doc));
    const diffForNobody = Y.encodeStateAsUpdate(c.doc, new Uint8Array([0]));
    take(b, c.made);
    if (b.text.toString() !== c.text.toString()) throw new Error('Yjs itself did not converge');
    out.concurrent = {
      base: b64(base),
      b: { client: 1002, updates: b.made.map(b64), ...afterB },
      c: { client: 1003, updates: c.made.map(b64), ...afterC },
      merged: c.text.toString(),
      diffForB: b64(diffForB),
      diffForNobody: b64(diffForNobody),
      state: b64(Y.encodeStateAsUpdate(c.doc)),
      clocks: vector(c.doc),
    };
  }

  // Updates that arrive before what they build on: held until it comes.
  {
    const a = device(1001);
    a.text.insert(0, 'one');
    a.text.insert(3, ' two');
    a.text.insert(7, ' three');
    a.text.delete(0, 4);
    const order = [3, 1, 2, 0];
    const b = device(1002);
    const texts = order.map((index) => {
      take(b, [a.made[index]]);
      return b.text.toString();
    });
    out.outOfOrder = { updates: a.made.map(b64), order, texts, text: a.text.toString() };
  }

  // The web's diff compares UTF-16 code units, so an emoji swapped for a near one is split, and Yjs writes U+FFFD
  // over the halves. Rust never makes such an update; it has to read one and arrive where Yjs did.
  {
    const a = device(1001);
    a.text.insert(0, 'a😀b');
    const base = Y.encodeStateAsUpdate(a.doc);
    applyTextDiff(a.text, a.text.toString(), 'a😁b');
    // The device that made it holds half a character; every device that hears of it reads U+FFFD there, since the
    // update carries its text as UTF-8. `heard` is what the rest of the team has.
    const heard = device(1002, [base, a.made.at(-1)]).text.toString();
    const units = (text) => Array.from({ length: text.length }, (_, i) => text.charCodeAt(i));
    out.splitCharacter = { base: b64(base), update: b64(a.made.at(-1)), madeUnits: units(a.text.toString()), heard, heardUnits: units(heard) };
  }

  // Three devices typing and deleting at random, hearing each other now and then: every update each made, in the
  // order it was made, and the words all three end with.
  {
    const next = seeded(20261007);
    const pick = (n) => Math.floor(next() * n);
    const chunks = ['a', 'b', ' ', '\n', 'é', '✓', '😀', '日本', 'word ', '- [ ] ', '👩‍👧', '# '];
    const devices = [device(2001), device(2002), device(2003)];
    const heard = devices.map(() => devices.map(() => 0));
    const log = [];
    devices[0].text.insert(0, 'Shared note\n');
    for (let step = 0; step < 240; step += 1) {
      const who = pick(3);
      const one = devices[who];
      const now = one.text.toString();
      const roll = next();
      if (roll < 0.62 || now.length === 0) {
        let at = pick(now.length + 1);
        while (splits(now, at)) at -= 1;
        one.text.insert(at, chunks[pick(chunks.length)]);
      } else if (roll < 0.9) {
        let at = pick(now.length);
        while (splits(now, at)) at -= 1;
        let end = Math.min(now.length, at + 1 + pick(4));
        while (splits(now, end)) end += 1;
        one.text.delete(at, end - at);
      } else {
        // Hears everything one other device has made since it last heard from it.
        const from = (who + 1 + pick(2)) % 3;
        take(one, devices[from].made.slice(heard[who][from]));
        heard[who][from] = devices[from].made.length;
      }
      for (const [index, other] of devices.entries()) {
        while ((other.logged ?? 0) < other.made.length) {
          log.push({ client: other.client, update: b64(other.made[other.logged ?? 0]) });
          other.logged = (other.logged ?? 0) + 1;
        }
        void index;
      }
    }
    for (const one of devices) for (const other of devices) if (one !== other) take(one, other.made);
    const texts = devices.map((one) => one.text.toString());
    if (new Set(texts).size !== 1) throw new Error('Yjs itself did not converge');
    out.random = { updates: log, text: texts[0], state: b64(Y.encodeStateAsUpdate(devices[0].doc)), clocks: vector(devices[0].doc), length: texts[0].length };
  }

  // Relative positions (a caret that stays with its character), as presence carries them.
  {
    const a = device(3001);
    a.text.insert(0, 'hello world');
    const b = device(3002, a.made);
    b.text.insert(5, ', 😀 dear');
    take(a, b.made);
    a.text.delete(0, 2);
    a.text.insert(a.text.length, '!');
    const state = Y.encodeStateAsUpdate(a.doc);
    const text = a.text.toString();
    const at = [];
    for (let index = 0; index <= text.length; index += 1) {
      if (splits(text, index)) continue;
      for (const assoc of [0, -1, 1]) at.push({ index, assoc, json: Y.relativePositionToJSON(Y.createRelativePositionFromTypeIndex(a.text, index, assoc)) });
    }
    // The words move under the carets: typed before, typed after, and some of what they sat in deleted.
    const made = a.made.length;
    a.text.insert(0, '>> ');
    a.text.delete(6, 5);
    a.text.insert(a.text.length, ' <<');
    const after = at.map(({ json }) => {
      const absolute = Y.createAbsolutePositionFromRelativePosition(Y.createRelativePositionFromJSON(json), a.doc);
      return absolute && absolute.type === a.text ? absolute.index : null;
    });
    // A caret in something this copy has not been given, and one in another field.
    const stranger = { tname: FIELD, item: { client: 9999, clock: 4 }, assoc: 0 };
    const elsewhere = Y.relativePositionToJSON(Y.createRelativePositionFromTypeIndex(a.doc.getText('title'), 0));
    out.positions = { state: b64(state), text, at, then: a.made.slice(made).map(b64), textAfter: a.text.toString(), after, stranger, elsewhere };
  }

  // Awareness: who a device is and where its caret is (live/team.ts sets `user`, y-codemirror `cursor`,
  // presence.ts `at`), as one device says it and another hears it.
  {
    const a = new Awareness(new Y.Doc());
    a.doc.clientID = 4001;
    a.clientID = 4001;
    a.states.clear();
    a.meta.clear();
    a.setLocalState({});
    const other = new Awareness(new Y.Doc());
    other.doc.clientID = 4002;
    other.clientID = 4002;
    other.states.clear();
    other.meta.clear();
    other.setLocalState({});
    const hearer = new Awareness(new Y.Doc());
    hearer.doc.clientID = 4999;
    hearer.clientID = 4999;
    hearer.states.clear();
    hearer.meta.clear();
    hearer.setLocalState({});
    let last = null;
    hearer.on('change', (change) => (last = change));
    const steps = [];
    const said = (label, update) => {
      last = null;
      applyAwarenessUpdate(hearer, update, 'remote');
      steps.push({
        label,
        update: b64(update),
        change: last ?? { added: [], updated: [], removed: [] },
        states: Object.fromEntries([...hearer.getStates()].filter(([client]) => client !== hearer.clientID).map(([client, state]) => [String(client), state])),
        clocks: Object.fromEntries([...hearer.meta].filter(([client]) => client !== hearer.clientID).map(([client, meta]) => [String(client), meta.clock])),
      });
    };
    const mine = () => encodeAwarenessUpdate(a, [a.clientID]);
    said('a device that has said nothing yet is not news', mine());
    a.setLocalStateField('user', { name: 'matt', hue: 'moss', color: 'oklch(var(--app-hue-lift) var(--app-hue-chroma) 150)', colorLight: 'oklch(var(--app-hue-lift) var(--app-hue-chroma) 150 / 0.24)' });
    said('who it is', mine());
    const caret = { anchor: { tname: FIELD, item: { client: 3001, clock: 6 }, assoc: 0 }, head: { tname: FIELD, assoc: 0 } };
    a.setLocalStateField('cursor', caret);
    said('where its caret is', mine());
    said('the same again is old news', mine());
    a.setLocalStateField('at', { note: 'n1', title: 'Roadmap día ✓ 😀', kind: 'note', cursor: caret, pointer: null });
    said('where it is in the organization', mine());
    a.setLocalStateField('at', { note: 'c1', title: 'Board', kind: 'canvas', cursor: null, pointer: { x: 120.5, y: -40 } });
    other.setLocalStateField('user', { name: 'sam', hue: null, color: 'var(--app-ink)', colorLight: 'color-mix(in oklch, var(--app-ink) 20%, transparent)' });
    applyAwarenessUpdate(a, encodeAwarenessUpdate(other, [other.clientID]), 'remote');
    said('two devices in one update', encodeAwarenessUpdate(a, [a.clientID, other.clientID]));
    a.setLocalState(a.getLocalState());
    said('said again unchanged: no change, a later clock', mine());
    a.setLocalState(null);
    said('leaving', mine());
    out.awareness = { hearer: 4999, steps };
    for (const one of [a, other, hearer]) one.destroy();
  }

  // What a team's canvas keeps beside the words (core/team/canvas.ts): maps, arrays and texts inside maps. The
  // phone does not draw one yet, but it holds the document, so what it sends on must still have them.
  {
    const a = device(5001);
    a.text.insert(0, '---\ntitle: Board\n---\n');
    const nodes = a.doc.getMap('canvas-nodes');
    const card = new Y.Map();
    nodes.set('card-1', card);
    card.set('type', 'text');
    card.set('x', 120.5);
    card.set('y', -40);
    card.set('width', 260);
    const words = new Y.Text();
    card.set('text', words);
    words.insert(0, 'A card día ✓ 😀');
    const order = a.doc.getArray('canvas-order');
    order.push(['card-1', 'card-2']);
    const comments = a.doc.getMap('canvas-comments');
    const thread = new Y.Map();
    comments.set('t1', thread);
    const replies = new Y.Array();
    thread.set('replies', replies);
    replies.push([{ by: 'sam', text: 'yes', at: 1759000000000 }]);
    a.doc.getMap('canvas-meta').set('seeded', true);
    order.delete(1, 1);
    out.canvas = {
      state: b64(Y.encodeStateAsUpdate(a.doc)),
      text: a.text.toString(),
      roots: { 'canvas-nodes': nodes.toJSON(), 'canvas-order': order.toJSON(), 'canvas-comments': comments.toJSON(), 'canvas-meta': a.doc.getMap('canvas-meta').toJSON() },
    };
  }

  mkdirSync(dirname(FIXTURE), { recursive: true });
  writeFileSync(FIXTURE, `${JSON.stringify(out, null, 1)}\n`);
  const count = 1 + (out.concurrent.b.updates.length + out.concurrent.c.updates.length + 3) + out.outOfOrder.updates.length + 1 + out.random.updates.length + out.positions.at.length * 2 + 2 + out.awareness.steps.length + 1;
  console.log(`yjs_vectors: ${FIXTURE}\n  ${count} vectors from yjs ${out.yjs} and y-protocols ${out.protocols}`);
}

// ---- check: what yrs wrote, read by Yjs --------------------------------------------------------------------

function check() {
  const web = JSON.parse(readFileSync(FIXTURE, 'utf8'));
  let rust;
  try {
    rust = JSON.parse(readFileSync(FROM_RUST, 'utf8'));
  } catch {
    console.error(`yjs_vectors: ${FROM_RUST} is not there. Run tool/build-native.sh test first: the Rust tests write it.`);
    process.exit(1);
  }
  if (rust.fixture !== web.made) {
    console.error('yjs_vectors: what Rust wrote was made from another fixture. Run tool/build-native.sh test again.');
    process.exit(1);
  }
  let passed = 0;
  const failures = [];
  const hold = (name, body) => {
    try {
      const said = body();
      if (said !== true) throw new Error(typeof said === 'string' ? said : 'not what Rust said');
      passed += 1;
    } catch (failure) {
      failures.push(`${name}: ${failure?.message ?? failure}`);
    }
  };
  const fresh = (...updates) => device(7000 + Math.floor(Math.random() * 1000), updates.map(unb64));
  const differs = (got, want) => (got === want ? true : `Yjs reads ${JSON.stringify(got)}, Rust said ${JSON.stringify(want)}`);

  // A document seeded in Rust.
  hold('seeded: the whole document', () => differs(fresh(rust.seeded.state).text.toString(), rust.seeded.text));
  hold('seeded: its pending update is the whole of it', () => differs(fresh(rust.seeded.pending).text.toString(), rust.seeded.text));
  hold('seeded: its state vector', () => same(vectorOf(unb64(rust.seeded.vector)), vector(fresh(rust.seeded.state).doc)));

  // Each change Rust made, as an update, in order; and all of them backwards.
  {
    const one = fresh(rust.seeded.state);
    for (const [i, step] of rust.steps.entries()) {
      take(one, [unb64(step.update)]);
      hold(`step ${i}: ${step.label}`, () => differs(one.text.toString(), step.text));
    }
    const backwards = fresh(...[...rust.steps].reverse().map((step) => step.update), rust.seeded.state);
    hold('steps: backwards', () => differs(backwards.text.toString(), rust.steps.at(-1).text));
    hold('steps: the snapshot after them', () => differs(fresh(rust.stepsState).text.toString(), rust.steps.at(-1).text));
  }

  // Rust as a third member of the web's concurrent edit.
  {
    const all = [web.concurrent.base, ...web.concurrent.b.updates, ...web.concurrent.c.updates];
    const one = fresh(...all, ...rust.merge.updates);
    hold('merge: Yjs with Rust\'s changes reads what Rust reads', () => differs(one.text.toString(), rust.merge.text));
    hold('merge: Rust\'s whole state alone', () => differs(fresh(rust.merge.state).text.toString(), rust.merge.text));
    hold('merge: state vectors agree', () => same(vectorOf(unb64(rust.merge.vector)), vector(one.doc)));
    // What Rust answers a device that has only B's changes.
    const b = fresh(web.concurrent.base, ...web.concurrent.b.updates);
    take(b, [unb64(rust.merge.diffForB)]);
    hold('merge: the difference for a state vector', () => differs(b.text.toString(), rust.merge.text));
    hold('merge: the difference is smaller than the whole', () => unb64(rust.merge.diffForB).length < unb64(rust.merge.state).length);
    // And what Yjs answers Rust's state vector brings nothing new.
    const diff = Y.encodeStateAsUpdate(one.doc, unb64(rust.merge.vector));
    hold('merge: Yjs has nothing Rust lacks', () => Y.decodeUpdate(diff).structs.length === 0);
  }

  // The random run, re-encoded by Rust.
  hold('random: Rust\'s snapshot of 240 steps', () => differs(fresh(rust.random.state).text.toString(), web.random.text));
  hold('random: its state vector', () => same(vectorOf(unb64(rust.random.vector)), web.random.clocks));

  // Relative positions made by Rust, placed by Yjs.
  {
    const one = fresh(rust.positions.state);
    for (const at of rust.positions.at) {
      hold(`position ${at.index} assoc ${at.assoc}: Yjs places it`, () => {
        const absolute = Y.createAbsolutePositionFromRelativePosition(Y.createRelativePositionFromJSON(at.json), one.doc);
        return absolute && absolute.type === one.text ? differs(absolute.index, at.index) : 'Yjs cannot place it';
      });
      hold(`position ${at.index} assoc ${at.assoc}: Yjs writes the same`, () => same(Y.relativePositionToJSON(Y.createRelativePositionFromTypeIndex(one.text, at.index, at.assoc)), at.json));
    }
  }

  // Awareness made by Rust.
  {
    const hearer = new Awareness(new Y.Doc());
    for (const [i, step] of rust.awareness.entries()) {
      applyAwarenessUpdate(hearer, unb64(step.update), 'remote');
      const states = Object.fromEntries([...hearer.getStates()].filter(([client]) => client !== hearer.clientID).map(([client, state]) => [String(client), state]));
      hold(`awareness ${i}: ${step.label}`, () => (same(states, step.states) ? true : `Yjs holds ${JSON.stringify(states)}, Rust said ${JSON.stringify(step.states)}`));
    }
    hearer.destroy();
  }

  // The canvas's types, through Rust and back.
  {
    const one = fresh(rust.canvas.state);
    const roots = { 'canvas-nodes': one.doc.getMap('canvas-nodes').toJSON(), 'canvas-order': one.doc.getArray('canvas-order').toJSON(), 'canvas-comments': one.doc.getMap('canvas-comments').toJSON(), 'canvas-meta': one.doc.getMap('canvas-meta').toJSON() };
    hold('canvas: maps, arrays and nested texts survive Rust', () => (same(roots, web.canvas.roots) ? true : `Yjs reads ${JSON.stringify(roots)}`));
    hold('canvas: with the words Rust changed', () => differs(one.text.toString(), rust.canvas.text));
    const card = one.doc.getMap('canvas-nodes').get('card-1');
    hold('canvas: a nested text is still a text', () => card?.get('text') instanceof Y.Text);
  }

  // A canvas written by Rust into the types core/team/canvas.ts keeps: read by Yjs as that file reads them (the
  // nodes in their order, a card's words a text, the replies an array), from the whole state and from the update.
  {
    const read = (doc) => {
      const nodes = doc.getMap('canvas-nodes');
      const plain = (fields) => Object.fromEntries([...fields.entries()].map(([key, value]) => [key, value instanceof Y.Text ? value.toString() : value instanceof Y.Array ? value.toArray() : value]));
      const sorted = (map) => [...map.keys()].sort().map((id) => ({ id, ...plain(map.get(id)) }));
      return { nodes: doc.getArray('canvas-order').toArray().map((id) => ({ id, ...plain(nodes.get(id)) })), edges: sorted(doc.getMap('canvas-edges')), comments: sorted(doc.getMap('canvas-comments')) };
    };
    const canon = (canvas) => JSON.parse(JSON.stringify(canvas, (_key, value) => (value && typeof value === 'object' && !Array.isArray(value) ? Object.fromEntries(Object.keys(value).sort().map((key) => [key, value[key]])) : value)));
    const whole = fresh(rust.canvasTypes.state);
    hold('canvas types: the canvas Rust wrote, whole', () => (same(canon(read(whole.doc)), canon(rust.canvasTypes.canvas)) ? true : `Yjs reads ${JSON.stringify(read(whole.doc))}`));
    const followed = fresh(web.canvas.state, rust.canvasTypes.update);
    hold('canvas types: a web member follows from the update alone', () => (same(canon(read(followed.doc)), canon(rust.canvasTypes.canvas)) ? true : `Yjs reads ${JSON.stringify(read(followed.doc))}`));
    hold('canvas types: a card Rust made has its words as a text', () => whole.doc.getMap('canvas-nodes').get('card-2')?.get('text') instanceof Y.Text);
    hold('canvas types: the replies are still the array the web made, added to', () => whole.doc.getMap('canvas-comments').get('t1')?.get('replies') instanceof Y.Array && whole.doc.getMap('canvas-comments').get('t1').get('replies').length === 2);
    hold('canvas types: still seeded', () => Boolean(whole.doc.getMap('canvas-meta').get('seeded')));
  }

  // The character the web's diff cut through: Rust's copy after it, and what Rust typed there, read by Yjs.
  {
    hold('split: the document Rust holds after the cut', () => differs(fresh(rust.split.state).text.toString(), rust.split.text));
    const heard = fresh(web.splitCharacter.base, web.splitCharacter.update);
    hold('split: a web member that heard the cut reads what Rust typed after it', () => {
      Y.applyUpdate(heard.doc, unb64(rust.split.update), 'remote');
      return differs(heard.text.toString(), rust.split.text);
    });
  }

  for (const failure of failures) console.error(`  FAILED ${failure}`);
  console.log(`yjs_vectors: yjs ${version('yjs')} read ${passed} of ${passed + failures.length} things yrs wrote`);
  process.exit(failures.length ? 1 : 0);
}

const mode = process.argv[2];
if (mode === 'make') make();
else if (mode === 'check') check();
else {
  console.error('usage: node tool/yjs_vectors.mjs make|check');
  process.exit(2);
}
