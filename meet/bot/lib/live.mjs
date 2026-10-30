/**
 * The captions as the meeting goes, to the person's devices (Matt, 2026-10-30: "If possible add real time
 * transcriptions for meetings"; docs/MEET.md, "Live captions").
 *
 * The lines the timeline finishes (captions.mjs) go to the take's NDJSON as before, and now also to glyph-api in small
 * batches, `{ startedAt, lines, partial }` (api.mjs `live`), which seals each to the account and passes it to its
 * devices at once (server/src/meet/live.rs). `partial` is the line being said, its words not yet finished, so a long
 * turn is seen as it grows rather than once the speaker stops.
 *
 * - A batch at most every `everyMs` (1.5 s), one at a time: the loop never waits on one, and a slow answer is
 *   overtaken by the next batch, which carries whatever piled up.
 * - Nothing to send is nothing sent: lines go once each; the line being said only when it changed.
 * - Failures keep the lines for the next batch, up to `keepMost` (the take carries every line all the same); 429
 *   waits a little longer.
 * - Off for the rest of the call on 404 (a server from before live captions) and 409 (Ghost is not in the meeting any
 *   more, or its account has no key).
 *
 * Nothing of the words goes to the log: a batch is counted (`lines`), never read.
 */

/** How often a batch goes, at most. */
export const LIVE_EVERY_MS = 1500;
/** The most lines a batch carries (the server's `LINES_MOST`). */
export const LINES_A_BATCH = 100;
/** Lines kept while the server does not answer; past it the oldest go (the take has them). */
export const KEEP_MOST = 400;

export class LiveFeed {
  /** `send(batch)` resolves when the server has it; `startedAt` is the recording's start, ms. */
  constructor({ send, startedAt, everyMs = LIVE_EVERY_MS, keepMost = KEEP_MOST, now = Date.now, log = () => {} }) {
    this.send = send;
    this.startedAt = startedAt;
    this.everyMs = everyMs;
    this.keepMost = keepMost;
    this.now = now;
    this.log = log;
    /** Lines finished and not yet taken by the server. */
    this.pending = [];
    /** The line being said now, and the one last sent. */
    this.partial = null;
    this.sentPartial = null;
    this.lastSent = -Infinity;
    this.inFlight = null;
    this.off = false;
    this.sent = 0;
  }

  /** What the timeline finished this read, and the line being said now (null for none). Never waits. */
  heard(lines, partial) {
    if (this.off) return;
    for (const line of lines ?? []) {
      if (line && typeof line.text === 'string' && line.text.trim()) this.pending.push({ at: line.at, speaker: line.speaker ?? '', text: line.text });
    }
    if (this.pending.length > this.keepMost) this.pending.splice(0, this.pending.length - this.keepMost);
    this.partial = partial && partial.text && partial.text.trim() ? { at: partial.at, speaker: partial.speaker ?? '', text: partial.text } : null;
    if (!this.inFlight && this.now() - this.lastSent >= this.everyMs) this.inFlight = this.#flush().finally(() => (this.inFlight = null));
  }

  /** The call is over: what is left goes, with no line being said. Resolves once it has gone, or failed. */
  async end() {
    if (this.inFlight) await this.inFlight;
    if (this.off) return;
    this.partial = null;
    this.sentPartial = null;
    while (!this.off && this.pending.length) {
      const before = this.pending.length;
      await this.#flush();
      if (this.pending.length >= before) break;
    }
  }

  async #flush() {
    const changed = JSON.stringify(this.partial) !== JSON.stringify(this.sentPartial);
    if (!this.pending.length && !changed) return;
    const lines = this.pending.slice(0, LINES_A_BATCH);
    const partial = this.partial;
    this.lastSent = this.now();
    try {
      await this.send({ startedAt: this.startedAt, lines, partial });
      this.pending.splice(0, lines.length);
      this.sentPartial = partial;
      this.sent += lines.length;
    } catch (e) {
      const status = e?.status ?? 0;
      if (status === 404 || status === 409) {
        this.off = true;
        this.pending = [];
        this.log('live_off', { status });
      } else if (status === 429) {
        // Past the server's pace: the next batch waits a little longer.
        this.lastSent = this.now() + this.everyMs;
      }
    }
  }
}
