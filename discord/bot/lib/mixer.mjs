/**
 * A Discord call as ONE track (docs/DISCORD_CALLS.md, "The recording"). Discord hands the bot each speaker's Opus
 * packets apart, one stream a person, and only while they speak: no packets at all while they are quiet. The device
 * writes a meeting up from one recording (lib/meet/tape.dart), so the bot lays every speaker's sound on one timeline
 * and sums it, frame by frame, with silence wherever nobody spoke.
 *
 * TIME. Everything is in 20 ms frames (960 samples at 48 kHz, mono) counted from the recording's start (`t0`). A
 * packet is placed by its arrival, but within a burst of speech by count: the first packet of a burst goes where it
 * arrived, each one after it in the frame after the one before, so the jitter of a network does not smear a voice.
 * A packet arriving more than `resyncMs` later than its count says (the speaker paused, or packets were lost) starts
 * the count again where it arrived: the silence between is kept. One arriving early, a rush after a stall, keeps
 * the count, so nothing is laid over itself; only a count more than `aheadMs` ahead is taken back to the clock.
 *
 * MIXING. A frame is written once nothing more can come for it: `latencyMs` after its time. A packet that comes for a
 * frame already written is dropped (and counted, `late`), as a phone call drops one. Voices are summed and clipped to
 * 16 bits; two people talking at once is two voices, as in the room.
 *
 * Pure: no Discord, no Opus, no files. recorder.mjs feeds it decoded sound and encodes what it hands back.
 */

export const RATE = 48_000;
export const FRAME_MS = 20;
export const FRAME_SAMPLES = (RATE * FRAME_MS) / 1000;

export const MIX = {
  /** How long a frame waits for a packet that is late before it is mixed and written. */
  latencyMs: 400,
  /** A packet this much later than its burst's count starts the count again from when it came. */
  resyncMs: 200,
  /** A count this far ahead of the clock is taken back to it. */
  aheadMs: 1000,
};

export class Mixer {
  /** `t0`: when the recording began, ms (Date.now()'s clock). */
  constructor({ t0, limits = MIX } = {}) {
    this.t0 = t0;
    this.limits = limits;
    /** Per speaker, the frame their next packet goes in, by count. */
    this.next = new Map();
    /** Frames not yet written, by index: the voices summed so far. */
    this.pending = new Map();
    /** The first frame not yet written. */
    this.written = 0;
    /** Packets that came for a frame already written. */
    this.late = 0;
  }

  /** The frame moment `at` (ms) falls in. */
  frameAt(at) {
    return Math.floor((at - this.t0) / FRAME_MS);
  }

  /**
   * `pcm` (Int16Array, 960 samples a frame, any whole number of frames) of `speaker`, which arrived at `at` (ms).
   * Answers the frame it was put in, or null where it came too late and was dropped.
   */
  place(speaker, pcm, at) {
    const arrived = this.frameAt(at);
    const counted = this.next.get(speaker);
    const resync = Math.round(this.limits.resyncMs / FRAME_MS);
    const ahead = Math.round(this.limits.aheadMs / FRAME_MS);
    let frame = counted;
    if (frame == null || arrived - frame > resync || frame - arrived > ahead) frame = arrived;
    const frames = Math.max(1, Math.ceil(pcm.length / FRAME_SAMPLES));
    this.next.set(speaker, frame + frames);
    if (frame < this.written) {
      this.late += 1;
      return null;
    }
    for (let i = 0; i < frames; i += 1) {
      let sum = this.pending.get(frame + i);
      if (!sum) {
        sum = new Int32Array(FRAME_SAMPLES);
        this.pending.set(frame + i, sum);
      }
      const from = i * FRAME_SAMPLES;
      const to = Math.min(pcm.length, from + FRAME_SAMPLES);
      for (let s = from; s < to; s += 1) sum[s - from] += pcm[s];
    }
    return frame;
  }

  /** The frames that can be written at `now` (ms): every one `latencyMs` old, in order, silence where nobody spoke. */
  drain(now) {
    return this.#writeUpTo(this.frameAt(now - this.limits.latencyMs));
  }

  /** Every frame left, to the last one any voice reached: the recording's end. */
  finish() {
    let last = this.written;
    for (const frame of this.pending.keys()) last = Math.max(last, frame + 1);
    return this.#writeUpTo(last);
  }

  #writeUpTo(end) {
    const out = [];
    for (; this.written < end; this.written += 1) {
      const sum = this.pending.get(this.written);
      this.pending.delete(this.written);
      const frame = new Int16Array(FRAME_SAMPLES);
      if (sum) for (let s = 0; s < FRAME_SAMPLES; s += 1) frame[s] = Math.max(-32768, Math.min(32767, sum[s]));
      out.push(frame);
    }
    return out;
  }
}
