import { act } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { show } from '../../../test/render.tsx';
import type { Session } from '../account/keystore.ts';
import { saveOrgs } from '../orgs/orgs.ts';
import type { Org, OrgRow } from '../orgs/types.ts';
import { ensureOrgWorkspace, fileNote, reloadWorkspaces } from '../workspaces.ts';
import { forgetMemberColours, readMemberColours, useCommentColours, type CommentColours } from './colours.ts';

/**
 * Whose colour a comment wears (core/comments/colours.ts; docs/SHARED.md, S7): ink outside an organization, and in
 * one your colour from the kept list at once and each other member's once the organization has been read, read once a
 * session and asked again after a failure.
 */

const SESSION: Session = { token: 't1', handle: 'matt', accountId: 7 };
let session: Session | null = null;
vi.mock('../account/account.ts', () => ({
  accountState: () => ({ session, unlocked: session !== null }),
  accountKey: async () => null,
  onAccount: () => () => undefined,
}));

const fetched = vi.hoisted(() => ({ org: null as unknown }));
vi.mock('../orgs/orgs.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../orgs/orgs.ts')>()),
  fetchOrg: async () => {
    if (!fetched.org) throw new Error('offline');
    return fetched.org;
  },
}));

const ORG = { id: 'o1', members: [{ handle: 'sam', colour: 'sea' }, { handle: 'matt', colour: 'moss' }, { handle: 'kit', colour: 'tartan' }] } as unknown as Org;
const ROW = { id: 'o1', name: 'Barn', hue: null, role: 'member', state: 'member', members: 3, createdAt: 0, colour: 'amber' } as OrgRow;

beforeEach(() => {
  localStorage.clear();
  session = { ...SESSION };
  reloadWorkspaces();
  fetched.org = ORG;
});

afterEach(() => forgetMemberColours());

/** The colours the hook answers for `noteId`, as a component drawn with it sees them. */
function colours(noteId: string): { now: CommentColours } {
  const seen = { now: null as unknown as CommentColours };
  function Probe() {
    seen.now = useCommentColours(noteId);
    return null;
  }
  show(<Probe />);
  return seen;
}

describe('the colours comments wear', () => {
  it('are ink outside an organization', () => {
    const seen = colours('n1');
    expect(seen.now.of('sam')).toBe('ink');
    expect(seen.now.key).toBe('');
  });

  it('are yours from the kept list, and each member’s once the organization is read, ink for a hue not known', async () => {
    saveOrgs(7, { list: [ROW], at: 1, colour: null });
    ensureOrgWorkspace({ id: 'o1', name: 'Barn' });
    fileNote('n1', 'org-o1');
    const seen = colours('n1');
    // Yours from the list, which a change of colour updates at once: amber, not the moss the rows were read with.
    expect(seen.now.of('matt')).toBe('amber');
    await act(async () => {
      await Promise.resolve();
    });
    expect(seen.now.of('sam')).toBe('sea');
    expect(seen.now.of('kit')).toBe('ink');
    expect(seen.now.of('nobody')).toBe('ink');
    expect(seen.now.key).toContain('sam:sea');
  });

  it('reads an organization once a session, asks again after a failure, and asks nothing signed out', async () => {
    const fetch = vi.fn().mockRejectedValueOnce(new Error('offline')).mockResolvedValue(ORG);
    await readMemberColours('o2', fetch);
    await readMemberColours('o2', fetch);
    await readMemberColours('o2', fetch);
    expect(fetch).toHaveBeenCalledTimes(2);
    session = null;
    await readMemberColours('o3', fetch);
    expect(fetch).toHaveBeenCalledTimes(2);
  });
});
