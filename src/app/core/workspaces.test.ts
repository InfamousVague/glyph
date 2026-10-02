import { beforeEach, describe, expect, it } from 'vitest';
import { preferences, reloadPreferences, setPreferences } from './preferences.ts';
import {
  addWorkspace,
  chooseWorkspace,
  dropOrgWorkspace,
  ensureOrgWorkspace,
  fileNewNote,
  fileNote,
  forgetNote,
  inWorkspace,
  isOrgWorkspace,
  onWorkspaces,
  reloadWorkspaces,
  removeWorkspace,
  renameOrgWorkspace,
  renameWorkspace,
  setWorkspaceHue,
  workspaceOf,
  workspaces,
} from './workspaces.ts';

describe('workspaces', () => {
  beforeEach(() => {
    localStorage.clear();
    // The workspaces themselves live in the preferences now (they travel between devices), so both are read again.
    reloadPreferences();
    reloadWorkspaces();
  });

  it('starts empty, with all notes shown', () => {
    expect(workspaces()).toEqual({ list: [], of: {}, current: null });
  });

  it('makes a workspace once per name, tidied', () => {
    const work = addWorkspace('  Work  ');
    expect(work).toEqual({ id: expect.stringMatching(/^w-[a-z0-9]{6}$/), name: 'Work' });
    expect(addWorkspace('work')).toBe(work);
    expect(addWorkspace('   ')).toBeNull();
    expect(workspaces().list).toEqual([work]);
  });

  it('files a note in one workspace at a time, and unfiles it', () => {
    const work = addWorkspace('Work')!;
    const home = addWorkspace('Home')!;
    fileNote('n1', work.id);
    expect(workspaceOf('n1')).toEqual(work);
    fileNote('n1', home.id);
    expect(workspaceOf('n1')).toEqual(home);
    fileNote('n1', 'w-nowhere');
    expect(workspaceOf('n1')).toEqual(home);
    fileNote('n1', null);
    expect(workspaceOf('n1')).toBeNull();
  });

  it('files a new note where the list is, and only when it is not filed', () => {
    const work = addWorkspace('Work')!;
    fileNewNote('n1');
    expect(workspaceOf('n1')).toBeNull();
    chooseWorkspace(work.id);
    fileNewNote('n1');
    expect(workspaceOf('n1')).toEqual(work);
    const home = addWorkspace('Home')!;
    chooseWorkspace(home.id);
    fileNewNote('n1');
    expect(workspaceOf('n1')).toEqual(work);
  });

  it('filters notes by workspace, and shows all for null', () => {
    const work = addWorkspace('Work')!;
    fileNote('n1', work.id);
    const notes = [{ id: 'n1' }, { id: 'n2' }];
    expect(inWorkspace(notes, work.id)).toEqual([{ id: 'n1' }]);
    expect(inWorkspace(notes, null)).toEqual(notes);
  });

  it('renames, and removing unfiles its notes and clears the filter', () => {
    const work = addWorkspace('Work')!;
    renameWorkspace(work.id, ' Day job ');
    expect(workspaces().list[0]?.name).toBe('Day job');
    renameWorkspace(work.id, '');
    expect(workspaces().list[0]?.name).toBe('Day job');
    fileNote('n1', work.id);
    chooseWorkspace(work.id);
    expect(workspaces().current?.id).toBe(work.id);
    removeWorkspace(work.id);
    expect(workspaces()).toEqual({ list: [], of: {}, current: null });
    expect(workspaceOf('n1')).toBeNull();
  });

  it('forgets a deleted note, and tells listeners once per change', () => {
    const work = addWorkspace('Work')!;
    fileNote('n1', work.id);
    let told = 0;
    const off = onWorkspaces(() => {
      told += 1;
    });
    forgetNote('n1');
    forgetNote('n1');
    expect(told).toBe(1);
    expect(workspaces().of).toEqual({});
    off();
  });

  it('reads workspaces another device sent again, and tells listeners once', () => {
    let told = 0;
    const off = onWorkspaces(() => {
      told += 1;
    });
    // Our own write is heard once, not again as it comes back through the preferences.
    const work = addWorkspace('Work')!;
    expect(told).toBe(1);
    // Settings from another device land as a preference change (core/sync/prefs.ts).
    const home = { id: 'w-home', name: 'Home' };
    setPreferences({ workspaces: { list: [work, home], notes: { n1: home.id } } });
    expect(told).toBe(2);
    expect(workspaces().list).toEqual([work, home]);
    expect(workspaceOf('n1')).toEqual(home);
    // Any other setting changing leaves the workspaces, and whoever watches them, alone.
    setPreferences({ ripples: false });
    expect(told).toBe(2);
    off();
  });

  it('takes workspaces kept under the old key into the preferences, where they travel', () => {
    // Made before workspaces synced: read once from where they were, and from the preferences ever after.
    localStorage.setItem(KEY, JSON.stringify({ list: [{ id: 'w-a', name: 'Work' }], notes: { n1: 'w-a', n2: 'w-gone' }, current: 'w-gone' }));
    reloadWorkspaces();
    expect(workspaces()).toEqual({ list: [{ id: 'w-a', name: 'Work' }], of: { n1: 'w-a' }, current: null });
    expect(preferences().workspaces).toEqual({ list: [{ id: 'w-a', name: 'Work' }], notes: { n1: 'w-a' } });
    // The old key is no longer read, so rubbish left in it changes nothing.
    localStorage.setItem(KEY, 'not json');
    reloadWorkspaces();
    expect(workspaces().list).toEqual([{ id: 'w-a', name: 'Work' }]);
  });

  it('reads rubbish in the preference as no workspaces at all', () => {
    localStorage.setItem('glyph-preferences', JSON.stringify({ workspaces: 'not a sheet' }));
    reloadPreferences();
    reloadWorkspaces();
    expect(workspaces().list).toEqual([]);
  });

  it('hands React the same snapshot until something changes', () => {
    const before = workspaces();
    expect(workspaces()).toBe(before);
    addWorkspace('Work');
    expect(workspaces()).not.toBe(before);
  });
});

