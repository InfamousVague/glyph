/**
 * glyph-api's internal Meet routes (server/src/meet.rs, docs/MEET.md), the bot's only way to the server. Loopback, a
 * bearer token, no proxy headers (a request carrying X-Forwarded-* is taken for one through Caddy and answered 404),
 * three calls:
 *
 *   GET  /api/internal/meet/due          { meetings: [{ id, url, title, startsAt, endsAt, state, announce }] }, state
 *                                        booked | joining | in_call | leave, from 2 min before the start to 15 after
 *                                        the end
 *   POST /api/internal/meet/{id}/state   { state, detail? }: joining | in_call | done | failed | skipped. 409 means the
 *                                        meeting is over or Ghost was asked to leave: leave, and never join it again
 *   PUT  /api/internal/meet/{id}/take    multipart: `audio` (audio/webm), `captions` (NDJSON), `startedAt` and
 *                                        `endedAt` (ms as text). The meeting is then done. 400 no audio, 409 skipped
 *                                        or called off (nothing of it is kept: the bot deletes its copy too)
 *
 * The contract lives here and nowhere else, so a change on the server's side is a change to this one file.
 *
 * node:http rather than fetch: the take is streamed from disk with its length known, which Node 18's fetch cannot do
 * without reading a three-hour recording into memory, and the box's Node may be 18.
 */
import { createReadStream, statSync } from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import { randomBytes } from 'node:crypto';

export const BASE_PATH = '/api/internal/meet';

/** An answer the server gave that is not a success; `status` is the HTTP status, 0 for a network failure. */
export class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
  /** The server's "not Ghost's meeting any more": over, called off, or Ghost was asked to leave. */
  get over() {
    return this.status === 409;
  }
  /** Worth trying again: no answer, a server error, a timeout or a rate limit. A 4xx is the request's own fault. */
  get retryable() {
    return this.status === 0 || this.status >= 500 || this.status === 408 || this.status === 429;
  }
}

/**
 * The client. `basePath` and `tokenName` are the Discord bot's to change (discord/bot/lib/api.mjs: the same three
 * calls under /api/internal/discord, with GLYPH_DISCORD_TOKEN), which is why they are options at all.
 */
