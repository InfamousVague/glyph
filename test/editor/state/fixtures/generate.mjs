// Writes the fixtures the state tests hold the Dart port to: inputs run through the real CodeMirror
// (@codemirror/state, @codemirror/commands and @codemirror/view from tauri/node_modules, read only) and what it
// answered. Seeded, so running it again writes the same files:
//
//   node test/editor/state/fixtures/generate.mjs
//
// The Dart tests (test/editor/state/*_fixture_test.dart) replay every input and expect the same answers.
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const modules = process.env.GLYPH_NODE_MODULES ?? join(here, '../../../../tauri/node_modules');
const load = (name) => import(pathToFileURL(join(modules, name, 'dist/index.js')).href);

const S = await load('@codemirror/state');
const C = await load('@codemirror/commands');
const V = await load('@codemirror/view');
const {
  Text, ChangeSet, ChangeDesc, MapMode, EditorSelection, EditorState, Facet, StateField, StateEffect, Compartment, Prec,
  RangeSet, RangeSetBuilder, RangeValue, Transaction, findClusterBreak, countColumn, findColumn, codePointAt,
} = S;

function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const int = (r, n) => Math.floor(r() * n);
const pick = (r, list) => list[int(r, list.length)];
const ALPHABET = ['a', 'b', 'c', 'd', 'e', ' ', ' ', 'x', 'é', '#', '[', ']', '*', '😀', '\t'];
const word = (r, max) => Array.from({ length: int(r, max + 1) }, () => pick(r, ALPHABET)).join('');
const lines = (r, count, max) => Array.from({ length: count }, () => word(r, max));
const save = (name, data) => {
  const text = JSON.stringify(data);
  writeFileSync(join(here, name), text + '\n');
  console.log(name, (text.length / 1024).toFixed(0) + ' kB');
};

function checksum(s) {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (Math.imul(h, 31) + s.charCodeAt(i)) & 0x7fffffff;
  return h;
}
const lineJson = (l) => [l.from, l.to, l.number, l.text];
const drain = (iter) => {
  const out = [];
  for (iter.next(); !iter.done; iter.next()) out.push(iter.value);
  return out;
};

// ---------------------------------------------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------------------------------------------
{
  const r = rng(1);
  const cases = [];
  for (const count of [1, 1, 2, 3, 5, 8, 31, 32, 33, 64, 65, 100, 200, 400, 1100]) {
    const src = lines(r, count, count > 100 ? 12 : 20);
    const doc = Text.of(src);
    const ops = [];
    for (let i = 0; i < 12; i++) {
      const pos = int(r, doc.length + 1);
      ops.push({ k: 'lineAt', pos, r: lineJson(doc.lineAt(pos)) });
      const n = 1 + int(r, doc.lines);
      ops.push({ k: 'line', n, r: lineJson(doc.line(n)) });
      const from = int(r, doc.length + 1), to = from + int(r, Math.min(80, doc.length - from) + 1);
      ops.push({ k: 'slice', from, to, r: doc.sliceString(from, to), sep: doc.sliceString(from, to, '\r\n'), sub: doc.slice(from, to).toJSON() });
      const ins = lines(r, 1 + int(r, pick(r, [1, 2, 3, 40, 80])), 6);
      const replaced = doc.replace(from, to, Text.of(ins));
      ops.push({ k: 'replace', from, to, ins, lines: replaced.lines, length: replaced.length, sum: checksum(replaced.toString()), eq: replaced.eq(doc) });
      const a = int(r, doc.length + 1), b = int(r, doc.length + 1);
      ops.push({ k: 'iterRange', from: a, to: b, r: drain(doc.iterRange(a, b)) });
      const l1 = 1 + int(r, doc.lines), l2 = l1 + int(r, doc.lines - l1 + 2);
      ops.push({ k: 'iterLines', from: l1, to: l2, r: drain(doc.iterLines(l1, l2)) });
    }
    ops.push({ k: 'iter', dir: 1, r: count <= 100 ? drain(doc.iter()) : null, sum: checksum(drain(doc.iter()).join('')) });
    ops.push({ k: 'iter', dir: -1, r: count <= 100 ? drain(doc.iter(-1)) : null, sum: checksum(drain(doc.iter(-1)).join('')) });
    ops.push({ k: 'iterLines', from: null, to: null, r: count <= 100 ? drain(doc.iterLines()) : null, sum: checksum(drain(doc.iterLines()).join('|')) });
    cases.push({ lines: src, length: doc.length, ops });
  }
  // One long run of edits on a big document: the tree rebalancing as it goes.
  const src = lines(r, 5000, 30);
  let doc = Text.of(src);
  const edits = [];
  for (let i = 0; i < 400; i++) {
    const from = int(r, doc.length + 1), to = Math.min(doc.length, from + pick(r, [0, 0, 1, 5, 200, 4000]));
    const ins = lines(r, pick(r, [1, 1, 1, 2, 10, 120]), 10);
    doc = doc.replace(from, to, Text.of(ins));
    const pos = int(r, doc.length + 1);
    edits.push({ from, to, ins, lines: doc.lines, length: doc.length, sum: i % 20 === 19 ? checksum(doc.toString()) : null, pos, at: lineJson(doc.lineAt(pos)) });
  }
  save('text.json', { cases, big: { lines: src, edits } });
}

