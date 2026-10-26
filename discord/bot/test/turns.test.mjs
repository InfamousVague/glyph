import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { SILENCE, Speech, TURNS, ndjson, speakerTurns } from '../lib/turns.mjs';

const names = new Map([
  ['1', 'Sam Lee'],
  ['2', 'Ali'],
  ['3', 'Dana'],
]);
const lag = TURNS.lagMs;

test('the lag matches the device’s caption lag, so a turn lands where the speaking began', () => {
  const dart = readFileSync(fileURLToPath(new URL('../../../lib/meet/speakers.dart', import.meta.url)), 'utf8');
  const said = /const int captionLagMs = (\d+);/.exec(dart);
  assert.ok(said, 'lib/meet/speakers.dart names captionLagMs');
  assert.equal(TURNS.lagMs, Number(said[1]));
});

test('packets make intervals, a quiet longer than the gap ends one, and silence frames are not speech', () => {
  const s = new Speech();
  for (let at = 0; at < 1000; at += 20) s.packet('1', at, 20);
  // Discord's five silence frames as Sam stops: not more speaking.
  for (let at = 1000; at < 1100; at += 20) s.packet('1', at, 20, true);
  // 400 ms quiet, under the gap: the same interval.
  s.packet('1', 1400, 20);
  // 2 s quiet: a new one, and the first closed.
  const closed = s.packet('1', 3420, 20);
  assert.deepEqual(closed, { speaker: '1', start: 0, end: 1420 });
  assert.deepEqual(s.settle(3440 + TURNS.gapMs + 1), [{ speaker: '1', start: 3420, end: 3440 }]);
  assert.deepEqual(s.finish().map((i) => [i.start, i.end]), [[0, 1420], [3420, 3440]]);
  assert.equal(SILENCE.length, 3);
});

test('the floor passes to whoever starts, and back to the talker after an interjection', () => {
  const turns = speakerTurns(
    [
      { speaker: '1', start: 0, end: 10_000 },
      { speaker: '2', start: 4_000, end: 5_000 },
      { speaker: '3', start: 12_000, end: 15_000 },
    ],
    names,
  );
  assert.deepEqual(turns, [
    { at: 0 + lag, speaker: 'Sam Lee', text: '' },
    { at: 4_000 + lag, speaker: 'Ali', text: '' },
    { at: 5_000 + lag, speaker: 'Sam Lee', text: '' },
    { at: 12_000 + lag, speaker: 'Dana', text: '' },
  ]);
});

test('a blip never takes the floor, and one speaker after a pause is one turn', () => {
  const turns = speakerTurns(
    [
      { speaker: '1', start: 0, end: 3_000 },
      { speaker: '2', start: 1_000, end: 1_200 },
      { speaker: '1', start: 5_000, end: 8_000 },
      { speaker: '2', start: 9_000, end: 11_000 },
    ],
    names,
  );
  assert.deepEqual(turns.map((t) => [t.at - lag, t.speaker]), [[0, 'Sam Lee'], [9_000, 'Ali']]);
});

test('overlapping talk: the later starter holds it until they stop, then the one still talking', () => {
  const turns = speakerTurns(
    [
      { speaker: '1', start: 0, end: 6_000 },
      { speaker: '2', start: 2_000, end: 9_000 },
      { speaker: '3', start: 3_000, end: 4_000 },
    ],
    names,
  );
  assert.deepEqual(turns.map((t) => [t.at - lag, t.speaker]), [[0, 'Sam Lee'], [2_000, 'Ali'], [3_000, 'Dana'], [4_000, 'Ali']]);
});

test('someone with no name is "Someone", and the lines are NDJSON', () => {
  const lines = speakerTurns([{ speaker: '9', start: 0, end: 1_000 }], names);
  assert.deepEqual(lines, [{ at: lag, speaker: 'Someone', text: '' }]);
  assert.equal(ndjson(lines), `{"at":${lag},"speaker":"Someone","text":""}\n`);
  assert.deepEqual(speakerTurns([]), []);
});