export function createApi({ base = 'http://127.0.0.1:8796', token, timeoutMs = 30_000, basePath = BASE_PATH, tokenName = 'GLYPH_MEET_TOKEN' } = {}) {
  if (!token) throw new Error(`${tokenName} is not set`);
  const root = new URL(base);
  const client = root.protocol === 'https:' ? https : http;

  /** One request; `body` is a Buffer, or a function that writes the body to the request and ends it. */
  function request(method, path, { headers = {}, body = null, timeout = timeoutMs } = {}) {
    return new Promise((resolve, reject) => {
      const req = client.request(
        new URL(root.pathname.replace(/\/$/, '') + path, root),
        { method, headers: { Authorization: `Bearer ${token}`, ...headers }, timeout },
        (res) => {
          const chunks = [];
          res.on('data', (chunk) => chunks.push(chunk));
          res.on('end', () => {
            const text = Buffer.concat(chunks).toString('utf8');
            if (res.statusCode >= 200 && res.statusCode < 300) resolve(text);
            // The body is not put in the message: an error page could carry anything, and messages reach the log.
            else reject(new ApiError(res.statusCode, `${method} ${path.replace(/\/(meet|discord)\/[^/]+\/(state|take)$/, '/$1/:id/$2')} answered ${res.statusCode}`));
          });
          res.on('error', (e) => reject(new ApiError(0, e.message)));
        },
      );
      req.on('timeout', () => req.destroy(new Error('timed out')));
      req.on('error', (e) => reject(e instanceof ApiError ? e : new ApiError(0, `${method} failed: ${e.code ?? e.message}`)));
      if (typeof body === 'function') body(req);
      else req.end(body ?? undefined);
    });
  }

  const json = (value) => {
    const body = Buffer.from(JSON.stringify(value));
    return { headers: { 'Content-Type': 'application/json', 'Content-Length': body.length }, body };
  };
  const meetingPath = (id, what) => `${basePath}/${encodeURIComponent(id)}/${what}`;

  return {
    /** One request as the calls below make them, for a client that adds calls of its own (the Discord bot's). */
    request,
    json,

    /** The meetings that are due, or under way. */
    async due() {
      const text = await request('GET', `${basePath}/due`);
      const parsed = JSON.parse(text || '{}');
      return Array.isArray(parsed.meetings) ? parsed.meetings : [];
    },

    /** A meeting's new state, with why when there is a why. */
    async state(id, state, detail) {
      await request('POST', meetingPath(id, 'state'), json(detail ? { state, detail } : { state }));
    },

    /**
     * The take: the recording and the captions, streamed from their files as one multipart body, and the recording's
     * own span (ms) when known. A missing file is sent as an empty part (the server answers 400 to a take without
     * audio: the call is then kept in work/failed/ like any other upload that did not go).
     */
    async take(id, { audio, captions, startedAt, endedAt }) {
      const boundary = `----ghostmeet${randomBytes(12).toString('hex')}`;
      const fields = Object.entries({ startedAt, endedAt })
        .filter(([, value]) => Number.isFinite(value))
        .map(([name, value]) => Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="${name}"\r\n\r\n${Math.round(value)}\r\n`));
      const parts = [
        { name: 'audio', filename: `${id}.webm`, type: 'audio/webm', path: audio },
        { name: 'captions', filename: `${id}.ndjson`, type: 'application/x-ndjson', path: captions },
      ].map((part) => ({
        ...part,
        size: sizeOf(part.path),
        head: Buffer.from(
          `--${boundary}\r\nContent-Disposition: form-data; name="${part.name}"; filename="${part.filename}"\r\n` +
            `Content-Type: ${part.type}\r\n\r\n`,
        ),
      }));
      const tail = Buffer.from(`--${boundary}--\r\n`);
      const length = fields.reduce((sum, f) => sum + f.length, 0) + parts.reduce((sum, p) => sum + p.head.length + p.size + 2, 0) + tail.length;
      await request('PUT', meetingPath(id, 'take'), {
        headers: { 'Content-Type': `multipart/form-data; boundary=${boundary}`, 'Content-Length': length },
        // Ten minutes: a three-hour recording is ~100 MB at most, over loopback.
        timeout: 10 * 60_000,
        body: (req) => {
          const write = async () => {
            for (const field of fields) req.write(field);
            for (const part of parts) {
              req.write(part.head);
              if (part.size) {
                for await (const chunk of createReadStream(part.path)) {
                  if (!req.write(chunk)) await new Promise((r) => req.once('drain', r));
                }
              }
              req.write('\r\n');
            }
            req.end(tail);
          };
          write().catch((e) => req.destroy(e));
        },
      });
    },
  };
}

function sizeOf(path) {
  try {
    return path ? statSync(path).size : 0;
  } catch {
    return 0;
  }
}

/**
 * `fn`, tried up to `tries` times while it fails with something worth retrying, waiting `baseMs`, then three times
 * as long each time (2 s, 6 s, 18 s, 54 s by default). `shouldStop` cuts the waiting short (the service stopping).
 */
export async function withRetry(fn, { tries = 5, baseMs = 2000, factor = 3, sleep = defaultSleep, onRetry = () => {}, shouldStop = () => false } = {}) {
  let wait = baseMs;
  for (let attempt = 1; ; attempt++) {
    try {
      return await fn(attempt);
    } catch (error) {
      const retryable = !(error instanceof ApiError) || error.retryable;
      if (!retryable || attempt >= tries || shouldStop()) throw error;
      onRetry(error, attempt, wait);
      await sleep(wait);
      wait *= factor;
    }
  }
}

const defaultSleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
