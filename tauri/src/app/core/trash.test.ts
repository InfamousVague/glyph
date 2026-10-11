import { beforeEach, describe, expect, it } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import { preferences, setPreferences } from './preferences.ts';
import { forget, inTrash, isTrashed, outOfTrash, restoreNote, trashNote } from './trash.ts';

describe('the trash', () => {
  beforeEach(() => setPreferences({ trash: {} }));

  it('takes a note in and gives it back', () => {
    trashNote('a', 10);
    expect(isTrashed('a')).toBe(true);
    restoreNote('a');
    expect(isTrashed('a')).toBe(false);
    expect(preferences().trash).toEqual({});
  });

  it('keeps a trashed note out of everything else, and shows the trash newest first', () => {
    trashNote('a', 10);
    trashNote('c', 30);
    const notes = [makeNote('a'), makeNote('b'), makeNote('c')];
    expect(outOfTrash(notes, preferences().trash).map((n) => n.id)).toEqual(['b']);
    expect(inTrash(notes, preferences().trash).map((n) => n.id)).toEqual(['c', 'a']);
  });

  it('forgets notes deleted for good, and leaves the rest', () => {
    trashNote('a', 10);
    trashNote('b', 20);
    forget(['a', 'zz']);
    expect(preferences().trash).toEqual({ b: 20 });
  });
});
