/**
 * The bot's decisions, kept apart from the browser and the network so they can be tested with plain numbers: which
 * meeting to join, which ones to give up on while it is busy, and when to leave a call.
 */

export const LIMITS = {
  /** How often /due is asked, idle and in a call. */
  pollMs: 20_000,
  /** How early before its start a meeting is joined, at most (the server decides what is due; this is a guard). */
  earlyMs: 5 * 60_000,
  /** How late a meeting may be joined because another one ran over, before it is given up as `busy`. */
  lateMs: 10 * 60_000,
  /** How long to wait in the lobby to be let in. */
  admitMs: 10 * 60_000,
  /** How long alone in the call before leaving. */
  aloneMs: 2 * 60_000,
  /** When nobody else has ever been in the call: how long past the start to wait for someone. */
  nobodyMs: 10 * 60_000,
  /** How long past the booked end to stay. */
  overrunMs: 10 * 60_000,
  /** The longest call, whatever the booking says. */
  maxMs: 3 * 60 * 60_000,
};

/** The states in which a meeting is the bot's to join: booked, or one it was in when it last stopped (a restart). */
const JOINABLE = new Set(['booked', 'joining', 'in_call']);

/**
 * Idle: what to do with the meetings /due lists. `handled` holds the ids this process has already dealt with, so a
 * meeting the server still lists for a moment after its last state is not joined twice.
 *
 * Returns `{ join, skip }`: the meeting to join now (the earliest that is ready), and `[{ id, detail }]` to report as
 * skipped (over before the bot got to it).
 */
export function planIdle(meetings, now, handled = new Set(), limits = LIMITS) {
  const skip = [];
  const ready = [];
  for (const meeting of meetings ?? []) {
    if (!meeting || handled.has(meeting.id) || !JOINABLE.has(meeting.state)) continue;
    if (Number.isFinite(meeting.endsAt) && now >= meeting.endsAt) {
      skip.push({ id: meeting.id, detail: 'time_up' });
      continue;
    }
    if (Number.isFinite(meeting.startsAt) && now < meeting.startsAt - limits.earlyMs) continue;
    ready.push(meeting);
  }
  ready.sort((a, b) => (a.startsAt ?? 0) - (b.startsAt ?? 0));
  return { join: ready[0] ?? null, skip };
}

/**
 * Busy in a call: the other meetings that would now be joined more than `lateMs` late, to be reported `failed: busy`
 * (one meeting at a time; the later ones wait, but not for ever).
 */
export function busyMisses(meetings, now, currentId, handled = new Set(), limits = LIMITS) {
  return (meetings ?? [])
    .filter((m) => m && m.id !== currentId && !handled.has(m.id) && m.state === 'booked')
    .filter((m) => Number.isFinite(m.startsAt) && now > m.startsAt + limits.lateMs)
    .map((m) => m.id);
}

/**
 * The people count, read again: when the bot was first seen alone (`aloneSince`), or null while somebody else is
 * there. A count the page would not give (null) resets the timer: the bot leaves for being alone only on counts it
 * actually read.
 */
export function trackAlone(aloneSince, count, now) {
  if (count === 1) return aloneSince ?? now;
  return null;
}

/**
 * Why to leave the call now, or null to stay.
 *
 *   ended          the page says the call is over for us ('meeting_ended', 'removed'), as meet.mjs read it
 *   serverLeave    the server's state for the meeting is `leave` ('asked_to_leave')
 *   stopping       the service is being stopped ('shutdown')
 *   aloneSince     see trackAlone; counted from the booked start at the earliest, and, when nobody else has been in
 *                  the call at all (`seenOthers` false), not before `nobodyMs` past the start
 *   endsAt         the booked end; the bot stays `overrunMs` past it
 *   joinedAt       for the `maxMs` ceiling
 */
export function leaveReason(
  { now, joinedAt, startsAt, endsAt, aloneSince = null, seenOthers = false, serverLeave = false, ended = null, stopping = false },
  limits = LIMITS,
) {
  if (ended) return ended;
  if (stopping) return 'shutdown';
  if (serverLeave) return 'asked_to_leave';
  if (aloneSince != null) {
    const from = Math.max(aloneSince, Number.isFinite(startsAt) ? startsAt : aloneSince);
    const waitedForSomeone = seenOthers || !Number.isFinite(startsAt) || now >= startsAt + limits.nobodyMs;
    if (now - from >= limits.aloneMs && waitedForSomeone) return 'alone';
  }
  if (Number.isFinite(endsAt) && now >= endsAt + limits.overrunMs) return 'time_up';
  if (now - joinedAt >= limits.maxMs) return 'time_up';
  return null;
}

/** A Meet link the bot will open: https://meet.google.com/<code>, and nothing else. */
export function isMeetUrl(url) {
  try {
    const parsed = new URL(url);
    return parsed.protocol === 'https:' && parsed.hostname === 'meet.google.com' && /^\/[a-z0-9-]{3,}(\/)?$/i.test(parsed.pathname);
  } catch {
    return false;
  }
}

/** A meeting id safe to put in a file name and a URL path. */
export const isSafeId = (id) => typeof id === 'string' && /^[A-Za-z0-9_-]{1,80}$/.test(id);
