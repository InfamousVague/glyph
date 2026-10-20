import { beforeEach, describe, expect, it, vi } from 'vitest';
import { makeNote } from '../../test/notes.ts';
import type { Note } from './store.ts';

const applied: Note[] = [];
let stored: Note | null = null;
let native = true;

vi.mock('./tauri.ts', () => ({ isTauri: () => native, invoke: async () => undefined }));
vi.mock('./store.ts', () => ({
  getNote: async () => stored,
  applyNote: async (note: Note) => {
    applied.push(note);
    return note;
  },
  announceNotesChanged: () => undefined,
}));

const { fileNoteInFolder, folderFor, folderName } = await import('./noteFolders.ts');

/** The one note these tests file, at `path` in the library or at none. */
function note(path: string | undefined): Note {
  return makeNote('n1', '# Weekend trip', path === undefined ? {} : { path });
}

/** A personal workspace called `name`, and an organization's. */
const HOME = { id: 'w-home', name: 'Home' };
const GHOST = { id: 'org-abc', name: 'Ghost' };

describe('the folder a note is filed in', () => {
  beforeEach(() => {
    applied.length = 0;
    stored = note('Inbox/Weekend trip.md');
    native = true;
  });

  it('names a folder after the workspace, and the inbox for none', () => {
    expect(folderFor(HOME)).toBe('workspaces/Home');
    expect(folderFor(null)).toBe('Inbox');
    // What a file name cannot hold goes, and a name that cleans away to nothing is no folder at all.
    expect(folderName('Work/Clients: 2026?')).toBe('WorkClients 2026');
    expect(folderFor({ id: 'w-1', name: '  ///  ' })).toBeNull();
    expect(folderFor({ id: 'w-1', name: '..' })).toBeNull();
  });

  it('files an organization’s workspace under orgs/, apart from a personal workspace of the same name', () => {
    expect(folderFor(GHOST)).toBe('orgs/Ghost');
    expect(folderFor({ id: 'w-ghost', name: 'Ghost' })).toBe('workspaces/Ghost');
    // The organization's name is another account's choice, and is cleaned like any other.
    expect(folderFor({ id: 'org-abc', name: '../Ghost: 2026' })).toBe('orgs/Ghost 2026');
    expect(folderFor({ id: 'org-abc', name: '..' })).toBeNull();
  });

  it('moves the file into the workspace folder, keeping its name', async () => {
    await fileNoteInFolder('n1', HOME);
    expect(applied.map((n) => n.path)).toEqual(['workspaces/Home/Weekend trip.md']);
    applied.length = 0;
    await fileNoteInFolder('n1', GHOST);
    expect(applied.map((n) => n.path)).toEqual(['orgs/Ghost/Weekend trip.md']);
  });

  it('moves it back to the inbox when it leaves a workspace', async () => {
    stored = note('workspaces/Home/Weekend trip.md');
    await fileNoteInFolder('n1', null);
    expect(applied.map((n) => n.path)).toEqual(['Inbox/Weekend trip.md']);
  });

  it('leaves the words alone and asks for nothing it cannot do', async () => {
    await fileNoteInFolder('n1', HOME);
    expect(applied[0]?.body).toBe('# Weekend trip');
    applied.length = 0;

    // Already there: nothing to ask for.
    stored = note('workspaces/Home/Weekend trip.md');
    await fileNoteInFolder('n1', HOME);
    expect(applied).toEqual([]);

    // A draft, or a binary too old to have paths: no file to move.
    stored = note(undefined);
    await fileNoteInFolder('n1', HOME);
    expect(applied).toEqual([]);

    // A browser has no library at all.
    stored = note('Inbox/Weekend trip.md');
    native = false;
    await fileNoteInFolder('n1', HOME);
    expect(applied).toEqual([]);
  });
});

describe('a folder inside another (GHST-107)', () => {
  const CLIENTS = { id: 'w-cl', name: 'Clients', parent: GHOST.id };
  const ACME = { id: 'w-acme', name: 'Acme', parent: CLIENTS.id };
  const WORK = { id: 'w-work', name: 'Work' };
  const PLANS = { id: 'w-plans', name: 'Plans', parent: WORK.id };

  it('is a folder inside its parent’s, under orgs/ for an organization’s and workspaces/ for a personal one', () => {
    // The path rides in a team note's row, so a folder under an organization is written where the phone writes it.
    const all = [GHOST, CLIENTS, ACME, WORK, PLANS];
    expect(folderFor(ACME, all)).toBe('orgs/Ghost/Clients/Acme');
    expect(folderFor(CLIENTS, all)).toBe('orgs/Ghost/Clients');
    expect(folderFor(PLANS, all)).toBe('workspaces/Work/Plans');
    expect(folderFor(GHOST, all)).toBe('orgs/Ghost');
  });

  it('stands at the top without the list, with a parent that is gone, or with a parent whose name cleans away', () => {
    expect(folderFor(ACME)).toBe('workspaces/Acme');
    expect(folderFor(ACME, [ACME])).toBe('workspaces/Acme');
    expect(folderFor({ id: 'w-x', name: 'X', parent: 'w-dots' }, [{ id: 'w-dots', name: '..' }, { id: 'w-x', name: 'X', parent: 'w-dots' }])).toBe('workspaces/X');
  });
});
