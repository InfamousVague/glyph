#!/usr/bin/env node
/**
 * Publishes Ghost.md's web version: the Flutter app compiled to WebAssembly (tool/build-web.sh, docs/WEB.md), in place
 * of the Tauri app's page at attack.fm/glyph/, which had stood still since the cut-over (Matt, 2026-10-26: "update
 * the web version of the app it's very behind").
 *
 *   node scripts/deploy-flutter-web.mjs --dry-run         what it would change, logging in nowhere
 *   node scripts/deploy-flutter-web.mjs --print           the script the box would run, logging in nowhere
 *   node scripts/deploy-flutter-web.mjs [--caddy] [--keep-connection]
 *
 * Build first, from a tree that has everything main has: `GHOST_WEB_VERSION=2.3.36 tool/build-web.sh`. The build is
 * refused if it was made from other code than this tree's, against any service but ghostmarkdown.com/api, under any
 * address but /glyph/, without a version, or with a browser's core older than the Rust it is built from.
 *
 * WHAT IT CHANGES on the box, in /opt/attackfm-site/glyph (the release directory tauri/scripts/deploy-ota.mjs
 * publishes the old page to, which the landing page's downloads and the reader page for shared notes are served
 * from too):
 *
 * - **The page's files are added or replaced, and nothing is deleted.** No `--delete`: the APK, the Mac's image and
 *   zip, the Windows installer, every manifest and signature (apk.json, mac.json, desktop.json, windows.json,
 *   ota.json, changelog.json), the Whisper weights in models/, Claude's connector in mcp/, install.html, read.html
 *   and the assets/ the reader page and an installed Tauri app's update read, all stay exactly as they are. The
 *   build is checked to name none of them before anything is sent.
 * - **index.html goes in last**, by rename, after every file it names is in place, so a visitor never gets a page
 *   whose files are still arriving.
 * - **The old page's entry script is replaced by a stub** (the `<script src>` the live index.html names, read from
 *   the live page before the publish): a browser that kept the old index.html and asks for its script gets one that
 *   lets go of any service worker and cache the page left, and loads the page again, which is then the new one. The
 *   old page had no service worker (it registers none; checked 2026-10-26); the new one registers none either, and
 *   lets go of any it finds under /glyph/ (web/flutter_bootstrap.js). The reader page's own scripts are not touched.
 *   An installed Tauri app's over-the-air update listed that script too: its signature check now refuses that
 *   bundle and the app keeps the one it has, which is what the Flutter app's APK and Mac app replace anyway.
 * - **With --caddy, index.html and every file under /glyph/ are served no-cache** (none of Flutter's file names
 *   change from build to build: main.dart.wasm, main.dart.mjs, the core), by a rule added once to attack.fm's block
 *   in the shared Caddyfile: `header @ghostweb ?Cache-Control "no-cache"`, for /glyph/* but /glyph/api/* and
 *   /glyph/mcp/*, and only where a response has no Cache-Control of its own. The Caddyfile is shared (attack.fm,
 *   the registry, prettycardboard.com, ghostmarkdown.com), so this is deploy-landing.mjs --caddy's procedure: a
 *   timestamped backup, every site asked for its page before and after, `caddy validate`, and the backup put back on
 *   any difference. Without --caddy, the live page's Cache-Control is read after the publish and said.
 *
 * ONE LOGIN (tauri/scripts/lib/box.mjs): the backup, the upload and the publish ride one shared connection, and the
 * login's stamp names the backup (`glyph.web-before-<stamp>`, the three newest kept), so the time of the login is in
 * its name. The box allows three logins an hour, ten minutes apart: batch this with the other deploys.
 *
 * AFTER: everything checked from outside, as a visitor would: the page and its build stamp, the WebAssembly's
 * hashes against the built files and its type (application/wasm, which WebAssembly's streaming compile wants), the
 * old entry answering the stub, and every protected file answering as it did before.
 */
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { BOX_ENV_KEYS, boxSshOptions, openBox } from '../tauri/scripts/lib/box.mjs';
import { loadEnv } from './lib/env.mjs';
import { ROOT } from './lib/paths.mjs';
import { fail } from '../tauri/scripts/lib/say.mjs';

