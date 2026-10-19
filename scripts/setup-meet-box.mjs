#!/usr/bin/env node
/**
 * Sets up the Google Meet notetaker (GHST-106, meet/bot, docs/MEET.md "The bot and the box") on the box, in ONE ssh
 * session, and every step is safe to repeat.
 *
 * WHAT IT CHANGES ON THE BOX:
 *
 *   packages   apt installs xvfb, x11vnc, pulseaudio, fonts-liberation, fonts-noto-color-emoji (and curl, gnupg,
 *              ca-certificates if missing); and google-chrome-stable from Google's apt repository, which it adds
 *              (/etc/apt/keyrings/google-chrome.gpg, /etc/apt/sources.list.d/google-chrome.list, and
 *              /etc/default/google-chrome telling Chrome's own cron job to leave that list alone). Chrome is then
 *              held (apt-mark hold): Meet's buttons are matched by name, and a Chrome that upgrades itself on a
 *              Tuesday is a bot that stops joining on a Tuesday. Nothing is apt-get updated when nothing is missing.
 *   a user     glyph-meet, a system user and group, home /var/lib/glyph-meet (0700: the Chrome profile, a call's
 *              recording until it is uploaded), no shell, no password.
 *   files      /opt/glyph-meet/bot (meet/bot without node_modules; `npm ci --omit=dev` run on the box as glyph-meet,
 *              then the whole tree made root's), the previous one kept as bot.prev; /opt/glyph-meet/meetctl;
 *              /opt/glyph-meet/glyph-meet.env (GLYPH_MEET_TOKEN, root:glyph-meet 0640) when .env has the token.
 *   units      glyph-meet-xvfb, glyph-meet-pulse and glyph-meet (enabled), glyph-meet-vnc and glyph-meet-signin (on
 *              demand only) in /etc/systemd/system; daemon-reload. The bot is started only when its env file has the
 *              token, and nothing is restarted while a meeting is under way (the new files wait for `meetctl
 *              restart`).
 *
 * It does NOT touch glyph-api, glyph-mcp, Caddy, AttackFM or anything else on the box. glyph-api needs the same
 * GLYPH_MEET_TOKEN, which scripts/deploy-server.mjs writes into its own env file.
 *
 * Usage:
 *   node scripts/setup-meet-box.mjs                   set up, or update the bot (the later deploys are this too)
 *   node scripts/setup-meet-box.mjs --signin          only start the sign-in (browser + VNC) and print the tunnel
 *   node scripts/setup-meet-box.mjs --setup --signin  both, in the one login: the first time
 *   node scripts/setup-meet-box.mjs --signin-done     stop the sign-in, check it, start the bot
 *   node scripts/setup-meet-box.mjs --print           what would run, without logging in or reading .env
 *
 * The box allows few logins (tauri/scripts/lib/box.mjs): each run spends ONE, or none when it rides a connection a
 * deploy left open. The sign-in's SSH tunnel is a login of Matt's own; inside that same tunnel's shell,
 * `/opt/glyph-meet/meetctl signin-done` finishes the sign-in without another one.
 *
 * The token travels as deploy-server's does: on ssh's stdin, never in an argument list or a file on this Mac, shape-
 * checked first because it is written out by printf on the box. The box's password reaches sshpass through SSHPASS.
 */
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readdirSync, rmSync, cpSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { BOX_ENV_KEYS, boxSshOptions, openBox, tarball } from '../tauri/scripts/lib/box.mjs';
import { loadEnv } from './lib/env.mjs';
import { ROOT } from './lib/paths.mjs';
import { dim, fail, ok, step } from '../tauri/scripts/lib/say.mjs';

const BOT = join(ROOT, 'meet/bot');
const BOX = join(ROOT, 'meet/box');
const UNITS = ['glyph-meet-xvfb.service', 'glyph-meet-pulse.service', 'glyph-meet.service', 'glyph-meet-vnc.service', 'glyph-meet-signin.service'];
const STAGE = '.glyph-meet-stage';
/** The oldest Node the bot runs on (meet/bot/package.json engines; playwright-core 1.59 needs 18). */
const NODE_MAJOR = 18;
const VNC_PORT = 5901;

