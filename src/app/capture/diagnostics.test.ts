import { describe, expect, it } from 'vitest';
import { describe as describeCounts, diagnosticsLine, EMPTY_DIAGNOSTICS, soundsSilent } from './diagnostics.ts';

/** The recorder's diagnostics line (capture/diagnostics.ts): the one that told the Fold's silent capture apart. */

describe('what the pipeline has done, in a line', () => {
  it('says how much was heard, at what rate, and what came of it, one or many', () => {
    expect(describeCounts({ ...EMPTY_DIAGNOSTICS, heardSamples: 131_200, deviceRate: 48_000, partials: 3, segments: 1 })).toBe('heard 8.2 s at 48 kHz · 3 guesses · 1 phrase');
    expect(describeCounts({ ...EMPTY_DIAGNOSTICS, partials: 1, segments: 2 })).toBe('heard 0.0 s · 1 guess · 2 phrases');
  });

  it('ends with the errors and the last of them', () => {
    expect(describeCounts({ ...EMPTY_DIAGNOSTICS, errors: 2, lastError: 'capture_push rejected' })).toBe('heard 0.0 s · 0 guesses · 0 phrases · 2 errors: capture_push rejected');
    expect(describeCounts({ ...EMPTY_DIAGNOSTICS, errors: 1, lastError: null })).toMatch(/1 error: $/);
  });

  it('opens with the engine once one is listening', () => {
    expect(diagnosticsLine('whisper', EMPTY_DIAGNOSTICS)).toBe('On-device Whisper · heard 0.0 s · 0 guesses · 0 phrases');
    expect(diagnosticsLine(null, EMPTY_DIAGNOSTICS)).toBe('heard 0.0 s · 0 guesses · 0 phrases');
  });
});

describe('a capture worth explaining unasked', () => {
  const heardLong = { ...EMPTY_DIAGNOSTICS, heardSamples: 8 * 16_000 + 1 };

  it('is Whisper hearing more than eight seconds and making nothing of it', () => {
    expect(soundsSilent('whisper', heardLong)).toBe(true);
  });

  it('is not one that made a guess or a phrase, heard less, or ran on another engine', () => {
    expect(soundsSilent('whisper', { ...heardLong, partials: 1 })).toBe(false);
    expect(soundsSilent('whisper', { ...heardLong, segments: 1 })).toBe(false);
    expect(soundsSilent('whisper', { ...heardLong, heardSamples: 8 * 16_000 })).toBe(false);
    expect(soundsSilent('browser', heardLong)).toBe(false);
    expect(soundsSilent(null, heardLong)).toBe(false);
  });
});
