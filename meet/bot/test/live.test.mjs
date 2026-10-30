import assert from 'node:assert/strict';
import http from 'node:http';
import { test } from 'node:test';
import { ApiError, createApi } from '../lib/api.mjs';
import { CaptionTimeline } from '../lib/captions.mjs';
import { LINES_A_BATCH, LiveFeed } from '../lib/live.mjs';

/** A feed with a clock the test moves, and a server it answers for. */
function feed({ answer = async () => {}, keepMost } = {}) {
  let now = 0;
  const sent = [];
  const logged = [];
  const live = new LiveFeed({
    send: async (batch) => {
      sent.push(structuredClone(batch));
      await answer(batch);
    },
    startedAt: 1_792_159_500_000,
    now: () => now,
    keepMost,
    log: (event, fields) => logged.push({ event, ...fields }),
  });
  return { live, sent, logged, tick: (ms) => (now += ms), settle: () => live.inFlight ?? Promise.resolve() };
}

const line = (at, speaker, text) => ({ at, speaker, text });

test('lines go once each, in batches at most every second and a half, with the line being said', async () => {
  const { live, sent, tick, settle } = feed();
  live.heard([line(4000, 'Sam Lee', 'Good morning everyone.')], line(6000, 'Daniel', 'Thanks'));
  await settle();
  assert.deepEqual(sent, [{ startedAt: 1_792_159_500_000, lines: [line(4000, 'Sam Lee', 'Good morning everyone.')], partial: line(6000, 'Daniel', 'Thanks') }]);
  // Within the gap: kept for the next batch.
  tick(500);
  live.heard([line(6000, 'Daniel', 'Thanks. The pricing page is drafted.')], null);
  await settle();
  assert.equal(sent.length, 1);
  tick(1000);
  live.heard([], null);
  await settle();
  assert.deepEqual(sent[1], { startedAt: 1_792_159_500_000, lines: [line(6000, 'Daniel', 'Thanks. The pricing page is drafted.')], partial: null });
  // Nothing new, and the line being said the same: nothing goes.
  tick(2000);
  live.heard([], null);
  await settle();
  assert.equal(sent.length, 2);
  // The line being said, changed alone, goes alone.
  tick(2000);
  live.heard([], line(9000, 'Sam Lee', 'and the'));
  await settle();
  assert.deepEqual(sent[2].lines, []);
  assert.deepEqual(sent[2].partial, line(9000, 'Sam Lee', 'and the'));
});

test('a batch never waits on the last, and the lines it could not send go with the next', async () => {
  let release;
  const { live, sent, tick, settle } = feed({ answer: () => new Promise((r) => (release = r)) });
  live.heard([line(1, 'A', 'one')], null);
  tick(5000);
  live.heard([line(2, 'A', 'two')], null);
  assert.equal(sent.length, 1, 'one in flight at a time');
  release();
  await settle();
  tick(5000);
  live.heard([], null);
  release?.();
  await settle();
  assert.deepEqual(sent[1].lines, [line(2, 'A', 'two')]);
});

test('a failure keeps the lines, a 429 waits longer, and 404 or 409 turn the feed off for the call', async () => {
  let failWith = 500;
  const { live, sent, logged, tick, settle } = feed({ answer: async () => {
    if (failWith) throw new ApiError(failWith, 'no');
  } });
  live.heard([line(1, 'A', 'one')], null);
  await settle();
  tick(1500);
  live.heard([line(2, 'A', 'two')], null);
  await settle();
  assert.deepEqual(sent[1].lines, [line(1, 'A', 'one'), line(2, 'A', 'two')], 'kept through the failure');
  failWith = 429;
  tick(1500);
  live.heard([], null);
  await settle();
  const before = sent.length;
  tick(1500);
  live.heard([], null);
  await settle();
  assert.equal(sent.length, before, 'past the pace: waits a gap more');
  failWith = 404;
  tick(5000);
  live.heard([], null);
  await settle();
  assert.equal(live.off, true);
  assert.deepEqual(logged, [{ event: 'live_off', status: 404 }]);
  const after = sent.length;
  tick(5000);
  live.heard([line(3, 'A', 'three')], null);
  await settle();
  await live.end();
  assert.equal(sent.length, after, 'off for the rest of the call');
  assert.ok(!JSON.stringify(logged).includes('three'), 'no word in the log');
});

test('so many lines a batch, so many kept while the server is away, and the end sends what is left', async () => {
  let failing = true;
  const { live, sent, tick, settle } = feed({ keepMost: 250, answer: async () => {
    if (failing) throw new ApiError(0, 'down');
  } });
  for (let n = 0; n < 300; n++) live.heard([line(n, 'A', `line ${n}`)], null);
  await settle();
  failing = false;
  tick(1500);
  live.heard([], line(400, 'A', 'still saying'));
  await settle();
  const last = sent.at(-1);
  assert.equal(last.lines.length, LINES_A_BATCH);
  assert.equal(last.lines[0].text, 'line 50', 'the oldest went past the room');
  await live.end();
  const ended = sent.at(-1);
  assert.equal(ended.partial, null, 'the end says nothing is being said');
  assert.equal(ended.lines.at(-1).text, 'line 299');
  assert.equal(live.pending.length, 0);
});

test('the timeline says the line being said: the block still changing, its words not yet written', () => {
  const timeline = new CaptionTimeline();
  assert.equal(timeline.saying(), null);
  timeline.update(['Sam Lee\nGood morning'], 1000);
  assert.deepEqual(timeline.saying(), { at: 1000, speaker: 'Sam Lee', text: 'Good morning' });
  timeline.update(['Sam Lee\nGood morning everyone'], 1500);
  assert.deepEqual(timeline.saying(), { at: 1000, speaker: 'Sam Lee', text: 'Good morning everyone' });
  // Quiet long enough: finished, written, and nothing is being said.
  const finished = timeline.update(['Sam Lee\nGood morning everyone'], 4000);
  assert.equal(finished.length, 1);
  assert.equal(timeline.saying(), null);
  // The same block grows again: only its new words are being said.
  timeline.update(['Sam Lee\nGood morning everyone. Let us start'], 4500);
  assert.equal(timeline.saying().text, 'Let us start');
});

test('live: a JSON batch to the meeting live route, five seconds at most, its id kept out of errors', async () => {
  const seen = [];
  const server = http.createServer((req, res) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      seen.push({ method: req.method, path: req.url, body: Buffer.concat(chunks).toString() });
      res.writeHead(seen.length === 1 ? 204 : 409);
      res.end();
    });
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  try {
    const api = createApi({ base: `http://127.0.0.1:${server.address().port}`, token: 'meet-bot-test-token-0123456789abcdef0123456789' });
    await api.live('m1', { startedAt: 5, lines: [line(1, 'A', 'hi')], partial: null });
    assert.equal(seen[0].path, '/api/internal/meet/m1/live');
    assert.deepEqual(JSON.parse(seen[0].body), { startedAt: 5, lines: [line(1, 'A', 'hi')], partial: null });
    const refused = await api.live('secret-id', { lines: [] }).catch((e) => e);
    assert.equal(refused.status, 409);
    assert.ok(refused.over);
    assert.ok(!refused.message.includes('secret-id'), refused.message);
  } finally {
    server.close();
  }
});
