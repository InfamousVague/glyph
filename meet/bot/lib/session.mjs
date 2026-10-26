/**
 * One meeting, start to finish: join, record, leave, hand the take over.
 *
 * The files are /var/lib/glyph-meet/work/<id>.webm (the recording, appended to every 5 s) and <id>.captions.ndjson
 * (the speaker timeline, a line per finished phrase). After the server has taken them they are deleted: the bot keeps
 * no audio. When the upload fails five times they go to work/failed/ and the meeting is reported `failed: upload`.
 */
import { existsSync, mkdirSync, renameSync, rmSync, statSync, writeFileSync, appendFileSync } from 'node:fs';
import { join } from 'node:path';
import { withRetry } from './api.mjs';
import { CaptionTimeline } from './captions.mjs';
import { LIMITS, busyMisses, leaveReason, nextPeak, trackAlone, trackFew } from './decide.mjs';
import { errorField, log } from './log.mjs';
import * as meet from './meet.mjs';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const size = (path) => (existsSync(path) ? statSync(path).size : 0);

/**
 * `meeting` from /due; `ctx`: { api, work, profile, handled, stopping(), limits }. Resolves when it is over, whatever
 * happened; reports the meeting's state itself.
 */
export async function runMeeting(meeting, ctx) {
  const { api, work, profile, handled, stopping } = ctx;
  const limits = ctx.limits ?? LIMITS;
  const id = meeting.id;
  const audio = join(work, `${id}.webm`);
  const captions = join(work, `${id}.captions.ndjson`);
  /** Posts a state; resolves to false when the server answers 409 (the meeting is not Ghost's any more), else true. */
  const report = (state, detail) =>
    api.state(id, state, detail).then(
      () => {
        log('state', { id, state, detail });
        return true;
      },
      (e) => {
        log('state_failed', { id, state, detail, status: e.status, error: errorField(e) });
        return !e.over;
      },
    );

  handled.add(id);
  if (!(await report('joining'))) return;
  let browser = null;
  let recording = false;
  let reason = null;
  let t0 = null;
  let endedAt = null;
  const timeline = new CaptionTimeline();
  const write = (lines) => {
    for (const line of lines) appendFileSync(captions, JSON.stringify(line) + '\n');
  };
  try {
    browser = await meet.openBrowser(profile);
    const { page } = browser;
    const joined = await meet.join(page, meeting.url, { admitMs: limits.admitMs, shouldStop: stopping, log: (e, f) => log(e, { id, ...f }) });
    if (!joined.ok) {
      // Stopped in the lobby (a restart): left as `joining`, which the next run joins again.
      if (joined.detail === 'shutdown') log('lobby_left', { id, detail: 'shutdown' });
      else await report(joined.detail === 'meeting_ended' ? 'skipped' : 'failed', joined.detail);
      return;
    }
    const joinedAt = Date.now();
    if (!(await report('in_call'))) {
      // Asked to leave, or called off, while the bot was in the lobby.
      await meet.leaveCall(page);
      return;
    }
    await sleep(2000);
    await meet.announce(page, meeting.announce, (e) => log(e, { id }));
    await meet.captionsOn(page);

    writeFileSync(audio, Buffer.alloc(0));
    writeFileSync(captions, '');
    t0 = Date.now();
    try {
      await meet.startRecording(page, audio);
      recording = true;
      log('recording', { id });
    } catch (e) {
      // The captions are still worth having: carry on without the sound.
      recording = true;
      log('capture_failed', { id, error: errorField(e) });
    }

    const live = { goneFor: 0 };
    let aloneSince = null;
    let fewSince = null;
    let peak = 0;
    let count = null;
    let countedAt = null;
    let seenOthers = false;
    let serverLeave = false;
    let lastPoll = Date.now();
    let lastSlow = 0;
    let lastCaptionsSeen = Date.now();
    let lastCaptionsAsk = Date.now();
    let lastLevel = Date.now();
    for (;;) {
      const now = Date.now();
      const blocks = await meet.captionBlocks(page);
      if (blocks) {
        lastCaptionsSeen = now;
        write(timeline.update(blocks, now - t0));
      } else if (now - lastCaptionsSeen > 10_000 && now - lastCaptionsAsk > 30_000) {
        // Captions went off (or never came on): asked for again, now and then.
        lastCaptionsAsk = now;
        await meet.captionsOn(page);
        log('captions_asked', { id });
      }
      let ended = null;
      if (now - lastSlow >= 5000) {
        lastSlow = now;
        ended = await meet.endedReason(page, live);
        const read = await meet.people(page);
        count = read?.count ?? null;
        if (count != null) countedAt = now;
        if (count > 1) seenOthers = true;
        peak = nextPeak(peak, read);
        aloneSince = trackAlone(aloneSince, count, now);
        fewSince = trackFew(fewSince, count, peak, now, limits);
      }
      if (now - lastPoll >= limits.pollMs) {
        lastPoll = now;
        try {
          const due = await api.due();
          serverLeave = due.some((m) => m.id === id && m.state === 'leave');
          for (const other of busyMisses(due, now, id, handled, limits)) {
            handled.add(other);
            await api.state(other, 'failed', 'busy').then(
              () => log('state', { id: other, state: 'failed', detail: 'busy' }),
              (e) => log('state_failed', { id: other, error: errorField(e) }),
            );
          }
        } catch (e) {
          log('due_failed', { id, error: errorField(e) });
        }
      }
      if (now - lastLevel >= 60_000) {
        lastLevel = now;
        log('in_call', { id, seconds: Math.round((now - t0) / 1000), bytes: size(audio), level: await meet.soundLevel(page), people: count });
      }
      reason = leaveReason({ now, joinedAt, startsAt: meeting.startsAt, endsAt: meeting.endsAt, aloneSince, fewSince, count, countedAt, seenOthers, serverLeave, ended, stopping: stopping() }, limits);
      if (reason) break;
      await sleep(500);
    }
    log('leaving', { id, reason });
    await meet.stopRecording(page);
    endedAt = Date.now();
    if (reason !== 'meeting_ended' && reason !== 'removed') await meet.leaveCall(page);
  } catch (e) {
    log('meeting_error', { id, error: errorField(e) });
    reason = reason ?? 'error';
    if (!recording) await report('failed', 'error');
  } finally {
    if (recording) write(timeline.flush());
    if (browser) await browser.context.close().catch(() => {});
  }
  if (recording) await upload(id, { audio, captions, reason, startedAt: t0, endedAt: endedAt ?? Date.now() }, ctx);
}

/**
 * The take to the server, five tries; deleted after. When the server will not have it because the meeting was called
 * off or skipped (409), it is deleted all the same: nothing of such a meeting is kept, here either. Any other failure
 * keeps it in work/failed/ and reports `failed: upload`.
 */
export async function upload(id, { audio, captions, reason, startedAt, endedAt }, { api, work, stopping }) {
  const bytes = size(audio);
  try {
    await withRetry(() => api.take(id, { audio, captions, startedAt, endedAt }), {
      // Being stopped: one try, then the files are kept.
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
  // The server set `done` when it took the take; this adds why the call ended (done to done is allowed), and is let go
  // if the server will not have it.
  await api.state(id, 'done', reason).catch(() => {});
  return true;
}
