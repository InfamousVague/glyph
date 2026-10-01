# ghostmarkdown.com

The app's own site: what Ghost.md does for a life's notes, how it works with AI, and the ways to get it (docs/DESIGN.md
§153, §154). One short page: the opening with the app on a wide screen; Organise (the home page, journals, boards and
canvases); Work with AI (the phone's own AI and its marked changes, Claude's connector and its address to copy, Notion
and GitHub); Document (meetings written up, with the app's own cassette); Private; the downloads; and a foot with the
app's six themes to try on the site itself.
It lives in `landing/` and ships with `node scripts/deploy-landing.mjs`, one ssh login. It has no npm alias.

- **The files.** `index.html` (the page), `home.css` and `home.js` (its layout, the downloads, the address to copy and
  the theme picker), `site.css` (the fonts, the colours and the reading column every page shares), `theme.js` (the
  theme a visitor picked, on every page before it draws), and the icons, resized from `src-tauri/icons/icon.png`.
- **Only the app's own components show the app** (Matt: "use only real components from the app for things like the
  tape cassette"). What does not move is the app's screens (`shots/`). What moves is the app's code: `parts/` is
  `src/landing/parts.tsx` built by `npm run build:landing` (vite.landing.config.ts) - today the cassette, `TapeArt`,
  which plays on a tap and turns with the site's theme, since site.css hands it the app's names for its two inks. Run
  it when a part changes and commit what it writes: the site is still one directory the deploy tars whole.
- **Glacier.** The site is drawn from the kit's tokens, as the app is: `glacier/tokens.css` is `@glacier/tokens`'s, and
  its type scale, spacing, radii, motion, shadows and the named themes (Dawn, Boreal, Ember) are what `home.css` and
  `site.css` use. The colours are the app's ink (src/app/ink.css): pure grey, light or dark, or the kit's tinted greys
  under a named theme. The two faces, Inter and JetBrains Mono, are served from `fonts/`, so a visit asks nothing of a
  font host. `node scripts/landing-assets.mjs` copies the tokens, the fonts and the ghosts the page wears (`ghosts/`, the
  app's masks, painted in the site's ink) from the kit and the app; run it when either changes and commit what it
  writes.
- **The screens** (`shots/`) are the web build's own, seeded with a handful of notes (and a Product notebook of
  tickets, a query board and table, and a note of to-dos with fields, dated a day back so the home page is as it was) - one with the AI's changes still
  marked, as ai/marks.ts keeps them, and one Claude wrote - and drawn at a phone's size and a desk's in the dark page:
  `npm run build`, `npx vite preview --port 4173`, then `node scripts/landing-shots.mjs` (`PLAYWRIGHT=` the path of `npx playwright`'s copy where there is no global one). Take them again when the
  app's look changes.
- **Plan and Connected** (2026-10-01; Matt: "details about our custom formatting for tickets, boards, queries etc
  and show how Claude can help manage them as well as our notion integration use real company logos"). Plan is a
  query drawn as a ticket board on a desk's screen (`shots/query.webp`), then to-dos with fields, a ticket, a query
  as a table and a board, each with the lines that draw it; Connected is a card for Claude (what to ask it, what it
  will and will not do, the connector's address) and one for Notion. The two logos are Notion's and Claude's own,
  from Simple Icons (`brands/`), drawn inline: Claude's in its orange, Notion's in the page's ink.
- **The formatting reference** (`reference.html`, Matt: "a easy to follow reference sheet for all of the formatting
  base markdown and our custom formatting") is written by `src/landing/reference.ts` from the Academy's lessons, so
  it says what the app teaches: standard Markdown first, then each chapter's own marks, each with its characters,
  what it does and an example to copy (`reference.js`). `src/landing/reference.test.ts` fails while the page is behind
  the lessons; `WRITE_REFERENCE=1 npx vitest run src/landing/reference.test.ts` writes it again.
- **What it says is what the app does.** Each claim is the Guide's, the code's, or docs/store/play/FEATURES.md's; a
  feature that changes is a sentence here to change.
- **The stores** are one line each in `home.js` (`STORES`). Null, a store's button says Coming soon and is not a link;
  set a listing's address there once it is live (Google Play: docs/store/PLAY_STORE.md; the App Store waits on voice
  notes for iOS, docs/store/APP_STORE.md) and it is.

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
  Connect (docs/store/PLAY_STORE.md), and Settings › Account › Privacy policy opens the first. Changing either is a
  landing deploy, not an OTA.
- **The device in hand goes first.** Android gets the APK filled and first, a Mac gets the Mac app, with a line on
  opening an app that isn't notarised yet, and an iPhone or iPad gets the web app, since there's no iOS app.
- **The certificate** is Caddy's own, from Let's Encrypt, for `ghostmarkdown.com`. `www.ghostmarkdown.com` still
  points at the registrar's redirect service, not the box, so it has no block. Point it at the box and add it to the
  block's address line to serve it too.
- **The Caddyfile is shared.** `--caddy` writes only this domain's block, replacing it if it's there. It takes a
  backup, checks every site before and after, runs `caddy validate`, and restores the backup on any difference. The
  same care is described in `scripts/deploy-server.mjs`.
