// @vitest-environment node
import { beforeEach, describe, expect, it } from 'vitest';
import type { Note } from '../tauri/src/app/core/store.ts';
import { open } from '../tauri/src/app/core/sync/crypto.ts';
import { forgetTeamDocs } from '../tauri/src/app/core/team/doc.ts';
import type { fakeService } from '../tauri/src/test/fakeService.ts';
import { canMove, fileNameOf, fileStem, folderAtPath, folderFor, folderName, orgFolderNames, orgOf, pathName, workspaceFamily, type Kept } from './folders.ts';
import { aNote, anOrganization, connected, teamDevice, WRITTEN } from './testKit.ts';

/**
 * Folders through the connector (GHST-108; Matt, 2026-10-19: "Make it so the AI can manage folders and sorting of
 * files into folders and organize all my organizations into neat logical folders"): the app's rules for folders
 * inside folders (lib/core/workspaces.dart, lib/core/note_folders.dart), and the tools that make, rename, move and
 * delete them - a personal one in the settings alone, one inside an organization's by its notes' paths too, which a
 * member's device (the app's own channel, testKit.ts `teamDevice`) files them by.
 */

type Space = { id: string; name: string; parent?: string; path: string; organization: boolean; notes: number; notesUnder: number; archived: number };
type Folder = { id: string; name: string; parent?: string; path: string; organization: boolean };
type Prefs = { workspaces: { list: Kept[]; notes: Record<string, string> } };

beforeEach(() => {
  forgetTeamDocs();
});

/** A team note's row on the service, opened as a member opens it. */
async function rowOf(service: Awaited<ReturnType<typeof fakeService>>, org: { id: string; key: CryptoKey }, id: string) {
  const row = service.teamNotes(org.id).get(id);
  if (!row?.blob) return null;
  return { rev: row.rev, ...(await open<{ note: Note; state: string; seq: number }>(org.key, row.blob, `org:${org.id}:note:${id}`)) };
}

describe('the app’s rules, ported', () => {
  const list: Kept[] = [
    { id: 'org-o1', name: 'Ghost.md', hue: 'sea' },
    { id: 'w-clnt', name: 'Clients', parent: 'org-o1' },
    { id: 'w-acme', name: 'Acme: "Inc"', parent: 'w-clnt' },
    { id: 'w-work', name: 'Work' },
    { id: 'w-proj', name: 'Projects', parent: 'w-work' },
  ];

  it('walks parents to the organization, the family down, and the path up', () => {
    expect(orgOf(list, 'w-acme')).toBe('o1');
    expect(orgOf(list, 'org-o1')).toBe('o1');
    expect(orgOf(list, 'w-proj')).toBeNull();
    expect(workspaceFamily(list, 'org-o1')).toEqual(['org-o1', 'w-clnt', 'w-acme']);
    expect(pathName(list, 'w-acme')).toBe('Ghost.md › Clients › Acme: "Inc"');
  });

  it('names folders on disk as the app does, and reads a team note’s path back to its folder', () => {
    expect(folderName('  Acme: "Inc"..  ')).toBe('Acme Inc');
    expect(folderFor(list[2]!, list)).toBe('orgs/Ghost.md/Clients/Acme Inc');
    expect(folderFor(list[4]!, list)).toBe('workspaces/Work/Projects');
    expect(folderFor(null)).toBe('Inbox');
    expect(orgFolderNames('orgs/Ghost.md/Clients/Acme Inc/Plan.md')).toEqual(['Clients', 'Acme Inc']);
    expect(orgFolderNames('orgs/Ghost.md/Plan.md')).toEqual([]);
    expect(folderAtPath(list, 'org-o1', ['clients', 'Acme Inc'])).toBe('w-acme');
    expect(folderAtPath(list, 'org-o1', ['Clients', 'Gone'])).toBe('w-clnt');
  });

  it('keeps a note’s file name, or names a new one after its title as the library does', () => {
    expect(fileNameOf('orgs/Ghost.md/Plan 2.md', 'Plan')).toBe('Plan 2.md');
    expect(fileNameOf(undefined, 'Q3: plan / #1')).toBe('Q3 plan 1.md');
    expect(fileStem('...')).toBe('Untitled');
  });

  it('moves a folder only within the organization it is in, or out of every one, and never into itself', () => {
    expect(canMove(list, 'w-acme', 'org-o1')).toBe(true);
    expect(canMove(list, 'w-acme', null)).toBe(false);
    expect(canMove(list, 'w-acme', 'w-work')).toBe(false);
    expect(canMove(list, 'w-work', 'w-clnt')).toBe(false);
    expect(canMove(list, 'w-work', 'w-proj')).toBe(false);
    expect(canMove(list, 'org-o1', null)).toBe(false);
    expect(canMove(list, 'w-proj', null)).toBe(true);
  });
});

