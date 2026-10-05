import { useEffect, useMemo } from 'react';
import { accountState } from '../account/account.ts';
import { externalStore } from '../externalStore.ts';
import { fetchOrg, useOrgs } from '../orgs/orgs.ts';
import { orgIdOf } from '../orgs/types.ts';
import { useWorkspaces, workspaceOf, WORKSPACE_HUES, type WorkspaceHue } from '../workspaces.ts';

/**
 * Whose colour a comment wears (docs/SHARED.md, S7, S8): in an organization's workspace, each member's colour there,
 * as the member rows carry it (`colour`, DESIGN §191) - the account's own from the kept list at once, the others' once
 * the organization has been read this session; anywhere else, and for anyone the rows do not name, the app's ink.
 *
 * The members are read with the organization (`fetchOrg`) the first time a note of it is open, and kept for the
 * session in memory: a colour is not a secret (S7), but nothing here needs it after the app closes, and the next
 * session reads it fresh. Read best effort: offline, the others are ink until it can be read.
 */

/** Each organization's members' colours, by handle, as read this session. */
const read = externalStore<ReadonlyMap<string, ReadonlyMap<string, string | null>>>(new Map());
/** The organizations asked for, so a note opened twice asks once. */
const asked = new Set<string>();

function remember(orgId: string, members: ReadonlyMap<string, string | null>): void {
  read.update((was) => new Map([...was, [orgId, members]]));
}

/** Reads an organization's members' colours, once a session; a failure is forgotten so the next note asks again. */
export function readMemberColours(orgId: string, fetch: typeof fetchOrg = fetchOrg): Promise<void> {
  if (asked.has(orgId) || !accountState().session) return Promise.resolve();
  asked.add(orgId);
  return fetch(orgId)
    .then((org) => remember(orgId, new Map(org.members.map((member) => [member.handle, member.colour ?? null]))))
    .catch(() => {
      asked.delete(orgId);
    });
}

/** For a test: nothing read. */
export function forgetMemberColours(): void {
  asked.clear();
  read.set(new Map());
}

/** A colour as a hue the stylesheets know, `ink` for none or one this build does not. */
const hueOf = (colour: string | null | undefined): WorkspaceHue => (WORKSPACE_HUES as readonly (string | null | undefined)[]).includes(colour) ? (colour as WorkspaceHue) : 'ink';

/** Who wears what in a note: a lookup by handle, and a key that changes when any answer would, to redraw by. */
export interface CommentColours {
  of: (handle: string) => WorkspaceHue;
  key: string;
}

/** The colours for the comments in `noteId`, followed as it is filed, the list changes and the members are read. */
export function useCommentColours(noteId: string): CommentColours {
  useWorkspaces();
  const orgs = useOrgs();
  const members = read.use();
  const orgId = (() => {
    const space = workspaceOf(noteId);
    return space ? orgIdOf(space.id) : null;
  })();
  useEffect(() => {
    if (orgId) void readMemberColours(orgId);
  }, [orgId]);
  const mine = orgId ? (orgs.list.find((row) => row.id === orgId)?.colour ?? null) : null;
  const handle = accountState().session?.handle ?? null;
  const theirs = orgId ? members.get(orgId) : undefined;
  return useMemo(() => {
    const of = (who: string): WorkspaceHue => {
      if (!orgId) return 'ink';
      // Your own from the kept list, which a change of your colour updates at once; the others' as the rows said.
      if (handle && who === handle && mine) return hueOf(mine);
      return hueOf(theirs?.get(who));
    };
    const key = orgId ? `${orgId}|${handle ?? ''}:${mine ?? ''}|${[...(theirs ?? new Map())].map(([who, hue]) => `${who}:${hue ?? ''}`).join(',')}` : '';
    return { of, key };
  }, [orgId, mine, handle, theirs]);
}