// ---------------------------------------------------------------------------------------------------------------
// Changes
// ---------------------------------------------------------------------------------------------------------------
const specs = (r, length, max = 4) =>
  Array.from({ length: int(r, max + 1) }, () => {
    const from = int(r, length + 1), to = Math.min(length, from + pick(r, [0, 0, 1, 2, 5]));
    const insert = pick(r, ['', '', 'x', 'yz', 'one\ntwo', '😀', '\n']);
    return insert ? { from, to, insert } : { from, to };
  });
const sortedSpecs = (r, length, max = 4) => {
  const out = [];
  let pos = 0;
  for (let i = int(r, max + 1); i > 0 && pos <= length; i--) {
    const from = pos + int(r, Math.max(1, Math.min(8, length - pos + 1))), to = Math.min(length, from + pick(r, [0, 0, 1, 2, 5]));
    if (from > length) break;
    const insert = pick(r, ['', 'x', 'yz', 'one\ntwo', '\n']);
    if (from === to && !insert) continue;
    out.push(insert ? { from, to, insert } : { from, to });
    pos = to + 1;
  }
  return out;
};
const changedRanges = (set, individual) => {
  const out = [];
  set.iterChangedRanges((a, b, c, d) => out.push([a, b, c, d]), individual);
  return out;
};
{
  const r = rng(2);
  const cases = [];
  for (let n = 0; n < 220; n++) {
    const text = lines(r, 1 + int(r, 4), 9).join('\n');
    const doc = Text.of(text.split('\n'));
    const a = specs(r, doc.length), b = specs(r, doc.length);
    const A = ChangeSet.of(a, doc.length), B = ChangeSet.of(b, doc.length);
    const after = A.apply(doc);
    const c = specs(r, after.length);
    const Cs = ChangeSet.of(c, after.length);
    const mapPos = [];
    for (let pos = 0; pos <= doc.length; pos++)
      for (const assoc of [-1, 1]) mapPos.push([MapMode.Simple, MapMode.TrackDel, MapMode.TrackBefore, MapMode.TrackAfter].map((m) => A.mapPos(pos, assoc, m)));
    const touches = [];
    for (let i = 0; i < 8; i++) {
      const from = int(r, doc.length + 1), to = from + int(r, doc.length - from + 1);
      const t = A.touchesRange(from, to);
      touches.push([from, to, t === 'cover' ? 2 : t ? 1 : 0]);
    }
    const iter = [];
    A.iterChanges((fa, ta, fb, tb, ins) => iter.push([fa, ta, fb, tb, ins.toString()]));
    const iterInd = [];
    A.iterChanges((fa, ta, fb, tb, ins) => iterInd.push([fa, ta, fb, tb, ins.toString()]), true);
    const gaps = [];
    A.iterGaps((pa, pb, len) => gaps.push([pa, pb, len]));
    const ranges = [];
    for (let pos = 0, i = int(r, 3); i > 0; i--) {
      const from = pos + int(r, 4), to = from + int(r, 5);
      if (to > doc.length) break;
      ranges.push(from, to);
      pos = to + 1;
    }
    const filtered = A.filter(ranges);
    cases.push({
      doc: text, a, b, c,
      r: {
        json: A.toJSON(), desc: A.desc.toString(), length: A.length, newLength: A.newLength, empty: A.empty,
        applied: after.toString(), inverted: A.invert(doc).toJSON(), invertedDesc: A.invertedDesc.toString(),
        mapPos, touches, iter, iterInd, gaps,
        ranges: changedRanges(A, false), rangesInd: changedRanges(A, true),
        aMapB: A.map(B).toJSON(), aMapBBefore: A.map(B, true).toJSON(),
        bMapA: B.map(A).toJSON(), bMapABefore: B.map(A, true).toJSON(),
        aMapDescB: A.desc.mapDesc(B.desc).toString(), aMapDescBBefore: A.desc.mapDesc(B.desc, true).toString(),
        compose: A.compose(Cs).toJSON(), composeDesc: A.desc.composeDesc(Cs.desc).toString(),
        composed: A.compose(Cs).apply(doc).toString(),
        filterRanges: ranges, filterChanges: filtered.changes.toJSON(), filterFiltered: filtered.filtered.toString(),
      },
    });
  }
  save('changes.json', { cases });
}

