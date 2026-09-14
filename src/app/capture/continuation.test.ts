import { beforeEach, describe, expect, it } from 'vitest';
import { appendBody, continues, readLastCapture, rememberCapture } from './continuation.ts';

describe('continuing the last voice note', () => {
  beforeEach(() => localStorage.clear());

  it('continues the last note with memo mode on, however long ago, and never with it off', () => {
    const last = { id: 'n1', at: 1_000_000 };
    expect(continues(last, true)).toBe(true);
    expect(continues(null, true)).toBe(false);
    expect(continues(last, false)).toBe(false);
  });

  it('remembers the last capture and ignores anything malformed', () => {
    rememberCapture('n7', 42);
    expect(readLastCapture()).toEqual({ id: 'n7', at: 42 });
    localStorage.setItem('glyph-last-capture', '{"id":3}');
    expect(readLastCapture()).toBeNull();
    localStorage.setItem('glyph-last-capture', 'not json');
    expect(readLastCapture()).toBeNull();
  });

  it('puts the new recording below the note, a blank line between', () => {
    expect(appendBody('# Trip\n\nBook the cabin.\n\n', 'Ask Sam about the dog.')).toBe('# Trip\n\nBook the cabin.\n\nAsk Sam about the dog.');
    expect(appendBody('Book the cabin.', '   ')).toBe('Book the cabin.');
    expect(appendBody('', 'Ask Sam.')).toBe('Ask Sam.');
  });
});
