import { useSyncExternalStore } from 'react';
import { accountState, onAccount } from '../account/account.ts';
import { ApiError, call, notYet } from '../account/api.ts';
import { externalStore } from '../externalStore.ts';
import { readStored, writeStored } from '../stored.ts';
import { dropOrgWorkspace, ensureOrgWorkspace, orgIdOf, workspaces } from '../workspaces.ts';
import type { Member, Org, OrgRow, OrgState, Role } from './types.ts';

/**
 * The account's organizations on this device (docs/TEAMS.md): the calls for every route, the list as the service
 * last gave it, kept per account so the Organizations page and the home card draw at once, and the step of the sync
 * pass that takes the list again and brings the workspaces into line with it.
 *
 * Matt: "We should be able to create an organization in order to add users as team members by handle ...
 * Organizations should also get their own workspace automatically". The workspace is reconciled against the list
 * after every pass that gets one (D5): made for each organization the person is a member of, renamed and re-hued
 * with it, dropped once they have left or it is gone - its notes unfiled, never deleted. Only a 200 list is acted on;
 * a list that did not arrive (offline, a service without the route yet, a 500) leaves the workspaces and the cached
 * list exactly as they were, because reading a failure as "no organizations" would unfile every member's notes and
 * push that to their other devices. The reconcile runs outside the pass's `applyingRemote` (core/sync/engine.ts), so
 * the preference change it makes is pushed a moment later rather than on the next pass.
 *
 * A call that changes one organization brings that one's row and workspace up to date here as well, so the screens
 * do not wait for the pass; the next pass makes it the service's truth.
 */

// --- what this device keeps -------------------------------------------------------------

function stateKey(accountId: number): string {
  return `glyph-sync-${accountId}-orgs`;
}

const NONE: OrgState = { list: [], at: null };

function isRole(value: unknown): value is Role {
  return value === 'owner' || value === 'admin' || value === 'member';
}

/** A row as kept, if it has the shape this build reads; null for one it does not. */
function asRow(raw: unknown): OrgRow | null {
  if (!raw || typeof raw !== 'object') return null;
  const r = raw as Partial<Record<keyof OrgRow, unknown>>;
  if (typeof r.id !== 'string' || typeof r.name !== 'string' || !isRole(r.role) || (r.state !== 'member' && r.state !== 'invited')) return null;
  return {
    id: r.id,
    name: r.name,
    hue: typeof r.hue === 'string' ? r.hue : null,
    role: r.role,
    state: r.state,
    members: typeof r.members === 'number' ? r.members : 0,
    invitedBy: typeof r.invitedBy === 'string' ? r.invitedBy : null,
    createdAt: typeof r.createdAt === 'number' ? r.createdAt : 0,
  };
}

function asState(raw: unknown): OrgState | null {
  if (!raw || typeof raw !== 'object') return null;
  const { list, at } = raw as { list?: unknown; at?: unknown };
  if (!Array.isArray(list)) return null;
  return { list: list.map(asRow).filter((row): row is OrgRow => row !== null), at: typeof at === 'number' ? at : null };
}

/** The list for one account, read from storage once and kept; `changes` counts every write so React follows it. */
let cache: { accountId: number; state: OrgState } | null = null;
const changes = externalStore(0);

function stateOf(accountId: number): OrgState {
  if (cache?.accountId !== accountId) cache = { accountId, state: readStored(stateKey(accountId), NONE, asState) };
  return cache.state;
}

/** Keeps the list for an account: on this device for the next launch, and for everything watching it now. */
export function saveOrgs(accountId: number, state: OrgState): void {
  cache = { accountId, state };
  writeStored(stateKey(accountId), state);
  changes.update((n) => n + 1);
}

/** Forgets the list this device kept of an account's organizations: for signing out (core/sync/engine.ts). */
export function forgetOrgs(accountId: number): void {
  if (cache?.accountId === accountId) cache = null;
  writeStored(stateKey(accountId), null);
  changes.update((n) => n + 1);
}

/** The organizations of the account signed in now, as the service last listed them; none signed out. */
export function orgsState(): OrgState {
  const session = accountState().session;
  return session ? stateOf(session.accountId) : NONE;
}