const RELEASE = '/opt/attackfm-site/glyph';
const SITE = 'https://attack.fm/glyph/';
const API = 'https://ghostmarkdown.com/api';
const BASE = '/glyph/';
const WEB = join(ROOT, 'build/web');
const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const printOnly = args.includes('--print');
const withCaddy = args.includes('--caddy');
const keepConnection = args.includes('--keep-connection');
const ok = (words) => console.log(`ok ${words}`);
const step = (words) => console.log(`> ${words}`);
const note = (words) => console.log(`   ${words}`);

/**
 * What the release directory holds that is not the page's, at its top: never in the build, never written, never
 * deleted. The old deploy's --delete filters and excludes named these (tauri/scripts/deploy-ota.mjs), and the
 * Flutter deploys and the landing page's Caddy block name the rest.
 */
const PROTECTED = [
  'models', 'mcp', 'download',
  'glyph.apk', 'apk.json', 'apk.json.sig', 'apk.json.flutter.sig',
  'glyph.dmg', 'glyph-mac.zip', 'desktop.json', 'mac.json', 'mac.json.sig',
  'glyph-setup.exe', 'windows.json',
  'ota.json', 'ota.json.sig', 'changelog.json', 'install.html',
  'read.html', 'favicon.svg', 'apple-touch-icon.png', 'glyph-mcp.mjs',
];

/** What a live check compares before and after: each answers as it did. The reader page's scripts are added once read. */
const WATCHED = ['apk.json', 'mac.json', 'desktop.json', 'windows.json', 'ota.json', 'changelog.json', 'install.html', 'read.html', 'favicon.svg'];

/** The stub an old page's kept index.html loads in place of its own script. */
const OLD_ENTRY_STUB = `// ghost-old-page: Ghost.md's web version is the new one now (scripts/deploy-flutter-web.mjs, docs/WEB.md). This was
// the old page's own script, asked for by a copy of its index.html the browser kept: it lets go of whatever that page
// left, and loads the address again, which answers the new page.
(async () => {
  try {
    for (const one of (await navigator.serviceWorker?.getRegistrations?.()) ?? []) await one.unregister();
  } catch (_) {}
  try {
    if ('caches' in self) for (const name of await caches.keys()) await caches.delete(name);
  } catch (_) {}
  const once = 'ghost-old-page-reloaded';
  let again = true;
  try {
    again = !sessionStorage.getItem(once);
    sessionStorage.setItem(once, String(Date.now()));
  } catch (_) {}
  if (again) location.reload();
  else document.body.textContent = 'Ghost.md has a new web version. Reload this page to open it.';
})();
`;

// ---- what is to be shipped -------------------------------------------------------------------------------------

const problems = [];
const refuse = (words) => problems.push(words);
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const git = (gitArgs) => spawnSync('git', gitArgs, { cwd: ROOT, encoding: 'utf8' });

function filesUnder(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) out.push(...filesUnder(full));
    else out.push(relative(WEB, full));
  }
  return out;
}

