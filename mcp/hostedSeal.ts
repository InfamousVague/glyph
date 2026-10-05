import { createCipheriv, createDecipheriv, hkdfSync, randomBytes } from 'node:crypto';

/**
 * How the hosted server's sessions are sealed for the disk (mcp/hostedStore.ts, docs/MCP.md "What the hosted server
 * keeps"), so that a restart does not sign everyone out and the file by itself opens nothing.
 *
 * Each session has a seal key of its own, 32 random bytes, which seals the account key and the sync token. The seal
 * key is never written: what is written is the seal key wrapped once under each token that names the session, with a
 * key derived from that token. And the tokens are not written either - the file names each by an id derived from it,
 * one way - so the only thing that opens a session is a token Claude holds, presented.
 *
 *   id        HKDF-SHA256(token, "id")      what the file calls the token
 *   wrap key  HKDF-SHA256(token, "wrap")    what wraps the session's seal key for that token
 *   sealing   AES-256-GCM, a fresh 12-byte nonce each time, bound to what it is (`aad`): nonce | tag | sealed, base64url
 *
 * A token is 32 random bytes (hostedStore.ts newToken), so HKDF is enough: there is no password here to stretch.
 * Node's own crypto, synchronous, so the store stays as plain as it was.
 */

const SALT = 'glyph-mcp/v1';
const NONCE = 12;
const TAG = 16;

const derive = (token: string, info: string) => Buffer.from(hkdfSync('sha256', token, SALT, info, 32));

/** What the file calls a token: derived one way, so the file cannot be used as one. */
export const tokenId = (token: string) => derive(token, 'id').toString('base64url');

/** A session's seal key, new. */
export const newSealKey = () => randomBytes(32);

/** `plain` sealed under `key`, bound to `aad`: what it is and whose. */
export function seal(key: Buffer, plain: Buffer | string, aad: string): string {
  const nonce = randomBytes(NONCE);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(Buffer.from(aad));
  const sealed = Buffer.concat([cipher.update(plain), cipher.final()]);
  return Buffer.concat([nonce, cipher.getAuthTag(), sealed]).toString('base64url');
}

/** What `seal` sealed. Throws for another key, another `aad`, or a byte changed. */
export function open(key: Buffer, sealed: string, aad: string): Buffer {
  const bytes = Buffer.from(sealed, 'base64url');
  const decipher = createDecipheriv('aes-256-gcm', key, bytes.subarray(0, NONCE));
  decipher.setAAD(Buffer.from(aad));
  decipher.setAuthTag(bytes.subarray(NONCE, NONCE + TAG));
  return Buffer.concat([decipher.update(bytes.subarray(NONCE + TAG)), decipher.final()]);
}

/** A session's seal key wrapped for one token. */
export const wrapFor = (token: string, sealKey: Buffer, aad: string) => seal(derive(token, 'wrap'), sealKey, aad);

/** The seal key a token's wrap holds. Throws for any other token. */
export const unwrapWith = (token: string, wrap: string, aad: string) => open(derive(token, 'wrap'), wrap, aad);
