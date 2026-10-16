# Ghost.md Clipper

A browser extension that saves what is on a web page into a person's Ghost.md, sealed with their account key in the
browser before it leaves. Manifest V3; Chrome, Edge and Brave from `dist/chrome`, Firefox from `dist/firefox`, one
source. Not published to any store.

## What it does

The toolbar button opens a popup (dark, Inter, the app's ink scale from `tauri/src/app/ink.css`). The person signs in
once with their handle and password, then on any page chooses:

| Mode | What the note holds |
| --- | --- |
| Article | The readable part of the page (Mozilla Readability), as Markdown (Turndown, GFM strikethrough, and the clipper's own rules for tables, fenced code with its language, and task lists) |
| Selection | What is selected, as Markdown; the popup opens on it when there is a selection |
| Full page | The whole visible body as Markdown |
| Bookmark | A link to the page, its description, and its preview picture (`og:image`) |
| Screenshot | The visible part of the tab, as a picture |

Each note is plain Markdown the app draws:

```markdown
---
source: https://example.com/the-article
clipped: 2026-10-16
tags: [reading, garden]
---
# The page's title

The person's comment, when they wrote one.

---

The page's words, its pictures as ![alt](image/clip-<id>.jpg)
```

The popup edits the title, adds tags (front matter `tags:`, which queries read), files the note in a personal
workspace (the synced settings' `workspaces`, as the connector files one) or adds it to a notebook (a `- [[Title]]`
line in the notebook's index, the title made unique first), and takes a comment. Also: the context menu's
"Save selection to Ghost.md", and two shortcuts, Alt+Shift+G (open the clipper) and Alt+Shift+S (save the selection,
or the article, straight away; the toolbar badge says how it went).

Pictures are fetched, drawn at most 1600 px on the long side as a JPEG over white (as the app keeps a pasted picture,
`tauri/src/app/core/imageShrink.ts`), sealed as `file:i-jpg-<stem>` and sent through the app's own file route
(`sendFile`, `PUT recordings/<id>`), then named in the note's payload so every device fetches them. A picture over 15
MB, one its site will not hand over, one the browser cannot open (an SVG), or one past the sixtieth stays a link to
where it is. The phone keeps only jpg/jpeg/png/webp whose bytes match their name, which is why every stored picture is
made a JPEG.

## How it is made

- `src/core/account.ts`: the account as a device of it, made of the web app's own modules (`tauri/src/app/core`):
  `derive` and `unwrap` (`sync/crypto.ts`) to sign in, `call` (`account/api.ts`, whose base is the build's
  `VITE_GLYPH_API`), `seal` for each note as `note:<id>`, `sendFile` (`sync/notes.ts`) for each picture. It mirrors the
  connector's `GlyphAccount` (`mcp/glyph.ts`).
- `src/core/keep.ts`: where the session is kept (below).
- `src/core/page.ts`, `markdown.ts`, `escape.ts`: the page read in the tab (`src/content.ts`, injected only when the
  person asks), and its HTML as Markdown. Only what Ghost.md would read as a mark is escaped: a `[[`, a `](`, a
  blank's `{?` (the app's own `BLANK`), maths by the app's own `MATHS`, emphasis and the line-start marks.
- `src/core/note.ts`, `pictures.ts`, `library.ts`, `save.ts`: the note, its pictures, the workspaces and notebooks
  (read from the synced settings and the feed as the connector reads them), and the saving.
- `src/background.ts`: the one place the account lives; the popup (`src/popup/`) only asks it
  (`src/core/messages.ts`). `src/popup/state.ts` is the popup as a pure state machine.
- `src/manifest.ts`: the manifest for both browsers; `build.mjs` builds with esbuild.

## Signing in, and "Stay signed in"

The password is turned into its login half and wrap key in the clipper's background the moment it is sent there
(`derive`, 600 000 rounds); only the login half goes to the service, as the app sends it. The wrap key opens the
account key, and the password is dropped.

- **Off (default):** the session token and the account key's bytes are in `chrome.storage.session`, in the browser's
  memory, and gone when the browser closes. No device key is registered, so a sign-in does not add a device to the
  account.
- **On:** the account key and a signing key of the clipper's own are kept as CryptoKey objects in the extension's
  IndexedDB, which no script can read the bytes of (as the web app keeps its keys); the session is sealed under a
  third such key in `chrome.storage.local`; the signing key is registered as "Web clipper" and renews a lapsed token
  without the password. This protects a copy of the storage file on its own; anyone who can use that browser profile
  can save to the account, which the popup says.

## Permissions

`activeTab`, `scripting`, `storage`, `contextMenus`, and one host: the service the build talks to. No content script
is declared for any page, and nothing is `<all_urls>`: a page is read only after the person presses the button, uses
the menu item or the shortcut (each gives `activeTab` for that tab), and `activeTab` also covers the screenshot
(`captureVisibleTab`). A picture on another site is fetched by the page itself where that site allows it (CORS);
otherwise the popup offers "Keep them", which asks the browser for those sites alone
(`optional_host_permissions`), and never at install. No analytics, no other network: the only requests are to the
service, and to the page's own pictures.

## Build, load, test

```sh
cd clipper
npm install
node build.mjs                       # dist/chrome and dist/firefox, for https://ghostmarkdown.com/api
node build.mjs chrome --api=http://127.0.0.1:5555/api --out=/tmp/ext   # a local service; only https or this computer is accepted
npx vitest run                       # conversion, note, pictures, sealing, session, popup states, manifest
npx tsc --noEmit -p .
node e2e/run.mjs                     # end to end (below)
```

**Load unpacked in Chrome, Edge or Brave:** open `chrome://extensions` (`edge://extensions`, `brave://extensions`),
turn on Developer mode, Load unpacked, choose `clipper/dist/chrome`. Pin it from the puzzle-piece menu.
**Firefox:** `about:debugging#/runtime/this-firefox`, Load Temporary Add-on, choose `clipper/dist/firefox/manifest.json`
(it stays until Firefox restarts; a lasting install needs Mozilla's signing).

**End to end** (`e2e/run.mjs`): a real glyph-api (`tool/local-server.sh build` makes it; `GLYPH_API_BIN` names
another) on 127.0.0.1 with a data folder for the run; the fixture pages at `localhost` and a second site at `[::1]`;
the extension built for that service; Playwright's own Chromium (from this Mac's npx cache, `PLAYWRIGHT` to name
another) with the extension loaded. `e2e/clip.e2e.test.ts` signs up a made-up account with the app's sign-up code,
presses the toolbar button through Chrome's DevTools command for it (`Extensions.triggerAction`, which gives the same
`activeTab` grant as a click), drives the real popup over its own DevTools connection, clips every mode, and reads
each note and picture back through the connector's `GlyphAccount` and the app's sync code. Pictures of the popup go
to `e2e/out/shots`, the notes and their pictures as a library folder to `e2e/out/notes`.

## The stores (not done)

- **Chrome Web Store:** a developer account (one-time fee) under Matt's Google account; the zip of `dist/chrome`; a
  128 px icon (`icons/128.png`), at least one 1280x800 or 640x400 screenshot and a 440x280 promo tile; a single
  purpose ("save web pages into your Ghost.md notes"); the privacy practices form: a justification for each permission
  (above), "website content" and "authentication information" handled, not sold, not used for anything but the
  feature, and the privacy policy's address (ghostmarkdown.com/privacy.html covers the account; it would need a
  paragraph on the clipper). Remote code: none.
- **Edge Add-ons:** the same zip, a Partner Center account (free).
- **Firefox (AMO):** the same source built for Firefox; `browser_specific_settings.gecko.id` is
  `clipper@ghostmarkdown.com`; the data collection declaration in the manifest names website content and
  authentication information; AMO reviews the unminified source as built.
- **Safari:** not built. It needs an Xcode project made by `xcrun safari-web-extension-converter dist/chrome`, a macOS
  (and iOS, for iPhone Safari) app that contains it, signed with the shared MattsSoftware team (F6ZAL7ANAD), and the App
  Store, since Safari loads extensions only from an app. Safari's MV3 support has gaps to check against this
  extension: `chrome.storage.session` (Safari 16.4+), `scripting.executeScript` with `files`, `captureVisibleTab`
  (supported), `optional_host_permissions` (Safari asks per site anyway), and `contextMenus` (as `menus`). The popup
  and the background would run unchanged; the work is the wrapper app, its signing and review, and testing each API.