if (!existsSync(join(WEB, 'index.html'))) fail('No build/web: run GHOST_WEB_VERSION=<version> tool/build-web.sh first.');
// Flutter's own note of its last build is not the page's.
const files = filesUnder(WEB).filter((file) => file !== '.last_build_id').sort();
const bytes = files.reduce((sum, file) => sum + statSync(join(WEB, file)).size, 0);
let stamp = {};
try {
  stamp = JSON.parse(readFileSync(join(WEB, 'ghost-build.json'), 'utf8'));
} catch {
  refuse('build/web has no ghost-build.json: it was not made by tool/build-web.sh.');
}
if (stamp.api !== API) refuse(`build/web talks to ${stamp.api ?? 'an unknown service'}, not ${API}: a build for the browser pane (a dead address) is never published.`);
if (stamp.base !== BASE) refuse(`build/web is built for ${stamp.base ?? 'an unknown base'}, not ${BASE}.`);
if (!/^\d+\.\d+\.\d+$/.test(stamp.version ?? '')) refuse(`build/web has no version (About would say pubspec's 0.1.0): build with GHOST_WEB_VERSION=<version>.`);
const head = git(['rev-parse', 'HEAD']).stdout.trim();
if (stamp.commit !== head) refuse(`build/web was built from ${String(stamp.commit).slice(0, 8)}, and this tree is at ${head.slice(0, 8)}: build again.`);
const dirty = git(['status', '--porcelain', '--', 'lib', 'web', 'native', 'pubspec.yaml', 'pubspec.lock', 'assets', 'shaders', 'packages', 'tauri/src-tauri/src']).stdout.trim();
if (dirty) refuse(`the tree has changes that are not committed, so the build is not the commit it says:\n${dirty}`);
// The deploy ships the whole tree: it must hold everything main has (memory: an OTA from a worktree clobbered other branches).
git(['fetch', '-q', 'origin', 'main']);
if (git(['merge-base', '--is-ancestor', 'origin/main', 'HEAD']).status !== 0) refuse('this tree does not have everything origin/main has: merge it, build again, and then publish.');
const index = readFileSync(join(WEB, 'index.html'), 'utf8');
if (!index.includes(`<base href="${BASE}">`)) refuse(`build/web/index.html does not say <base href="${BASE}">.`);
for (const needed of ['main.dart.wasm', 'main.dart.mjs', 'main.dart.js', 'flutter_bootstrap.js', 'core/ghost_core_web.wasm', 'core/ghost_core_worker.js', 'core/ghost_core_wasi.js']) {
  if (!files.includes(needed)) refuse(`build/web has no ${needed}.`);
}
const bootstrap = existsSync(join(WEB, 'flutter_bootstrap.js')) ? readFileSync(join(WEB, 'flutter_bootstrap.js'), 'utf8') : '';
// Flutter's loader is inlined above the page's own lines, and names the setting itself: what is asked is the call.
if (/serviceWorkerSettings/.test(bootstrap.slice(bootstrap.lastIndexOf('_flutter.loader.load(')))) refuse('build/web/flutter_bootstrap.js registers Flutter\'s service worker: web/flutter_bootstrap.js must be the one built.');
// The browser's core is the Rust's own: newer than every file it is built from, and the copy web/core/ holds.
const core = join(WEB, 'core/ghost_core_web.wasm');
if (existsSync(core)) {
  const built = statSync(core).mtimeMs;
  const sources = ['native/web/src/lib.rs', 'native/web/src/ffi.rs', 'native/web/src/paths.rs', 'native/web/Cargo.toml', 'native/src/crypto.rs', 'native/src/crdt.rs', 'native/src/crdt_wire.rs', 'tauri/src-tauri/src/note.rs', 'tauri/src-tauri/src/lock.rs', 'tauri/src-tauri/src/library/names.rs'];
  for (const source of sources) {
    if (statSync(join(ROOT, source)).mtimeMs > built) refuse(`${source} is newer than the browser's core in build/web: run tool/build-web.sh again.`);
  }
  if (existsSync(join(ROOT, 'web/core/ghost_core_web.wasm')) && sha256(readFileSync(core)) !== sha256(readFileSync(join(ROOT, 'web/core/ghost_core_web.wasm')))) {
    refuse('build/web\'s core is not web/core\'s: run tool/build-web.sh again.');
  }
}
const named = files.filter((file) => PROTECTED.includes(file.split('/')[0]));
if (named.length) refuse(`build/web names what the release directory keeps for others: ${named.join(', ')}.`);
const hashes = Object.fromEntries(['main.dart.wasm', 'core/ghost_core_web.wasm', 'main.dart.mjs'].filter((f) => files.includes(f)).map((f) => [f, sha256(readFileSync(join(WEB, f)))]));

// ---- the live page, read as a visitor reads it (no login) ----------------------------------------------------------

const curl = (curlArgs, options = {}) => spawnSync('curl', ['-s', '--max-time', '30', ...curlArgs], { encoding: options.binary ? 'buffer' : 'utf8', maxBuffer: 64 * 1024 * 1024 });
const liveIndex = String(curl([SITE]).stdout ?? '');
// The old page's entry scripts: what the live page names, while it is the old page, and the one it named when it was
// retired (2026-10-26, for a placeholder that names none). The box stubs every assets/index-*.js it holds that the
// reader page does not load (REMOTE below); these are the ones checked from outside after.
const KNOWN_OLD_ENTRIES = ['assets/index-DRvGB95l.js'];
const oldEntries = [...new Set([...KNOWN_OLD_ENTRIES, ...[...liveIndex.matchAll(/<script[^>]*\bsrc="\.?\/?(assets\/index-[A-Za-z0-9_-]+\.js)"/g)].map((m) => m[1])])];
const liveIsFlutter = liveIndex.includes('flutter_bootstrap.js');
const readerScripts = [...String(curl([`${SITE}read.html`]).stdout ?? '').matchAll(/(?:src|href)="\.?\/?(assets\/[^"]+\.(?:js|css))"/g)].map((m) => m[1]);
const watched = [...WATCHED, ...readerScripts];
if (oldEntries.some((entry) => readerScripts.includes(entry))) refuse(`the old page's entry ${oldEntries.join(', ')} is one the reader page loads too: it is not stubbed by this script; look first.`);
const before = Object.fromEntries(watched.map((file) => {
  const answer = curl(['-o', '-', '-w', '\n%{http_code}', `${SITE}${file}`], { binary: true });
  const all = answer.stdout ?? Buffer.alloc(0);
  const cut = all.lastIndexOf(10);
  return [file, { code: all.subarray(cut + 1).toString(), sha: sha256(all.subarray(0, Math.max(cut, 0))) }];
}));

