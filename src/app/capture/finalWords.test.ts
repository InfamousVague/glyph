import { describe, expect, it } from 'vitest';
import { withFinalWords } from './finalWords.ts';

/** The words a stopped decode added after the last phrase (capture/finalWords.ts). */

const heard = [
  { text: 'Weekend plans include', startMs: 0, endMs: 900 },
  { text: 'packing', startMs: 900, endMs: 1500 },
];

describe('the last words of a recording', () => {
  it('keeps what the stop’s transcript says past the phrases, as one more phrase to the end of the recording', () => {
    expect(withFinalWords(heard, 'Weekend plans include packing sunscreen and a hat.', 2600)).toEqual([
      ...heard,
      { text: 'sunscreen and a hat.', startMs: 1500, endMs: 2600 },
    ]);
  });

  it('matches the words however Whisper cased, accented and punctuated them the second time', () => {
    const cafe = [{ text: 'The café, on Main', startMs: 0, endMs: 1000 }];
    expect(withFinalWords(cafe, 'the cafe on main... opens at nine.', 1800).at(-1)).toEqual({ text: 'opens at nine.', startMs: 1000, endMs: 1800 });
  });

  it('takes the whole transcript when no phrase had arrived at all', () => {
    expect(withFinalWords([], 'Call Sam.', 1200)).toEqual([{ text: 'Call Sam.', startMs: 0, endMs: 1200 }]);
  });

  it('never ends the new phrase before it starts', () => {
    expect(withFinalWords(heard, 'Weekend plans include packing sunscreen', 1000).at(-1)).toEqual({ text: 'sunscreen', startMs: 1500, endMs: 1501 });
  });

  it('leaves the phrases as they were heard when the transcript says something else, nothing more, or nothing', () => {
    expect(withFinalWords(heard, 'Weekend plans exclude packing sunscreen', 2600)).toEqual(heard);
    expect(withFinalWords(heard, 'Weekend plans include packing.', 2600)).toEqual(heard);
    expect(withFinalWords(heard, 'Weekend plans', 2600)).toEqual(heard);
    expect(withFinalWords(heard, null, 2600)).toEqual(heard);
    expect(withFinalWords(heard, '   ', 2600)).toEqual(heard);
  });

  it('answers a copy, so the take’s own phrases are never the array that grows', () => {
    const answered = withFinalWords(heard, null, 2600);
    expect(answered).not.toBe(heard);
  });
});
