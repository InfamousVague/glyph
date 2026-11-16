// The HTTP side: what the app asks of the bot. No discord.js here: the bot hands in `guilds`, which finds a server by
// id ({ status: 'ok', guild } | { status: 'gone' } | { status: 'starting' }), and everything else is this folder's.
//
//   POST /discord/claim   {"code":"ABC123"} -> {token, guild}       (404 unknown code, 429 too many tries)
//   GET  /discord/state?token=<token>       -> {guild, channels, at} (401 not linked, 410 gone)
//   GET  /discord/invite                    -> {url}
//   GET  /discord/                          -> {ok: true}            (the deploy's health check)
//
// Caddy passes https://ghost-sms.com/discord/* on with the prefix kept; the same routes answer without it.
import { buildState, guildInfo } from './state.js';
import { RateLimit } from './ratelimit.js';

export const MAX_BODY = 4 * 1024;
export const inviteUrl = (appId) => `https://discord.com/oauth2/authorize?client_id=${appId}&scope=bot%20applications.commands&permissions=1024`;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Max-Age': '600',
};

function send(res, status, body, extra = {}) {
  const text = body === null ? '' : JSON.stringify(body);
  res.writeHead(status, {
    ...CORS,
    ...(body === null ? {} : { 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': Buffer.byteLength(text) }),
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    ...extra,
  });
  res.end(text);
}

/** The body, at most MAX_BODY bytes; null when it was longer (the rest is not read). */
function readBody(req) {
  return new Promise((resolve, reject) => {
    const declared = Number(req.headers['content-length']);
    if (Number.isFinite(declared) && declared > MAX_BODY) return resolve(null);
    const chunks = [];
    let size = 0;
    let done = false;
    req.on('data', (chunk) => {
      if (done) return;
      size += chunk.length;
      if (size > MAX_BODY) {
        done = true;
        resolve(null);
        req.pause();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => { if (!done) { done = true; resolve(Buffer.concat(chunks)); } });
    req.on('error', (e) => { if (!done) { done = true; reject(e); } });
  });
}

/** The asker's address. Behind Caddy every request comes from loopback, and Caddy's X-Forwarded-For ends with the
 * address it was itself connected from (it does not trust one a client sent), so the last entry is the asker. */
export function clientIp(req) {
  const remote = req.socket?.remoteAddress ?? '';
  const loopback = remote === '127.0.0.1' || remote === '::1' || remote === '::ffff:127.0.0.1';
  const forwarded = req.headers['x-forwarded-for'];
  if (loopback && typeof forwarded === 'string' && forwarded.trim()) {
    const parts = forwarded.split(',').map((s) => s.trim()).filter(Boolean);
    if (parts.length) return parts[parts.length - 1];
  }
  return remote || 'unknown';
}

/**
 * The request handler. codes: Codes; store: TokenStore; guilds: { lookup(id, { members }) }; appId: for /invite.
 * log(message) gets counts and outcomes only, never a token, a code or a name.
 */
export function createHandler({ codes, store, guilds, appId = null, now = Date.now, log = () => {}, perIp = 10, overall = 300 }) {
  const ipLimit = new RateLimit({ limit: perIp, now });
  const allLimit = new RateLimit({ limit: overall, now });

  async function claim(req, res) {
    const ip = clientIp(req);
    if (!ipLimit.hit(ip)) return send(res, 429, { error: 'slow down' }, { 'Retry-After': String(ipLimit.retryAfter(ip)) });
    if (!allLimit.hit('*')) return send(res, 429, { error: 'slow down' }, { 'Retry-After': String(allLimit.retryAfter('*')) });
    const raw = await readBody(req);
    if (raw === null) return send(res, 413, { error: 'too large' }, { Connection: 'close' });
    let body;
    try {
      body = JSON.parse(raw.toString('utf8'));
    } catch {
      return send(res, 400, { error: 'bad json' });
    }
    const guildId = codes.take(body?.code);
    if (!guildId) {
      log('claim: unknown code');
      return send(res, 404, { error: 'unknown code' });
    }
    const found = await guilds.lookup(guildId, { members: false });
    if (found.status === 'gone') return send(res, 410, { error: 'gone' });
    if (found.status !== 'ok') return send(res, 503, { error: 'starting' }, { 'Retry-After': '5' });
    const token = store.add(guildId);
    log(`claim: linked guild ${guildId} (${store.countGuild(guildId)} links)`);
    return send(res, 200, { token, guild: guildInfo(found.guild) });
  }

  async function state(req, res, url) {
    const guildId = store.guildOf(url.searchParams.get('token') ?? '');
    if (!guildId) return send(res, 401, { error: 'not linked' });
    const found = await guilds.lookup(guildId, { members: true });
    if (found.status === 'gone') return send(res, 410, { error: 'gone' });
    if (found.status !== 'ok') return send(res, 503, { error: 'starting' }, { 'Retry-After': '5' });
    return send(res, 200, buildState(found.guild, now()));
  }

  return async function handle(req, res) {
    try {
      const url = new URL(req.url ?? '/', 'http://localhost');
      let path = url.pathname;
      if (path === '/discord' || path.startsWith('/discord/')) path = path.slice('/discord'.length) || '/';
      if (path.length > 1 && path.endsWith('/')) path = path.slice(0, -1);
      const method = req.method ?? 'GET';

      if (method === 'OPTIONS') return send(res, 204, null);
      if (path === '/claim') return method === 'POST' ? await claim(req, res) : send(res, 405, { error: 'method' }, { Allow: 'POST, OPTIONS' });
      if (path === '/state') return method === 'GET' ? await state(req, res, url) : send(res, 405, { error: 'method' }, { Allow: 'GET, OPTIONS' });
      if (path === '/invite') {
        if (method !== 'GET') return send(res, 405, { error: 'method' }, { Allow: 'GET, OPTIONS' });
        return appId ? send(res, 200, { url: inviteUrl(appId) }) : send(res, 503, { error: 'starting' });
      }
      if (path === '/' && method === 'GET') return send(res, 200, { ok: true, service: 'ghost-discord' });
      return send(res, 404, { error: 'not found' });
    } catch (e) {
      log(`error: ${e?.message ?? e}`);
      if (!res.headersSent) send(res, 500, { error: 'server' });
      else res.destroy();
    }
  };
}
