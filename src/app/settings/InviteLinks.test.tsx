import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { NO_SUCH_ROUTE } from '../core/account/api.ts';
import type { Session } from '../core/account/keystore.ts';
import { show, unmount } from '../../test/render.tsx';
import { stubResizeObserver } from '../../test/stubs.ts';

await vi.hoisted(async () => (await import('../../test/stubs.ts')).stubMatchMedia());
stubResizeObserver();

const session: Session = { token: 'tok', handle: 'matt', accountId: 7 };
vi.mock('../core/account/account.ts', () => ({
  accountState: () => ({ session, unlocked: true }),
  useAccount: () => ({ session, unlocked: true }),
  onAccount: () => () => undefined,
}));

const { InviteLinks } = await import('./InviteLinks.tsx');

/**
 * The invite links' panel against a service from before them (docs/TEAMS.md "Two kinds of 404"): the page can reach
 * one first, and draws nothing rather than the refusal. Making, copying and turning off are in
 * OrganizationSheet.test.tsx, against the service in memory.
 */

afterEach(() => {
  unmount();
  vi.unstubAllGlobals();
});

describe('invite links on an older service', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', async () => new Response(JSON.stringify({ error: NO_SUCH_ROUTE }), { status: 404, headers: { 'Content-Type': 'application/json' } }));
  });

  it('draw nothing', async () => {
    const host = show(<InviteLinks orgId="GhostOrg00000000000001" />);
    await act(async () => new Promise((r) => setTimeout(r, 20)));
    expect(host.innerHTML).toBe('');
  });
});
