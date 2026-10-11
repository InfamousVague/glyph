import { describe, expect, it } from 'vitest';
import { MODES } from './modes.ts';

describe('the robot’s three modes', () => {
  it('are Format, Summarize and Enhance, in the order the note’s cog lists them', () => {
    expect(MODES.map((mode) => mode.id)).toEqual(['format', 'summarize', 'enhance']);
  });

  it('say in the cog what each does, under its word', () => {
    // The words editor/NoteSettings.tsx draws for each row: the label, and the hint under it.
    expect(MODES.map(({ label, hint }) => ({ label, hint }))).toEqual([
      { label: 'Format', hint: 'Tidy and organise, keeping every word that matters.' },
      { label: 'Summarize', hint: 'The point of the note and its tasks, in far fewer words.' },
      { label: 'Enhance', hint: 'Every thought finished and the note made fuller, without inventing.' },
    ]);
  });
});
