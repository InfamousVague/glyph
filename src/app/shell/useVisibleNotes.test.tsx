import { beforeEach, describe, expect, it } from 'vitest';
import { act } from 'react';
import { reloadPreferences } from '../core/preferences.ts';
import { restoreNote, trashNote } from '../core/trash.ts';
import { makeNote } from '../../test/notes.ts';
import { rerender, show } from '../../test/render.tsx';
import { useVisibleNotes, type VisibleNotes } from './useVisibleNotes.ts';

/**
 * The library every screen is handed: a note a pending delete is holding back is out of it at once, a note in the
 * trash is out of it and in the Trash folder's list instead, and `live` names exactly what is left.
 */

const NOTES = [makeNote('a', '# Apples'), makeNote('b', '# Bread'), makeNote('c', '# Cheese')];

let seen: VisibleNotes;
function Probe({ hidden = new Set<string>() }: { hidden?: ReadonlySet<string> }) {
  seen = useVisibleNotes(NOTES, hidden);
  return null;
}
const ids = (notes: readonly { id: string }[]) => notes.map((n) => n.id);

beforeEach(() => {
  localStorage.clear();
  reloadPreferences();
});

describe('the notes a screen may show', () => {
  it('are all of them with nothing held back or thrown away', () => {
    show(<Probe />);
    expect(ids(seen.visible)).toEqual(['a', 'b', 'c']);
    expect(seen.trashed).toEqual([]);
    expect([...seen.live]).toEqual(['a', 'b', 'c']);
  });

  it('leave out a note a pending delete is holding back, from the trash folder too', () => {
    trashNote('c');
    show(<Probe hidden={new Set(['b', 'c'])} />);
    expect(ids(seen.visible)).toEqual(['a']);
    expect(seen.trashed).toEqual([]);
    expect([...seen.live]).toEqual(['a']);
    rerender(<Probe />);
    expect(ids(seen.visible)).toEqual(['a', 'b']);
    expect(ids(seen.trashed)).toEqual(['c']);
  });

  it('follow the trash as notes go into it and come back, the most recently thrown away first', () => {
    show(<Probe />);
    act(() => {
      trashNote('a', 1000);
      trashNote('b', 2000);
    });
    expect(ids(seen.visible)).toEqual(['c']);
    expect(ids(seen.trashed)).toEqual(['b', 'a']);
    expect(seen.live.has('a')).toBe(false);
    act(() => restoreNote('a'));
    expect(ids(seen.visible)).toEqual(['a', 'c']);
    expect(ids(seen.trashed)).toEqual(['b']);
    expect(seen.live.has('a')).toBe(true);
  });
});
