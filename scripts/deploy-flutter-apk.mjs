#!/usr/bin/env node
/**
 * Publishes the Android app that replaced the Tauri one: the Flutter app's release, made and signed in this
 * repository, whose root is that app (tool/cutover-build.sh, tool/release_apk.mjs; docs/CUTOVER.md says why and what
 * was proven).
 *
 *   node scripts/deploy-flutter-apk.mjs [--from build/cutover] [--keep-connection]
 *
 *   /glyph/glyph.apk              the APK every install and the download page fetch
 *   /glyph/apk.json               what an installed app reads to know of it
 *   /glyph/apk.json.sig           the Tauri app's signature of it: an installed Tauri app offers this APK by it
 *   /glyph/apk.json.flutter.sig   the Flutter app's own
 *
 * Nothing is built or signed here. The files are checked against each other, the live three are kept beside them on
 * the box (`.before-<stamp>`), and they are placed in the order that is the safety: the APK first, whole, by rename;
 * the Flutter signature; then apk.json and apk.json.sig last, so no installed app is told of an APK that is still
 * arriving. One ssh session (the box counts logins: tauri/scripts/deploy-ota.mjs).
 */
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { BOX_ENV_KEYS, boxSshOptions, openBox } from '../tauri/scripts/lib/box.mjs';
import { loadEnv } from './lib/env.mjs';
import { ROOT } from './lib/paths.mjs';
import { fail } from '../tauri/scripts/lib/say.mjs';

const RELEASE = '/opt/attackfm-site/glyph';
const args = process.argv.slice(2);
const at = args.indexOf('--from');
// The default is the root's own build/cutover wherever this is run from; a --from is relative to where it is run.
const from = at >= 0 ? resolve(args[at + 1]) : join(ROOT, 'build/cutover');
const keepConnection = args.includes('--keep-connection');

const names = ['glyph.apk', 'apk.json', 'apk.json.sig', 'apk.json.flutter.sig'];
for (const name of names) if (!existsSync(join(from, name))) fail(`No ${name} in ${from}: run tool/release_apk.mjs first.`);
const info = JSON.parse(readFileSync(join(from, 'apk.json'), 'utf8'));
const apk = readFileSync(join(from, 'glyph.apk'));
const sha = createHash('sha256').update(apk).digest('hex');
if (sha !== info.sha256 || apk.length !== info.bytes) fail('glyph.apk is not the file apk.json describes.');
if (!(info.versionCode > 1015000) || !(info.native > 27)) fail(`apk.json says ${info.version} (${info.versionCode}, native ${info.native}): not above the Tauri app's last.`);
console.log(`ok Ghost.md ${info.version} (code ${info.versionCode}, native ${info.native}), ${(info.bytes / 1e6).toFixed(0)} MB`);
if (args.includes('--print')) process.exit(0);

const env = loadEnv(BOX_ENV_KEYS);
const box = openBox(env, boxSshOptions({ connectTimeout: 20 }));
console.log('> Logging in to the box');
box.logIn();
const STAGE = '/tmp/ghostmd-flutter-apk-stage';
box.ssh(`rm -rf ${STAGE} && mkdir -p ${STAGE}`);
console.log(`> Uploading the APK (${(info.bytes / 1e6).toFixed(0)} MB)`);
box.rsync(['--progress'], join(from, 'glyph.apk'), `${STAGE}/glyph.apk`);
for (const name of names.slice(1)) box.rsync([], join(from, name), `${STAGE}/${name}`);
console.log('> Publishing');
box.ssh(`set -e
SUDO=; [ "$(id -u)" -eq 0 ] || SUDO=sudo
[ "$(sha256sum ${STAGE}/glyph.apk | cut -d' ' -f1)" = "${info.sha256}" ] || { echo "x the APK arrived changed"; exit 1; }
stamp=$(date -u +%Y%m%d%H%M%S)
$SUDO mkdir -p ${RELEASE}.apk-before-$stamp
for f in glyph.apk apk.json apk.json.sig; do [ -f ${RELEASE}/$f ] && $SUDO cp -p ${RELEASE}/$f ${RELEASE}.apk-before-$stamp/; done
$SUDO install -m 644 -o root -g root ${STAGE}/glyph.apk ${RELEASE}/.glyph.apk.new
$SUDO mv -f ${RELEASE}/.glyph.apk.new ${RELEASE}/glyph.apk
$SUDO install -m 644 -o root -g root ${STAGE}/apk.json.flutter.sig ${RELEASE}/apk.json.flutter.sig
$SUDO install -m 644 -o root -g root ${STAGE}/apk.json.sig ${RELEASE}/.apk.json.sig.new
$SUDO install -m 644 -o root -g root ${STAGE}/apk.json ${RELEASE}/.apk.json.new
$SUDO mv -f ${RELEASE}/.apk.json.sig.new ${RELEASE}/apk.json.sig
$SUDO mv -f ${RELEASE}/.apk.json.new ${RELEASE}/apk.json
rm -rf ${STAGE}
echo "ok placed; the three before it are in ${RELEASE}.apk-before-$stamp (login $stamp)"`);
if (!keepConnection) box.close();

const curl = (curlArgs) => spawnSync('curl', ['-s', '--max-time', '30', ...curlArgs], { encoding: 'utf8' }).stdout;
const live = curl(['https://attack.fm/glyph/apk.json']);
const said = (() => {
  try {
    return JSON.parse(live);
  } catch {
    return null;
  }
})();
if (said?.sha256 !== info.sha256) fail(`https://attack.fm/glyph/apk.json does not say this APK yet:\n${live}`);
const size = /content-length: (\d+)/i.exec(curl(['-I', 'https://attack.fm/glyph/glyph.apk']))?.[1];
console.log(`ok live: Ghost.md ${info.version}; glyph.apk served at ${size} bytes (${info.bytes} expected)`);