const KEY = 'glyph-workspaces';

describe('a workspace’s colour', () => {
  beforeEach(() => {
    localStorage.clear();
    reloadPreferences();
    reloadWorkspaces();
  });

  it('is made with one, changed, and taken off again', () => {
    const made = addWorkspace('Work', 'sea')!;
    expect(made.hue).toBe('sea');
    expect(workspaces().list[0]?.hue).toBe('sea');
    setWorkspaceHue(made.id, 'moss');
    expect(workspaces().list[0]?.hue).toBe('moss');
    // Ink is the app's own colour, and is kept as no colour at all rather than as a name.
    setWorkspaceHue(made.id, 'ink');
    expect(workspaces().list[0]?.hue).toBeUndefined();
  });

  it('keeps its colour through a rename, and has none by default', () => {
    const made = addWorkspace('Home', 'rose')!;
    renameWorkspace(made.id, 'House');
    expect(workspaces().list[0]).toMatchObject({ name: 'House', hue: 'rose' });
    expect(addWorkspace('Plain')?.hue).toBeUndefined();
  });

  it('ignores a colour it does not know, on the way in and on the way out', () => {
    const made = addWorkspace('Work', 'amber')!;
    setWorkspaceHue(made.id, 'chartreuse' as never);
    expect(workspaces().list[0]?.hue).toBe('amber');
    setWorkspaceHue('w-nothing', 'sea');
    expect(workspaces().list.length).toBe(1);
    // A hue written by a phone further ahead reads as ink rather than as a broken colour.
    setPreferences({ workspaces: { list: [{ id: 'w-1', name: 'Saved', hue: 'octarine' }], notes: {} } });
    reloadWorkspaces();
    expect(workspaces().list[0]).toEqual({ id: 'w-1', name: 'Saved' });
  });

  it('reads a kept ink as no colour at all, from the preferences and from the old key', () => {
    setPreferences({ workspaces: { list: [{ id: 'w-1', name: 'Saved', hue: 'ink' }], notes: {} } });
    reloadWorkspaces();
    expect(workspaces().list[0]).toEqual({ id: 'w-1', name: 'Saved' });

    localStorage.clear();
    reloadPreferences();
    localStorage.setItem(KEY, JSON.stringify({ list: [{ id: 'w-2', name: 'Old', hue: 'ink' }], notes: {} }));
    reloadWorkspaces();
    expect(workspaces().list[0]).toEqual({ id: 'w-2', name: 'Old' });
    // And it is carried into the preferences without one.
    expect(preferences().workspaces.list).toEqual([{ id: 'w-2', name: 'Old' }]);
  });
});