// ---------------------------------------------------------------------------------------------------------------
// Selection
// ---------------------------------------------------------------------------------------------------------------
const rangeJson = (x) => ({ from: x.from, to: x.to, anchor: x.anchor, head: x.head, empty: x.empty, assoc: x.assoc, bidi: x.bidiLevel ?? null, goal: x.goalColumn ?? null });
const selJson = (s) => ({ ranges: s.ranges.map(rangeJson), main: s.mainIndex });
{
  const r = rng(3);
  const cases = [];
  for (let n = 0; n < 160; n++) {
    const length = 30;
    const pairs = Array.from({ length: 1 + int(r, 5) }, () => {
      const anchor = int(r, length + 1);
      return [anchor, pick(r, [anchor, anchor, int(r, length + 1)])];
    });
    const main = int(r, pairs.length);
    const sel = EditorSelection.create(pairs.map(([a, h]) => EditorSelection.range(a, h)), main);
    const change = specs(r, length);
    const set = ChangeSet.of(change, length);
    const extra = [int(r, length + 1), int(r, length + 1)];
    const ext = [int(r, length + 1), int(r, 6)];
    cases.push({
      pairs, main, change, extra, ext,
      r: {
        sel: selJson(sel), single: selJson(sel.asSingle()), json: sel.toJSON(),
        mapped: selJson(sel.map(set)), mappedAfter: selJson(sel.map(set, 1)),
        added: selJson(sel.addRange(EditorSelection.range(extra[0], extra[1]))), addedNotMain: selJson(sel.addRange(EditorSelection.range(extra[0], extra[1]), false)),
        replaced: selJson(sel.replaceRange(EditorSelection.range(extra[0], extra[1]))),
        extended: rangeJson(sel.main.extend(ext[0], ext[0] + ext[1])),
        eqSingle: sel.eq(sel.asSingle()),
      },
    });
  }
  const flags = [];
  for (const [anchor, head] of [[3, 3], [3, 7], [7, 3], [0, 0]])
    for (const goal of [undefined, 4])
      for (const bidi of [undefined, 0, 1, 9])
        for (const assoc of [undefined, -1, 0, 1]) {
          flags.push({ k: 'range', anchor, head, goal: goal ?? null, bidi: bidi ?? null, assoc: assoc ?? null, r: rangeJson(EditorSelection.range(anchor, head, goal, bidi, assoc)) });
          if (anchor === head) flags.push({ k: 'cursor', anchor, head, goal: goal ?? null, bidi: bidi ?? null, assoc: assoc ?? null, r: rangeJson(EditorSelection.cursor(anchor, assoc ?? 0, bidi, goal)) });
        }
  save('selection.json', { cases, flags });
}

