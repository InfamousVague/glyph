import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { heightMemory } from './heightMemory.ts';

const KEY = 'glyph-test-heights';
const tenths = (px: number) => Math.round(px * 10) / 10;

beforeEach(() => {
  vi.useFakeTimers();
  localStorage.removeItem(KEY);
});

afterEach(() => {
  vi.useRealTimers();
  localStorage.removeItem(KEY);
});

describe('remembered block heights', () => {
  it('knows nothing of a block never drawn, and the height, rounded its way, of one that was', () => {
    const memory = heightMemory(KEY, 10, tenths);
    expect(memory.known('To do:a|Done:b')).toBeNull();
    memory.keep('To do:a|Done:b', 212.349);
    expect(memory.known('To do:a|Done:b')).toBe(212.3);
    // Another block, however alike, is its own.
    expect(memory.known('To do:a|Done:c')).toBeNull();
  });

  it('writes once, half a second after the last change, under a short key that a later launch reads back', () => {
    const memory = heightMemory(KEY, 10, Math.round);
    memory.keep('graph TD\nA-->B', 180.4);
    memory.keep('graph TD\nA-->B', 181.2);
    vi.advanceTimersByTime(499);
    expect(localStorage.getItem(KEY)).toBeNull();
    vi.advanceTimersByTime(1);
    // The stored form is what builds before this one wrote and read: the text's length and its FNV-1a hash, base 36.
    expect(JSON.parse(localStorage.getItem(KEY) ?? 'null')).toEqual([['e.1rmy62q', 181]]);
    expect(heightMemory(KEY, 10, Math.round).known('graph TD\nA-->B')).toBe(181);
  });

  it('lets the oldest go first once it holds as many as it keeps, a block drawn again counting as new', () => {
    const memory = heightMemory(KEY, 2, Math.round);
    memory.keep('one', 10);
    memory.keep('two', 20);
    memory.keep('one', 11);
    memory.keep('three', 30);
    expect(memory.known('two')).toBeNull();
    expect(memory.known('one')).toBe(11);
    expect(memory.known('three')).toBe(30);
  });

  it('reads what was kept before it only when first asked, and takes nothing it cannot read', () => {
    localStorage.setItem(KEY, JSON.stringify([['e.1rmy62q', 90], ['not a pair'], [3, 4]]));
    const memory = heightMemory(KEY, 10, Math.round);
    localStorage.setItem(KEY, JSON.stringify([['e.1rmy62q', 95]]));
    expect(memory.known('graph TD\nA-->B')).toBe(95);
    localStorage.setItem(KEY, '{not json');
    expect(heightMemory(KEY, 10, Math.round).known('graph TD\nA-->B')).toBeNull();
  });
});
