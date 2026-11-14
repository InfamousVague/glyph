#!/usr/bin/env node
/**
 * Puts Ghost Messaging's relay on the box (Matt, 2026-11-14: "Deploy the relay"): relay/, which is the pairings'
 * relay at /relay/<channel> (a phone and the computer it is paired with) and the hub at /hub (where two people's
 * apps find each other: docs/network.md). One program, one service, listening on the box alone; the web server
 * that holds ghost-sms.com's certificate passes those two addresses to it (tool/deploy-site.mjs --caddy writes
 * that into ghost-sms.com's own block).
 *
 *   node tool/deploy-relay.mjs                    builds it for the box, installs it, (re)starts the service
 *   node tool/deploy-relay.mjs --keep-connection  the same, and leaves the login open for the next script
 *   node tool/deploy-relay.mjs --print            the script the box would run, and nothing sent
 *   node tool/deploy-relay.mjs --env <file>       the same, and puts <file> on the box as /etc/ghost-relay/env
 *
 * --env is how the relay's secrets reach the box (Matt, 2026-11-14, of the texting service's: "where can I give you
 * the codes to upload to the server"): never through a chat. They are written in a file on the Mac, one NAME=value
 * a line (docs/me.md says which: GHOST_TWILIO_SID and the rest), and this reads the file, checks each name is one
 * the relay knows and each value has the shape it should, and sends it down the same ssh session as the program,
 * on its input and not in the command, where the box's other users could read it. Only the names are ever printed.
 * The file on the box is the Mac's, whole: a value taken out of the Mac's file is gone from the box's.
 *
 * The first time, both in one login (the box counts them; the second rides the first's connection):
 *
 *   node tool/deploy-relay.mjs --keep-connection && node tool/deploy-site.mjs --caddy
 *
 * After that the first alone, whenever relay/ changes. A restart drops whoever is connected: the apps connect
 * again by themselves, and what the hub was holding for people who are away is lost (it is kept in memory; the
 * apps' other routes are what a sender falls back on).
 *
 * What it does on the box, in one ssh session, stopping before anything is changed if the build does not run
 * there or the port is someone else's: a user of its own with no shell and no home (ghost-relay); the program in
 * /opt/ghost-relay; what it keeps (the pairings' channels: a hash and a day each) in /var/lib/ghost-relay; a
 * systemd service that restarts it, may write nowhere else, and may use 300 MB and one processor at most.
 *
 * It uses Ghost.md's box account and its own deploy code, as tool/release.mjs does (--glyph <path> or GLYPH_ROOT).
 */
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const RELAY = join(ROOT, 'relay');
const OUT = join(ROOT, 'build', 'relay');
const BIN = join(OUT, 'ghost-relay');
const DIR = '/opt/ghost-relay';
const DATA = '/var/lib/ghost-relay';
const UNIT = '/etc/systemd/system/ghost-relay.service';
// 8787, the relay's own default, is another service's on the box (found by the first deploy, which stopped there).
// tool/deploy-site.mjs's block names the same port: the two must agree.
const PORT = 18787;
const DOMAIN = 'ghost-sms.com';
const ENV = '/etc/ghost-relay/env';
const args = process.argv.slice(2);
const printOnly = args.includes('--print');
const fail = (message) => { console.error(`x ${message}`); process.exit(1); };

