/**
 * One Discord call, from `/ghost join` to the take on glyph-api (docs/DISCORD_CALLS.md). bot.mjs owns Discord - the
 * voice connection, the receiver's streams, the members - and hands this the packets, the people counted and the
 * names; this owns the recording, when to leave, and the upload.
 *
 * LEAVING, on the first of (the Meet bot's rules, meet/bot/lib/decide.mjs `leaveReason`, with Discord's exact count):
 * `/ghost leave` (`asked`); the device's "Leave now" (`leave` in `due`, polled every 20 s: `asked_to_leave`); alone
 * for 2 minutes (`alone`); after a big group (5 in the call at once, Ghost counted), down to Ghost and one more for 2
 * minutes (`few_left`); three hours in (`time_up`); Ghost moved or put out of the channel (`removed`), or its
 * connection gone for good (`disconnected`); the service stopping (`shutdown`).
 *
 * THE TAKE: the mix (`<id>.webm`) and the speaker turns (`<id>.captions.ndjson`, turns.mjs, the names put on now),
 * `PUT take` with `startedAt` and `endedAt`, five tries (once when stopping). Taken: the files deleted, and `done`
 * posted with why the call ended. Refused with 409 (the call was called off on the device): deleted all the same.
 * Anything else: moved to `work/failed/`, and `failed: upload`. A call in which nobody was heard at all has no take:
 * `failed: nothing_heard`, its files deleted (where the voice receive is broken - DAVE, below - this is what it
 * looks like, and the log says how many packets came).
 */
