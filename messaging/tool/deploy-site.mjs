#!/usr/bin/env node
/**
 * Ships ghost-sms.com, Ghost Messaging's site (site/), to the box in one ssh session, as Ghost Keyboard's
 * tool/deploy-site.mjs ships ghostkbd.com (Matt, 2026-11-13: "serve it over ghost-sms.com I'll point the domain to
 * the same server ghost kbd uses").
 *
 *   node tool/deploy-site.mjs            the site's files into /opt/ghost-sms-site
 *   node tool/deploy-site.mjs --caddy    that, and the site's block written to /etc/caddy/Caddyfile: added, or put in
 *                                        place of the one there. Needed once, and again when the block below changes.
 *   node tool/deploy-site.mjs --print    the script the box would run, and nothing sent
 *
 * The download and its version are the release's own files (/ghost-messaging.apk and /apk.json, served from
 * /opt/ghost-sms-release by the block), so a release (tool/release.mjs) updates this site's download with nothing to
 * do here. INSTALLED COPIES UPDATE FROM THOSE TWO ADDRESSES (Updater.BASE): a block under which they stop answering
 * is put back, never kept.
 *
 * It uses Ghost.md's box account and its own deploy code, as tool/release.mjs does (this app lives in Ghost.md's
 * repository, so the checkout is the folder above; --glyph <path> or GLYPH_ROOT say otherwise). THE CADDYFILE IS
 * SHARED (attack.fm, ghostmarkdown.com, ghostkbd.com and more), so --caddy is glyph's scripts/deploy-landing.mjs
 * procedure, line for line: it touches only ghost-sms.com's own block; a timestamped backup; every other site asked
 * for its page before; the block written; `caddy validate`; a reload; every other site asked again; a failed
 * validate, or any site answering differently, puts the backup back. Caddy gets the certificate by itself, once the
 * domain's DNS points at the box. The box counts logins: this spends one.
 */
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SITE_DIR = join(ROOT, 'site');
const SITE = '/opt/ghost-sms-site';
const RELEASE = '/opt/ghost-sms-release';
const APK = 'ghost-messaging.apk';
// The Mac app's (tool/release-mac.mjs): what an installed copy reads, and the zip it updates itself from.
const MAC_ZIP = 'ghost-messaging-mac.zip';
const DOMAIN = 'ghost-sms.com';
const args = process.argv.slice(2);
const withCaddy = args.includes('--caddy');
const printOnly = args.includes('--print');
const fail = (message) => { console.error(`x ${message}`); process.exit(1); };

if (!existsSync(join(SITE_DIR, 'index.html'))) fail('No site/index.html to ship.');
const at = args.indexOf('--glyph');
const glyph = [at >= 0 ? args[at + 1] : null, process.env.GLYPH_ROOT, join(ROOT, '..'), join(ROOT, '..', 'glyph'), join(homedir(), 'Development/Apps/glyph')]
  .filter(Boolean)
  .find((dir) => existsSync(join(dir, 'tauri/scripts/lib/box.mjs')));
if (!glyph && !printOnly) fail('No Ghost.md checkout found for its box code (--glyph <path> or GLYPH_ROOT).');

// www answers with a redirect to the bare name. The release's two files come from the release's own folder; every
// other address is the site's. Nothing is cached hard: the site is small and changes with the app.
const BLOCK = `
${DOMAIN} {
	encode zstd gzip
	# The release's own files (tool/release.mjs, tool/release-mac.mjs), so a release updates this site's download
	# and version. Installed copies update from these addresses (the phone's Updater.BASE, the Mac's macFeed): they
	# must never stop answering.
	@release path /${APK} /apk.json /${MAC_ZIP} /mac.json
	handle @release {
		root * ${RELEASE}
		header Cache-Control "no-cache"
		file_server
	}
	handle {
		root * ${SITE}
		header Cache-Control "no-cache"
		header X-Content-Type-Options "nosniff"
		header Referrer-Policy "strict-origin-when-cross-origin"
		file_server
	}
}
www.${DOMAIN} {
	redir https://${DOMAIN}{uri} permanent
}
`;