const args = process.argv.slice(2);
for (const arg of args) {
  if (!['--setup', '--signin', '--signin-done', '--wait', '--print'].includes(arg)) fail(`Unknown flag ${arg}.`);
}
const PRINT = args.includes('--print');
const SIGNIN = args.includes('--signin');
const SIGNIN_DONE = args.includes('--signin-done');
// --signin --wait: this session carries the VNC view to this Mac (-L) and waits on the box until Ghost's profile has a
// Google sign-in, then finishes it: one login for the whole sign-in, where the tunnel by hand was a second (the box
// allows three an hour).
const WAIT = args.includes('--wait');
if (WAIT && !SIGNIN) fail('--wait goes with --signin.');
const SETUP = args.includes('--setup') || (!SIGNIN && !SIGNIN_DONE);
if (SIGNIN && SIGNIN_DONE) fail('--signin and --signin-done are two separate moments.');

/*
 * The remote half, run from the stage as the deploy account. DO_SETUP / DO_SIGNIN / DO_SIGNIN_DONE choose the parts;
 * the token, when it came, is in GLYPH_MEET_TOKEN_NEW. Every line it prints that the script reads starts with a
 * capital word: OS, GLIBC, USERNS, NODE, CHROME, UNIT, NODE_CHECK, SIGNED_IN, MEETING, ...
 */
