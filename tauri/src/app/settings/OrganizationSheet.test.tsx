import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { fakeService, type FakeService } from '../../test/fakeService.ts';
import type { Session } from '../core/account/keystore.ts';
import { button, buttonSaying, show, typeInto, unmount, waitUntil } from '../../test/render.tsx';
import { stubResizeObserver } from '../../test/stubs.ts';

// The kit asks the window's resolution as it loads, before any of the imports below reach it.
await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
stubResizeObserver();

// A phone's width unless a test says otherwise; the smoke under the header is its own test's.
let wide = false;
vi.mock('../core/useWideScreen.ts', () => ({ useSidebar: () => wide }));
vi.mock('../art/wispEdge.ts', () => ({ useWispEdge: () => undefined }));
// The motor, which a twice-tapped row warns through.
vi.mock('../core/haptics.ts', async (importOriginal) => ({ ...(await importOriginal<typeof import('../core/haptics.ts')>()), fireNativeHaptic: () => undefined }));
// The way out to the phone's mail app, which a report opens.
const opened: string[] = [];
vi.mock('../core/linkPreview.ts', async (importOriginal) => ({ ...(await importOriginal<typeof import('../core/linkPreview.ts')>()), openLink: async (url: string) => void opened.push(url) }));
// Signed in as matt, with a token the service in memory minted: every call the screen makes reaches that service.
let session: Session | null = null;
vi.mock('../core/account/account.ts', () => ({
  accountState: () => ({ session, unlocked: session !== null }),
  useAccount: () => ({ session, unlocked: session !== null }),
  accountKey: async () => null,
  onAccount: () => () => undefined,
  resume: async () => undefined,
}));

const { OrganizationSheet } = await import('./OrganizationSheet.tsx');
const { createOrg, forgetOrgs, saveOrgs, syncOrgs } = await import('../core/orgs/orgs.ts');
const { preferences, reloadPreferences, setPreferences, DEFAULT_PREFERENCES } = await import('../core/preferences.ts');
const { reloadWorkspaces, workspaces } = await import('../core/workspaces.ts');
const { goBack } = await import('../core/back.ts');

/**
 * An organization's own screen (docs/TEAMS.md, D6), against the service in memory: the Settings surface with the
 * organization's name, opened on Members with its hero, the roles' powers on the rows, invitations by handle with
 * the service's words when they are refused, the workspace, the mute, and Leave or Delete tapped twice.
 */

const ACCOUNT = { handle: 'matt', password: 'correct horse' };
let service: FakeService;

/** The organization made by matt, as the service holds it. */
async function ghost(): Promise<string> {
  const org = await createOrg('Ghost', 'sea', { token: service.signedIn(), fetcher: service.fetcher });
  return org.id;
}

