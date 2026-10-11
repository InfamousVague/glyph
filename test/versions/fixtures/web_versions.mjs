// What the web app's own versions modules answer, written down for test/versions/parity_test.dart to hold the Dart
// port to. Reads tauri/ and writes nothing there:
//
//   node --experimental-strip-types test/versions/fixtures/web_versions.mjs > test/versions/fixtures/web_versions.json
//
// A seeded generator, so the file is the same from run to run until the web's modules change.
import { diffLines, linesOf, firstChange } from '../../../tauri/src/app/core/versions/diff.ts';
import { hashText, mergeFiles, readFile, withVersion, writeFile } from '../../../tauri/src/app/core/versions/file.ts';

let seed = 20261007;
const random = () => {
  seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
  return seed / 4294967296;
};
const pick = (list) => list[Math.floor(random() * list.length)];
const LINES = ['# Plan', '', '- book the venue', '- book the venue (done)', '  =3 looks like a keep', '  +looks like an add', '  -looks like a del', 'v9 2026-10-04T15:20:01.000Z matt 3f9a21c0', '# note other', 'naïve café 🥛', 'tab\there', 'a "quoted" \\ line', 'x', 'y', 'z', 'x', ' leading', 'trailing '];
const text = () => Array.from({ length: Math.floor(random() * 9) }, () => pick(LINES)).join('\n') + (random() < 0.4 ? '\n' : '');
const edit = (was) => {
  const lines = linesOf(was);
  for (let i = 0, n = 1 + Math.floor(random() * 3); i < n; i += 1) {
    const at = Math.floor(random() * (lines.length + 1));
    const roll = random();
    if (roll < 0.4) lines.splice(at, 0, pick(LINES));
    else if (roll < 0.7) lines.splice(at, 1);
    else lines.splice(at, 1, pick(LINES));
  }
  return lines.join('\n');
};
const HANDLES = ['matt', 'sam', 'Matt', 'me', 'two words', 'a.b', 'a-b', 'a_b', 'kit9', ''];
const LABELS = [undefined, undefined, undefined, 'Before the review', 'say "hi" \\ there', '  spaced  ', 'ünï 🥛', '   '];
const summary = (file) => {
  const read = file ? readFile(file) : null;
  return read && { noteId: read.noteId, damaged: read.damaged, versions: read.versions.map(({ text: words, ...rest }) => ({ ...rest, label: rest.label ?? null, text: words })) };
};

const diffs = [];
for (let i = 0; i < 60; i += 1) {
  const before = text();
  const after = random() < 0.5 ? edit(before) : text();
  // The first change is asked against the version before, or against nothing, as for a note's first version.
  const firstBefore = random() < 0.2 ? null : before;
  diffs.push({ before, after, steps: diffLines(linesOf(before), linesOf(after)), firstBefore, first: firstChange(firstBefore, after) });
}
const hashes = ['', 'a', 'foobar', 'naïve café 🥛', '# Launch plan\n- book the venue\n', '\u{1F47B}\uD83D', 'x'.repeat(5000)].map((t) => ({ text: t, hash: hashText(t) }));

const histories = [];
for (let i = 0; i < 24; i += 1) {
  let file = null;
  const kept = [];
  let words = text();
  let at = 1_700_000_000_000 + i * 86_400_000;
  for (let step = 0, n = 2 + Math.floor(random() * 8); step < n; step += 1) {
    const entry = { text: words, at, by: pick(HANDLES), label: pick(LABELS) ?? null };
    const next = withVersion(file, `n-${i}`, entry.text, { at: entry.at, by: entry.by, ...(entry.label ? { label: entry.label } : {}) });
    kept.push({ ...entry, file: next });
    file = next ?? file;
    if (random() < 0.8) words = edit(words);
    at += Math.floor(random() * 3) * 60_000;
  }
  histories.push({ noteId: `n-${i}`, kept, read: summary(file) });
}

const merges = [];
for (let i = 0; i < 16; i += 1) {
  const branch = (base, who) => {
    let file = base;
    let words = text();
    for (let step = 0, n = Math.floor(random() * 5); step < n; step += 1) {
      file = withVersion(file, 'm', words, { at: 1_700_000_000_000 + Math.floor(random() * 4) * 1000, by: pick(who), ...(random() < 0.3 ? { label: pick(['One', 'Two']) } : {}) }) ?? file;
      words = edit(words);
    }
    return file;
  };
  const base = random() < 0.3 ? null : branch(null, ['matt']);
  const mine = branch(base, ['matt', 'Matt', 'a.b']);
  const theirs = branch(base, ['sam', 'a-b', 'matt']);
  const merged = mergeFiles(mine, theirs, 'm');
  merges.push({ mine, theirs, merged, back: mergeFiles(theirs, mine, 'm'), read: summary(merged) });
}

const many = writeFile('big', Array.from({ length: 130 }, (_, i) => ({ at: i * 1000, by: 'matt', text: `line ${i}\nsame\n${i % 7}` })));
const sorted = ['a-b', 'a.b', 'a_b', 'a1', 'aa', 'a9', 'B', 'a', 'Matt', 'matt', 'sam', 'ab', 'abc', 'me', 'kit9', 'two-words', '0f3a', 'ff00', '3f9a21c0', '8c0d4e11', 'n-1', 'n-10', 'n-2', 'c0ffee00-1111-4222-8333-444455556666', 'c0ffee00-1111-4222-8333-444455556667'].sort((x, y) => x.localeCompare(y));

process.stdout.write(`${JSON.stringify({ diffs, hashes, histories, merges, many, sorted })}\n`);
