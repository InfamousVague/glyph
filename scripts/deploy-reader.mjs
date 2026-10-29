#!/usr/bin/env node
/**
 * Publishes the reader page alone: read.html, the page a share link opens (tauri/src/read, docs/SHARING.md), and the
 * scripts, styles and fonts it loads, into the release directory ghostmarkdown.com/read.html and attack.fm/glyph/read.html
 * are served from. Written for the shared meeting's page (Matt, 2026-10-29: "Update the web version of the meeting
 * transcripts to include the casette tape and the per user transcript so we can listen along").
 *
 *   cd tauri && npm run build            the reader is built with the Tauri page, into tauri/dist
 *   node scripts/deploy-reader.mjs --dry-run      what it would send, logging in nowhere
 *   node scripts/deploy-reader.mjs --print        the script the box would run, logging in nowhere
 *   node scripts/deploy-reader.mjs [--keep-connection]
 *
 * Why not tauri/scripts/deploy-ota.mjs, which used to publish it: that deploy puts the whole Tauri build over the
 * release directory with rsync --delete, and the release directory has held the Flutter web app since 2026-10-26
 * (scripts/deploy-flutter-web.mjs), which it would delete. This sends only what read.html needs:
 *
 * - **Added, never deleted or replaced.** Every file read.html reaches - its entry script, the chunks that imports,
 *   their styles and fonts - found by following the names from read.html through each file, all hashed by Vite, so
 *   a name already on the box is the same bytes and is left as it is. Nothing else in assets/, and nothing the release
 *   directory keeps for others (the Flutter page, the downloads, the manifests), is touched.
 * - **read.html last, by rename**, once every file it names is in place: a reader never gets a page whose scripts are
 *   still arriving. The old read.html is kept beside it as read.html.before-<login stamp>.
 *
 * Refused: a build that talks to any service but ghostmarkdown.com/api (a browser-pane build against a local address
 * is never published), and a tree that does not hold everything origin/main has.
 *
 * ONE LOGIN (tauri/scripts/lib/box.mjs), or none after a deploy that kept its connection; --keep-connection keeps this
 * one open for the next. The box allows three logins an hour, ten minutes apart: batch this with the other deploys.
 */
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { BOX_ENV_KEYS, boxSshOptions, openBox } from '../tauri/scripts/lib/box.mjs';
import { loadEnv } from './lib/env.mjs';
import { ROOT, TAURI } from './lib/paths.mjs';
import { fail } from '../tauri/scripts/lib/say.mjs';

const RELEASE = '/opt/attackfm-site/glyph';
const SITE = 'https://ghostmarkdown.com/';
const API = 'https://ghostmarkdown.com/api';
const DIST = join(TAURI, 'dist');
const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const printOnly = args.includes('--print');
const keepConnection = args.includes('--keep-connection');
const step = (words) => console.log(`> ${words}`);
const note = (words) => console.log(`   ${words}`);
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const git = (gitArgs) => spawnSync('git', gitArgs, { cwd: ROOT, encoding: 'utf8' });
const curl = (curlArgs) => spawnSync('curl', ['-s', '--max-time', '30', ...curlArgs], { encoding: 'utf8' });

// ---- what is to be sent -----------------------------------------------------------------------------------------

if (!existsSync(join(DIST, 'read.html'))) fail('No tauri/dist/read.html: run `npm run build` in tauri/ first.');
const page = readFileSync(join(DIST, 'read.html'), 'utf8');
const assets = readdirSync(join(DIST, 'assets'));
// Every file read.html reaches, following names through each file reached.
const reached = new Set();
const queue = [page];
while (queue.length) {
  const text = queue.shift();
  for (const name of assets) {
    if (reached.has(name) || !text.includes(name)) continue;
    reached.add(name);
    if (/\.(js|css|mjs)$/.test(name)) queue.push(readFileSync(join(DIST, 'assets', name), 'utf8'));
  }
}
const files = [...reached].sort();
const entry = /src="\.?\/?assets\/(read-[^"]+\.js)"/.exec(page)?.[1];
const problems = [];
if (!entry || !reached.has(entry)) problems.push('read.html names no assets/read-*.js entry.');
const scripts = files.filter((name) => name.endsWith('.js')).map((name) => readFileSync(join(DIST, 'assets', name), 'utf8')).join('\n');
if (!scripts.includes(API)) problems.push(`the reader does not talk to ${API}.`);
if (/https?:\/\/(127\.0\.0\.1|localhost)(:\d+)?\/api/.test(scripts)) problems.push('the reader was built against a local service (VITE_GLYPH_API): build again without it.');
git(['fetch', '-q', 'origin', 'main']);
if (git(['merge-base', '--is-ancestor', 'origin/main', 'HEAD']).status !== 0) problems.push('this tree does not have everything origin/main has: merge it, build again, and then publish.');
const dirty = git(['status', '--porcelain', '--', 'tauri/src', 'tauri/read.html', 'tauri/vendor']).stdout.trim();
if (dirty) problems.push(`tauri/ has changes that are not committed, so the build is not the commit:\n${dirty}`);
const bytes = files.reduce((sum, name) => sum + readFileSync(join(DIST, 'assets', name)).length, 0);

