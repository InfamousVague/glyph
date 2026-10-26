// The take's container (lib/webm.mjs) read back by a small EBML reader of the tests' own, element by element, as the
// device's (lib/meet/webm.dart) reads it; and a real call's worth of Opus written through the whole recorder, decoded
// again, to find each voice where it was spoken. With GHOST_WRITE_FIXTURE=1 it also writes the file the device's own
// test reads (test/meet/fixtures/discord_mix.webm, test/meet/webm_test.dart), so the two readers are held to one file.
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import OpusScript from 'opusscript';
import { opusCodec } from '../lib/codec.mjs';
import { FRAME_SAMPLES } from '../lib/mixer.mjs';
import { Recorder } from '../lib/recorder.mjs';
import { WebmOpusWriter, opusHead, vsize } from '../lib/webm.mjs';

/** An EBML variable-length integer at `at`: its value (marker off, or kept for an id) and its length. */
function vint(bytes, at, keepMarker) {
  const first = bytes[at];
  let length = 1;
  while (length <= 8 && !(first & (0x80 >> (length - 1)))) length += 1;
  let value = keepMarker ? first : first & (0xff >> length);
  for (let i = 1; i < length; i += 1) value = value * 256 + bytes[at + i];
  const unknown = !keepMarker && value === 2 ** (7 * length) - 1;
  return { value, length, unknown };
}

const CONTAINERS = new Set([0x1a45dfa3, 0x18538067, 0x1549a966, 0x1654ae6b, 0xae, 0xe1, 0x1f43b675]);

/** Every element, flat, as `{ id, at, size, body }`, containers entered (the device's walk). */
function elements(bytes) {
  const out = [];
  let at = 0;
  while (at < bytes.length) {
    const id = vint(bytes, at, true);
    const size = vint(bytes, at + id.length, false);
    const start = at + id.length + size.length;
    const end = size.unknown ? bytes.length : start + size.value;
    out.push({ id: id.value, at, size: size.unknown ? null : size.value, body: bytes.subarray(start, end) });
    at = CONTAINERS.has(id.value) ? start : end;
  }
  return out;
}

const uintOf = (body) => body.reduce((v, b) => v * 256 + b, 0);

/** The blocks with their times in ms: each cluster's timecode plus the block's own. */
function blocks(bytes) {
  let cluster = 0;
  const out = [];
  for (const e of elements(bytes)) {
    if (e.id === 0xe7) cluster = uintOf(e.body);
    if (e.id === 0xa3) {
      assert.equal(e.body[0], 0x81, 'track 1');
      assert.equal(e.body[3] & 0x80, 0x80, 'a keyframe');
      out.push({ at: cluster + e.body.readInt16BE(1), packet: e.body.subarray(4) });
    }
  }
  return out;
}

test('sizes are the fewest bytes, never the all-ones that means unknown', () => {
  assert.deepEqual(vsize(0), [0x80]);
  assert.deepEqual(vsize(126), [0xfe]);
  assert.deepEqual(vsize(127), [0x40, 0x7f], '127 in one byte would be all ones');
  assert.deepEqual(vsize(300), [0x41, 0x2c]);
});

test('the header, the Opus track and five-second clusters, read back element by element', () => {
  const pieces = [];
  const w = new WebmOpusWriter({ write: (b) => pieces.push(Buffer.from(b)), clusterMs: 100 });
  w.start();
  for (let i = 0; i < 12; i += 1) w.packet(Buffer.from([0xf8, i]));
  w.end();
  const bytes = Buffer.concat(pieces);
  const all = elements(bytes);
  const find = (id) => all.find((e) => e.id === id);
  assert.equal(find(0x4282).body.toString(), 'webm');
  assert.equal(find(0x18538067).size, null, 'a Segment of unknown size, as a live recording has');
  assert.equal(uintOf(find(0x2ad7b1).body), 1_000_000, 'a millisecond timecode scale');
  assert.equal(find(0x86).body.toString(), 'A_OPUS');
  assert.deepEqual(find(0x63a2).body, opusHead(1, 312));
  assert.equal(uintOf(find(0x56aa).body), 6_500_000, '312 samples of codec delay, in ns');
  assert.equal(uintOf(find(0x9f).body), 1, 'mono');
  assert.equal(find(0xb5).body.readFloatBE(0), 48_000);
  // A cluster every 100 ms here: five packets each, the last one short, each written whole with its size.
  const clusters = all.filter((e) => e.id === 0x1f43b675);
  assert.deepEqual(clusters.map((c) => c.size != null), [true, true, true]);
  const read = blocks(bytes);
  assert.deepEqual(read.map((b) => b.at), Array.from({ length: 12 }, (_, i) => i * 20));
  assert.deepEqual(read.map((b) => b.packet[1]), Array.from({ length: 12 }, (_, i) => i));
  // Nothing is written before a cluster is full: a crash loses at most the one being filled.
  const early = [];
  const w2 = new WebmOpusWriter({ write: (b) => early.push(b), clusterMs: 100 });
  w2.start();
  for (let i = 0; i < 4; i += 1) w2.packet(Buffer.from([0xf8]));
  assert.equal(early.length, 1, 'the header alone');
});

