import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { fakeService, type FakeService } from '../../test/fakeService.ts';
import { makeNote } from '../../test/notes.ts';
import type { Session } from '../core/account/keystore.ts';
import type { Notification } from '../core/notifications/kinds.ts';
import { button, buttonSaying, show, typeInto, unmount, waitUntil } from '../../test/render.tsx';
import { stubResizeObserver } from '../../test/stubs.ts';

// The kit asks matchMedia as it loads; the page's wisp watches the bar's size, which jsdom never lays out.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
stubResizeObserver();
vi.mock('../art/wispEdge.ts', () => ({ useWispEdge: () => undefined }));
// A card's small drawing is a CodeMirror editor, one per card: nothing the dashboard decides.
vi.mock('./NotePeek.tsx', () => ({ NotePeek: () => null }));
// Signed in as matt, with a token the service in memory minted: every call the page makes reaches that service.
let session: Session | null = null;
vi.mock('../core/account/account.ts', () => ({
  accountState: () => ({ session, unlocked: session !== null }),
  useAccount: () => ({ session, unlocked: session !== null }),
  accountKey: async () => null,
  onAccount: () => () => undefined,
  resume: async () => undefined,
}));
// The pass the page asks for as it opens and on a pull: counted.
const passes = vi.hoisted(() => ({ count: 0 }));
vi.mock('../core/sync/engine.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/sync/engine.ts')>()),
  syncNotificationsNow: async () => {
    passes.count += 1;
  },
}));

const { OrganizationScreen } = await import('./OrganizationScreen.tsx');
const { createOrg, forgetOrgs, orgsState, saveOrgs } = await import('../core/orgs/orgs.ts');
const { forgetNotifications, updateFeed, withFed } = await import('../core/notifications/feed.ts');
const { DEFAULT_PREFERENCES, reloadPreferences, setPreferences } = await import('../core/preferences.ts');
const { fileNote, orgWorkspaceId, reloadWorkspaces } = await import('../core/workspaces.ts');

/**
 * An organization's dashboard (notes/OrganizationScreen.tsx; Matt: "Design and deploy a dashboard for organizations
 * when clicking an organization in the header don't take me to the settings, instead, take me to this dashboard page
 * and have a organization settings icon on that"), against the service in memory: the hero and its two things to do,
 * the notes filed in its workspace, the members with the invite field for an owner or an admin, the organization's
 * own news, the pills to the others, and the cog to its settings.
 */

const ACCOUNT = { handle: 'matt', password: 'correct horse' };
let service: FakeService;
let at = 1_000_000;

/** An organization made by matt, as the service holds it; its row is kept and its workspace made at once. */
async function made(name: string, hue: string | null = 'sea'): Promise<string> {
  const org = await createOrg(name, hue, { token: service.signedIn(), fetcher: service.fetcher });
  return org.id;
}

