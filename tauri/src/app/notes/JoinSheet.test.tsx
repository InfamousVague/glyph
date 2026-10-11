import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { fakeService, type FakeService } from '../../test/fakeService.ts';
import type { Session } from '../core/account/keystore.ts';
import { buttonSaying, rerender, show, unmount, waitUntil } from '../../test/render.tsx';
import { stubResizeObserver } from '../../test/stubs.ts';

await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
stubResizeObserver();

// Signed in as matt against the service in memory, or signed out; `useAccount` is read afresh on every render.
let session: Session | null = null;
vi.mock('../core/account/account.ts', () => ({
  accountState: () => ({ session, unlocked: session !== null }),
  useAccount: () => ({ session, unlocked: session !== null }),
  accountKey: async () => null,
  onAccount: () => () => undefined,
  resume: async () => undefined,
}));

const { JoinInvites } = await import('./JoinSheet.tsx');
const { forgetOrgs, orgsState } = await import('../core/orgs/orgs.ts');
const { heldJoin } = await import('../core/orgs/joinLinks.ts');
const { reloadWorkspaces, workspaces } = await import('../core/workspaces.ts');

/**
 * "Join it?" for an invite link (docs/TEAMS.md), against the service in memory: the organization's name before
 * anything is joined, Join making the row and the workspace here, Not now, a link that stopped, one for an
 * organization already joined, and a link followed signed out that waits for an account.
 */

let service: FakeService;
const sheet = () => document.querySelector<HTMLElement>('[role="dialog"]');
const title = () => sheet()?.querySelector('p')?.textContent ?? null;

function host(request: { code: string; nonce: number } | null, over: { onOpen?: (id: string) => void; onAccount?: () => void; hold?: boolean } = {}) {
  return <JoinInvites request={request} hold={over.hold ?? false} onOpen={over.onOpen ?? (() => undefined)} onAccount={over.onAccount ?? (() => undefined)} />;
}

beforeEach(async () => {
  localStorage.clear();
  reloadWorkspaces();
  service = await fakeService({ handle: 'matt', password: 'correct horse' });
  vi.stubGlobal('fetch', service.fetcher);
  session = { token: service.signedIn(), handle: 'matt', accountId: 7 };
  forgetOrgs(7);
});

afterEach(() => {
  unmount();
  vi.unstubAllGlobals();
  forgetOrgs(7);
});

describe('an invite link', () => {
  it('names the organization and who sent it, and joins only on Join, opening it', async () => {
    const code = service.peerLink('Ghost', 'sam');
    const onOpen = vi.fn();
    show(host({ code, nonce: 1 }, { onOpen }));
    await waitUntil(() => expect(title()).toBe('Join Ghost?'));
    expect(sheet()?.textContent).toContain('sam shared this invite link. 1 member so far.');
    const orgId = [...service.orgs.keys()][0]!;
    expect(service.rowIn(orgId)).toBeNull();
    await act(async () => buttonSaying(sheet()!, 'Join Ghost')!.click());
    await waitUntil(() => expect(onOpen).toHaveBeenCalledWith(orgId));
    expect(service.rowIn(orgId)).toEqual({ role: 'member', state: 'member' });
    expect(orgsState().list.map((row) => [row.name, row.state])).toEqual([['Ghost', 'member']]);
    expect(workspaces().list.map((w) => w.name)).toContain('Ghost');
    expect(sheet()).toBeNull();
    expect(heldJoin()).toBeNull();
  });

  it('is let go on Not now, with nothing joined', async () => {
    const code = service.peerLink('Ghost', 'sam');
    show(host({ code, nonce: 1 }));
    await waitUntil(() => expect(title()).toBe('Join Ghost?'));
    act(() => buttonSaying(sheet()!, 'Not now')!.click());
    expect(sheet()).toBeNull();
    expect(heldJoin()).toBeNull();
    expect(service.rowIn([...service.orgs.keys()][0]!)).toBeNull();
  });

  it('that stopped working says so in the service’s words', async () => {
    const code = service.peerLink('Ghost', 'sam', { expiresAt: Date.now() - 1 });
    show(host({ code, nonce: 1 }));
    await waitUntil(() => expect(title()).toBe('This invite link doesn’t work'));
    expect(sheet()?.textContent).toContain('That invite link has expired or was turned off.');
  });

  it('for an organization already joined offers to open it', async () => {
    const code = service.peerLink('Ghost', 'sam');
    const orgId = [...service.orgs.keys()][0]!;
    service.orgs.get(orgId)!.rows.set('matt', { handle: 'matt', role: 'member', state: 'member', since: 1, invitedBy: 'sam' });
    const onOpen = vi.fn();
    show(host({ code, nonce: 1 }, { onOpen }));
    await waitUntil(() => expect(title()).toBe('You’re in Ghost'));
    act(() => buttonSaying(sheet()!, 'Open Ghost')!.click());
    expect(onOpen).toHaveBeenCalledWith(orgId);
  });

  it('followed signed out waits on this device, and is asked about once an account is signed in', async () => {
    const code = service.peerLink('Ghost', 'sam');
    session = null;
    const onAccount = vi.fn();
    show(host({ code, nonce: 1 }, { onAccount }));
    expect(title()).toBe('Join a team');
    act(() => buttonSaying(sheet()!, 'Sign in or sign up')!.click());
    expect(onAccount).toHaveBeenCalled();
    expect(sheet()).toBeNull();
    expect(heldJoin()).toBe(code);
    session = { token: service.signedIn(), handle: 'matt', accountId: 7 };
    rerender(host({ code, nonce: 1 }, { onAccount }));
    await waitUntil(() => expect(title()).toBe('Join Ghost?'));
  });

  it('waits while the way into an account is up', async () => {
    const code = service.peerLink('Ghost', 'sam');
    show(host({ code, nonce: 1 }, { hold: true }));
    expect(sheet()).toBeNull();
    rerender(host({ code, nonce: 1 }, { hold: false }));
    await waitUntil(() => expect(title()).toBe('Join Ghost?'));
  });
});
