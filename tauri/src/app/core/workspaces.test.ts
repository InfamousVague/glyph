import { beforeEach, describe, expect, it } from 'vitest';
import { preferences, reloadPreferences, setPreferences } from './preferences.ts';
import {
  addWorkspace,
  chooseWorkspace,
  dropOrgWorkspace,
  ensureOrgWorkspace,
  fileNewNote,
  fileNote,
  fileTeamNote,
  forgetNote,
  inWorkspace,
  isOrgWorkspace,
  onWorkspaces,
  orgOfNote,
  orgOfWorkspace,
  reloadWorkspaces,
  removeWorkspace,
  renameOrgWorkspace,
  renameWorkspace,
  setWorkspaceHue,
  workspaceFamily,
  workspaceOf,
  workspacePath,
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

describe('a workspace nested by the Flutter app', () => {
  beforeEach(() => {
    localStorage.clear();
    reloadPreferences();
    reloadWorkspaces();
  });

  it('keeps its parent through a read, a rename and a hue reset, though this page lists it flat', () => {
    setPreferences({ workspaces: { list: [{ id: 'w-aaaaaa', name: 'Work' }, { id: 'w-bbbbbb', name: 'Clients', hue: 'moss', parent: 'w-aaaaaa' }], notes: {} } });
    reloadWorkspaces();
    expect(workspaces().list.find((w) => w.id === 'w-bbbbbb')?.parent).toBe('w-aaaaaa');
    renameWorkspace('w-bbbbbb', 'Customers');
    setWorkspaceHue('w-bbbbbb', 'ink');
    const kept = (preferences().workspaces as { list: { id: string; parent?: string; name: string }[] }).list.find((w) => w.id === 'w-bbbbbb');
    expect(kept).toMatchObject({ name: 'Customers', parent: 'w-aaaaaa' });
  });
});

describe('folders under an organization’s workspace (GHST-107, read as the phone reads them)', () => {
  const GHOST = { id: 'org-abc', name: 'Ghost' };
  const CLIENTS = { id: 'w-cl', name: 'Clients', parent: 'org-abc' };
  const ACME = { id: 'w-acme', name: 'Acme', parent: 'w-cl' };
  const HOME = { id: 'w-home', name: 'Home' };

  beforeEach(() => {
    localStorage.clear();
    reloadPreferences();
    reloadWorkspaces();
    // Folders made on the phone or by the connector arrive through the preferences, parents and all.
    setPreferences({ workspaces: { list: [GHOST, CLIENTS, ACME, HOME], notes: { deep: ACME.id, top: GHOST.id, mine: HOME.id } } });
  });

  it('keeps a folder’s parent as it was read, an organization’s workspace included', () => {
    // An organization's workspace reads its organization from its id (`org`); the folders keep their parents.
    expect(workspaces().list).toEqual([{ ...GHOST, org: 'abc' }, CLIENTS, ACME, HOME]);
    expect(workspacePath(workspaces().list, ACME.id).map((w) => w.id)).toEqual([GHOST.id, CLIENTS.id, ACME.id]);
    expect(workspaceFamily(workspaces().list, GHOST.id)).toEqual([GHOST.id, CLIENTS.id, ACME.id]);
  });

  it('reads a note filed in a folder under an organization as the team’s, however deep', () => {
    // 2026-10-20: the id's prefix alone read such folders as personal and took 160 team notes out of three
    // organizations; walking the parents is what the phone does (lib/core/workspaces.dart orgOfWorkspace).
    expect(orgOfNote('deep')).toBe('abc');
    expect(orgOfNote('top')).toBe('abc');
    expect(orgOfNote('mine')).toBeNull();
    expect(orgOfNote('unfiled')).toBeNull();
    expect(orgOfWorkspace(workspaces().list, CLIENTS.id)).toBe('abc');
    expect(orgOfWorkspace(workspaces().list, HOME.id)).toBeNull();
    expect(orgOfWorkspace(workspaces().list, 'w-gone')).toBeNull();
  });

  it('reads a parent chain that loops back as no organization, and does not spin', () => {
    setPreferences({ workspaces: { list: [{ id: 'w-a', name: 'A', parent: 'w-b' }, { id: 'w-b', name: 'B', parent: 'w-a' }], notes: { n: 'w-a' } } });
    expect(orgOfNote('n')).toBeNull();
    expect(workspacePath(workspaces().list, 'w-a').map((w) => w.id)).toEqual(['w-b', 'w-a']);
  });

  it('shows an organization’s notes with those in its folders', () => {
    const notes = [{ id: 'deep' }, { id: 'top' }, { id: 'mine' }, { id: 'unfiled' }];
    expect(inWorkspace(notes, GHOST.id).map((n) => n.id)).toEqual(['deep', 'top']);
    expect(inWorkspace(notes, CLIENTS.id).map((n) => n.id)).toEqual(['deep']);
    expect(inWorkspace(notes, HOME.id).map((n) => n.id)).toEqual(['mine']);
  });

  it('makes a folder inside a parent once per name there, and a personal one apart from the team’s', () => {
    expect(addWorkspace('clients', 'ink', GHOST.id)).toEqual(CLIENTS);
    const plans = addWorkspace('Plans', 'ink', GHOST.id)!;
    expect(plans).toEqual({ id: expect.stringMatching(/^w-/), name: 'Plans', parent: GHOST.id });
    // The same name at the top is a personal folder, not the team's one.
    const mine = addWorkspace('Clients')!;
    expect(mine).not.toBe(CLIENTS);
    expect(mine.parent).toBeUndefined();
    expect(addWorkspace('Clients')).toBe(mine);
    // A parent the list does not have is no parent.
    expect(addWorkspace('Loose', 'ink', 'w-gone')!.parent).toBeUndefined();
  });

  it('files a note from the team where its row’s path says, finding or making the folders by name', () => {
    fileTeamNote('n1', 'abc', 'orgs/Ghost/Clients/Acme/Plan.md');
    expect(workspaceOf('n1')).toEqual(ACME);
    // A folder the path names that is not here yet is made under the one before it, as on the phone.
    fileTeamNote('n2', 'abc', 'orgs/Ghost/Clients/Initech/Plan.md');
    const initech = workspaces().list.find((w) => w.name === 'Initech')!;
    expect(initech.parent).toBe(CLIENTS.id);
    expect(workspaceOf('n2')).toEqual(initech);
    // Found ignoring case, as the file system would.
    fileTeamNote('n3', 'abc', 'orgs/Ghost/clients/Note.md');
    expect(workspaceOf('n3')).toEqual(CLIENTS);
    // No folders in the path, or no path: the organization's own workspace, as before.
    fileTeamNote('n4', 'abc', 'orgs/Ghost/Plan.md');
    expect(workspaceOf('n4')).toMatchObject(GHOST);
    fileTeamNote('n5', 'abc', undefined);
    expect(workspaceOf('n5')).toMatchObject(GHOST);
    // Without the organization's workspace here, nothing is filed.
    fileTeamNote('n6', 'nope', 'orgs/Nope/Clients/Plan.md');
    expect(workspaceOf('n6')).toBeNull();
  });
});
