import { describe, expect, it } from 'vitest';
import type { Shared } from '../app/share/share.ts';
import { Frames, heardAt, meetingOf, readWav, seekFor, speakerOf, summaryOf, timelineOf, wantsMore, wavHeader, audioContext, type Meeting } from './meeting.ts';

/*
 * A shared meeting as the page reads it (meeting.ts): which phrase is heard at a moment, where a tap takes the tape,
 * what Summary shows, and the recording's parts and WAV read as they arrive.
 */

const shared = (meeting: unknown, kind: 'note' | 'book' = 'note'): Shared => ({ v: 1, kind, title: 'Launch sync', pages: [{ title: 'Launch sync', body: '# Launch sync' }], at: 9, meeting } as Shared);

const words = {
  ms: 90000,
  hue: 'teal',
  at: 1_760_000_000_000,
  speakers: ['Sam Lee', 'Ana'],
  turns: [
    { s: 0, p: [[0, 2000, 'Good morning everyone.'], [2000, 4800, 'The checklist is first.']] },
    { s: 1, p: [[5000, 7000, 'Thanks.']] },
    { s: -1, p: [[-1, -1, 'Said with no time.']] },
    { s: 0, p: [[9000, 12000, 'Last thing.']] },
  ],
  audio: { upload: 'up', parts: 2, bytes: 100, mime: 'audio/wav', ms: 90000, chunk: 64 },
};

describe('a shared meeting', () => {
  it('is read from what the share carries, and nothing is made up for what it does not', () => {
    const meeting = meetingOf(shared(words))!;
    expect(meeting.speakers).toEqual(['Sam Lee', 'Ana']);
    expect(meeting.turns).toHaveLength(4);
    expect(meeting.audio).toEqual(words.audio);
    expect(meeting.hue).toBe('teal');
    expect(speakerOf(meeting, meeting.turns[1]!)).toBe('Ana');
    expect(speakerOf(meeting, meeting.turns[2]!)).toBeNull();
    // An older build's share, a book, and a meeting with broken parts.
    expect(meetingOf(shared(undefined))).toBeNull();
    expect(meetingOf(shared(words, 'book'))).toBeNull();
    const broken = meetingOf(shared({ speakers: ['A'], turns: [{ s: 7, p: [[0, 1, 'kept'], ['x', 1, 'dropped']] }, { s: 0, p: [] }], audio: { upload: 3 } }))!;
    expect(broken.turns).toEqual([{ s: -1, p: [[0, 1, 'kept']] }]);
    expect(broken.audio).toBeUndefined();
    expect(broken.at).toBe(9);
  });

  it('lights the last phrase begun: through the quiet after it, never one with no time, and nothing before the first', () => {
    const timeline = timelineOf(meetingOf(shared(words))!);
    expect(timeline.starts).toEqual([0, 2000, 5000, 9000]);
    expect(heardAt(timeline, 0)).toEqual({ turn: 0, phrase: 0 });
    expect(heardAt(timeline, 1999)).toEqual({ turn: 0, phrase: 0 });
    expect(heardAt(timeline, 2000)).toEqual({ turn: 0, phrase: 1 });
    // The quiet after a phrase is still it, and the phrase with no time is never lit.
    expect(heardAt(timeline, 4900)).toEqual({ turn: 0, phrase: 1 });
    expect(heardAt(timeline, 8000)).toEqual({ turn: 1, phrase: 0 });
    expect(heardAt(timeline, 80_000)).toEqual({ turn: 3, phrase: 0 });
    const late: Meeting = { ms: 1, at: 0, speakers: [], turns: [{ s: -1, p: [[3000, 4000, 'late']] }] };
    expect(heardAt(timelineOf(late), 100)).toBeNull();
  });

  it('finds the phrase heard by halves, as a walk over an hour of them would', () => {
    const turns = Array.from({ length: 3000 }, (_, i) => ({ s: i % 3, p: [[i * 1200, i * 1200 + 1000, `phrase ${i}`]] }));
    const timeline = timelineOf(meetingOf(shared({ ...words, turns }))!);
    for (const ms of [0, 1, 1199, 1200, 1_234_567, 3_599_999, 9_999_999]) {
      const walked = turns.reduce((last, turn, i) => (turn.p[0]![0] as number) <= ms ? i : last, -1);
      expect(heardAt(timeline, ms)?.turn ?? -1).toBe(walked);
    }
  });

  it('takes the tape to a phrase’s start when it is tapped, and nowhere for one with no time', () => {
    expect(seekFor([5000, 7000, 'Thanks.'])).toBe(5000);
    expect(seekFor([-1, -1, 'Said with no time.'])).toBeNull();
  });

  it('shows the note without its transcript, its captions or its title under Summary', () => {
    const body = '# Launch sync\n\nGhost was in this meeting.\n\n## Summary\nWhat it settled.\n\n- Launch moves.\n\n## Captions\n\n**Sam (0:01):** hi\n\n## Notes after\n\nKept.\n\n## Transcript\n\n**Sam Lee (0:00):** Good morning.';
    expect(summaryOf(body, 'Launch sync')).toBe('Ghost was in this meeting.\n\n## Summary\nWhat it settled.\n\n- Launch moves.\n\n## Notes after\n\nKept.');
    expect(summaryOf('# Other\n\nWords.', 'Launch sync')).toBe('# Other\n\nWords.');
  });
});

