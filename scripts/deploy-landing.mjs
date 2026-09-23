#!/usr/bin/env node
/**
 * Ships ghostmarkdown.com, the download page (landing/, docs/LANDING.md), to the box in one ssh session.
 *
 *   node scripts/deploy-landing.mjs            the page's files into /opt/ghostmarkdown-site
 *   node scripts/deploy-landing.mjs --caddy    that, and the site's block added to /etc/caddy/Caddyfile if it has none
 *
 * The page's downloads and the manifests it reads its versions from are the release's own files, served from
 * /opt/attackfm-site/glyph by the site block, so a release (deploy-ota.mjs) updates this page with nothing to do here.
 *
 * THE CADDYFILE IS SHARED: attack.fm, the registry, prettycardboard.com and more are on it. So --caddy touches it only
 * when ghostmarkdown.com is not already there, and only this way: a timestamped backup; every site on it asked for its
 * page, on the box, before; the block appended; `caddy validate`; a reload; every site asked again. A validate that
 * fails, or any site answering differently after, puts the backup back and reloads it. Caddy then gets the
 * certificate from Let's Encrypt by itself, and retries on its own while the domain's DNS is still settling.
 *
 * The box counts connections, not deploys (deploy-ota.mjs): this spends ONE. The password reaches sshpass through
 * SSHPASS, read from .env, never an argument.
 */
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const LANDING = join(ROOT, 'landing');
const SITE = '/opt/ghostmarkdown-site';
const RELEASE = '/opt/attackfm-site/glyph';
const DOMAIN = 'ghostmarkdown.com';
const withCaddy = process.argv.includes('--caddy');

const fail = (message) => {
  console.error(`\x1b[31mx\x1b[0m ${message}`);
  process.exit(1);
};

