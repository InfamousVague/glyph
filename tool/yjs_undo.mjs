#!/usr/bin/env node
// Ghost.md's own undo in a live note, for the Flutter app to be held to (docs/PARITY.md, Differs 26): the web
// app's editor bound to its live document by its own code, under Node, driven a step at a time.
//
//   node --experimental-transform-types --no-warnings tool/yjs_undo.mjs
//
// Every member here is what a member is on the page: a `Y.Doc` with the note's words in `body`
// (core/team/doc.ts), a CodeMirror `EditorView` (mounted under jsdom) with its undo in the slot
// (`undoSlot.of(localUndo())`, as editor/Editor.tsx builds it), and `bindLive` from
// ../glyph/src/app/editor/liveBinding.ts called on the two: `new Y.UndoManager(text)` handed to y-codemirror's
// `yCollab`, with `yUndoManagerKeymap`. Nothing of it is written here: a key is a transaction dispatched to the
// real view, an undo is the real key (or the keyboard's own `beforeinput`), what arrives is `Y.applyUpdate` under
// an origin that is not the editor's, and a reconcile is core/team/textDiff.ts `applyTextDiff`. So what this
// answers is what Ghost.md does, with the versions it ships (`versions` in the first line).
//
// The clock is the caller's: `Date.now` is replaced before Yjs loads (lib0 keeps the function it finds), and every
// command that could begin or lengthen an undo step says the time (`now`), so how typing is grouped (500 ms,
// `captureTimeout`) is the same every run.
//
// It reads commands from stdin, one JSON object a line, and answers each with one JSON line (a command's `id`, if
// it has one, is said back). A member is named by `who`; what is answered of one is `{words, text, anchor, head, undo, redo, bound}`: the editor's words, the
// document's, the main selection, and how many steps can be taken back and put in again (y-codemirror's
// `undoDepth` and `redoDepth` while bound, CodeMirror's own when not).
//
//   {do: 'open', who, client, words}        a member whose document is seeded with `words` (doc.ts `make`)
//   {do: 'open', who, client, from}         a member who adopts member `from`'s document as it stands
//   {do: 'bind', who} / {do: 'unbind', who}  liveBinding.ts `bindLive` / `unbindLive`
//   {do: 'type', who, at, remove, insert, now}   a key: the change, the caret after it, userEvent input.type
//   {do: 'select', who, anchor, head}       the caret moved
//   {do: 'undo' | 'redo', who, now, by?}    the key (Mod-z; Mod-y, or with by 'shift' Mod-Shift-z), or with by
//                                          'input' the keyboard's own undo (`beforeinput` historyUndo/historyRedo)
//   {do: 'key', who, key, shift?}           another key with Mod held; `taken` says whether the editor took it
//   {do: 'reconcile', who, words}           words that reach the note without the editor (textDiff.ts, LOCAL)
//   {do: 'deliver', from, to, count?}      the next `count` updates `from` made reach `to`, in order (all, left out)
//   {do: 'state', who}                      the member as it stands
//   {do: 'made', who?}                      every update the member has made, in order, base64url; of every member,
//                                          in the order they were made, with no `who`
//   {do: 'seed', who}                       the member's document as it was opened, as one update
//   {do: 'whole', who}                      the member's document as it stands, as one update
//   {do: 'read', updates}                  a fresh Yjs document that applies `updates`: its words
//   {do: 'reset'}                          every member let go, for the next scenario
//   {do: 'close'}                          ends
//
// ../glyph is only READ: its TypeScript loaded as it is, its node_modules for yjs, y-codemirror.next, CodeMirror
// and jsdom. Nothing here touches a network.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { createInterface } from 'node:readline';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const glyph = resolve(root, '../glyph');
const require = createRequire(join(glyph, 'package.json'));

// ---- The clock, before anything reads it ---------------------------------------------------------------------------

const wall = Date.now.bind(Date);
let clock = null;
Date.now = () => clock ?? wall();

// ---- A browser for the view ----------------------------------------------------------------------------------------

