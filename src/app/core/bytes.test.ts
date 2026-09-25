import { describe, expect, it } from 'vitest';
import { toBase64, toHex } from './bytes.ts';
import { toBase64Url } from './sync/crypto.ts';

/** Bytes as text: standard base64 as Rust reads it, and hex as a digest is written. */

/** Every byte value, then a run long enough to cross a slice boundary more than once. */
function sample(length: number): Uint8Array {
  return Uint8Array.from({ length }, (_, i) => (i * 37 + (i >> 8)) & 0xff);
}

describe('bytes as base64', () => {
  it('is standard, padded base64, the same as Node writes it', () => {
    for (const length of [0, 1, 2, 3, 255, 0x8000, 0x8000 * 3 + 7]) {
      const bytes = sample(length);
      expect(toBase64(bytes)).toBe(Buffer.from(bytes).toString('base64'));
    }
  });

  it('is what the sync wire’s URL-safe text turns back into', () => {
    // What the sync engine used to do by hand before sending a recording to Rust: the same text, character for character.
    const bytes = sample(1000);
    const url = toBase64Url(bytes).replace(/-/g, '+').replace(/_/g, '/');
    expect(toBase64(bytes)).toBe(url + '='.repeat((4 - (url.length % 4)) % 4));
  });
});

describe('bytes as hex', () => {
  it('writes two lower-case digits a byte, a leading zero kept', () => {
    expect(toHex(new Uint8Array([0, 1, 15, 16, 171, 255]))).toBe('00010f10abff');
    expect(toHex(new Uint8Array())).toBe('');
  });
});
