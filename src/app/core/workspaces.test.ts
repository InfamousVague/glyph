import { beforeEach, describe, expect, it } from 'vitest';
import {
  addWorkspace,
  chooseWorkspace,
  fileNewNote,
  fileNote,
  forgetNote,
  inWorkspace,
  onWorkspaces,
  reloadWorkspaces,
  removeWorkspace,
  renameWorkspace,
  workspaceOf,
  workspaces,
} from './workspaces.ts';

describe('workspaces', () => {
  beforeEach(() => {
    localStorage.clear();
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

  it('comes back from storage, dropping filings to workspaces that are gone', () => {
    localStorage.setItem(KEY, JSON.stringify({ list: [{ id: 'w-a', name: 'Work' }], notes: { n1: 'w-a', n2: 'w-gone' }, current: 'w-gone' }));
    reloadWorkspaces();
    expect(workspaces()).toEqual({ list: [{ id: 'w-a', name: 'Work' }], of: { n1: 'w-a' }, current: null });
    localStorage.setItem(KEY, 'not json');
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
