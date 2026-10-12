import { describe, expect, it } from 'vitest';
import { successorIn } from './macSuccessor.ts';

describe('the Mac app that comes after this one', () => {
  it('is offered only by a note of version 2 or later', () => {
    expect(successorIn({ version: '2.0.3', url: 'glyph.dmg' })).toBe('2.0.3');
    expect(successorIn({ version: '10.1.0' })).toBe('10.1.0');
    expect(successorIn({ version: '1.15.0' })).toBeNull();
    expect(successorIn({ version: 'two' })).toBeNull();
    expect(successorIn({})).toBeNull();
    expect(successorIn(null)).toBeNull();
    expect(successorIn('2.0.3')).toBeNull();
  });
});
