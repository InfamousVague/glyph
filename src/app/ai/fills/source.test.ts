import { describe, expect, it } from 'vitest';
import { blanksIn } from '../../core/blanks.ts';
import { contentWords, fromThisNote, noteForSource } from './source.ts';
import { shapeOf } from './shape.ts';

/** Whether `answer` to the last blank of `text` reads as from this note. */
function fromNote(text: string, answer: string, scope = text): boolean {
  const blank = blanksIn(text).at(-1)!;
  return fromThisNote(answer, blank, shapeOf(blank, text).shape, text, scope);
}

describe('where an answer came from', () => {
  it('is this note when the answer stands in a sentence beside what was asked', () => {
    expect(fromNote('Sam said she would bring the charger and the dog food. I am booking the ferry.\n\nWho brings the charger? {?}', 'Sam')).toBe(true);
  });

  it('is memory when the words are in the note but not beside the question', () => {
    expect(fromNote('We watched France play in Qatar.\n\nThe 2022 World Cup was won by {?}', 'France')).toBe(false);
  });

  it('is memory for words the note lacks, and for an answer with no content words', () => {
    expect(fromNote('# Kitchen tap\n- [x] Found the leak under the sink\n- [ ] {?the next step}', 'Turn off the water and fit the new washer')).toBe(false);
    expect(fromNote('Is it done? {?}', 'no')).toBe(false);
  });

  it('reads a summary from its scope', () => {
    const note = '# Standup\n\nPriya: export bug fixed, in review, lands Tuesday. Tom: blocked on staging keys. We moved the launch to the 24th.\n\nIn one line: {?summary}';
    expect(fromNote(note, 'Priya fixed an export bug in review for Tuesday, Tom is blocked on staging keys, and the launch moved to the 24th.')).toBe(true);
  });

  it('never lets an earlier fill vouch for a later one', () => {
    const note = 'Who brings the charger? ??Sam??(Qwen3.5 4B from memory, 2026-09-28)\n\nWho brings the charger this time? {?}';
    expect(noteForSource(note)).not.toContain('Sam');
    expect(fromNote(note, 'Sam')).toBe(false);
  });

  it('compares words lower-cased, folded, a trailing s aside, numbers whole', () => {
    expect(contentWords('The Cafés, 1,200 bags and a Dog')).toEqual(['cafe', '1200', 'bag', 'dog']);
  });
});