const INSTALL = `set -euo pipefail
SUDO=; [ "$(id -u)" -eq 0 ] || SUDO=sudo
STAGE="$HOME/${STAGE}"
REMOTE=/opt/glyph-meet
DATA=/var/lib/glyph-meet
# sudo drops the environment, so apt's is given on its command line: no questions, and needrestart told not to run at
# all - left to itself it restarts whatever services use an upgraded library, glyph-api and AttackFM included.
APT="$SUDO env DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get"

# ---- what the box is ---------------------------------------------------------
. /etc/os-release
echo "OS $PRETTY_NAME"
echo "GLIBC $(ldd --version 2>/dev/null | head -1 | awk '{print $NF}')"
# Chrome's sandbox is built on unprivileged user namespaces. 22.04 allows them; 24.04 restricts them through AppArmor
# unless a profile (Ubuntu ships one for /opt/google/chrome/chrome) grants them.
echo "USERNS clone=$(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null || echo n/a) apparmor_restrict=$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || echo n/a) chrome_profile=$([ -e /etc/apparmor.d/chrome ] && echo yes || echo no)"
NODE_V=$(/usr/bin/node --version 2>/dev/null || echo none)
echo "NODE $NODE_V"
major=$(echo "$NODE_V" | sed -E 's/^v([0-9]+).*/\\1/')
if ! [ "$major" -ge ${NODE_MAJOR} ] 2>/dev/null; then
  echo "NODE_TOO_OLD /usr/bin/node is $NODE_V; the bot needs ${NODE_MAJOR} or newer (glyph-mcp runs on the same Node)"
  exit 3
fi

in_meeting() { systemctl is-active --quiet glyph-meet && pgrep -u glyph-meet -f /opt/google/chrome/chrome >/dev/null; }

if [ "\${DO_SETUP:-0}" = 1 ]; then
# ---- packages ------------------------------------------------------------------
need=()
for p in xvfb x11vnc pulseaudio fonts-liberation fonts-noto-color-emoji ca-certificates curl gnupg; do
  dpkg-query -W -f='\${Status}' "$p" 2>/dev/null | grep -q 'ok installed' || need+=("$p")
done
# "ok installed", not "install ok installed": once held (below), dpkg says "hold ok installed" (the second setup tried to
# upgrade the held package and apt refused).
if ! dpkg-query -W -f='\${Status}' google-chrome-stable 2>/dev/null | grep -q 'ok installed'; then
  # Chrome's package installs a daily cron job that rewrites its apt list; told not to, so the list stays ours.
  printf 'repo_add_once="false"\\nrepo_reenable_on_distupgrade="false"\\n' | $SUDO tee /etc/default/google-chrome >/dev/null
  $SUDO install -d -m 0755 /etc/apt/keyrings
  if [ ! -s /etc/apt/keyrings/google-chrome.gpg ]; then
    command -v gpg >/dev/null || { $APT update -q; $APT install -y -q --no-install-recommends gnupg curl ca-certificates; }
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor | $SUDO tee /etc/apt/keyrings/google-chrome.gpg.new >/dev/null
    $SUDO chmod 644 /etc/apt/keyrings/google-chrome.gpg.new
    $SUDO mv -f /etc/apt/keyrings/google-chrome.gpg.new /etc/apt/keyrings/google-chrome.gpg
  fi
  echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main' | $SUDO tee /etc/apt/sources.list.d/google-chrome.list >/dev/null
  need+=(google-chrome-stable)
fi
if [ \${#need[@]} -gt 0 ]; then
  echo "INSTALLING \${need[*]}"
  $APT update -q
  $APT install -y -q --no-install-recommends "\${need[@]}"
fi
$SUDO apt-mark hold google-chrome-stable >/dev/null
echo "CHROME $(google-chrome-stable --version 2>/dev/null || echo missing) (held)"

# ---- the user and its directories ---------------------------------------------------
getent group glyph-meet >/dev/null || $SUDO groupadd --system glyph-meet
id -u glyph-meet >/dev/null 2>&1 || $SUDO useradd --system --gid glyph-meet --home-dir $DATA --no-create-home --shell /usr/sbin/nologin glyph-meet
$SUDO install -d -o glyph-meet -g glyph-meet -m 700 $DATA $DATA/profile $DATA/work $DATA/work/failed $DATA/tmp
$SUDO install -d -o root -g root -m 755 $REMOTE

# ---- the bot's code -------------------------------------------------------------------
# npm runs as glyph-meet, with no install scripts, in a tree it owns for the moment; then the tree is root's, so the
# running bot cannot change its own code.
$SUDO rm -rf $REMOTE/bot.new
$SUDO cp -a "$STAGE/bot" $REMOTE/bot.new
$SUDO chown -R glyph-meet:glyph-meet $REMOTE/bot.new
# The one dependency (playwright-core, plain JavaScript) comes in the stage already installed: Ubuntu 24.04's nodejs
# has no npm, and installing it would bring hundreds of packages onto a box AttackFM shares (2026-10-19).
if [ ! -d $REMOTE/bot.new/node_modules/playwright-core ]; then
  command -v npm >/dev/null || { echo "NPM_MISSING install npm beside /usr/bin/node"; exit 4; }
  $SUDO runuser -u glyph-meet -- env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=$DATA npm_config_cache=$DATA/.npm \\
    sh -c "cd $REMOTE/bot.new && npm ci --omit=dev --ignore-scripts --no-audit --no-fund --loglevel=error"
fi
echo "PLAYWRIGHT $(/usr/bin/node -e "console.log(require('$REMOTE/bot.new/node_modules/playwright-core/package.json').version)" 2>/dev/null || echo missing)"
$SUDO chown -R root:root $REMOTE/bot.new
$SUDO chmod -R u+rwX,go+rX,go-w $REMOTE/bot.new
/usr/bin/node --check $REMOTE/bot.new/bot.mjs && echo "NODE_CHECK ok"
code_changed=1
if [ -d $REMOTE/bot ] && diff -rq $REMOTE/bot $REMOTE/bot.new >/dev/null 2>&1; then code_changed=; fi
if [ -n "$code_changed" ]; then
  $SUDO rm -rf $REMOTE/bot.prev
  [ -d $REMOTE/bot ] && $SUDO mv $REMOTE/bot $REMOTE/bot.prev
  $SUDO mv $REMOTE/bot.new $REMOTE/bot
else
  $SUDO rm -rf $REMOTE/bot.new
fi
echo "CODE_CHANGED \${code_changed:-0}"
$SUDO install -o root -g root -m 755 "$STAGE/meetctl" $REMOTE/meetctl

# ---- the token -----------------------------------------------------------------------------
# printf is a builtin: the token is in no argument list here either. Root's, readable by the bot's group only.
if [ -n "\${GLYPH_MEET_TOKEN_NEW:-}" ]; then
  printf 'GLYPH_MEET_TOKEN=%s\\n' "$GLYPH_MEET_TOKEN_NEW" | $SUDO tee $REMOTE/glyph-meet.env.new >/dev/null
  $SUDO chown root:glyph-meet $REMOTE/glyph-meet.env.new
  $SUDO chmod 640 $REMOTE/glyph-meet.env.new
  $SUDO mv -f $REMOTE/glyph-meet.env.new $REMOTE/glyph-meet.env
  echo "TOKEN written"
else
  echo "TOKEN $([ -s $REMOTE/glyph-meet.env ] && echo 'kept (none in .env)' || echo 'none: the bot will not be started')"
fi
unset GLYPH_MEET_TOKEN_NEW

# ---- the units -----------------------------------------------------------------------------
units_changed=
for unit in ${UNITS.join(' ')}; do
  if ! cmp -s "$STAGE/units/$unit" /etc/systemd/system/$unit; then
    $SUDO install -o root -g root -m 644 "$STAGE/units/$unit" /etc/systemd/system/$unit
    units_changed="$units_changed $unit"
  fi
done
echo "UNITS_CHANGED \${units_changed:- none}"
$SUDO systemctl daemon-reload
$SUDO systemctl enable glyph-meet-xvfb glyph-meet-pulse >/dev/null 2>&1

if in_meeting; then
  echo "MEETING yes: nothing restarted; run /opt/glyph-meet/meetctl restart after it"
else
  if [ -n "$units_changed" ]; then $SUDO systemctl restart glyph-meet-xvfb glyph-meet-pulse; else $SUDO systemctl start glyph-meet-xvfb glyph-meet-pulse; fi
  if [ "\${DO_SIGNIN:-0}" != 1 ]; then
    # Checked with the bot stopped (meetctl check stops and restarts it), then the bot started with the new code.
    $SUDO $REMOTE/meetctl check
    if [ -s $REMOTE/glyph-meet.env ]; then
      $SUDO systemctl enable glyph-meet >/dev/null 2>&1
      $SUDO systemctl restart glyph-meet
    fi
  fi
fi
fi

if [ "\${DO_SIGNIN:-0}" = 1 ]; then
  [ -x $REMOTE/meetctl ] || { echo "NOT_SET_UP run the setup first"; exit 5; }
  $SUDO $REMOTE/meetctl signin
  if [ "\${DO_WAIT:-0}" = 1 ]; then
    # Waits, up to 45 minutes, for the profile to hold Google's sign-in cookies (names only, read-only, never values),
    # then finishes the sign-in in this same session.
    signed_cookies() { $SUDO python3 -c "import sqlite3,sys;c=sqlite3.connect('file:$DATA/profile/Default/Cookies?mode=ro&immutable=1',uri=True);print(c.execute(\"select count(*) from cookies where host_key like '%google.com' and name in ('SID','__Secure-1PSID')\").fetchone()[0])" 2>/dev/null || echo 0; }
    waited=0
    until [ "$(signed_cookies)" -gt 0 ] 2>/dev/null; do
      sleep 15; waited=$((waited + 15))
      if [ $waited -ge 2700 ]; then echo "SIGNIN_TIMEOUT"; $SUDO systemctl stop glyph-meet-vnc glyph-meet-signin || true; exit 6; fi
    done
    echo "SIGNIN_SEEN after \${waited}s"
    # Google sets the cookies as the sign-in lands; a moment more for the redirects and the profile to settle.
    sleep 30
    $SUDO $REMOTE/meetctl signin-done
  fi
fi
if [ "\${DO_SIGNIN_DONE:-0}" = 1 ]; then
  [ -x $REMOTE/meetctl ] || { echo "NOT_SET_UP run the setup first"; exit 5; }
  $SUDO $REMOTE/meetctl signin-done
fi

sleep 2
for unit in glyph-meet-xvfb glyph-meet-pulse glyph-meet glyph-meet-vnc glyph-meet-signin; do
  echo "UNIT $unit $(systemctl is-active $unit 2>/dev/null || true)"
done
if $SUDO test -S /run/glyph-meet-pulse/native; then echo "PULSE socket"; else echo "PULSE no socket"; fi
rm -rf "$STAGE"
`;

