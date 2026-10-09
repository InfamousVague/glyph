// What the web's voice capture does, for the Dart port to be held against (lib/capture/voice_suite.dart,
// lib/capture/live_route.dart; test/capture/voice_suite_test.dart, test/capture/live_route_test.dart).
//
//   node --experimental-transform-types --no-warnings tool/voice_fixtures.mjs
//
// (`--experimental-transform-types` because capture/liveTake.ts has a constructor with parameter properties, which
// Node's plain type stripping refuses.) Everything is read from ../glyph and nothing is written there. Nothing is
// random and no clock is read, so running it again writes the same files. Three files go to test/capture/fixtures/:
//
//   suite.json             a copy of glyph/voice-tests/suite.json, byte for byte: the scripts and what each expects.
//
//   voice_suite_web.json   every suite case played by the web's own capture/voiceSuite.ts (`scriptHeard`, `runTest`,
//                          `problems`), as voiceSuite.test.ts plays it from the scripts:
//     formats   the spoken formats set before the run (`setSpokenFormats`): the Marks plugin's cues and delimiters.
//               voiceSuite.test.ts takes them from plugins/marks/index.tsx, which Node cannot import (a .tsx with
//               icon components), so they are read out of that file's text: each mark's `delimiter` and `cue`.
//     cases     one per test, in the suite's order: {id, file, heard: {segments, audioMs}, outcome: {note, notes,
//               newNote, stoppedAtMs, lastWordsMs, log}, problems: [...], pass}. `outcome` is runTest's whole
//               answer (the take's own note, every note by title after the recording, the log of what the live
//               reader routed and read); `problems` and `pass` are the web's own judgement of it.
//
//   live_route_web.json    capture/liveRoute.test.ts run as it stands, under a stand-in for vitest that runs each
//                          case's body and judges nothing, with `LiveTake.apply` watched: for every case, by its
//                          full name ("describe > it"), each take the case made, and for each take every list of
//                          steps the live reader handed it, in order. A step is as the web makes it, but a note is
//                          its id, a card's candidates are {id, title, note: id}, and keys holding null or undefined
//                          are left out. The Dart test replays the same cases and holds its steps against these.
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { registerHooks } from 'node:module';

const GLYPH = '/Users/matt/Development/Apps/glyph/';
const APP = `${GLYPH}src/app/`;
const OUT = new URL('../test/capture/fixtures/', import.meta.url).pathname;
mkdirSync(OUT, { recursive: true });

// ---- A stand-in for vitest, and for JSON imports ----------------------------------------------------------------

const VITEST = 'ghost-fixtures:vitest';
const SHIM = `
const state = globalThis.__voiceFixtures;
const anything = new Proxy(function () {}, { get: (_, key) => (key === 'then' ? undefined : anything), apply: () => anything });
export const expect = anything;
export const vi = anything;
export const beforeAll = (fn) => fn();
export const beforeEach = () => {};
export const afterEach = () => {};
export const afterAll = () => {};
export function describe(name, body) {
  state.groups.push(name);
  body();
  state.groups.pop();
}
const format = (name, row) => {
  const values = Array.isArray(row) ? [...row] : [row];
  return name.replace(/%[sdioj]/g, () => String(values.shift()));
};
export function it(name, body) {
  state.cases.push({ name: [...state.groups, name].join(' > '), body });
}
it.each = (rows) => (name, body) => {
  for (const row of rows) it(format(name, row), () => (Array.isArray(row) ? body(...row) : body(row)));
};
export const test = it;
`;

globalThis.__voiceFixtures = { groups: [], cases: [] };
registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === 'vitest') return { url: VITEST, shortCircuit: true };
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (url === VITEST) return { format: 'module', source: SHIM, shortCircuit: true };
    return nextLoad(url, context);
  },
});

// ---- The voice suite ------------------------------------------------------------------------------------------------

copyFileSync(`${GLYPH}voice-tests/suite.json`, `${OUT}suite.json`);
const suite = JSON.parse(readFileSync(`${GLYPH}voice-tests/suite.json`, 'utf8'));

