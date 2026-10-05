import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { fakeService, type FakeService } from '../../../test/fakeService.ts';
import { ensureEncryptionKey } from './encKey.ts';
import { memoryKeys, type KeyStore } from './keystore.ts';
import { publicKeyOf, unwrapWith, wrapContext, wrapFor } from '../orgs/wrap.ts';
import { open } from '../sync/crypto.ts';

/**
 * The account's encryption key pair (core/account/encKey.ts; docs/SHARED.md, S3): kept on the device, else read from
 * the service and unsealed with the account key, else made here and registered - and when two devices race, the
 * service's choice stands on both.
 */

const ACCOUNT = { handle: 'matt', password: 'correct horse' };
let service: FakeService;
let accountKey: CryptoKey;

beforeEach(async () => {
  service = await fakeService(ACCOUNT);
  vi.stubGlobal('fetch', service.fetcher);
  accountKey = service.accountKey;
});

afterEach(() => {
  vi.unstubAllGlobals();
});

const ctx = (keys: KeyStore) => ({ token: service.signedIn(), accountKey, keys, fetcher: service.fetcher });

describe('the encryption key pair', () => {
  it('is made once, registered with the private half sealed, kept non-extractable, and read back by another device', async () => {
    const phone = memoryKeys();
    const made = await ensureEncryptionKey(ctx(phone));
    expect(made.pair.privateKey.extractable).toBe(false);
    expect(await phone.encryptionKey()).toBe(made.pair);
    expect(service.encryption?.pub).toBe(made.pub);
    // The private half travels sealed under the account key: the service holds ciphertext it cannot read.
    const jwk = await open<JsonWebKey>(accountKey, service.encryption!.sealed, 'encryption-key');
    expect(jwk.kty).toBe('EC');
    expect(service.encryption!.sealed).not.toContain(jwk.d!);
    // The same device again: the kept pair, and no call.
    const before = service.calls.length;
    expect((await ensureEncryptionKey(ctx(phone))).pair).toBe(made.pair);
    expect(service.calls.length).toBe(before);
    // Another device of the account: the pair from the service, able to open what was wrapped for the first.
    const mac = memoryKeys();
    const read = await ensureEncryptionKey(ctx(mac));
    expect(read.pub).toBe(made.pub);
    expect(read.pair.privateKey.extractable).toBe(false);
    const orgKey = crypto.getRandomValues(new Uint8Array(32));
    const wrapped = await wrapFor(made.pub, orgKey, wrapContext('org-1', 1));
    expect(await unwrapWith(read.pair, wrapped, wrapContext('org-1', 1))).toEqual(orgKey);
  });

  it('adopts the pair the service kept when another device registered first', async () => {
    // The other device's pair stands on the service before this one asks; this one made its own in between.
    const other = memoryKeys();
    const theirs = await ensureEncryptionKey(ctx(other));
    const racing = memoryKeys();
    const fetcher = service.fetcher;
    let adopted = false;
    // A fetch that answers the first GET with 404 (as it was when this device looked) and lets the PUT meet the 409.
    const raced: typeof fetch = async (input, init) => {
      const path = new URL(String(input)).pathname;
      if (!adopted && path.endsWith('/account/key') && (init?.method ?? 'GET') === 'GET') {
        adopted = true;
        return new Response(JSON.stringify({ error: 'No key pair yet.' }), { status: 404, headers: { 'Content-Type': 'application/json' } });
      }
      return fetcher(input, init);
    };
    const mine = await ensureEncryptionKey({ token: service.signedIn(), accountKey, keys: racing, fetcher: raced });
    expect(mine.pub).toBe(theirs.pub);
    expect(await publicKeyOf((await racing.encryptionKey())!)).toBe(theirs.pub);
  });
});
