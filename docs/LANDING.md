# ghostmarkdown.com

The download page: the app icon, the name, one line, and the three ways in. Those are the Android APK, the Mac app,
and the web app on attack.fm. The page lives in `landing/` (index.html and the icons, resized from
src-tauri/icons/icon.png) and ships with `node scripts/deploy-landing.mjs`, one ssh login.

- **The downloads are the release's own files.** The site's Caddy block serves `/glyph.apk`, `/glyph.dmg`,
  `/apk.json` and `/desktop.json` from `/opt/attackfm-site/glyph`, where deploy-ota.mjs publishes them. Every release
  updates this page's downloads, and the version and size it shows, which it reads from the two manifests. Nothing
  here needs redeploying for that.
- **The device in hand goes first.** Android gets the APK filled and first, a Mac gets the Mac app, with a line on
  opening an app that isn't notarised yet, and an iPhone or iPad gets the web app, since there's no iOS app.
- **The certificate** is Caddy's own, from Let's Encrypt, for `ghostmarkdown.com`. `www.ghostmarkdown.com` still
  points at the registrar's redirect service, not the box, so it has no block. Point it at the box and add it to the
  block's address line to serve it too.
- **The Caddyfile is shared.** `--caddy` adds the block only when the domain has none. It takes a backup, checks
  every site before and after, runs `caddy validate`, and restores the backup on any difference. The same care is
  described in scripts/deploy-server.mjs.
