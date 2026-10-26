#!/usr/bin/env node
/**
 * Sets up the Discord notetaker (discord/bot, docs/DISCORD_CALLS.md "The bot and the box") on the box, in ONE ssh
 * session, and every step is safe to repeat.
 *
 * WHAT IT CHANGES ON THE BOX:
 *
 *   a Node     /opt/glyph-discord/node: the official Node NODE_VERSION for linux-x64 from nodejs.org, fetched on the
 *              box with curl and checked against NODE_SHA256 below before it is unpacked (a tarball that does not
 *              match is thrown away and nothing changes). @discordjs/voice 0.19 needs Node 22.12 or newer; the box's
 *              /usr/bin/node is Ubuntu's 18, which glyph-mcp and the Meet bot keep, so this one is the bot's alone.
 *              Fetched only when the one there is not that version.
 *   a user     glyph-discord, a system user and group, home /var/lib/glyph-discord (0700: a call's recording until it
 *              is uploaded), no shell, no password. Its own, not glyph-meet's: it needs no screen, no sound and no
 *              Chrome profile, and shares nothing with the Meet bot but the loopback port both call.
 *   files      /opt/glyph-discord/app (discord/bot with its dependencies installed HERE, for linux-x64 - `npm ci --os=
 *              linux --cpu=x64 --libc=glibc`, no install scripts, so the DAVE library's prebuilt Linux binary comes
 *              and nothing is compiled - and the four files of meet/bot/lib it shares, decide.mjs, zoomtext.mjs, api.mjs and
 *              log.mjs, at the same relative paths), made root's, the previous kept as app.prev;
 *              /opt/glyph-discord/glyph-discord.env (DISCORD_BOT_TOKEN, GLYPH_DISCORD_TOKEN, DISCORD_APP_ID,
 *              root:glyph-discord 0640) when .env has them.
 *   a unit     glyph-discord.service in /etc/systemd/system (enabled), daemon-reload. Started only when its env file
 *              has both tokens; not restarted while a call is being recorded (the new code waits for
 *              `systemctl restart glyph-discord` after it).
 *
 * It does NOT touch glyph-api, glyph-mcp, the Meet bot, Caddy, AttackFM or anything else on the box. glyph-api needs
 * the same GLYPH_DISCORD_TOKEN, which scripts/deploy-server.mjs writes into its own env file: deploy that first.
 *
 * Usage:
 *   node scripts/setup-discord-box.mjs                        set up, or update the bot (later deploys are this too)
 *   node scripts/setup-discord-box.mjs --register-commands    the same, then tell Discord of /ghost (register.mjs):
 *                                                             in the one server DISCORD_GUILD_ID when .env has it
 *                                                             (at once), else globally
 *   node scripts/setup-discord-box.mjs --register-only        only the commands, nothing installed
 *   node scripts/setup-discord-box.mjs --print                what would run, without logging in or reading .env
 *
 * The box allows few logins (tauri/scripts/lib/box.mjs): each run spends ONE, or none when it rides a connection a
 * deploy left open. The tokens travel as setup-meet-box's do: on ssh's stdin, never in an argument list or a file on
 * this Mac, shape-checked first because they are written out by printf on the box; never printed.
 */
import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { BOX_ENV_KEYS, boxSshOptions, openBox, tarball } from '../tauri/scripts/lib/box.mjs';
import { loadEnv } from './lib/env.mjs';
import { ROOT } from './lib/paths.mjs';
import { dim, fail, ok, step } from '../tauri/scripts/lib/say.mjs';

const BOT = join(ROOT, 'discord/bot');
const UNIT = join(ROOT, 'discord/box/glyph-discord.service');
/** The Meet bot's files the Discord bot imports, by their path from the repository's root. */
// decide.mjs reads Zoom's hosts from zoomtext.mjs since the Zoom bot (2026-10-26: the first run crash-looped without it).
const SHARED = ['meet/bot/lib/decide.mjs', 'meet/bot/lib/zoomtext.mjs', 'meet/bot/lib/api.mjs', 'meet/bot/lib/log.mjs'];
const STAGE = '.glyph-discord-stage';
/** The bot's Node: the 22 line's release of 2026-10-20 (a security release), and its tarball's SHA-256 from
 * https://nodejs.org/dist/v22.23.4/SHASUMS256.txt. Move both together. */