// ---------------------------------------------------------------------------------------------------------------
// State: characters, words, changeByRange, several specs, phrases, and configurations
// ---------------------------------------------------------------------------------------------------------------
{
  const r = rng(4);
  const strings = ['', 'hello world', 'a😀b', 'été', '👨‍👩‍👧 fam', '🇳🇱🇩🇪x', '\ud83d', 'a‍b', 'tab\there', 'naïve café_1 x-y', '日本語 text', 'ß und ǅ', '  two  spaces ', '#tag [3/8] *b*'];
  const clusters = strings.map((s) => ({
    s,
    fwd: Array.from({ length: s.length + 1 }, (_, i) => findClusterBreak(s, i)),
    back: Array.from({ length: s.length + 1 }, (_, i) => findClusterBreak(s, i, false)),
    fwdNoExt: Array.from({ length: s.length + 1 }, (_, i) => findClusterBreak(s, i, true, false)),
    backNoExt: Array.from({ length: s.length + 1 }, (_, i) => findClusterBreak(s, i, false, false)),
    points: Array.from({ length: s.length }, (_, i) => codePointAt(s, i)),
    column: Array.from({ length: s.length + 1 }, (_, i) => countColumn(s, 4, i)),
    find: Array.from({ length: s.length + 4 }, (_, i) => [findColumn(s, i, 4), findColumn(s, i, 4, true)]),
  }));
  const words = strings.map((s) => {
    const state = EditorState.create({ doc: 'first\n' + s + '\nlast' });
    return { s, r: Array.from({ length: s.length + 1 }, (_, i) => { const w = state.wordAt(6 + i); return w ? [w.from, w.to] : null; }) };
  });

  const byRange = [];
  for (let n = 0; n < 120; n++) {
    const doc = lines(r, 1 + int(r, 3), 14).join('\n');
    const pairs = Array.from({ length: 1 + int(r, 4) }, () => {
      const anchor = int(r, doc.length + 1);
      return [anchor, pick(r, [anchor, int(r, doc.length + 1)])];
    });
    const main = int(r, pairs.length);
    const kind = pick(r, ['wrap', 'replace', 'backspace', 'effect']);
    const arg = pick(r, ['**', '~', 'new\nline', 'Z']);
    const mark = StateEffect.define({ map: (v, m) => m.mapPos(v, 1) });
    const state = EditorState.create({
      doc,
      selection: EditorSelection.create(pairs.map(([a, h]) => EditorSelection.range(a, h)), main),
      extensions: EditorState.allowMultipleSelections.of(true),
    });
    const spec =
      kind === 'replace'
        ? state.replaceSelection(arg)
        : state.changeByRange((range) => {
            if (kind === 'wrap') return { changes: [{ from: range.from, insert: arg }, { from: range.to, insert: arg }], range: EditorSelection.range(range.anchor + arg.length, range.head + arg.length) };
            if (kind === 'backspace') {
              const from = range.empty ? Math.max(0, range.from - 1) : range.from;
              return { changes: { from, to: range.to }, range: EditorSelection.cursor(from) };
            }
            return { changes: { from: range.from, insert: arg }, range: EditorSelection.cursor(range.from), effects: mark.of(range.to) };
          });
    const tr = state.update(spec);
    byRange.push({
      doc, pairs, main, kind, arg,
      r: { changes: spec.changes.toJSON(), sel: selJson(spec.selection), doc: tr.newDoc.toString(), stateSel: selJson(tr.state.selection), effects: (spec.effects ?? []).map((e) => e.value) },
    });
  }

  const multi = [];
  for (let n = 0; n < 120; n++) {
    const doc = lines(r, 1 + int(r, 3), 14).join('\n');
    const state = EditorState.create({ doc });
    const out = [];
    let length = doc.length;
    for (let i = 0, count = 1 + int(r, 3); i < count; i++) {
      const sequential = i > 0 && r() < 0.5;
      const base = sequential ? length : doc.length;
      const changes = specs(r, base, 2);
      const after = ChangeSet.of(changes, base).newLength;
      const selection = r() < 0.4 ? { anchor: int(r, after + 1), head: int(r, after + 1) } : null;
      // A selection is in the document after its own spec's changes; a later non-sequential spec may shorten that
      // document under it, which CodeMirror maps. Kept as generated.
      const spec = { changes, sequential, scroll: r() < 0.2, userEvent: r() < 0.3 ? pick(r, ['input.type', 'delete']) : null };
      if (selection) spec.selection = selection;
      out.push(spec);
      length = sequential ? after : Math.max(0, length + (after - doc.length));
      // The running length is only used to make valid sequential specs: recompute it from the real merge.
      const sofar = state.update(...out.map((s) => ({ changes: s.changes, sequential: s.sequential })));
      length = sofar.changes.newLength;
    }
    let tr;
    try {
      tr = state.update(...out.map((s) => ({ changes: s.changes, sequential: s.sequential, selection: s.selection, scrollIntoView: s.scroll, userEvent: s.userEvent ?? undefined })));
    } catch (e) {
      multi.push({ doc, specs: out, r: null });
      continue;
    }
    multi.push({
      doc, specs: out,
      r: { changes: tr.changes.toJSON(), sel: tr.selection ? selJson(tr.selection) : null, doc: tr.newDoc.toString(), newSel: selJson(tr.newSelection), scroll: tr.scrollIntoView, userEvent: tr.annotation(Transaction.userEvent) ?? null, isType: tr.isUserEvent('input.type'), isInput: tr.isUserEvent('input'), isDelete: tr.isUserEvent('delete') },
    });
  }

  const phraseState = EditorState.create({ extensions: [EditorState.phrases.of({ Hello: 'Bonjour', 'Go to $': 'Aller à $', 'from $1 to $2': 'de $1 à $2' }), EditorState.phrases.of({ Hello: 'Hallo', Bye: 'Tschüss' })] });
  const phrases = [['Hello'], ['Bye'], ['Missing'], ['Go to $', 'x'], ['from $1 to $2', 3, 9], ['cost $$ $', 5], ['$3 only', 'a'], ['plain $', 'a', 'b'], ['$2 $1', 'a', 'b']].map((args) => ({ args, r: phraseState.phrase(...args) }));

  // Configurations: trees of providers for three facets and a field, written as data both sides build from.
  const F0 = Facet.define();
  const F1 = Facet.define({ combine: (v) => v.reduce((a, b) => a + b, 0) });
  const F2 = Facet.define({ combine: (v) => (v.length ? v[0] : -1), static: true });
  const facets = [F0, F1, F2];
  const counter = StateField.define({ create: () => 0, update: (v, tr) => (tr.docChanged ? v + 1 : v) });
  const build = (node, ctx) => {
    switch (node.t) {
      case 'v': return facets[node.f].of(node.v);
      case 'c': return facets[node.f].compute(node.dep === 'doc' ? ['doc'] : node.dep === 'sel' ? ['selection'] : node.dep === 'field' ? [counter] : [facets[node.dep]],
        (state) => node.mul * (node.dep === 'doc' ? state.doc.length : node.dep === 'sel' ? state.selection.main.head : node.dep === 'field' ? (state.field(counter, false) ?? 0) : state.facet(facets[node.dep]).length));
      case 'n': return facets[node.f].computeN(['doc'], (state) => [state.doc.lines, state.doc.lines + node.add]);
      case 'field': return counter;
      case 'l': return node.c.map((c) => build(c, ctx));
      case 'p': return Prec[node.p](build(node.c, ctx));
      case 'k': return (ctx.comps[node.id] ??= new Compartment()).of(build(node.c, ctx));
      case 'r': return (ctx.shared[node.i] ??= build(ctx.sharedNodes[node.i], ctx));
    }
    throw new Error('node ' + node.t);
  };
  const leaf = (r2, allowDynamic = true) => {
    const f = int(r2, 3);
    const kind = f === 2 || !allowDynamic ? 'v' : pick(r2, ['v', 'v', 'c', 'n', 'field']);
    if (kind === 'v') return { t: 'v', f, v: int(r2, 50) };
    if (kind === 'c') {
      // F0 computed from F0 would be a cycle.
      const dep = pick(r2, ['doc', 'sel', 'field', 0]);
      return { t: 'c', f, dep: dep === 0 && f === 0 ? 'doc' : dep, mul: 1 + int(r2, 3) };
    }
    if (kind === 'n') return { t: 'n', f, add: 1 + int(r2, 3) };
    return { t: 'field' };
  };
  const tree = (r2, depth, used, sharedCount, comps = true) => {
    const roll = r2();
    if (depth <= 0 || roll < 0.35) return leaf(r2);
    if (roll < 0.6) return { t: 'l', c: Array.from({ length: int(r2, 4) }, () => tree(r2, depth - 1, used, sharedCount, comps)) };
    if (roll < 0.75) return { t: 'p', p: pick(r2, ['highest', 'high', 'default', 'low', 'lowest']), c: tree(r2, depth - 1, used, sharedCount, comps) };
    if (roll < 0.87 && comps) {
      const id = int(r2, 4);
      if (!used.has(id)) {
        used.add(id);
        return { t: 'k', id, c: tree(r2, depth - 1, used, sharedCount, false) };
      }
    }
    return sharedCount ? { t: 'r', i: int(r2, sharedCount) } : leaf(r2);
  };
  const read = (state) => ({ f0: state.facet(F0), f1: state.facet(F1), f2: state.facet(F2), field: state.field(counter, false) ?? null });
  const configs = [];
  for (let n = 0; n < 150; n++) {
    const sharedNodes = Array.from({ length: 2 }, () => tree(r, 2, new Set([0, 1, 2, 3]), 0, false));
    const ctx = { comps: {}, shared: {}, sharedNodes };
    const root = tree(r, 4, new Set(), 2);
    let state = EditorState.create({ doc: 'one\ntwo', extensions: build(root, ctx) });
    const steps = [];
    const start = read(state);
    for (let i = 0; i < 6; i++) {
      const kind = pick(r, ['edit', 'edit', 'sel', 'reconf', 'reconf', 'append', 'full']);
      let step;
      if (kind === 'edit') {
        const from = int(r, state.doc.length + 1);
        step = { s: 'edit', from, insert: pick(r, ['x', 'ab\ncd']) };
        state = state.update({ changes: { from, insert: step.insert } }).state;
      } else if (kind === 'sel') {
        step = { s: 'sel', anchor: int(r, state.doc.length + 1) };
        state = state.update({ selection: { anchor: step.anchor } }).state;
      } else if (kind === 'reconf') {
        const id = int(r, 4);
        step = { s: 'reconf', id, tree: tree(r, 2, new Set([0, 1, 2, 3]), 2, false) };
        state = state.update({ effects: (ctx.comps[id] ??= new Compartment()).reconfigure(build(step.tree, ctx)) }).state;
      } else if (kind === 'append') {
        step = { s: 'append', tree: tree(r, 2, new Set([0, 1, 2, 3]), 2, false) };
        state = state.update({ effects: StateEffect.appendConfig.of(build(step.tree, ctx)) }).state;
      } else {
        step = { s: 'full', tree: tree(r, 3, new Set(), 2) };
        state = state.update({ effects: StateEffect.reconfigure.of(build(step.tree, ctx)) }).state;
      }
      step.r = read(state);
      steps.push(step);
    }
    configs.push({ shared: sharedNodes, root, start, steps });
  }
  save('state.json', { clusters, words, byRange, multi, phrases, configs });
}

