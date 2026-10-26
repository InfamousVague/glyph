/**
 * One call's recording, from Discord's packets to the take's two files (docs/DISCORD_CALLS.md, "The recording"):
 *
 *   <work>/<id>.webm             the mix, Opus in WebM (webm.mjs), a Cluster appended every five seconds
 *   <work>/<id>.speech.ndjson    each person's speaking intervals as they close, `{speaker, start, end}` (Discord
 *                                ids and ms; the names are put on at the end, turns.mjs), so a crash keeps them too
 *
 * Each speaker's packets are decoded by a decoder of their own (codec.mjs), laid on the one timeline (mixer.mjs) and
 * their speaking noted (turns.mjs `Speech`); `tick` writes what the mixer has finished, encoded again. The bot calls
 * `tick` ten times a second; `stop` writes the rest and answers the intervals, for the speaker turns the take carries.
 *
 * The codec and the file writes are handed in, so the tests drive the whole of it with numbers.
 */
import { appendFileSync, writeFileSync } from 'node:fs';
import { FRAME_MS, Mixer, MIX } from './mixer.mjs';
import { SILENCE, Speech, TURNS } from './turns.mjs';
import { WebmOpusWriter } from './webm.mjs';

export class Recorder {
  constructor({ audioPath, speechPath, t0, codec, mix = MIX, turns = TURNS, append = appendFileSync, create = writeFileSync }) {
    this.audioPath = audioPath;
    this.speechPath = speechPath;
    this.t0 = t0;
    this.codec = codec;
    this.append = append;
    this.mixer = new Mixer({ t0, limits: mix });
    this.speech = new Speech({ limits: turns });
    this.decoders = new Map();
    this.encoder = codec.encoder();
    create(audioPath, Buffer.alloc(0));
    create(speechPath, '');
    this.writer = new WebmOpusWriter({ write: (bytes) => append(audioPath, bytes), frameMs: FRAME_MS });
    this.writer.start();
    /** Packets heard, those that would not decode, and the speakers heard at all. */
    this.packets = 0;
    this.broken = 0;
    this.speakers = new Set();
    this.stopped = false;
  }

  /** An Opus packet of `speaker`'s (a Discord user id), arrived at `at` (ms). */
  packet(speaker, opus, at) {
    if (this.stopped) return;
    let decoder = this.decoders.get(speaker);
    if (!decoder) {
      decoder = this.codec.decoder();
      this.decoders.set(speaker, decoder);
    }
    let pcm;
    try {
      pcm = decoder.decode(opus);
    } catch {
      this.broken += 1;
      return;
    }
    this.packets += 1;
    const silent = opus.length === SILENCE.length && opus.equals(SILENCE);
    if (!silent) this.speakers.add(speaker);
    const frame = this.mixer.place(speaker, pcm, at);
    const start = (frame ?? this.mixer.frameAt(at)) * FRAME_MS;
    const closed = this.speech.packet(speaker, start, Math.max(FRAME_MS, Math.round((pcm.length / 48_000) * 1000)), silent);
    if (closed) this.#keep([closed]);
  }

  /** What can be written at `now` (ms), written; intervals quiet long enough, kept. */
  tick(now) {
    if (this.stopped) return;
    for (const frame of this.mixer.drain(now)) this.writer.packet(this.encoder.encode(frame));
    this.#keep(this.speech.settle(now - this.t0));
  }

  /** The end: every frame written, the last Cluster, every interval. Answers what the take needs and the counts. */
  stop() {
    if (this.stopped) return this.result;
    this.stopped = true;
    for (const frame of this.mixer.finish()) this.writer.packet(this.encoder.encode(frame));
    this.writer.end();
    const intervals = this.speech.finish();
    const kept = new Set(this.keptIntervals ?? []);
    this.#keep(intervals.filter((i) => !kept.has(i)));
    for (const decoder of this.decoders.values()) decoder.close?.();
    this.encoder.close?.();
    this.result = { intervals, packets: this.packets, broken: this.broken, late: this.mixer.late, speakers: this.speakers.size, durationMs: this.writer.durationMs };
    return this.result;
  }

  #keep(intervals) {
    if (intervals.length === 0) return;
    this.keptIntervals = [...(this.keptIntervals ?? []), ...intervals];
    this.append(this.speechPath, intervals.map((i) => JSON.stringify({ speaker: i.speaker, start: i.start, end: i.end }) + '\n').join(''));
  }
}
