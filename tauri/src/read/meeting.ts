import type { Shared } from '../app/share/share.ts';

/*
 * A shared meeting, as the page reads it (lib/share/share_audio.dart writes it; docs/SHARING.md, "A meeting's
 * recording"): the turns with their times, the recording's parts and how they are sealed, and which turn is being
 * heard. Pure, so every rule is tested (meeting.test.ts); MeetingRead.tsx draws it and shareAudio.ts fetches the sound.
 */

/** A phrase: when it began and ended in ms (-1 for neither, where nothing said), and its words. */
export type Phrase = [startMs: number, endMs: number, text: string];

/** A speaker's run of phrases; `s` is an index into the speakers, -1 for nobody named. */
export interface Turn {
  s: number;
  p: Phrase[];
}

/** The recording the share carries, as the words name it. */
export interface SharedAudio {
  upload: string;
  parts: number;
  bytes: number;
  mime: string;
  ms: number;
  chunk: number;
}

export interface Meeting {
  /** How long the recording is, in ms. */
  ms: number;
  /** The cassette's colour in the app (lib/tapes/tape_art.dart `tapeHue`). */
  hue?: string;
  /** When it was, in ms. */
  at: number;
  speakers: string[];
  turns: Turn[];
  audio?: SharedAudio;
}

const isNumber = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value);

/** The meeting a share carries, read with care: null for anything else, or a share from before meetings were shared. */
export function meetingOf(shared: Shared): Meeting | null {
  const raw = (shared as Shared & { meeting?: unknown }).meeting;
  if (shared.kind !== 'note' || !raw || typeof raw !== 'object') return null;
  const m = raw as Record<string, unknown>;
  const speakers = Array.isArray(m.speakers) ? m.speakers.map((s) => (typeof s === 'string' ? s : '')) : [];
  const turns: Turn[] = [];
  for (const turn of Array.isArray(m.turns) ? m.turns : []) {
    if (!turn || typeof turn !== 'object') continue;
    const t = turn as { s?: unknown; p?: unknown };
    const phrases: Phrase[] = [];
    for (const p of Array.isArray(t.p) ? t.p : []) {
      if (Array.isArray(p) && isNumber(p[0]) && isNumber(p[1]) && typeof p[2] === 'string') phrases.push([p[0], p[1], p[2]]);
    }
    const s = isNumber(t.s) && t.s >= 0 && t.s < speakers.length ? t.s : -1;
    if (phrases.length) turns.push({ s, p: phrases });
  }
  const a = m.audio as Record<string, unknown> | undefined;
  const audio =
    a && typeof a.upload === 'string' && isNumber(a.parts) && a.parts > 0 && isNumber(a.bytes) && typeof a.mime === 'string'
      ? { upload: a.upload, parts: a.parts, bytes: a.bytes, mime: a.mime, ms: isNumber(a.ms) ? a.ms : 0, chunk: isNumber(a.chunk) ? a.chunk : 1 << 20 }
      : undefined;
  return { ms: isNumber(m.ms) ? m.ms : 0, hue: typeof m.hue === 'string' ? m.hue : undefined, at: isNumber(m.at) ? m.at : shared.at, speakers, turns, audio };
}

/** A phrase found by where it is: its turn, and its place in the turn. */
export interface At {
  turn: number;
  phrase: number;
}

/** Every timed phrase, in the order spoken, with where it is: what `heardAt` searches. */
export interface Timeline {
  starts: number[];
  at: At[];
}

export function timelineOf(meeting: Meeting): Timeline {
  const starts: number[] = [];
  const at: At[] = [];
  meeting.turns.forEach((turn, t) =>
    turn.p.forEach(([start], p) => {
      // A phrase with no time is read, not lit; and the times never fall, so one that would is left out.
      if (start < 0 || (starts.length && start < starts[starts.length - 1]!)) return;
      starts.push(start);
      at.push({ turn: t, phrase: p });
    }),
  );
  return { starts, at };
}

/**
 * The phrase being heard at `ms` (lib/tapes/transcript_words.dart `litAt`): the last one begun by then, lit through
 * the quiet after it until the next begins; null before the first. By halves, so an hour's thousands of phrases cost a
 * dozen looks a tick.
 */
export function heardAt(timeline: Timeline, ms: number): At | null {
  let low = 0;
  let high = timeline.starts.length;
  while (low < high) {
    const mid = (low + high) >> 1;
    if (timeline.starts[mid]! <= ms) low = mid + 1;
    else high = mid;
  }
  return low > 0 ? timeline.at[low - 1]! : null;
}

/** Where a click on a phrase takes the tape: its start, or nowhere for one with no time. */
export function seekFor(phrase: Phrase): number | null {
  return phrase[0] >= 0 ? phrase[0] : null;
}

/** The speaker's name for a turn, or null for nobody named. */
export function speakerOf(meeting: Meeting, turn: Turn): string | null {
  const name = turn.s >= 0 ? meeting.speakers[turn.s] : undefined;
  return name ? name : null;
}

