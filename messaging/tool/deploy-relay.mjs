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
const args = process.argv.slice(2);
const printOnly = args.includes('--print');
const fail = (message) => { console.error(`x ${message}`); process.exit(1); };

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
EnvironmentFile=-/etc/ghost-relay/env
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

// Run on the box. Reads the program on stdin.
const REMOTE = `set -e
SUDO=; [ "$(id -u)" -eq 0 ] || SUDO=sudo
STAGE="$HOME/.ghost-relay-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"; cat > "$STAGE/ghost-relay"
[ "$(sha256sum "$STAGE/ghost-relay" | cut -d' ' -f1)" = "${sum}" ] || { echo "x the relay arrived changed"; exit 1; }
[ "$(uname -m)" = x86_64 ] || { echo "x this box is $(uname -m); the relay was built for x86_64"; exit 1; }
chmod +x "$STAGE/ghost-relay"
# Run here before anything is changed: a build that cannot start on this box stops the deploy.
"$STAGE/ghost-relay" --help >/dev/null || { echo "x the relay does not run on this box"; exit 1; }
# The port is the relay's own, or nobody's.
if $SUDO ss -ltnp 2>/dev/null | grep -q ":${PORT} "; then
  $SUDO ss -ltnp | grep ":${PORT} " | grep -q ghost-relay || { echo "x port ${PORT} is in use by something else:"; $SUDO ss -ltnp | grep ":${PORT} "; exit 1; }
fi
id ghost-relay >/dev/null 2>&1 || $SUDO useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin ghost-relay
$SUDO mkdir -p ${DIR} ${DATA}
$SUDO chown ghost-relay:ghost-relay ${DATA}
$SUDO chmod 750 ${DATA}
$SUDO cp "$STAGE/ghost-relay" ${DIR}/ghost-relay.next
$SUDO chmod 755 ${DIR}/ghost-relay.next
$SUDO mv ${DIR}/ghost-relay.next ${DIR}/ghost-relay
printf '%s' '${SERVICE.replace(/'/g, "'\\''")}' | $SUDO tee ${UNIT} >/dev/null
$SUDO systemctl daemon-reload
$SUDO systemctl enable ghost-relay >/dev/null 2>&1
$SUDO systemctl restart ghost-relay
sleep 2
$SUDO systemctl is-active ghost-relay >/dev/null || { echo "x the relay did not stay up:"; $SUDO journalctl -u ghost-relay -n 20 --no-pager; exit 1; }
ANSWER=$(curl -s --max-time 5 http://127.0.0.1:${PORT}/ || true)
[ "$ANSWER" = "Ghost Messaging relay" ] || { echo "x the relay does not answer on 127.0.0.1:${PORT} (it said: $ANSWER)"; $SUDO journalctl -u ghost-relay -n 20 --no-pager; exit 1; }
rm -rf "$STAGE"
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
const result = box.exec(REMOTE, { input: program, stdio: ['pipe', 'inherit', 'inherit'] });
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
