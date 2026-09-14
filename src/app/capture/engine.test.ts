import { describe, expect, it } from 'vitest';
import { toBase64 } from './engine.ts';

/**
 * The audio envelope. Rust decodes exactly what this produces back into f32
 * samples, so a byte out of place here is noise in every transcription.
 */
describe('toBase64', () => {
  it('matches the platform encoder on float PCM bytes', () => {
    const samples = new Float32Array([0, 0.5, -0.5, 1, -1, 0.123456]);
    const bytes = new Uint8Array(samples.buffer);
    expect(toBase64(bytes)).toBe(Buffer.from(bytes).toString('base64'));
  });

  /*
   * A 200 ms chunk is 12,800 bytes, and spreading that many arguments into
   * String.fromCharCode in one call is what the slicing exists to avoid.
   */
  it('round-trips a chunk far larger than one slice', () => {
    const samples = new Float32Array(16_000 * 3).map((_, i) => Math.sin(i / 40));
    const bytes = new Uint8Array(samples.buffer);
    const decoded = new Float32Array(new Uint8Array(Buffer.from(toBase64(bytes), 'base64')).buffer);
    expect(decoded).toEqual(samples);
  });
});
