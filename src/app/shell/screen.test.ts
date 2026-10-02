import { afterEach, describe, expect, it, vi } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { captureScreen, isPlace, noteOnScreen, placeOf, type Screen } from './screen.ts';

const note: Screen = { name: 'note', note: makeNote('a') };

describe('the screens', () => {
  afterEach(() => vi.useRealTimers());

  it('makes each capture a fresh one, keyed by when it began, into a note only when it was that note’s', () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(1000);
    expect(captureScreen(true)).toStrictEqual({ name: 'capture', key: 1000, fromAssistant: true, stop: 0 });
    vi.setSystemTime(2000);
    expect(captureScreen(false, 'a')).toStrictEqual({ name: 'capture', key: 2000, fromAssistant: false, stop: 0, noteId: 'a' });
    // Where in the note, only with a note to be in.
    const lead = { kind: 'end', lead: '**14:05** ' } as const;
    expect(captureScreen(false, 'a', { placing: lead })).toStrictEqual({ name: 'capture', key: 2000, fromAssistant: false, stop: 0, noteId: 'a', placing: lead });
    expect(captureScreen(false, undefined, { placing: lead })).toStrictEqual({ name: 'capture', key: 2000, fromAssistant: false, stop: 0 });
  });

  it('says which screens are places, and where on the trail each is', () => {
    expect(placeOf({ name: 'list' })).toBe('list');
    expect(placeOf({ name: 'notes' })).toBe('notes');
    expect(placeOf(note)).toBe('note:a');
    expect(placeOf(captureScreen(false))).toBeNull();
    expect(placeOf({ name: 'academy' })).toBeNull();
    // An organization (docs/TEAMS.md) is drawn in the pane with the tab row, and is not on the trail.
    expect(placeOf({ name: 'organization', orgId: 'o' })).toBeNull();
    expect(
      [{ name: 'list' } as Screen, { name: 'notes' } as Screen, note, captureScreen(false), { name: 'academy' } as Screen, { name: 'organization', orgId: 'o' } as Screen].map(isPlace),
    ).toEqual([true, true, true, false, false, true]);
  });

  it('names the note on screen, and only a note', () => {
    expect(noteOnScreen(note)).toBe('a');
    expect(noteOnScreen(captureScreen(false, 'a'))).toBeNull();
    expect(noteOnScreen({ name: 'list' })).toBeNull();
  });
});