describe('a shared recording’s parts', () => {
  const framed = (...parts: number[][]) => {
    const out: number[] = [];
    for (const part of parts) out.push((part.length >>> 24) & 255, (part.length >>> 16) & 255, (part.length >>> 8) & 255, part.length & 255, ...part);
    return Uint8Array.from(out);
  };

  it('are read whole however the network cuts them, and a cut-short stream is known', () => {
    const bytes = framed([1, 2, 3], [], [4, 5, 6, 7, 8]);
    for (const size of [1, 2, 3, 5, 7, bytes.length]) {
      const frames = new Frames();
      const got: number[][] = [];
      for (let at = 0; at < bytes.length; at += size) got.push(...frames.push(bytes.subarray(at, at + size)).map((part) => [...part]));
      expect(got).toEqual([[1, 2, 3], [], [4, 5, 6, 7, 8]]);
      expect(frames.pending).toBe(false);
    }
    const short = new Frames();
    expect(short.push(bytes.subarray(0, 9))).toHaveLength(1);
    expect(short.pending).toBe(true);
  });

  it('are sealed each in a context naming the upload, the part and how many there are', () => {
    expect(audioContext('up', 0, 3)).toBe('glyph/v1/share-audio/up/0/3');
  });

  it('play as far as they have come: the WAV read, and a header written for the sound so far', () => {
    // A 16 kHz mono 16-bit WAV with a LIST chunk before its sound, as a recorder may write one.
    const fmt = new Uint8Array(16);
    const f = new DataView(fmt.buffer);
    f.setUint16(0, 1, true);
    f.setUint16(2, 1, true);
    f.setUint32(4, 16000, true);
    f.setUint32(8, 32000, true);
    f.setUint16(12, 2, true);
    f.setUint16(14, 16, true);
    const ascii = (s: string) => [...s].map((c) => c.charCodeAt(0));
    const le = (n: number) => [n & 255, (n >>> 8) & 255, (n >>> 16) & 255, (n >>> 24) & 255];
    const head = Uint8Array.from([...ascii('RIFF'), ...le(0), ...ascii('WAVE'), ...ascii('fmt '), ...le(16), ...fmt, ...ascii('LIST'), ...le(4), ...ascii('INFO'), ...ascii('data'), ...le(64000), 9, 9]);
    const wav = readWav(head)!;
    expect(wav).toMatchObject({ dataOffset: 56, dataSize: 64000, byteRate: 32000, blockAlign: 2 });
    const header = wavHeader(wav, 32000);
    expect(readWav(Uint8Array.from([...header, 0, 0]))).toMatchObject({ dataOffset: 44, dataSize: 32000, byteRate: 32000 });
    expect(new DataView(header.buffer).getUint32(4, true)).toBe(header.length - 8 + 32000);
    expect(readWav(Uint8Array.from(ascii('not a wav at all')))).toBeNull();
  });

  it('are given to the tape again while it plays near the end of what it has, once more has come', () => {
    expect(wantsMore(28_000, 30_000, 60_000)).toBe(true);
    expect(wantsMore(20_000, 30_000, 60_000)).toBe(false);
    // Nothing more has come.
    expect(wantsMore(29_900, 30_000, 30_100)).toBe(false);
  });
});
