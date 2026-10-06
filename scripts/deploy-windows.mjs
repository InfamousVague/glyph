#!/usr/bin/env node
/**
 * Publishes Ghost.md for Windows: the installer the Windows runner built (.github/workflows/windows.yml), put beside
 * the Mac app and the APK on the box, with `windows.json` for the download page to read (docs/DESIGN.md §208).
 *
 *   node scripts/deploy-windows.mjs                 the newest green run of the Windows build
 *   node scripts/deploy-windows.mjs --run 123456    that run's installer
 *   node scripts/deploy-windows.mjs --file x.exe    an installer already on this Mac
 *   ... --keep-connection                           leave the box's connection open for the next script
 *
 *   /glyph/glyph-setup.exe   the NSIS installer, x64
 *   /glyph/windows.json      { version, sha256, bytes, url, arch, signed, minimumSystemVersion }
 *
 * A Mac cannot build the Windows app (the speech and language engines are C++ built with MSVC), so nothing here
 * builds: it fetches the run's artifact with `gh`, checks it is a Windows program and whether it carries a signature
 * (a PE file's certificate table, read here, since macOS has no signtool), hashes it, and ships both files in one
 * ssh session. The installer first, the manifest last and by rename, so the page never offers a version whose file is
 * still arriving (deploy-ota.mjs, ORDER IS THE SAFETY).
 *
 * deploy-ota.mjs protects both files from its own `rsync --delete`, as it does the APK and the Mac app; a deploy from
 * a tree older than §208 would delete them, which is one more reason to deploy from main.
 *
 * The box counts connections (deploy-ota.mjs): this rides a connection deploy-ota left open (`--keep-connection`), or
 * spends one of its own.
 */
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { BOX_ENV_KEYS, boxSshOptions, openBox } from './lib/box.mjs';
import { loadEnv } from './lib/env.mjs';
import { readPe, versionIn } from './lib/pe.mjs';
import { fail } from './lib/say.mjs';

const RELEASE = '/opt/attackfm-site/glyph';
const WORKFLOW = 'windows.yml';
const ARTIFACT = 'ghost-md-windows';

const args = process.argv.slice(2);
const valueOf = (flag) => {
  const at = args.indexOf(flag);
  return at >= 0 ? args[at + 1] : null;
};
const keepConnection = args.includes('--keep-connection');

/** `gh`'s answer as text; a failure stops the deploy with what gh said. */
function gh(ghArgs) {
  const result = spawnSync('gh', ghArgs, { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
  if (result.status !== 0) fail(`gh ${ghArgs.join(' ')} failed:\n${result.stderr}`);
  return result.stdout.trim();
}

/** The installer to ship, as a path on this Mac: named, or fetched from a run of the Windows build. */
function installer() {
  const file = valueOf('--file');
  if (file) {
    if (!existsSync(file)) fail(`No file at ${file}.`);
    return file;
  }
  const run = valueOf('--run') ?? gh(['run', 'list', '--workflow', WORKFLOW, '--status', 'success', '--limit', '1', '--json', 'databaseId', '-q', '.[0].databaseId']);
  if (!run) fail(`No green run of ${WORKFLOW} to fetch. Run it (gh workflow run ${WORKFLOW}), or pass --file.`);
  const into = mkdtempSync(join(tmpdir(), 'ghostmd-windows-'));
  console.log(`> Fetching the installer from run ${run}`);
  gh(['run', 'download', String(run), '--name', ARTIFACT, '--dir', into]);
  const found = readdirSync(into).filter((name) => name.toLowerCase().endsWith('.exe'));
  if (found.length !== 1) fail(`Run ${run}'s artifact holds ${found.length} installers, not one: ${found.join(', ') || 'none'}.`);
  return join(into, found[0]);
}

const path = installer();
const bytes = readFileSync(path);
const pe = readPe(bytes);
if (!pe) fail(`${path} is not a Windows program.`);
// An NSIS installer is a 32-bit program whatever it installs: the app's own architecture is in its name.
const name = path.split('/').pop();
const version = valueOf('--version') ?? versionIn(name);
if (!version) fail(`No version in the installer's name (${name}); pass --version 1.2.3.`);
const arch = /_(x64|arm64|x86)[-_]/.exec(name)?.[1] ?? pe.arch;
const info = {
  version,
  sha256: createHash('sha256').update(bytes).digest('hex'),
  bytes: bytes.length,
  url: 'glyph-setup.exe',
  arch: [arch],
  // Windows 10 and up: the installer fetches WebView2, the page's engine, where the PC has none (Windows 10).
  minimumSystemVersion: '10',
  // Authenticode: unsigned, Windows SmartScreen asks before running it (More info, Run anyway).
  signed: pe.signed,
};
const stage = mkdtempSync(join(tmpdir(), 'ghostmd-windows-stage-'));
writeFileSync(join(stage, 'windows.json'), `${JSON.stringify(info, null, 2)}\n`);
console.log(`ok Windows installer ${info.version}, ${arch}, ${(info.bytes / 1e6).toFixed(0)} MB, ${info.signed ? 'signed' : 'NOT signed'}`);
if (args.includes('--print')) {
  console.log(JSON.stringify(info, null, 2));
  process.exit(0);
}

const env = loadEnv(BOX_ENV_KEYS);
const box = openBox(env, boxSshOptions({ connectTimeout: 20 }));
console.log('> Logging in to the box');
box.logIn();
const STAGE = '/tmp/ghostmd-windows-stage';
box.ssh(`rm -rf ${STAGE} && mkdir -p ${STAGE}`);
console.log(`> Uploading the installer (${(info.bytes / 1e6).toFixed(0)} MB)`);
box.rsync(['--progress'], path, `${STAGE}/glyph-setup.exe`);
box.rsync([], join(stage, 'windows.json'), `${STAGE}/windows.json`);
console.log('> Publishing');
// The installer by rename, then the manifest by rename: a page reading in between offers the old one whole.
box.ssh(`set -e
SUDO=; [ "$(id -u)" -eq 0 ] || SUDO=sudo
[ "$(sha256sum ${STAGE}/glyph-setup.exe | cut -d' ' -f1)" = "${info.sha256}" ] || { echo "x the installer arrived changed"; exit 1; }
$SUDO install -m 644 -o root -g root ${STAGE}/glyph-setup.exe ${RELEASE}/.glyph-setup.exe.new
$SUDO mv -f ${RELEASE}/.glyph-setup.exe.new ${RELEASE}/glyph-setup.exe
$SUDO install -m 644 -o root -g root ${STAGE}/windows.json ${RELEASE}/.windows.json.new
$SUDO mv -f ${RELEASE}/.windows.json.new ${RELEASE}/windows.json
rm -rf ${STAGE}
echo "ok glyph-setup.exe and windows.json in ${RELEASE}"`);
if (!keepConnection) box.close();

// From here, as a visitor would.
const curl = (curlArgs) => spawnSync('curl', ['-s', '--max-time', '20', ...curlArgs], { encoding: 'utf8' }).stdout;
const live = curl(['https://attack.fm/glyph/windows.json']);
let said = null;
try {
  said = JSON.parse(live);
} catch {
  said = null;
}
if (said?.sha256 !== info.sha256) fail(`https://attack.fm/glyph/windows.json does not say this installer yet:\n${live}`);
console.log(`ok Windows app live: ${info.version}, ${info.bytes} bytes`);
console.log('  the installer   https://attack.fm/glyph/glyph-setup.exe');
