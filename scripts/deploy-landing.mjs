#!/usr/bin/env node
/**
 * Ships ghostmarkdown.com, the download page (landing/, docs/LANDING.md), to the box in one ssh session.
 *
 *   node scripts/deploy-landing.mjs            the page's files into /opt/ghostmarkdown-site
 *   node scripts/deploy-landing.mjs --caddy    that, and the site's block written to /etc/caddy/Caddyfile: added, or put in place of the one there
 *
 * The page's downloads and the manifests it reads its versions from are the release's own files, served from
 * /opt/attackfm-site/glyph by the site block, so a release (deploy-ota.mjs) updates this page with nothing to do here.
 *
 * The reader page for shared notes is the release's too (/read.html, /assets/*, /favicon.svg): share links are
 * `https://ghostmarkdown.com/read.html#…` (share/share.ts READER_URL), and the page they open is whatever the last
 * release published, beside the app on attack.fm.
 *
 * THE CADDYFILE IS SHARED: attack.fm, the registry, prettycardboard.com and more are on it. So --caddy touches only
 * ghostmarkdown.com's own block (from its first line to the closing brace at the start of a line), and only this way:
 * a timestamped backup; every other site on it asked for its page, on the box, before; the block written; `caddy
 * validate`; a reload; every other site asked again. A validate that
 * fails, or any site answering differently after, puts the backup back and reloads it. Caddy then gets the
 * certificate from Let's Encrypt by itself, and retries on its own while the domain's DNS is still settling.
 *
 * The box counts connections, not deploys (deploy-ota.mjs): this spends ONE. The password reaches sshpass through
 * SSHPASS, read from .env, never an argument.
 */
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { boxSshOptions, openBox, tarball } from './lib/box.mjs';
import { loadEnv } from './lib/env.mjs';
import { ROOT } from './lib/paths.mjs';
import { fail } from './lib/say.mjs';

const LANDING = join(ROOT, 'landing');
const SITE = '/opt/ghostmarkdown-site';
const RELEASE = '/opt/attackfm-site/glyph';
const DOMAIN = 'ghostmarkdown.com';
const withCaddy = process.argv.includes('--caddy');

if (!existsSync(join(LANDING, 'index.html'))) fail('No landing/index.html to ship.');

const BLOCK = `
${DOMAIN} {
	encode zstd gzip
	# The release's own files, so a release updates this page's downloads and versions (scripts/deploy-landing.mjs).
	# And the reader page shared links open, with its scripts, styles and icon.
	@release path /glyph.apk /glyph.dmg /apk.json /desktop.json /read.html /assets/* /favicon.svg
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
BEFORE=$(probe | grep -v '^${DOMAIN} ' || true)
echo "before:"; echo "$BEFORE" | sed 's/^/  /'
restore() { echo "x $1: putting $BACKUP back"; $SUDO cp -a "$BACKUP" "$CF"; $SUDO systemctl reload caddy || true; exit 1; }
# The domain's own block out, if it is there - its first line to the next brace at the start of a line - and the new
# one on the end.
$SUDO awk -v start='^${DOMAIN.replace('.', '[.]')}[ ,{]' '$0 ~ start { skip = 1; next } skip && /^}/ { skip = 0; next } !skip' "$CF" | $SUDO tee "$CF.next" >/dev/null
printf '%s\\n' '${BLOCK.replace(/'/g, "'\\''")}' | $SUDO tee -a "$CF.next" >/dev/null
# Copied onto the Caddyfile rather than moved over it, so the file keeps its owner and its mode.
$SUDO cp "$CF.next" "$CF"; $SUDO rm -f "$CF.next"
echo "the new block:"; $SUDO awk -v start='^${DOMAIN.replace('.', '[.]')}[ ,{]' '$0 ~ start { on = 1 } on { print "  " $0 } on && /^}/ { on = 0 }' "$CF"
$SUDO caddy validate --config "$CF" --adapter caddyfile >/dev/null 2>&1 || restore "caddy validate refused it"
$SUDO systemctl reload caddy || restore "caddy would not reload"
sleep 4
AFTER=$(probe | grep -v '^${DOMAIN} ' || true)
echo "after:"; echo "$AFTER" | sed 's/^/  /'
[ "$BEFORE" = "$AFTER" ] || restore "a site answers differently after the reload"
echo "ok ${DOMAIN}'s block written and live"
`;

const site = tarball(LANDING, 64 * 1024 * 1024);
// Its own connection, not deploy-ota's shared one: one login of its own every run.
const SSH_OPTS = boxSshOptions({ connectTimeout: 20, shareConnection: false, knownHosts: join(homedir(), '.ssh', 'known_hosts') });
console.log(`> Shipping ${DOMAIN}${withCaddy ? ' and its Caddy block' : ''} (one ssh session)`);
// --print: the script the box would run, for reading before it does.
if (process.argv.includes('--print')) {
  process.stdout.write(REMOTE);
  process.exit(0);
}
const env = loadEnv(['AFM_DEPLOY_HOST', 'AFM_DEPLOY_USER', 'AFM_DEPLOY_PASS']);
const result = openBox(env, SSH_OPTS).exec(REMOTE, {
  input: site,
  stdio: ['pipe', 'inherit', 'inherit'],
});
if (result.status !== 0) fail(result.status === 5 ? 'ssh refused the password: if .env is right, this is the box\'s lockout; wait it out.' : 'The remote step failed (output above).');

// From here, as a visitor would: the page, and a download's headers.
const curl = (args) => spawnSync('curl', ['-s', '--max-time', '15', ...args], { encoding: 'utf8' });
const page = curl(['-o', '/dev/null', '-w', '%{http_code}', `https://${DOMAIN}/`]).stdout;
const apk = curl(['-o', '/dev/null', '-w', '%{http_code} %{size_download}', '-r', '0-0', `https://${DOMAIN}/glyph.apk`]).stdout;
console.log(`  https://${DOMAIN}/ answers ${page || 'nothing yet'}; /glyph.apk ${apk || 'nothing yet'}`);
if (page !== '200') console.log('  (a certificate can take a minute, or longer while the domain\'s DNS settles: Caddy keeps trying.)');
