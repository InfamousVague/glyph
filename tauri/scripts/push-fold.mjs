#!/usr/bin/env node
/**
 * Build a debug APK and put it on the Fold over Wi-Fi.
 *
 * The phone advertises Android's wireless debugging as an mDNS service
 * (_adb-tls-connect._tcp) whose PORT changes every time the feature is toggled
 * or the phone reboots, so nothing here is hard-coded: the script asks adb's
 * mDNS resolver for the current address, connects, builds, installs, launches.
 * Pairing is a one-time, on-phone step (Settings > Developer options >
 * Wireless debugging > Pair device with pairing code) and is deliberately NOT
 * automated - it needs a code read off the screen.
 *
 * Usage:
 *   node scripts/push-fold.mjs            # discover, build, install, launch
 *   node scripts/push-fold.mjs --no-build # reinstall the last APK
 *   GLYPH_DEVICE=192.168.1.20:38081 node scripts/push-fold.mjs   # skip discovery
 *
 * Only the arm64 slice is built: the Fold is arm64 and a universal APK
 * quadruples the Rust compile for nothing.
 */
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { ROOT } from './lib/paths.mjs';
import { fatal, say } from './lib/say.mjs';

const SDK = process.env.ANDROID_HOME ?? join(homedir(), 'Library/Android/sdk');
const ADB = join(SDK, 'platform-tools/adb');
const APP_ID = 'com.mattssoftware.glyph';
// `--no-launch` installs without bringing Glyph to the front, for when the phone
// is in use: an install that pops an app over navigation is not a neutral act.
const launch = !process.argv.includes('--no-launch');
const ACTIVITY = `${APP_ID}/.MainActivity`;

// The same toolchain pins the android:* scripts in package.json use, so a
// build from here and a build from npm agree on the JDK and the NDK.
const env = {
  ...process.env,
  ADB_MDNS_OPENSCREEN: '1',
  JAVA_HOME: process.env.JAVA_HOME ?? '/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home',
  ANDROID_HOME: SDK,
  NDK_HOME: process.env.NDK_HOME ?? join(SDK, 'ndk/26.3.11579264'),
};

const adb = (...args) => execFileSync(ADB, args, { env, encoding: 'utf8' }).trim();

// ---- 1. find the phone ------------------------------------------------------
/*
 * The phone stops advertising over mDNS whenever its screen is off, but the
 * port it was last reachable on usually still works - so a remembered address
 * is tried before giving up, and only a failure on BOTH is worth stopping for.
 * Wireless debugging does pick a new port when it is toggled or the phone
 * reboots, which is why the remembered value is a fallback rather than the
 * first choice.
 */
const LAST_ADDRESS = join(ROOT, 'node_modules', '.glyph-fold');

function remembered() {
  try {
    return readFileSync(LAST_ADDRESS, 'utf8').trim() || null;
  } catch {
    return null;
  }
}

function advertised() {
  // adb's own resolver, with the OpenScreen backend that actually finds
  // Samsung phones (the default one came back empty on this network).
  const lines = adb('mdns', 'services').split('\n');
  const hit = lines.map((l) => l.trim().split(/\s+/)).find((cols) => cols[1] === '_adb-tls-connect._tcp');
  return hit ? hit[2] : null;
}

/**
 * The same question, asked of macOS's own Bonjour daemon instead of adb's.
 *
 * Needed because adb's resolver is not reliable, and measurably so: on
 * 2026-09-12 it reported nothing while `dns-sd` on the same Mac, in the same
 * second, saw the Fold advertising and resolved its port. mDNSResponder is the
 * thing every other app on the Mac trusts for `.local`, so it is the better
 * witness. `dns-sd` never exits on its own - it is a live browser - so each
 * call is given a timeout, and `spawnSync` still hands back everything it
 * printed before being killed.
 *
 * Three steps because Bonjour hands them out separately: browse for instance
 * names, look an instance up for its host and port, then resolve that host to
 * an IPv4 address. The address is preferred over the `.local` name because the
 * adb daemon does its own name resolution and has been the unreliable party.
 */
function bonjour() {
  if (process.platform !== 'darwin') return null;
  const ask = (args) => spawnSync('dns-sd', args, { encoding: 'utf8', timeout: 3000 }).stdout ?? '';
  const browse = ask(['-B', '_adb-tls-connect._tcp', 'local.']);
  const names = [...browse.matchAll(/\sAdd\s.*_adb-tls-connect\._tcp\.\s+(\S+)\s*$/gm)].map((m) => m[1]);
  for (const name of names) {
    const found = /can be reached at (\S+?)\.?:(\d+)/.exec(ask(['-L', name, '_adb-tls-connect._tcp', 'local.']));
    if (!found) continue;
    const [, host, port] = found;
    const ip = /\s(\d{1,3}(?:\.\d{1,3}){3})\s/.exec(ask(['-G', 'v4', host]))?.[1];
    return `${ip ?? host}:${port}`;
  }
  return null;
}

/**
 * Connect, restarting the adb daemon once if it has gone blind.
 *
 * "No route to host" from `adb connect` while the port is demonstrably open is
 * not a network fault. The adb SERVER is a long-lived background daemon
 * started by whichever process first ran adb, possibly hours earlier and from
 * a different context, and on macOS a daemon can lose local-network access
 * that the shell running this script still has: `nc` reached the Fold's port
 * in the same second that adb reported no route. Killing the daemon makes the
 * next adb call start a fresh one from here, which inherits working access.
 */
