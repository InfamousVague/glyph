import { describe, expect, it } from 'vitest';
import { kindWords } from '../ai/kinds.ts';
import { MODES } from './modes.ts';

describe('the robot’s three modes', () => {
  it('are Format, Summarize and Enhance, in the order the note’s cog lists them', () => {
    expect(MODES.map((mode) => mode.id)).toEqual(['format', 'summarize', 'enhance']);
    expect(MODES.map((mode) => mode.label)).toEqual(['Format', 'Summarize', 'Enhance']);
  });

  it('say what the chips and the strip say about the same run', () => {
    for (const mode of MODES) expect(mode).toEqual(kindWords(mode.id));
  });
});
