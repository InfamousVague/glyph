#!/usr/bin/env node
/**
 * Builds, checks and publishes a Ghost Messaging release to the box (the server Ghost.md and Ghost Keyboard deploy
 * to), where installed copies find it and update themselves (android/.../Updater.kt). Ghost Keyboard's
 * tool/release.mjs, for this app (Matt, 2026-11-13: "add auto update and serve it over ghost-sms.com I'll point the
 * domain to the same server ghost kbd uses").
 *
 *   node tool/release.mjs [--glyph ~/path/to/glyph] [--version 0.4.0] [--no-deploy] [--keep-connection] [--again]
 *
 * Put in /opt/ghost-sms-release, which ghost-sms.com's Caddy block (tool/deploy-site.mjs --caddy) serves at:
 *
 *   https://ghost-sms.com/apk.json             { version, versionCode, sha256, bytes, url, build }: what an installed app reads
 *   https://ghost-sms.com/ghost-messaging.apk  the release, signed with the release key; the site's download
 *
 * RUN tool/deploy-site.mjs --caddy ONCE FIRST, so the domain has its block; a release before that is placed but
 * not served, and this says so.
 *
 * THE CREDENTIALS ARE GHOST.MD'S. Nothing is copied here: the box's address, account and password are read from
 * Ghost.md's own .env (tauri/.env: AFM_DEPLOY_HOST, AFM_DEPLOY_USER, AFM_DEPLOY_PASS) by Ghost.md's own loader, and the
 * box is reached through Ghost.md's box.mjs, so this spends ONE login on the shared, multiplexed connection exactly as
 * Ghost.md's deploys do (the box locks an account out after a few logins in a short window). This app lives in
 * Ghost.md's repository (messaging/), so the checkout is the folder above; --glyph or $GLYPH_ROOT say otherwise.
 *
 * THE RELEASE KEY is ~/.config/ghostmessaging/ (signing.properties and release.keystore), made here the first time.
 * Android installs an update only over the same certificate, so losing it means everyone reinstalls: back it up. The
 * certificate's SHA-256 is pinned in ~/.config/ghostmessaging/cert.sha256 by the first release, and a build signed by
 * anything else (the debug key included) is refused. A copy installed from a build made without this key (the first
 * ones, built in a cloud session) is replaced once by the release, and updates itself from then on.
 *
 * The version code is one above the live release's, so it always rises; the version name is pubspec.yaml's unless
 * --version says otherwise.
 */