import { existsSync, mkdirSync, renameSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { LIMITS, leaveReason, nextPeak, trackAlone, trackFew } from '../../../meet/bot/lib/decide.mjs';
import { errorField, log as defaultLog } from '../../../meet/bot/lib/log.mjs';
import { withRetry } from './api.mjs';
import { Recorder } from './recorder.mjs';
import { ndjson, speakerTurns } from './turns.mjs';

const size = (path) => (existsSync(path) ? statSync(path).size : 0);

/**
 * Where the leaving rules stand after a count read at `now`: the alone and few-left timers, the most counted at once,
 * and whether anyone else has been in the call. `count` is the people in the channel, Ghost counted (Discord's
 * member list: exact, so it is read as the Meet bot reads the People button).
 */
export function presence(was, count, now, limits = LIMITS) {
  const peak = nextPeak(was.peak, count == null ? null : { from: 'button', count });
  return {
    peak,
    seenOthers: was.seenOthers || (count ?? 0) > 1,
    aloneSince: trackAlone(was.aloneSince, count, now),
    fewSince: trackFew(was.fewSince, count, peak, now, limits),
    count,
    countedAt: count == null ? was.countedAt : now,
  };
}

export const NOBODY = { peak: 0, seenOthers: false, aloneSince: null, fewSince: null, count: null, countedAt: null };

/** Why to leave now, or null: decide.mjs's rules over a call with no booked end (the three hours are the end). */
export function whyLeave(p, { now, joinedAt, asked = null, serverLeave = false, ended = null, stopping = false }, limits = LIMITS) {
  if (asked) return asked;
  return leaveReason({ now, joinedAt, startsAt: joinedAt, endsAt: undefined, ...p, serverLeave, ended, stopping }, limits);
}

export class Call {
  /**
   * `meeting` from `open` ({ id, startsAt, ... }); `forName` the person it records for; `ctx`: { api, work, codec,
   * stopping(), limits?, log? }.
   */
  constructor({ meeting, forName, guildId, channelId, requester, ctx }) {
    this.meeting = meeting;
    this.id = meeting.id;
    this.forName = forName;
    this.guildId = guildId;
    this.channelId = channelId;
    this.requester = requester;
    this.ctx = ctx;
    this.limits = ctx.limits ?? LIMITS;
    this.log = ctx.log ?? defaultLog;
    this.names = new Map();
    this.presence = NOBODY;
    this.asked = null;
    this.ended = null;
    this.serverLeave = false;
    this.lastPoll = 0;
    this.reason = null;
    this.recorder = null;
    this.audio = join(ctx.work, `${this.id}.webm`);
    this.speech = join(ctx.work, `${this.id}.speech.ndjson`);
    this.captions = join(ctx.work, `${this.id}.captions.ndjson`);
  }

  /** In the call: the recording begins at `now`. */
  start(now) {
    this.joinedAt = now;
    this.recorder = new Recorder({ audioPath: this.audio, speechPath: this.speech, t0: now, codec: this.ctx.codec });
  }

  /** A packet of `user`'s, arrived at `at`. */
  packet(user, opus, at) {
    this.recorder?.packet(user, opus, at);
  }

  /** `user`'s name in this server, for the turns. Never logged. */
  name(user, name) {
    if (name) this.names.set(user, name);
  }

  /** The people in the channel, Ghost counted, read at `now`. */
  counted(count, now) {
    this.presence = presence(this.presence, count, now, this.limits);
  }

  /** `/ghost leave`, or Discord put Ghost out (`removed`, `disconnected`). */
  stop(reason) {
    if (reason === 'asked') this.asked = 'asked';
    else this.ended = this.ended ?? reason;
  }

  /** Ten times a second: what the recorder can write, the device's word now and then, and whether to leave. */
  async tick(now) {
    this.recorder?.tick(now);
    if (now - this.lastPoll >= this.limits.pollMs) {
      this.lastPoll = now;
      try {
        const due = await this.ctx.api.due();
        this.serverLeave = due.some((m) => m.id === this.id && m.state === 'leave');
      } catch (e) {
        this.log('due_failed', { id: this.id, error: errorField(e) });
      }
    }
    this.reason = whyLeave(this.presence, { now, joinedAt: this.joinedAt, asked: this.asked, serverLeave: this.serverLeave, ended: this.ended, stopping: this.ctx.stopping() }, this.limits);
    return this.reason;
  }

  /** The call is over: the recording finished, the turns written, the take handed over. Resolves to whether it went. */
  async finish(now = Date.now()) {
    const result = this.recorder?.stop() ?? { intervals: [], packets: 0, speakers: 0, late: 0, broken: 0, durationMs: 0 };
    const reason = this.reason ?? this.ended ?? 'error';
    this.log('leaving', { id: this.id, reason, packets: result.packets, speakers: result.speakers, late: result.late, broken: result.broken, seconds: Math.round(result.durationMs / 1000) });
    const { api } = this.ctx;
    if (result.speakers === 0) {
      for (const path of [this.audio, this.speech, this.captions]) rmSync(path, { force: true });
      this.log('nothing_heard', { id: this.id, packets: result.packets, broken: result.broken });
      await api.state(this.id, 'failed', 'nothing_heard').catch(() => {});
      return false;
    }
    writeFileSync(this.captions, ndjson(speakerTurns(result.intervals, this.names)));
    const sent = await upload(this.id, { audio: this.audio, captions: this.captions, reason, startedAt: this.joinedAt, endedAt: now }, this.ctx, this.log);
    rmSync(this.speech, { force: true });
    return sent;
  }
}

/**
 * The take to the server, five tries; deleted after. As the Meet bot's (meet/bot/lib/session.mjs `upload`), which
 * cannot be imported here: its module opens a browser. Refused with 409 (called off on a device): deleted all the
 * same. Any other failure keeps it in `work/failed/` and reports `failed: upload`.
 */
export async function upload(id, { audio, captions, reason, startedAt, endedAt }, { api, work, stopping }, log = defaultLog) {
  const bytes = size(audio);
  try {
    await withRetry(() => api.take(id, { audio, captions, startedAt, endedAt }), {
      tries: stopping() ? 1 : 5,
      shouldStop: stopping,
      onRetry: (e, attempt, wait) => log('upload_retry', { id, attempt, wait, error: errorField(e) }),
    });
  } catch (e) {
    if (e.over) {
      rmSync(audio, { force: true });
      rmSync(captions, { force: true });
      log('take_refused', { id, bytes, status: e.status });
      return false;
    }
    const failed = join(work, 'failed');
    mkdirSync(failed, { recursive: true });
    for (const path of [audio, captions]) {
      if (existsSync(path)) renameSync(path, join(failed, path.slice(work.length + 1)));
    }
    log('upload_failed', { id, bytes, error: errorField(e) });
    await api.state(id, 'failed', 'upload').catch(() => {});
    return false;
  }
  rmSync(audio, { force: true });
  rmSync(captions, { force: true });
  log('uploaded', { id, bytes, reason });
  await api.state(id, 'done', reason).catch(() => {});
  return true;
}
