#!/usr/bin/env node
/**
 * Builds and signs Ghost Messaging for the Mac, makes what an installed copy updates itself from, and (when asked)
 * installs it on this Mac or publishes it. Matt, 2026-11-13: "install the app on my mac and make sure it has OTA
 * updates so we don't need to reinstall again".
 *
 *   node tool/release-mac.mjs                        # build, sign, zip, describe: into build/release-mac
 *   node tool/release-mac.mjs --install              # ...and put the app in /Applications (once: it updates itself after)
 *   node tool/release-mac.mjs --notarize             # ...and have Apple notarise it and staple the ticket
 *   node tool/release-mac.mjs --publish [--glyph ~/path/to/glyph] [--keep-connection]
 *                                                    # ...and put the zip and its description on the box
 *   --version 0.6.2   the version's name (pubspec.yaml's otherwise)
 *   --build 455123    its number (see below)
 *   --replace         with --install: take the place of a copy already in /Applications
 *
 * WHAT AN INSTALLED COPY READS (lib/desktop/updates.dart, macos/Runner/UpdatesChannel.swift):
 *
 *   https://ghost-sms.com/mac.json                 { version, versionCode, sha256, bytes, url, build, minimumSystemVersion }
 *   https://ghost-sms.com/ghost-messaging-mac.zip  the signed app, zipped by ditto
 *
 * beside the phone app's apk.json, in /opt/ghost-sms-release. ghost-sms.com's Caddy block serves that folder's
 * files by name (tool/deploy-site.mjs): the two above were added to it with this tool, so
 * `node tool/deploy-site.mjs --caddy` has to run once more before the first Mac release answers.
 *
 * THE NUMBER (`CFBundleVersion`, `versionCode`) is what newer is asked of, and an installed copy never steps back.
 * It is the minutes since 2026 began, so it rises by itself and needs nothing kept; one above the live release's
 * where that is not higher. The phone app's version code is another number and has nothing to do with it.
 *
 * WHO SIGNS IT is what makes an update believed. The app is signed inside out with the Developer ID
 * ("Developer ID Application: Matt Wisniewski (F6ZAL7ANAD)", in this Mac's keychain, as Ghost.md's Mac app is:
 * scripts/deploy-flutter-mac.mjs in the repository's root) under the hardened runtime. An installed copy takes an
 * update only if it is whole and signed by its own team, whatever the server says, so there is no second key to
 * keep or lose. A build signed any other way is refused here: no installed copy would take it.
 *
 * NOTARISING is for a copy someone downloads with a browser, which macOS will not open otherwise. A copy that
 * updates itself, or is put in /Applications by --install, is not asked for it. --notarize uses the shared
 * MattsSoftware App Store Connect key (~/.config/mattssoftware/signing/asc-api.env, or APPLE_API_ISSUER,
 * APPLE_API_KEY and APPLE_API_KEY_PATH), as Ghost.md's does.
 *
 * PUBLISHING is as tool/release.mjs does it, with Ghost.md's box code and credentials and one login: the zip first,
 * whole and by rename, and mac.json last, so no installed copy is told of a zip still arriving. It is never done
 * unless --publish is given.
 */
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const HOST_URL = 'https://ghost-sms.com';
const RELEASE = '/opt/ghost-sms-release';
const BACKUPS = '/opt/ghost-sms-releases';
const ZIP = 'ghost-messaging-mac.zip';
const FEED = 'mac.json';
const APP = 'Ghost Messaging.app';
const BUNDLE_ID = 'com.infamousvague.ghostmessaging.mac';
const TEAM = 'F6ZAL7ANAD';
const IDENTITY = process.env.GHOST_MAC_IDENTITY ?? `Developer ID Application: Matt Wisniewski (${TEAM})`;
const OUT = join(ROOT, 'build/release-mac');

