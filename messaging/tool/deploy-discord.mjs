#!/usr/bin/env node
/**
 * Puts Ghost Messaging's Discord presence bot (discord/) on the box: who is in a linked Discord server's voice
 * channels, for the app's spaces. One Node program holding one connection to Discord's gateway and answering the app
 * on 127.0.0.1:18788; the web server passes https://ghost-sms.com/discord/* (and gogho.st's) to it
 * (tool/deploy-site.mjs --caddy writes that into the site's blocks). It does not join voice.
 *
 *   node tool/deploy-discord.mjs --env <file>       the first time: installs it with <file> as /etc/ghost-discord/env
 *   node tool/deploy-discord.mjs                    later: the new code, the values on the box kept
 *   node tool/deploy-discord.mjs --keep-connection  either, and leaves the login open for the next script
 *   node tool/deploy-discord.mjs --print            the script the box would run, and nothing built or sent
 *
 * --env is how the bot's token reaches the box: never through a chat or a command line. It is a file on the Mac, one
 * NAME=value a line (DISCORD_TOKEN and DISCORD_APP_ID, from the Developer Portal: discord/README.md), and this reads
 * it, checks each name is one the bot reads and each value has the shape it should, and sends it down the same ssh
 * session as the program, on its input and not in the command, where the box's other users could read it. Only the
 * names are ever printed. The file on the box is the Mac's, whole.
 *
 * The first time, both in one login (the box counts them; the second rides the first's connection):
 *
 *   node tool/deploy-discord.mjs --env <file> --keep-connection && node tool/deploy-site.mjs --caddy
 *
 * What it does on the box, in one ssh session, stopping before anything is changed if the port is someone else's,
 * the program does not load, or there are no values yet: a user of its own with no shell and no home (ghost-discord);
 * its own Node (/opt/ghost-discord/node, the official linux-x64 release pinned below and checked against its
 * SHA-256: the box's /usr/bin/node is Ubuntu's, which other services keep); the program in /opt/ghost-discord/app
 * with its dependencies installed here (`npm ci --omit=dev`: discord.js is plain JavaScript, nothing is compiled);
 * the links (hashes of the app's tokens) in /var/lib/ghost-discord; a systemd service that restarts it, may write
 * nowhere else, and may use 200 MB and half a processor at most. A restart forgets codes not yet used (/ghost link
 * again) and keeps every link.
 *
 * It uses Ghost.md's box account and its own deploy code, as tool/release.mjs does (--glyph <path> or GLYPH_ROOT).
 */
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { cpSync, existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const BOT = join(ROOT, 'discord');
const DIR = '/opt/ghost-discord';
const DATA = '/var/lib/ghost-discord';
const UNIT = '/etc/systemd/system/ghost-discord.service';
// tool/deploy-site.mjs's block names the same port: the two must agree. 18787 is the relay's.
const PORT = 18788;
const DOMAIN = 'gogho.st'; // ghost-sms.com passes /discord/* on as well (tool/deploy-site.mjs).
const ENV = '/etc/ghost-discord/env';
/** The bot's Node: the same release glyph's Discord notetaker runs (scripts/setup-discord-box.mjs), and its tarball's
 * SHA-256 from https://nodejs.org/dist/v22.23.4/SHASUMS256.txt. Move both together. */
const NODE_VERSION = 'v22.23.4';
const NODE_SHA256 = '1805bcd35e6815559bd2eb97db438d3fdb0eb3a5e6a977b7c1badca76337e9ce';
const args = process.argv.slice(2);
const printOnly = args.includes('--print');
const fail = (message) => { console.error(`x ${message}`); process.exit(1); };

for (const [i, arg] of args.entries()) {
  if (['--print', '--keep-connection'].includes(arg)) continue;
  if (['--env', '--glyph'].includes(arg)) continue;
  if (['--env', '--glyph'].includes(args[i - 1])) continue;
  fail(`Unknown argument ${arg}.`);
}

// What the bot reads from its environment (discord/src/bot.js), and the shape of each. PORT and DISCORD_DATA are the
// service's own (the unit sets them), so they are not taken from the file.
const KNOWN = {
  // Three base64url parts joined by dots (Developer Portal › Bot › Reset Token).
  DISCORD_TOKEN: /^[A-Za-z0-9_-]{20,100}\.[A-Za-z0-9_-]{4,20}\.[A-Za-z0-9_-]{20,100}$/,
  DISCORD_APP_ID: /^[0-9]{15,22}$/,
};
const SHAPES = {
  DISCORD_TOKEN: 'three parts joined by dots: Developer Portal › your application › Bot › Reset Token',
  DISCORD_APP_ID: 'digits: Developer Portal › your application › General Information › Application ID',
};
const REQUIRED = ['DISCORD_TOKEN', 'DISCORD_APP_ID'];

/** The file's values as the box's file will hold them, and their names. No value is ever part of a message. */
function readEnvFile(file) {
  if (!existsSync(file)) fail(`No file at ${file}.`);
  const values = new Map();
  for (const [i, raw] of readFileSync(file, 'utf8').split(/\r?\n/).entries()) {
    const line = raw.trim();
    if (!line || line.startsWith('#') || line.startsWith(';')) continue;
    const eq = line.indexOf('=');
    const name = eq < 0 ? line : line.slice(0, eq).trim();
    if (eq < 0 || !/^[A-Z0-9_]+$/.test(name)) fail(`${file}, line ${i + 1}: not a NAME=value line.`);
    if (!(name in KNOWN)) fail(`${file}, line ${i + 1}: ${name} is not a name the bot reads. It reads: ${Object.keys(KNOWN).join(', ')}.`);
    let value = line.slice(eq + 1).trim();
    // Copied with quotes round it, or a curly pair an editor made of them.
    value = value.replace(/^["'“‘](.*)["'”’]$/, '$1').trim();
    if (!value) continue;
    if (!KNOWN[name].test(value)) fail(`${file}: the value of ${name} does not look right (it is ${SHAPES[name]}). Nothing was sent.`);
    if (values.has(name)) fail(`${file}: ${name} is there twice.`);
    values.set(name, value);
  }
  const missing = REQUIRED.filter((n) => !values.has(n));
  if (missing.length) fail(`${file}: ${missing.join(' and ')} ${missing.length === 1 ? 'is' : 'are'} not filled in; the bot needs both. Nothing was sent.`);
  return { names: [...values.keys()], bytes: Buffer.from([...values].map(([n, v]) => `${n}=${v}\n`).join(''), 'utf8') };
}

const envAt = args.indexOf('--env');
if (envAt >= 0 && !args[envAt + 1]) fail('--env needs the file: --env ~/.config/mattssoftware/ghost-discord.env');
const envFile = envAt >= 0 ? resolve(args[envAt + 1].replace(/^~(?=\/)/, homedir())) : null;
const secrets = envFile ? readEnvFile(envFile) : null;
const secretsSum = secrets ? createHash('sha256').update(secrets.bytes).digest('hex') : '';
if (secrets) console.log(`> ${envFile}: ${secrets.names.length} values for the box (${secrets.names.join(', ')})`);

const at = args.indexOf('--glyph');
const glyph = [at >= 0 ? args[at + 1] : null, process.env.GLYPH_ROOT, join(ROOT, '..'), join(ROOT, '..', 'glyph'), join(homedir(), 'Development/Apps/glyph')]
  .filter(Boolean)
  .map((dir) => resolve(dir.replace(/^~(?=\/)/, homedir())))
  .find((dir) => existsSync(join(dir, 'tauri/scripts/lib/box.mjs')));
if (!glyph && !printOnly) fail('No Ghost.md checkout found for its box code (--glyph <path> or GLYPH_ROOT).');

for (const file of ['package.json', 'package-lock.json', 'src/bot.js']) {
  if (!existsSync(join(BOT, file))) fail(`Missing discord/${file}.`);
}

/** The program as it runs on the box: src/, package.json, the lock, and the dependencies installed here (no tests,
 * nothing dev). discord.js and its dependencies are plain JavaScript, so a Mac's npm ci is the box's too. */
function stage() {
  const dir = mkdtempSync(join(tmpdir(), 'ghost-discord-'));
  for (const file of ['package.json', 'package-lock.json', 'README.md', 'src']) cpSync(join(BOT, file), join(dir, file), { recursive: true });
  const npm = spawnSync('npm', ['ci', '--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund', '--loglevel=error'], { cwd: dir, stdio: 'inherit' });
  if (npm.status !== 0) fail('npm ci for the bot failed.');
  // Anything native would have been built for this Mac and would not load on the box.
  const native = spawnSync('find', [join(dir, 'node_modules'), '-name', '*.node'], { encoding: 'utf8' }).stdout.trim();
  if (native) fail(`The bot's dependencies now carry a native module, which a Mac's npm ci cannot build for the box:\n${native}`);
  return dir;
}

let program = Buffer.alloc(0);
let sum = '(the tarball\'s sha256)';
if (!printOnly) {
  console.log('> Installing the bot\'s dependencies for the box (npm ci --omit=dev)');
  const dir = stage();
  try {
    const { tarball } = await import(pathToFileURL(join(glyph, 'tauri/scripts/lib/box.mjs')).href);
    program = tarball(dir, 128 * 1024 * 1024);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
  sum = createHash('sha256').update(program).digest('hex');
  console.log(`  ${(program.length / 1e6).toFixed(1)} MB, sha256 ${sum.slice(0, 16)}…`);
}

const SERVICE = `[Unit]
Description=Ghost Messaging Discord presence bot: who is in a linked server's voice channels, at /discord (ghost-sms.com)
After=network-online.target
Wants=network-online.target

[Service]
User=ghost-discord
Group=ghost-discord
# DISCORD_TOKEN and DISCORD_APP_ID, in a file only root reads; systemd reads it before dropping to the user.
EnvironmentFile=${ENV}
Environment=PORT=${PORT}
Environment=DISCORD_DATA=${DATA}
Environment=NODE_ENV=production
Environment=NODE_OPTIONS=--max-old-space-size=128
WorkingDirectory=${DIR}/app
ExecStart=${DIR}/node/bin/node ${DIR}/app/src/bot.js
Restart=always
RestartSec=5
MemoryMax=200M
CPUQuota=50%
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
UMask=0077
ReadWritePaths=${DATA}

[Install]
WantedBy=multi-user.target
`;

// Run on the box. Reads, on stdin, the values' file first when --env gave one (so many bytes of it), then the
// program's tarball. What is staged is in a folder only this account reads, and is gone however the script ends.
const REMOTE = `set -e
SUDO=; [ "$(id -u)" -eq 0 ] || SUDO=sudo
STAGE="$HOME/.ghost-discord-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"; chmod 700 "$STAGE"
trap 'rm -rf "$STAGE"' EXIT
${secrets ? `dd bs=1 count=${secrets.bytes.length} of="$STAGE/env" 2>/dev/null
[ "$(sha256sum "$STAGE/env" | cut -d' ' -f1)" = "${secretsSum}" ] || { echo "x the values arrived changed"; exit 1; }
` : `$SUDO test -s ${ENV} || { echo "x there is no ${ENV} on the box yet: run this once with --env <file> (discord/README.md)"; exit 1; }
`}cat > "$STAGE/app.tgz"
[ "$(sha256sum "$STAGE/app.tgz" | cut -d' ' -f1)" = "${sum}" ] || { echo "x the program arrived changed"; exit 1; }
[ "$(uname -m)" = x86_64 ] || { echo "x this box is $(uname -m); the Node fetched is for x86_64"; exit 1; }
mkdir -p "$STAGE/app"; tar xzf "$STAGE/app.tgz" -C "$STAGE/app" --no-same-owner
[ -f "$STAGE/app/src/bot.js" ] || { echo "x the program arrived without src/bot.js"; exit 1; }
# The port is the bot's own, or nobody's. Its own is known by the process that holds it being the service's.
if $SUDO ss -ltnp 2>/dev/null | grep -q ":${PORT} "; then
  HOLDER=$($SUDO ss -ltnp | grep ":${PORT} " | sed -n 's/.*pid=\\([0-9]*\\).*/\\1/p' | head -1)
  OURS=$($SUDO systemctl show -p MainPID --value ghost-discord 2>/dev/null || true)
  { [ -n "$HOLDER" ] && [ "$HOLDER" = "$OURS" ]; } || { echo "x port ${PORT} is in use by something else:"; $SUDO ss -ltnp | grep ":${PORT} "; exit 1; }
fi
# Its own Node, fetched only when the one there is not this version, and checked before it is unpacked.
NODE=${DIR}/node/bin/node
if [ "$($NODE --version 2>/dev/null || echo none)" != "${NODE_VERSION}" ]; then
  echo "  fetching Node ${NODE_VERSION}"
  curl -fsSL -o "$STAGE/node.tar.xz" "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.xz"
  [ "$(sha256sum "$STAGE/node.tar.xz" | cut -d' ' -f1)" = "${NODE_SHA256}" ] || { echo "x the Node tarball did not match its SHA-256: nothing was changed"; exit 1; }
  $SUDO mkdir -p ${DIR}
  $SUDO rm -rf ${DIR}/node.next; $SUDO mkdir -p ${DIR}/node.next
  $SUDO tar xJf "$STAGE/node.tar.xz" -C ${DIR}/node.next --strip-components=1 --no-same-owner
  $SUDO rm -rf ${DIR}/node.old
  if [ -d ${DIR}/node ]; then $SUDO mv ${DIR}/node ${DIR}/node.old; fi
  $SUDO mv ${DIR}/node.next ${DIR}/node
  $SUDO rm -rf ${DIR}/node.old
fi
echo "  Node $($NODE --version)"
# Loaded here before anything else is changed: a program that does not load on this box stops the deploy.
$NODE --check "$STAGE/app/src/bot.js"
(cd "$STAGE/app" && $NODE -e "import('discord.js').then(() => {}, (e) => { console.log('x discord.js does not load: ' + (e.code || e.message)); process.exit(1) })")
id ghost-discord >/dev/null 2>&1 || $SUDO useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin ghost-discord
$SUDO mkdir -p ${DIR} ${DATA}
$SUDO chown ghost-discord:ghost-discord ${DATA}
$SUDO chmod 700 ${DATA}
$SUDO rm -rf ${DIR}/app.next
$SUDO cp -a "$STAGE/app" ${DIR}/app.next
$SUDO chown -R root:root ${DIR}/app.next
$SUDO chmod -R u+rwX,go+rX,go-w ${DIR}/app.next
$SUDO rm -rf ${DIR}/app.old
if [ -d ${DIR}/app ]; then $SUDO mv ${DIR}/app ${DIR}/app.old; fi
$SUDO mv ${DIR}/app.next ${DIR}/app
printf '%s' '${SERVICE.replace(/'/g, "'\\''")}' | $SUDO tee ${UNIT} >/dev/null
${secrets ? `# The values: root's alone, in a folder that is root's alone. The service reads them as it starts.
$SUDO mkdir -p ${dirname(ENV)}
$SUDO chmod 700 ${dirname(ENV)}
$SUDO install -m 600 -o root -g root "$STAGE/env" ${ENV}
echo "  ${ENV}: ${secrets.names.length} values written"
` : ''}$SUDO systemctl daemon-reload
$SUDO systemctl enable ghost-discord >/dev/null 2>&1
$SUDO systemctl restart ghost-discord
sleep 3
$SUDO systemctl is-active ghost-discord >/dev/null || { echo "x the bot did not stay up:"; $SUDO journalctl -u ghost-discord -n 20 --no-pager; exit 1; }
ANSWER=$(curl -s --max-time 5 http://127.0.0.1:${PORT}/discord/ || true)
case "$ANSWER" in *'"service":"ghost-discord"'*) ;; *) echo "x the bot does not answer on 127.0.0.1:${PORT} (it said: $ANSWER)"; $SUDO journalctl -u ghost-discord -n 20 --no-pager; exit 1;; esac
$SUDO rm -rf ${DIR}/app.old
# The invite link (no secret in it): the journal has it too.
echo "  invite: $(curl -s --max-time 5 http://127.0.0.1:${PORT}/discord/invite | sed -n 's/.*"url":"\\([^"]*\\)".*/\\1/p')"
echo "ok the bot is running as ghost-discord on 127.0.0.1:${PORT}; $(free -m | awk '/^Mem:/ {print $7}') MB of the box's memory is free"
`;

if (printOnly) {
  process.stdout.write(REMOTE);
  process.exit(0);
}

const { BOX_ENV_KEYS, boxSshOptions, openBox } = await import(pathToFileURL(join(glyph, 'tauri/scripts/lib/box.mjs')).href);
const { loadEnv } = await import(pathToFileURL(join(glyph, 'scripts/lib/env.mjs')).href);
const env = loadEnv(BOX_ENV_KEYS);
const box = openBox(env, boxSshOptions({ connectTimeout: 20, knownHosts: join(homedir(), '.ssh', 'known_hosts') }));
console.log('> Logging in to the box');
box.logIn();
console.log('> Installing the bot (one ssh session)');
const result = box.exec(REMOTE, { input: secrets ? Buffer.concat([secrets.bytes, program]) : program, stdio: ['pipe', 'inherit', 'inherit'] });
if (!args.includes('--keep-connection')) box.close();
if (result.status !== 0) fail(result.status === 5 ? 'ssh refused the password: if .env is right, this is the box\'s lockout; wait it out.' : 'The remote step failed (output above).');

// From here, as the app would reach it: through the web server, at the site's own names.
const curl = (url) => spawnSync('curl', ['-s', '--max-time', '15', url], { encoding: 'utf8' }).stdout.trim();
const live = ['ghost-sms.com', DOMAIN].filter((host) => curl(`https://${host}/discord/`).includes('"service":"ghost-discord"'));
if (live.length === 2) {
  console.log(`ok live: https://ghost-sms.com/discord and https://${DOMAIN}/discord answer`);
} else {
  console.log(`  https://ghost-sms.com/discord/ ${live.length ? `(only ${live.join(', ')} answers) ` : ''}does not reach it yet: the web server has to be told once (node tool/deploy-site.mjs --caddy, while this login is still open).`);
}
