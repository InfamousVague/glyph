import { describe, expect, it } from 'vitest';
import { createResampler } from './audio.ts';

/**
 * The resampler exists for the platform that ignores `sampleRate: 16000`. If it
 * is wrong, Whisper hears speech at the wrong speed and transcribes nothing,
 * with no error anywhere - so its arithmetic is pinned here.
 */

const sine = (rate: number, seconds: number, hz: number) =>
  Float32Array.from({ length: Math.round(rate * seconds) }, (_, i) => Math.sin((2 * Math.PI * hz * i) / rate));

describe('createResampler', () => {
  it('passes 16 kHz through untouched', () => {
    const input = sine(16_000, 0.1, 440);
    expect(createResampler(16_000, 16_000)(input)).toBe(input);
  });

  it('turns one second at 48 kHz into one second at 16 kHz', () => {
    const out = createResampler(48_000, 16_000)(sine(48_000, 1, 440));
    expect(out.length).toBe(16_000);
  });

  it('handles a non-integer ratio (44.1 kHz) without drifting', () => {
    const out = createResampler(44_100, 16_000)(sine(44_100, 2, 440));
    expect(Math.abs(out.length - 32_000)).toBeLessThanOrEqual(1);
  });

  /*
   * The worklet hands over 200 ms at a time. Resampling chunk by chunk has to
   * give the same samples as resampling the whole, or every boundary is a click.
   */
  it('gives the same output whether fed whole or in chunks', () => {
    const input = sine(48_000, 1, 300);
    const whole = createResampler(48_000, 16_000)(input);
    const chunked = createResampler(48_000, 16_000);
    const parts: number[] = [];
    for (let i = 0; i < input.length; i += 9_600) parts.push(...chunked(input.subarray(i, i + 9_600)));
    expect(parts.length).toBe(whole.length);
    expect(Math.max(...parts.map((v, i) => Math.abs(v - (whole[i] ?? 0))))).toBeLessThan(1e-6);
  });

  it('keeps a speech-band tone recognisable after decimation', () => {
    const out = createResampler(48_000, 16_000)(sine(48_000, 0.5, 300));
    const expected = sine(16_000, 0.5, 300);
    // Box averaging over 3 samples attenuates 300 Hz by well under 1 dB, and
    // shifts phase by one input sample; correlation stays close to 1.
    let dot = 0;
    let a = 0;
    let b = 0;
    for (let i = 0; i < out.length; i += 1) {
      dot += (out[i] ?? 0) * (expected[i] ?? 0);
      a += (out[i] ?? 0) ** 2;
      b += (expected[i] ?? 0) ** 2;
    }
    expect(dot / Math.sqrt(a * b)).toBeGreaterThan(0.98);
  });
});
