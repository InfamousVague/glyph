#!/usr/bin/env node
/**
 * Creates the Ed25519 key that signs Glyph's over-the-air updates, and adds its
 * public half to src-tauri/ota-trusted-keys.txt so the next APK trusts it.
 *
 * Run once per key, ever. It refuses to overwrite an existing private key:
 * replacing it would silently strand every installed app, which accepts only
 * manifests signed by a key it was built with. To ROTATE, run with
 * `--new-key-path <path>`, ship an APK that trusts both keys, and only then
 * point GLYPH_OTA_KEY at the new one.
 *
 * Back the private key up (a password manager takes the PEM as a note). See the
 * header of scripts/ota-sign.mjs for what losing it costs.
 */
import { generateKeyPairSync } from 'node:crypto';
import { appendFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { KEY_PATH, TRUSTED_KEYS_FILE, publicKeyBase64, readList } from './ota-sign.mjs';

const flag = process.argv.indexOf('--new-key-path');
const path = flag >= 0 ? process.argv[flag + 1] : KEY_PATH;
if (!path) {
  console.error('--new-key-path needs a path');
  process.exit(1);
}

if (existsSync(path)) {
  console.error(`A signing key already exists at ${path}. Not overwriting it: installed apps trust it.`);
  process.exit(1);
}

const { privateKey, publicKey } = generateKeyPairSync('ed25519');
mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
writeFileSync(path, privateKey.export({ format: 'pem', type: 'pkcs8' }), { mode: 0o600 });

const pub = publicKeyBase64(publicKey);
const known = existsSync(TRUSTED_KEYS_FILE) ? readList(TRUSTED_KEYS_FILE) : [];
if (!known.includes(pub)) {
  appendFileSync(TRUSTED_KEYS_FILE, `${pub}  # added ${new Date().toISOString().slice(0, 10)}\n`);
}

console.log(`private key  ${path}   (back this up; it never goes in the repo)`);
console.log(`public key   ${pub}`);
console.log(`trusted by   ${TRUSTED_KEYS_FILE} - the next APK built compiles it in`);