describe('personal folders', () => {
  async function withFolders() {
    const kit = await connected();
    await kit.service.deviceWrites(aNote('a', '# Pricing'));
    await kit.service.deviceWrites(aNote('b', '# Roadmap'));
    await kit.service.deviceWrites(aNote('c', '# Groceries'));
    await kit.account.changePrefs(() => ({
      theme: 'dark',
      workspaces: {
        list: [
          { id: 'w-work', name: 'Work', hue: 'moss' },
          { id: 'w-clnt', name: 'Clients', parent: 'w-work', future: 1 },
          { id: 'w-home', name: 'Home' },
          { id: 'w-hcl', name: 'Clients', parent: 'w-home' },
        ],
        notes: { a: 'w-clnt', b: 'w-work' },
      },
    }));
    const prefs = async () => (await kit.account.readPrefs()).prefs as unknown as Prefs;
    return { ...kit, prefs };
  }

  it('keeps every folder’s parent, and every other field, when file_notes writes the settings', async () => {
    const { call, prefs } = await withFolders();
    expect((await call('file_notes', { ids: ['c'], workspace: 'Home' })).isError).toBe(false);
    const { list, notes } = (await prefs()).workspaces;
    expect(list).toEqual([
      { id: 'w-work', name: 'Work', hue: 'moss' },
      { id: 'w-clnt', name: 'Clients', parent: 'w-work', future: 1 },
      { id: 'w-home', name: 'Home' },
      { id: 'w-hcl', name: 'Clients', parent: 'w-home' },
    ]);
    expect(notes).toEqual({ a: 'w-clnt', b: 'w-work', c: 'w-home' });
  });

  it('lists each with its parent, its path and what is under it, and list_notes on a parent takes its folders’ notes', async () => {
    const { call } = await withFolders();
    const spaces = (JSON.parse((await call('list_workspaces')).text) as { workspaces: Space[] }).workspaces;
    expect(spaces.find((w) => w.id === 'w-work')).toEqual({ id: 'w-work', name: 'Work', path: 'Work', organization: false, notes: 1, notesUnder: 2, archived: 0 });
    expect(spaces.find((w) => w.id === 'w-clnt')).toEqual({ id: 'w-clnt', name: 'Clients', parent: 'w-work', path: 'Work › Clients', organization: false, notes: 1, notesUnder: 1, archived: 0 });
    const listed = JSON.parse((await call('list_notes', { workspace: 'Work' })).text) as { notes: { id: string; workspace: { id: string; path?: string } }[] };
    expect(listed.notes.map((n) => n.id).sort()).toEqual(['a', 'b']);
    expect(listed.notes.find((n) => n.id === 'a')!.workspace).toEqual({ id: 'w-clnt', name: 'Clients', organization: false, path: 'Work › Clients' });
    expect((JSON.parse((await call('list_notes', { workspace: 'Work › Clients' })).text) as { count: number }).count).toBe(1);
  });

  it('finds a folder by its path either way, and refuses a name two folders share, naming both', async () => {
    const { call, prefs } = await withFolders();
    expect((await call('file_notes', { ids: ['c'], workspace: 'Home › Clients' })).isError).toBe(false);
    expect((await prefs()).workspaces.notes.c).toBe('w-hcl');
    expect((await call('file_notes', { ids: ['c'], workspace: 'work/clients' })).isError).toBe(false);
    expect((await prefs()).workspaces.notes.c).toBe('w-clnt');
    expect(await call('file_notes', { ids: ['c'], workspace: 'Clients' })).toEqual({
      isError: true,
      text: 'More than one workspace is called “Clients”: give its path or id (Work › Clients (w-clnt), Home › Clients (w-hcl)).',
    });
    expect((await call('file_notes', { ids: ['c'], workspace: 'Nowhere › Clients' })).text).toBe('No workspace is called “Nowhere › Clients”. These are: Work, Work › Clients, Home, Home › Clients.');
  });

  it('makes a folder in the app’s id shape, inside a parent or at the top, and answers the one already there', async () => {
    const { call, prefs } = await withFolders();
    const made = JSON.parse((await call('create_folder', { name: '  Acme   Ltd ', parent: 'Work › Clients', hue: 'rose' })).text) as { folder: Folder };
    expect(made.folder).toMatchObject({ name: 'Acme Ltd', parent: 'w-clnt', path: 'Work › Clients › Acme Ltd', organization: false });
    expect(made.folder.id).toMatch(/^w-[0-9a-z]{6}$/);
    expect((await prefs()).workspaces.list.at(-1)).toEqual({ id: made.folder.id, name: 'Acme Ltd', hue: 'rose', parent: 'w-clnt' });
    const again = JSON.parse((await call('create_folder', { name: 'acme ltd', parent: 'w-clnt' })).text) as { folder: Folder; existed: boolean };
    expect(again).toMatchObject({ existed: true, folder: { id: made.folder.id } });
    const top = JSON.parse((await call('create_folder', { name: 'Reading' })).text) as { folder: Folder };
    expect(top.folder).toEqual({ id: top.folder.id, name: 'Reading', path: 'Reading', organization: false });
    expect((await call('create_folder', { name: '///' })).isError).toBe(true);
    expect((await prefs()).workspaces.list).toHaveLength(6);
  });

  it('renames and moves a folder in the settings alone, refusing a clash, itself, and a folder inside it', async () => {
    const { call, prefs } = await withFolders();
    expect(JSON.parse((await call('rename_folder', { folder: 'Work › Clients', name: 'Customers' })).text)).toEqual({ folder: { id: 'w-clnt', name: 'Customers', parent: 'w-work', path: 'Work › Customers', organization: false } });
    expect((await call('rename_folder', { folder: 'Home', name: 'work' })).text).toBe('“Work” is there already (w-work). File the notes into it, or pick another name.');
    expect(JSON.parse((await call('move_folder', { folder: 'w-clnt', parent: 'Home' })).text)).toEqual({ folder: { id: 'w-clnt', name: 'Customers', parent: 'w-home', path: 'Home › Customers', organization: false } });
    expect(JSON.parse((await call('move_folder', { folder: 'w-clnt' })).text).folder).toEqual({ id: 'w-clnt', name: 'Customers', path: 'Customers', organization: false });
    expect((await call('move_folder', { folder: 'Home', parent: 'Home › Clients' })).text).toBe('“Home” cannot go inside itself or a folder inside it.');
    expect((await call('move_folder', { folder: 'w-hcl', parent: 'Work' })).isError).toBe(false);
    expect((await call('move_folder', { folder: 'w-clnt', parent: 'Work' })).isError).toBe(false);
    const { list, notes } = (await prefs()).workspaces;
    expect(list.find((w) => w.id === 'w-clnt')).toEqual({ id: 'w-clnt', name: 'Customers', parent: 'w-work', future: 1 });
    expect(notes).toEqual({ a: 'w-clnt', b: 'w-work' });
  });

  it('deletes a folder as the app removes one: its folders a level up, its own notes unfiled, no note deleted', async () => {
    const { call, prefs, service } = await withFolders();
    const answer = JSON.parse((await call('delete_folder', { folder: 'Work' })).text);
    expect(answer).toEqual({ deleted: { id: 'w-work', name: 'Work', path: 'Work', organization: false }, foldersMovedUp: [{ id: 'w-clnt', name: 'Clients', path: 'Clients', organization: false }], notesUnfiled: 1 });
    const { list, notes } = (await prefs()).workspaces;
    expect(list.map((w) => w.id)).toEqual(['w-clnt', 'w-home', 'w-hcl']);
    expect(list[0]).toEqual({ id: 'w-clnt', name: 'Clients', future: 1 });
    expect(notes).toEqual({ a: 'w-clnt' });
    expect((await service.stored('b'))!.note.body).toBe('# Roadmap');
  });
});