const { JSDOM } = require('jsdom');
const dom = new JSDOM('<!doctype html><html><body></body></html>', { pretendToBeVisual: true });
const define = (name, value) => Object.defineProperty(globalThis, name, { value, configurable: true, writable: true });
define('window', dom.window);
define('document', dom.window.document);
define('navigator', dom.window.navigator);
for (const name of ['MutationObserver', 'Node', 'HTMLElement', 'Range', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'DOMRect', 'Text', 'KeyboardEvent', 'InputEvent']) {
  define(name, typeof dom.window[name] === 'function' && /^[a-z]/.test(name) ? dom.window[name].bind(dom.window) : dom.window[name]);
}

// One copy of each library, the one the web's own files load: two would make every instanceof a lie.
const load = (path) => import(pathToFileURL(join(glyph, 'node_modules', path)).href);
const { EditorState } = await load('@codemirror/state/dist/index.js');
const { EditorView } = await load('@codemirror/view/dist/index.js');
const { undoDepth, redoDepth } = await load('@codemirror/commands/dist/index.js');
const Y = await load('yjs/dist/yjs.mjs');
const { yUndoManagerFacet } = await load('y-codemirror.next/src/y-undomanager.js');
const web = (path) => import(pathToFileURL(join(glyph, 'src/app', path)).href);
const { bindLive, unbindLive } = await web('editor/liveBinding.ts');
const { localUndo, undoSlot } = await web('editor/undoSlot.ts');
const { applyTextDiff } = await web('core/team/textDiff.ts');
const version = (name) => JSON.parse(readFileSync(join(glyph, 'node_modules', name, 'package.json'), 'utf8')).version;

/** The field a note's words live in (core/team/doc.ts `FIELD`). */
const FIELD = 'body';
/** What arrives, as doc.ts and session.ts mark it: an origin of its own, never the editor's. */
const REMOTE = Symbol('from another device');
const b64 = (bytes) => Buffer.from(bytes).toString('base64url');
const unb64 = (text) => new Uint8Array(Buffer.from(text, 'base64url'));
/** CodeMirror reads the platform once: under jsdom it is not a Mac, so Mod is Ctrl. */
const mac = /Mac/.test(navigator.platform);

const members = new Map();
/** Every update any member made, in the order they were made. */
let everything = [];
const member = (id) => {
  const found = members.get(id);
  if (!found) throw new Error(`no member ${id}`);
  return found;
};

function open({ who: id, client, words, from }) {
  const doc = new Y.Doc();
  doc.clientID = client;
  const text = doc.getText(FIELD);
  const made = [];
  const outbox = new Map();
  if (from !== undefined) Y.applyUpdate(doc, Y.encodeStateAsUpdate(member(from).doc), REMOTE);
  else if (words) text.insert(0, words);
  // The document as it began: what every other member was given to start from.
  const seed = Y.encodeStateAsUpdate(doc);
  doc.on('update', (update, origin) => {
    if (origin === REMOTE) return;
    made.push(update);
    everything.push(update);
    for (const queue of outbox.values()) queue.push(update);
  });
  const view = new EditorView({ state: EditorState.create({ doc: text.toString(), extensions: [undoSlot.of(localUndo())] }), parent: document.body });
  const one = { id, doc, text, view, made, outbox, seed, bound: false };
  // Everyone already here hears this one from now on, and it hears them.
  for (const other of members.values()) {
    other.outbox.set(id, []);
    outbox.set(other.id, []);
  }
  members.set(id, one);
  return one;
}

function state(one) {
  const main = one.view.state.selection.main;
  const manager = one.bound ? one.view.state.facet(yUndoManagerFacet).undoManager : null;
  return {
    words: one.view.state.doc.toString(),
    text: one.text.toString(),
    anchor: main.anchor,
    head: main.head,
    undo: manager ? manager.undoStack.length : undoDepth(one.view.state),
    redo: manager ? manager.redoStack.length : redoDepth(one.view.state),
    bound: one.bound,
  };
}

/** A key with Mod held, as a keyboard sends one: the letter Shift makes of it, and the key's own code, which is how CodeMirror finds `Mod-Shift-z` under a `Z`. */
function key(one, name, shift) {
  const code = name.toUpperCase().charCodeAt(0);
  const event = new KeyboardEvent('keydown', { key: shift ? name.toUpperCase() : name, code: `Key${name.toUpperCase()}`, keyCode: code, which: code, ctrlKey: !mac, metaKey: mac, shiftKey: shift, bubbles: true, cancelable: true });
  one.view.contentDOM.dispatchEvent(event);
  return event.defaultPrevented;
}