let restarted = false;
function connect(candidate) {
  if (!candidate) return false;
  const attempt = () => {
    const result = spawnSync(ADB, ['connect', candidate], { env, encoding: 'utf8' });
    return `${result.stdout}${result.stderr}`;
  };
  let output = attempt();
  if (/No route to host/i.test(output) && !restarted) {
    restarted = true;
    say('adb daemon cannot reach the network; restarting it');
    spawnSync(ADB, ['kill-server'], { env });
    spawnSync(ADB, ['start-server'], { env });
    output = attempt();
  }
  return /connected|already/.test(output);
}

// Cheapest and most specific first. Bonjour is asked even when adb's own
// resolver answered, because the two can disagree about the current port after
// wireless debugging is toggled, and a stale answer from adb just fails.
const candidates = [
  ...new Set([process.env.GLYPH_DEVICE, advertised(), bonjour(), remembered()].filter(Boolean)),
];
const address = candidates.find(connect);
if (!address) {
  fatal(
    'could not reach the phone.\n' +
      `  tried: ${candidates.length ? candidates.join(', ') : '(nothing advertised, nothing remembered)'}\n` +
      '  On the Fold: wake the screen, then Settings > Developer options > Wireless debugging (on),\n' +
      '  on the same Wi-Fi as this Mac. Pair once if this Mac is new to it.',
  );
}
say(`phone at ${address}`);
try {
  writeFileSync(LAST_ADDRESS, address);
} catch {
  // Remembering is a convenience; failing to is not worth stopping a push.
}
const state = spawnSync(ADB, ['-s', address, 'get-state'], { env, encoding: 'utf8' });
if (state.stdout.trim() !== 'device') {
  fatal(
    `the phone is reachable but not authorised (${(state.stderr || state.stdout).trim()}).\n` +
      'Pair once: Wireless debugging > Pair device with pairing code, then\n' +
      `  ${ADB} pair <ip:pairing-port> <code>`,
  );
}
say(`${adb('-s', address, 'shell', 'getprop', 'ro.product.model')} on Android ${adb('-s', address, 'shell', 'getprop', 'ro.build.version.release')}`);

// ---- 2. build ---------------------------------------------------------------
if (!process.argv.includes('--no-build')) {
  say('building arm64 debug APK');
  // Delete the previous APK first: Gradle rewrites it in place without
  // truncating, so a smaller build keeps the old build's bytes on the end.
  rmSync(join(ROOT, 'src-tauri/gen/android/app/build/outputs/apk'), { recursive: true, force: true });
  const build = spawnSync(
    'npx',
    ['tauri', 'android', 'build', '--debug', '--apk', '--target', 'aarch64'],
    { cwd: ROOT, env, stdio: 'inherit' },
  );
  if (build.status !== 0) fatal('the Android build failed; see above');
}

// ---- 3. install + launch ----------------------------------------------------
// Tauri names the APK after the target set it was built for, and that name has
// drifted between CLI versions - so take the newest .apk under the debug
// output rather than guessing a filename.
const outputs = join(ROOT, 'src-tauri/gen/android/app/build/outputs/apk');
function newestApk(dir) {
  if (!existsSync(dir)) return null;
  let best = null;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      const inner = newestApk(full);
      if (inner && (!best || inner.mtime > best.mtime)) best = inner;
    } else if (entry.name.endsWith('.apk') && full.includes('debug')) {
      const mtime = statSync(full).mtimeMs;
      if (!best || mtime > best.mtime) best = { path: full, mtime };
    }
  }
  return best;
}
const apk = newestApk(outputs);
if (!apk) fatal(`no debug APK under ${outputs}`);
say(`installing ${apk.path.replace(ROOT + '/', '')}`);
// -r keeps the app's data across reinstalls so a tester's notes survive a
// new build; -d allows a downgrade so an older branch can be pushed too.
const install = spawnSync(ADB, ['-s', address, 'install', '-r', '-d', apk.path], { env, stdio: 'inherit' });
if (install.status !== 0) fatal('adb install failed');
/*
 * WAIT FOR THE UPDATE TO SETTLE BEFORE LAUNCHING. `adb install` returns while
 * the package manager is still finishing the replace, and the tail of that work
 * - the "package replaced" broadcast - force-stops the app. Launched straight
 * after install, Glyph started, drew its first frame, and was stopped and
 * destroyed half a second later with a clean exit code; the log showed
 * `onPackageReplaced` landing 0.7 s after the launch (measured on the Fold,
 * 2026-09-12). It looked exactly like a crash on startup and was not one.
 * So: pause, launch, and confirm the process is still alive a moment later,
 * relaunching once if the update took the first attempt.
 */
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const alive = () => spawnSync(ADB, ['-s', address, 'shell', 'pidof', APP_ID], { env, encoding: 'utf8' }).stdout.trim() !== '';
await pause(2500);
if (!launch) {
  say(`installed ${APP_ID} (not launched)`);
  process.exit(0);
}
adb('-s', address, 'shell', 'am', 'start', '-n', ACTIVITY);
await pause(2500);
if (!alive()) {
  say('the update closed the first launch; launching again');
  adb('-s', address, 'shell', 'am', 'start', '-n', ACTIVITY);
  await pause(2500);
}
say(alive() ? `launched ${APP_ID}` : `installed, but ${APP_ID} did not stay running - check \`adb logcat -b crash\``);