const dom = DOMAIN.replace('.', '[.]');
// Run on the box. Reads the site as a tarball on stdin.
const REMOTE = `set -e
SUDO=; [ "$(id -u)" -eq 0 ] || SUDO=sudo
STAGE="$HOME/.ghost-sms-site-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"; tar xzf - -C "$STAGE"
[ -f "$STAGE/index.html" ] || { echo "x the site arrived without its index.html"; exit 1; }
$SUDO mkdir -p ${SITE}.next
$SUDO rm -rf ${SITE}.next/*
$SUDO cp -a "$STAGE"/. ${SITE}.next/
$SUDO chmod -R a+rX ${SITE}.next
# Swapped in whole, so a visitor never gets a page of one version with scripts of another.
if [ -d ${SITE} ]; then $SUDO rm -rf ${SITE}.old; $SUDO mv ${SITE} ${SITE}.old; fi
$SUDO mv ${SITE}.next ${SITE}
$SUDO rm -rf ${SITE}.old
rm -rf "$STAGE"
echo "ok site in ${SITE}: $(ls ${SITE} | tr '\\n' ' ')"
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
# What installed copies update from. Where it answered before, it must answer after.
feeds() { for p in /apk.json /${APK}; do curl -s -o /dev/null -w "$p %{http_code}\\n" -I --max-time 10 --resolve "${DOMAIN}:443:127.0.0.1" "https://${DOMAIN}$p" || true; done; }
FEEDS=$(feeds)
BEFORE=$(probe | grep -v -E '^(www[.])?${dom} ' || true)
echo "before:"; echo "$BEFORE" | sed 's/^/  /'
restore() { echo "x $1: putting $BACKUP back"; $SUDO cp -a "$BACKUP" "$CF"; $SUDO systemctl reload caddy || true; exit 1; }
# The domain's own blocks out, if they are there - each from its first line to the next brace at the start of a line -
# and the new ones on the end.
$SUDO awk -v start='^(www[.])?${dom}[ ,{]' '$0 ~ start { skip = 1; next } skip && /^}/ { skip = 0; next } !skip' "$CF" | $SUDO tee "$CF.next" >/dev/null
printf '%s\\n' '${BLOCK.replace(/'/g, "'\\''")}' | $SUDO tee -a "$CF.next" >/dev/null
# Copied onto the Caddyfile rather than moved over it, so the file keeps its owner and its mode.
$SUDO cp "$CF.next" "$CF"; $SUDO rm -f "$CF.next"
echo "the new blocks:"; $SUDO awk -v start='^(www[.])?${dom}[ ,{]' '$0 ~ start { on = 1 } on { print "  " $0 } on && /^}/ { on = 0 }' "$CF"
$SUDO caddy validate --config "$CF" --adapter caddyfile >/dev/null 2>&1 || restore "caddy validate refused it"
$SUDO systemctl reload caddy || restore "caddy would not reload"
sleep 4
AFTER=$(probe | grep -v -E '^(www[.])?${dom} ' || true)
echo "after:"; echo "$AFTER" | sed 's/^/  /'
[ "$BEFORE" = "$AFTER" ] || restore "a site answers differently after the reload"
if [ "$FEEDS" = "$(printf '/apk.json 200\\n/${APK} 200')" ]; then
  [ "$(feeds)" = "$FEEDS" ] || restore "https://${DOMAIN}/apk.json or /${APK} no longer answers, and installed copies update from them"
  echo "ok /apk.json and /${APK} answer as before"
fi
echo "ok ${DOMAIN}'s blocks written and live"
`;

console.log(`> Shipping ${DOMAIN}${withCaddy ? ' and its Caddy blocks' : ''} (one ssh session)`);
if (printOnly) {
  process.stdout.write(REMOTE);
  process.exit(0);
}

const { BOX_ENV_KEYS, boxSshOptions, openBox, tarball } = await import(pathToFileURL(join(glyph, 'tauri/scripts/lib/box.mjs')).href);
const { loadEnv } = await import(pathToFileURL(join(glyph, 'scripts/lib/env.mjs')).href);
const site = tarball(SITE_DIR, 64 * 1024 * 1024);
const env = loadEnv(BOX_ENV_KEYS);
const box = openBox(env, boxSshOptions({ connectTimeout: 20, knownHosts: join(homedir(), '.ssh', 'known_hosts') }));
box.logIn();
const result = box.exec(REMOTE, { input: site, stdio: ['pipe', 'inherit', 'inherit'] });
if (!args.includes('--keep-connection')) box.close();
if (result.status !== 0) fail(result.status === 5 ? 'ssh refused the password: if .env is right, this is the box\'s lockout; wait it out.' : 'The remote step failed (output above).');

// From here, as a visitor would: the page, the version, and the download's headers.
const curl = (a) => spawnSync('curl', ['-s', '--max-time', '15', ...a], { encoding: 'utf8' });
const page = curl(['-o', '/dev/null', '-w', '%{http_code}', `https://${DOMAIN}/`]).stdout;
const info = curl(['-o', '/dev/null', '-w', '%{http_code}', `https://${DOMAIN}/apk.json`]).stdout;
const apk = curl(['-o', '/dev/null', '-w', '%{http_code}', '-r', '0-0', `https://${DOMAIN}/${APK}`]).stdout;
console.log(`  https://${DOMAIN}/ answers ${page || 'nothing yet'}; /apk.json ${info || 'nothing yet'}; /${APK} ${apk || 'nothing yet'} (404 for those two until the first tool/release.mjs)`);
if (page !== '200') console.log('  (a certificate can take a minute, or longer while the domain\'s DNS settles: Caddy keeps trying.)');
