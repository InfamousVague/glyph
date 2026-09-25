import { describe, expect, it } from 'vitest';
import { appendsTo, onTape, shifted } from './timeline.ts';

/** A take on the tape of the note it is kept with (capture/timeline.ts): what is appended, and where each piece lands. */

describe('a take’s stretches on its note’s tape', () => {
  it('move later by the tape the note already had, keeping what else they carry', () => {
    const clip = { text: '![voice 0:05](tape:0-5000)', startMs: 0, endMs: 5000 };
    expect(shifted([clip, { startMs: 6000, endMs: 7000 }], 12_000)).toEqual([
      { text: '![voice 0:05](tape:0-5000)', startMs: 12_000, endMs: 17_000 },
      { startMs: 18_000, endMs: 19_000 },
    ]);
    expect(shifted([], 500)).toEqual([]);
  });
});

describe('which tape a take goes on the end of', () => {
  it('is only a tape the continued note still has', () => {
    expect(appendsTo({ recordingMs: 30_000 })).toBe(true);
    // A recording removed from the note leaves its file behind: the take starts the file afresh.
    expect(appendsTo({ recordingMs: 0 })).toBe(false);
    expect(appendsTo({ recordingMs: null })).toBe(false);
    expect(appendsTo({})).toBe(false);
    expect(appendsTo(null)).toBe(false);
  });
});

describe('a take on its note’s tape', () => {
  const take = {
    commandSpans: [{ startMs: 0, endMs: 1800 }],
    clips: [{ text: '![voice 0:02](tape:4000-6000)', startMs: 4000, endMs: 6000 }],
    keywordSpans: [{ startMs: 2000, endMs: 3500 }],
  };
  const spoken = [{ text: 'Call Sam.', startMs: 2000, endMs: 3500 }];

  it('puts every piece after the tape the continued note already had, and keeps its phrases before them', () => {
    const before = [{ text: 'Eggs.', startMs: 0, endMs: 900 }];
    const placed = onTape({ recordingMs: 30_000, segments: before }, take, spoken);
    expect(placed).toEqual({
      fromMs: 30_000,
      prior: before,
      segments: [before[0], { text: 'Call Sam.', startMs: 32_000, endMs: 33_500 }],
      skip: [{ startMs: 30_000, endMs: 31_800 }],
      clips: [{ text: '![voice 0:02](tape:4000-6000)', startMs: 34_000, endMs: 36_000 }],
      keywordAt: [{ startMs: 32_000, endMs: 33_500 }],
    });
  });

  it('starts a new note’s tape, or one whose recording was removed, at nothing', () => {
    for (const continued of [null, { recordingMs: 0, segments: null }]) {
      const placed = onTape(continued, take, spoken);
      expect(placed.fromMs).toBe(0);
      expect(placed.prior).toEqual([]);
      expect(placed.segments).toEqual(spoken);
      expect(placed.skip).toEqual(take.commandSpans);
      expect(placed.clips).toEqual(take.clips);
      expect(placed.keywordAt).toEqual(take.keywordSpans);
    }
  });
});
