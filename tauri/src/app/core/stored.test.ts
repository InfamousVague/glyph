import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { readStored, readStoredShared, readStoredText, storedFlag, storedKeys, writeStored, writeStoredText } from './stored.ts';

/** Storage that will not answer: a private window, a webview with site data off. */
function refuse(): void {
  const no = () => {
    throw new DOMException('The operation is insecure.', 'SecurityError');
  };
  vi.spyOn(Storage.prototype, 'getItem').mockImplementation(no);
  vi.spyOn(Storage.prototype, 'setItem').mockImplementation(no);
  vi.spyOn(Storage.prototype, 'removeItem').mockImplementation(no);
  vi.spyOn(Storage.prototype, 'key').mockImplementation(no);
}

beforeEach(() => localStorage.clear());
afterEach(() => vi.restoreAllMocks());

describe('reading and writing a value', () => {
  it('answers the fallback for nothing kept, for text that is not JSON, and for a shape the caller will not have', () => {
    const list = (raw: unknown) => (Array.isArray(raw) ? raw.filter((x): x is string => typeof x === 'string') : null);
    expect(readStored('glyph-t', ['none'], list)).toEqual(['none']);
    localStorage.setItem('glyph-t', 'not json');
    expect(readStored('glyph-t', ['none'], list)).toEqual(['none']);
    localStorage.setItem('glyph-t', '{"a":1}');
    expect(readStored('glyph-t', ['none'], list)).toEqual(['none']);
    localStorage.setItem('glyph-t', '["a",2,"b"]');
    expect(readStored('glyph-t', ['none'], list)).toEqual(['a', 'b']);
  });

  it('reads a check that throws as nothing kept, and takes the value as it is without one', () => {
    localStorage.setItem('glyph-t', 'null');
    expect(readStored('glyph-t', 'fallback', (raw) => (raw as { x: string }).x)).toBe('fallback');
    expect(readStored<unknown>('glyph-t', 'fallback')).toBeNull();
  });

  it('writes JSON, and removes the key for null', () => {
    writeStored('glyph-t', { a: [1, 2] });
    expect(localStorage.getItem('glyph-t')).toBe('{"a":[1,2]}');
    expect(readStored('glyph-t', {})).toEqual({ a: [1, 2] });
    writeStored('glyph-t', null);
    expect(localStorage.getItem('glyph-t')).toBeNull();
  });

  it('keeps text as text: a bare word or number is not JSON', () => {
    writeStoredText('glyph-t', 'on');
    expect(localStorage.getItem('glyph-t')).toBe('on');
    expect(readStoredText('glyph-t')).toBe('on');
    writeStoredText('glyph-t', null);
    expect(readStoredText('glyph-t')).toBeNull();
  });

  it('answers the fallback and keeps quiet when storage refuses', () => {
    localStorage.setItem('glyph-t', '[1]');
    refuse();
    expect(readStored('glyph-t', 'fallback')).toBe('fallback');
    expect(readStoredShared('glyph-t', 'fallback')).toBe('fallback');
    expect(readStoredText('glyph-t')).toBeNull();
    expect(() => writeStored('glyph-t', [2])).not.toThrow();
    expect(() => writeStoredText('glyph-t', null)).not.toThrow();
    expect(storedKeys()).toEqual([]);
  });

  it('answers the fallback when there is no storage at all, as on a server', () => {
    vi.stubGlobal('localStorage', undefined);
    try {
      expect(readStored('glyph-t', 7)).toBe(7);
      expect(() => writeStored('glyph-t', 8)).not.toThrow();
      expect(storedFlag('glyph-t', { unreadable: true }).is()).toBe(true);
    } finally {
      vi.unstubAllGlobals();
    }
  });
});

describe('a shared read', () => {
  it('parses once while the text stays the same, and again the moment it changes', () => {
    const parse = vi.fn((raw: unknown) => raw as { n: number });
    writeStored('glyph-shared', { n: 1 });
    const first = readStoredShared('glyph-shared', { n: 0 }, parse);
    expect(readStoredShared('glyph-shared', { n: 0 }, parse)).toBe(first);
    expect(parse).toHaveBeenCalledTimes(1);
    // Written behind its back, by hand: the text is asked every time, so it is never stale.
    localStorage.setItem('glyph-shared', '{"n":2}');
    expect(readStoredShared('glyph-shared', { n: 0 }, parse)).toEqual({ n: 2 });
    expect(parse).toHaveBeenCalledTimes(2);
  });
});

describe('the keys kept', () => {
  it('lists every key on the device, the page’s and anybody else’s', () => {
    localStorage.setItem('glyph-a', '1');
    localStorage.setItem('other', '2');
    expect(storedKeys().sort()).toEqual(['glyph-a', 'other']);
  });
});

describe('a once-flag', () => {
  it('is marked with the moment it was, and cleared', () => {
    const flag = storedFlag('glyph-once');
    expect(flag.is()).toBe(false);
    flag.mark();
    expect(flag.is()).toBe(true);
    expect(Number.isNaN(Date.parse(localStorage.getItem('glyph-once') ?? ''))).toBe(false);
    flag.clear();
    expect(flag.is()).toBe(false);
  });

  it('with a value, writes it and counts only it', () => {
    const flag = storedFlag('glyph-once', { value: '1' });
    flag.mark();
    expect(localStorage.getItem('glyph-once')).toBe('1');
    localStorage.setItem('glyph-once', '0');
    expect(flag.is()).toBe(false);
  });

  it('answers its own judgement when storage cannot be read, and nothing is thrown', () => {
    refuse();
    expect(storedFlag('glyph-once').is()).toBe(false);
    expect(storedFlag('glyph-once', { unreadable: true }).is()).toBe(true);
    expect(() => storedFlag('glyph-once').mark()).not.toThrow();
  });
});