const args = process.argv.slice(2);
const flag = (name) => {
  const at = args.indexOf(`--${name}`);
  return at < 0 ? undefined : args[at + 1];
};
const has = (name) => args.includes(`--${name}`);
const say = (line) => console.log(line);
const fail = (why) => {
  console.error(`x ${why}`);
  process.exit(1);
};
const run = (cmd, cmdArgs, options = {}) => {
  const result = spawnSync(cmd, cmdArgs, { stdio: 'inherit', ...options });
  if (result.error) fail(`${cmd} could not run: ${result.error.message}`);
  if (result.status !== 0) fail(`${cmd} ${cmdArgs.join(' ')} failed (${result.status}).`);
  return result;
};
/** What a tool printed, both streams (codesign describes on stderr); '' where it failed. */
const read = (cmd, cmdArgs) => {
  const result = spawnSync(cmd, cmdArgs, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  return result.status === 0 ? `${result.stdout}${result.stderr}` : '';
};

if (process.platform !== 'darwin') fail('The Mac app is built and signed on a Mac.');

// --- the version ----------------------------------------------------------------------------------------------------

function pubspecVersion() {
  const match = /^version:\s*([0-9]+\.[0-9]+\.[0-9]+)/m.exec(readFileSync(join(ROOT, 'pubspec.yaml'), 'utf8'));
  if (!match) fail('pubspec.yaml has no version.');
  return match[1];
}

/** The live release's description; null where none has been published. */
async function liveRelease() {
  try {
    const res = await fetch(`${HOST_URL}/${FEED}?t=${Date.now()}`, { cache: 'no-store' });
    if (res.status === 404) return null;
    if (!res.ok) fail(`${HOST_URL}/${FEED} answered ${res.status}.`);
    return await res.json();
  } catch (e) {
    fail(`Could not read the live Mac release: ${e.message}`);
  }
}

const live = await liveRelease();
const versionName = flag('version') ?? pubspecVersion();
const minutes = Math.floor((Date.now() - Date.UTC(2026, 0, 1)) / 60000);
const versionCode = flag('build') ? Number(flag('build')) : Math.max(minutes, (live?.versionCode ?? 0) + 1);
if (!Number.isInteger(versionCode) || versionCode <= 0) fail(`--build ${flag('build')} is not a number.`);
if (live && versionCode <= live.versionCode) fail(`Build ${versionCode} is not above the live release's ${live.versionCode}: no installed copy would take it.`);
say(`> Building Ghost Messaging for the Mac ${versionName} (${versionCode}; live is ${live ? `${live.version} (${live.versionCode})` : 'nothing yet'})`);

if (!read('security', ['find-identity', '-v', '-p', 'codesigning']).includes(`"${IDENTITY}"`)) {
  fail(`No signing identity "${IDENTITY}" in this Mac's keychain: an installed copy takes only what its own team signed.`);
}

// --- the build ------------------------------------------------------------------------------------------------------

run('flutter', ['build', 'macos', '--release', `--build-name=${versionName}`, `--build-number=${versionCode}`], { cwd: ROOT });
const built = join(ROOT, 'build/macos/Build/Products/Release', APP);
if (!existsSync(join(built, 'Contents/Info.plist'))) fail(`No app at ${built}.`);

// A copy is signed, never the build's own output: a second run starts from the same bytes.
rmSync(OUT, { recursive: true, force: true });
mkdirSync(OUT, { recursive: true });
const app = join(OUT, APP);
run('ditto', [built, app]);

const plist = JSON.parse(read('plutil', ['-convert', 'json', '-o', '-', join(app, 'Contents/Info.plist')]) || '{}');
if (plist.CFBundleIdentifier !== BUNDLE_ID) fail(`The app's id is ${plist.CFBundleIdentifier}, not ${BUNDLE_ID}.`);
if (plist.CFBundleShortVersionString !== versionName || String(plist.CFBundleVersion) !== String(versionCode)) {
  fail(`The app says ${plist.CFBundleShortVersionString} (${plist.CFBundleVersion}), not ${versionName} (${versionCode}).`);
}
if (!plist.NSLocalNetworkUsageDescription) fail('The app has no NSLocalNetworkUsageDescription: macOS would not let it look for the phone.');
const executable = join(app, 'Contents/MacOS', String(plist.CFBundleExecutable ?? ''));
const archs = read('lipo', ['-archs', executable]).trim().split(/\s+/).filter(Boolean);
if (!archs.includes('arm64')) fail(`The app is built for ${archs.join(', ') || 'nothing'}, not Apple silicon.`);

// --- signing --------------------------------------------------------------------------------------------------------

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

say('> Signing the app, inside out');
const entitlements = join(ROOT, 'macos/Runner/Release.entitlements');
const sign = (target, more = []) => run('codesign', ['--force', '--timestamp', '--options', 'runtime', '--sign', IDENTITY, ...more, target], { stdio: ['ignore', 'ignore', 'inherit'] });
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
if (/TeamIdentifier=(\S+)/.exec(signing)?.[1] !== TEAM) fail(`The app is not signed by team ${TEAM}.`);
if (!/flags=\S*\(.*runtime.*\)/.test(signing)) fail('The app is not signed with the hardened runtime.');
// What an installed copy asks of an update (UpdatesChannel.signatureRefused), asked here first.
const asked = spawnSync('codesign', ['--verify', '--deep', '--strict', `-R=anchor apple generic and certificate leaf[subject.OU] = "${TEAM}"`, app], { encoding: 'utf8' });
if (asked.status !== 0) fail(`The app does not meet what an installed copy asks of an update:\n${asked.stderr}`);
if (read('codesign', ['-d', '--entitlements', ':-', app]).includes('com.apple.security.app-sandbox')) fail('The app is sandboxed: it could not replace itself with an update.');
say(`ok signed by team ${TEAM} (Developer ID, hardened runtime), ${archs.join(' + ')}, macOS ${plist.LSMinimumSystemVersion}+`);

// --- notarising, when asked -----------------------------------------------------------------------------------------

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
  return issuer && keyId && keyPath && existsSync(keyPath) ? { issuer, keyId, keyPath } : null;
}

