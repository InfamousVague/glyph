import assert from 'node:assert/strict';
import { test } from 'node:test';
import { FRAME_SAMPLES, Mixer } from '../lib/mixer.mjs';

/** A frame of one value throughout, so a frame's source can be read off its samples. */
const tone = (value, frames = 1) => new Int16Array(FRAME_SAMPLES * frames).fill(value);
const level = (frame) => frame[0];

test('a burst is laid by count, not by its jittery arrivals, and the silence before it is kept', () => {
  const m = new Mixer({ t0: 0 });
  // Five packets, the first at 100 ms, the rest arriving 13 to 27 ms apart.
  const arrivals = [100, 113, 140, 161, 178];
  const frames = arrivals.map((at) => m.place('sam', tone(1000), at));
  assert.deepEqual(frames, [5, 6, 7, 8, 9]);
  const out = m.drain(10_000);
  assert.equal(out.length, Math.floor((10_000 - 400) / 20));
  assert.deepEqual(out.slice(0, 11).map(level), [0, 0, 0, 0, 0, 1000, 1000, 1000, 1000, 1000, 0]);
});

test('a pause starts the count again where the next packet came, and an early rush keeps its count', () => {
  const m = new Mixer({ t0: 0 });
  m.place('sam', tone(1), 0);
  m.place('sam', tone(1), 20);
  // Two seconds quiet: the next packet goes where it came, frame 100, not frame 2.
  assert.equal(m.place('sam', tone(2), 2000), 100);
  // A stall, then three packets at once: laid one after another, none over another.
  assert.equal(m.place('sam', tone(3), 2400), 120, 'more than 200 ms late on its count: placed by the clock');
  assert.equal(m.place('sam', tone(3), 2401), 121);
  assert.equal(m.place('sam', tone(3), 2401), 122);
});

test('two people at once are summed, and clipped to sixteen bits', () => {
  const m = new Mixer({ t0: 0 });
  m.place('sam', tone(20000), 0);
  m.place('ali', tone(20000), 5);
  m.place('sam', tone(-300), 20);
  m.place('ali', tone(100), 25);
  const out = m.finish();
  assert.deepEqual(out.map(level), [32767, -200]);
});

test('a packet for a frame already written is dropped and counted; a long packet fills its frames', () => {
  const m = new Mixer({ t0: 0 });
  m.place('sam', tone(5), 0);
  assert.equal(m.drain(1000).length, 30);
  assert.equal(m.place('ali', tone(7), 100), null, 'frame 5 went out at 500 ms');
  assert.equal(m.late, 1);
  // A 60 ms packet: three frames.
  assert.equal(m.place('sam', tone(9, 3), 2000), 100);
  const out = m.finish();
  assert.equal(out.length, 103 - 30);
  assert.deepEqual(out.slice(-3).map(level), [9, 9, 9]);
});

test('drain writes each frame once, in order, and finish ends at the last voice', () => {
  const m = new Mixer({ t0: 1_000_000 });
  m.place('sam', tone(1), 1_000_040);
  const first = m.drain(1_000_000 + 400 + 60);
  const second = m.drain(1_000_000 + 400 + 60);
  assert.equal(first.length, 3);
  assert.equal(second.length, 0);
  assert.deepEqual(first.map(level), [0, 0, 1]);
  assert.equal(m.finish().length, 0);
});