describe('an organization’s workspace', () => {
  beforeEach(() => {
    localStorage.clear();
    reloadPreferences();
    reloadWorkspaces();
  });

  const ghost = { id: 'abc', name: 'Ghost', hue: 'sea' };

  it('has the organization’s id, name and hue, and is made once however many times it is asked for', () => {
    const made = ensureOrgWorkspace(ghost);
    expect(made).toEqual({ id: 'org-abc', name: 'Ghost', hue: 'sea', org: 'abc' });
    expect(isOrgWorkspace(made)).toBe(true);
    expect(ensureOrgWorkspace(ghost)).toEqual(made);
    expect(workspaces().list).toEqual([made]);
    // No hue, or one this build does not know, is the app's own ink.
    expect(ensureOrgWorkspace({ id: 'def', name: 'Boo', hue: null })).toEqual({ id: 'org-def', name: 'Boo', org: 'def' });
    expect(ensureOrgWorkspace({ id: 'ghi', name: 'Eek', hue: 'octarine' })).toEqual({ id: 'org-ghi', name: 'Eek', org: 'ghi' });
  });

  it('follows the organization’s name and hue, and keeps its filings through a rename', () => {
    ensureOrgWorkspace(ghost);
    fileNote('n1', 'org-abc');
    renameOrgWorkspace({ id: 'abc', name: 'Spectre', hue: null });
    expect(workspaces().list[0]).toEqual({ id: 'org-abc', name: 'Spectre', org: 'abc' });
    expect(workspaceOf('n1')?.id).toBe('org-abc');
    ensureOrgWorkspace({ id: 'abc', name: 'Spectre', hue: 'rose' });
    expect(workspaces().list[0]?.hue).toBe('rose');
    // One this device has not got is nothing to rename.
    renameOrgWorkspace({ id: 'zzz', name: 'Nobody' });
    expect(workspaces().list).toHaveLength(1);
  });

  it('is refused the personal rename, hue and removal: those are the organization’s', () => {
    ensureOrgWorkspace(ghost);
    renameWorkspace('org-abc', 'Mine');
    setWorkspaceHue('org-abc', 'rose');
    removeWorkspace('org-abc');
    expect(workspaces().list).toEqual([{ id: 'org-abc', name: 'Ghost', hue: 'sea', org: 'abc' }]);
  });

  it('goes when the person leaves, its notes unfiled and the filter cleared', () => {
    ensureOrgWorkspace(ghost);
    fileNote('n1', 'org-abc');
    chooseWorkspace('org-abc');
    dropOrgWorkspace('abc');
    expect(workspaces()).toEqual({ list: [], of: {}, current: null });
    dropOrgWorkspace('abc');
    expect(workspaces().list).toEqual([]);
  });

  it('may share its name with a personal workspace, which is deduped among the personal ones only', () => {
    ensureOrgWorkspace(ghost);
    const mine = addWorkspace('ghost')!;
    expect(mine.id).toMatch(/^w-/);
    expect(isOrgWorkspace(mine)).toBe(false);
    expect(addWorkspace('Ghost')).toBe(mine);
    expect(workspaces().list).toHaveLength(2);
  });

  it('is known by its id alone, so a build that stripped the marker, or another device, still reads it as the organization’s', () => {
    setPreferences({ workspaces: { list: [{ id: 'org-abc', name: 'Ghost' }, { id: 'w-1', name: 'Home' }], notes: { n1: 'org-abc' } } });
    reloadWorkspaces();
    expect(workspaces().list).toEqual([
      { id: 'org-abc', name: 'Ghost', org: 'abc' },
      { id: 'w-1', name: 'Home' },
    ]);
    // Adopted as it is: no second "Ghost".
    expect(ensureOrgWorkspace({ id: 'abc', name: 'Ghost' })).toEqual({ id: 'org-abc', name: 'Ghost', org: 'abc' });
    expect(workspaces().list).toHaveLength(2);
    expect(workspaceOf('n1')?.org).toBe('abc');
    // A marker written by another device is never what decides.
    setPreferences({ workspaces: { list: [{ id: 'w-2', name: 'Fake', org: 'abc' } as { id: string; name: string }], notes: {} } });
    reloadWorkspaces();
    expect(workspaces().list[0]).toEqual({ id: 'w-2', name: 'Fake' });
  });
});