// ---- the plan ---------------------------------------------------------------------------------------------------

const groups = {};
for (const file of files) {
  const group = file.includes('/') ? `${file.split('/')[0]}/` : file;
  groups[group] = (groups[group] ?? 0) + 1;
}
step(`Ghost.md ${stamp.version ?? '?'} for the web, built ${stamp.built ?? '?'} from ${String(stamp.commit ?? '?').slice(0, 10)}: ${files.length} files, ${(bytes / 1e6).toFixed(1)} MB`);
note(`to ${RELEASE} (${SITE}), added or replaced, nothing deleted:`);
for (const [group, count] of Object.entries(groups)) note(`  ${group.padEnd(28)} ${count === 1 ? '' : `${count} files`}`);
note('  index.html                   last, by rename');
const livePage = liveIsFlutter ? 'the Flutter page already' : /old web version .* is retired/s.test(liveIndex) ? 'the placeholder that retired the old page' : 'the old Tauri page';
note(`the live page is ${livePage}; every assets/index-*.js the old page left (${oldEntries.join(', ')}) becomes the stub that loads the new page`);
note(`kept as they are (protected): ${PROTECTED.join(', ')}, and assets/'s other files`);
note(`checked unchanged after: ${watched.join(', ')}`);
note(`backed up first: ${RELEASE} to ${RELEASE}.web-before-<login stamp>, without models/ and the downloads (the three newest kept)`);
note(withCaddy ? 'and attack.fm\'s Caddy block gets the no-cache rule for /glyph/* (backup, validate, every site before and after)' : 'the Caddyfile is not touched (--caddy adds the no-cache rule)');
const liveCache = String(curl(['-sI', SITE]).stdout ?? '').match(/^cache-control:\s*(.+)$/im)?.[1]?.trim();
note(`the page is served now with Cache-Control: ${liveCache ?? 'none (a browser may keep it a while by its age)'}`);

if (problems.length && !printOnly) {
  console.log('');
  for (const problem of problems) console.log(`x ${problem}`);
  if (dryRun) {
    console.log(`\n${problems.length} ${problems.length === 1 ? 'thing stops' : 'things stop'} this build from being published; nothing was sent anywhere.`);
    process.exit(1);
  }
  fail('Not published: the lines above say why.');
}

// ---- the box's half ---------------------------------------------------------------------------------------------

const STAGE = '/tmp/ghostmd-flutter-web-stage';
// The stub, over every assets/index-*.js the old page left that the reader page (read.html) does not load.
const stubs = `printf '%s' '${OLD_ENTRY_STUB.replace(/'/g, "'\\''")}' > ${STAGE}.stub
for old in ${RELEASE}/assets/index-*.js; do
  [ -f "$old" ] || continue
  grep -q ghost-old-page "$old" && continue
  grep -q "$(basename "$old")" ${RELEASE}/read.html 2>/dev/null && { echo "   kept $old: the reader page loads it"; continue; }
  $SUDO install -m 644 -o root -g root ${STAGE}.stub "$old.new" && $SUDO mv -f "$old.new" "$old"
  echo "   stubbed $old"
done
rm -f ${STAGE}.stub`;

