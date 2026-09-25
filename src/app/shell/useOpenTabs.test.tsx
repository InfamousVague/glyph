import { beforeEach, describe, expect, it } from 'vitest';
import { act } from 'react';
import { preferences, reloadPreferences, setPreferences } from '../core/preferences.ts';
import type { Note } from '../core/store.ts';
import type { TabGroups } from '../notes/tabGroups.ts';
import { makeNote } from '../../test/notes.ts';
import { rerender, show } from '../../test/render.tsx';
import { useOpenTabs, type OpenTabs } from './useOpenTabs.ts';

/**
 * The open tabs and their groups as the Shell holds them: which note takes a tab, where closing one lands, and the
 * two things kept in the synced preferences - the row, and the groups over it.
 */

const notes = ['a', 'b', 'c', 'd'].map((id) => makeNote(id));
const all = new Set(notes.map((n) => n.id));

/** The hook's answer after each render. */
let tabs: OpenTabs;
function Probe({ shown, loaded = notes, live = all }: { shown: string | null; loaded?: Note[]; live?: ReadonlySet<string> }) {
  tabs = useOpenTabs(shown, loaded, live);
  return null;
}
const ids = () => tabs.tabs.map((n) => n.id);

beforeEach(() => {
  localStorage.clear();
  reloadPreferences();
});

describe('the open tabs', () => {
  it('gives each note shown a tab, and keeps the row in the synced preferences', () => {
    show(<Probe shown={null} />);
    expect(ids()).toEqual([]);
    rerender(<Probe shown="a" />);
    rerender(<Probe shown="b" />);
    rerender(<Probe shown="a" />);
    expect(ids()).toEqual(['a', 'b']);
    expect(preferences().openNotes).toEqual(['a', 'b']);
  });

  it('opens the row as it was left, drawing only the tabs whose notes can be seen', () => {
    setPreferences({ openNotes: ['a', 'gone', 'b'] });
    show(<Probe shown={null} live={new Set(['a', 'b'])} />);
    expect(tabs.open).toEqual(['a', 'gone', 'b']);
    expect(ids()).toEqual(['a', 'b']);
  });

  it('gives the next note shown the tab it is told to, once, and a tab of its own after that', () => {
    show(<Probe shown="a" />);
    act(() => tabs.replaceNext('a'));
    rerender(<Probe shown="b" />);
    expect(ids()).toEqual(['b']);
    rerender(<Probe shown="c" />);
    expect(ids()).toEqual(['b', 'c']);
  });

  it('forgets a request nothing read once no note is on screen', () => {
    show(<Probe shown="a" />);
    // Asked for from the note already shown: no tab changes, so nothing reads it.
    act(() => tabs.replaceNext('a'));
    rerender(<Probe shown={null} />);
    rerender(<Probe shown="b" />);
    expect(ids()).toEqual(['a', 'b']);
  });

  it('answers where to land when the tab being read closes, and nothing when another does', () => {
    setPreferences({ openNotes: ['a', 'b', 'c'] });
    show(<Probe shown="b" />);
    let landing: string | null | undefined;
    act(() => {
      landing = tabs.close(['a']);
    });
    expect(landing).toBeUndefined();
    expect(ids()).toEqual(['b', 'c']);
    act(() => {
      landing = tabs.close(['b']);
    });
    expect(landing).toBe('c');
    rerender(<Probe shown="c" />);
    act(() => {
      landing = tabs.close(['c']);
    });
    expect(landing).toBeNull();
    expect(tabs.open).toEqual([]);
  });

  it('closes a whole group at once, landing past it when the tab being read was in it', () => {
    setPreferences({ openNotes: ['a', 'b', 'c', 'd'] });
    show(<Probe shown="b" />);
    let landing: string | null | undefined;
    act(() => {
      landing = tabs.close(['b', 'c']);
    });
    expect(landing).toBe('d');
    expect(tabs.open).toEqual(['a', 'd']);
  });

  it('drops a tab without asking where to go', () => {
    setPreferences({ openNotes: ['a', 'b'] });
    show(<Probe shown="a" />);
    act(() => tabs.drop('a'));
    expect(tabs.open).toEqual(['b']);
  });

  it('moves a tab by the keys into the group it lands inside, and out of one it leaves', () => {
    const groups: TabGroups = { list: [{ id: 'g', name: 'Trip', hue: 'sea' }], of: { a: 'g', b: 'g' } };
    setPreferences({ openNotes: ['a', 'b', 'c'], tabGroups: groups });
    show(<Probe shown={null} />);
    act(() => tabs.move('c', 1));
    expect(tabs.open).toEqual(['a', 'c', 'b']);
    expect(tabs.groups.of.c).toBe('g');
    // A drag says for itself which group the tab is in, so the move leaves the groups alone.
    act(() => tabs.move('c', 2, true));
    expect(tabs.open).toEqual(['a', 'b', 'c']);
    expect(tabs.groups.of.c).toBe('g');
  });
});

describe('the tab groups', () => {
  const groups: TabGroups = { list: [{ id: 'g', name: 'Trip', hue: 'sea' }], of: { a: 'g' } };

  it('survive a first render with no note loaded, since they are measured against the row as kept', () => {
    setPreferences({ openNotes: ['a', 'b'], tabGroups: groups });
    show(<Probe shown={null} loaded={[]} live={new Set()} />);
    expect(tabs.groups).toEqual(groups);
    expect(preferences().tabGroups).toEqual(groups);
  });

  it('lose a tab that closes, and a group left with nothing in it goes', () => {
    setPreferences({ openNotes: ['a', 'b'], tabGroups: groups });
    show(<Probe shown={null} />);
    act(() => void tabs.close(['a']));
    expect(tabs.groups).toEqual({ list: [], of: {} });
    expect(preferences().tabGroups).toEqual({ list: [], of: {} });
  });

  it('follow a change made on another device', () => {
    setPreferences({ openNotes: ['a', 'b'] });
    show(<Probe shown={null} />);
    act(() => setPreferences({ tabGroups: groups }));
    expect(tabs.groups).toEqual(groups);
    // Drawn together, where the first of them stands.
    expect(ids()).toEqual(['a', 'b']);
  });
});
