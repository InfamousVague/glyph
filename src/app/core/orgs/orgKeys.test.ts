import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { fakeService, type FakeService } from '../../../test/fakeService.ts';
import { ensureEncryptionKey } from '../account/encKey.ts';
import { memoryKeys } from '../account/keystore.ts';
import { createOrg, listOrgs } from './orgs.ts';
import { forgetOrgKeys, orgKeyGeneration, orgKeyOf, syncOrgKeys } from './orgKeys.ts';
import { newEncryptionKey, publicKeyOf, unwrapWith, wrapContext } from './wrap.ts';

/**
 * The organization key on a device (core/orgs/orgKeys.ts; docs/SHARED.md, S2): made by the first member device to
 * find none, wrapped for everyone who can be wrapped for, read by the others, filled for whoever joins, and settled
 * by the service when two devices make one at once.
 */

const ACCOUNT = { handle: 'matt', password: 'correct horse' };
let service: FakeService;

beforeEach(async () => {
  service = await fakeService(ACCOUNT, { peers: ['sam', 'lee'] });
  vi.stubGlobal('fetch', service.fetcher);
  forgetOrgKeys();
});

afterEach(() => {
  vi.unstubAllGlobals();
  forgetOrgKeys();
});

const call = () => ({ token: service.signedIn(), fetcher: service.fetcher });

describe('the organization key', () => {
  it('is made by the first member device, wrapped for itself, held, and skipped once the list says it is in hand', async () => {
    const keys = memoryKeys();
    const { pair } = await ensureEncryptionKey({ token: service.signedIn(), accountKey: service.accountKey, keys, fetcher: service.fetcher });
    const org = await createOrg('Ghost', 'sea', call());
    expect(orgKeyOf(org.id)).toBeNull();
    const raw = new Uint8Array(32).fill(7);
    let { rows } = await listOrgs(call());
    await syncOrgKeys({ ...call(), pair, list: rows, randomKey: () => raw });
    expect(orgKeyGeneration(org.id)).toBe(1);
    expect(orgKeyOf(org.id)).not.toBeNull();
    const stored = service.keysOf(org.id);
    expect(stored.generation).toBe(1);
    expect(await unwrapWith(pair, stored.wraps.matt![1]!, wrapContext(org.id, 1))).toEqual(raw);
    // The list now says it is in hand: the next pass asks nothing.
    ({ rows } = await listOrgs(call()));
    expect(rows[0]!.keys).toEqual({ generation: 1, mine: true, missing: 0 });
    const before = service.calls.length;
    await syncOrgKeys({ ...call(), pair, list: rows });
    expect(service.calls.length).toBe(before);
  });

  it('wraps for a member who joins with a public key, and reads its own wrap on another device', async () => {
    const keys = memoryKeys();
    const { pair } = await ensureEncryptionKey({ token: service.signedIn(), accountKey: service.accountKey, keys, fetcher: service.fetcher });
    const org = await createOrg('Ghost', null, call());
    const raw = new Uint8Array(32).fill(9);
    await syncOrgKeys({ ...call(), pair, list: (await listOrgs(call())).rows, randomKey: () => raw });
    // sam joins (through the service's own rows) with a key pair of their own: missing, then wrapped for.
    const sam = await newEncryptionKey();
    service.peerKey('sam', await publicKeyOf(sam));
    service.orgs.get(org.id)!.rows.set('sam', { handle: 'sam', role: 'member', state: 'member', since: Date.now(), invitedBy: 'matt' });
    const { rows } = await listOrgs(call());
    expect(rows[0]!.keys).toEqual({ generation: 1, mine: true, missing: 1 });
    await syncOrgKeys({ ...call(), pair, list: rows });
    const stored = service.keysOf(org.id);
    expect(await unwrapWith(sam, stored.wraps.sam![1]!, wrapContext(org.id, 1))).toEqual(raw);
    // Another device of matt's, with the pair but no key held: reads the wrap rather than making a new generation.
    forgetOrgKeys();
    await syncOrgKeys({ ...call(), pair, list: (await listOrgs(call())).rows, randomKey: () => new Uint8Array(32).fill(1) });
    expect(orgKeyGeneration(org.id)).toBe(1);
    expect(service.keysOf(org.id).generation).toBe(1);
  });

  it('adopts the generation another device made first, and waits when it has no wrap yet', async () => {
    const keys = memoryKeys();
    const { pair } = await ensureEncryptionKey({ token: service.signedIn(), accountKey: service.accountKey, keys, fetcher: service.fetcher });
    const org = await createOrg('Ghost', null, call());
    // sam's device made the first generation before this one posted: this one's post meets the generation in force.
    const sam = await newEncryptionKey();
    service.peerKey('sam', await publicKeyOf(sam));
    service.orgs.get(org.id)!.rows.set('sam', { handle: 'sam', role: 'admin', state: 'member', since: Date.now(), invitedBy: 'matt' });
    const fetcher = service.fetcher;
    let raced = false;
    const racing: typeof fetch = async (input, init) => {
      const path = new URL(String(input)).pathname;
      if (!raced && path.endsWith('/keys') && init?.method === 'POST') {
        // sam's post lands first, wrapping for sam alone.
        raced = true;
        const stored = service.orgs.get(org.id)!;
        stored.generation = 1;
        stored.wraps = new Map([['sam', new Map([[1, 'w-sam']])]]);
      }
      return fetcher(input, init);
    };
    await syncOrgKeys({ token: service.signedIn(), fetcher: racing, pair, list: (await listOrgs(call())).rows });
    // No wrap for matt yet: nothing held, nothing made; sam's generation stands untouched.
    expect(orgKeyOf(org.id)).toBeNull();
    expect(service.keysOf(org.id)).toEqual({ generation: 1, wraps: { sam: { 1: 'w-sam' } } });
    expect(orgKeyGeneration(org.id)).toBe(0);
    // sam's device wraps for matt; the next pass reads it.
    const raw = new Uint8Array(32).fill(3);
    const { wrapFor } = await import('./wrap.ts');
    service.orgs.get(org.id)!.wraps!.set('matt', new Map([[1, await wrapFor(await publicKeyOf(pair), raw, wrapContext(org.id, 1))]]));
    await syncOrgKeys({ ...call(), pair, list: (await listOrgs(call())).rows });
    expect(orgKeyGeneration(org.id)).toBe(1);
  });

  it('drops the key of an organization the account has left', async () => {
    const keys = memoryKeys();
    const { pair } = await ensureEncryptionKey({ token: service.signedIn(), accountKey: service.accountKey, keys, fetcher: service.fetcher });
    const org = await createOrg('Ghost', null, call());
    await syncOrgKeys({ ...call(), pair, list: (await listOrgs(call())).rows });
    expect(orgKeyOf(org.id)).not.toBeNull();
    await syncOrgKeys({ ...call(), pair, list: [] });
    expect(orgKeyOf(org.id)).toBeNull();
  });
});