const CADDY = `CF=/etc/caddy/Caddyfile
if $SUDO grep -q 'ghost-web-no-cache' "$CF"; then
  echo "ok attack.fm's block has the no-cache rule already"
else
  probe() {
    for h in $($SUDO grep -E '^[a-z0-9][a-z0-9.:/, -]*[{]' "$CF" | sed 's/{.*//; s/,/ /g'); do
      h=\${h#http://}; h=\${h#https://}; h=\${h%%:*}
      [ -n "$h" ] || continue
      code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 --resolve "$h:443:127.0.0.1" "https://$h/" || true)
      echo "$h $code"
    done | sort
    echo "attack.fm/glyph/ $(curl -s -o /dev/null -w '%{http_code}' --max-time 10 --resolve attack.fm:443:127.0.0.1 https://attack.fm/glyph/ || true)"
  }
  line=$($SUDO grep -nE '^(https?://)?attack[.]fm([ ,:][^{]*)?[{]' "$CF" | head -1 | cut -d: -f1)
  [ -n "$line" ] || { echo "x no block for attack.fm in $CF: the rule is for Matt to place"; exit 1; }
  BACKUP="$CF.bak-$(date -u +%Y%m%d-%H%M%S)"
  $SUDO cp -a "$CF" "$BACKUP"
  echo "ok backup $BACKUP"
  BEFORE=$(probe)
  restore() { echo "x $1: putting $BACKUP back"; $SUDO cp -a "$BACKUP" "$CF"; $SUDO systemctl reload caddy || true; exit 1; }
  $SUDO awk -v at="$line" 'NR == at {
      print
      print "\\t# ghost-web-no-cache: Ghost.md on the web (scripts/deploy-flutter-web.mjs). Its files keep their names from build to"
      print "\\t# build, so a browser asks again each time; a response that says its own Cache-Control keeps it."
      print "\\t@ghostweb {"
      print "\\t\\tpath /glyph/*"
      print "\\t\\tnot path /glyph/api/* /glyph/mcp/*"
      print "\\t}"
      print "\\theader @ghostweb ?Cache-Control \\"no-cache\\""
      next
    } { print }' "$CF" | $SUDO tee "$CF.next" >/dev/null
  $SUDO cp "$CF.next" "$CF"; $SUDO rm -f "$CF.next"
  $SUDO caddy validate --config "$CF" --adapter caddyfile >/dev/null 2>&1 || restore "caddy validate refused it"
  $SUDO systemctl reload caddy || restore "caddy would not reload"
  sleep 4
  AFTER=$(probe)
  [ "$BEFORE" = "$AFTER" ] || { echo "before:"; echo "$BEFORE"; echo "after:"; echo "$AFTER"; restore "a site answers differently after the reload"; }
  echo "ok attack.fm's block serves /glyph/ no-cache"
fi`;

const REMOTE = `set -e
SUDO=; [ "$(id -u)" -eq 0 ] || SUDO=sudo
stamp=$(date -u +%Y%m%d-%H%M%S)
[ "$(sha256sum ${STAGE}/main.dart.wasm | cut -d' ' -f1)" = "${hashes['main.dart.wasm']}" ] || { echo "x main.dart.wasm arrived changed"; exit 1; }
[ "$(sha256sum ${STAGE}/core/ghost_core_web.wasm | cut -d' ' -f1)" = "${hashes['core/ghost_core_web.wasm']}" ] || { echo "x the core arrived changed"; exit 1; }
# Nothing staged may name what the release directory keeps for others.
for kept in ${PROTECTED.join(' ')}; do [ ! -e "${STAGE}/$kept" ] || { echo "x the stage names $kept"; exit 1; }; done
# What is there now, without the weights and the downloads, which this never touches.
$SUDO rsync -a --exclude '/models/' --exclude '/glyph.apk' --exclude '/glyph.dmg' --exclude '/glyph-mac.zip' --exclude '/glyph-setup.exe' ${RELEASE}/ ${RELEASE}.web-before-$stamp/
ls -1dt ${RELEASE}.web-before-* 2>/dev/null | tail -n +4 | xargs -r $SUDO rm -rf
# Every file but index.html, added or replaced; nothing deleted (no --delete).
$SUDO rsync -a --exclude '/index.html' --exclude '/.last_build_id' ${STAGE}/ ${RELEASE}/
$SUDO chown -R root:root ${RELEASE}
$SUDO find ${RELEASE} -path ${RELEASE}/models -prune -o -type d -exec chmod 755 {} +
$SUDO find ${RELEASE} -path ${RELEASE}/models -prune -o -type f -exec chmod 644 {} +
# The old page's entry, the stub that loads the new page.
${stubs || '# no old entry named by the live page'}
# The page itself, last.
$SUDO install -m 644 -o root -g root ${STAGE}/index.html ${RELEASE}/.index.html.new
$SUDO mv -f ${RELEASE}/.index.html.new ${RELEASE}/index.html
rm -rf ${STAGE}
echo "ok published; what was there is in ${RELEASE}.web-before-$stamp (login $stamp)"
${withCaddy ? CADDY : '# no --caddy: the Caddyfile is not touched'}`;

