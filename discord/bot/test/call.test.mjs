// One call's decisions and its end (lib/call.mjs): when to leave, by the Meet bot's rules over Discord's exact count;
// the take handed over and deleted, kept aside when it will not go, deleted when the call was called off; a call in
// which nobody was heard reported as such, with no take; and the speaker turns written with the names put on.
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { ApiError } from '../lib/api.mjs';
import { Call, NOBODY, presence, upload, whyLeave } from '../lib/call.mjs';
import { LIMITS } from '../../../meet/bot/lib/decide.mjs';

const MIN = 60_000;

/** The presence after a run of counts, one every 5 s from `from`. */
function counted(counts, from = 0) {
  let p = NOBODY;
  counts.forEach((count, i) => {
    p = presence(p, count, from + i * 5000);
  });
  return p;
}

test('alone for two minutes: leave; someone back before then: stay', () => {
  const p = counted([2, 2, 1]);
  assert.equal(p.aloneSince, 10_000);
  assert.equal(whyLeave(p, { now: 10_000 + 2 * MIN - 1, joinedAt: 0 }), null);
  assert.equal(whyLeave(p, { now: 10_000 + 2 * MIN, joinedAt: 0 }), 'alone');
  assert.equal(presence(p, 2, 20_000).aloneSince, null);
});

test('after a big group, down to Ghost and one more for two minutes: leave', () => {
  const p = counted([3, 5, 4, 2]);
  assert.equal(p.peak, 5);
  assert.equal(whyLeave(p, { now: 15_000 + 2 * MIN, joinedAt: 0 }), 'few_left');
  // Never a big group: two people may talk for as long as they like.
  const pair = counted([2, 2, 2]);
  assert.equal(whyLeave(pair, { now: 2 * 60 * MIN, joinedAt: 0 }), null);
});

test('three hours in, asked, told by the device, put out, or the service stopping', () => {
  const p = counted([2]);
  assert.equal(whyLeave(p, { now: LIMITS.maxMs, joinedAt: 0 }), 'time_up');
  assert.equal(whyLeave(p, { now: 1, joinedAt: 0, asked: 'asked' }), 'asked');
  assert.equal(whyLeave(p, { now: 1, joinedAt: 0, serverLeave: true }), 'asked_to_leave');
  assert.equal(whyLeave(p, { now: 1, joinedAt: 0, ended: 'removed' }), 'removed');
  assert.equal(whyLeave(p, { now: 1, joinedAt: 0, stopping: true }), 'shutdown');
});

/** A work directory with a take in it, and an api whose take() answers from `outcomes` in turn. */
function setUp(outcomes = []) {
  const work = mkdtempSync(join(tmpdir(), 'discord-work-'));
  const audio = join(work, 'c1.webm');
  const captions = join(work, 'c1.captions.ndjson');
  writeFileSync(audio, Buffer.from('sound'));
  writeFileSync(captions, '{"at":1000}\n');
  const states = [];
  const takes = [];
  const api = {
    async take(id, files) {
      takes.push([id, { ...files, captionsText: readFileSync(files.captions, 'utf8') }]);
      const outcome = outcomes[takes.length - 1];
      if (outcome) throw outcome;
    },
    async state(id, state, detail) {
      states.push([id, state, detail]);
    },
    async due() {
      return [];
    },
  };
  return { work, audio, captions, states, takes, api, done: () => rmSync(work, { recursive: true, force: true }) };
}

const quiet = () => {};

test('a take the server has is deleted here, and done posted with why', async () => {
  const s = setUp();
  try {
    assert.equal(await upload('c1', { audio: s.audio, captions: s.captions, reason: 'alone', startedAt: 1, endedAt: 2 }, { api: s.api, work: s.work, stopping: () => false }, quiet), true);
    assert.ok(!existsSync(s.audio) && !existsSync(s.captions));
    assert.deepEqual(s.states, [['c1', 'done', 'alone']]);
  } finally {
    s.done();
  }
});

test('a take of a call called off (409) is deleted too; one that will not go is kept in failed/', async () => {
  const off = setUp([new ApiError(409, 'x')]);
  try {
    assert.equal(await upload('c1', { audio: off.audio, captions: off.captions }, { api: off.api, work: off.work, stopping: () => false }, quiet), false);
    assert.ok(!existsSync(off.audio) && !existsSync(join(off.work, 'failed', 'c1.webm')));
    assert.deepEqual(off.states, []);
  } finally {
    off.done();
  }
  const bad = setUp([new ApiError(400, 'x')]);
  try {
    await upload('c1', { audio: bad.audio, captions: bad.captions }, { api: bad.api, work: bad.work, stopping: () => false }, quiet);
    assert.ok(existsSync(join(bad.work, 'failed', 'c1.webm')) && existsSync(join(bad.work, 'failed', 'c1.captions.ndjson')));
    assert.deepEqual(bad.states, [['c1', 'failed', 'upload']]);
  } finally {
    bad.done();
  }
});

/** A codec that decodes a packet to a frame of its first byte, and encodes a frame to its first sample. */
const fakeCodec = {
  decoder: () => ({ decode: (p) => new Int16Array(960).fill(p[0]) }),
  encoder: () => ({ encode: (pcm) => Buffer.from([0xf8, pcm[0] & 0xff]) }),
};

test('a call: the turns named and uploaded with the mix; nobody heard is no take at all', async () => {
  const s = setUp();
  try {
    const ctx = { api: s.api, work: s.work, codec: fakeCodec, stopping: () => false, log: quiet };
    const call = new Call({ meeting: { id: 'c2' }, forName: 'Sam', guildId: 'g', channelId: 'v', requester: '1', ctx });
    call.start(0);
    call.name('1', 'Sam Lee');
    call.name('2', 'Ali');
    for (let at = 0; at < 2000; at += 20) call.packet('1', Buffer.from([10]), at);
    for (let at = 3000; at < 4000; at += 20) call.packet('2', Buffer.from([20]), at);
    call.counted(3, 0);
    call.stop('asked');
    assert.equal(await call.tick(5000), 'asked');
    assert.equal(await call.finish(6000), true);
    const [[id, files]] = s.takes;
    assert.equal(id, 'c2');
    assert.deepEqual(files.captionsText.trim().split('\n').map((l) => JSON.parse(l)), [
      { at: 1000, speaker: 'Sam Lee', text: '' },
      { at: 4000, speaker: 'Ali', text: '' },
    ]);
    assert.deepEqual([files.startedAt, files.endedAt], [0, 6000]);
    assert.deepEqual(s.states, [['c2', 'done', 'asked']]);
    assert.ok(!existsSync(join(s.work, 'c2.webm')) && !existsSync(join(s.work, 'c2.speech.ndjson')), 'nothing of it left here');

    const silent = new Call({ meeting: { id: 'c3' }, forName: 'Sam', guildId: 'g', channelId: 'v', requester: '1', ctx });
    silent.start(0);
    // Only Discord's silence frames: nobody spoke.
    for (let at = 0; at < 100; at += 20) silent.packet('1', Buffer.from([0xf8, 0xff, 0xfe]), at);
    silent.stop('removed');
    await silent.tick(1000);
    assert.equal(await silent.finish(1000), false);
    assert.deepEqual(s.states.at(-1), ['c3', 'failed', 'nothing_heard']);
    assert.equal(s.takes.length, 1);
    assert.ok(!existsSync(join(s.work, 'c3.webm')));
  } finally {
    s.done();
  }
});
