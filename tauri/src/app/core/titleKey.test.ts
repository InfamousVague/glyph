import { describe, expect, it } from 'vitest';
import { titleKey } from './titleKey.ts';

describe('a title as it is matched', () => {
  it('keys titles the way links are matched', () => {
    expect(titleKey('  The Oaks!  ')).toBe('the oaks');
    expect(titleKey('oaks')).toBe(titleKey('Oaks'));
  });

  it('makes every run of punctuation and space one space, so a title said aloud finds the note however it was written', () => {
    expect(titleKey('Weekend trip - packing, list')).toBe('weekend trip packing list');
    expect(titleKey('weekend trip packing list')).toBe('weekend trip packing list');
    expect(titleKey('AttackFM/bugbash_2')).toBe('attackfm bugbash 2');
  });

  it('is empty for a title with nothing but punctuation, which matches nothing', () => {
    expect(titleKey('  -- !! ')).toBe('');
    expect(titleKey('')).toBe('');
  });
});
