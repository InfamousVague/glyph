import { ApiError, call, notYet } from '../account/api.ts';
import { externalStore } from '../externalStore.ts';
import type { Bytes } from '../sync/crypto.ts';
import type { Member, OrgRow } from './types.ts';
import { unwrapWith, wrapContext, wrapFor } from './wrap.ts';

/**
 * The organization key on this device (docs/SHARED.md, S2): fetched as this account's wrap and opened with its
 * encryption key pair, made here when the organization has none yet, and wrapped by this device for whichever members
 * the service says lack one. Held in memory for the session, by organization; `orgKeyOf` is what team notes seal
 * and open with (slice 2).
 *
 * The service arbitrates: a first generation posted when one already stands is answered 409 with the one in force,
 * and this device then reads its wrap instead. What the list already says (`OrgRow.keys`) spares the calls: an
 * organization whose generation this device holds, with nobody missing, is not asked about.
 *
 * The key turns when a member goes (S11): the list says `stale`, and the next member device holding the generation
 * in force makes the one after it (`turnOrgKey`), wrapped for everyone who remains, and re-seals the team's notes
 * under it (core/team/sync.ts `resealTeamNotes`, run by the engine). The generations before are kept for the
 * session and read from this account's older wraps on demand (`orgKeyAt`), for a row sealed before a turn that no
 * device has re-sealed yet.
 */

interface Held {
  generation: number;
  raw: Bytes;
  key: CryptoKey;
  /** Earlier generations, as read from this account's wraps at them; null for one it has no wrap at. */
  older: Map<number, CryptoKey | null>;
}

const held = new Map<string, Held>();
/** Counts every key held or forgotten, for whatever waits on one (core/live/presence.ts). */
const changes = externalStore(0);

/** Called after a key is held or the keys are forgotten; answers the way to stop. */
export const onOrgKeys = changes.subscribe;

/** The organization key as a key for sealing, if this device holds it. */
export function orgKeyOf(orgId: string): CryptoKey | null {
  return held.get(orgId)?.key ?? null;
}

/** The generation this device holds for an organization: 0 for none. */
export function orgKeyGeneration(orgId: string): number {
  return held.get(orgId)?.generation ?? 0;
}

/** Forgotten, on signing out. */
export function forgetOrgKeys(): void {
  held.clear();
  changes.update((n) => n + 1);
}

interface Keys {
  generation: number;
  mine: string | null;
  missing: { handle: string; pub: string }[];
  stale?: boolean;
}

export interface OrgKeysContext {
  token: string;
  fetcher?: typeof fetch;
  /** This account's encryption key pair and its public key, as the service keeps it. */
  pair: CryptoKeyPair;
  /** The organizations as the list last said them: which need a look. */
  list: readonly OrgRow[];
  /** For tests: the key's bytes, instead of random ones. */
  randomKey?: () => Bytes;
}