/** The stage: the bot with its one dependency installed here (`npm ci --omit=dev`, no install scripts), the units,
 * meetctl and the install script. */
function stage() {
  const dir = mkdtempSync(join(tmpdir(), 'glyph-meet-'));
  cpSync(BOT, join(dir, 'bot'), {
    recursive: true,
    filter: (src) => !/[/\\](node_modules|\.DS_Store)([/\\]|$)/.test(src),
  });
  const npm = spawnSync('npm', ['ci', '--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund', '--loglevel=error'], { cwd: join(dir, 'bot'), stdio: 'inherit' });
  if (npm.status !== 0) fail('npm ci for the bot failed.');
  cpSync(join(BOX, 'meetctl'), join(dir, 'meetctl'));
  for (const unit of UNITS) cpSync(join(BOX, unit), join(dir, 'units', unit));
  writeFileSync(join(dir, 'install.sh'), INSTALL);
  return dir;
}

for (const path of [join(BOT, 'bot.mjs'), join(BOT, 'package-lock.json'), join(BOX, 'meetctl'), ...UNITS.map((u) => join(BOX, u))]) {
  if (!existsSync(path)) fail(`Missing ${path}.`);
}

const parts = `DO_SETUP=${SETUP ? 1 : 0} DO_SIGNIN=${SIGNIN ? 1 : 0} DO_SIGNIN_DONE=${SIGNIN_DONE ? 1 : 0} DO_WAIT=${WAIT ? 1 : 0}`;
const remote =
  `set -e; IFS= read -r GLYPH_MEET_TOKEN_NEW; export GLYPH_MEET_TOKEN_NEW; ` +
  `rm -rf "$HOME/${STAGE}"; mkdir -p "$HOME/${STAGE}"; tar xzf - -C "$HOME/${STAGE}"; ${parts} bash "$HOME/${STAGE}/install.sh"`;

