#!/usr/bin/env node
/**
 * Publishes the Mac app that replaces the Tauri one: the Flutter app's Mac release (tool/cutover-build-mac.sh;
 * docs/CUTOVER.md says why and what was proven), as the download the site has always served.
 *
 *   node scripts/deploy-flutter-mac.mjs --prepare build/release-mac/Ghost.md.app   # sign, notarise, make the image
 *   node scripts/deploy-flutter-mac.mjs [--from build/cutover-mac] [--print]       # publish what --prepare left
 *
 *   /glyph/glyph.dmg      the Mac app: universal, signed with the Developer ID, notarised and stapled (app and image)
 *   /glyph/desktop.json   what the download page says of it, placed last, after the image is whole
 *
 * --prepare logs in nowhere. It signs the app inside out under the hardened runtime with the microphone's
 * entitlement, sends it to Apple with the shared MattsSoftware App Store Connect key, staples the ticket, makes the
 * disk image with hdiutil, signs, notarises and staples that too, checks all of it on the built files as
 * tauri/scripts/deploy-ota.mjs --desktop does, and writes glyph.dmg and desktop.json to build/cutover-mac.
 *
 * Publishing is one ssh session (the box counts logins): the image and the note that were live are kept beside the
 * release (`.dmg-before-<stamp>`), the image is placed by rename, then desktop.json.
 */
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { BOX_ENV_KEYS, boxSshOptions, openBox } from '../tauri/scripts/lib/box.mjs';
import { loadEnv } from './lib/env.mjs';
import { ROOT } from './lib/paths.mjs';
import { fail } from '../tauri/scripts/lib/say.mjs';

const RELEASE = '/opt/attackfm-site/glyph';
const MAC_TEAM = 'F6ZAL7ANAD';
const MAC_IDENTITY = process.env.GLYPH_MAC_IDENTITY ?? `Developer ID Application: Matt Wisniewski (${MAC_TEAM})`;
const TAURI_ID = 'com.mattssoftware.glyph';
const OUT = join(ROOT, 'build/cutover-mac');
const args = process.argv.slice(2);
const ok = (words) => console.log(`ok ${words}`);
const step = (words) => console.log(`> ${words}`);

function run(command, commandArgs, what = command) {
  const done = spawnSync(command, commandArgs, { stdio: 'inherit' });
  if (done.status !== 0) fail(`${what} failed.`);
}
const read = (command, commandArgs) => {
  const done = spawnSync(command, commandArgs, { encoding: 'utf8' });
  return `${done.stdout ?? ''}${done.stderr ?? ''}`;
};

/** The team's App Store Connect key, as tauri/scripts/deploy-ota.mjs finds it. */
function notaryCredentials() {
  let issuer = process.env.APPLE_API_ISSUER;
  let keyId = process.env.APPLE_API_KEY;
  let keyPath = process.env.APPLE_API_KEY_PATH;
  const shared = join(homedir(), '.config/mattssoftware/signing/asc-api.env');
  if (!(issuer && keyId && keyPath) && existsSync(shared)) {
    const kept = Object.fromEntries(
      readFileSync(shared, 'utf8')
        .split('\n')
        .map((line) => /^\s*(?:export\s+)?([A-Z_]+)\s*=\s*"?([^"\n]*?)"?\s*$/.exec(line))
        .filter(Boolean)
        .map((match) => [match[1], match[2]]),
    );
    issuer ||= kept.ASC_ISSUER_ID;
    keyId ||= kept.ASC_KEY_ID;
    keyPath ||= kept.ASC_KEY_PATH;
  }
  keyPath = keyPath?.replace(/^(\$HOME|~)(?=\/)/, homedir());
  return issuer && keyId && keyPath && existsSync(keyPath) ? { issuer, keyId, keyPath } : null;
}

/** Every file under [dir], deepest first, so what is inside is signed before what holds it. */
function walk(dir) {
  const found = [];
  for (const name of readdirSync(dir, { withFileTypes: true })) {
    const at = join(dir, name.name);
    if (name.isSymbolicLink()) continue;
    if (name.isDirectory()) found.push(...walk(at), at);
    else found.push(at);
  }
  return found;
}