/** Called after every change to the list, and after the account changes; answers the way to stop. */
export function onOrgs(listener: () => void): () => void {
  const stopChanges = changes.subscribe(listener);
  const stopAccount = onAccount(listener);
  return () => {
    stopChanges();
    stopAccount();
  };
}

export function useOrgs(): OrgState {
  return useSyncExternalStore(onOrgs, orgsState, orgsState);
}

/** One organization's row from the kept list, or null. */
export function orgRow(id: string): OrgRow | null {
  return orgsState().list.find((row) => row.id === id) ?? null;
}

/** A row of the kept list as a full organization answers it: what a call that answered `{ org }` keeps here. */
function rowOf(org: Org): OrgRow {
  return { id: org.id, name: org.name, hue: org.hue, role: org.role, state: org.state, members: org.members.filter((m) => m.state === 'member').length, invitedBy: org.invitedBy ?? null, createdAt: org.createdAt };
}

/** The kept list with one row replaced, added, or (for null) taken out; nothing signed out. */
function keepRow(id: string, row: OrgRow | null): void {
  const session = accountState().session;
  if (!session) return;
  const was = stateOf(session.accountId);
  const list = was.list.filter((r) => r.id !== id);
  saveOrgs(session.accountId, { ...was, list: row ? [...list, row] : list });
}

// --- the calls -----------------------------------------------------------------------------

/** What a call needs of the session; the signed-in session by default, or a test's own. */
export interface CallContext {
  token: string;
  fetcher?: typeof fetch;
}

function signedIn(): CallContext {
  const session = accountState().session;
  if (!session) throw new ApiError(401, 'Sign in first.');
  return { token: session.token };
}

function orgs<T>(method: string, path: string, ctx: CallContext, body?: unknown): Promise<T> {
  return call<T>(method, path, { token: ctx.token, fetcher: ctx.fetcher, ...(body === undefined ? {} : { body }) });
}

/** A new organization, owned by the caller, with its workspace made here at once. */
export async function createOrg(name: string, hue: string | null = null, ctx: CallContext = signedIn()): Promise<Org> {
  const { org } = await orgs<{ org: Org }>('POST', 'orgs', ctx, { name: name.trim(), hue });
  keepRow(org.id, rowOf(org));
  ensureOrgWorkspace(org);
  return org;
}

/** Every organization the account is in or invited to. The kept list is not touched: that is the pass's (`syncOrgs`). */
export async function listOrgs(ctx: CallContext = signedIn()): Promise<OrgRow[]> {
  const { orgs: rows } = await orgs<{ orgs: OrgRow[] }>('GET', 'orgs', ctx);
  return rows;
}

/** One organization in full, for a member; 404 "No such organization." otherwise. */
export async function fetchOrg(id: string, ctx: CallContext = signedIn()): Promise<Org> {
  const { org } = await orgs<{ org: Org }>('GET', `orgs/${encodeURIComponent(id)}`, ctx);
  keepRow(org.id, rowOf(org));
  return org;
}

/** The organization renamed or re-hued (owner or admin); its workspace follows at once. */
export async function updateOrg(id: string, change: { name?: string; hue?: string | null }, ctx: CallContext = signedIn()): Promise<Org> {
  const body = { ...(change.name === undefined ? {} : { name: change.name.trim() }), ...(change.hue === undefined ? {} : { hue: change.hue }) };
  const { org } = await orgs<{ org: Org }>('PUT', `orgs/${encodeURIComponent(id)}`, ctx, body);
  keepRow(org.id, rowOf(org));
  ensureOrgWorkspace(org);
  return org;
}

/** The organization deleted (owner); its workspace goes here, its notes unfiled. */
export async function deleteOrg(id: string, ctx: CallContext = signedIn()): Promise<void> {
  await orgs<{ deleted: true }>('DELETE', `orgs/${encodeURIComponent(id)}`, ctx);
  keepRow(id, null);
  dropOrgWorkspace(id);
}

