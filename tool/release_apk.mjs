#!/usr/bin/env node
// What a release of the app that replaces Ghost.md's Tauri app is made of, written and signed and NOT uploaded
// (docs/CUTOVER.md says where it goes, in which order, and who does it).
//
//   node tool/release_apk.mjs build/app/outputs/flutter-apk/app-release.apk [--out build/cutover] [--native 28]
//
// Into --out:
//
//   glyph.apk              the APK, under the name every Ghost.md install and the download page fetch
//   apk.json               { version, versionCode, native, sha256, bytes, url: "glyph.apk", build }
//   apk.json.sig           Ed25519 over "glyph-apk\0" + apk.json: what an installed TAURI app verifies, and so
//                          offers this APK as its next version (../glyph/src-tauri/src/ota/apk.rs, core/ota.ts)
//   apk.json.flutter.sig   Ed25519 over "ghost-flutter-apk\0" + apk.json: what THIS app verifies from then on
//                          (native/src/kept/updates.rs, lib/core/updates.dart)
//
// One key signs both: Ghost.md's update key, ~/.config/glyph/ota-signing-key.pem (or --key), whose public half is
// the one line of ../glyph/src-tauri/ota-trusted-keys.txt and of lib/core/update_keys.dart. This script reads it,
// signs, and prints nothing of it.
//
// `native` is the Tauri app's "native generation". Its installs are offered an APK whose version is newer than
// theirs OR whose native is above theirs (27 at 1.15.0), and its parser refuses a description without the field,
// so it is written, one above.
//
// It refuses what must never be published: an APK that is not com.mattssoftware.glyph, one that is debuggable,
// one whose version code is not above the Tauri app's last (1015000), one not signed by the certificate pinned in
// ../glyph/src-tauri/apk-signer.sha256 (Android installs an update only over the same certificate), and a signing
// key the apps do not trust. --test turns the refusals into warnings, for trying the script with a throwaway key.
import { createHash, createPrivateKey, createPublicKey, sign, verify } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const flag = (name, fallback) => {
  const at = args.indexOf(`--${name}`);
  return at < 0 ? fallback : args[at + 1];
};
const test = args.includes('--test');
const apk = args.find((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--') && args[i - 1] !== '--test'));
if (!apk || !existsSync(apk)) {
  console.error('usage: node tool/release_apk.mjs <the release apk> [--out build/cutover] [--key <pem>] [--native 28] [--test]');
  process.exit(2);
}
const out = resolve(flag('out', join(ROOT, 'build/cutover')));
const keyPath = flag('key', join(homedir(), '.config/glyph/ota-signing-key.pem'));
const native = Number(flag('native', '28'));
const TAURI_LAST_CODE = 1015000;
const PIN = '3ca686b5ee56d923b9a645685e2011b66762ae99aa3a5b444b1ee754884c63aa';
const CONTEXT = { tauri: 'glyph-apk\0', flutter: 'ghost-flutter-apk\0' };

let refused = false;
const refuse = (why) => {
  console.error(`${test ? 'WARNING (would refuse)' : 'REFUSED'}: ${why}`);
  if (!test) refused = true;
};

// --- what the APK says it is ------------------------------------------------------------------------------------
const sdk = process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT || join(homedir(), 'Library/Android/sdk');
const tools = join(sdk, 'build-tools');
const newest = existsSync(tools) ? readdirSync(tools).sort((a, b) => a.localeCompare(b, undefined, { numeric: true })).pop() : null;
if (!newest) {
  console.error(`No Android build-tools under ${tools}: set ANDROID_HOME.`);
  process.exit(2);
}
const badging = spawnSync(join(tools, newest, 'aapt2'), ['dump', 'badging', apk], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
if (badging.status !== 0) {
  console.error(`aapt2 could not read ${apk}: ${badging.stderr}`);
  process.exit(2);
}
const pkg = /^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'/m.exec(badging.stdout);
if (!pkg) {
  console.error('The APK does not say what it is.');
  process.exit(2);
}
const [, id, code, version] = pkg;
if (id !== 'com.mattssoftware.glyph') refuse(`the APK is ${id}, not com.mattssoftware.glyph: build with GHOST_CUTOVER=1 (tool/cutover-build.sh).`);
if (Number(code) <= TAURI_LAST_CODE) refuse(`version code ${code} is not above the Tauri app's ${TAURI_LAST_CODE}: Android would refuse the update.`);
if (/application-debuggable/.test(badging.stdout)) refuse('the APK is debuggable. The public link must never serve one.');
if (!Number.isInteger(native) || native < 28) refuse(`native ${native} must be a whole number above the Tauri app's 27.`);

// --- who signed it ----------------------------------------------------------------------------------------------
// apksigner is Java: the JDK ../glyph/scripts/deploy-ota.mjs falls back on, or Android Studio's, unless JAVA_HOME says.
const jdk = ['/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home', '/Applications/Android Studio.app/Contents/jbr/Contents/Home'].find((home) => existsSync(home));
const env = { ...process.env, ...(process.env.JAVA_HOME || !jdk ? {} : { JAVA_HOME: jdk, PATH: `${jdk}/bin:${process.env.PATH}` }) };
const certs = spawnSync(join(tools, newest, 'apksigner'), ['verify', '--print-certs', apk], { encoding: 'utf8', env });
const signer = /certificate SHA-256 digest: ([0-9a-f]{64})/.exec(certs.stdout ?? '')?.[1];
if (certs.status !== 0 || !signer) refuse(`apksigner could not say who signed the APK (${(certs.stderr || '').trim().split('\n')[0] || 'no answer'}): set JAVA_HOME.`);
else if (signer !== PIN) refuse(`the APK is signed by ${signer}, not by Ghost.md's certificate ${PIN}: no installed Ghost.md could take it.`);

// --- the description, and its two signatures --------------------------------------------------------------------
const bytes = readFileSync(apk);
const build = flag('build', new Date().toISOString().replace(/\D/g, '').slice(0, 14));
const info = { version, versionCode: Number(code), native, sha256: createHash('sha256').update(bytes).digest('hex'), bytes: bytes.length, url: 'glyph.apk', build };
const body = Buffer.from(`${JSON.stringify(info, null, 2)}\n`);

if (!existsSync(keyPath)) {
  console.error(`No signing key at ${keyPath}.`);
  process.exit(2);
}
const key = createPrivateKey(readFileSync(keyPath));
const publicRaw = createPublicKey(key).export({ type: 'spki', format: 'der' }).subarray(-32).toString('base64');
const trusted = [...readFileSync(join(ROOT, 'lib/core/update_keys.dart'), 'utf8').matchAll(/^\s*'([A-Za-z0-9+/=]{43,44})'/gm)].map((m) => m[1]);
if (!trusted.includes(publicRaw)) refuse('the signing key is not one lib/core/update_keys.dart trusts: no installed app would believe what it signs.');

const signed = (context) => sign(null, Buffer.concat([Buffer.from(context, 'utf8'), body]), key).toString('base64');
const sigs = { tauri: signed(CONTEXT.tauri), flutter: signed(CONTEXT.flutter) };
for (const [name, context] of Object.entries(CONTEXT)) {
  if (!verify(null, Buffer.concat([Buffer.from(context, 'utf8'), body]), createPublicKey(key), Buffer.from(sigs[name], 'base64'))) {
    console.error(`The ${name} signature does not verify.`);
    process.exit(1);
  }
}
if (refused) process.exit(1);

mkdirSync(out, { recursive: true });
copyFileSync(apk, join(out, 'glyph.apk'));
writeFileSync(join(out, 'apk.json'), body);
writeFileSync(join(out, 'apk.json.sig'), `${sigs.tauri}\n`);
writeFileSync(join(out, 'apk.json.flutter.sig'), `${sigs.flutter}\n`);
console.log(`${test ? 'A TEST, NOT FOR PUBLISHING. ' : ''}Ghost.md ${version} (code ${code}, native ${native}), ${(bytes.length / 1e6).toFixed(0)} MB, signed by ${signer ?? 'nobody this script could read'}`);
console.log(`Written to ${out}: glyph.apk, apk.json, apk.json.sig, apk.json.flutter.sig. Nothing was uploaded.`);
console.log('Upload glyph.apk first and the three small files only after it is whole (docs/CUTOVER.md).');