const NODE_VERSION = 'v22.23.4';
const NODE_SHA256 = '1805bcd35e6815559bd2eb97db438d3fdb0eb3a5e6a977b7c1badca76337e9ce';

const args = process.argv.slice(2);
for (const arg of args) {
  if (!['--register-commands', '--register-only', '--print'].includes(arg)) fail(`Unknown flag ${arg}.`);
}
const PRINT = args.includes('--print');
const REGISTER_ONLY = args.includes('--register-only');
const REGISTER = REGISTER_ONLY || args.includes('--register-commands');
const SETUP = !REGISTER_ONLY;

/*
 * The remote half, run from the stage as the deploy account. DO_SETUP / DO_REGISTER choose the parts; the tokens, when
 * they came, are in DISCORD_BOT_TOKEN_NEW, GLYPH_DISCORD_TOKEN_NEW, DISCORD_APP_ID_NEW, DISCORD_GUILD_ID_NEW. Every
 * line it prints that the script reads starts with a capital word.
 */
const INSTALL = `set -euo pipefail
SUDO=; [ "$(id -u)" -eq 0 ] || SUDO=sudo
STAGE="$HOME/${STAGE}"
REMOTE=/opt/glyph-discord
DATA=/var/lib/glyph-discord
NODE=$REMOTE/node/bin/node

. /etc/os-release
echo "OS $PRETTY_NAME"
echo "GLIBC $(ldd --version 2>/dev/null | head -1 | awk '{print $NF}')"

# A call is being recorded while its file is in the work folder.
in_call() { $SUDO sh -c "ls $DATA/work/*.webm" >/dev/null 2>&1 && systemctl is-active --quiet glyph-discord; }

if [ "\${DO_SETUP:-0}" = 1 ]; then
# ---- the user ------------------------------------------------------------------------------
getent group glyph-discord >/dev/null || $SUDO groupadd --system glyph-discord
id -u glyph-discord >/dev/null 2>&1 || $SUDO useradd --system --gid glyph-discord --home-dir $DATA --no-create-home --shell /usr/sbin/nologin glyph-discord
$SUDO install -d -o glyph-discord -g glyph-discord -m 700 $DATA $DATA/work $DATA/work/failed
$SUDO install -d -o root -g root -m 755 $REMOTE

# ---- its Node ------------------------------------------------------------------------------
if [ "$($NODE --version 2>/dev/null || echo none)" != "${NODE_VERSION}" ]; then
  echo "NODE_FETCHING ${NODE_VERSION}"
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/node.tar.xz" "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.xz"
  if [ "$(sha256sum "$tmp/node.tar.xz" | awk '{print $1}')" != "${NODE_SHA256}" ]; then
    rm -rf "$tmp"
    echo "NODE_CHECKSUM_MISMATCH"
    exit 7
  fi
  $SUDO rm -rf $REMOTE/node.new
  $SUDO install -d -o root -g root -m 755 $REMOTE/node.new
  $SUDO tar xJf "$tmp/node.tar.xz" -C $REMOTE/node.new --strip-components=1 --no-same-owner
  rm -rf "$tmp"
  $SUDO rm -rf $REMOTE/node.prev
  [ -d $REMOTE/node ] && $SUDO mv $REMOTE/node $REMOTE/node.prev
  $SUDO mv $REMOTE/node.new $REMOTE/node
fi
echo "NODE $($NODE --version)"

# ---- the bot's code ------------------------------------------------------------------------
$SUDO rm -rf $REMOTE/app.new
$SUDO cp -a "$STAGE/app" $REMOTE/app.new
$SUDO chown -R root:root $REMOTE/app.new
$SUDO chmod -R u+rwX,go+rX,go-w $REMOTE/app.new
$NODE --check $REMOTE/app.new/discord/bot/bot.mjs && echo "NODE_CHECK ok"
# The DAVE library's Linux binary, loaded as the bot will load it.
(cd $REMOTE/app.new/discord/bot && $NODE -e "import('@snazzah/davey').then(d => console.log('DAVE', d.DAVE_PROTOCOL_VERSION ?? 'loaded'), e => { console.log('DAVE_MISSING', e.code ?? e.message); process.exit(8) })")
code_changed=1
if [ -d $REMOTE/app ] && diff -rq $REMOTE/app $REMOTE/app.new >/dev/null 2>&1; then code_changed=; fi
if [ -n "$code_changed" ]; then
  $SUDO rm -rf $REMOTE/app.prev
  [ -d $REMOTE/app ] && $SUDO mv $REMOTE/app $REMOTE/app.prev
  $SUDO mv $REMOTE/app.new $REMOTE/app
else
  $SUDO rm -rf $REMOTE/app.new
fi
echo "CODE_CHANGED \${code_changed:-0}"

# ---- the tokens ----------------------------------------------------------------------------
# printf is a builtin: no token is in an argument list. Root's, readable by the bot's group only.
if [ -n "\${DISCORD_BOT_TOKEN_NEW:-}" ] && [ -n "\${GLYPH_DISCORD_TOKEN_NEW:-}" ]; then
  {
    printf 'DISCORD_BOT_TOKEN=%s\\n' "$DISCORD_BOT_TOKEN_NEW"
    printf 'GLYPH_DISCORD_TOKEN=%s\\n' "$GLYPH_DISCORD_TOKEN_NEW"
    [ -n "\${DISCORD_APP_ID_NEW:-}" ] && printf 'DISCORD_APP_ID=%s\\n' "$DISCORD_APP_ID_NEW"
    [ -n "\${DISCORD_GUILD_ID_NEW:-}" ] && printf 'DISCORD_GUILD_ID=%s\\n' "$DISCORD_GUILD_ID_NEW"
    true
  } | $SUDO tee $REMOTE/glyph-discord.env.new >/dev/null
  $SUDO chown root:glyph-discord $REMOTE/glyph-discord.env.new
  $SUDO chmod 640 $REMOTE/glyph-discord.env.new
  $SUDO mv -f $REMOTE/glyph-discord.env.new $REMOTE/glyph-discord.env
  echo "TOKENS written"
else
  echo "TOKENS $([ -s $REMOTE/glyph-discord.env ] && echo 'kept (not both in .env)' || echo 'none: the bot will not be started')"
fi

# ---- the unit ------------------------------------------------------------------------------
unit_changed=
if ! cmp -s "$STAGE/glyph-discord.service" /etc/systemd/system/glyph-discord.service; then
  $SUDO install -o root -g root -m 644 "$STAGE/glyph-discord.service" /etc/systemd/system/glyph-discord.service
  unit_changed=1
fi
echo "UNIT_CHANGED \${unit_changed:-0}"
$SUDO systemctl daemon-reload
if in_call; then
  echo "CALL yes: nothing restarted; run sudo systemctl restart glyph-discord after it"
elif $SUDO grep -q '^DISCORD_BOT_TOKEN=..' $REMOTE/glyph-discord.env 2>/dev/null && $SUDO grep -q '^GLYPH_DISCORD_TOKEN=..' $REMOTE/glyph-discord.env; then
  $SUDO systemctl enable glyph-discord >/dev/null 2>&1
  $SUDO systemctl restart glyph-discord
fi
fi

if [ "\${DO_REGISTER:-0}" = 1 ]; then
  [ -s $REMOTE/glyph-discord.env ] && [ -x $NODE ] || { echo "NOT_SET_UP run the setup first, with the tokens in .env"; exit 5; }
  # As the bot, reading its own env file (its group may): the token is in no argument list.
  where=; $SUDO grep -q '^DISCORD_GUILD_ID=..' $REMOTE/glyph-discord.env && where=--guild
  $SUDO runuser -u glyph-discord -- /bin/sh -c "set -a; . $REMOTE/glyph-discord.env; set +a; cd $REMOTE/app/discord/bot && exec $NODE register.mjs $where" || echo "REGISTER_FAILED"
fi

sleep 2
echo "UNIT_STATE $(systemctl is-active glyph-discord 2>/dev/null || true)"
rm -rf "$STAGE"
`;

