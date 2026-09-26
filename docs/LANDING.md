# ghostmarkdown.com

The download page: the app icon, the name, one line, and the three ways in. Those are the Android APK, the Mac app,
and the web app on attack.fm. The page lives in `landing/` (`landing/index.html`, `landing/site.css` and the icons,
resized from `src-tauri/icons/icon.png`) and ships with `node scripts/deploy-landing.mjs`, one ssh login. It has no
npm alias.

- **The downloads are the release's own files.** The site's Caddy block serves `/glyph.apk`, `/glyph.dmg`,
  `/apk.json` and `/desktop.json` from `/opt/attackfm-site/glyph`, where deploy-ota.mjs publishes them. Every release
  updates this page's downloads, and the version and size it shows, which it reads from the two manifests. Nothing
  here needs redeploying for that.
- **Shared notes open here too.** Share links are `ghostmarkdown.com/read.html#…` (`src/app/share/share.ts`). The block also
  serves `/read.html`, `/assets/*` and `/favicon.svg` from the release, so the reader is always the latest release's.
  The share service allows this origin (`server/src/main.rs` `ORIGINS`). The web app itself stays on attack.fm, since
  this domain doesn't route `/glyph/api`.
- **The privacy policy and the delete-account page are here**, linked from the page's foot:
  `landing/privacy.html` and `landing/delete-account.html`. They are the addresses given to Play Console and App Store
  Connect (docs/store/PLAY_STORE.md), and Settings › About › Privacy policy opens the first. Changing either is a
  landing deploy, not an OTA.
- **The device in hand goes first.** Android gets the APK filled and first, a Mac gets the Mac app, with a line on
  opening an app that isn't notarised yet, and an iPhone or iPad gets the web app, since there's no iOS app.
- **The certificate** is Caddy's own, from Let's Encrypt, for `ghostmarkdown.com`. `www.ghostmarkdown.com` still
  points at the registrar's redirect service, not the box, so it has no block. Point it at the box and add it to the
  block's address line to serve it too.
- **The Caddyfile is shared.** `--caddy` writes only this domain's block, replacing it if it's there. It takes a
  backup, checks every site before and after, runs `caddy validate`, and restores the backup on any difference. The
  same care is described in `scripts/deploy-server.mjs`.