function run(command) {
  if (typeof command.now === 'number') clock = command.now;
  switch (command.do) {
    case 'open':
      return state(open(command));
    case 'bind': {
      const one = member(command.who);
      bindLive(one.view, { text: one.text });
      one.bound = true;
      return state(one);
    }
    case 'unbind': {
      const one = member(command.who);
      unbindLive(one.view);
      one.bound = false;
      return state(one);
    }
    case 'type': {
      const one = member(command.who);
      const insert = command.insert ?? '';
      one.view.dispatch({ changes: { from: command.at, to: command.at + (command.remove ?? 0), insert }, selection: { anchor: command.at + insert.length }, userEvent: 'input.type' });
      return state(one);
    }
    case 'select': {
      const one = member(command.who);
      one.view.dispatch({ selection: { anchor: command.anchor, head: command.head ?? command.anchor } });
      return state(one);
    }
    case 'undo':
    case 'redo': {
      const one = member(command.who);
      const redo = command.do === 'redo';
      let taken;
      if (command.by === 'input') {
        const event = new InputEvent('beforeinput', { inputType: redo ? 'historyRedo' : 'historyUndo', bubbles: true, cancelable: true });
        one.view.contentDOM.dispatchEvent(event);
        taken = event.defaultPrevented;
      } else if (!redo) taken = key(one, 'z', false);
      else if (command.by === 'shift') taken = key(one, 'z', true);
      else taken = key(one, 'y', false);
      // Whether the editor took the key as its own (a binding ran, or asked for it to be swallowed).
      return { ...state(one), taken };
    }
    case 'reconcile': {
      const one = member(command.who);
      applyTextDiff(one.text, one.text.toString(), command.words);
      return state(one);
    }
    case 'deliver': {
      const from = member(command.from);
      const to = member(command.to);
      const queue = from.outbox.get(command.to);
      const taken = queue.splice(0, command.count ?? queue.length);
      // doc.ts `applyRemote`: every update of a batch in one transaction.
      to.doc.transact(() => {
        for (const update of taken) Y.applyUpdate(to.doc, update, REMOTE);
      }, REMOTE);
      return { ...state(to), delivered: taken.length, waiting: queue.length };
    }
    case 'key': {
      // Any other key with Mod held: whether the editor has a binding for it.
      const one = member(command.who);
      return { ...state(one), taken: key(one, command.key, command.shift === true) };
    }
    case 'state':
      return state(member(command.who));
    case 'made':
      return { updates: (command.who === undefined ? everything : member(command.who).made).map(b64) };
    case 'seed':
      return { update: b64(member(command.who).seed) };
    case 'whole':
      return { update: b64(Y.encodeStateAsUpdate(member(command.who).doc)) };
    case 'read': {
      const doc = new Y.Doc();
      for (const update of command.updates) Y.applyUpdate(doc, unb64(update), REMOTE);
      return { text: doc.getText(FIELD).toString() };
    }
    default:
      throw new Error(`no command ${command.do}`);
  }
}

console.log(JSON.stringify({ ready: true, versions: { yjs: version('yjs'), 'y-codemirror.next': version('y-codemirror.next'), '@codemirror/commands': version('@codemirror/commands') }, mac }));

for await (const line of createInterface({ input: process.stdin })) {
  if (!line.trim()) continue;
  let command;
  try {
    command = JSON.parse(line);
  } catch (failure) {
    console.log(JSON.stringify({ error: `not a command: ${failure.message}` }));
    continue;
  }
  if (command.do === 'close') {
    console.log(JSON.stringify({ id: command.id, closed: true }));
    break;
  }
  if (command.do === 'reset') {
    for (const one of members.values()) one.view.destroy();
    members.clear();
    everything = [];
    console.log(JSON.stringify({ id: command.id, reset: true }));
    continue;
  }
  try {
    console.log(JSON.stringify({ id: command.id, ...run(command) }));
  } catch (failure) {
    console.log(JSON.stringify({ id: command.id, error: String(failure?.stack ?? failure) }));
  }
}
process.exit(0);