/**
 * The note's words for Summary: everything but the transcript and the captions, which are Transcript's, and the title,
 * which the page sets above the toggle.
 */
export function summaryOf(body: string, title: string): string {
  const lines = body.split('\n');
  const out: string[] = [];
  let skipping = false;
  let titled = false;
  for (const line of lines) {
    if (/^## (Transcript|Captions)[ \t]*$/.test(line)) {
      skipping = true;
      continue;
    }
    if (skipping && /^## /.test(line)) skipping = false;
    if (skipping) continue;
    if (!titled && /^#\s/.test(line) && line.replace(/^#\s+/, '').trim() === title.trim()) {
      titled = true;
      continue;
    }
    out.push(line);
  }
  return out.join('\n').replace(/^\s*\n/, '').trimEnd();
}

/** The tape counter: "0:07", "12:40", "1:02:03" (capture/tape.ts `counter`). */
export { counter as clock } from '../app/capture/tape.ts';

// ---- the recording's parts ------------------------------------------------------------------------------------------

/** The context part `n` of `parts` of an upload is sealed in (lib/share/share_audio.dart `audioPartContext`). */
export function audioContext(upload: string, n: number, parts: number): string {
  return `glyph/v1/share-audio/${upload}/${n}/${parts}`;
}

/**
 * The parts out of what the service streams (server/src/shares.rs: each part as its length, four bytes big-endian,
 * then its bytes), as they come: bytes are pushed in whatever pieces the network hands over, and each whole part is
 * handed back once its last byte is in.
 */
export class Frames {
  private held: Uint8Array = new Uint8Array(0);

  push(piece: Uint8Array): Uint8Array[] {
    const joined = new Uint8Array(this.held.length + piece.length);
    joined.set(this.held, 0);
    joined.set(piece, this.held.length);
    const out: Uint8Array[] = [];
    let at = 0;
    while (joined.length - at >= 4) {
      const length = new DataView(joined.buffer, joined.byteOffset + at, 4).getUint32(0);
      if (joined.length - at - 4 < length) break;
      out.push(joined.slice(at + 4, at + 4 + length));
      at += 4 + length;
    }
    this.held = joined.slice(at);
    return out;
  }

  /** Whether bytes are left over that make no whole part: a stream cut short. */
  get pending(): boolean {
    return this.held.length > 0;
  }
}

/** What a WAV says of itself: where its sound starts, how long it says the sound is, and its format. */
export interface Wav {
  dataOffset: number;
  /** The sound's length as the file says it; 0 or past the file where it was written before it was known. */
  dataSize: number;
  fmt: Uint8Array;
  byteRate: number;
  blockAlign: number;
}

/** The WAV's chunks read from its first bytes, or null for something that is not a WAV of PCM. */
export function readWav(head: Uint8Array): Wav | null {
  const text = (at: number) => String.fromCharCode(...head.subarray(at, at + 4));
  if (head.length < 12 || text(0) !== 'RIFF' || text(8) !== 'WAVE') return null;
  const view = new DataView(head.buffer, head.byteOffset, head.byteLength);
  let at = 12;
  let fmt: Uint8Array | null = null;
  while (at + 8 <= head.length) {
    const id = text(at);
    const size = view.getUint32(at + 4, true);
    if (id === 'fmt ') fmt = head.slice(at + 8, at + 8 + size);
    if (id === 'data') {
      if (!fmt || fmt.length < 16) return null;
      const f = new DataView(fmt.buffer, fmt.byteOffset, fmt.byteLength);
      return { dataOffset: at + 8, dataSize: size, fmt, byteRate: f.getUint32(8, true), blockAlign: f.getUint16(12, true) };
    }
    at += 8 + size + (size % 2);
  }
  return null;
}

/** A WAV's header for `dataLength` bytes of its sound: what lets a part of the recording play before the rest is in. */
export function wavHeader(wav: Wav, dataLength: number): Uint8Array {
  const out = new Uint8Array(12 + 8 + wav.fmt.length + 8);
  const view = new DataView(out.buffer);
  const put = (at: number, text: string) => [...text].forEach((c, i) => (out[at + i] = c.charCodeAt(0)));
  put(0, 'RIFF');
  view.setUint32(4, out.length - 8 + dataLength, true);
  put(8, 'WAVE');
  put(12, 'fmt ');
  view.setUint32(16, wav.fmt.length, true);
  out.set(wav.fmt, 20);
  put(20 + wav.fmt.length, 'data');
  view.setUint32(24 + wav.fmt.length, dataLength, true);
  return out;
}

/**
 * Whether the tape has to be given more of the recording now: it plays within `marginMs` of the end of what it was
 * given, and more has come since. What lets it start on the first part and carry on as the rest arrives.
 */
export function wantsMore(atMs: number, givenMs: number, loadedMs: number, marginMs = 2500): boolean {
  return loadedMs > givenMs + 250 && atMs >= givenMs - marginMs;
}
