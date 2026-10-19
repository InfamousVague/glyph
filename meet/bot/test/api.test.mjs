import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import http from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { ApiError, createApi, withRetry } from '../lib/api.mjs';

/*
 * A tiny stand-in for glyph-api's internal routes: it writes down every request (method, path, headers, body) and
 * answers from `answers`, a queue per "METHOD path", or 200 `{}`.
 */
const TOKEN = 'meet-bot-test-token-0123456789abcdef0123456789';
const seen = [];
const answers = new Map();
let server;
let base;

before(async () => {
  server = http.createServer((req, res) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      seen.push({ method: req.method, path: req.url, headers: req.headers, body: Buffer.concat(chunks) });
      const queue = answers.get(`${req.method} ${req.url}`) ?? [];
      const [status, body] = queue.shift() ?? [200, {}];
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(body));
    });
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => server.close());

const reset = () => {
  seen.length = 0;
  answers.clear();
};

test('due: the bearer token, no proxy headers, the meetings', async () => {
  reset();
  const meetings = [{ id: 'm1', url: 'https://meet.google.com/abc-defg-hij', title: 'T', startsAt: 1, endsAt: 2, state: 'booked', announce: 'hi' }];
  answers.set('GET /api/internal/meet/due', [[200, { meetings }]]);
  const api = createApi({ base, token: TOKEN });
  assert.deepEqual(await api.due(), meetings);
  assert.equal(seen[0].headers.authorization, `Bearer ${TOKEN}`);
  assert.ok(!Object.keys(seen[0].headers).some((h) => /forwarded|real-ip/i.test(h)));
});

test('state: JSON with a detail when there is one', async () => {
  reset();
  const api = createApi({ base, token: TOKEN });
  await api.state('m1', 'in_call');
  await api.state('m1', 'failed', 'signed_out');
  assert.equal(seen[0].path, '/api/internal/meet/m1/state');
  assert.equal(seen[0].headers['content-type'], 'application/json');
  assert.deepEqual(JSON.parse(seen[0].body), { state: 'in_call' });
  assert.deepEqual(JSON.parse(seen[1].body), { state: 'failed', detail: 'signed_out' });
});

test('state: a 409 is the meeting over, not worth retrying; a 401 is a wrong token', async () => {
  reset();
  answers.set('POST /api/internal/meet/m1/state', [[409, { error: 'x', id: 'm1', state: 'leave' }], [401, { error: 'x' }]]);
  const api = createApi({ base, token: TOKEN });
  const conflict = await api.state('m1', 'joining').catch((e) => e);
  assert.ok(conflict instanceof ApiError);
  assert.equal(conflict.status, 409);
  assert.ok(conflict.over);
  assert.ok(!conflict.retryable);
  const wrong = await api.state('m1', 'joining').catch((e) => e);
  assert.equal(wrong.status, 401);
  assert.ok(!wrong.over);
  // No error body in the message: it reaches the log.
  assert.ok(!/error/.test(wrong.message.replace(/answered/, '')));
});

test('take: multipart with audio, captions and the span, streamed with its length', async () => {
  reset();
  const dir = mkdtempSync(join(tmpdir(), 'meet-take-'));
  try {
    const audio = join(dir, 'm1.webm');
    const captions = join(dir, 'm1.captions.ndjson');
    const sound = Buffer.from([0x1a, 0x45, 0xdf, 0xa3, 0, 1, 2, 3, 255, 13, 10]);
    writeFileSync(audio, sound);
    writeFileSync(captions, '{"at":0,"speaker":"Alice","text":"Hi"}\n');
    const api = createApi({ base, token: TOKEN });
    await api.take('m1', { audio, captions, startedAt: 1000, endedAt: 2000.4 });
    const req = seen[0];
    assert.equal(req.method, 'PUT');
    assert.equal(req.path, '/api/internal/meet/m1/take');
    assert.equal(Number(req.headers['content-length']), req.body.length);
    const boundary = /boundary=(.+)$/.exec(req.headers['content-type'])[1];
    const parts = parseMultipart(req.body, boundary);
    assert.deepEqual(Object.keys(parts).sort(), ['audio', 'captions', 'endedAt', 'startedAt']);
    assert.ok(parts.audio.body.equals(sound));
    assert.match(parts.audio.headers, /Content-Type: audio\/webm/);
    assert.match(parts.captions.headers, /Content-Type: application\/x-ndjson/);
    assert.equal(parts.captions.body.toString(), '{"at":0,"speaker":"Alice","text":"Hi"}\n');
    assert.equal(parts.startedAt.body.toString(), '1000');
    assert.equal(parts.endedAt.body.toString(), '2000');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('take: a missing file is an empty part', async () => {
  reset();
  const api = createApi({ base, token: TOKEN });
  await api.take('m2', { audio: '/nonexistent/a.webm', captions: null });
  const boundary = /boundary=(.+)$/.exec(seen[0].headers['content-type'])[1];
  const parts = parseMultipart(seen[0].body, boundary);
  assert.equal(parts.audio.body.length, 0);
  assert.equal(parts.startedAt, undefined);
});

test('retry: server errors and no answer are tried again, five times at most; a 4xx is not', async () => {
  reset();
  answers.set('PUT /api/internal/meet/m1/take', [[503, {}], [500, {}], [200, { take: 't', size: 1 }]]);
  const api = createApi({ base, token: TOKEN });
  const waits = [];
  const sleep = async (ms) => waits.push(ms);
  await withRetry(() => api.take('m1', { audio: null, captions: null }), { sleep });
  assert.deepEqual(waits, [2000, 6000]);
  assert.equal(seen.length, 3);

  reset();
  answers.set('PUT /api/internal/meet/m1/take', Array.from({ length: 9 }, () => [502, {}]));
  waits.length = 0;
  const gaveUp = await withRetry(() => api.take('m1', { audio: null, captions: null }), { sleep }).catch((e) => e);
  assert.equal(gaveUp.status, 502);
  assert.equal(seen.length, 5);
  assert.deepEqual(waits, [2000, 6000, 18000, 54000]);

  reset();
  answers.set('PUT /api/internal/meet/m1/take', [[400, {}]]);
  const bad = await withRetry(() => api.take('m1', { audio: null, captions: null }), { sleep }).catch((e) => e);
  assert.equal(bad.status, 400);
  assert.equal(seen.length, 1);

  const dead = createApi({ base: 'http://127.0.0.1:1', token: TOKEN });
  let tries = 0;
  const refused = await withRetry(() => (tries++, dead.due()), { sleep, tries: 2 }).catch((e) => e);
  assert.equal(refused.status, 0);
  assert.equal(tries, 2);
});

test('no token, no client', () => {
  assert.throws(() => createApi({ base, token: '' }), /GLYPH_MEET_TOKEN/);
});

function parseMultipart(body, boundary) {
  const parts = {};
  const text = body.toString('latin1');
  for (const chunk of text.split(`--${boundary}`).slice(1)) {
    if (chunk.startsWith('--')) break;
    const split = chunk.indexOf('\r\n\r\n');
    const headers = chunk.slice(2, split);
    const name = /name="([^"]+)"/.exec(headers)[1];
    parts[name] = { headers, body: Buffer.from(chunk.slice(split + 4, -2), 'latin1') };
  }
  return parts;
}
