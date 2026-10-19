/**
 * The bot's log: one line per event on stdout, which journald keeps (and stamps). Only ids, states, sizes, counts and
 * durations go in: never a meeting's title or link, never a word of its captions or chat. `fields` is checked against
 * that list, so a careless call cannot leak what it was handed.
 */
const ALLOWED = new Set([
  'id', 'state', 'detail', 'reason', 'bytes', 'lines', 'count', 'seconds', 'attempt', 'wait', 'status', 'error',
  'button', 'level', 'people', 'tracks', 'signed_in', 'mode', 'version', 'waiting', 'host',
]);

export function log(event, fields = {}) {
  const parts = [event];
  for (const [key, value] of Object.entries(fields)) {
    if (!ALLOWED.has(key) || value === undefined || value === null) continue;
    const text = String(value).replace(/\s+/g, '_').slice(0, 120);
    parts.push(`${key}=${text}`);
  }
  console.log(parts.join(' '));
}

/** An error, as a log field: its code or the first line of its message, short. */
export const errorField = (error) => String(error?.code ?? error?.message ?? error).split('\n')[0].slice(0, 120);