import { spawnSync } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { chmodSync, copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const HOST_URL = 'https://ghost-sms.com';
const RELEASE = '/opt/ghost-sms-release';
const BACKUPS = '/opt/ghost-sms-releases';
const APK = 'ghost-messaging.apk';
const PACKAGE = 'com.infamousvague.ghostmessaging';
const CONFIG = join(homedir(), '.config', 'ghostmessaging');

const args = process.argv.slice(2);
const flag = (name) => {
  const at = args.indexOf(`--${name}`);
  return at < 0 ? undefined : args[at + 1];
};
const deploy = !args.includes('--no-deploy');
const keepConnection = args.includes('--keep-connection');

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
const capture = (cmd, cmdArgs) => {
  const result = spawnSync(cmd, cmdArgs, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (result.error) fail(`${cmd} could not run: ${result.error.message}`);
  if (result.status !== 0) fail(`${cmd} failed: ${result.stderr || result.stdout}`);
  return result.stdout;
};

// --- Ghost.md, for the box and its credentials ----------------------------------------------------------------------

function findGlyph() {
  const candidates = [
    flag('glyph'),
    process.env.GLYPH_ROOT,
    join(ROOT, '..'),
    join(ROOT, '..', 'glyph'),
    join(ROOT, '..', 'Glyph'),
    ...['Projects', 'Developer', 'dev', 'code', 'src', 'GitHub', 'Documents/GitHub', 'repos', ''].map((d) => join(homedir(), d, 'glyph')),
  ].filter(Boolean);
  for (const dir of candidates) {
    if (existsSync(join(dir, 'tauri', 'scripts', 'lib', 'box.mjs')) && existsSync(join(dir, 'scripts', 'lib', 'env.mjs'))) return resolve(dir);
  }
  fail(`Could not find the Ghost.md checkout (looked in ${candidates.join(', ')}). Pass --glyph <path> or set GLYPH_ROOT.`);
}

// --- the Android SDK's tools --------------------------------------------------------------------------------------

const sdk = process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT || join(homedir(), 'Library/Android/sdk');
function buildTool(name) {
  const tools = join(sdk, 'build-tools');
  const newest = existsSync(tools) ? readdirSync(tools).sort((a, b) => a.localeCompare(b, undefined, { numeric: true })).pop() : null;
  if (!newest) fail(`No Android build-tools under ${tools}: set ANDROID_HOME.`);
  return join(tools, newest, name);
}

function keytool() {
  const candidates = [
    process.env.JAVA_HOME && join(process.env.JAVA_HOME, 'bin', 'keytool'),
    '/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool',
    '/Applications/Android Studio.app/Contents/jre/Contents/Home/bin/keytool',
  ].filter(Boolean);
  for (const path of candidates) if (existsSync(path)) return path;
  const javaHome = spawnSync('/usr/libexec/java_home', [], { encoding: 'utf8' });
  if (javaHome.status === 0 && existsSync(join(javaHome.stdout.trim(), 'bin', 'keytool'))) return join(javaHome.stdout.trim(), 'bin', 'keytool');
  return 'keytool';
}

// --- the release key ----------------------------------------------------------------------------------------------

function ensureSigningKey() {
  const props = join(CONFIG, 'signing.properties');
  if (existsSync(props)) return;
  say('> No release key yet: making one in ~/.config/ghostmessaging (back this folder up)');
  mkdirSync(CONFIG, { recursive: true, mode: 0o700 });
  const store = join(CONFIG, 'release.keystore');
  const password = randomBytes(24).toString('hex');
  run(keytool(), [
    '-genkeypair', '-noprompt',
    '-keystore', store, '-storetype', 'PKCS12',
    '-alias', 'ghostmessaging', '-keyalg', 'RSA', '-keysize', '4096', '-validity', '36500',
    '-dname', 'CN=Ghost Messaging, O=InfamousVague',
    '-storepass', password, '-keypass', password,
  ]);
  writeFileSync(props, `storeFile=${store}\nstorePassword=${password}\nkeyAlias=ghostmessaging\nkeyPassword=${password}\n`, { mode: 0o600 });
  chmodSync(props, 0o600);
  chmodSync(store, 0o600);
}

// --- versions -----------------------------------------------------------------------------------------------------

async function liveRelease() {
  try {
    const res = await fetch(`${HOST_URL}/apk.json?t=${Date.now()}`, { cache: 'no-store' });
    if (res.status === 404) return null;
    if (!res.ok) fail(`${HOST_URL}/apk.json answered ${res.status}.`);
    return await res.json();
  } catch (e) {
    fail(`Could not read the live release: ${e.message}`);
  }
}

function pubspecVersion() {
  const match = /^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?/m.exec(readFileSync(join(ROOT, 'pubspec.yaml'), 'utf8'));
  if (!match) fail('pubspec.yaml has no version.');
  return { name: match[1], build: Number(match[2] ?? 1) };
}

// --- the release --------------------------------------------------------------------------------------------------

const glyph = deploy ? findGlyph() : null;
if (glyph) say(`ok Ghost.md at ${glyph} (the box's credentials)`);

ensureSigningKey();

const live = await liveRelease();
const pub = pubspecVersion();
const versionName = flag('version') ?? pub.name;
const versionCode = Math.max((live?.versionCode ?? 0) + 1, pub.build);
// A version that is live already is not published a second time (tool/release-mac.mjs says why): the same name
// live means someone has released it since this was started. --again says it is meant.
if (deploy && live && live.version === versionName && !args.includes('--again')) {
  fail(`${versionName} is live already (code ${live.versionCode}, published ${live.build ?? 'earlier'}): someone has released it. Nothing was built or sent. If it really is to go out again under the same name, pass --again.`);
}
say(`> Building Ghost Messaging ${versionName} (code ${versionCode}; live is ${live ? `${live.version} (${live.versionCode})` : 'nothing yet'})`);

run('flutter', ['build', 'apk', '--release', '--target-platform', 'android-arm64', `--build-name=${versionName}`, `--build-number=${versionCode}`], { cwd: ROOT });
const built = join(ROOT, 'build/app/outputs/flutter-apk/app-release.apk');
if (!existsSync(built)) fail(`No APK at ${built}.`);

// What the APK says it is.
const badging = capture(buildTool('aapt2'), ['dump', 'badging', built]);
const pkg = /^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'/m.exec(badging);
if (!pkg) fail('The APK does not say what it is.');
if (pkg[1] !== PACKAGE) fail(`The APK is ${pkg[1]}, not ${PACKAGE}.`);
if (Number(pkg[2]) !== versionCode || pkg[3] !== versionName) fail(`The APK is ${pkg[3]} (${pkg[2]}), not ${versionName} (${versionCode}).`);
if (/^application-debuggable/m.test(badging)) fail('The APK is debuggable.');

// Who signed it.
const certs = capture(buildTool('apksigner'), ['verify', '--print-certs', built]);
const digest = /certificate SHA-256 digest: ([0-9a-f]{64})/i.exec(certs)?.[1]?.toLowerCase();
if (!digest) fail('apksigner did not name the signing certificate.');
if (/CN=Android Debug/.test(certs)) fail('The APK is signed with the debug key: ~/.config/ghostmessaging/signing.properties was not used.');
const pinFile = join(CONFIG, 'cert.sha256');
if (existsSync(pinFile)) {
  const pin = readFileSync(pinFile, 'utf8').trim();
  if (pin !== digest) fail(`The APK is signed by ${digest}, not the release key ${pin}. Installed copies could not update to it.`);
} else {
  writeFileSync(pinFile, `${digest}\n`, { mode: 0o600 });
  say(`ok release certificate pinned: ${digest}`);
}

// The release's files.
const out = join(ROOT, 'build/release');
mkdirSync(out, { recursive: true });
copyFileSync(built, join(out, APK));
const bytes = readFileSync(join(out, APK));
const info = {
  version: versionName,
  versionCode,
  sha256: createHash('sha256').update(bytes).digest('hex'),
  bytes: bytes.length,
  url: APK,
  build: new Date().toISOString().replace(/\D/g, '').slice(0, 14),
};
writeFileSync(join(out, 'apk.json'), `${JSON.stringify(info, null, 2)}\n`);
say(`ok Ghost Messaging ${info.version} (code ${info.versionCode}), ${(info.bytes / 1e6).toFixed(1)} MB, in build/release`);
if (!deploy) process.exit(0);

// --- publishing, with Ghost.md's box ------------------------------------------------------------------------------

const { BOX_ENV_KEYS, boxSshOptions, openBox } = await import(pathToFileURL(join(glyph, 'tauri/scripts/lib/box.mjs')).href);
const { loadEnv } = await import(pathToFileURL(join(glyph, 'scripts/lib/env.mjs')).href);
const env = loadEnv(BOX_ENV_KEYS);
const box = openBox(env, boxSshOptions({ connectTimeout: 20 }));
// Asked once more, just before the login: the build took minutes, and it may have been released by someone else
// since this started.
{
  const now = await liveRelease();
  if (now && now.version === versionName && !args.includes('--again')) fail(`${versionName} was released while this was being made (code ${now.versionCode}, published ${now.build ?? 'just now'}). Nothing was sent.`);
}
say('> Logging in to the box');
box.logIn();
const STAGE = '/tmp/ghost-messaging-stage';
box.ssh(`rm -rf ${STAGE} && mkdir -p ${STAGE}`);
say(`> Uploading (${(info.bytes / 1e6).toFixed(1)} MB)`);
box.rsync(['--progress'], join(out, APK), `${STAGE}/${APK}`);
box.rsync([], join(out, 'apk.json'), `${STAGE}/apk.json`);
say('> Publishing');
// The APK first, whole, by rename; apk.json last, so no installed copy is told of an APK still arriving. The live
// files are kept outside the web root first.
box.ssh(`set -e
SUDO=; [ "$(id -u)" -eq 0 ] || SUDO=sudo
[ "$(sha256sum ${STAGE}/${APK} | cut -d' ' -f1)" = "${info.sha256}" ] || { echo "x the APK arrived changed"; exit 1; }
stamp=$(date -u +%Y%m%d%H%M%S)
$SUDO mkdir -p ${RELEASE} ${BACKUPS}
if [ -f ${RELEASE}/apk.json ]; then $SUDO mkdir -p ${BACKUPS}/before-$stamp && $SUDO cp -p ${RELEASE}/* ${BACKUPS}/before-$stamp/; fi
$SUDO install -m 644 -o root -g root ${STAGE}/${APK} ${RELEASE}/.${APK}.new
$SUDO mv -f ${RELEASE}/.${APK}.new ${RELEASE}/${APK}
$SUDO install -m 644 -o root -g root ${STAGE}/apk.json ${RELEASE}/.apk.json.new
$SUDO mv -f ${RELEASE}/.apk.json.new ${RELEASE}/apk.json
$SUDO chmod 755 ${RELEASE}
rm -rf ${STAGE}
echo "ok placed in ${RELEASE}"`);

// Is it served? ghost-sms.com's block reads the folder it was put in. Where it answers otherwise, the block is shown:
// before tool/deploy-site.mjs --caddy has run once there is none, and the release waits in its folder.
const res = await fetch(`${HOST_URL}/apk.json?t=${Date.now()}`, { cache: 'no-store' }).catch((e) => ({ ok: false, status: e.message }));
const said = res.ok ? await res.json().catch(() => null) : null;
if (said?.sha256 !== info.sha256) {
  say(`x ${HOST_URL}/apk.json answered ${res.status}, not this release. The release is in ${RELEASE} on the box.`);
  say('  If ghost-sms.com has no Caddy block yet: node tool/deploy-site.mjs --caddy. Its block, for a look:');
  box.ssh(`grep -n -A25 '^ghost-sms.com' /etc/caddy/Caddyfile || echo "(none)"`);
  if (!keepConnection) box.close();
  process.exit(1);
}
if (!keepConnection) box.close();
const head = await fetch(`${HOST_URL}/${APK}`, { method: 'HEAD' });
say(`ok live: ${HOST_URL}/ — Ghost Messaging ${info.version}, APK served at ${head.headers.get('content-length')} bytes (${info.bytes} expected)`);
