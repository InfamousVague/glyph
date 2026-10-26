/**
 * glyph-api's internal Discord routes (server/src/discord.rs, docs/DISCORD_CALLS.md), the bot's only way to the
 * server. The Meet bot's client (meet/bot/lib/api.mjs) under /api/internal/discord with the Discord bot's own token,
 * GLYPH_DISCORD_TOKEN, so the take's multipart upload, the token, the absence of proxy headers and the retries are
 * the very ones the Meet bot's tests cover, and two calls of its own:
 *
 *   POST /api/internal/discord/link       { code, user, name } → { linked: true }; 404 a code that is not one, or ran
 *                                         out; 429 too many tried
 *   POST /api/internal/discord/session    { user, guild, channel, title } → { meeting: { id, state, startsAt, endsAt },
 *                                         name }; 404 not linked; 403 linked, with the Discord plugin's "Join Discord
 *                                         calls" off; 409 the account has no key; 429 too many
 *   GET  /api/internal/discord/due        { meetings: [{ id, state, startsAt, endsAt }] }: the calls under way
 *   POST /api/internal/discord/{id}/state and PUT …/{id}/take, as the Meet bot's
 */
import { ApiError, createApi, withRetry } from '../../../meet/bot/lib/api.mjs';

export { ApiError, withRetry };

export const BASE_PATH = '/api/internal/discord';

export function createDiscordApi({ base = 'http://127.0.0.1:8796', token, timeoutMs = 30_000 } = {}) {
  const api = createApi({ base, token, timeoutMs, basePath: BASE_PATH, tokenName: 'GLYPH_DISCORD_TOKEN' });
  const post = async (path, body) => JSON.parse((await api.request('POST', `${BASE_PATH}/${path}`, api.json(body))) || '{}');
  return {
    due: api.due,
    state: api.state,
    take: api.take,

    /** `/ghost link <code>` for Discord user `user` (their id) called `name`. */
    async link({ code, user, name }) {
      return post('link', { code, user, name });
    },

    /** `/ghost join`: the call booked for the account `user` is linked to; `{ meeting, name }`. */
    async open({ user, guild, channel, title }) {
      return post('session', { user, guild, channel, title });
    },
  };
}

/** What `/ghost link` came to, in words.mjs `linkReply`'s terms. */
export async function redeemCode(api, { code, user, name }) {
  try {
    await api.link({ code, user, name });
    return 'linked';
  } catch (e) {
    if (e instanceof ApiError && (e.status === 404 || e.status === 400)) return 'bad_code';
    if (e instanceof ApiError && e.status === 429) return 'too_many';
    return 'down';
  }
}

/**
 * What `/ghost join` came to: `{ ok: true, meeting, name }`, or `{ ok: false, why }` with why `not_linked` (404),
 * `calls_off` (403: the plugin's switch), `refused` (409 or 429, with its status) or `down`.
 */
export async function openCall(api, request) {
  try {
    const said = await api.open(request);
    if (!said?.meeting?.id) return { ok: false, why: 'down' };
    return { ok: true, meeting: said.meeting, name: said.name };
  } catch (e) {
    if (e instanceof ApiError && e.status === 404) return { ok: false, why: 'not_linked' };
    if (e instanceof ApiError && e.status === 403) return { ok: false, why: 'calls_off' };
    if (e instanceof ApiError && (e.status === 409 || e.status === 429)) return { ok: false, why: 'refused', status: e.status };
    return { ok: false, why: 'down' };
  }
}
