import { describe, expect, it } from 'vitest';
import { exportPrivateKey, importEncryptionKey, newEncryptionKey, publicKeyOf, settleEncryptionKey, unwrapWith, wrapContext, wrapFor } from './wrap.ts';

/** The organization key wrapped for a member and back (core/orgs/wrap.ts): ECIES over P-256. */
describe('wrapping the organization key', () => {
  it('wraps for a public key and unwraps with its private half, bound to the context', async () => {
    const sam = await newEncryptionKey();
    const orgKey = crypto.getRandomValues(new Uint8Array(32));
    const wrapped = await wrapFor(await publicKeyOf(sam), orgKey, wrapContext('org-1', 1));
    expect(await unwrapWith(sam, wrapped, wrapContext('org-1', 1))).toEqual(orgKey);
    // Another member's key, another organization, another generation: none of them opens it.
    const lee = await newEncryptionKey();
    await expect(unwrapWith(lee, wrapped, wrapContext('org-1', 1))).rejects.toThrow();
    await expect(unwrapWith(sam, wrapped, wrapContext('org-2', 1))).rejects.toThrow();
    await expect(unwrapWith(sam, wrapped, wrapContext('org-1', 2))).rejects.toThrow();
    await expect(unwrapWith(sam, 'AAAA', wrapContext('org-1', 1))).rejects.toThrow('That wrap could not be read.');
    // Every wrap is fresh: the same key for the same member twice is two different wraps.
    expect(await wrapFor(await publicKeyOf(sam), orgKey, wrapContext('org-1', 1))).not.toBe(wrapped);
  });

  it('travels to another device as its private half, and is kept there non-extractable', async () => {
    const made = await newEncryptionKey();
    const orgKey = crypto.getRandomValues(new Uint8Array(32));
    const wrapped = await wrapFor(await publicKeyOf(made), orgKey, wrapContext('org-1', 1));
    const elsewhere = await importEncryptionKey(await exportPrivateKey(made));
    expect(elsewhere.privateKey.extractable).toBe(false);
    expect(await publicKeyOf(elsewhere)).toBe(await publicKeyOf(made));
    expect(await unwrapWith(elsewhere, wrapped, wrapContext('org-1', 1))).toEqual(orgKey);
    const settled = await settleEncryptionKey(made);
    expect(settled.privateKey.extractable).toBe(false);
    expect(await settleEncryptionKey(settled)).toBe(settled);
  });
});
