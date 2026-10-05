import { fromBase64Url, toBase64Url, type Bytes } from '../sync/crypto.ts';

/**
 * The organization key wrapped for one member (docs/SHARED.md, S2, S3): ECIES over the account's encryption key pair.
 *
 * The pair is ECDH on P-256, which WebCrypto has on every engine the app runs on (X25519 is not yet everywhere). A wrap
 * makes an ephemeral P-256 pair, agrees a secret with the member's public key, draws an AES-256-GCM key from it with
 * HKDF-SHA-256, and seals the organization key under that, bound to `context` (`org-key:<org id>:<generation>`) so a
 * wrap made for one organization and generation opens in no other. The wrap is the ephemeral public key, the IV and
 * the ciphertext, base64url. Unwrapping agrees the same secret from the member's private key and the ephemeral
 * public key, and opens the seal.
 */

const CURVE = { name: 'ECDH', namedCurve: 'P-256' } as const;
const INFO = 'glyph/v1/org-key';
/** A P-256 public key, raw: the uncompressed point. */
const POINT_BYTES = 65;
const IV_BYTES = 12;
const encoder = new TextEncoder();

/** A fresh encryption key pair, extractable: its private half is exported once, to travel sealed to the account's other devices. */
export function newEncryptionKey(): Promise<CryptoKeyPair> {
  return crypto.subtle.generateKey(CURVE, true, ['deriveBits']) as Promise<CryptoKeyPair>;
}

/** A pair's public key as the service keeps it: the raw point, base64url. */
export async function publicKeyOf(pair: CryptoKeyPair): Promise<string> {
  return toBase64Url(new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey)));
}

/** The private half as JSON, to seal for the account's other devices. */
export function exportPrivateKey(pair: CryptoKeyPair): Promise<JsonWebKey> {
  return crypto.subtle.exportKey('jwk', pair.privateKey);
}

/**
 * A pair back from its private half, as another device of the account keeps it: non-extractable, with the public key
 * read from the same JSON.
 */
export async function importEncryptionKey(jwk: JsonWebKey): Promise<CryptoKeyPair> {
  const privateKey = await crypto.subtle.importKey('jwk', jwk, CURVE, false, ['deriveBits']);
  const { d: _d, ...publicJwk } = jwk;
  const publicKey = await crypto.subtle.importKey('jwk', { ...publicJwk, key_ops: [] }, CURVE, true, []);
  return { privateKey, publicKey };
}

/** The same pair, its private half no longer extractable: the form a device keeps. */
export async function settleEncryptionKey(pair: CryptoKeyPair): Promise<CryptoKeyPair> {
  if (!pair.privateKey.extractable) return pair;
  return importEncryptionKey(await exportPrivateKey(pair));
}

async function agreed(privateKey: CryptoKey, publicKey: CryptoKey, context: string): Promise<CryptoKey> {
  const secret = await crypto.subtle.deriveBits({ name: 'ECDH', public: publicKey }, privateKey, 256);
  const base = await crypto.subtle.importKey('raw', secret, 'HKDF', false, ['deriveKey']);
  return crypto.subtle.deriveKey({ name: 'HKDF', hash: 'SHA-256', salt: new Uint8Array(0), info: encoder.encode(`${INFO}:${context}`) }, base, { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}

/** `orgKey` wrapped for the member whose public key is `pub` (raw, base64url), bound to `context`. */
export async function wrapFor(pub: string, orgKey: Bytes, context: string): Promise<string> {
  const theirs = await crypto.subtle.importKey('raw', fromBase64Url(pub), CURVE, true, []);
  const ephemeral = await newEncryptionKey();
  const key = await agreed(ephemeral.privateKey, theirs, context);
  const iv = crypto.getRandomValues(new Uint8Array(IV_BYTES));
  const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: encoder.encode(context) }, key, orgKey));
  const point = new Uint8Array(await crypto.subtle.exportKey('raw', ephemeral.publicKey));
  const out = new Uint8Array(point.length + iv.length + sealed.length);
  out.set(point, 0);
  out.set(iv, point.length);
  out.set(sealed, point.length + iv.length);
  return toBase64Url(out);
}

/** The organization key out of `wrapped`, with this account's private key. Fails on another's wrap, or another context. */
export async function unwrapWith(pair: CryptoKeyPair, wrapped: string, context: string): Promise<Bytes> {
  const bytes = fromBase64Url(wrapped);
  if (bytes.length < POINT_BYTES + IV_BYTES + 17) throw new Error('That wrap could not be read.');
  const ephemeral = await crypto.subtle.importKey('raw', bytes.slice(0, POINT_BYTES), CURVE, true, []);
  const key = await agreed(pair.privateKey, ephemeral, context);
  const iv = bytes.slice(POINT_BYTES, POINT_BYTES + IV_BYTES);
  return new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv, additionalData: encoder.encode(context) }, key, bytes.slice(POINT_BYTES + IV_BYTES)));
}

/** The context a wrap is bound to. */
export const wrapContext = (orgId: string, generation: number): string => `org-key:${orgId}:${generation}`;
