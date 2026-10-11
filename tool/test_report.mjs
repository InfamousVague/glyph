#!/usr/bin/env node
// Writes assets/diag/test_report.json: what every test this app has did the last time the whole suite was run,
// which a build carries and Settings › Test results (Developer mode) shows. Ghost.md's own is
// tauri/scripts/test-report.mjs, which writes src/app/diag/testReport.generated.json for its page to compile in;
// the report is the same shape, so the page here is the page there (lib/settings/panes/test_results_pane.dart).
//
//   node tool/test_report.mjs                    runs tool/check.sh, all of it, then writes the report
//   node tool/test_report.mjs --skip=native      leaves parts of the check out (kit, app, server, kotlin, native):
//   node tool/test_report.mjs --only=kit,app     a suite that was not run keeps its last results, marked not run
//   node tool/test_report.mjs --read             runs nothing: the report of what build/check holds now, for a
//                                                look at a check made by hand. It says nothing of what code those
//                                                runs were of, so the page calls it a development build's
//   node tool/test_report.mjs --source           prints this checkout's source fingerprint and writes nothing: a
//                                                build is given it as --dart-define=GHOST_SOURCE=<it>
//   node tool/test_report.mjs --clear            puts back the report of a build made without one
//
// It exits 1 when anything failed or did not run, so whatever makes a release can refuse to go on
// (tool/release.md says when this is run).
//
// THE SUITES are tool/check.sh's parts, read from what each leaves in build/check:
//   App (Flutter)    every folder of test/ and the tests at its top (app-<folder>.json, app-top.json: flutter's
//                    own report, an event a line). test/e2e and test/live are run twice by a whole check, without
//                    the service and with it (server-e2e.json, server-live.json): the run with the service is the
//                    one reported, where there is one.
//   Kit (Flutter)    packages/glacier, and any other package under packages/ with tests (kit.json, kit-<name>.json)
//   Phone (Kotlin)   the JVM tests of android/app/src/test (gradle's XML, written since build/check/kotlin.began)
//   Core (Rust)      cargo's own tests of native/ (native.log)
// A suite that ran no test is an error and never a pass, and so is a run that did not end: a runner that could not
// find its tests, or died before them, would otherwise show green. A folder of test/ whose run is not there (or is
// from before this report's check began) makes the app's suite one that did not run, and says which.
//
// THE FINGERPRINT (`sourceHash`) is of the code the tests test: every file git knows, or would know (not ignored),
// under lib, test, packages, native, tool, android/app/src, assets and shaders, with pubspec.yaml and its lock, in
// a stable order, less the report itself. The report records it as the check begins, and a build is stamped with
// it (GHOST_SOURCE), so the page can say whether the build in your hand is the code these results are for. Not in
// it: tauri/, which the core and the faces are partly built from and which is the Tauri app's own tree, with a report
// of its own (tauri/scripts/test-report.mjs).
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, readdirSync, realpathSync, statSync, writeFileSync } from 'node:fs';
import { arch, platform } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = fileURLToPath(new URL('..', import.meta.url)).replace(/\/$/, '');
export const REPORT_PATH = 'assets/diag/test_report.json';
const SOURCES = ['lib', 'test', 'packages', 'native', 'tool', 'android/app/src', 'assets', 'shaders', 'pubspec.yaml', 'pubspec.lock'];

/** The parts of tool/check.sh that are suites here, and the suite each is of. */
const PARTS = { kit: 'flutter:kit', app: 'flutter:app', server: 'flutter:app', kotlin: 'kotlin', native: 'cargo:core' };
const TITLES = { 'flutter:app': 'App (Flutter)', 'flutter:kit': 'Kit (Flutter)', kotlin: 'Phone (Kotlin)', 'cargo:core': 'Core (Rust)' };
const ORDER = ['flutter:app', 'flutter:kit', 'kotlin', 'cargo:core'];

const ANSI = new RegExp(`${String.fromCharCode(27)}\\[[0-9;]*[A-Za-z]`, 'g');
const CLAMP = 2000;

/** What a runner printed, without its colours, and no longer than a page has room for. */
export function clean(text) {
  const plain = String(text ?? '').replace(ANSI, '').trim();
  return plain.length > CLAMP ? `${plain.slice(0, CLAMP)}\n…` : plain;
}