/** sam invited to `orgId` by the service's own rules, and joined when `joined`: the one account can only be matt. */
async function sam(orgId: string, joined: boolean): Promise<void> {
  await service.fetcher(`https://x/api/v1/orgs/${orgId}/members`, { method: 'POST', headers: { Authorization: `Bearer ${service.signedIn()}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ handle: 'sam' }) });
  if (joined) {
    const row = service.orgs.get(orgId)!.rows.get('sam')!;
    row.state = 'member';
  }
}

const sheet = (orgId: string, over: Partial<{ from: 'settings' | 'dashboard'; landOnMembers: boolean; onClose: () => void; onNotes: () => void }> = {}) =>
  show(<OrganizationSheet orgId={orgId} onClose={over.onClose ?? (() => undefined)} onNotes={over.onNotes ?? (() => undefined)} from={over.from} landOnMembers={over.landOnMembers} />);

const display = (host: HTMLElement) => host.querySelector('.settingsScreen__display')?.textContent ?? null;
const headWord = (host: HTMLElement) => host.querySelector('.settingsScreen__headWord')?.textContent?.trim();
const labels = (host: HTMLElement) => [...host.querySelectorAll('.settingsScreen__rowLabel')].map((l) => l.textContent);
const rowFor = (host: HTMLElement, label: string) => [...host.querySelectorAll<HTMLButtonElement>('.settingsScreen__row')].find((row) => row.querySelector('.settingsScreen__rowLabel')?.textContent === label)!;
/** A member's row on Members, by handle, with its chip's words and the words under it. */
const member = (host: HTMLElement, handle: string) => {
  const row = [...host.querySelectorAll<HTMLElement>('.setk-row')].find((r) => r.querySelector('.setk-row__label')?.textContent?.startsWith(handle));
  return row ? { row, chip: row.querySelector('[data-role]')?.textContent, hint: row.querySelector('.setk-row__hint')?.textContent, words: [...row.querySelectorAll('button')].map((b) => b.textContent) } : null;
};
const problem = (host: HTMLElement) => host.querySelector('[role="alert"]')?.textContent;

beforeEach(async () => {
  localStorage.clear();
  reloadPreferences();
  reloadWorkspaces();
  setPreferences(DEFAULT_PREFERENCES);
  service = await fakeService(ACCOUNT);
  vi.stubGlobal('fetch', service.fetcher);
  session = { token: service.signedIn(), handle: 'matt', accountId: 7 };
  forgetOrgs(7);
});

afterEach(() => {
  unmount();
  vi.unstubAllGlobals();
  forgetOrgs(7);
});

describe('the screen', () => {
  it('opens on Members, with the hero and the sentence about the workspace, under the organization’s name and without a search', async () => {
    const id = await ghost();
    const host = sheet(id);
    expect(display(host)).toBe('Members');
    expect(headWord(host)).toBe('Ghost');
    expect(host.querySelector('.settingsScreen')?.getAttribute('aria-label')).toBe('Ghost');
    expect(host.querySelector('input[type="search"]')).toBeNull();
    expect(host.querySelector('.setk-hero__title')?.textContent).toBe('Ghost');
    expect(host.querySelector('.setk-hero__meta')?.textContent).toBe('1 member · You are owner');
    expect(host.querySelector('.setk-hero__glyph')?.querySelector('[data-hue="sea"]')).not.toBeNull();
    expect(host.querySelector('.setk__footer')?.textContent).toBe('Notes filed here are the team’s: everyone in it reads and edits them, and edits made apart merge.');
    await waitUntil(() => expect(member(host, 'matt')?.chip).toBe('Owner'));
    // The owner's own row offers nothing: leaving is the last section, and nobody removes the owner.
    expect(member(host, 'matt')?.words).toEqual([]);
  });

  // Matt: "add the ability for users to pick and change their color" (docs/SHARED.md, S7).
  it('has Your colour here under the members: the account’s until one is picked, then that one alone, with the way back', async () => {
    service.peerColour('matt', 'moss');
    const id = await ghost();
    const host = sheet(id);
    await waitUntil(() => expect(member(host, 'matt')?.chip).toBe('Owner'));
    const section = () => [...host.querySelectorAll<HTMLElement>('.setk')].find((s) => s.querySelector('.setk__title')?.textContent === 'Your colour here')!;
    expect(section().querySelector('.setk__footer')?.textContent).toContain('Your account’s colour');
    act(() => (section().querySelector('[role="radio"][aria-label="Rose"]') as HTMLButtonElement).click());
    await waitUntil(() => expect(service.orgs.get(id)!.rows.get('matt')!.hue).toBe('rose'));
    await waitUntil(() => expect(section().querySelector('.setk__footer')?.textContent).toContain('Worn in this organization alone'));
    expect(section().querySelector('[role="radio"][aria-checked="true"]')?.getAttribute('aria-label')).toBe('Rose');
    act(() => buttonSaying(section(), 'Use your account’s colour')!.click());
    await waitUntil(() => expect(service.orgs.get(id)!.rows.get('matt')!.hue).toBeNull());
    await waitUntil(() => expect(section().querySelector('.setk__footer')?.textContent).toContain('Your account’s colour'));
  });

  it('steps back from Members to the six sections, Delete last for the owner, and closes from there', async () => {
    const onClose = vi.fn();
    const id = await ghost();
    const host = sheet(id, { onClose });
    act(() => {
      goBack();
    });
    expect(display(host)).toBeNull();
    expect(labels(host)).toEqual(['General', 'Members', 'Workspace', 'Notifications', 'Report', 'Delete']);
    expect(host.querySelector('.settingsScreen__headWord')?.getAttribute('aria-label')).toBe('Back to your notes');
    act(() => {
      goBack();
    });
    expect(onClose).toHaveBeenCalledOnce();
  });

  it('says “← Organizations” when opened from Settings, and closing is that', async () => {
    const onClose = vi.fn();
    const id = await ghost();
    const host = sheet(id, { from: 'settings', onClose });
    act(() => host.querySelector<HTMLButtonElement>('.settingsScreen__headWord')!.click());
    expect(headWord(host)).toBe('Organizations');
    act(() => host.querySelector<HTMLButtonElement>('.settingsScreen__headWord')!.click());
    expect(onClose).toHaveBeenCalledOnce();
  });

  it('opens on its sections from the dashboard’s cog, its head the organization’s name, which closes back to it', async () => {
    const onClose = vi.fn();
    const id = await ghost();
    const host = sheet(id, { from: 'dashboard', landOnMembers: false, onClose });
    expect(display(host)).toBeNull();
    expect(labels(host)).toContain('Members');
    // The word is the place it goes, the dashboard, named as the organization is; not "Back to your notes".
    expect(headWord(host)).toBe('Ghost');
    expect(host.querySelector('.settingsScreen__headWord')?.hasAttribute('aria-label')).toBe(false);
    act(() => host.querySelector<HTMLButtonElement>('.settingsScreen__headWord')!.click());
    expect(onClose).toHaveBeenCalledOnce();
  });

  it('shows the list beside Members on a wide window, with Members’ row current', async () => {
    wide = true;
    try {
      const id = await ghost();
      const host = sheet(id);
      expect(display(host)).toBe('Members');
      expect(rowFor(host, 'Members').getAttribute('aria-current')).toBe('page');
      expect(host.querySelector('.settingsScreen__pane')?.getAttribute('data-hue')).toBe('blue');
    } finally {
      wide = false;
    }
  });
});

describe('Members', () => {
  it('invites by handle, draws the invitee with a dashed chip, and says in the service’s words when nobody has the handle', async () => {
    const id = await ghost();
    const host = sheet(id);
    await waitUntil(() => expect(member(host, 'matt')).not.toBeNull());
    const field = host.querySelector<HTMLInputElement>('input[aria-label="Handle"]')!;
    typeInto(field, 'nobody');
    await act(async () => buttonSaying(host, 'Invite')!.form!.requestSubmit());
    await waitUntil(() => expect(problem(host)).toBe('No one has that handle.'));
    typeInto(field, 'sam');
    await act(async () => buttonSaying(host, 'Invite')!.form!.requestSubmit());
    await waitUntil(() => expect(member(host, 'sam')?.chip).toBe('Invited'));
    expect(member(host, 'sam')?.row.querySelector('[data-state="invited"]')).not.toBeNull();
    expect(host.querySelector('[role="status"]')?.textContent).toBe('sam is invited. They see it in their notifications.');
    expect(member(host, 'sam')?.hint).toMatch(/^Invited by matt/);
    // An invitee can be withdrawn, not made anything.
    expect(member(host, 'sam')?.words).toEqual(['Withdraw']);
    act(() => member(host, 'sam')!.row.querySelector<HTMLButtonElement>('button')!.click());
    await waitUntil(() => expect(member(host, 'sam')).toBeNull());
    expect(service.orgs.get(id)?.rows.get('sam')?.state ?? 'gone').not.toBe('invited');
  });

  it('lets the owner make an admin, remove a member, and hand over on a second tap, after which Delete is Leave', async () => {
    const id = await ghost();
    await sam(id, true);
    const host = sheet(id);
    await waitUntil(() => expect(member(host, 'sam')?.chip).toBe('Member'));
    expect(member(host, 'sam')?.words).toEqual(['Make admin', 'Hand over', 'Remove']);
    expect(host.querySelector('.setk-hero__meta')?.textContent).toBe('2 members · You are owner');
    act(() => button('Make admin', member(host, 'sam')!.row).click());
    await waitUntil(() => expect(member(host, 'sam')?.chip).toBe('Admin'));
    expect(member(host, 'sam')?.words).toEqual(['Make member', 'Hand over', 'Remove']);
    // Handing over asks twice.
    act(() => button('Hand over', member(host, 'sam')!.row).click());
    expect(member(host, 'sam')?.words).toContain('Tap again to hand over');
    expect(service.orgs.get(id)?.rows.get('sam')?.role).toBe('admin');
    act(() => button('Tap again to hand over', member(host, 'sam')!.row).click());
    await waitUntil(() => expect(member(host, 'sam')?.chip).toBe('Owner'));
    expect(member(host, 'matt')?.chip).toBe('Admin');
    expect(host.querySelector('.setk-hero__meta')?.textContent).toBe('2 members · You are admin');
    // An admin removes members, never the owner, and the last section is Leave now.
    expect(member(host, 'sam')?.words).toEqual([]);
    act(() => {
      goBack();
    });
    expect(labels(host)).toEqual(['General', 'Members', 'Workspace', 'Notifications', 'Report', 'Leave']);
  });

  it('shows the service’s refusal under the row it was asked on', async () => {
    const id = await ghost();
    await sam(id, false);
    const host = sheet(id);
    await waitUntil(() => expect(member(host, 'sam')?.chip).toBe('Invited'));
    // The fake refuses a role for someone who has not joined, as the service does.
    const row = service.orgs.get(id)!.rows.get('sam')!;
    row.state = 'member';
    await act(async () => undefined);
    unmount();
    const again = sheet(id);
    await waitUntil(() => expect(member(again, 'sam')?.chip).toBe('Member'));
    row.state = 'invited';
    act(() => button('Make admin', member(again, 'sam')!.row).click());
    await waitUntil(() => expect(member(again, 'sam')?.hint).toBe('They have not joined yet.'));
  });

  it('makes an invite link, copies it as it is made, lists it with its terms, and turns it off', async () => {
    const copied: string[] = [];
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async (text: string) => void copied.push(text) } });
    const id = await ghost();
    const host = sheet(id);
    await waitUntil(() => expect(host.textContent).toContain('No links yet.'));
    act(() => buttonSaying(host, 'New link')!.click());
    // A day, for one person.
    act(() => host.querySelector<HTMLInputElement>('input[type="radio"][value="day"]')!.click());
    act(() => host.querySelector<HTMLInputElement>('input[type="radio"][value="one"]')!.click());
    await act(async () => buttonSaying(host, 'Make the link')!.click());
    await waitUntil(() => expect(host.querySelectorAll('[aria-label="Invite links"] li')).toHaveLength(1));
    const [link] = [...service.links.values()];
    expect(copied).toEqual([`https://ghostmarkdown.com/read.html#join=${link!.code}`]);
    expect(host.querySelector('[role="status"]')?.textContent).toBe('The link is made and copied. Anyone signed in who has it can join.');
    expect(host.querySelector('[aria-label="Invite links"] li')?.textContent).toContain('Stops in 24 hours · 0 of 1 used');
    expect(link!.maxUses).toBe(1);
    act(() => button('Turn the link off', host).click());
    await waitUntil(() => expect(host.textContent).toContain('No links yet.'));
    expect(service.links.size).toBe(0);
    expect(host.querySelector('[role="status"]')?.textContent).toBe('The link is turned off. No one else can join by it.');
  });

  it('draws no "Invite by link" section, heading and all, on a service from before invite links', async () => {
    const id = await ghost();
    // The live service before its deploy: the organization's routes answer, the links' are not there.
    vi.stubGlobal('fetch', (url: string, init?: RequestInit) => (String(url).includes('/links') ? Promise.resolve(new Response('', { status: 404 })) : service.fetcher(url, init)));
    const host = sheet(id);
    await waitUntil(() => expect(service.calls.length).toBeGreaterThan(0));
    await waitUntil(() => expect(host.textContent).not.toContain('Reading the links'));
    expect(host.textContent).not.toContain('Invite by link');
    expect(host.textContent).not.toContain('Anyone signed in who has the link');
  });

  it('shows no invite links to a member who does not manage the organization', async () => {
    const id = service.invited('Boo', 'sam');
    service.orgs.get(id)!.rows.get('matt')!.state = 'member';
    await syncOrgs({ token: service.signedIn(), fetcher: service.fetcher, save: (state) => saveOrgs(7, state) });
    const host = sheet(id);
    await waitUntil(() => expect(member(host, 'sam')).not.toBeNull());
    expect(host.textContent).not.toContain('Invite by link');
    expect(service.calls.some((c) => c.includes('/links'))).toBe(false);
  });

  it('draws an invitation with Accept and Decline when the account is only invited', async () => {
    const id = service.invited('Boo', 'sam');
    await syncOrgs({ token: service.signedIn(), fetcher: service.fetcher, save: (state) => saveOrgs(7, state) });
    const host = sheet(id);
    expect(headWord(host)).toBe('Boo');
    expect(host.querySelector('.setk-hero__meta')?.textContent).toBe('1 member · You are invited');
    expect(buttonSaying(host, 'Accept')).toBeDefined();
    expect(buttonSaying(host, 'Decline')).toBeDefined();
    expect(host.querySelector('input[aria-label="Handle"]')).toBeNull();
  });
});