/** A tone of `hz` for `ms` at `amp`, as 20 ms packets of Opus from an encoder of the speaker's own. */
function spoken(hz, ms, amp = 8000) {
  const encoder = new OpusScript(48_000, 1, OpusScript.Application.VOIP);
  const packets = [];
  for (let f = 0; f < ms / 20; f += 1) {
    const pcm = new Int16Array(FRAME_SAMPLES);
    for (let i = 0; i < FRAME_SAMPLES; i += 1) pcm[i] = Math.round(amp * Math.sin((2 * Math.PI * hz * (f * FRAME_SAMPLES + i)) / 48_000));
    packets.push(encoder.encode(Buffer.from(pcm.buffer), FRAME_SAMPLES));
  }
  encoder.delete();
  return packets;
}

/** The loudness of each 100 ms of `pcm`. */
function loudness(pcm) {
  const out = [];
  for (let from = 0; from + 4800 <= pcm.length; from += 4800) {
    let sum = 0;
    for (let i = from; i < from + 4800; i += 1) sum += pcm[i] * pcm[i];
    out.push(Math.sqrt(sum / 4800));
  }
  return out;
}

test('a call through the whole recorder: each voice is heard where it spoke, and silence between', () => {
  const dir = mkdtempSync(join(tmpdir(), 'discord-rec-'));
  try {
    const audioPath = join(dir, 'm.webm');
    const speechPath = join(dir, 'm.speech.ndjson');
    const t0 = 1_000_000;
    const rec = new Recorder({ audioPath, speechPath, t0, codec: opusCodec() });
    // Sam from 0.5 s to 1.5 s, Ali from 2.5 s to 3.0 s, each packet arriving with a little jitter; ticks between.
    const sam = spoken(440, 1000);
    const ali = spoken(660, 500);
    const events = [
      ...sam.map((p, i) => ({ at: t0 + 500 + i * 20 + (i % 3) * 4, who: '1', p })),
      ...ali.map((p, i) => ({ at: t0 + 2500 + i * 20 + (i % 2) * 6, who: '2', p })),
    ].sort((a, b) => a.at - b.at);
    let now = t0;
    for (const e of events) {
      while (now + 100 <= e.at) {
        now += 100;
        rec.tick(now);
      }
      rec.packet(e.who, e.p, e.at);
    }
    rec.tick(t0 + 4000);
    const result = rec.stop();
    assert.equal(result.speakers, 2);
    assert.equal(result.late, 0);
    assert.deepEqual(result.intervals.map((i) => [i.speaker, i.start, i.end]), [['1', 500, 1500], ['2', 2500, 3000]]);
    assert.equal(readFileSync(speechPath, 'utf8').trim().split('\n').length, 2, 'each interval kept as it closed');

    const bytes = readFileSync(audioPath);
    const read = blocks(bytes);
    assert.ok(read.length >= 175 && read.length <= 200, `${read.length} packets for 3.5 s and more`);
    assert.deepEqual(read.map((b) => b.at), read.map((_, i) => i * 20), 'one packet every 20 ms, no gaps');
    // Decoded again, as the device's decoder will: loud where each spoke, quiet elsewhere (the codec's delay of a
    // few ms is inside a 100 ms window's slack).
    const decoder = new OpusScript(48_000, 1);
    const pcm = [];
    for (const b of read) {
      const out = decoder.decode(b.packet);
      for (let i = 0; i < out.length / 2; i += 1) pcm.push(out.readInt16LE(i * 2));
    }
    decoder.delete();
    const loud = loudness(pcm).map((l) => l > 1000);
    const expect = loud.map((_, w) => (w >= 5 && w < 15) || (w >= 25 && w < 30));
    const wrong = loud.map((l, w) => (l === expect[w] || w === 5 || w === 15 || w === 25 || w === 30 ? null : w)).filter((w) => w != null);
    assert.deepEqual(wrong, [], `windows heard wrongly: ${wrong}`);
    if (process.env.GHOST_WRITE_FIXTURE === '1') {
      writeFileSync(fileURLToPath(new URL('../../../test/meet/fixtures/discord_mix.webm', import.meta.url)), bytes);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('the device’s fixture is this writer’s, read back the same', () => {
  const bytes = readFileSync(fileURLToPath(new URL('../../../test/meet/fixtures/discord_mix.webm', import.meta.url)));
  const read = blocks(bytes);
  assert.ok(read.length > 150);
  assert.deepEqual(read.map((b) => b.at), read.map((_, i) => i * 20));
});
