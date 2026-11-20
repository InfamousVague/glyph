#!/usr/bin/env node
/**
 * Ships gogho.st (before 2026-11-15, ghost-sms.com), Ghost Messaging's site (site/), to the box in one ssh session, as Ghost Keyboard's
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
 * procedure, line for line: it touches only gogho.st's and ghost-sms.com's own blocks; a timestamped backup; every other site asked
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
// The Mac download as the site offers it, a notarised disk image (tool/release-mac.mjs; Matt, 2026-11-19: "deploy it from a dmg").
const MAC_DMG = 'ghost-messaging-mac.dmg';
const DOMAIN = 'gogho.st';
// The site's first address (Matt, 2026-11-15: "I got the domain gogho.st hooked up the box, please update all the links
// in app and everything to point through that domain instead of the ghost-sms one also point that domain to the
// website"). It still answers what copies installed before the move ask of it - their updates and the relay - and
// the relay's sign-in pages (/link/*, whose addresses Discord, X and Telegram were given); anything else there goes
// to the same address on gogho.st. /discord/* answers on both names (the Discord presence bot, tool/deploy-discord.mjs).
const OLD = 'ghost-sms.com';
const args = process.argv.slice(2);
const withCaddy = args.includes('--caddy');
const printOnly = args.includes('--print');
const fail = (message) => { console.error(`x ${message}`); process.exit(1); };

if (!existsSync(join(SITE_DIR, 'index.html'))) fail('No site/index.html to ship.');
// The App Links file goes with the rest (the tarball takes dot folders too): without it, installed copies stop
// opening gogho.st/join links straight away the next time Android checks.
if (!existsSync(join(SITE_DIR, '.well-known', 'assetlinks.json'))) fail('No site/.well-known/assetlinks.json to ship.');
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
	@release path /${APK} /apk.json /${MAC_ZIP} /${MAC_DMG} /mac.json /ghost-messaging-setup.exe /windows.json
	handle @release {
		root * ${RELEASE}
		header Cache-Control "no-cache"
		file_server
	}
	# The relay (relay/, tool/deploy-relay.mjs): a phone and the computer it is paired with at /relay/<channel>, and
	# the hub two people's apps find each other through at /hub. WebSockets, passed to the service on this box.
	# The port is tool/deploy-relay.mjs's PORT: the two must agree. /link/* is the same service's pages for signing
	# in with a network to link an account (relay/lib/handles.dart, docs/me.md): what Discord, X and Telegram send
	# a person back to.
	@relay path /hub /relay/* /link/*
	handle @relay {
		reverse_proxy 127.0.0.1:18787
	}
	# Files spaces' sealed files (relay/lib/files.dart): plain HTTP to the same service. A file goes up in pieces of at
	# most 8 MB (the relay's maxBody), so no request needs more than this; a download streams back with Range. Not
	# buffered here either way: flush_interval -1 passes each piece on as it comes.
	# Timeouts (Matt, 2026-11-17: "Finish the missing pieces that went unfinished"): the relay must be reached at once,
	# and must answer within two minutes of a request's last byte arriving (it answers a piece once it has it, a log
	# page or a delete at once). Neither runs while a body is still coming, so a slow phone's 8 MB piece is not cut
	# off. A body that stops coming is the relay's to end (files.dart's bodyPause, 30 s without a byte): Caddy's own
	# read_body timeout is for every site on this box, not one route, so it is not set here.
	@files path /files /files/* /feedback
	handle @files {
		request_body {
			max_size 10MB
		}
		reverse_proxy 127.0.0.1:18787 {
			flush_interval -1
			transport http {
				dial_timeout 5s
				response_header_timeout 2m
			}
		}
	}
	# The Discord presence bot (discord/, tool/deploy-discord.mjs): a linked Discord server's voice channels and who
	# is in them, for the app's spaces. Passed on with the /discord prefix kept; the port is that script's PORT.
	@discord path /discord /discord/*
	handle @discord {
		reverse_proxy 127.0.0.1:18788
	}
	# Android App Links (site/.well-known/assetlinks.json): what Android reads to open gogho.st/join links in the app
	# straight away (Matt, 2026-11-17: invites texted to contacts). It must answer 200 as application/json, with no
	# redirect, so it is served here by itself.
	@assetlinks path /.well-known/assetlinks.json
	handle @assetlinks {
		root * ${SITE}
		header Content-Type "application/json"
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
${OLD} {
	encode zstd gzip
	@release path /${APK} /apk.json /${MAC_ZIP} /${MAC_DMG} /mac.json /ghost-messaging-setup.exe /windows.json
	handle @release {
		root * ${RELEASE}
		header Cache-Control "no-cache"
		file_server
	}
	@relay path /hub /relay/* /link/*
	handle @relay {
		reverse_proxy 127.0.0.1:18787
	}
	@files path /files /files/* /feedback
	handle @files {
		request_body {
			max_size 10MB
		}
		reverse_proxy 127.0.0.1:18787 {
			flush_interval -1
			transport http {
				dial_timeout 5s
				response_header_timeout 2m
			}
		}
	}
	@discord path /discord /discord/*
	handle @discord {
		reverse_proxy 127.0.0.1:18788
	}
	handle {
		redir https://${DOMAIN}{uri} permanent
	}
}
www.${OLD} {
	redir https://${DOMAIN}{uri} permanent
}
`;

// Both names' blocks are this site's: each is taken out and written again.
const dom = `(${DOMAIN.replace('.', '[.]')}|${OLD.replace('.', '[.]')})`;
// Run on the box. Reads the site as a tarball on stdin.
const REMOTE = `set -e
SUDO=; [ "$(id -u)" -eq 0 ] || SUDO=sudo
STAGE="$HOME/.ghost-sms-site-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"; tar xzf - -C "$STAGE"
[ -f "$STAGE/index.html" ] || { echo "x the site arrived without its index.html"; exit 1; }
[ -f "$STAGE/.well-known/assetlinks.json" ] || { echo "x the site arrived without .well-known/assetlinks.json"; exit 1; }
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
feeds() { for p in /apk.json /${APK}; do curl -s -o /dev/null -w "$p %{http_code}\\n" -I --max-time 10 --resolve "${OLD}:443:127.0.0.1" "https://${OLD}$p" || true; done; }
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
  [ "$(feeds)" = "$FEEDS" ] || restore "https://${OLD}/apk.json or /${APK} no longer answers, and copies installed before gogho.st update from them"
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
const links = curl(['-o', '/dev/null', '-w', '%{http_code} %{content_type}', `https://${DOMAIN}/.well-known/assetlinks.json`]).stdout;
console.log(`  https://${DOMAIN}/.well-known/assetlinks.json answers ${links || 'nothing yet'} (200 application/json once the block from --caddy is live)`);
console.log(`  https://${DOMAIN}/ answers ${page || 'nothing yet'}; /apk.json ${info || 'nothing yet'}; /${APK} ${apk || 'nothing yet'} (404 for those two until the first tool/release.mjs)`);
if (page !== '200') console.log('  (a certificate can take a minute, or longer while the domain\'s DNS settles: Caddy keeps trying.)');