/** The stage: the bot with its dependencies installed here for linux-x64, the shared Meet files, the unit, install.sh. */
function stage() {
  const dir = mkdtempSync(join(tmpdir(), 'glyph-discord-'));
  const app = join(dir, 'app');
  cpSync(BOT, join(app, 'discord/bot'), {
    recursive: true,
    filter: (src) => !/[/\\](node_modules|\.DS_Store|test)([/\\]|$)/.test(src),
  });
  for (const file of SHARED) {
    mkdirSync(join(app, file, '..'), { recursive: true });
    cpSync(join(ROOT, file), join(app, file));
  }
  const npm = spawnSync('npm', ['ci', '--omit=dev', '--ignore-scripts', '--no-audit', '--no-fund', '--loglevel=error', '--os=linux', '--cpu=x64', '--libc=glibc'], {
    cwd: join(app, 'discord/bot'),
    stdio: 'inherit',
  });
  if (npm.status !== 0) fail('npm ci for the bot failed.');
  if (!existsSync(join(app, 'discord/bot/node_modules/@snazzah/davey-linux-x64-gnu'))) fail("The DAVE library's linux-x64 binary did not come with npm ci --os=linux.");
  cpSync(UNIT, join(dir, 'glyph-discord.service'));
  writeFileSync(join(dir, 'install.sh'), INSTALL);
  return dir;
}