function prepare(given) {
  if (process.platform !== 'darwin') fail('--prepare signs the Mac app, and that needs a Mac.');
  const built = resolve(given ?? '');
  if (!given || !existsSync(join(built, 'Contents/Info.plist'))) fail('Give the built app: --prepare build/release-mac/Ghost.md.app');
  if (!read('security', ['find-identity', '-v', '-p', 'codesigning']).includes(`"${MAC_IDENTITY}"`)) {
    fail(`No signing identity "${MAC_IDENTITY}" in this Mac's keychain.`);
  }
  const notary = notaryCredentials();
  if (!notary) fail('No notarisation key: set APPLE_API_ISSUER, APPLE_API_KEY and APPLE_API_KEY_PATH, or keep the shared one in ~/.config/mattssoftware/signing/asc-api.env.');

  // A copy is signed, never the build's own output: a second run starts from the same bytes.
  rmSync(OUT, { recursive: true, force: true });
  mkdirSync(join(OUT, 'image'), { recursive: true });
  const app = join(OUT, 'image/Ghost.md.app');
  run('ditto', [built, app]);

  const plist = JSON.parse(read('plutil', ['-convert', 'json', '-o', '-', join(app, 'Contents/Info.plist')]) || '{}');
  if (plist.CFBundleIdentifier !== TAURI_ID) fail(`The app's id is ${plist.CFBundleIdentifier}, not ${TAURI_ID}: this is not the cut-over build.`);
  if (plist.CFBundleName !== 'Ghost.md' && plist.CFBundleDisplayName !== 'Ghost.md') fail(`The app is named ${plist.CFBundleName}, not Ghost.md.`);
  const version = String(plist.CFBundleShortVersionString ?? '');
  if (!/^[2-9]\.\d+\.\d+$/.test(version)) fail(`The app says version ${version}: not above the Tauri app's 1.15.0.`);
  if (!plist.NSMicrophoneUsageDescription) fail('The app has no NSMicrophoneUsageDescription: macOS would refuse it the microphone.');
  if (!plist.LSMinimumSystemVersion) fail('The app has no LSMinimumSystemVersion for the download page to quote.');
  const executable = join(app, 'Contents/MacOS', String(plist.CFBundleExecutable ?? ''));
  const archs = read('lipo', ['-archs', executable]).trim().split(/\s+/);
  if (!archs.includes('arm64') || !archs.includes('x86_64')) fail(`The app is built for ${archs.join(', ') || 'nothing'}, not both Apple silicon and Intel.`);

  step('Signing the app, inside out');
  const entitlements = join(ROOT, 'macos/Runner/Release.entitlements');
  const sign = (target, more = []) => run('codesign', ['--force', '--timestamp', '--options', 'runtime', '--sign', MAC_IDENTITY, ...more, target], `codesign ${target}`);
  const frameworks = join(app, 'Contents/Frameworks');
  if (existsSync(frameworks)) {
    for (const at of walk(frameworks)) {
      const isBundle = /\.(framework|bundle|xpc|app)$/.test(at) && statSync(at).isDirectory();
      const isCode = !isBundle && statSync(at).isFile() && (/\.dylib$/.test(at) || /Mach-O/.test(read('file', ['-b', at])));
      if (isBundle || isCode) sign(at);
    }
  }
  sign(app, ['--entitlements', entitlements]);

  const verified = spawnSync('codesign', ['--verify', '--deep', '--strict', app], { encoding: 'utf8' });
  if (verified.status !== 0) fail(`codesign does not verify the signed app:\n${verified.stderr}`);
  const signing = read('codesign', ['-dv', '--verbose=2', app]);
  if (/TeamIdentifier=(\S+)/.exec(signing)?.[1] !== MAC_TEAM) fail(`The app is not signed by team ${MAC_TEAM}.`);
  if (!/flags=\S*\(.*runtime.*\)/.test(signing)) fail('The app is not signed with the hardened runtime.');
  if (!read('codesign', ['-d', '--entitlements', ':-', app]).includes('com.apple.security.device.audio-input')) fail('The app has no microphone entitlement.');
  ok(`signed by team ${MAC_TEAM} (Developer ID, hardened runtime), microphone allowed, ${archs.join(' + ')}, macOS ${plist.LSMinimumSystemVersion}+`);

  const submit = (file, what) => run('xcrun', ['notarytool', 'submit', file, '--key', notary.keyPath, '--key-id', notary.keyId, '--issuer', notary.issuer, '--wait'], `notarytool submit (${what})`);
  step('Notarising the app');
  const zip = join(OUT, 'Ghost.md.zip');
  run('ditto', ['-c', '-k', '--keepParent', app, zip]);
  submit(zip, 'the app');
  rmSync(zip);
  run('xcrun', ['stapler', 'staple', app], 'stapler staple (the app)');

  step('Making the disk image');
  symlinkSync('/Applications', join(OUT, 'image/Applications'));
  const dmg = join(OUT, 'glyph.dmg');
  run('hdiutil', ['create', '-volname', 'Ghost.md', '-srcfolder', join(OUT, 'image'), '-ov', '-format', 'UDZO', dmg]);
  run('codesign', ['--force', '--timestamp', '--sign', MAC_IDENTITY, dmg], 'codesign (the image)');
  step('Notarising the disk image');
  submit(dmg, 'the image');
  run('xcrun', ['stapler', 'staple', dmg], 'stapler staple (the image)');
  for (const [what, at] of [['app', app], ['disk image', dmg]]) {
    if (spawnSync('xcrun', ['stapler', 'validate', at], { encoding: 'utf8' }).status !== 0) fail(`The ${what} has no notarisation ticket stapled to it.`);
  }
  if (!/source=Notarized Developer ID/.test(read('spctl', ['-a', '-vvv', '-t', 'install', app]))) fail('Gatekeeper does not take the app as notarised.');
  ok('app and disk image notarised, with their tickets stapled');

  const bytes = readFileSync(dmg);
  const now = new Date();
  const info = {
    version,
    build: now.toISOString().replace(/\D/g, '').slice(0, 14),
    sha256: createHash('sha256').update(bytes).digest('hex'),
    bytes: bytes.length,
    url: 'glyph.dmg',
    arch: archs,
    minimumSystemVersion: plist.LSMinimumSystemVersion,
    team: MAC_TEAM,
    notarized: true,
  };
  writeFileSync(join(OUT, 'desktop.json'), `${JSON.stringify(info, null, 2)}\n`);
  // The signed app is kept beside the image, for trying before it is published.
  rmSync(join(OUT, 'Ghost.md.app'), { recursive: true, force: true });
  cpSync(app, join(OUT, 'Ghost.md.app'), { recursive: true, verbatimSymlinks: true });
  rmSync(join(OUT, 'image'), { recursive: true, force: true });
  ok(`Ghost.md ${info.version} for Mac, ${(info.bytes / 1e6).toFixed(0)} MB, in ${OUT}. Nothing was uploaded.`);
}

