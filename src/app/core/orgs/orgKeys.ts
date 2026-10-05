import { ApiError, call, notYet } from '../account/api.ts';
import { externalStore } from '../externalStore.ts';
import type { Bytes } from '../sync/crypto.ts';
import type { OrgRow } from './types.ts';
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
 */

interface Held {
  generation: number;
  raw: Bytes;
  key: CryptoKey;
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
  const entry = { generation, raw, key };
  held.set(orgId, entry);
  changes.update((n) => n + 1);
  return entry;
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