let notarised = false;
if (has('notarize')) {
  const notary = notaryCredentials();
  if (!notary) fail('No notarisation key: set APPLE_API_ISSUER, APPLE_API_KEY and APPLE_API_KEY_PATH, or keep the shared one in ~/.config/mattssoftware/signing/asc-api.env.');
  say('> Notarising the app (Apple reads it; a few minutes)');
  const sent = join(OUT, 'for-apple.zip');
  run('ditto', ['-c', '-k', '--keepParent', app, sent]);
  run('xcrun', ['notarytool', 'submit', sent, '--key', notary.keyPath, '--key-id', notary.keyId, '--issuer', notary.issuer, '--wait']);
  rmSync(sent);
  run('xcrun', ['stapler', 'staple', app]);
  if (spawnSync('xcrun', ['stapler', 'validate', app], { encoding: 'utf8' }).status !== 0) fail('The app has no notarisation ticket stapled to it.');
  notarised = true;
  say('ok notarised, and the ticket stapled');
}

// --- what an installed copy reads -----------------------------------------------------------------------------------

const zip = join(OUT, ZIP);
run('ditto', ['-c', '-k', '--keepParent', app, zip]);
const bytes = readFileSync(zip);
const info = {
  version: versionName,
  versionCode,
  sha256: createHash('sha256').update(bytes).digest('hex'),
  bytes: bytes.length,
  url: ZIP,
  build: new Date().toISOString().replace(/\D/g, '').slice(0, 14),
  minimumSystemVersion: String(plist.LSMinimumSystemVersion ?? ''),
};
writeFileSync(join(OUT, FEED), `${JSON.stringify(info, null, 2)}\n`);
say(`ok Ghost Messaging for the Mac ${info.version} (${info.versionCode}), ${(info.bytes / 1e6).toFixed(1)} MB zipped${notarised ? ', notarised' : ''}, in build/release-mac`);

// --- on this Mac ----------------------------------------------------------------------------------------------------

if (has('install')) {
  const folder = resolve(flag('install-to') ?? '/Applications');
  const dest = join(folder, APP);
  let aside = null;
  if (existsSync(dest)) {
    if (!has('replace')) fail(`${dest} is there already. It updates itself; --replace takes its place with this build.`);
    if (read('pgrep', ['-f', join(dest, 'Contents/MacOS')]).trim()) fail(`${dest} is running. Quit it first.`);
    aside = join(folder, `.${APP}-replaced-${info.build}`);
    renameSync(dest, aside);
  }
  run('ditto', [app, dest]);
  if (spawnSync('codesign', ['--verify', '--deep', '--strict', dest], { encoding: 'utf8' }).status !== 0) {
    if (aside) {
      rmSync(dest, { recursive: true, force: true });
      renameSync(aside, dest);
    }
    fail(`The copy in ${folder} does not verify; ${aside ? 'the one that was there is back' : 'nothing was there before'}.`);
  }
  if (aside) rmSync(aside, { recursive: true, force: true });
  say(`ok installed: ${dest}`);
}