async function hold(orgId: string, generation: number, raw: Bytes): Promise<Held> {
  const key = await crypto.subtle.importKey('raw', raw, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
  const was = held.get(orgId);
  const older = new Map(was?.older ?? []);
  if (was && was.generation !== generation) older.set(was.generation, was.key);
  const entry = { generation, raw, key, older };
  held.set(orgId, entry);
  changes.update((n) => n + 1);
  return entry;
}

/**
 * The key at an older generation (S11): held from before a turn, or read now from this account's wrap at it; null
 * where the account has none - a member who joined after that generation, who could never read what was sealed under it.
 */
export async function orgKeyAt(ctx: Pick<OrgKeysContext, 'token' | 'fetcher' | 'pair'>, orgId: string, generation: number): Promise<CryptoKey | null> {
  const have = held.get(orgId);
  if (!have || generation < 1 || generation >= have.generation) return have?.generation === generation ? have.key : null;
  if (have.older.has(generation)) return have.older.get(generation) ?? null;
  let key: CryptoKey | null = null;
  try {
    const keys = await call<Keys>('GET', `orgs/${encodeURIComponent(orgId)}/keys?generation=${generation}`, { token: ctx.token, fetcher: ctx.fetcher });
    if (keys.mine) key = await crypto.subtle.importKey('raw', await unwrapWith(ctx.pair, keys.mine, wrapContext(orgId, generation)), { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
  } catch {
    // Not readable now: asked again next time.
    return null;
  }
  have.older.set(generation, key);
  return key;
}

/**
 * Whether an organization's key wants seeing to by this device now, from what the list says: none made yet, not in
 * hand here (a wrap to read, or this account's key pair still to register so that one can be made), or a member this
 * device, holding the key, could wrap for.
 */
export function keyWork(row: OrgRow, held: boolean): boolean {
  if (row.state !== 'member' || !row.keys) return false;
  // Not held is always work: a wrap to read, or - none yet - this account's key pair to register so one can be made.
  return row.keys.generation === 0 || !held || row.keys.missing > 0;
}

/** Whether the key owes a turn this device can make: the list says so, and this device holds the generation in force. */
export function turnDue(row: OrgRow): boolean {
  const have = held.get(row.id);
  return Boolean(row.keys?.stale && have && have.generation === row.keys.generation);
}

/**
 * The next generation, made here and wrapped for every member who remains and has a public key, brought into force
 * and held; the one before stays for the session, for what is not yet re-sealed. Null when another member's device
 * made it first (its wrap is read on the next pass) or when nobody could be wrapped for.
 */
export async function turnOrgKey(ctx: Pick<OrgKeysContext, 'token' | 'fetcher' | 'randomKey'>, orgId: string, members: readonly Pick<Member, 'handle' | 'state' | 'pub'>[]): Promise<{ generation: number } | null> {
  const have = held.get(orgId);
  if (!have) return null;
  const generation = have.generation + 1;
  const raw = (ctx.randomKey ?? (() => crypto.getRandomValues(new Uint8Array(32))))();
  const wraps = await Promise.all(members.filter((member) => member.state === 'member' && member.pub).map(async (member) => ({ handle: member.handle, wrapped: await wrapFor(member.pub!, raw, wrapContext(orgId, generation)) })));
  if (!wraps.length) return null;
  try {
    await call<Keys>('POST', `orgs/${encodeURIComponent(orgId)}/keys`, { token: ctx.token, fetcher: ctx.fetcher, body: { generation, make: true, wraps } });
  } catch (failure) {
    if (failure instanceof ApiError && failure.status === 409) return null;
    throw failure;
  }
  await hold(orgId, generation, raw);
  return { generation };
}

async function wraps(orgId: string, generation: number, raw: Bytes, missing: Keys['missing']): Promise<{ handle: string; wrapped: string }[]> {
  return Promise.all(missing.map(async ({ handle, pub }) => ({ handle, wrapped: await wrapFor(pub, raw, wrapContext(orgId, generation)) })));
}

/** One organization's key seen to: read, made, or filled for the missing. */
async function settle(ctx: OrgKeysContext, orgId: string): Promise<void> {
  const options = { token: ctx.token, fetcher: ctx.fetcher };
  const path = `orgs/${encodeURIComponent(orgId)}/keys`;
  let keys = await call<Keys>('GET', path, options);
  if (keys.generation === 0) {
    // Nothing made yet: this device makes the first generation and wraps it for everyone who can be wrapped for.
    const raw = (ctx.randomKey ?? (() => crypto.getRandomValues(new Uint8Array(32))))();
    try {
      keys = await call<Keys>('POST', path, { ...options, body: { generation: 1, make: true, wraps: await wraps(orgId, 1, raw, keys.missing) } });
      await hold(orgId, 1, raw);
      return;
    } catch (failure) {
      // Another member's device made one first: that one stands, and this device's wrap is read below.
      if (!(failure instanceof ApiError && failure.status === 409)) throw failure;
      keys = await call<Keys>('GET', path, options);
    }
  }
  const have = held.get(orgId);
  let entry = have && have.generation === keys.generation ? have : null;
  if (!entry) {
    // No wrap for this account yet: another member's device will make one on its next pass, and this one reads it then.
    if (keys.mine === null) return;
    entry = await hold(orgId, keys.generation, await unwrapWith(ctx.pair, keys.mine, wrapContext(orgId, keys.generation)));
  }
  if (keys.missing.length) {
    await call<Keys>('POST', path, { ...options, body: { generation: keys.generation, wraps: await wraps(orgId, keys.generation, entry.raw, keys.missing) } });
  }
}

/**
 * The step of the sync pass: every organization the account is a member of seen to, those the list says are in hand
 * skipped. An organization that fails is left for the next pass; a service without the routes yet stops the step.
 */
export async function syncOrgKeys(ctx: OrgKeysContext): Promise<void> {
  for (const row of ctx.list) {
    if (row.state !== 'member') continue;
    const have = held.get(row.id);
    const needs = row.keys ?? { generation: 0, mine: false, missing: 0 };
    if (have && have.generation === needs.generation && needs.missing === 0) continue;
    try {
      await settle(ctx, row.id);
    } catch (failure) {
      if (notYet(failure)) return;
    }
  }
  // Organizations the account has left take their keys with them.
  const members = new Set(ctx.list.filter((row) => row.state === 'member').map((row) => row.id));
  for (const orgId of [...held.keys()]) if (!members.has(orgId)) held.delete(orgId);
}
