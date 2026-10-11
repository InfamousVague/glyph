import { describe, expect, it } from 'vitest';
import { bodyHash } from './bodyHash.ts';

/**
 * The hash is kept: a gist, the AI's marks and a run's record are written against it, in localStorage and in the
 * store's i64 column. So it must be the same number for the same text on every run and every device, a different one
 * for a text that differs by a character, and a number JSON carries without rounding.
 */
describe('the hash a kept thing is written against', () => {
  it('is the same for the same text, every time', () => {
    const body = '# Trip\n\n- [ ] call the plumber before Thursday\n';
    expect(bodyHash(body)).toBe(bodyHash(`${body}`));
    // Pinned: a change to the function would strand every gist and mark already kept against the old numbers.
    expect(bodyHash('')).toBe(0x29ce484222325);
    expect(bodyHash('call Sam')).toBe(2362324126580082);
  });

  it('tells apart texts that differ by one character, a case or a newline', () => {
    const hashes = new Set(['call Sam', 'call Sa m', 'Call Sam', 'call Sam\n', 'call Sam ', 'call Sán'].map(bodyHash));
    expect(hashes.size).toBe(6);
  });

  it('stays a whole number JSON and an i64 column carry unchanged', () => {
    for (const text of ['', 'x', 'a much longer note, with 🍞 and ünïcödé in it\n'.repeat(40)]) {
      const hash = bodyHash(text);
      expect(Number.isSafeInteger(hash)).toBe(true);
      expect(hash).toBeGreaterThanOrEqual(0);
      expect(JSON.parse(JSON.stringify(hash))).toBe(hash);
    }
  });
});