/** The Marks plugin's spoken cues, read from the text of plugins/marks/index.tsx: each mark's delimiter and cue. */
function marksFormats() {
  const text = readFileSync(`${APP}plugins/marks/index.tsx`, 'utf8');
  const from = text.indexOf('export const MARKS');
  const list = text.slice(from, text.indexOf('\n];', from));
  const formats = [];
  for (const entry of list.split(/\n {2}\{\n/).slice(1)) {
    const delimiter = /\bdelimiter:\s*'([^']*)'/.exec(entry)?.[1];
    const cue = /\bcue:\s*'([^']*)'/.exec(entry)?.[1];
    if (delimiter === undefined) throw new Error(`a mark with no delimiter: ${entry.slice(0, 80)}`);
    if (cue) formats.push({ word: cue, delimiter });
  }
  if (!formats.length) throw new Error('no marks read from plugins/marks/index.tsx');
  return formats;
}

const { setSpokenFormats } = await import(`${APP}capture/spoken/inline.ts`);
const { problems, runTest, scriptHeard } = await import(`${APP}capture/voiceSuite.ts`);

const formats = marksFormats();
setSpokenFormats(formats);

const cases = suite.tests.map((test) => {
  const heard = scriptHeard(test.lines);
  const outcome = runTest(test, suite.fixtures, heard);
  const wrong = problems(test, outcome);
  return { id: test.id, file: test.file, skip: test.skip ?? null, heard, outcome, problems: wrong, pass: wrong.length === 0 };
});
// The day this run was made on, as the recorder counts a spoken "tomorrow" from it (capture/markdown.ts `isoDay`):
// the Dart suite is run as of this day, whenever it is run.
const made = new Date();
const today = `${made.getFullYear()}-${String(made.getMonth() + 1).padStart(2, '0')}-${String(made.getDate()).padStart(2, '0')}`;
writeFileSync(`${OUT}voice_suite_web.json`, `${JSON.stringify({ today, formats, cases }, null, 1)}\n`);
const failing = cases.filter((c) => !c.pass);
console.log(`voice_suite_web.json: ${cases.length} cases, ${cases.length - failing.length} pass as the web judges them${failing.length ? ` (failing: ${failing.map((c) => c.id).join(', ')})` : ''}`);

// ---- The live reader's own tests, traced ------------------------------------------------------------------------

/** A step as data: a note is its id, and what is null or undefined is left out. */
function plain(value, key = '') {
  if (value === null || value === undefined) return undefined;
  if (Array.isArray(value)) return value.map((item) => plain(item) ?? null);
  if (typeof value === 'object') {
    if (key === 'note' && typeof value.id === 'string') return value.id;
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      const made = plain(v, k);
      if (made !== undefined) out[k] = made;
    }
    return out;
  }
  return value;
}

const { LiveTake } = await import(`${APP}capture/liveTake.ts`);
let takes = [];
let seen = new Map();
const apply = LiveTake.prototype.apply;
LiveTake.prototype.apply = function traced(steps) {
  if (!seen.has(this)) {
    seen.set(this, []);
    takes.push(seen.get(this));
  }
  seen.get(this).push(steps.map((step) => plain(step)));
  return apply.call(this, steps);
};

// The suite left its link titles and the Marks' cues set; liveRoute.test.ts runs in a file of its own, with neither.
const { setLinkTitles } = await import(`${APP}capture/spoken/extras.ts`);
setLinkTitles([]);
setSpokenFormats([]);

await import(`${APP}capture/liveRoute.test.ts`);
const traces = {};
for (const { name, body } of globalThis.__voiceFixtures.cases) {
  if (name in traces) throw new Error(`two cases named ${name}`);
  takes = [];
  seen = new Map();
  await body();
  traces[name] = takes;
}
const names = Object.keys(traces);
writeFileSync(`${OUT}live_route_web.json`, `{\n${names.map((name) => `${JSON.stringify(name)}: ${JSON.stringify(traces[name])}`).join(',\n')}\n}\n`);
console.log(`live_route_web.json: ${names.length} cases, ${names.reduce((sum, name) => sum + traces[name].length, 0)} takes`);