step(`The reader page: read.html and ${files.length} files it loads (${(bytes / 1e6).toFixed(1)} MB), entry assets/${entry}`);
note(`to ${RELEASE}/assets, added where they are not there; nothing deleted, nothing else touched`);
note('read.html last, by rename; the old one kept as read.html.before-<login stamp>');
if (problems.length && !printOnly) {
  for (const problem of problems) console.log(`x ${problem}`);
  if (dryRun) process.exit(1);
  fail('Not published: the lines above say why.');
}

// ---- the box's half ---------------------------------------------------------------------------------------------

const STAGE = '/tmp/ghostmd-reader-stage';
const REMOTE = `set -e
SUDO=; [ "$(id -u)" -eq 0 ] || SUDO=sudo
stamp=$(date -u +%Y%m%d-%H%M%S)
[ "$(sha256sum ${STAGE}/read.html | cut -d' ' -f1)" = "${sha256(page)}" ] || { echo "x read.html arrived changed"; exit 1; }
$SUDO mkdir -p ${RELEASE}/assets
# Every file read.html loads, where it is not there already: Vite's names are its bytes' hashes.
$SUDO rsync -a --ignore-existing ${STAGE}/assets/ ${RELEASE}/assets/
$SUDO chown root:root ${files.map((name) => `${RELEASE}/assets/${name}`).join(' ')}
$SUDO chmod 644 ${files.map((name) => `${RELEASE}/assets/${name}`).join(' ')}
# The page, last.
[ ! -f ${RELEASE}/read.html ] || $SUDO cp -a ${RELEASE}/read.html ${RELEASE}/read.html.before-$stamp
ls -1t ${RELEASE}/read.html.before-* 2>/dev/null | tail -n +4 | xargs -r $SUDO rm -f
$SUDO install -m 644 -o root -g root ${STAGE}/read.html ${RELEASE}/.read.html.new
$SUDO mv -f ${RELEASE}/.read.html.new ${RELEASE}/read.html
rm -rf ${STAGE}
echo "ok published; the old page is read.html.before-$stamp (login $stamp)"`;

if (printOnly) {
  process.stdout.write(`${REMOTE}\n`);
  process.exit(0);
}
if (dryRun) {
  for (const name of files) note(`assets/${name}`);
  console.log('\n--dry-run: nothing was sent anywhere (--print for the box\'s script).');
  process.exit(0);
}

// ---- publish: one login -----------------------------------------------------------------------------------------

const env = loadEnv(BOX_ENV_KEYS);
const box = openBox(env, boxSshOptions({ connectTimeout: 20 }));
step('Logging in to the box');
box.logIn();
box.ssh(`rm -rf ${STAGE} && mkdir -p ${STAGE}/assets`);
step('Uploading');
box.rsync(['-az', ...files.map((name) => `--include=/assets/${name}`), '--include=/assets/', '--include=/read.html', '--exclude=*'], `${DIST}/`, `${STAGE}/`);
step('Publishing');
const said = box.ssh(REMOTE, { capture: true });
console.log(said.split('\n').map((line) => `   ${line}`).join('\n'));
if (!keepConnection) box.close();

// ---- prove it ---------------------------------------------------------------------------------------------------

step('Checking it from outside');
const live = String(curl([`${SITE}read.html`]).stdout ?? '');
if (!live.includes(entry)) fail(`${SITE}read.html does not load assets/${entry}.`);
for (const name of files) {
  const code = String(curl(['-o', '/dev/null', '-w', '%{http_code}', `${SITE}assets/${name}`]).stdout).trim();
  if (code !== '200') fail(`${SITE}assets/${name} answered ${code}.`);
}
console.log(`ok ${SITE}read.html is the new reader, and every file it loads answers`);