if (!has('publish')) process.exit(0);

// --- publishing, with Ghost.md's box --------------------------------------------------------------------------------

if (!notarised) say('! Not notarised: right for copies that update themselves, not for a download from a browser.');
const glyph = [flag('glyph'), process.env.GLYPH_ROOT, join(ROOT, '..'), join(ROOT, '..', 'glyph'), join(homedir(), 'Development/Apps/glyph')]
  .filter(Boolean)
  .find((dir) => existsSync(join(dir, 'tauri/scripts/lib/box.mjs')) && existsSync(join(dir, 'scripts/lib/env.mjs')));
if (!glyph) fail('No Ghost.md checkout found for its box code (--glyph <path> or GLYPH_ROOT).');
const { BOX_ENV_KEYS, boxSshOptions, openBox } = await import(pathToFileURL(join(glyph, 'tauri/scripts/lib/box.mjs')).href);
const { loadEnv } = await import(pathToFileURL(join(glyph, 'scripts/lib/env.mjs')).href);
const env = loadEnv(BOX_ENV_KEYS);
const box = openBox(env, boxSshOptions({ connectTimeout: 20 }));
const keepConnection = has('keep-connection');
say('> Logging in to the box');
box.logIn();
const STAGE = '/tmp/ghost-messaging-mac-stage';
box.ssh(`rm -rf ${STAGE} && mkdir -p ${STAGE}`);
say(`> Uploading (${(info.bytes / 1e6).toFixed(1)} MB)`);
box.rsync(['--progress'], zip, `${STAGE}/${ZIP}`);
box.rsync([], join(OUT, FEED), `${STAGE}/${FEED}`);
say('> Publishing');
// The zip first, whole, by rename; mac.json last, so no installed copy is told of a zip still arriving. The live
// two are kept outside the web root first.
box.ssh(`set -e
SUDO=; [ "$(id -u)" -eq 0 ] || SUDO=sudo
[ "$(sha256sum ${STAGE}/${ZIP} | cut -d' ' -f1)" = "${info.sha256}" ] || { echo "x the zip arrived changed"; exit 1; }
stamp=$(date -u +%Y%m%d%H%M%S)
$SUDO mkdir -p ${RELEASE} ${BACKUPS}
if [ -f ${RELEASE}/${FEED} ]; then $SUDO mkdir -p ${BACKUPS}/mac-before-$stamp && $SUDO cp -p ${RELEASE}/${FEED} ${RELEASE}/${ZIP} ${BACKUPS}/mac-before-$stamp/; fi
$SUDO install -m 644 -o root -g root ${STAGE}/${ZIP} ${RELEASE}/.${ZIP}.new
$SUDO mv -f ${RELEASE}/.${ZIP}.new ${RELEASE}/${ZIP}
$SUDO install -m 644 -o root -g root ${STAGE}/${FEED} ${RELEASE}/.${FEED}.new
$SUDO mv -f ${RELEASE}/.${FEED}.new ${RELEASE}/${FEED}
$SUDO chmod 755 ${RELEASE}
rm -rf ${STAGE}
echo "ok placed in ${RELEASE}"`);

// Is it served? ghost-sms.com's block names the files it serves from that folder (tool/deploy-site.mjs).
const res = await fetch(`${HOST_URL}/${FEED}?t=${Date.now()}`, { cache: 'no-store' }).catch((e) => ({ ok: false, status: e.message }));
const said = res.ok ? await res.json().catch(() => null) : null;
if (!keepConnection) box.close();
if (said?.sha256 !== info.sha256) {
  say(`x ${HOST_URL}/${FEED} answered ${res.status}, not this release. The release is in ${RELEASE} on the box.`);
  say(`  ghost-sms.com's Caddy block has to name /${FEED} and /${ZIP}: node tool/deploy-site.mjs --caddy`);
  process.exit(1);
}
const head = await fetch(`${HOST_URL}/${ZIP}`, { method: 'HEAD' });
say(`ok live: ${HOST_URL}/${FEED} — Ghost Messaging for the Mac ${info.version} (${info.versionCode}), zip served at ${head.headers.get('content-length')} bytes (${info.bytes} expected)`);