// What the relay reads from its environment (relay/lib/handles.dart `HandlesConfig.fromEnvironment`), and the
// shape of the ones that have one. A name that is not here is a slip of the hand, and is refused.
const KNOWN = {
  GHOST_PUBLIC_URL: /^https:\/\/[A-Za-z0-9.-]+$/,
  GHOST_DISCORD_ID: /^[0-9]{15,22}$/,
  GHOST_DISCORD_SECRET: null,
  GHOST_X_ID: null,
  GHOST_X_SECRET: null,
  GHOST_TELEGRAM_BOT: /^[A-Za-z0-9_]{5,32}$/,
  GHOST_TELEGRAM_TOKEN: /^[0-9]+:[A-Za-z0-9_-]+$/,
  GHOST_GITHUB_TOKEN: null,
  GHOST_TWILIO_SID: /^(AC|SK)[0-9a-fA-F]{32}$/,
  GHOST_TWILIO_TOKEN: /^[A-Za-z0-9]{32}$/,
  GHOST_TWILIO_VERIFY: /^VA[0-9a-fA-F]{32}$/,
  GHOST_TEXT_TO: /^\+[0-9]{1,6}(,\+[0-9]{1,6})*$/,
  GHOST_TEXTS_A_DAY: /^[0-9]{1,6}$/,
};
const SHAPES = {
  GHOST_TWILIO_SID: 'AC or SK and 32 more characters',
  GHOST_TWILIO_TOKEN: '32 letters and digits',
  GHOST_TWILIO_VERIFY: 'VA and 32 more characters',
};
// Kept together or not at all: with one of them missing the relay has that way of linking off, and says nothing.
const TOGETHER = [['GHOST_TWILIO_SID', 'GHOST_TWILIO_TOKEN', 'GHOST_TWILIO_VERIFY'], ['GHOST_DISCORD_ID', 'GHOST_DISCORD_SECRET'], ['GHOST_TELEGRAM_BOT', 'GHOST_TELEGRAM_TOKEN']];

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
    if (!(name in KNOWN)) fail(`${file}, line ${i + 1}: ${name} is not a name the relay reads. It reads: ${Object.keys(KNOWN).join(', ')}.`);
    let value = line.slice(eq + 1).trim();
    // Copied with quotes round it, or a curly pair an editor made of them.
    value = value.replace(/^["'\u201c\u2018](.*)["'\u201d\u2019]$/, '$1').trim();
    if (!value) continue;
    if (!/^[A-Za-z0-9+_.,:\/@-]+$/.test(value)) fail(`${file}: the value of ${name} has a space, a quote or another mark a value does not have.`);
    if (KNOWN[name] && !KNOWN[name].test(value)) fail(`${file}: the value of ${name} does not look right${SHAPES[name] ? ` (it is ${SHAPES[name]})` : ''}. Nothing was sent.`);
    if (values.has(name)) fail(`${file}: ${name} is there twice.`);
    values.set(name, value);
  }
  if (values.size === 0) fail(`${file} has no value filled in yet. Nothing was sent.`);
  for (const group of TOGETHER) {
    const have = group.filter((n) => values.has(n));
    if (have.length > 0 && have.length < group.length) fail(`${file}: ${group.filter((n) => !values.has(n)).join(' and ')} ${group.length - have.length === 1 ? 'is' : 'are'} not filled in, and ${have.join(' and ')} ${have.length === 1 ? 'does' : 'do'} nothing without. Nothing was sent.`);
  }
  return { names: [...values.keys()], bytes: Buffer.from([...values].map(([n, v]) => `${n}=${v}\n`).join(''), 'utf8') };
}

const envAt = args.indexOf('--env');
if (envAt >= 0 && !args[envAt + 1]) fail('--env needs the file: --env ~/.config/mattssoftware/ghost-relay.env');
const envFile = envAt >= 0 ? resolve(args[envAt + 1].replace(/^~(?=\/)/, homedir())) : null;
const secrets = envFile ? readEnvFile(envFile) : null;
const secretsSum = secrets ? createHash('sha256').update(secrets.bytes).digest('hex') : '';
if (secrets) console.log(`> ${envFile}: ${secrets.names.length} ${secrets.names.length === 1 ? 'value' : 'values'} for the box (${secrets.names.join(', ')})`);

const at = args.indexOf('--glyph');
const glyph = [at >= 0 ? args[at + 1] : null, process.env.GLYPH_ROOT, join(ROOT, '..'), join(ROOT, '..', 'glyph'), join(homedir(), 'Development/Apps/glyph')]
  .filter(Boolean)
  .find((dir) => existsSync(join(dir, 'tauri/scripts/lib/box.mjs')));
if (!glyph && !printOnly) fail('No Ghost.md checkout found for its box code (--glyph <path> or GLYPH_ROOT).');

// The box is x86-64 Linux (glyph's scripts/deploy-server.mjs builds for the same). Dart builds for it from here.
const dart = [process.env.DART, 'dart'].filter(Boolean).find((d) => spawnSync(d, ['--version'], { stdio: 'ignore' }).status === 0);
if (!dart) fail('No dart on the path (it comes with Flutter: set DART to it).');
mkdirSync(OUT, { recursive: true });
console.log('> Building the relay for the box (Linux, x86-64)');
const built = spawnSync(dart, ['compile', 'exe', '--target-os', 'linux', '--target-arch', 'x64', 'bin/relay.dart', '-o', BIN], { cwd: RELAY, stdio: ['ignore', 'ignore', 'inherit'] });
if (built.status !== 0 || !existsSync(BIN)) fail('dart compile exe failed.');
const program = readFileSync(BIN);
const sum = createHash('sha256').update(program).digest('hex');
console.log(`  ${(program.length / 1e6).toFixed(1)} MB, sha256 ${sum.slice(0, 16)}…`);

const SERVICE = `[Unit]
Description=Ghost Messaging relay: pairings at /relay, the hub at /hub (ghost-sms.com)
After=network.target

[Service]
User=ghost-relay
Group=ghost-relay
# The networks' sign-ins for Settings › Me (docs/me.md): GHOST_DISCORD_ID and the rest, one NAME=value a line, in a
# file only root reads. It need not exist: a network with no values is "off" in the app, and nothing else changes.
EnvironmentFile=-${ENV}
ExecStart=${DIR}/ghost-relay --host 127.0.0.1 --port ${PORT} --data ${DATA}
Restart=always
RestartSec=2
MemoryMax=300M
CPUQuota=100%
LimitNOFILE=65536
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=${DATA}

[Install]
WantedBy=multi-user.target
`;

