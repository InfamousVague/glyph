/**
 * Signing for over-the-air updates, shared by deploy-ota.mjs and ota-keygen.mjs.
 *
 * WHY SIGN AT ALL. An installed Glyph used to trust whatever its update URL
 * served over HTTPS. That is only as durable as the domain: if attack.fm ever
 * lapsed and someone else registered it, every install would download and run
 * their "update" - a page with IPC access to the notes store and the
 * microphone. With a signature the domain stops mattering to trust: the app
 * accepts a manifest only if a key compiled into the APK signed it, so any
 * host can serve updates, a redirect cannot inject one, and a lost domain can
 * stop updates but cannot ship code. That is also what makes it safe for a
 * signed manifest to MOVE installs to a new domain (`sources`, see ota.rs).
 *
 * THE SCHEME. Ed25519 over the exact bytes of the published file, prefixed by
 * a context string so a signature for one kind of file can never be replayed
 * as another: `glyph-ota\0` + ota.json, `glyph-apk\0` + apk.json. The signature
 * sits beside the file, base64, as `ota.json.sig` / `apk.json.sig` - detached
 * so the JSON stays byte-for-byte what 0.2.0 apps already parse.
 *
 * THE KEYS. The private key never enters the repo: it lives at
 * ~/.config/glyph/ota-signing-key.pem (or $GLYPH_OTA_KEY) and has to be backed
 * up somewhere safe - without it no installed app will accept another update,
 * and the only way back is a new APK installed by hand. Public keys live in
 * src-tauri/ota-trusted-keys.txt, which the APK compiles in; more than one may
 * be listed, which is how a key is rotated (ship an APK trusting old and new,
 * then sign with the new one).
 */
import { createPrivateKey, createPublicKey, sign, verify } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { ROOT } from './lib/paths.mjs';

export const TRUSTED_KEYS_FILE = join(ROOT, 'src-tauri/ota-trusted-keys.txt');
export const SOURCES_FILE = join(ROOT, 'src-tauri/ota-sources.txt');
export const KEY_PATH = process.env.GLYPH_OTA_KEY || join(homedir(), '.config/glyph/ota-signing-key.pem');

export const CONTEXT = {
  manifest: 'glyph-ota\0',
  apk: 'glyph-apk\0',
};

/** Lines of a src-tauri list file, without comments or blanks. The Rust side parses the same way. */
export function readList(path) {
  return readFileSync(path, 'utf8')
    .split('\n')
    .map((line) => line.replace(/#.*/, '').trim())
    .filter(Boolean);
}

/** The raw 32-byte Ed25519 public key, base64 - the form ota-trusted-keys.txt holds. */
export function publicKeyBase64(key) {
  const publicKey = key.type === 'public' ? key : createPublicKey(key);
  const jwk = publicKey.export({ format: 'jwk' });
  return Buffer.from(jwk.x, 'base64url').toString('base64');
}

export function loadPrivateKey() {
  if (!existsSync(KEY_PATH)) return null;
  return createPrivateKey(readFileSync(KEY_PATH));
}

/** base64 signature over context + bytes. */
export function signBytes(privateKey, context, bytes) {
  return sign(null, Buffer.concat([Buffer.from(context, 'utf8'), bytes]), privateKey).toString('base64');
}

/** Whether any trusted key signed these bytes - the same check the app makes. */
export function verifyBytes(trustedKeys, context, bytes, signatureBase64) {
  const message = Buffer.concat([Buffer.from(context, 'utf8'), bytes]);
  const signature = Buffer.from(String(signatureBase64).trim(), 'base64');
  return trustedKeys.some((raw) => {
    const key = createPublicKey({
      key: { kty: 'OKP', crv: 'Ed25519', x: Buffer.from(raw, 'base64').toString('base64url') },
      format: 'jwk',
    });
    return verify(null, message, key, signature);
  });
}
