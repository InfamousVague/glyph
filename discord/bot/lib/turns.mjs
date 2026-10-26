/**
 * Who spoke when in a Discord call, for the device to name Whisper's phrases by (docs/DISCORD_CALLS.md, "Who said
 * what"). A Meet take carries Meet's captions, `{at, speaker, text}` a line; Discord has no captions, but it says
 * exactly who is speaking, since each person's sound is a stream of its own. So the take carries the same NDJSON with
 * no words: a line `{at, speaker, text: ""}` each time the floor passes to someone, which is what the device reads a
 * caption's speaker for (lib/meet/speakers.dart: a turn lasts from its first line to the next one's; each phrase is
 * given the speaker whose turn overlaps it longest).
 *
 * SPEAKING ([Speech]): a person is speaking from a packet that is not Discord's silence frame until `gapMs` passes
 * with none; that is one interval, `{speaker, start, end}` in ms of the recording.
 *
 * THE FLOOR ([speakerTurns]): at each moment, of those speaking, the one who began last; when they stop, the one
 * still speaking who began last before them. So a long talk with an "mm-hm" over it is the talker's again after the
 * "mm-hm". An interval shorter than `minMs` (a cough, a laugh, a word) never takes the floor: the device would cut a
 * paragraph for it. A line is written only when the floor passes to someone else than had it last.
 *
 * THE LAG. The device moves every turn `lagMs` earlier, since Meet's captions show a moment after the words are said
 * (lib/meet/speakers.dart `captionLagMs`, a second). Discord's turns have no lag, so each line's `at` is written that
 * much later than the speaking began, to land where it was. test/turns.test.mjs reads the Dart constant to keep the
 * two the same.
 *
 * Pure: speakers are ids; their names are handed in at the end, and never logged.
 */

/** Discord's silence frame, sent five times as a person stops speaking: no voice in it. */
export const SILENCE = Buffer.from([0xf8, 0xff, 0xfe]);

export const TURNS = {
  /** Quiet this long ends a person's interval. */
  gapMs: 600,
  /** An interval shorter than this never takes the floor. */
  minMs: 400,
  /** lib/meet/speakers.dart `captionLagMs`. */
  lagMs: 1000,
};

/** Each person's speaking, as intervals. */
export class Speech {
  constructor({ limits = TURNS } = {}) {
    this.limits = limits;
    /** Open intervals by speaker. */
    this.open = new Map();
    /** Closed intervals, in the order they closed. */
    this.closed = [];
  }

  /**
   * A packet of `speaker`'s covering `[at, at + ms)` of the recording (ms). Silence frames are passed over: they are
   * the end of speaking, not more of it. Answers the interval it closed, if this packet began a new one.
   */
  packet(speaker, at, ms, silent = false) {
    if (silent) return null;
    const open = this.open.get(speaker);
    if (open && at - open.end <= this.limits.gapMs) {
      open.end = Math.max(open.end, at + ms);
      return null;
    }
    this.open.set(speaker, { speaker, start: at, end: at + ms });
    if (!open) return null;
    this.closed.push(open);
    return open;
  }

  /** The intervals quiet for `gapMs` at `now` (ms of the recording) closed; answers them. */
  settle(now) {
    const done = [];
    for (const [speaker, open] of this.open) {
      if (now - open.end > this.limits.gapMs) {
        this.open.delete(speaker);
        this.closed.push(open);
        done.push(open);
      }
    }
    return done;
  }

  /** Every interval, the open ones closed: the call is over. In order of their start. */
  finish() {
    for (const open of this.open.values()) this.closed.push(open);
    this.open.clear();
    return [...this.closed].sort((a, b) => a.start - b.start || a.end - b.end);
  }
}

/**
 * The turns of `intervals` (`[{speaker, start, end}]`, ms), as the NDJSON lines the take carries: `{at, speaker,
 * text: ""}`, `at` with the lag added (see the header), `speaker` the name `names` gives the id ("Someone" where it
 * has none).
 */
export function speakerTurns(intervals, names = new Map(), limits = TURNS) {
  const kept = intervals.filter((i) => i.end - i.start >= limits.minMs).sort((a, b) => a.start - b.start || a.end - b.end);
  // Every moment the floor may change: an interval beginning or ending.
  const moments = [...new Set(kept.flatMap((i) => [i.start, i.end]))].sort((a, b) => a - b);
  const lines = [];
  let last = null;
  for (const at of moments) {
    // Speaking at `at`: begun by then and not yet over. Of those, the one who began last.
    let holder = null;
    for (const i of kept) {
      if (i.start > at) break;
      if (i.end > at && (holder == null || i.start >= holder.start)) holder = i;
    }
    if (!holder || holder.speaker === last) continue;
    last = holder.speaker;
    // The floor passes at `at`: a new interval's start, or the moment the one who had it stopped.
    lines.push({ at: Math.max(0, Math.round(at)) + limits.lagMs, speaker: nameOf(names, holder.speaker), text: '' });
  }
  return lines;
}

const nameOf = (names, speaker) => {
  const name = String(names.get(speaker) ?? '').replace(/\s+/g, ' ').trim();
  return name || 'Someone';
};

/** The lines as the take's NDJSON part. */
export const ndjson = (lines) => lines.map((line) => JSON.stringify(line) + '\n').join('');