function publish() {
  const at = args.indexOf('--from');
  const from = at >= 0 ? resolve(args[at + 1]) : OUT;
  for (const name of ['glyph.dmg', 'desktop.json']) if (!existsSync(join(from, name))) fail(`No ${name} in ${from}: run --prepare first.`);
  const info = JSON.parse(readFileSync(join(from, 'desktop.json'), 'utf8'));
  const dmg = readFileSync(join(from, 'glyph.dmg'));
  if (createHash('sha256').update(dmg).digest('hex') !== info.sha256 || dmg.length !== info.bytes) fail('glyph.dmg is not the file desktop.json describes.');
  if (!/^[2-9]\./.test(info.version) || info.notarized !== true) fail(`desktop.json says ${info.version}, notarized ${info.notarized}: not a notarised build above the Tauri app's.`);
  if (spawnSync('xcrun', ['stapler', 'validate', join(from, 'glyph.dmg')], { encoding: 'utf8' }).status !== 0) fail('The disk image has no notarisation ticket stapled to it.');
  ok(`Ghost.md ${info.version} for Mac, ${(info.bytes / 1e6).toFixed(0)} MB`);
  if (args.includes('--print')) return;

  const env = loadEnv(BOX_ENV_KEYS);
  const box = openBox(env, boxSshOptions({ connectTimeout: 20 }));
  step('Logging in to the box');
  box.logIn();
  const STAGE = '/tmp/ghostmd-flutter-mac-stage';
  box.ssh(`rm -rf ${STAGE} && mkdir -p ${STAGE}`);
  step(`Uploading the disk image (${(info.bytes / 1e6).toFixed(0)} MB)`);
  box.rsync(['--progress'], join(from, 'glyph.dmg'), `${STAGE}/glyph.dmg`);
  box.rsync([], join(from, 'desktop.json'), `${STAGE}/desktop.json`);
  step('Publishing');
  box.ssh(`set -e
SUDO=; [ "$(id -u)" -eq 0 ] || SUDO=sudo
[ "$(sha256sum ${STAGE}/glyph.dmg | cut -d' ' -f1)" = "${info.sha256}" ] || { echo "x the image arrived changed"; exit 1; }
stamp=$(date -u +%Y%m%d%H%M%S)
$SUDO mkdir -p ${RELEASE}.dmg-before-$stamp
for f in glyph.dmg desktop.json; do [ -f ${RELEASE}/$f ] && $SUDO cp -p ${RELEASE}/$f ${RELEASE}.dmg-before-$stamp/; done
$SUDO install -m 644 -o root -g root ${STAGE}/glyph.dmg ${RELEASE}/.glyph.dmg.new
$SUDO mv -f ${RELEASE}/.glyph.dmg.new ${RELEASE}/glyph.dmg
$SUDO install -m 644 -o root -g root ${STAGE}/desktop.json ${RELEASE}/.desktop.json.new
$SUDO mv -f ${RELEASE}/.desktop.json.new ${RELEASE}/desktop.json
rm -rf ${STAGE}
echo "ok placed; the two before it are in ${RELEASE}.dmg-before-$stamp (login $stamp)"`);
  if (!args.includes('--keep-connection')) box.close();

  const curl = (curlArgs) => spawnSync('curl', ['-s', '--max-time', '30', ...curlArgs], { encoding: 'utf8' }).stdout;
  const live = curl(['https://ghostmarkdown.com/desktop.json']);
  let said = null;
  try {
    said = JSON.parse(live);
  } catch {
    said = null;
  }
  if (said?.sha256 !== info.sha256) fail(`https://ghostmarkdown.com/desktop.json does not say this image yet:\n${live}`);
  const size = /content-length: (\d+)/i.exec(curl(['-I', 'https://ghostmarkdown.com/glyph.dmg']))?.[1];
  ok(`live: Ghost.md ${info.version} for Mac; glyph.dmg served at ${size} bytes (${info.bytes} expected)`);
}

const preparing = args.indexOf('--prepare');
if (preparing >= 0) prepare(args[preparing + 1]);
else publish();