if (printOnly) {
  process.stdout.write(`${REMOTE}\n`);
  process.exit(0);
}
if (dryRun) {
  console.log('\n--dry-run: nothing was sent anywhere. The box would run (--print for the whole script):');
  for (const line of REMOTE.split('\n').filter((l) => l.trim() && !l.trim().startsWith('#')).slice(0, 14)) note(line);
  process.exit(0);
}

// ---- publish: one login ------------------------------------------------------------------------------------------

const env = loadEnv(BOX_ENV_KEYS);
const box = openBox(env, boxSshOptions({ connectTimeout: 20 }));
step('Logging in to the box');
box.logIn();
box.ssh(`rm -rf ${STAGE} && mkdir -p ${STAGE}`);
step(`Uploading build/web (${(bytes / 1e6).toFixed(1)} MB)`);
box.rsync(['-az', '--delete'], `${WEB}/`, `${STAGE}/`);
step('Publishing');
const said = box.ssh(REMOTE, { capture: true });
console.log(said.split('\n').map((line) => `   ${line}`).join('\n'));
const login = /\(login (\d{8}-\d{6})\)/.exec(said)?.[1] ?? '<stamp>';
if (!keepConnection) box.close();

// ---- prove it ---------------------------------------------------------------------------------------------------

step('Checking it from outside');
const page = String(curl([SITE]).stdout ?? '');
if (!page.includes('flutter_bootstrap.js') || !page.includes(`<base href="${BASE}">`)) fail(`${SITE} does not serve the new page.`);
const liveStamp = JSON.parse(String(curl([`${SITE}ghost-build.json`]).stdout || '{}'));
if (liveStamp.commit !== stamp.commit) fail(`${SITE}ghost-build.json says ${liveStamp.commit}, not ${stamp.commit}.`);
for (const [file, sha] of Object.entries(hashes)) {
  const served = curl([`${SITE}${file}`], { binary: true }).stdout;
  if (sha256(served) !== sha) fail(`${file} is served as ${served.length} bytes that are not the build's.`);
}
const wasmType = String(curl(['-sI', `${SITE}main.dart.wasm`]).stdout ?? '').match(/^content-type:\s*(.+)$/im)?.[1]?.trim();
if (!/application\/wasm/.test(wasmType ?? '')) console.log(`x main.dart.wasm is served as ${wasmType}: WebAssembly's streaming compile wants application/wasm (the page still loads, slower).`);
for (const entry of oldEntries) {
  const answer = curl(['-o', '-', '-w', '\n%{http_code}', `${SITE}${entry}`]);
  const text = String(answer.stdout ?? '');
  if (!text.endsWith('\n404') && !text.includes('ghost-old-page')) fail(`${entry} is not the stub.`);
}
for (const file of watched) {
  const answer = curl(['-o', '-', '-w', '\n%{http_code}', `${SITE}${file}`], { binary: true });
  const all = answer.stdout ?? Buffer.alloc(0);
  const cut = all.lastIndexOf(10);
  const now = { code: all.subarray(cut + 1).toString(), sha: sha256(all.subarray(0, Math.max(cut, 0))) };
  if (now.code !== before[file].code || now.sha !== before[file].sha) fail(`${file} answers differently after the publish (${before[file].code} before, ${now.code} now).`);
}
ok(`${watched.length} files the release directory keeps for others answer as they did`);
const cache = String(curl(['-sI', SITE]).stdout ?? '').match(/^cache-control:\s*(.+)$/im)?.[1]?.trim();
if (cache === 'no-cache') ok('the page is served no-cache');
else console.log(`x the page is served with Cache-Control: ${cache ?? 'none'}: a returning browser may keep the old page for a while by its age (run again with --caddy)`);
ok(`Ghost.md ${stamp.version} is live at ${SITE}`);
// The backup holds no weights and no downloads, so a restore protects them from its --delete, as deploy-ota's does.
console.log(`  rollback: sudo rsync -a --delete --filter 'P /models/' --filter 'P /glyph.apk' --filter 'P /glyph.dmg' --filter 'P /glyph-mac.zip' --filter 'P /glyph-setup.exe' ${RELEASE}.web-before-${login}/ ${RELEASE}/`);