if (PRINT) {
  const dir = stage();
  try {
    step('Would ship (one ssh session, as $AFM_DEPLOY_USER@$AFM_DEPLOY_HOST)');
    const list = (base, rel = '') =>
      readdirSync(join(base, rel), { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? list(base, join(rel, e.name)) : [join(rel, e.name)]));
    for (const file of list(dir)) console.log(`  ${file}`);
    step('Remote command');
    console.log(`  ${remote}`);
    console.log(dim('  stdin: one line, GLYPH_MEET_TOKEN from .env (or empty), then the tarball above'));
    step('install.sh');
    console.log(INSTALL);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
  process.exit(0);
}

const env = loadEnv(BOX_ENV_KEYS);
const token = env.GLYPH_MEET_TOKEN ?? '';
// The shape glyph-api accepts (deploy-server.mjs), and nothing that could break the printf line on the box.
if (token && !/^[A-Za-z0-9_-]{32,200}$/.test(token)) fail('GLYPH_MEET_TOKEN in .env must be 32 to 200 letters, digits, - or _.');
if (SETUP && !token) console.log(dim('  .env has no GLYPH_MEET_TOKEN: the bot is installed but not started until it does.'));

step(
  [SETUP && 'Setting up the Meet bot', SIGNIN && 'starting the sign-in', SIGNIN_DONE && 'finishing the sign-in'].filter(Boolean).join(', ') +
    ' (one ssh session)',
);
const dir = stage();
let out = '';
try {
  const box = openBox(env, [
    ...boxSshOptions({ connectTimeout: 20 }),
    ...(WAIT ? ['-L', `${VNC_PORT}:localhost:${VNC_PORT}`, '-o', 'ExitOnForwardFailure=yes', '-o', 'ServerAliveInterval=30'] : []),
  ]);
  const result = box.exec(remote, {
    input: Buffer.concat([Buffer.from(`${token}\n`), tarball(dir, 64 * 1024 * 1024)]),
    stdio: ['pipe', 'pipe', 'inherit'],
    maxBuffer: 16 * 1024 * 1024,
  });
  out = String(result.stdout ?? '');
  process.stdout.write(dim(out.replace(/^/gm, '  ')));
  if (result.status !== 0) {
    if (/^NODE_TOO_OLD /m.test(out)) fail(/^NODE_TOO_OLD (.*)$/m.exec(out)[1]);
    fail(
      result.status === 5 && !/NOT_SET_UP/.test(out)
        ? "ssh refused the password. If .env is right, this is the box's connection lockout - wait it out rather than retrying."
        : /NOT_SET_UP/.test(out)
          ? 'The bot is not set up on the box yet: run this without --signin / --signin-done first (or with --setup --signin).'
          : 'Remote setup failed (output above).',
    );
  }
} finally {
  rmSync(dir, { recursive: true, force: true });
}

// ---- what it says ---------------------------------------------------------------
const field = (name) => new RegExp(`^${name} (.*)$`, 'm').exec(out)?.[1] ?? '';
const unit = (name) => new RegExp(`^UNIT ${name} (\\S+)`, 'm').exec(out)?.[1] ?? 'unknown';
step('Health');
console.log(`  ${field('OS')}, glibc ${field('GLIBC')}, Node ${field('NODE')}, ${field('USERNS')}`);
if (SETUP) {
  ok(`Chrome: ${field('CHROME')}`);
  if (field('NODE_CHECK') !== 'ok') fail('node --check of the bot failed on the box.');
  ok('node --check bot.mjs');
}
const line = ['glyph-meet-xvfb', 'glyph-meet-pulse', 'glyph-meet'].map((u) => `${u} ${unit(u)}`).join(', ');
console.log(`  ${line}${field('PULSE') === 'socket' ? '' : ', pulse socket missing'}`);
for (const u of ['glyph-meet-xvfb', 'glyph-meet-pulse']) if (unit(u) !== 'active') fail(`${u} is ${unit(u)}: journalctl -u ${u} on the box.`);
const signed = field('SIGNED_IN');
if (signed) console.log(`  signed in: ${signed}`);
if (/^MEETING yes/m.test(out)) console.log(dim('  a meeting was under way: the new code waits for /opt/glyph-meet/meetctl restart'));

if (SIGNIN && WAIT) {
  if (/^SIGNIN_TIMEOUT/m.test(out)) fail('No sign-in within 45 minutes; the sign-in browser is stopped. Run it again with --signin --wait.');
  ok(`Ghost signed in on the box (${field('SIGNIN_SEEN')}); the sign-in browser and the VNC view are stopped.`);
} else if (SIGNIN) {
  if (unit('glyph-meet-signin') !== 'active' || unit('glyph-meet-vnc') !== 'active') fail('The sign-in browser or the VNC view did not start (output above).');
  step('Sign Ghost in');
  console.log(`  1. In a terminal here (it asks for the box's password; it is a login, so not within ten minutes of this one):`);
  console.log(`       ssh -L ${VNC_PORT}:localhost:${VNC_PORT} ${env.AFM_DEPLOY_USER}@${env.AFM_DEPLOY_HOST}`);
  console.log(`  2. Open vnc://localhost:${VNC_PORT} in Screen Sharing (no password; it answers only through the tunnel).`);
  console.log(`  3. Sign in to Ghost's Google account in the Chrome there (the account's language must be English).`);
  console.log(`  4. In the tunnel's shell:  /opt/glyph-meet/meetctl signin-done`);
  console.log(dim(`     (or, from here, later: node scripts/setup-meet-box.mjs --signin-done - one more login)`));
} else if (signed === 'no') {
  console.log(dim('  Ghost is not signed in: node scripts/setup-meet-box.mjs --signin'));
}
if ((!SIGNIN || WAIT) && unit('glyph-meet') !== 'active' && token) fail(`glyph-meet is ${unit('glyph-meet')}: journalctl -u glyph-meet on the box.`);
ok('done');