function loadEnv() {
  const path = join(ROOT, '.env');
  if (!existsSync(path)) fail(`No .env at ${path} (needs AFM_DEPLOY_HOST / AFM_DEPLOY_USER / AFM_DEPLOY_PASS).`);
  const env = {};
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    const match = /^\s*(?:export\s+)?([A-Z0-9_]+)\s*=\s*(.*)\s*$/.exec(line);
    if (match) env[match[1]] = match[2].trim().replace(/^['"]|['"]$/g, '');
  }
  for (const key of ['AFM_DEPLOY_HOST', 'AFM_DEPLOY_USER', 'AFM_DEPLOY_PASS']) if (!env[key]) fail(`.env is missing ${key}.`);
  return env;
}

if (!existsSync(join(LANDING, 'index.html'))) fail('No landing/index.html to ship.');

const BLOCK = `
${DOMAIN} {
	encode zstd gzip
	# The release's own files, so a release updates this page's downloads and versions (scripts/deploy-landing.mjs).
	@release path /glyph.apk /glyph.dmg /apk.json /desktop.json
	handle @release {
		root * ${RELEASE}
		header Cache-Control "no-cache"
		file_server
	}
	handle {
		root * ${SITE}
		file_server
	}
}
`;

// Run on the box. Reads the page as a tarball on stdin.
const REMOTE = `set -e
SUDO=; [ "$(id -u)" -eq 0 ] || SUDO=sudo
STAGE="$HOME/.ghostmd-landing-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"; tar xzf - -C "$STAGE"
$SUDO mkdir -p ${SITE}
$SUDO cp -a "$STAGE"/. ${SITE}/
$SUDO chmod -R a+rX ${SITE}
rm -rf "$STAGE"
echo "ok page in ${SITE}: $(ls ${SITE} | tr '\\n' ' ')"
[ "${withCaddy ? 1 : 0}" = 1 ] || exit 0
CF=/etc/caddy/Caddyfile
if $SUDO grep -qE '^${DOMAIN.replace('.', '\\.')}[ ,{]' "$CF"; then echo "ok ${DOMAIN} is already on the Caddyfile: left as it is"; exit 0; fi
# Every site on the Caddyfile, asked for its page on the box itself, by name.
probe() {
  for h in $($SUDO grep -E '^[a-z0-9][a-z0-9.:/, -]*[{]' "$CF" | sed 's/{.*//; s/,/ /g'); do
    h=\${h#http://}; h=\${h#https://}; h=\${h%%:*}
    [ -n "$h" ] || continue
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 --resolve "$h:443:127.0.0.1" "https://$h/" || true)
    echo "$h $code"
  done | sort
}
BACKUP="$CF.bak-$(date +%Y%m%d-%H%M%S)"
$SUDO cp -a "$CF" "$BACKUP"
echo "ok backup $BACKUP"
BEFORE=$(probe)
echo "before:"; echo "$BEFORE" | sed 's/^/  /'
restore() { echo "x $1: putting $BACKUP back"; $SUDO cp -a "$BACKUP" "$CF"; $SUDO systemctl reload caddy || true; exit 1; }
printf '%s\\n' '${BLOCK.replace(/'/g, "'\\''")}' | $SUDO tee -a "$CF" >/dev/null
$SUDO caddy validate --config "$CF" --adapter caddyfile >/dev/null 2>&1 || restore "caddy validate refused it"
$SUDO systemctl reload caddy || restore "caddy would not reload"
sleep 4
AFTER=$(probe | grep -v '^${DOMAIN} ' || true)
echo "after:"; echo "$AFTER" | sed 's/^/  /'
[ "$BEFORE" = "$AFTER" ] || restore "a site answers differently after the reload"
echo "ok ${DOMAIN} added; Caddy is getting its certificate"
`;

const tar = spawnSync('tar', ['-czf', '-', '--no-xattrs', '--no-mac-metadata', '-C', LANDING, '.'], { maxBuffer: 64 * 1024 * 1024 });
if (tar.status !== 0) fail(`tar failed: ${String(tar.stderr)}`);
const SSH_OPTS = ['-o', 'StrictHostKeyChecking=no', '-o', 'ConnectTimeout=20', '-o', 'NumberOfPasswordPrompts=1', '-o', `UserKnownHostsFile=${join(homedir(), '.ssh', 'known_hosts')}`];
console.log(`> Shipping ${DOMAIN}${withCaddy ? ' and its Caddy block' : ''} (one ssh session)`);
// --print: the script the box would run, for reading before it does.
if (process.argv.includes('--print')) {
  process.stdout.write(REMOTE);
  process.exit(0);
}
const env = loadEnv();
const result = spawnSync('sshpass', ['-e', 'ssh', ...SSH_OPTS, `${env.AFM_DEPLOY_USER}@${env.AFM_DEPLOY_HOST}`, REMOTE], {
  input: tar.stdout,
  stdio: ['pipe', 'inherit', 'inherit'],
  env: { ...process.env, SSHPASS: env.AFM_DEPLOY_PASS },
});
if (result.status !== 0) fail(result.status === 5 ? 'ssh refused the password: if .env is right, this is the box\'s lockout; wait it out.' : 'The remote step failed (output above).');

// From here, as a visitor would: the page, and a download's headers.
const curl = (args) => spawnSync('curl', ['-s', '--max-time', '15', ...args], { encoding: 'utf8' });
const page = curl(['-o', '/dev/null', '-w', '%{http_code}', `https://${DOMAIN}/`]).stdout;
const apk = curl(['-o', '/dev/null', '-w', '%{http_code} %{size_download}', '-r', '0-0', `https://${DOMAIN}/glyph.apk`]).stdout;
console.log(`  https://${DOMAIN}/ answers ${page || 'nothing yet'}; /glyph.apk ${apk || 'nothing yet'}`);
if (page !== '200') console.log('  (a certificate can take a minute, or longer while the domain\'s DNS settles: Caddy keeps trying.)');
