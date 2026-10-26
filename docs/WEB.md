# Ghost.md on the web

Matt, 2026-10-26: "update the web version of the app it's very behind". The web version is this Flutter app compiled
to WebAssembly and served at https://attack.fm/glyph/, where the Tauri app's React page stood still from the
cut-over until it was retired that day (it read organization sub-folder notes as personal and deleted 108 team
notes). It signs in to the same account (ghostmarkdown.com/api), syncs, and edits the same notes.

## How it is built

| what | where | how |
| --- | --- | --- |
| the app | `lib/` | `flutter build web --wasm`: dart2wasm and skwasm; a JavaScript copy beside it for browsers without WasmGC, which only says the browser is too old (`lib/web/too_old.dart`) |
| the browser's core | `native/web/` | native/'s own `crypto.rs`, `crdt.rs`, `crdt_wire.rs` and the library's `names.rs`, included by `#[path]`, built for `wasm32-wasip1`, run in a Web Worker (`web/core/`) |
| the library | `lib/web/web_store.dart` | the Rust library's rules (drafts, revisions, pins that keep the time, notes synced in with their own times and folders, command undo, pictures, versions) over IndexedDB, answering the same commands |
| the page | `web/` | `index.html`, `flutter_bootstrap.js` (no service worker), the manifest and Ghost.md's icons |

```sh
GHOST_WEB_VERSION=2.3.36 tool/build-web.sh                          # the release: the core, then the app, into build/web
GHOST_WEB_API=http://127.0.0.1:9999/api tool/build-web.sh           # one that signs in nowhere, for checking
tool/build-web-core.sh check                                        # the core alone, and node tool/web_core_vectors.mjs
node tool/serve_web.mjs 8790 /glyph/ build/web                      # served as the box serves it
node tool/web_shots.mjs --gpu                                       # walked in Chromium, pictured into build/feature-shots/web
node scripts/deploy-flutter-web.mjs --dry-run                       # what a publish would change; logs in nowhere
```

The core needs `rustup target add wasm32-wasip1` once. It has no dependency the phone's core does not have but
`wasi` (getrandom's WASI backend).

## Why WebAssembly, and why this split

**Why dart2wasm and not JavaScript.** The app keeps things against 64-bit FNV-1a hashes (`format/body_hash.dart`, a
reminder's id, a diagram's file). A Dart `int` compiled to JavaScript is a double and its bit operations are 32 bits,
so every one of those would be another number than the phone's. In WebAssembly an `int` is 64 bits, as on the
phone. The one 64-bit literal is written in halves (`fnvOffsetBasis`) so the JavaScript copy still compiles; that
copy opens nothing but the "too old" page. Browsers: Chrome and Edge 119, Firefox 120, Safari 18.2 and later.
Flutter's loader offers WebAssembly to Chromium alone unless told otherwise, and Safari and Firefox would have had the
"too old" page: `web/flutter_bootstrap.js` allows all three engines (`wasmAllowList`).

**Why Rust compiled to WebAssembly for the crypto and the documents.** These must be the same bytes on every device:
a password's derived halves under the `glyph/v1/` salt, the sealed wire, an organization's key out of its wrap, a
device's signature, a Yjs update. Compiling the very files the phone and the Mac run keeps them identical by
construction, and `tool/web_core_vectors.mjs` holds the browser's build to `native/tests/fixtures/crypto_web.json`
(what the old web app sealed with WebCrypto, at the real 600,000 rounds) through the very script the page runs. A
600,000-round derivation takes about 0.4 s in the worker; the page keeps drawing meanwhile.

**Why the library is not the Rust's.** The phone's library is a folder of Markdown files with a SQLite index, written
with `std::fs` throughout. A page has neither a folder nor a file for SQLite, and the Rust that would need both is
most of the library. So the page keeps each note whole (words, times, pin, archive, folder, revision, recording's
phrases, formatted version) in IndexedDB and answers `list_notes`, `get_note`, `create_note`, `update_note`,
`store_apply`, `delete_note`, the pins, versions, command mutations and the file commands with the library's rules,
port by port (`test/web/web_store_test.dart`). The one decision it asks of Rust is where a note's file would be
(`note_path`, over `names.rs`), so a note made in the page syncs to the path the Mac would have written.

**Why wasm32-wasip1 and not wasm32-unknown-unknown.** yrs depends on fastrand with its `js` feature, which on
`unknown` needs wasm-bindgen's generated glue, and the wasm-bindgen CLI installed here is not the crate's version.
WASI needs none of that: the worker provides random bytes, the clocks, stderr and nothing else
(`web/core/ghost_core_wasi.js`, forty lines). A wasm32 panic aborts; the worker answers it as an `err` and opens a fresh
core.

## What a browser does, and what it does not

Seen working in Chromium and in WebKit, Safari's engine (2026-10-26, `tool/web_shots.mjs`, signed in nowhere; Firefox
not yet tried): the sign-in page, "Use without an
account", the walkthrough, home, a note opened and typed in and still there after a reload, the Market, Settings and
About, at a desktop's width and a phone's. Built to work as in the apps, and not yet tried against the real service
(no check here signs in): signing in and up to the same account, sync of notes, pictures and versions, organizations
and team notes (the CRDT is the phone's; `test/web/web_team_sync_test.dart` runs the web library through the team's
pass), live typing over the relay's WebSocket, shares and sites, and each plugin as far as its service lets this site
in. The old web app's notes in this site's `localStorage`
(`glyph-notes`) are carried into the library the first time, once (`carryOldPage`); its keys were WebCrypto's and
cannot be, so a person signs in again.

