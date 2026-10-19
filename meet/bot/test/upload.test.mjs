import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { ApiError } from '../lib/api.mjs';
import { upload } from '../lib/session.mjs';

/** A work directory with a take in it, and an api whose take() answers from `outcomes` in turn. */
function setUp(outcomes) {
  const work = mkdtempSync(join(tmpdir(), 'meet-work-'));
  const audio = join(work, 'm1.webm');
  const captions = join(work, 'm1.captions.ndjson');
  writeFileSync(audio, Buffer.from('sound'));
  writeFileSync(captions, '{"at":0}\n');
  const states = [];
  let takes = 0;
  const api = {
    async take() {
      const outcome = outcomes[takes++];
      if (outcome) throw outcome;
    },
    async state(id, state, detail) {
      states.push([id, state, detail]);
    },
  };
  const ctx = { api, work, stopping: () => false };
  return { work, audio, captions, states, ctx, takes: () => takes, done: () => rmSync(work, { recursive: true, force: true }) };
}

const span = { reason: 'alone', startedAt: 1, endedAt: 2 };

test('a take the server has is deleted here', async (t) => {
  t.mock.method(console, 'log', () => {});
  const s = setUp([]);
  try {
    assert.equal(await upload('m1', { audio: s.audio, captions: s.captions, ...span }, s.ctx), true);
    assert.ok(!existsSync(s.audio) && !existsSync(s.captions));
    assert.deepEqual(s.states, [['m1', 'done', 'alone']]);
  } finally {
    s.done();
  }
});

test('a take of a called-off meeting (409) is deleted too, and nothing is reported', async (t) => {
  t.mock.method(console, 'log', () => {});
  const s = setUp([new ApiError(409, 'x')]);
  try {
    assert.equal(await upload('m1', { audio: s.audio, captions: s.captions, ...span }, s.ctx), false);
    assert.ok(!existsSync(s.audio) && !existsSync(join(s.work, 'failed', 'm1.webm')));
    assert.deepEqual(s.states, []);
  } finally {
    s.done();
  }
});

test('a take that will not go is kept in failed/ and reported failed: upload', async (t) => {
  t.mock.method(console, 'log', () => {});
  const s = setUp([new ApiError(400, 'x')]);
  try {
    assert.equal(await upload('m1', { audio: s.audio, captions: s.captions, ...span }, s.ctx), false);
    assert.equal(s.takes(), 1);
    assert.equal(readFileSync(join(s.work, 'failed', 'm1.webm'), 'utf8'), 'sound');
    assert.ok(existsSync(join(s.work, 'failed', 'm1.captions.ndjson')));
    assert.deepEqual(s.states, [['m1', 'failed', 'upload']]);
  } finally {
    s.done();
  }
});

test('stopping: one try, then kept', async (t) => {
  t.mock.method(console, 'log', () => {});
  const s = setUp([new ApiError(503, 'x'), new ApiError(503, 'x')]);
  try {
    await upload('m1', { audio: s.audio, captions: s.captions, ...span }, { ...s.ctx, stopping: () => true });
    assert.equal(s.takes(), 1);
    assert.ok(existsSync(join(s.work, 'failed', 'm1.webm')));
  } finally {
    s.done();
  }
});
