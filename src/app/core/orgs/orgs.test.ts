import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fakeService, type FakeService } from '../../../test/fakeService.ts';
import type { Session } from '../account/keystore.ts';
import { preferences, reloadPreferences, setPreferences } from '../preferences.ts';
import { fileNote, reloadWorkspaces, workspaceOf, workspaces } from '../workspaces.ts';
import * as orgs from './orgs.ts';
import type { OrgState } from './types.ts';

/*
 * The organizations against the service in memory (orgs.ts): the calls and the service's words, the list kept per
 * account, and the reconcile that makes an organization's workspace on every member's device - only after a list
 * that arrived (D5), so a service without the route, or one that is down, unfiles nobody's notes.
 */

const SESSION: Session = { token: 't1', handle: 'matt', accountId: 7 };
let session: Session | null = null;
vi.mock('../account/account.ts', () => ({
  accountState: () => ({ session, unlocked: session !== null }),
  accountKey: async () => null,
  onAccount: () => () => undefined,
}));

const ACCOUNT = { handle: 'matt', password: 'correct horse' };

/** A device's view of the list, synced through `service`. */
function device(service: FakeService, fetcher: typeof fetch = service.fetcher) {
  let state: OrgState = { list: [], at: null };
  return {
    get state() {
      return state;
    },
    sync: () =>
      orgs.syncOrgs({
        token: service.signedIn(),
        fetcher,
        save: (next) => {
          state = next;
        },
        now: () => 99,
      }),
  };
}

const ids = () => workspaces().list.map((w) => w.id);

beforeEach(() => {
  localStorage.clear();
  session = { ...SESSION };
  reloadPreferences();
  reloadWorkspaces();
  orgs.forgetOrgs(7);
});

