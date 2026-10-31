# ghostmarkdown.com

The app's own site: what sets Ghost.md apart, the notes app under it, and the ways to get it (docs/DESIGN.md §153,
§154). Since 2026-10-18 (Matt: "redo the website and the app store listing to highlight more important features that
set us apart like the claude integrations and calendar integrations as well as notion etc") the page runs: the opening
(the app on a wide screen, and a row of what it works with); **Claude** (the app's own Claude with your key,
docs/CLAUDE_APP.md, and Claude's own apps through the connector, docs/CLAUDE_LIVE.md, with its address to copy);
**Calendar** (docs/CALENDAR.md); **Plugins** (Notion's card, then the catalog's other plugins as tiles,
tauri/docs/PLUGINS.md "In the Flutter app", docs/INTEGRATIONS.md); then the core: Plain Markdown (home, journals, boards,
canvases), Voice (with the app's own cassette), Plan, Your files, Teams, Version history, Private; the downloads; and a
foot with the app's six themes to try on the site itself.

- **Per platform, as the code says.** Claude in the app, Calendar and the plugin catalog are the Flutter app's
  (Android, iPhone, Mac); Windows and the browser are still the Tauri app. Talk to Claude, Speak and meetings are not
  on the iPhone (lib/core/iphone_app.dart `recordsVoice`); Notion and Slack are not on the iPhone yet (`notOnIPhone`);
  place reminders are Android's. A line on the page says so wherever it matters.
- **Placeholders** (2026-10-18): the Claude pair (`shots/claude.webp`, `shots/ai.webp`), Calendar's phone
  (`shots/fields.webp`) and Plugins' phone (`shots/board.webp`) stand in for the new iPhone screens (the Claude chat,
  Claude typing, Today with its events, the plugins catalog or Notion's page). Each slot has a comment in index.html.
It lives in `landing/` and ships with `node scripts/deploy-landing.mjs`, one ssh login. It has no npm alias.

- **Ghost.md Docs at /docs/** (2026-10-26, Matt: "build an entire docs book build it using ghost markdown but host it
  publicly from the website so that people can read the docs"). The book is `docs/book/` at the repository's root
  (`index.md`, a notebook with `##` parts, and `chapters/NN-slug.md`), drawn by the reader's own site layout
  (`src/read/Site.tsx`) with the app's read-only editor: `docs.html` and `src/docs/`, built by `npm run build:docs`
  (`vite.docs.config.ts`, base `/docs/`) into `landing/docs/`, every page also at `landing/docs/<slug>/index.html` with
  its own title, description and canonical address. It is not committed (about 15 MB of hashed assets):
  deploy-landing builds it first, `--no-docs` to skip. The Caddy block's `handle /docs/*` sends an address with no
  page to the index (`try_files`), which says so.

- **Ten explorations** (2026-10-31; Matt: "Create ten versions of the website with different content densities and
  layouts look at apps like notion discord and other developer tools like git for inspiration"): `landing/explore/`,
  an index and ten standalone pages, `01-air` to `10-specs`, each after a site worth borrowing from (Notion, Discord,
  GitHub, Vercel, a README, Raycast, a product tour, Apple, Linear's changelog, a spec sheet), from a sentence a screen
  to a spec sheet. They share the site's tokens and colours and `explore.css` (pills, the icon on its hue square, the
  frames, the strip that flips between them); the words and screens are the home page's own, every download and
  address real. `09-feed` reads `explore/changelog.json`, a copy of `assets/changelog.json` taken that day. Every page
  is `noindex`; the deploy ships the folder with the rest. When one is chosen, it becomes `index.html` and the rest go.
- **The files.** `index.html` (the page), `home.css` and `home.js` (its layout, the downloads, the address to copy and
  the theme picker), `site.css` (the fonts, the colours and the reading column every page shares), `theme.js` (the
  theme a visitor picked, on every page before it draws), and the icons, resized from `src-tauri/icons/icon.png`.
- **Only the app's own components show the app** (Matt: "use only real components from the app for things like the
  tape cassette"). What does not move is the app's screens (`shots/`). What moves is the app's code: `parts/` is
  `src/landing/parts.tsx` built by `npm run build:landing` (vite.landing.config.ts) - today the cassette, `TapeArt`,
  which plays on a tap and turns with the site's theme, since site.css hands it the app's names for its two inks. Run
  it when a part changes and commit what it writes: the site is still one directory the deploy tars whole. The
  cassette is silent: a tap turns its reels and runs its counter, and no recording of anybody is behind it (Matt:
  "make sure the recorded meeting on the website doesn't use real audio"). `src/landing/silent.test.ts` fails if a
  sound file or a way of playing one ever reaches the site.
- **Glacier.** The site is drawn from the kit's tokens, as the app is: `glacier/tokens.css` is `@glacier/tokens`'s, and
  its type scale, spacing, radii, motion, shadows and the named themes (Dawn, Boreal, Ember) are what `home.css` and
  `site.css` use. The colours are the app's ink (src/app/ink.css): pure grey, light or dark, or the kit's tinted greys
  under a named theme. The two faces, Inter and JetBrains Mono, are served from `fonts/`, so a visit asks nothing of a
  font host. `node scripts/landing-assets.mjs` copies the tokens and the fonts from the kit; run it when the kit
  changes and commit what it writes. The page wears none of the app's ghosts: the two over Private and Get Ghost.md
  went on 2026-10-01 (Matt: "Remove the two ghost mascot images from the website towards the bottom").
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
- **Your files** (2026-10-01; Matt: "an example on the website of how data is stored in plain markdown and show a
  breakdown of files and folders for a given workspace example"): a Product workspace as the library lays it out
  (docs/LIBRARY.md): `Library/workspaces/Product/` and its notes, `Inbox/`, the hidden `.glyph/`, and `recordings/`
  and `images/` beside the library. A tap on a file shows it as it is on disk, the library's block (id, created,
  pinned, source) and then the page's (a ticket's fields, a notebook's key) (`files.js`, the files' words in
  `<template>`s beside the tree). Written by hand from the library's rules: when they change, so does this.
- **Teams** (2026-10-05; Matt: "Update the marketing site to include info about collaboration live cursors and
  organizations"): a section between Your files and Version history, and Teams in the bar. Six cards, each something
  the app does now (docs/TEAMS.md, docs/SHARED.md slices 1 to 4): organizations by handle or link, live cursors in each
  member's colour, who is editing what with Jump to cursor, comments in the note's own Markdown, version history and
  the audit log, the organization key, and Slack. Canvases are not live for a team yet (SHARED.md slice 5), so the page
  says nothing of them; when they are, this is a sentence to add.
- **Version history** (2026-10-04; Matt: "add information about versioning to the website"): a section after Your
  files, and `Launch plan.versions` in its tree beside `Launch plan.md` (docs/DESIGN.md §182). The file shown is a real
  one, written by the app's own `core/versions/file.ts` for three versions of the Launch plan note, so its hashes check:
  when the format changes, write it again the same way rather than by hand. There is no picture of the timeline: the
  app's screens are `shots/`, and none is taken of it yet.
- **Icons are Lucide's**, the app's own set (`@glacier/icons` proxies lucide-react; Matt: "use lucide icons for both,
  add iconography across the whole website"): `icons.svg` is a sprite of every icon the pages name, drawn as
  `<svg class="i"><use href="icons.svg#i-folder"/></svg>` in the text's ink. `node scripts/landing-icons.mjs` writes
  it from lucide-react's own data and the names in `landing/*.html`, and stops on a name Lucide does not have; run it
  after adding an icon to a page. The reference page's marks wear the icon the app's cheat sheet gives each one.
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
  this domain doesn't route `/api`.
- **The privacy policy and the delete-account page are here**, linked from the page's foot:
  `landing/privacy.html` and `landing/delete-account.html`. They are the addresses given to Play Console and App Store
  Connect (docs/store/PLAY_STORE.md), and Settings › Account › Privacy policy opens the first. Changing either is a
  landing deploy, not an OTA.
- **The device in hand goes first.** Android gets the APK filled and first, a Windows PC the installer (with a line on
  Run anyway while it is unsigned, DESIGN §209), a Mac gets the Mac app, with a line on
  opening an app that isn't notarised yet, and an iPhone or iPad gets the web app, since there's no iOS app.
- **The certificate** is Caddy's own, from Let's Encrypt, for `ghostmarkdown.com`. `www.ghostmarkdown.com` still
  points at the registrar's redirect service, not the box, so it has no block. Point it at the box and add it to the
  block's address line to serve it too.
- **The Caddyfile is shared.** `--caddy` writes only this domain's block, replacing it if it's there. It takes a
  backup, checks every site before and after, runs `caddy validate`, and restores the backup on any difference. The
  same care is described in `scripts/deploy-server.mjs`.

## Colour (2026-10-04)

Matt: "bring splashes of color into the marketing website like we do on the settings page with the color filled icon
squares and such". Every icon that leads a band's eyebrow, a card's heading or a point sits on a square filled with a
tint of its hue, the hue as its stroke, as a row's icon does in the app's Settings. The hues are Settings' own
(`site.css` `--hue-*`, a light and a dark pair each); a band has one, which its eyebrow wears (`home.css` `#plan`,
`#files`, ...), and the cards and points under it take six in turn by position, so a row is a set of different things.
The square is the svg's own box with padding, so no markup changed.