function counts(tests) {
  const tally = { total: tests.length, passed: 0, failed: 0, skipped: 0, todo: 0 };
  for (const test of tests) tally[test.status] += 1;
  return tally;
}

/** The files the fingerprint is of, as git lists them: known, or new and not ignored. */
export function sourceFiles(root) {
  const listed = spawnSync('git', ['ls-files', '-co', '--exclude-standard', '-z', '--', ...SOURCES], { cwd: root, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  if (listed.status !== 0) return [];
  return [...new Set(listed.stdout.split('\0').filter((path) => path && path !== REPORT_PATH))].sort();
}

export function sourceHash(root) {
  const files = sourceFiles(root);
  if (!files.length) return null;
  const hash = createHash('sha256');
  for (const path of files) {
    let bytes;
    try {
      bytes = readFileSync(join(root, path));
    } catch {
      // Deleted and not committed yet, or a link to a folder (a worktree's native/target): not source.
      continue;
    }
    hash.update(path);
    hash.update('\0');
    hash.update(bytes);
    hash.update('\0');
  }
  return hash.digest('hex').slice(0, 16);
}

/**
 * One `flutter test --file-reporter json:…` (an event a line), as tests: each with its file from the checkout's
 * top, the line it is written at, how long it took, and what it printed when it failed. A file that did not load
 * (it does not compile) is one failed test named for that; a group's setUpAll or tearDownAll that threw is one
 * too, by its own name. `finished` is whether the run reached its end.
 */
export function fromFlutter(text, root) {
  const suites = new Map(), started = new Map(), said = new Map(), errors = new Map();
  const tests = [];
  let finished = false, lastTime = 0;
  const push = (map, key, value) => map.set(key, [...(map.get(key) ?? []), ...String(value ?? '').split('\n')]);
  const why = (id) => {
    // A widget test's failure is printed by the framework, under "The following … was thrown"; a plain test's,
    // and a file that did not compile, say it in the error itself.
    const lines = said.get(id) ?? [];
    const from = lines.findIndex((line) => line.trimStart().startsWith('The following'));
    if (from >= 0) {
      const to = lines.findIndex((line, at) => at > from && line.trimStart().startsWith('When the exception was thrown'));
      return lines.slice(from, to < 0 ? undefined : to).join('\n');
    }
    return (errors.get(id) ?? []).join('\n');
  };
  for (const row of String(text ?? '').split('\n')) {
    let event;
    try {
      event = JSON.parse(row);
    } catch {
      continue;
    }
    if (typeof event?.time === 'number') lastTime = Math.max(lastTime, event.time);
    if (event.type === 'suite') suites.set(event.suite.id, event.suite.path);
    else if (event.type === 'testStart') started.set(event.test.id, { ...event.test, at: event.time });
    else if (event.type === 'print') push(said, event.testID, event.message);
    else if (event.type === 'error') push(errors, event.testID, event.error);
    else if (event.type === 'done') finished = true;
    else if (event.type === 'testDone') {
      const test = started.get(event.testID);
      if (!test) continue;
      const path = String(suites.get(test.suiteID) ?? '?');
      const file = path.startsWith(`${root}/`) ? path.slice(root.length + 1) : path;
      const failed = event.result !== 'success';
      // The loading of a file is a test of flutter's own, hidden when it goes well and shown when it does not; a
      // group's setUpAll and tearDownAll are hidden too. None is counted unless it failed.
      const loading = test.name === `loading ${path}`;
      if (loading || event.hidden) {
        if (failed) tests.push({ file, line: null, name: loading ? '(the file did not run)' : test.name, status: 'failed', ms: null, failure: clean(why(event.testID)) });
        continue;
      }
      const status = event.skipped ? 'skipped' : failed ? 'failed' : 'passed';
      tests.push({
        file,
        // A test written through a helper of the framework's (testWidgets) is at its `root_line` in its own file.
        line: test.root_line ?? test.line ?? null,
        name: test.name,
        status,
        ms: typeof event.time === 'number' && typeof test.at === 'number' ? Math.max(0, event.time - test.at) : null,
        failure: status === 'failed' ? clean(why(event.testID)) : null,
      });
    }
  }
  return { tests, finished, durationMs: lastTime };
}

const unescapeXml = (text) =>
  String(text ?? '')
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&');

/** Gradle's `TEST-<class>.xml` files, as tests: the class stands in for the file. */
export function fromJUnit(documents) {
  const tests = [];
  let durationMs = 0;
  for (const xml of documents) {
    for (const found of String(xml).matchAll(/<testcase\b([^>]*?)(\/>|>([\s\S]*?)<\/testcase>)/g)) {
      const attribute = (name) => unescapeXml(new RegExp(`\\b${name}="([^"]*)"`).exec(found[1])?.[1] ?? '');
      const inside = found[3] ?? '';
      const wrong = /<(failure|error)\b([^>]*?)(\/>|>([\s\S]*?)<\/\1>)/.exec(inside);
      const status = wrong ? 'failed' : /<skipped\b/.test(inside) ? 'skipped' : 'passed';
      const ms = Math.round(Number(attribute('time')) * 1000);
      if (Number.isFinite(ms)) durationMs += ms;
      const body = wrong ? unescapeXml((wrong[4] ?? '').replace(/^<!\[CDATA\[|\]\]>$/g, '')) : '';
      const message = wrong ? unescapeXml(/\bmessage="([^"]*)"/.exec(wrong[2])?.[1] ?? '') : '';
      tests.push({ file: attribute('classname') || '(class)', line: null, name: attribute('name'), status, ms: Number.isFinite(ms) ? ms : null, failure: wrong ? clean(body || message) : null });
    }
  }
  return { tests, durationMs };
}

/**
 * `cargo test`'s plain output: `test path::to::name ... ok | FAILED | ignored`, then a `---- name stdout ----`
 * block for each failure. A test of the library is filed under its module (`crdt::tests::x` under `crdt::tests`);
 * one of a file under tests/ under that file.
 */
export function fromCargo(output) {
  const text = String(output ?? '').replace(ANSI, '');
  const failures = new Map();
  const blocks = text.split(/^---- (.+?) stdout ----$/m);
  for (let i = 1; i < blocks.length; i += 2) {
    const body = (blocks[i + 1] ?? '').split(/^(?:failures:|successes:)$/m)[0];
    failures.set(blocks[i].trim(), clean(body));
  }
  const tests = [];
  let binary = null;
  for (const line of text.split('\n')) {
    const running = /^\s*Running (?:unittests )?(\S+) \(/.exec(line);
    if (running) {
      binary = running[1].startsWith('tests/') ? running[1] : null;
      continue;
    }
    if (/^\s*Doc-tests /.test(line)) {
      binary = '(doc)';
      continue;
    }
    const found = /^test (\S+) \.\.\. (ok|FAILED|ignored)(?:, .*)?$/.exec(line);
    if (!found) continue;
    const name = found[1];
    const at = name.lastIndexOf('::');
    const status = found[2] === 'ok' ? 'passed' : found[2] === 'FAILED' ? 'failed' : 'skipped';
    const module = at > 0 ? name.slice(0, at) : null;
    tests.push({
      file: binary ? (module ? `${binary} ${module}` : binary) : (module ?? '(crate)'),
      line: null,
      name: at > 0 ? name.slice(at + 2) : name,
      status,
      ms: null,
      failure: status === 'failed' ? (failures.get(name) ?? null) : null,
    });
  }
  const compileError = !tests.length && /error(\[E\d+\])?:/.test(text) ? clean(text.split('\n').filter((l) => /error|-->/.test(l)).slice(0, 30).join('\n')) : null;
  return { tests, compileError };
}

function suite(id, { tests, command, runnerVersion, durationMs, reason, incomplete }) {
  const failed = tests.some((test) => test.status === 'failed');
  return {
    id,
    title: TITLES[id],
    runner: id.split(':')[0],
    runnerVersion: runnerVersion ?? null,
    command: command ?? null,
    status: !tests.length ? 'error' : failed ? 'failed' : incomplete ? 'notRun' : 'passed',
    reason: reason ?? null,
    exitCode: null,
    durationMs: durationMs ?? null,
    counts: counts(tests),
    tests,
  };
}

/** A run's report in `dir`, if it is there and no older than `since` (milliseconds; null takes any). */
function fresh(dir, name, since) {
  const path = join(dir, name);
  try {
    const kept = statSync(path);
    if (!kept.isFile() || (since != null && kept.mtimeMs < since)) return null;
    return { path, at: kept.mtimeMs };
  } catch {
    return null;
  }
}

/**
 * The suites as `dir` (build/check) holds them. `folders` are the folders of test/ a whole check runs ("." for
 * the tests at its top); `results` are the folders gradle may have left its XML in; `since` leaves out what an
 * earlier check wrote; `versions` are the runners' own words for themselves. A suite with nothing of its own in
 * `dir` is not in the answer at all.
 */
export function suitesFrom(dir, { root = ROOT, folders = [], results = [], since = null, versions = {} } = {}) {
  const out = [];
  let newest = 0;
  const read = (name) => {
    const found = fresh(dir, name, since);
    if (!found) return null;
    newest = Math.max(newest, found.at);
    return fromFlutter(readFileSync(found.path, 'utf8'), root);
  };

  // The app: a run a folder, and the two folders that are run again with the service.
  const app = { tests: [], missing: [], unfinished: [], durationMs: 0, any: false };
  for (const folder of folders) {
    const name = folder === '.' ? 'app-top' : `app-${folder}`;
    const alone = read(`${name}.json`);
    const served = folder === 'e2e' || folder === 'live' ? read(`server-${folder}.json`) : null;
    const run = served ?? alone;
    if (!run) {
      app.missing.push(folder === '.' ? 'the tests at the top of test/' : `test/${folder}`);
      continue;
    }
    app.any = true;
    app.tests.push(...run.tests);
    app.durationMs += run.durationMs + (served && alone ? alone.durationMs : 0);
    if (!run.finished) app.unfinished.push(name);
  }
  if (app.any) {
    const reasons = [];
    if (app.unfinished.length) reasons.push(`Did not reach its end: ${app.unfinished.join(', ')}.`);
    // Named, a few of them: a check of one folder leaves fifty out.
    const named = app.missing.length > 8 ? `${app.missing.slice(0, 8).join(', ')} and ${app.missing.length - 8} more` : app.missing.join(', ');
    if (app.missing.length) reasons.push(`Not run for this report: ${named} (${app.missing.length} of ${folders.length} runs).`);
    if (!app.tests.length) reasons.push('flutter ran no tests.');
    out.push(suite('flutter:app', { tests: app.tests, command: 'tool/check.sh app, then tool/check.sh server', runnerVersion: versions.flutter, durationMs: app.durationMs, reason: reasons.join(' ') || null, incomplete: app.missing.length > 0 || app.unfinished.length > 0 }));
  }

  // The kit, and any other package with tests of its own.
  const kit = { tests: [], unfinished: [], durationMs: 0, any: false };
  let names = [];
  try {
    names = readdirSync(dir).filter((name) => /^kit(-.+)?\.json$/.test(name)).sort();
  } catch {
    names = [];
  }
  for (const name of names) {
    const run = read(name);
    if (!run) continue;
    kit.any = true;
    kit.tests.push(...run.tests);
    kit.durationMs += run.durationMs;
    if (!run.finished) kit.unfinished.push(name.replace(/\.json$/, ''));
  }
  if (kit.any) {
    const reasons = [];
    if (kit.unfinished.length) reasons.push(`Did not reach its end: ${kit.unfinished.join(', ')}.`);
    if (!kit.tests.length) reasons.push('flutter ran no tests.');
    out.push(suite('flutter:kit', { tests: kit.tests, command: 'tool/check.sh kit', runnerVersion: versions.flutter, durationMs: kit.durationMs, reason: reasons.join(' ') || null, incomplete: kit.unfinished.length > 0 }));
  }

  // The phone's Kotlin: what gradle wrote since this check's run of it began.
  const began = fresh(dir, 'kotlin.began', since);
  if (began) {
    newest = Math.max(newest, began.at);
    const documents = [];
    for (const folder of results) {
      let files = [];
      try {
        files = readdirSync(folder).filter((name) => name.endsWith('.xml')).sort();
      } catch {
        continue;
      }
      for (const name of files) {
        const path = join(folder, name);
        if (statSync(path).mtimeMs >= began.at) documents.push(readFileSync(path, 'utf8'));
      }
    }
    const read = fromJUnit(documents);
    out.push(suite('kotlin', { tests: read.tests, command: 'tool/check.sh kotlin', runnerVersion: versions.gradle, durationMs: read.durationMs, reason: read.tests.length ? null : 'gradle ran no tests (build/check/kotlin.log says why).' }));
  }

  // The core's own tests.
  const native = fresh(dir, 'native.log', since);
  if (native) {
    newest = Math.max(newest, native.at);
    const read = fromCargo(readFileSync(native.path, 'utf8'));
    out.push(suite('cargo:core', { tests: read.tests, command: 'tool/check.sh native', runnerVersion: versions.cargo, reason: read.tests.length ? null : (read.compileError ?? 'cargo ran no tests.') }));
  }
  return { suites: out, newest: newest || null };
}

/** The report's totals, from its suites: a suite that did not run counts once as not run. */
export function totalsOf(suites) {
  const totals = { total: 0, passed: 0, failed: 0, skipped: 0, todo: 0, notRun: 0 };
  for (const one of suites) {
    if (one.status === 'notRun' || one.status === 'error') totals.notRun += 1;
    for (const key of ['total', 'passed', 'failed', 'skipped', 'todo']) totals[key] += one.counts[key];
  }
  return totals;
}

/** The report of a build made without one: the page then says "No test report in this build." */
export const EMPTY = { schemaVersion: 1, generatedAt: null, version: null, commit: null, dirty: false, sourceHash: null, host: null, tools: {}, ok: false, totals: { total: 0, passed: 0, failed: 0, skipped: 0, todo: 0, notRun: 0 }, suites: [] };

/** The report as its file: a line for each of its own facts, and a line for each test, so two reports can be read against each other. */
export function written(report) {
  const { suites, ...facts } = report;
  const lines = Object.entries(facts).map(([key, value]) => ` ${JSON.stringify(key)}: ${JSON.stringify(value)},`);
  const cards = suites.map((one) => {
    const { tests, ...own } = one;
    const head = Object.entries(own).map(([key, value]) => `${JSON.stringify(key)}: ${JSON.stringify(value)}`).join(', ');
    return tests.length ? `  {${head}, "tests": [\n${tests.map((test) => `   ${JSON.stringify(test)}`).join(',\n')}\n  ]}` : `  {${head}, "tests": []}`;
  });
  return `{\n${lines.join('\n')}\n "suites": [${cards.length ? `\n${cards.join(',\n')}\n ` : ''}]\n}\n`;
}

function main() {
  const flag = (name) => process.argv.includes(`--${name}`);
  const list = (name) => process.argv.find((a) => a.startsWith(`--${name}=`))?.split('=')[1]?.split(',').filter(Boolean) ?? null;
  const out = join(ROOT, REPORT_PATH);
  if (flag('source')) {
    process.stdout.write(`${sourceHash(ROOT) ?? ''}\n`);
    return 0;
  }
  if (flag('clear')) {
    mkdirSync(dirname(out), { recursive: true });
    writeFileSync(out, written(EMPTY));
    process.stdout.write(`test report: cleared -> ${REPORT_PATH}\n`);
    return 0;
  }
  const firstLine = (command, args, cwd = ROOT) => (spawnSync(command, args, { cwd, encoding: 'utf8' }).stdout ?? '').split('\n')[0].trim() || null;
  const git = (args) => (spawnSync('git', args, { cwd: ROOT, encoding: 'utf8' }).stdout ?? '').trim();
  const reading = flag('read');
  const only = list('only'), skip = [...(list('skip') ?? []), ...(process.env.GHOST_CHECK_SKIP ?? '').split(/\s+/).filter(Boolean)];
  const parts = Object.keys(PARTS);
  for (const named of [...(only ?? []), ...(list('skip') ?? [])]) {
    if (!parts.includes(named)) {
      process.stderr.write(`test report: there is no part called ${named} (${parts.join(', ')})\n`);
      return 2;
    }
  }
  const left = reading ? [] : parts.filter((part) => (only && !only.includes(part)) || skip.includes(part));

  // The fingerprint and the moment, before anything runs: the results are of this code.
  const source = reading ? null : sourceHash(ROOT);
  const began = Date.now();
  if (!reading) {
    const leftOut = [...new Set([...left, ...skip, ...(only ? ['analyze', 'pictures'] : [])])];
    process.stdout.write(`test report: running tool/check.sh${leftOut.length ? ` without ${leftOut.join(', ')}` : ''}\n`);
    spawnSync(join(ROOT, 'tool/check.sh'), [], { cwd: ROOT, stdio: 'inherit', env: { ...process.env, GHOST_CHECK_SKIP: leftOut.join(' ') } });
    const after = sourceHash(ROOT);
    if (after !== source) process.stdout.write('test report: the code changed while the check ran; the report is stamped with what it began on\n');
  }

  const folders = [...new Set(git(['ls-files', 'test/*_test.dart']).split('\n').filter(Boolean).map((path) => (path.split('/').length > 2 ? path.split('/')[1] : '.')))].sort();
  const flutter = firstLine('flutter', ['--version'])?.split(' • ')[0] ?? null;
  const tools = { flutter, dart: firstLine('dart', ['--version'])?.replace(/^Dart SDK version: (\S+).*$/, 'Dart $1') ?? null, cargo: firstLine('cargo', ['--version']), rustc: firstLine('rustc', ['--version']) };
  const results = ['build/app/test-results/testDebugUnitTest', 'android/app/build/test-results/testDebugUnitTest'].map((path) => join(ROOT, path));
  const { suites: ran, newest } = suitesFrom(join(ROOT, 'build/check'), { root: ROOT, folders, results, since: reading ? null : began, versions: { flutter, cargo: tools.cargo } });

  let previous = null;
  try {
    previous = JSON.parse(readFileSync(out, 'utf8'));
  } catch {
    previous = null;
  }
  const suites = ORDER.map((id) => {
    const now = ran.find((one) => one.id === id);
    const asked = parts.filter((part) => PARTS[part] === id && !left.includes(part));
    if (now && (reading || asked.length)) return now;
    if (reading) return { id, title: TITLES[id], runner: id.split(':')[0], runnerVersion: null, command: null, status: 'notRun', reason: 'Nothing of it is in build/check.', exitCode: null, durationMs: null, counts: counts([]), tests: [] };
    // Asked for and nothing came of it: the run died before it wrote anything.
    if (asked.length) return { id, title: TITLES[id], runner: id.split(':')[0], runnerVersion: null, command: null, status: 'error', reason: 'The check left no results for it (build/check has its log).', exitCode: null, durationMs: null, counts: counts([]), tests: [] };
    // Not asked for this time: what it did last is kept, but marked as not run for this report.
    const last = previous?.suites?.find((one) => one.id === id);
    return last
      ? { ...last, status: 'notRun', reason: 'Not run for this report (left out with --only, --skip or GHOST_CHECK_SKIP). Its last results are shown.' }
      : { id, title: TITLES[id], runner: id.split(':')[0], runnerVersion: null, command: null, status: 'notRun', reason: 'Never run.', exitCode: null, durationMs: null, counts: counts([]), tests: [] };
  });

  const totals = totalsOf(suites);
  const report = {
    schemaVersion: 1,
    // A report read from what is there is as old as the newest run in it.
    generatedAt: new Date(reading ? (newest ?? began) : Date.now()).toISOString(),
    version: /^version:\s*([^\s+]+)/m.exec(readFileSync(join(ROOT, 'pubspec.yaml'), 'utf8'))?.[1] ?? null,
    commit: git(['rev-parse', '--short', 'HEAD']) || null,
    dirty: git(['status', '--porcelain', '--', '.', `:(exclude)${REPORT_PATH}`]).length > 0,
    sourceHash: source,
    host: { os: `${platform()} ${arch()}`, node: process.version },
    tools,
    ok: suites.every((one) => one.status === 'passed'),
    totals,
    suites,
  };
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, written(report));
  const summary = `${totals.passed} passed, ${totals.failed} failed, ${totals.skipped} skipped${totals.notRun ? `, ${totals.notRun} suite${totals.notRun === 1 ? '' : 's'} not run` : ''}`;
  process.stdout.write(`test report: ${summary} -> ${REPORT_PATH}\n`);
  return report.ok ? 0 : 1;
}

// Run as a command, and not when a test imports it for its readers.
const asked = (() => {
  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
})();
if (asked) process.exit(main());