describe('the calls', () => {
  it('make an organization with the caller as owner, and its workspace here at once', async () => {
    const service = await fakeService(ACCOUNT);
    const ctx = { token: service.signedIn(), fetcher: service.fetcher };
    const org = await orgs.createOrg('  Ghost ', 'sea', ctx);
    expect(org).toMatchObject({ name: 'Ghost', hue: 'sea', role: 'owner', state: 'member', members: [{ handle: 'matt', role: 'owner', state: 'member' }] });
    expect(workspaces().list).toEqual([{ id: `org-${org.id}`, name: 'Ghost', hue: 'sea', org: org.id }]);
    expect(orgs.orgsState().list).toEqual([expect.objectContaining({ id: org.id, name: 'Ghost', members: 1 })]);
    expect((await orgs.listOrgs(ctx)).rows).toEqual([expect.objectContaining({ id: org.id, role: 'owner', state: 'member', members: 1 })]);
    expect(await orgs.fetchOrg(org.id, ctx)).toMatchObject({ id: org.id });
  });

  it('invite by handle, and say so in the service’s words when nobody has it', async () => {
    const service = await fakeService(ACCOUNT);
    const ctx = { token: service.signedIn(), fetcher: service.fetcher };
    const org = await orgs.createOrg('Ghost', null, ctx);
    expect(await orgs.inviteByHandle(org.id, 'sam', ctx)).toMatchObject({ handle: 'sam', role: 'member', state: 'invited', invitedBy: 'matt' });
    await expect(orgs.inviteByHandle(org.id, 'nobody', ctx)).rejects.toThrow('No one has that handle.');
    await expect(orgs.inviteByHandle(org.id, 'matt', ctx)).rejects.toThrow('They are already a member.');
    // A pending invitation asked again is refreshed, not doubled.
    await orgs.inviteByHandle(org.id, 'sam', ctx);
    expect((await orgs.fetchOrg(org.id, ctx)).members).toHaveLength(2);
  });

  it('rename and re-hue, with the workspace following; remove and leave; delete with the workspace gone', async () => {
    const service = await fakeService(ACCOUNT);
    const ctx = { token: service.signedIn(), fetcher: service.fetcher };
    const org = await orgs.createOrg('Ghost', null, ctx);
    await orgs.updateOrg(org.id, { name: 'Boo', hue: 'rose' }, ctx);
    expect(workspaces().list[0]).toMatchObject({ name: 'Boo', hue: 'rose' });
    await orgs.inviteByHandle(org.id, 'sam', ctx);
    await orgs.removeMember(org.id, 'sam', ctx);
    expect((await orgs.fetchOrg(org.id, ctx)).members).toHaveLength(1);
    await expect(orgs.removeMember(org.id, 'sam', ctx)).rejects.toThrow('No one by that handle is in this organization.');
    // The owner cannot leave, nor change their own role.
    await expect(orgs.removeMember(org.id, 'matt', ctx)).rejects.toThrow('Hand the organization over first.');
    await expect(orgs.setRole(org.id, 'matt', 'admin', ctx)).rejects.toThrow('Hand the organization over first.');
    fileNote('n1', `org-${org.id}`);
    await orgs.deleteOrg(org.id, ctx);
    expect(workspaces().list).toEqual([]);
    expect(workspaceOf('n1')).toBeNull();
    expect(orgs.orgsState().list).toEqual([]);
    // A 404 in the service's words surfaces as one: it is an answer, not a service without the route.
    await expect(orgs.fetchOrg(org.id, ctx)).rejects.toThrow('No such organization.');
  });

  it('hand the organization over, and the old owner is an admin at once', async () => {
    const service = await fakeService(ACCOUNT);
    const ctx = { token: service.signedIn(), fetcher: service.fetcher };
    const org = await orgs.createOrg('Ghost', null, ctx);
    await orgs.inviteByHandle(org.id, 'sam', ctx);
    await expect(orgs.setRole(org.id, 'sam', 'owner', ctx)).rejects.toThrow('They have not joined yet.');
    service.orgs.get(org.id)!.rows.get('sam')!.state = 'member';
    expect(await orgs.setRole(org.id, 'sam', 'owner', ctx)).toMatchObject({ handle: 'sam', role: 'owner' });
    expect(orgs.orgRow(org.id)?.role).toBe('admin');
    expect(service.rowIn(org.id)).toEqual({ role: 'admin', state: 'member' });
  });

  it('answer an invitation: joined, with the workspace made; or declined, with the row gone', async () => {
    const service = await fakeService(ACCOUNT);
    const ctx = { token: service.signedIn(), fetcher: service.fetcher };
    const joined = service.invited('Ghost', 'sam');
    const declined = service.invited('Boo', 'sam');
    const phone = device(service);
    await phone.sync();
    expect(phone.state.list.map((r) => r.state)).toEqual(['invited', 'invited']);
    // An invitation gets no workspace.
    expect(ids()).toEqual([]);
    expect(await orgs.postInviteAnswer(joined, true, ctx)).toMatchObject({ id: joined, state: 'member', role: 'member' });
    expect(ids()).toEqual([`org-${joined}`]);
    expect(await orgs.postInviteAnswer(declined, false, ctx)).toBeNull();
    await expect(orgs.postInviteAnswer(declined, true, ctx)).rejects.toThrow('You were not invited.');
    await phone.sync();
    expect(phone.state.list).toEqual([expect.objectContaining({ id: joined, state: 'member' })]);
  });

  it('refuse signed out, before any round trip', async () => {
    session = null;
    await expect(orgs.listOrgs()).rejects.toThrow('Sign in first.');
  });
});