Not in a browser, and left out rather than offered and failing (`recordsVoice`, `onWeb`, `!kIsWeb &&` at each
phone call's source): recording and every way into it, the AI models, the side key, home-screen widgets, reminders
and places (they are notifications), the phone's notices, spell check, a library folder, backup, export and import,
and app updates (About says "You're on the web version. Reload the page to update."). A browser on an Android phone
or a Mac is no Android app and no Mac app: `defaultTargetPlatform` still shapes the look (phone or desktop), never a
call to the device.

Kept in the page's own storage: the notes and pictures in IndexedDB (`ghost-md`, `lib/web/idb_shelf.dart`, asked to
persist); preferences in `localStorage` (`flutter.` keys, shared_preferences); the session and the account's keys as
the core writes them down, in `localStorage` (`ghost-secure:`, `lib/web/page_secure.dart`), which is as close to a
keychain as a page can write. A browser that will not open IndexedDB (a private window) opens on memory and About says
nothing is kept.

## Things a browser decided

- **The space bar and the arrows.** Flutter's shortcuts for a page give the space bar to a page-down scroll and the
  arrows to scrolling; an EditableText takes them back while focused, and the note's editor is none, so a space typed
  in a note scrolled it and never arrived. The app gives the page the desktops' shortcuts (`pageShortcuts`).
- **The edge blur** is the strips (`lib/art/edge_strips.dart`) in every browser: a page cannot filter by a shader, so
  Android's backdrop would have faded. A note scrolls at 60 frames a second at a desktop's width and a phone's
  (`tool/web_shots.mjs --gpu`).
- **Threads.** skwasm draws on one thread unless the page is cross-origin isolated (COOP and COEP headers); the box
  does not send them, so it draws on one, and says nothing of it (`suppressMultithreadingWarning`).
- **CORS.** The account's service lets in https://attack.fm, https://ghostmarkdown.com and any local port
  (`server/src/main.rs ORIGINS`). A third party's service that does not let this site in is no answer, said as
  "unreachable".

## Publishing

`scripts/deploy-flutter-web.mjs` publishes `build/web` into `/opt/attackfm-site/glyph`, the release directory, with one
login: added and replaced, nothing deleted (the APK, the Mac and Windows downloads, every manifest, `models/`, `mcp/`,
`read.html` and the reader page's `assets/` stay as they are), `index.html` last, a backup named for the login first,
and every protected file checked from outside after. It refuses a build made from other code than the tree's,
against another service, without a version, or with a core older than its Rust.

**Returning visitors.** None of Flutter's file names change from build to build, so the page wants every file under
/glyph/ served `no-cache`; `--caddy` adds that rule to attack.fm's block in the shared Caddyfile, by
deploy-landing's procedure (backup, validate, every site before and after, restore on any difference). The new page
registers no service worker and lets go of any under /glyph/; the old page had none. The old page's entry script
(`assets/index-*.js`) is replaced by a stub that loads the address again, so a browser holding the old index.html
gets the new page.