// ---------------------------------------------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------------------------------------------
{
  const r = rng(5);
  const sessions = [];
  for (let n = 0; n < 90; n++) {
    const config = pick(r, [{}, {}, { newGroupDelay: 200 }, { minDepth: 3 }, { minDepth: 3, newGroupDelay: 1000 }]);
    const setFlag = StateEffect.define();
    const flag = StateField.define({ create: () => 0, update: (v, tr) => { for (const e of tr.effects) if (e.is(setFlag)) v = e.value; return v; } });
    const withFlag = n % 3 === 0;
    const inverted = C.invertedEffects.of((tr) => {
      const found = [];
      for (const e of tr.effects) if (e.is(setFlag)) found.push(setFlag.of(tr.startState.field(flag)));
      return found;
    });
    let state = EditorState.create({ doc: 'The quick brown fox\njumps over', extensions: [C.history(config), withFlag ? [flag, inverted] : []] });
    let time = 1000;
    const ops = [];
    const target = { get state() { return state; }, dispatch: (tr) => { state = tr.state; } };
    const read = () => ({ doc: state.doc.toString(), anchor: state.selection.main.anchor, head: state.selection.main.head, undo: C.undoDepth(state), redo: C.redoDepth(state), flag: withFlag ? state.field(flag) : null });
    for (let i = 0; i < 40; i++) {
      // 199/200, 499/500 and 999/1000 sit on either side of the three delays the sessions use.
      time += pick(r, [10, 50, 120, 199, 200, 300, 499, 500, 520, 999, 1000, 1500]);
      const kind = pick(r, ['type', 'type', 'type', 'type', 'edit', 'edit', 'delete', 'select', 'select', 'undo', 'undo', 'redo', 'undoSelection', 'redoSelection', 'remote', withFlag ? 'effect' : 'type']);
      let op;
      if (kind === 'undo' || kind === 'redo' || kind === 'undoSelection' || kind === 'redoSelection') {
        op = { op: kind, time };
        // history's commands stamp their own transactions with Date.now(); nothing reads that time back.
        op.ran = C[kind](target);
      } else if (kind === 'select') {
        const anchor = int(r, state.doc.length + 1);
        op = { op: 'select', time, anchor, head: pick(r, [anchor, anchor, int(r, state.doc.length + 1)]), userEvent: pick(r, ['select', 'select.pointer', null]) };
        state = state.update({ selection: { anchor: op.anchor, head: op.head }, annotations: Transaction.time.of(time), userEvent: op.userEvent ?? undefined }).state;
      } else if (kind === 'effect') {
        op = { op: 'effect', time, v: 1 + int(r, 9) };
        state = state.update({ effects: setFlag.of(op.v), annotations: Transaction.time.of(time) }).state;
      } else {
        let from, to, insert, userEvent, sel = null;
        if (kind === 'type') {
          from = to = state.selection.main.head;
          insert = pick(r, ['a', 'b', ' ', 'word']);
          userEvent = pick(r, ['input.type', 'input.type', 'input.type', 'input.type.compose', null]);
          sel = from + insert.length;
        } else if (kind === 'delete') {
          to = state.selection.main.head;
          from = Math.max(0, to - 1);
          insert = '';
          userEvent = 'delete.backward';
          sel = from;
        } else {
          from = int(r, state.doc.length + 1);
          to = Math.min(state.doc.length, from + int(r, 4));
          insert = pick(r, ['', 'X', 'pasted\ntext']);
          userEvent = kind === 'remote' ? null : pick(r, ['input.paste', 'input', null, 'input.format']);
          if (from === to && !insert) insert = 'Q';
        }
        const isolate = r() < 0.12 ? pick(r, ['before', 'after', 'full']) : null;
        op = { op: 'edit', time, from, to, insert, userEvent, sel, isolate, remote: kind === 'remote' };
        const annotations = [Transaction.time.of(time)];
        if (isolate) annotations.push(C.isolateHistory.of(isolate));
        if (kind === 'remote') annotations.push(Transaction.addToHistory.of(false));
        state = state.update({ changes: { from, to, insert }, selection: sel == null ? undefined : { anchor: sel }, annotations, userEvent: userEvent ?? undefined }).state;
      }
      op.r = read();
      ops.push(op);
    }
    sessions.push({ config, withFlag, ops, json: state.toJSON({ history: C.historyField }).history });
  }
  save('history.json', { sessions });
}