describe('the reconcile', () => {
  it('runs on a list that arrived, and only over the organizations the person is a member of', async () => {
    const service = await fakeService(ACCOUNT);
    const ctx = { token: service.signedIn(), fetcher: service.fetcher };
    const ghost = await orgs.createOrg('Ghost', 'moss', ctx);
    const invited = service.invited('Boo', 'sam');
    const phone = device(service);
    await phone.sync();
    expect(phone.state).toEqual({ list: [expect.objectContaining({ id: ghost.id }), expect.objectContaining({ id: invited, state: 'invited' })], at: 99, colour: null });
    expect(workspaces().list).toEqual([{ id: `org-${ghost.id}`, name: 'Ghost', hue: 'moss', org: ghost.id }]);
    // Renamed elsewhere: the workspace follows on the next list. Left: it goes, and its notes are unfiled.
    service.orgs.get(ghost.id)!.name = 'Spectre';
    fileNote('n1', `org-${ghost.id}`);
    await phone.sync();
    expect(workspaces().list[0]).toMatchObject({ name: 'Spectre' });
    expect(workspaceOf('n1')?.id).toBe(`org-${ghost.id}`);
    service.orgs.delete(ghost.id);
    await phone.sync();
    expect(ids()).toEqual([]);
    expect(workspaceOf('n1')).toBeNull();
  });

  it('changes nothing - no workspace, no kept list - when the list does not arrive', async () => {
    const service = await fakeService(ACCOUNT);
    const ctx = { token: service.signedIn(), fetcher: service.fetcher };
    const ghost = await orgs.createOrg('Ghost', null, ctx);
    fileNote('n1', `org-${ghost.id}`);
    const was = workspaces();
    const notYet = await fakeService(ACCOUNT, { teams: false });
    const older = device(notYet);
    await expect(older.sync()).resolves.toBeNull();
    expect(older.state).toEqual({ list: [], at: null });
    expect(workspaces()).toBe(was);

    const down: typeof fetch = async () => new Response(JSON.stringify({ error: 'The service is down.' }), { status: 500 });
    const offline = device(service, down);
    await expect(offline.sync()).rejects.toThrow('The service is down.');
    expect(offline.state).toEqual({ list: [], at: null });
    expect(workspaces()).toBe(was);
    expect(workspaceOf('n1')?.id).toBe(`org-${ghost.id}`);
  });

  it('makes one workspace per organization across devices, so a filing keyed by it survives whichever settings win', async () => {
    const service = await fakeService(ACCOUNT);
    const ctx = { token: service.signedIn(), fetcher: service.fetcher };
    const ghost = await orgs.createOrg('Ghost', null, ctx);
    const phone = device(service);
    await phone.sync();
    fileNote('n1', `org-${ghost.id}`);
    const mine = preferences().workspaces;
    // The other device's settings arrive (core/sync/prefs.ts): it reconciled the same list and made the same id, with
    // a filing of its own; a build before organizations had rewritten the workspace without its marker.
    setPreferences({ workspaces: { list: [{ id: `org-${ghost.id}`, name: 'Ghost' }], notes: { ...mine.notes, n2: `org-${ghost.id}` } } });
    reloadWorkspaces();
    await phone.sync();
    expect(ids()).toEqual([`org-${ghost.id}`]);
    expect(workspaceOf('n1')?.id).toBe(`org-${ghost.id}`);
    expect(workspaceOf('n2')?.id).toBe(`org-${ghost.id}`);
    expect(workspaces().list[0]?.org).toBe(ghost.id);
  });
});

describe('the list kept here', () => {
  it('is the account’s, read once from storage and forgotten on signing out; none signed out', async () => {
    orgs.saveOrgs(7, { list: [], at: 5 });
    expect(JSON.parse(localStorage.getItem('glyph-sync-7-orgs') ?? 'null')).toEqual({ list: [], at: 5 });
    expect(orgs.orgsState().at).toBe(5);
    session = null;
    expect(orgs.orgsState()).toEqual({ list: [], at: null, colour: null });
    session = { ...SESSION };
    orgs.forgetOrgs(7);
    expect(localStorage.getItem('glyph-sync-7-orgs')).toBeNull();
    expect(orgs.orgsState()).toEqual({ list: [], at: null, colour: null });
  });

  it('reads rubbish, or a row this build cannot read, as nothing', () => {
    localStorage.setItem('glyph-sync-7-orgs', JSON.stringify({ list: [{ id: 'o1', name: 'Ghost', role: 'owner', state: 'member' }, { id: 'o2' }, 'no'], at: 'then' }));
    expect(orgs.orgsState()).toEqual({ list: [{ id: 'o1', name: 'Ghost', hue: null, role: 'owner', state: 'member', members: 0, invitedBy: null, createdAt: 0, colour: null, keys: { generation: 0, mine: false, missing: 0 } }], at: null, colour: null });
    localStorage.setItem('glyph-sync-7-orgs', 'not json');
    orgs.forgetOrgs(7);
    expect(orgs.orgsState()).toEqual({ list: [], at: null, colour: null });
  });

  it('tells its listeners once per change', async () => {
    let told = 0;
    const off = orgs.onOrgs(() => {
      told += 1;
    });
    orgs.saveOrgs(7, { list: [], at: 1 });
    expect(told).toBe(1);
    off();
  });
});
