import { afterEach, describe, expect, it, vi } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { captureScreen, isPlace, noteOnScreen, placeOf, type Screen } from './screen.ts';

const note: Screen = { name: 'note', note: makeNote('a') };

describe('the screens', () => {
  afterEach(() => vi.useRealTimers());

  it('makes each capture a fresh one, keyed by when it began, into a note only when it was that note’s', () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(1000);
    expect(captureScreen(true)).toEqual({ name: 'capture', key: 1000, fromAssistant: true, stop: 0 });
    vi.setSystemTime(2000);
    expect(captureScreen(false, 'a')).toEqual({ name: 'capture', key: 2000, fromAssistant: false, stop: 0, noteId: 'a' });
  });

  it('says which screens are places, and where on the trail each is', () => {
    expect(placeOf({ name: 'list' })).toBe('list');
    expect(placeOf({ name: 'notes' })).toBe('notes');
    expect(placeOf(note)).toBe('note:a');
    expect(placeOf(captureScreen(false))).toBeNull();
    expect(placeOf({ name: 'academy' })).toBeNull();
    expect([{ name: 'list' } as Screen, { name: 'notes' } as Screen, note, captureScreen(false), { name: 'academy' } as Screen].map(isPlace)).toEqual([true, true, true, false, false]);
  });

  it('names the note on screen, and only a note', () => {
    expect(noteOnScreen(note)).toBe('a');
    expect(noteOnScreen(captureScreen(false, 'a'))).toBeNull();
    expect(noteOnScreen({ name: 'list' })).toBeNull();
  });
});
