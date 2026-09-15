import { beforeEach, describe, expect, it } from 'vitest';
import { readPlace, writePlace } from './notePlace.ts';

describe('where a note was left', () => {
  beforeEach(() => localStorage.clear());

  it('is kept per note, and forgotten when the note is left at the top', () => {
    writePlace('a', { pos: 3124, offset: 51.5 });
    writePlace('b', { pos: 10, offset: 0 });
    expect(readPlace('a')).toEqual({ pos: 3124, offset: 51.5 });
    expect(readPlace('b')).toEqual({ pos: 10, offset: 0 });
    writePlace('a', null);
    expect(readPlace('a')).toBeNull();
    expect(readPlace('missing')).toBeNull();
  });

  it('keeps the most recently read notes, not every note ever opened', () => {
    for (let i = 0; i < 205; i += 1) writePlace(`n${i}`, { pos: i, offset: 0 }, i);
    expect(readPlace('n0')).toBeNull();
    expect(readPlace('n4')).toBeNull();
    expect(readPlace('n5')).toEqual({ pos: 5, offset: 0 });
    expect(readPlace('n204')).toEqual({ pos: 204, offset: 0 });
  });

  it('opens at the top when what is stored is not a place', () => {
    localStorage.setItem('glyph-note-places', '{"a":{"pos":"x"}}');
    expect(readPlace('a')).toBeNull();
    localStorage.setItem('glyph-note-places', 'not json');
    expect(readPlace('a')).toBeNull();
  });
});