describe('General', () => {
  it('renames and recolours for the owner, the workspace following', async () => {
    const id = await ghost();
    const host = sheet(id);
    await waitUntil(() => expect(member(host, 'matt')).not.toBeNull());
    act(() => {
      goBack();
    });
    act(() => rowFor(host, 'General').click());
    expect(display(host)).toBe('General');
    const field = host.querySelector<HTMLInputElement>('input[aria-label="Organization name"]')!;
    expect(field.value).toBe('Ghost');
    expect(buttonSaying(host, 'Rename')!.disabled).toBe(true);
    typeInto(field, 'Boo');
    await act(async () => buttonSaying(host, 'Rename')!.form!.requestSubmit());
    await waitUntil(() => expect(headWord(host)).toBe('Boo'));
    expect(workspaces().list).toEqual([{ id: `org-${id}`, name: 'Boo', hue: 'sea', org: id }]);
    act(() => button('Rose').click());
    await waitUntil(() => expect(workspaces().list[0]?.hue).toBe('rose'));
    expect(service.orgs.get(id)?.hue).toBe('rose');
  });

  it('only shows the name and the colour to a member', async () => {
    const id = service.invited('Boo', 'sam');
    service.orgs.get(id)!.rows.get('matt')!.state = 'member';
    await syncOrgs({ token: service.signedIn(), fetcher: service.fetcher, save: (state) => saveOrgs(7, state) });
    const host = sheet(id);
    await waitUntil(() => expect(member(host, 'sam')?.chip).toBe('Owner'));
    expect(host.querySelector('input[aria-label="Handle"]')).toBeNull();
    act(() => {
      goBack();
    });
    act(() => rowFor(host, 'General').click());
    expect(host.querySelector('input[aria-label="Organization name"]')).toBeNull();
    expect(host.querySelector('[role="radiogroup"]')).toBeNull();
    expect(host.textContent).toContain('Only the owner or an admin can rename it.');
  });
});