// ---------------------------------------------------------------------------------------------------------------
// Range sets
// ---------------------------------------------------------------------------------------------------------------
{
  const r = rng(6);
  class Val extends RangeValue {
    constructor(id, spec) {
      super();
      this.id = id;
      this.startSide = spec.startSide;
      this.endSide = spec.endSide;
      this.point = spec.point;
      this.mapMode = spec.mapMode;
    }
    eq(other) { return other.id === this.id; }
  }
  const dump = (set, from = 0) => {
    const out = [];
    for (let c = set.iter(from); c.value; c.next()) out.push([c.from, c.to, c.value.id]);
    return out;
  };
  const dumpAll = (sets, from = 0) => {
    const out = [];
    for (let c = RangeSet.iter(sets, from); c.value; c.next()) out.push([c.from, c.to, c.value.id]);
    return out;
  };
  const spansOf = (sets, from, to, minPoint) => {
    const out = [];
    const open = RangeSet.spans(sets, from, to, {
      span: (f, t, active, openStart) => out.push(['s', f, t, active.map((v) => v.id), openStart]),
      point: (f, t, value, active, openStart, index) => out.push(['p', f, t, value.id, active.map((v) => v.id), openStart, index]),
    }, minPoint);
    return { out, open };
  };
  const compareOf = (a, b, diff, bounds, minPoint) => {
    const out = [];
    const comparator = {
      compareRange: (f, t, x, y) => out.push(['r', f, t, x.map((v) => v.id), y.map((v) => v.id)]),
      comparePoint: (f, t, x, y) => out.push(['p', f, t, x ? x.id : null, y ? y.id : null]),
    };
    if (bounds) comparator.boundChange = (pos) => out.push(['b', pos]);
    RangeSet.compare(a, b, diff, comparator, minPoint);
    return out;
  };
  const cases = [];
  for (let n = 0; n < 130; n++) {
    const length = pick(r, [40, 40, 40, 60, 60, 60, 3000]);
    const big = length > 100;
    const vals = Array.from({ length: big ? 40 : 10 }, () => {
      const point = r() < 0.35;
      const startSide = pick(r, [0, 0, -1, 1, -5, 5]);
      return { startSide, endSide: point ? pick(r, [startSide, startSide, startSide + 3]) : pick(r, [0, startSide, 1, -1]), point, mapMode: pick(r, [0, 1, 1, 2, 3]) };
    });
    const objs = vals.map((v, i) => new Val(i, v));
    const mkRanges = (count) =>
      Array.from({ length: count }, () => {
        const v = int(r, vals.length);
        const from = int(r, length + 1);
        let to = vals[v].point && r() < 0.6 ? from : Math.min(length, from + 1 + int(r, big ? 30 : 8));
        // An empty range whose end side is before its start side is not a range the builder may be given.
        if (to === from && vals[v].endSide < vals[v].startSide) to = Math.min(length, from + 1);
        if (to === from && vals[v].endSide < vals[v].startSide) return null;
        return [from, to, v];
      }).filter(Boolean);
    const toRanges = (list) => list.map(([f, t, v]) => objs[v].range(f, t));
    const ranges = mkRanges(big ? 520 : int(r, 14)), ranges2 = mkRanges(big ? 30 : int(r, 8)), add = mkRanges(int(r, 6));
    const set = RangeSet.of(toRanges(ranges), true), set2 = RangeSet.of(toRanges(ranges2), true);
    const change = big ? sortedSpecs(r, length, 6) : specs(r, length, 3);
    const changes = ChangeSet.of(change, length);
    const mapped = set.map(changes);
    const k = int(r, 3), filterFrom = int(r, length + 1), filterTo = filterFrom + int(r, length - filterFrom + 1);
    const filter = (f, t, v) => v.id % 3 !== k;
    const updated = set.update({ add: toRanges(add), sort: true, filter, filterFrom, filterTo });
    const updatedNoFilter = set.update({ add: toRanges(add), sort: true });
    const a = int(r, length + 1), b = a + int(r, length - a + 1);
    const between = [];
    set.between(a, b, (f, t, v) => { between.push([f, t, v.id]); });
    const firstTwo = [];
    set.between(a, b, (f, t, v) => { firstTwo.push([f, t, v.id]); return firstTwo.length < 2 ? undefined : false; });
    const newLength = changes.newLength;
    const na = Math.min(a, newLength), nb = Math.min(b, newLength);
    const add2 = mkRanges(1 + int(r, 4)).filter(([, t]) => t <= newLength);
    const changed = mapped.update({ add: toRanges(add2), sort: true, filter });
    cases.push({
      length, vals, ranges, ranges2, add, add2, change, k, filterFrom, filterTo, a, b,
      r: {
        dump: big ? null : dump(set), sum: checksum(JSON.stringify(dump(set))), size: set.size, length: set.length,
        mapped: big ? null : dump(mapped), mappedSum: checksum(JSON.stringify(dump(mapped))),
        updated: big ? null : dump(updated), updatedSum: checksum(JSON.stringify(dump(updated))),
        updatedNoFilter: checksum(JSON.stringify(dump(updatedNoFilter))),
        between, firstTwo, from: dump(set, a).slice(0, 30), both: dumpAll([set, set2], a).slice(0, 30),
        joined: checksum(JSON.stringify(dump(RangeSet.join([set, set2])))),
        spans: spansOf([set, set2], a, b, -1), spansPoints: spansOf([set], a, b, 0),
        compare: compareOf([set], [mapped], changes.desc, false, -1),
        compareBounds: compareOf([set], [mapped], changes.desc, true, -1),
        compareChanged: compareOf([set], [changed], changes.desc, true, -1),
        compareChangedPoints: compareOf([set, set2], [changed], changes.desc, false, 0),
        compareSelf: compareOf([set], [set], ChangeSet.empty(length).desc, true, -1),
        compareOther: compareOf([set, set2], [set2], ChangeSet.empty(length).desc, false, -1),
        eqSelf: RangeSet.eq([set], [RangeSet.of(toRanges(ranges), true)]), eqOther: RangeSet.eq([set], [set2]),
        eqMapped: RangeSet.eq([set], [mapped], na, nb),
      },
    });
  }

  // Decorations: the sides and map modes CodeMirror's view gives each kind, and what mapping does to them.
  class W extends V.WidgetType {
    constructor(h) { super(); this.h = h; }
    eq(o) { return o.h === this.h; }
    get estimatedHeight() { return this.h; }
    toDOM() { return null; }
  }
  const kinds = [];
  const describe = (d) => ({ startSide: d.startSide, endSide: d.endSide, point: d.point, mapMode: d.mapMode, heightRelevant: d.heightRelevant, block: d.block ?? null, type: d.block ? d.type : null });
  for (const inclusive of [null, true, false])
    for (const inclusiveStart of [null, true, false])
      for (const inclusiveEnd of [null, true, false]) {
        const spec = {};
        if (inclusive !== null) spec.inclusive = inclusive;
        if (inclusiveStart !== null) spec.inclusiveStart = inclusiveStart;
        if (inclusiveEnd !== null) spec.inclusiveEnd = inclusiveEnd;
        kinds.push({ k: 'mark', spec, r: describe(V.Decoration.mark({ ...spec, class: 'x' })) });
        for (const block of [false, true]) kinds.push({ k: 'replace', spec: { ...spec, block }, r: describe(V.Decoration.replace({ ...spec, block })) });
      }
  for (const side of [0, -1, 1, 5, -20000, 20000])
    for (const block of [false, true])
      for (const h of [-1, 3, 20]) kinds.push({ k: 'widget', spec: { side, block, h }, r: describe(V.Decoration.widget({ widget: new W(h), side, block })) });
  kinds.push({ k: 'line', spec: {}, r: describe(V.Decoration.line({ class: 'l' })) });
  kinds.push({ k: 'replace', spec: { h: 20 }, r: describe(V.Decoration.replace({ widget: new W(20) })) });

  const decoCases = [];
  for (let n = 0; n < 120; n++) {
    const text = lines(r, 3 + int(r, 3), 10).join('\n');
    const doc = Text.of(text.split('\n'));
    const made = [];
    const list = [];
    for (let i = 0, count = 2 + int(r, 8); i < count; i++) {
      const kind = pick(r, ['mark', 'mark', 'markInc', 'replace', 'replaceInc', 'widget', 'widgetAfter', 'line', 'block', 'blockReplace']);
      const from = int(r, doc.length + 1), to = Math.min(doc.length, from + 1 + int(r, 6));
      const line = doc.lineAt(from);
      try {
        const range =
          kind === 'mark' ? V.Decoration.mark({ class: 'm' + i }).range(from, to)
          : kind === 'markInc' ? V.Decoration.mark({ class: 'm' + i, inclusive: true }).range(from, to)
          : kind === 'replace' ? V.Decoration.replace({}).range(from, to)
          : kind === 'replaceInc' ? V.Decoration.replace({ inclusive: true }).range(from, to)
          : kind === 'widget' ? V.Decoration.widget({ widget: new W(i), side: -1 }).range(from)
          : kind === 'widgetAfter' ? V.Decoration.widget({ widget: new W(i), side: 1 }).range(from)
          : kind === 'line' ? V.Decoration.line({ class: 'l' + i }).range(line.from)
          : kind === 'block' ? V.Decoration.widget({ widget: new W(i), block: true, side: pick(r, [-1, 1]) }).range(pick(r, [line.from, line.to]))
          : V.Decoration.replace({ block: true, widget: new W(i) }).range(line.from, line.to);
        range.value.tag = i;
        list.push(range);
        made.push({ kind, i, from: range.from, to: range.to, side: kind === 'block' ? (range.value.startSide > 0 ? 1 : -1) : 0 });
      } catch (e) {
        // an empty mark: not a decoration
      }
    }
    const set = V.Decoration.set(list, true);
    const change = specs(r, doc.length, 3);
    const changes = ChangeSet.of(change, doc.length);
    const tags = (s) => { const out = []; for (let c = s.iter(); c.value; c.next()) out.push([c.from, c.to, c.value.tag]); return out; };
    decoCases.push({ doc: text, made, change, r: { dump: tags(set), mapped: tags(set.map(changes)) } });
  }
  save('rangeset.json', { cases, kinds, decoCases });
}