/** sam invited to `orgId` by the service's own rules, and joined when `joined`. */
async function sam(orgId: string, joined: boolean): Promise<void> {
  await service.fetcher(`https://x/api/v1/orgs/${orgId}/members`, { method: 'POST', headers: { Authorization: `Bearer ${service.signedIn()}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ handle: 'sam' }) });
  if (joined) service.orgs.get(orgId)!.rows.get('sam')!.state = 'member';
}

/** A row of the feed, as a pass would have fed it. */
function fed(row: Partial<Notification> & { kind: Notification['kind'] }): Notification {
  at += 60_000;
  const item: Notification = { id: row.id ?? `n${at}`, rev: at, at, readAt: null, hidden: false, ...row };
  updateFeed(7, (state) => ({ ...withFed(state, item, at), cursor: at }));
  return item;
}

type Props = Parameters<typeof OrganizationScreen>[0];
const page = (orgId: string, over: Partial<Props> = {}) =>
  show(
    <OrganizationScreen
      orgId={orgId}
      notes={[]}
      onBack={() => undefined}
      onOpenNote={() => undefined}
      onNewNote={() => undefined}
      onAllNotes={() => undefined}
      onSettings={() => undefined}
      onOpenOrganization={() => undefined}
      onLog={() => undefined}
      onAccount={() => undefined}
      {...over}
    />,
  );

const members = () => [...document.querySelectorAll<HTMLElement>('ul[aria-label="Members"] li')].map((li) => li.textContent);
const cards = () => [...document.querySelectorAll<HTMLElement>('ol[aria-label="Notes in this organization"] li')].map((li) => li.textContent);
const news = () => [...document.querySelectorAll<HTMLElement>('ol[aria-label="Activity"] li')].map((li) => li.textContent);

beforeEach(async () => {
  localStorage.clear();
  reloadPreferences();
  reloadWorkspaces();
  setPreferences(DEFAULT_PREFERENCES);
  service = await fakeService(ACCOUNT, { peers: ['sam', 'lee'] });
  vi.stubGlobal('fetch', service.fetcher);
  session = { token: service.signedIn(), handle: 'matt', accountId: 7 };
  passes.count = 0;
  forgetOrgs(7);
  forgetNotifications(7);
});

afterEach(() => {
  unmount();
  vi.unstubAllGlobals();
  forgetOrgs(7);
  forgetNotifications(7);
});

describe('an organization’s dashboard', () => {
  it('is the organization: its name in the bar, the hero, the members read from the service, and the feed taken on opening', async () => {
    const id = await made('Ghost');
    await sam(id, true);
    page(id);
    expect(document.querySelector('h1')?.textContent).toBe('Ghost');
    expect(document.querySelector('h1 [data-hue="sea"]')).not.toBeNull();
    expect(document.body.textContent).toContain('Notes filed here stay yours for now; sharing them with the team comes next.');
    await waitUntil(() => expect(members()).toHaveLength(2));
    expect(members()[0]).toContain('matt');
    expect(members()[0]).toContain('Owner');
    expect(members()[0]).toContain('You, owner since');
    expect(members()[1]).toContain('samMember');
    // The hero counts who has joined, once the service has said.
    expect(document.body.textContent).toContain('2 members · You are owner');
    expect(passes.count).toBe(1);
  });

  it('puts its settings behind a cog in the bar, and New note and the way home on the page', async () => {
    const onSettings = vi.fn();
    const onNewNote = vi.fn();
    const onBack = vi.fn();
    const id = await made('Ghost');
    page(id, { onSettings, onNewNote, onBack });
    act(() => button('Organization settings').click());
    expect(onSettings).toHaveBeenCalledOnce();
    act(() => buttonSaying(document.body, 'New note')!.click());
    expect(onNewNote).toHaveBeenCalledOnce();
    act(() => button('Back to home').click());
    expect(onBack).toHaveBeenCalledOnce();
  });

  it('shows the notes filed in its workspace, newest first, and not the others or the archived', async () => {
    const onAllNotes = vi.fn();
    const onOpenNote = vi.fn();
    const id = await made('Ghost');
    const notes = [
      makeNote('a', '# Roadmap', { updatedAt: 10 }),
      makeNote('b', '# Standup', { updatedAt: 20 }),
      makeNote('c', '# Groceries', { updatedAt: 30 }),
      makeNote('d', '# Old plan', { updatedAt: 40, archivedAt: 41 }),
    ];
    fileNote('a', orgWorkspaceId(id));
    fileNote('b', orgWorkspaceId(id));
    fileNote('d', orgWorkspaceId(id));
    page(id, { notes, onAllNotes, onOpenNote });
    expect(cards()).toHaveLength(2);
    expect(cards()[0]).toContain('Standup');
    expect(cards()[1]).toContain('Roadmap');
    act(() => buttonSaying(document.body, 'In its workspace')!.click());
    expect(onAllNotes).toHaveBeenCalledOnce();
    act(() => [...document.querySelectorAll<HTMLButtonElement>('ol[aria-label="Notes in this organization"] button')][0]!.click());
    expect(onOpenNote).toHaveBeenCalledWith('b');
  });

  it('says so when nothing is filed in its workspace yet', async () => {
    const id = await made('Ghost');
    page(id, { notes: [makeNote('c', '# Groceries')] });
    expect(cards()).toEqual([]);
    expect(document.body.textContent).toContain('Nothing is filed here yet.');
  });

  it('invites by handle for an owner, with the service’s words when it refuses, and the new invitee in the list', async () => {
    const id = await made('Ghost');
    page(id);
    await waitUntil(() => expect(members()).toHaveLength(1));
    typeInto(document.querySelector<HTMLInputElement>('input[aria-label="Invite by handle"]')!, 'nobody');
    act(() => buttonSaying(document.querySelector('form')!, 'Invite')!.click());
    await waitUntil(() => expect(document.querySelector('form [role="alert"]')?.textContent).toBe('No one has that handle.'));
    typeInto(document.querySelector<HTMLInputElement>('input[aria-label="Invite by handle"]')!, 'lee');
    act(() => buttonSaying(document.querySelector('form')!, 'Invite')!.click());
    await waitUntil(() => expect(document.querySelector('form [role="status"]')?.textContent).toBe('lee is invited. They see it in their notifications.'));
    await waitUntil(() => expect(members()).toHaveLength(2));
    expect(members()[1]).toContain('Invited');
  });

  it('offers no invitation to a member who is neither owner nor admin', async () => {
    const id = await made('Ghost');
    const row = orgsState().list.find((each) => each.id === id)!;
    saveOrgs(7, { list: [{ ...row, role: 'member' }], at: Date.now() });
    page(id);
    expect(buttonSaying(document.body, 'Invite')).toBeUndefined();
    expect(document.querySelector('input[aria-label="Invite by handle"]')).toBeNull();
    expect(document.body.textContent).toContain('You are member');
  });

  it('opens the audit log from the clock in the bar and from the Activity heading', async () => {
    const onLog = vi.fn();
    const id = await made('Ghost');
    page(id, { onLog });
    act(() => button('Audit log').click());
    act(() => buttonSaying(document.body, 'Audit log')!.click());
    expect(onLog).toHaveBeenCalledTimes(2);
  });

  it('shows the organization’s own news, newest first, and not another’s or an invitation', async () => {
    const id = await made('Ghost');
    fed({ kind: 'member-joined', from: 'sam', org: { id, name: 'Ghost' }, body: { name: 'Ghost' } });
    fed({ kind: 'role-changed', from: 'matt', org: { id, name: 'Ghost' }, body: { name: 'Ghost', role: 'admin' } });
    fed({ kind: 'member-joined', from: 'lee', org: { id: 'elsewhere', name: 'Elsewhere' }, body: { name: 'Elsewhere' } });
    fed({ kind: 'invite', from: 'sam', org: { id, name: 'Ghost' }, body: { name: 'Ghost' }, state: 'pending' });
    page(id);
    expect(news()).toHaveLength(2);
    expect(news()[0]).toContain('admin');
    expect(news()[1]).toContain('sam');
  });

  it('is the invitation when the person is invited and not yet in, with Accept and Decline', async () => {
    saveOrgs(7, { list: [{ id: 'inv', name: 'Studio', hue: null, role: 'member', state: 'invited', members: 3, invitedBy: 'sam', createdAt: 1 }], at: Date.now() });
    page('inv');
    expect(document.body.textContent).toContain('sam invited you · 3 members');
    expect(buttonSaying(document.body, 'Accept')).toBeTruthy();
    expect(buttonSaying(document.body, 'Decline')).toBeTruthy();
    expect(document.querySelector('ul[aria-label="Members"]')).toBeNull();
  });

  it('moves to another organization by its pill', async () => {
    const onOpenOrganization = vi.fn();
    const id = await made('Ghost');
    const other = await made('Studio', 'rose');
    page(id, { onOpenOrganization });
    const pills = [...document.querySelectorAll<HTMLElement>('nav[aria-label="Your organizations"] > *')];
    expect(pills.map((pill) => pill.textContent)).toEqual(['Ghost', 'Studio']);
    expect(pills[0]!.getAttribute('aria-current')).toBe('page');
    act(() => (pills[1] as HTMLButtonElement).click());
    expect(onOpenOrganization).toHaveBeenCalledWith(other);
  });

  it('says so when the organization is no longer in the list, with no cog', () => {
    page('gone');
    expect(document.body.textContent).toContain('This organization is not in your list any more.');
    expect(() => button('Organization settings')).toThrow();
  });

  it('says what is missing when signed out, and asks for nothing', async () => {
    const id = await made('Ghost');
    session = null;
    page(id);
    expect(document.body.textContent).toContain('Organizations come with an account.');
    expect(passes.count).toBe(0);
  });
});