describe('the rest', () => {
  it('goes to the notes filed in its workspace, and mutes the organization', async () => {
    const onNotes = vi.fn();
    const id = await ghost();
    const host = sheet(id, { onNotes });
    act(() => {
      goBack();
    });
    act(() => rowFor(host, 'Workspace').click());
    expect(host.textContent).toContain('Notes filed here are the team’s');
    act(() => buttonSaying(host, 'Notes filed here')!.click());
    expect(onNotes).toHaveBeenCalledOnce();
    act(() => {
      goBack();
    });
    act(() => rowFor(host, 'Notifications').click());
    act(() => host.querySelector<HTMLInputElement>('[aria-label="Mute this organization"]')!.click());
    expect(preferences().notifications.mutedOrgs).toEqual([id]);
    act(() => host.querySelector<HTMLInputElement>('[aria-label="Mute this organization"]')!.click());
    expect(preferences().notifications.mutedOrgs).toEqual([]);
  });

  it('opens an email to the maker from Report, naming the organization and who reports', async () => {
    opened.length = 0;
    const id = await ghost();
    const host = sheet(id);
    act(() => {
      goBack();
    });
    act(() => rowFor(host, 'Report').click());
    expect(host.textContent).toContain('Team notes are sealed');
    act(() => buttonSaying(host, 'Report a member or a note')!.click());
    expect(opened).toHaveLength(1);
    const mail = new URL(opened[0]!);
    expect(mail.protocol).toBe('mailto:');
    expect(mail.pathname).toBe('infamousvaguerat@gmail.com');
    expect(mail.searchParams.get('subject')).toBe(`Ghost.md report: Ghost (${id})`);
    expect(mail.searchParams.get('body')).toContain('Reported by: matt');
  });

  it('deletes on a second tap, the workspace going with it, and closes', async () => {
    const onClose = vi.fn();
    const id = await ghost();
    const host = sheet(id, { onClose });
    act(() => {
      goBack();
    });
    act(() => rowFor(host, 'Delete').click());
    act(() => button('Delete').click());
    expect(button('Tap again')).toBeTruthy();
    expect(service.orgs.has(id)).toBe(true);
    await act(async () => button('Tap again').click());
    await waitUntil(() => expect(onClose).toHaveBeenCalledOnce());
    expect(service.orgs.has(id)).toBe(false);
    expect(workspaces().list).toEqual([]);
  });

  it('leaves on a second tap, for a member', async () => {
    const onClose = vi.fn();
    const id = service.invited('Boo', 'sam');
    service.orgs.get(id)!.rows.get('matt')!.state = 'member';
    await syncOrgs({ token: service.signedIn(), fetcher: service.fetcher, save: (state) => saveOrgs(7, state) });
    expect(workspaces().list.map((w) => w.id)).toEqual([`org-${id}`]);
    const host = sheet(id, { onClose });
    act(() => {
      goBack();
    });
    act(() => rowFor(host, 'Leave').click());
    act(() => button('Leave').click());
    await act(async () => button('Tap again').click());
    await waitUntil(() => expect(onClose).toHaveBeenCalledOnce());
    expect(service.rowIn(id)).toBeNull();
    expect(workspaces().list).toEqual([]);
  });
});
