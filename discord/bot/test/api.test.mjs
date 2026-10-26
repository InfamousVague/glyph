// The bot's client of glyph-api's internal Discord routes (lib/api.mjs), against a stand-in that writes down every
// request: the paths, the token, no proxy headers, the take's multipart; and what `/ghost link` and `/ghost join` come
// to for each answer the service can give (linked or not, the plugin's switch on or off) - the link flow end to end,
// from the bot's side.
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import http from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';
import { createDiscordApi, openCall, redeemCode } from '../lib/api.mjs';
import { CALLS_OFF, HOW_TO_LINK, linkReply, refusedJoin } from '../lib/words.mjs';

const TOKEN = 'discord-bot-test-token-0123456789abcdef01234567';
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
      const [status, body] = (answers.get(`${req.method} ${req.url}`) ?? []).shift() ?? [200, {}];
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

test('no token, no client', () => {
  assert.throws(() => createDiscordApi({ base: 'http://127.0.0.1:9' }), /GLYPH_DISCORD_TOKEN is not set/);
});

test('the routes are the Discord ones, with the bearer token and no proxy headers', async () => {
  reset();
  const api = createDiscordApi({ base, token: TOKEN });
  answers.set('GET /api/internal/discord/due', [[200, { meetings: [{ id: 'c1', state: 'leave' }] }]]);
  assert.deepEqual(await api.due(), [{ id: 'c1', state: 'leave' }]);
  await api.state('c1', 'in_call');
  await api.link({ code: 'K7QM-2XRP', user: '111111111111111111', name: 'sam' });
  await api.open({ user: '111111111111111111', guild: '2', channel: '3', title: 'Standup in HQ' });
  assert.deepEqual(seen.map((s) => `${s.method} ${s.path}`), [
    'GET /api/internal/discord/due',
    'POST /api/internal/discord/c1/state',
    'POST /api/internal/discord/link',
    'POST /api/internal/discord/session',
  ]);
  for (const s of seen) {
    assert.equal(s.headers.authorization, `Bearer ${TOKEN}`);
    assert.ok(!Object.keys(s.headers).some((h) => /forwarded|real-ip/i.test(h)));
  }
  assert.deepEqual(JSON.parse(seen[2].body), { code: 'K7QM-2XRP', user: '111111111111111111', name: 'sam' });
  assert.deepEqual(JSON.parse(seen[3].body), { user: '111111111111111111', guild: '2', channel: '3', title: 'Standup in HQ' });
});

test('the take goes up as the Meet bot’s does, to the call’s own route', async () => {
  reset();
  const dir = mkdtempSync(join(tmpdir(), 'discord-api-'));
  try {
    const audio = join(dir, 'c1.webm');
    const captions = join(dir, 'c1.captions.ndjson');
    writeFileSync(audio, Buffer.from('opus in webm'));
    writeFileSync(captions, '{"at":1000,"speaker":"Sam","text":""}\n');
    await createDiscordApi({ base, token: TOKEN }).take('c1', { audio, captions, startedAt: 5, endedAt: 9 });
    const [put] = seen;
    assert.equal(`${put.method} ${put.path}`, 'PUT /api/internal/discord/c1/take');
    const body = put.body.toString();
    assert.match(body, /name="audio"; filename="c1.webm"\r\nContent-Type: audio\/webm\r\n\r\nopus in webm\r\n/);
    assert.match(body, /"speaker":"Sam","text":""/);
    assert.match(body, /name="startedAt"\r\n\r\n5\r\n/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('/ghost link: linked, a code that is not one, too many tries, or the service down', async () => {
  reset();
  const api = createDiscordApi({ base, token: TOKEN });
  const path = 'POST /api/internal/discord/link';
  answers.set(path, [[200, { linked: true }], [404, { error: 'x' }], [400, { error: 'x' }], [429, { error: 'x' }], [500, { error: 'x' }]]);
  const outcomes = [];
  for (let i = 0; i < 5; i += 1) outcomes.push(await redeemCode(api, { code: 'K7QM2XRP', user: '111111111111111111', name: 'sam' }));
  assert.deepEqual(outcomes, ['linked', 'bad_code', 'bad_code', 'too_many', 'down']);
  assert.match(linkReply('linked'), /Linked/);
  assert.match(linkReply('bad_code'), /ten minutes/);
  const down = await redeemCode(createDiscordApi({ base: 'http://127.0.0.1:9', token: TOKEN }), { code: 'K7QM2XRP', user: '1', name: 's' });
  assert.equal(down, 'down', 'nothing listening');
});

test('/ghost join: a call, not linked (and how to link), refused, or down', async () => {
  reset();
  const api = createDiscordApi({ base, token: TOKEN });
  const meeting = { id: 'c1', state: 'joining', startsAt: 1, endsAt: 2 };
  answers.set('POST /api/internal/discord/session', [[200, { meeting, name: 'sam' }], [404, { error: 'x', linked: false }], [403, { error: 'x', calls: false }], [409, { error: 'x' }], [429, { error: 'x' }], [502, {}], [200, {}]]);
  const request = { user: '1', guild: '2', channel: '3', title: 't' };
  assert.deepEqual(await openCall(api, request), { ok: true, meeting, name: 'sam' });
  assert.deepEqual(await openCall(api, request), { ok: false, why: 'not_linked' });
  assert.deepEqual(await openCall(api, request), { ok: false, why: 'calls_off' });
  assert.deepEqual(await openCall(api, request), { ok: false, why: 'refused', status: 409 });
  assert.deepEqual(await openCall(api, request), { ok: false, why: 'refused', status: 429 });
  assert.deepEqual(await openCall(api, request), { ok: false, why: 'down' });
  assert.deepEqual(await openCall(api, request), { ok: false, why: 'down' }, 'an answer with no meeting');
  assert.match(HOW_TO_LINK, /Settings › Discord/);
  assert.match(CALLS_OFF, /Join Discord calls/);
  assert.match(HOW_TO_LINK, /\/ghost link/);
  assert.match(refusedJoin(409), /sync once/);
});
