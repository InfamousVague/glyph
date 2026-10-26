/**
 * The bot's decisions, kept apart from the browser and the network so they can be tested with plain numbers: which
 * meeting to join, which ones to give up on while it is busy, and when to leave a call.
 */
import { isZoomHost } from './zoomtext.mjs';

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
  /**
   * How long past the booked end to stay when the people in the call cannot be counted. While they can, a meeting
   * that runs over is stayed in for as long as it goes on (Matt, 2026-10-26: "it doesn't leave meetings that are
   * running over"), and left alone, by the few left after a big group, or at `maxMs`.
   */
  overrunMs: 10 * 60_000,
  /** A big group: this many in the call at once, the bot counted, at some point (Matt: "after a big group"). */
  bigGroup: 5,
  /** After a big group, this few left, the bot counted, is "one of the last people in chat": the bot and one more. */
  fewLeft: 2,
  /** How long that few before leaving: the same grace as alone. */
  fewMs: 2 * 60_000,
  /** How long without a count before the people are taken as not countable: a read the page fumbles now and then
   * (a side panel opened, the tiles laid out again) is not that. */
  uncountedMs: 3 * 60_000,
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
 * The most counted at once, for [trackFew]: only a count the People button gave, since a presentation can be a tile
 * of its own and a call of three would read as a big group from the tiles.
 */
export function nextPeak(peak, read) {
  return read && read.from === 'button' && read.count > peak ? read.count : peak;
}

/**
 * The few-left timer: when the call was first seen down to `fewLeft` (the bot and one more) after it had held a big
 * group (`peak`, the most counted at once, at least `bigGroup`), or null otherwise. A count the page would not give
 * resets it, as the alone timer's does.
 */
export function trackFew(fewSince, count, peak, now, limits = LIMITS) {
  if (count != null && peak >= limits.bigGroup && count > 1 && count <= limits.fewLeft) return fewSince ?? now;
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
 *   fewSince       see trackFew: the call down to the bot and one more after a big group, for `fewMs`
 *   count          the people in the call as last read, the bot counted; null where the page would not say
 *   countedAt      when a count was last read; the people are uncountable only `uncountedMs` after it (or with none)
 *   endsAt         the booked end; past it the bot stays while it can count people, and `overrunMs` when it cannot
 *   joinedAt       for the `maxMs` ceiling
 */
export function leaveReason(
  { now, joinedAt, startsAt, endsAt, aloneSince = null, fewSince = null, count = null, countedAt = null, seenOthers = false, serverLeave = false, ended = null, stopping = false },
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
  if (fewSince != null && now - fewSince >= limits.fewMs) return 'few_left';
  // Running over: stayed in while the people can be counted (the alone and few-left rules end it), and only
  // `overrunMs` past the end where they cannot.
  const uncountable = count == null && (countedAt == null || now - countedAt >= limits.uncountedMs);
  if (Number.isFinite(endsAt) && uncountable && now >= endsAt + limits.overrunMs) return 'time_up';
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

/**
 * A Zoom link the bot will open, in the forms the server books (server/src/meet/ics.rs `zoom_url`): https, zoom.us or
 * one name under it, and `/j/<id>` or `/wc/join/<id>` (nine to eleven digits) or a personal `/my/<name>`; and nothing
 * else (a webinar's `/w/`, a host's start link `/s/`, which would sign in as the host).
 */
export function isZoomUrl(url) {
  try {
    const parsed = new URL(url);
    return (
      parsed.protocol === 'https:' &&
      isZoomHost(parsed.hostname) &&
      (/^\/(?:j|wc\/join)\/\d{9,11}\/?$/.test(parsed.pathname) || /^\/my\/[a-z0-9._-]{1,64}\/?$/i.test(parsed.pathname))
    );
  } catch {
    return false;
  }
}

/**
 * Which service a meeting's link is on, so session.mjs drives the page that service draws (lib/meet.mjs,
 * lib/zoom.mjs): `meet`, `zoom`, or null for a link the bot will not open. Read from the link itself, not from the
 * booking's `kind`, which only says the same.
 */
export function platformOf(url) {
  if (isMeetUrl(url)) return 'meet';
  if (isZoomUrl(url)) return 'zoom';
  return null;
}

/** A meeting id safe to put in a file name and a URL path. */
export const isSafeId = (id) => typeof id === 'string' && /^[A-Za-z0-9_-]{1,80}$/.test(id);