// Run on the box. Reads the program on stdin; with --env, the values' file first, so many bytes of it, and then
// the program. What is staged is in a folder only this account reads, and is gone however the script ends.
const REMOTE = `set -e
SUDO=; [ "$(id -u)" -eq 0 ] || SUDO=sudo
STAGE="$HOME/.ghost-relay-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"; chmod 700 "$STAGE"
trap 'rm -rf "$STAGE"' EXIT
${secrets ? `dd bs=1 count=${secrets.bytes.length} of="$STAGE/env" 2>/dev/null
[ "$(sha256sum "$STAGE/env" | cut -d' ' -f1)" = "${secretsSum}" ] || { echo "x the values arrived changed"; exit 1; }
` : ''}cat > "$STAGE/ghost-relay"
[ "$(sha256sum "$STAGE/ghost-relay" | cut -d' ' -f1)" = "${sum}" ] || { echo "x the relay arrived changed"; exit 1; }
[ "$(uname -m)" = x86_64 ] || { echo "x this box is $(uname -m); the relay was built for x86_64"; exit 1; }
chmod +x "$STAGE/ghost-relay"
# Run here before anything is changed: a build that cannot start on this box stops the deploy.
"$STAGE/ghost-relay" --help >/dev/null || { echo "x the relay does not run on this box"; exit 1; }
# The port is the relay's own, or nobody's. Its own is known by the process that holds it being the service's: the
# name ss gives is cut short ("dart:ghost-rela"), which the first deploy over a running relay took for a stranger.
if $SUDO ss -ltnp 2>/dev/null | grep -q ":${PORT} "; then
  HOLDER=$($SUDO ss -ltnp | grep ":${PORT} " | sed -n 's/.*pid=\\([0-9]*\\).*/\\1/p' | head -1)
  OURS=$($SUDO systemctl show -p MainPID --value ghost-relay 2>/dev/null || true)
  { [ -n "$HOLDER" ] && [ "$HOLDER" = "$OURS" ]; } || { echo "x port ${PORT} is in use by something else:"; $SUDO ss -ltnp | grep ":${PORT} "; exit 1; }
fi
id ghost-relay >/dev/null 2>&1 || $SUDO useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin ghost-relay
$SUDO mkdir -p ${DIR} ${DATA}
$SUDO chown ghost-relay:ghost-relay ${DATA}
$SUDO chmod 750 ${DATA}
$SUDO cp "$STAGE/ghost-relay" ${DIR}/ghost-relay.next
$SUDO chmod 755 ${DIR}/ghost-relay.next
$SUDO mv ${DIR}/ghost-relay.next ${DIR}/ghost-relay
printf '%s' '${SERVICE.replace(/'/g, "'\\''")}' | $SUDO tee ${UNIT} >/dev/null
${secrets ? `# The values: root's alone, in a folder that is root's alone. The service reads them as it starts.
$SUDO mkdir -p ${dirname(ENV)}
$SUDO chmod 700 ${dirname(ENV)}
$SUDO install -m 600 -o root -g root "$STAGE/env" ${ENV}
echo "  ${ENV}: ${secrets.names.length} ${secrets.names.length === 1 ? 'value' : 'values'} written"
` : ''}$SUDO systemctl daemon-reload
$SUDO systemctl enable ghost-relay >/dev/null 2>&1
$SUDO systemctl restart ghost-relay
sleep 2
$SUDO systemctl is-active ghost-relay >/dev/null || { echo "x the relay did not stay up:"; $SUDO journalctl -u ghost-relay -n 20 --no-pager; exit 1; }
ANSWER=$(curl -s --max-time 5 http://127.0.0.1:${PORT}/ || true)
[ "$ANSWER" = "Ghost Messaging relay" ] || { echo "x the relay does not answer on 127.0.0.1:${PORT} (it said: $ANSWER)"; $SUDO journalctl -u ghost-relay -n 20 --no-pager; exit 1; }
echo "ok the relay is running as ghost-relay on 127.0.0.1:${PORT}; $(free -m | awk '/^Mem:/ {print $7}') MB of the box's memory is free"
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
console.log('> Installing the relay (one ssh session)');
const result = box.exec(REMOTE, { input: secrets ? Buffer.concat([secrets.bytes, program]) : program, stdio: ['pipe', 'inherit', 'inherit'] });
if (!args.includes('--keep-connection')) box.close();
if (result.status !== 0) fail(result.status === 5 ? 'ssh refused the password: if .env is right, this is the box\'s lockout; wait it out.' : 'The remote step failed (output above).');

// From here, as an app would reach it: through the web server, at the site's own name.
const curl = (path) => spawnSync('curl', ['-s', '--max-time', '15', `https://${DOMAIN}${path}`], { encoding: 'utf8' }).stdout.trim();
const relay = curl('/relay/'), hub = curl('/hub');
if (relay === 'Ghost Messaging relay' && hub === 'Ghost Messaging relay') {
  console.log(`ok live: wss://${DOMAIN}/relay and wss://${DOMAIN}/hub answer`);
} else {
  console.log(`  https://${DOMAIN}/relay/ and /hub do not reach it yet: the web server has to be told once (node tool/deploy-site.mjs --caddy, while this login is still open).`);
}