/**
 * Someone invited by handle (owner or admin). The service resolves the handle - 404 "No one has that handle." - and
 * says when they are already in, declined lately, have too many invitations waiting, or the organization is full.
 */
export async function inviteByHandle(id: string, handle: string, ctx: CallContext = signedIn()): Promise<Member> {
  const { member } = await orgs<{ member: Member }>('POST', `orgs/${encodeURIComponent(id)}/members`, ctx, { handle: handle.trim() });
  return member;
}

/**
 * A member or invitee taken out (owner or admin, with the owner the only one who can remove an admin), or the caller
 * leaving by their own handle: then the organization and its workspace go from this device.
 */
export async function removeMember(id: string, handle: string, ctx: CallContext = signedIn()): Promise<void> {
  await orgs<{ removed: true }>('DELETE', `orgs/${encodeURIComponent(id)}/members/${encodeURIComponent(handle.trim())}`, ctx);
  const session = accountState().session;
  if (session && session.handle.toLowerCase() === handle.trim().toLowerCase()) {
    keepRow(id, null);
    dropOrgWorkspace(id);
  }
}

/** A member's role set by the owner; `owner` hands the organization over, and the old owner becomes an admin. */
export async function setRole(id: string, handle: string, role: Role, ctx: CallContext = signedIn()): Promise<Member> {
  const { member } = await orgs<{ member: Member }>('PUT', `orgs/${encodeURIComponent(id)}/members/${encodeURIComponent(handle.trim())}`, ctx, { role });
  // Handing over: the caller is an admin now, which the kept row should say before the pass does.
  const row = orgRow(id);
  if (role === 'owner' && row) keepRow(id, { ...row, role: 'admin' });
  return member;
}

/**
 * The invitation answered on the wire: the organization, joined, or null for declined. 404 "You were not invited."
 * when there is no pending invitation - answered from another device already. The feed's `answerInvite`
 * (core/notifications/feed.ts) is what a screen calls: it applies the answer here at once and replays this.
 */
export async function postInviteAnswer(id: string, accept: boolean, ctx: CallContext = signedIn()): Promise<Org | null> {
  const answer = await orgs<{ org: Org } | { declined: true }>('POST', `orgs/${encodeURIComponent(id)}/invite`, ctx, { accept });
  if ('org' in answer) {
    keepRow(answer.org.id, rowOf(answer.org));
    ensureOrgWorkspace(answer.org);
    return answer.org;
  }
  keepRow(id, null);
  return null;
}

// --- the pass ------------------------------------------------------------------------------

export interface OrgsContext extends CallContext {
  /** Keeps the list that arrived: the account's store (`saveOrgs`), or a test's variable. */
  save(state: OrgState): void;
  /** The time, in ms: swapped in by the tests. */
  now?: () => number;
}

/**
 * The workspaces brought into line with a list the service answered: one for each organization the person is a
 * member of, named and coloured after it; an organization's workspace whose organization is not in the list goes,
 * its notes unfiled. An invitation is not a membership, and gets no workspace until it is accepted.
 */
export function reconcileOrgWorkspaces(list: readonly OrgRow[]): void {
  const members = list.filter((row) => row.state === 'member');
  for (const org of members) ensureOrgWorkspace(org);
  const wanted = new Set(members.map((org) => org.id));
  for (const workspace of workspaces().list) {
    const org = orgIdOf(workspace.id);
    if (org !== null && !wanted.has(org)) dropOrgWorkspace(org);
  }
}

/**
 * The step of the sync pass: the list taken again, kept, and the workspaces reconciled against it. Answers the list,
 * or null when the service does not have the route yet (core/account/api.ts `notYet`), which changes nothing here
 * and says nothing. Any other failure is thrown as it is, and changes nothing either.
 */
export async function syncOrgs(ctx: OrgsContext): Promise<OrgRow[] | null> {
  let list: OrgRow[];
  try {
    list = await listOrgs(ctx);
  } catch (failure) {
    if (notYet(failure)) return null;
    throw failure;
  }
  ctx.save({ list, at: (ctx.now ?? Date.now)() });
  reconcileOrgWorkspaces(list);
  return list;
}