for (const path of [join(BOT, 'bot.mjs'), join(BOT, 'register.mjs'), join(BOT, 'package-lock.json'), UNIT, ...SHARED.map((f) => join(ROOT, f))]) {
  if (!existsSync(path)) fail(`Missing ${path}.`);
}

const parts = `DO_SETUP=${SETUP ? 1 : 0} DO_REGISTER=${REGISTER ? 1 : 0}`;
const TOKENS = ['DISCORD_BOT_TOKEN_NEW', 'GLYPH_DISCORD_TOKEN_NEW', 'DISCORD_APP_ID_NEW', 'DISCORD_GUILD_ID_NEW'];
const remote =
  `set -e; ${TOKENS.map((t) => `IFS= read -r ${t}`).join('; ')}; export ${TOKENS.join(' ')}; ` +
  `rm -rf "$HOME/${STAGE}"; mkdir -p "$HOME/${STAGE}"; tar xzf - -C "$HOME/${STAGE}"; ${parts} bash "$HOME/${STAGE}/install.sh"`;

if (PRINT) {
  const dir = stage();
  try {
    step('Would ship (one ssh session, as $AFM_DEPLOY_USER@$AFM_DEPLOY_HOST)');
    const list = (base, rel = '') =>
      readdirSync(join(base, rel), { withFileTypes: true }).flatMap((e) =>
        e.name === 'node_modules' ? [join(rel, 'node_modules/…')] : e.isDirectory() ? list(base, join(rel, e.name)) : [join(rel, e.name)],
      );
    for (const file of list(dir)) console.log(`  ${file}`);
    step('Remote command');
    console.log(`  ${remote}`);
    console.log(dim('  stdin: four lines, DISCORD_BOT_TOKEN, GLYPH_DISCORD_TOKEN, DISCORD_APP_ID, DISCORD_GUILD_ID from .env (each or empty), then the tarball'));
    step('install.sh');
    console.log(INSTALL);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
  process.exit(0);
}

const env = loadEnv(BOX_ENV_KEYS);
const bot = env.DISCORD_BOT_TOKEN ?? '';
const glyph = env.GLYPH_DISCORD_TOKEN ?? '';
const app = env.DISCORD_APP_ID ?? '';
const guild = env.DISCORD_GUILD_ID ?? '';
// The shapes, and nothing that could break the printf lines on the box. A Discord bot token is three base64url parts
// joined by dots; the bot's key to glyph-api is the shape glyph-api accepts (deploy-server.mjs).
if (bot && !/^[A-Za-z0-9_-]{20,100}\.[A-Za-z0-9_-]{4,20}\.[A-Za-z0-9_-]{20,100}$/.test(bot)) fail('DISCORD_BOT_TOKEN in .env does not look like a Discord bot token (Developer Portal › Bot › Reset Token).');
if (glyph && !/^[A-Za-z0-9_-]{32,200}$/.test(glyph)) fail('GLYPH_DISCORD_TOKEN in .env must be 32 to 200 letters, digits, - or _ (openssl rand -hex 32).');
if (app && !/^\d{15,21}$/.test(app)) fail('DISCORD_APP_ID in .env is the Application ID: digits.');
if (guild && !/^\d{15,21}$/.test(guild)) fail('DISCORD_GUILD_ID in .env is a server id: digits.');
if (SETUP && !(bot && glyph)) console.log(dim('  .env lacks DISCORD_BOT_TOKEN or GLYPH_DISCORD_TOKEN: the bot is installed but not started until it has both.'));
if (REGISTER && !app) fail('--register-commands needs DISCORD_APP_ID in .env.');

step([SETUP && 'Setting up the Discord bot', REGISTER && 'registering /ghost'].filter(Boolean).join(', ') + ' (one ssh session)');
const dir = SETUP ? stage() : mkdtempSync(join(tmpdir(), 'glyph-discord-'));
if (!SETUP) writeFileSync(join(dir, 'install.sh'), INSTALL);
let out = '';
try {
  const result = openBox(env, boxSshOptions({ connectTimeout: 20 })).exec(remote, {
    input: Buffer.concat([Buffer.from(`${bot}\n${glyph}\n${app}\n${guild}\n`), tarball(dir, 128 * 1024 * 1024)]),
    stdio: ['pipe', 'pipe', 'inherit'],
    maxBuffer: 16 * 1024 * 1024,
  });
  out = String(result.stdout ?? '');
  process.stdout.write(dim(out.replace(/^/gm, '  ')));
  if (result.status !== 0) {
    if (/^NODE_CHECKSUM_MISMATCH/m.test(out)) fail(`The Node tarball fetched on the box did not match ${NODE_SHA256}: nothing was changed.`);
    if (/^DAVE_MISSING/m.test(out)) fail("The DAVE library's binary would not load on the box (output above).");
    fail(
      result.status === 5 && !/NOT_SET_UP/.test(out)
        ? "ssh refused the password. If .env is right, this is the box's connection lockout - wait it out rather than retrying."
        : /NOT_SET_UP/.test(out)
          ? 'The bot is not set up on the box yet: run this without --register-only first, with the tokens in .env.'
          : 'Remote setup failed (output above).',
    );
  }
} finally {
  rmSync(dir, { recursive: true, force: true });
}

// ---- what it says ---------------------------------------------------------------
const field = (name) => new RegExp(`^${name} (.*)$`, 'm').exec(out)?.[1] ?? '';
step('Health');
console.log(`  ${field('OS')}, glibc ${field('GLIBC')}`);
if (SETUP) {
  if (field('NODE_CHECK') !== 'ok') fail('node --check of the bot failed on the box.');
  ok(`Node ${field('NODE')}, DAVE ${field('DAVE')}, node --check bot.mjs`);
  if (/^CALL yes/m.test(out)) console.log(dim('  a call was being recorded: the new code waits for sudo systemctl restart glyph-discord'));
}
if (REGISTER) {
  if (/^REGISTER_FAILED/m.test(out) || !/^REGISTERED /m.test(out)) fail(`Registering /ghost failed: ${field('REGISTER_FAILED') || 'see above'}.`);
  ok(field('REGISTERED') ? `REGISTERED ${field('REGISTERED')}` : 'registered');
}
const state = field('UNIT_STATE');
console.log(`  glyph-discord ${state || 'unknown'}`);
if (SETUP && bot && glyph && state !== 'active' && !/^CALL yes/m.test(out)) fail(`glyph-discord is ${state}: journalctl -u glyph-discord on the box.`);
ok('done');