describe('folders inside an organization', () => {
  async function withTeam() {
    const kit = await connected();
    const org = await anOrganization(kit.service, 'Ghost.md');
    const root = `org-${org.id}`;
    await kit.account.changePrefs(() => ({ workspaces: { list: [{ id: root, name: 'Ghost.md' }], notes: {} } }));
    const phone = teamDevice(kit.service, org);
    phone.put('t1', '# Baby on the way\n\n- [ ] crib', { path: 'orgs/Ghost.md/Baby on the way.md', createdAt: WRITTEN - 5 });
    await phone.sync();
    const prefs = async () => (await kit.account.readPrefs()).prefs as unknown as Prefs;
    const folder = async (name: string, parent: string) => (JSON.parse((await kit.call('create_folder', { name, parent })).text) as { folder: Folder }).folder;
    return { ...kit, org, root, phone, prefs, folder };
  }

  it('files a team note into a folder by its path alone - id, words, file name and dates kept - and a member’s device follows', async () => {
    const { call, service, org, phone, folder, prefs } = await withTeam();
    const clients = await folder('Clients', 'Ghost.md');
    expect(clients).toMatchObject({ parent: `org-${org.id}`, path: 'Ghost.md › Clients', organization: true });
    const before = (await rowOf(service, org, 't1'))!.note;
    const filed = JSON.parse((await call('file_notes', { ids: ['t1'], workspace: 'Ghost.md › Clients' })).text);
    expect(filed).toEqual({ workspace: { id: clients.id, name: 'Clients', organization: true, path: 'Ghost.md › Clients' }, filed: [{ id: 't1', title: 'Baby on the way' }] });
    const after = (await rowOf(service, org, 't1'))!.note;
    expect(after).toEqual({ ...before, path: 'orgs/Ghost.md/Clients/Baby on the way.md' });
    expect((await prefs()).workspaces.notes.t1).toBe(clients.id);
    await phone.sync();
    expect(phone.notes.get('t1')).toMatchObject({ id: 't1', path: 'orgs/Ghost.md/Clients/Baby on the way.md', body: before.body, createdAt: before.createdAt });
    // Read back where its path says, and counted there and under the organization.
    expect((JSON.parse((await call('read_note', { id: 't1' })).text) as { workspace: unknown }).workspace).toEqual({ id: clients.id, name: 'Clients', organization: true, path: 'Ghost.md › Clients' });
    const spaces = (JSON.parse((await call('list_workspaces')).text) as { workspaces: Space[] }).workspaces;
    expect(spaces.find((w) => w.id === `org-${org.id}`)).toMatchObject({ notes: 0, notesUnder: 1 });
    expect(spaces.find((w) => w.id === clients.id)).toMatchObject({ notes: 1, notesUnder: 1, organization: true });
    expect((JSON.parse((await call('list_notes', { workspace: 'Ghost.md' })).text) as { count: number }).count).toBe(1);
    // And back to the organization's own folder.
    await call('file_notes', { ids: ['t1'], workspace: 'Ghost.md' });
    expect((await rowOf(service, org, 't1'))!.note).toEqual({ ...before, path: 'orgs/Ghost.md/Baby on the way.md' });
  });

  it('keeps its new path over a row another member put first, and their change with it', async () => {
    const { account, service, org, phone } = await withTeam();
    await account.pull();
    phone.put('t1', '# Baby on the way\n\n- [ ] crib\n- [ ] pram', { starred: true });
    await phone.sync();
    await account.repath('t1', 'orgs/Ghost.md/Family/Baby on the way.md');
    const row = (await rowOf(service, org, 't1'))!.note;
    expect(row).toMatchObject({ path: 'orgs/Ghost.md/Family/Baby on the way.md', starred: true, body: '# Baby on the way\n\n- [ ] crib\n- [ ] pram' });
  });

  it('puts one of the account’s own notes to the team in a folder, at the folder’s path, its file name kept', async () => {
    const { call, service, org, folder, prefs } = await withTeam();
    const plans = await folder('Plans', 'Ghost.md');
    await service.deviceWrites(aNote('p1', '# Trip\n\nLisbon.', { path: 'workspaces/Home/Trip 2.md' }));
    expect((await call('file_notes', { ids: ['p1'], workspace: plans.id })).isError).toBe(false);
    const row = (await rowOf(service, org, 'p1'))!.note;
    expect(row).toMatchObject({ id: 'p1', body: '# Trip\n\nLisbon.', createdAt: WRITTEN, path: 'orgs/Ghost.md/Plans/Trip 2.md' });
    expect(service.notes.get('p1')).toMatchObject({ deleted: true });
    expect((await prefs()).workspaces.notes.p1).toBe(plans.id);
  });

  it('makes a note in a folder of the team’s as the team’s, at that folder’s path', async () => {
    const { call, service, org, folder, phone } = await withTeam();
    await folder('Clients', 'Ghost.md');
    const acme = await folder('Acme', 'Ghost.md › Clients');
    const made = JSON.parse((await call('create_note', { title: 'Kickoff', body: 'Monday.', workspace: 'Ghost.md › Clients › Acme' })).text) as { created: { id: string; workspace: unknown } };
    expect(made.created.workspace).toEqual({ id: acme.id, name: 'Acme', organization: true, path: 'Ghost.md › Clients › Acme' });
    expect((await rowOf(service, org, made.created.id))!.note.path).toBe('orgs/Ghost.md/Clients/Acme/Kickoff.md');
    expect(service.notes.has(made.created.id)).toBe(false);
    await phone.sync();
    expect(phone.notes.get(made.created.id)!.path).toBe('orgs/Ghost.md/Clients/Acme/Kickoff.md');
  });

  it('renames and moves a folder of the team’s, putting each note under it again with only its path changed', async () => {
    const { call, service, org, folder, phone } = await withTeam();
    const family = await folder('Family', 'Ghost.md');
    const baby = await folder('Baby', 'Ghost.md › Family');
    await call('file_notes', { ids: ['t1'], workspace: baby.id });
    const before = (await rowOf(service, org, 't1'))!.note;
    expect(before.path).toBe('orgs/Ghost.md/Family/Baby/Baby on the way.md');

    const renamed = JSON.parse((await call('rename_folder', { folder: 'Ghost.md › Family', name: 'Household' })).text);
    expect(renamed).toEqual({
      folder: { id: family.id, name: 'Household', parent: `org-${org.id}`, path: 'Ghost.md › Household', organization: true },
      teamNotesMoved: [{ id: 't1', title: 'Baby on the way', path: 'orgs/Ghost.md/Household/Baby/Baby on the way.md' }],
    });
    expect((await rowOf(service, org, 't1'))!.note).toEqual({ ...before, path: 'orgs/Ghost.md/Household/Baby/Baby on the way.md' });

    const moved = JSON.parse((await call('move_folder', { folder: baby.id, parent: 'Ghost.md' })).text);
    expect(moved.teamNotesMoved).toEqual([{ id: 't1', title: 'Baby on the way', path: 'orgs/Ghost.md/Baby/Baby on the way.md' }]);
    const now = (await rowOf(service, org, 't1'))!.note;
    expect(now).toEqual({ ...before, path: 'orgs/Ghost.md/Baby/Baby on the way.md' });
    await phone.sync();
    expect(phone.notes.get('t1')).toMatchObject({ id: 't1', body: before.body, path: 'orgs/Ghost.md/Baby/Baby on the way.md' });
  });

  it('deletes a folder of the team’s with its notes a level up, still the team’s', async () => {
    const { call, service, org, folder, prefs } = await withTeam();
    const family = await folder('Family', 'Ghost.md');
    const baby = await folder('Baby', family.id);
    const school = await folder('School', family.id);
    await call('file_notes', { ids: ['t1'], workspace: baby.id });
    await call('move_folder', { folder: school.id, parent: baby.id });
    const answer = JSON.parse((await call('delete_folder', { folder: baby.id })).text);
    expect(answer).toMatchObject({
      deleted: { id: baby.id, path: 'Ghost.md › Family › Baby' },
      foldersMovedUp: [{ id: school.id, parent: family.id, path: 'Ghost.md › Family › School' }],
      notesMovedTo: { id: family.id, path: 'Ghost.md › Family' },
      teamNotesMoved: [{ id: 't1', path: 'orgs/Ghost.md/Family/Baby on the way.md' }],
    });
    expect((await rowOf(service, org, 't1'))!.note.path).toBe('orgs/Ghost.md/Family/Baby on the way.md');
    const { list, notes } = (await prefs()).workspaces;
    expect(list.map((w) => w.id)).not.toContain(baby.id);
    expect(notes.t1).toBe(family.id);
  });

  it('refuses the organization’s own workspace, and a folder moved into or out of the organization', async () => {
    const { call, folder, org } = await withTeam();
    const clients = await folder('Clients', 'Ghost.md');
    await call('create_folder', { name: 'Home' });
    expect((await call('rename_folder', { folder: 'Ghost.md', name: 'Other' })).text).toBe('“Ghost.md” is an organization’s own workspace: it follows the organization, and is never renamed, moved or deleted here.');
    expect((await call('delete_folder', { folder: `org-${org.id}` })).isError).toBe(true);
    expect((await call('move_folder', { folder: clients.id })).text).toContain('is the team’s, and its notes would leave the team');
    expect((await call('move_folder', { folder: 'Home', parent: clients.id })).text).toContain('is personal, and its notes would go to a team');
    expect((await call('create_folder', { name: 'Ghost.md' })).isError).toBe(false);
  });

  it('lists an organization’s workspace the settings did not have when a folder is made in it', async () => {
    const { call, account, org, prefs } = await withTeam();
    await account.changePrefs(() => ({ workspaces: { list: [], notes: {} } }));
    const made = JSON.parse((await call('create_folder', { name: 'Clients', parent: `org-${org.id}` })).text) as { folder: Folder };
    expect((await prefs()).workspaces.list).toEqual([{ id: `org-${org.id}`, name: 'Ghost.md' }, { id: made.folder.id, name: 'Clients', parent: `org-${org.id}` }]);
  });
});
