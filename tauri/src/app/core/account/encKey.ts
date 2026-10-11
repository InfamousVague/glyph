import { exportPrivateKey, importEncryptionKey, newEncryptionKey, publicKeyOf, settleEncryptionKey } from '../orgs/wrap.ts';
import { open, seal } from '../sync/crypto.ts';
import { ApiError, call } from './api.ts';
import type { KeyStore } from './keystore.ts';

/**
 * The account's encryption key pair (docs/SHARED.md, S3), on this device: read from the keystore; else from the
 * service, where the account's other device left it sealed under the account key; else made here and registered.
 * Two devices making one at once are settled by the service, which keeps the first and answers the second 409 with
 * it, so the second throws its own away and adopts the one that stands. The pair is kept non-extractable, as the
 * account key is.
 */

/** The private half is sealed under the account key with this as its context. */
const CONTEXT = 'encryption-key';

export interface EncryptionKeyContext {
  token: string;
  accountKey: CryptoKey;
  keys: KeyStore;
  fetcher?: typeof fetch;
}

interface Registered {
  pub: string;
  sealed: string;
}

/** This device's copy of the account's pair, with its public key as the service keeps it. */
export interface EncryptionKey {
  pair: CryptoKeyPair;
  pub: string;
}

async function adopt(ctx: EncryptionKeyContext, registered: Registered): Promise<EncryptionKey> {
  const jwk = await open<JsonWebKey>(ctx.accountKey, registered.sealed, CONTEXT);
  const pair = await importEncryptionKey(jwk);
  await ctx.keys.setEncryptionKey(pair);
  return { pair, pub: registered.pub };
}

/** The pair, from wherever it is: this device, the service, or made now. */
export async function ensureEncryptionKey(ctx: EncryptionKeyContext): Promise<EncryptionKey> {
  const kept = await ctx.keys.encryptionKey();
  if (kept) return { pair: kept, pub: await publicKeyOf(kept) };
  const options = { token: ctx.token, fetcher: ctx.fetcher };
  try {
    return await adopt(ctx, await call<Registered>('GET', 'account/key', options));
  } catch (failure) {
    if (!(failure instanceof ApiError) || failure.status !== 404) throw failure;
  }
  // None registered: this device makes one, and registers it with the private half sealed for the account's others.
  const made = await newEncryptionKey();
  const pub = await publicKeyOf(made);
  const sealed = await seal(ctx.accountKey, await exportPrivateKey(made), CONTEXT);
  try {
    await call<Registered>('PUT', 'account/key', { ...options, body: { pub, sealed } });
  } catch (failure) {
    // Another device registered first: its pair stands, and this one is forgotten.
    if (failure instanceof ApiError && failure.status === 409 && isRegistered(failure.body)) return adopt(ctx, failure.body);
    throw failure;
  }
  const pair = await settleEncryptionKey(made);
  await ctx.keys.setEncryptionKey(pair);
  return { pair, pub };
}

function isRegistered(body: unknown): body is Registered {
  return !!body && typeof body === 'object' && typeof (body as Registered).pub === 'string' && typeof (body as Registered).sealed === 'string';
}
