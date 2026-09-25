# Ghost.md

A mobile-first markdown notes app built on [Glacier UI](https://github.com/InfamousVague/GlacierUI):
live formatting that keeps the markdown tokens on screen, haptics as styles land,
and a hardware-button voice capture transcribed on the device.

The repository, its ids, storage keys and URLs are still named `glyph`; the name people see is Ghost.md.

## Develop

```sh
npm install
npm run dev            # web app on http://localhost:5250
npm run tauri:dev      # the Mac app, a 1280×820 desktop window
npm run ios:dev        # iOS simulator (needs Xcode + the Rust iOS targets)
npm run android:dev    # Android emulator (needs the SDK/NDK paths in package.json)
npm run desktop:build  # the Mac app as .app and .dmg
```

```sh
npm test               # every Vitest test: the page, the reader, the MCP server, the scripts
npm run typecheck      # tsc for the page and for mcp/
npm run lint           # eslint over the whole tree, no warnings allowed
npm run check          # lint, typecheck and test, in that order
npm run coverage       # the Vitest run with coverage, written to coverage/
```

`npm run lint` lints everything under the repository root, and that includes any worktree under .claude/worktrees,
which it does not ignore. While other worktrees exist, lint the files you changed by path instead:
`npx eslint <paths>`. The Rust suites run with `cargo test` in `src-tauri/` and `server/`, and
`node scripts/test-report.mjs` runs all three and writes the report the app shows in Settings › Test results.

The kit is vendored under `vendor/@glacier/*`, so the app installs and runs with nothing published to npm. The docs
are indexed in `docs/README.md`; the dated design log is `docs/DESIGN.md`.

## Over the air

The phone does not need a cable. `deploy:ota` publishes to
[attack.fm/glyph](https://attack.fm/glyph/), the Caddy document root the marketing site and
DeadCatBounce share on that box.

```sh
npm run deploy:ota                      # tests, web build, and the over-the-air update for installed apps
npm run deploy:ota -- --apk             # also build and publish the release APK (bump the version first)
npm run deploy:ota -- --desktop         # also build and publish the Mac app (on a Mac, with the Developer ID)
npm run deploy:ota -- --mcp             # also build and publish Claude's MCP server file (docs/MCP.md)
npm run deploy:ota -- --notes "Faster voice notes."   # the text of the update alert
```

The other flags, all listed in the header of `scripts/deploy-ota.mjs`:

| Flag | What it does |
| --- | --- |
| `--same-version` | Republishes an APK whose version is not newer than the live one. |
| `--skip-tests` | Ships without running the tests first. The build's Test results page then says its report is from other code. Not recommended. |
| `--release <n>` | Numbers the release by hand. Needed after a rollback, when the live manifest is older than the highest ever published. |
| `--keep-connection` | Leaves the box's login open for two minutes, so `npm run deploy:server` straight after spends no second login. |
| `--public` | Blanks `VITE_GLYPH_API_TOKEN` for the build. Nothing in the page reads the token any more, so this changes nothing. |

Every deploy first runs `scripts/test-report.mjs` and refuses to ship a failure. It backs up the live tree on the
box, and prints the `rsync` line that puts the backup back, with the `--release` number the next deploy after such a
rollback needs.

Each release is numbered from what is live: 1.8.0-12 is the twelfth update published on 1.8.0. **A version bump
goes in two files**: `package.json` (the version the page calls itself, and the base of the OTA numbering) and
`src-tauri/tauri.conf.json` (the APK's versionName, which `--apk` compares with the live one). The version in
`src-tauri/Cargo.toml` is not read by anything.

On the phone, open [attack.fm/glyph/install.html](https://attack.fm/glyph/install.html) once
and install the APK. After that the app keeps itself current:

- **Web-layer changes** (almost all of them) ship with a plain `deploy:ota`. The installed app, on Android or a
  Mac, looks for `ota.json` a few seconds after launch, whenever it comes back to the screen a minute or more after
  it last looked, and every two minutes while it stays in front. It downloads only the files that changed, verifies
  each SHA-256, and runs the new build on its next start (the list also offers "Reload"). A build that fails to
  start is quarantined and the app falls back to the frontend inside the APK in the same launch. The iOS app takes
  no updates over the air; the App Store is its only way to update.
- **Native changes** (Rust, Kotlin, the manifest) need `--apk` and a version bump. Installed apps see the newer
  `apk.json`, download it, and hand it to Android's installer; the first time, Android asks to allow installs from
  Ghost.md. A Play build (`GLYPH_STORE=play`) never installs an APK itself.
- **A page change that calls a new Rust command** needs three things. Bump `NATIVE_GENERATION` in
  `src-tauri/src/ota.rs` and add a line saying what the generation brought. Gate the feature on the page with its
  own threshold beside the command it calls, such as `FILES_GENERATION = 18` in `src/app/core/libraryFiles.ts`,
  asked through `hasNativeGeneration` (`src/app/core/nativeGeneration.ts`), so an older binary hides the feature
  rather than calling a command it lacks. And ship with `--apk`. Raise `BUNDLE_REQUIRES` as well only when the
  page cannot run at all on an older binary: older apps then keep their current frontend and offer the APK
  instead. Generation 19 did that (revision-checked note writes, DESIGN §114), so both constants are 19 today.
  Never stamp `NATIVE_GENERATION` into `ota.json`; `vite.config.ts` reads `BUNDLE_REQUIRES` for that.

Every `ota.json` and `apk.json` is **Ed25519-signed**, and the app accepts only what a key in
`src-tauri/ota-trusted-keys.txt` signed. Trust is a key, not a domain: any host can serve
updates, a redirect cannot inject one, and a domain that lapses and changes hands cannot ship code
into installed apps. The private key is `~/.config/glyph/ota-signing-key.pem` - **back it up**.
Without it no installed app accepts another update, and the only way forward is a new APK
installed by hand.

How it works, and the failure modes it is built around, is the header of `src-tauri/src/ota.rs` (whose parts are in
`src-tauri/src/ota/`) and DESIGN section 14. To test against a local server instead of attack.fm, build with
`GLYPH_OTA_BASE=http://10.0.2.2:8787` (the emulator's view of the host) and serve a build's dist folder there.

## The other deploys

| Command | What it ships |
| --- | --- |
| `npm run deploy:server` | glyph-api, the Rust service under `server/` behind `/glyph/api/`: accounts, sync, shares, the live relay, Notion's sign-in and the door to Claude's hosted MCP server. The old formatting route, `POST /glyph/api/format`, still runs behind its token: nothing in the app calls it, but the deploy fails when `health` reports Ollama unreachable and checks that the route refuses a request without the token (`server/src/format.rs`). `--mcp-only` ships only the hosted MCP server. |
| `node scripts/deploy-landing.mjs` | ghostmarkdown.com, the download page and its privacy and delete-account pages (docs/LANDING.md). It has no npm alias. `--caddy` also writes the site's block into the box's shared Caddyfile. |

The box counts logins, not deploys, and locks an account out after a handful in a short window: the lockout answers
as a wrong password. Every script spends one login; `--keep-connection` lets an OTA and a server deploy share one.

## Update alerts

Off by default, and Android only. Settings › About › Update alerts turns on a notification when a new Ghost.md is
published, even with the app closed: a WorkManager job looks every ~6 hours, and once right away when switched on,
calling into Rust over JNI (`src-tauri/src/update_alerts.rs` → `ota::peek`) so it trusts only signed manifests and
follows a domain move. One release alerts once. Pass the alert text with
`npm run deploy:ota -- --notes "What changed."`. On a Samsung with "Sleeping apps" battery limits, set Ghost.md's
battery use to Unrestricted or the job may never run. The job is
`src-tauri/gen/android/app/src/main/java/com/mattssoftware/glyph/updates/UpdateCheckWorker.kt`.

## Signing keys

Three keys decide whether an installed Ghost.md accepts anything from you. The first two live outside the repo in
`~/.config/glyph/`, and **both must be backed up off this Mac** (a password manager takes them as file attachments):

| File | What it signs | If it is lost |
| --- | --- | --- |
| `glyph-android.keystore` (+ `android-signing.properties`) | The APK. Android installs an update only over an app signed by the same certificate, pinned in `src-tauri/apk-signer.sha256`. | No existing install can ever be updated; everyone reinstalls, losing notes on the phone. |
| `ota-signing-key.pem` | `ota.json` / `apk.json` over the air. Public half in `src-tauri/ota-trusted-keys.txt`. | Installed apps stop taking updates until a new APK is installed by hand. |
| The Developer ID certificate, in this Mac's keychain | The Mac app. `deploy:ota --desktop` refuses a build signed by any team but the one pinned in the script. | A new certificate signs the next Mac build; the app is not yet notarised or self-updating, so nothing installed is bound to it. |

The APK key is the original Android debug keystore from this Mac, kept because every install
already carries it. It is copied out of `~/.android/` because Android Studio silently makes a new
one whenever that file is missing, and `deploy:ota --apk` refuses to publish an APK signed by
anything but the pinned certificate, or one that is debuggable. `GLYPH_ANDROID_SIGNING` points the build at
another signing file.

Google Play refuses an upload signed with a debug certificate, so a Play upload key is planned
(docs/store/PLAY_STORE.md). It does not exist yet.

## Moving to another domain

Installed apps look for updates in the order of the newest **signed** `sources` list they have
seen, then the list their APK was built with (`src-tauri/ota-sources.txt`). So moving the updates is a
publish, not a new APK:

1. Serve the same glyph tree from the new host (the files are identical; only where they live
   changes).
2. Put the new base URL **first** in `src-tauri/ota-sources.txt`, keeping attack.fm after it. If
   the model files move too, write an `ota-services.json` beside it in src-tauri (there is none today):
   `{ "modelMirrors": ["https://…/models"] }`. Its `format` field is still accepted, but nothing reads it.
3. `npm run deploy:ota`. Every 0.3.0+ app that checks in remembers the new list and uses it from
   then on. Ship an `--apk` release as well so fresh installs compile the new list in.
4. Keep attack.fm/glyph serving - or `301` it to the new host - for as long as you can. An app that
   never checks in before the old domain goes dark only knows what its APK compiled in, and 0.2.0
   (which predates signing) only follows redirects.
5. Point `REMOTE` and `URL_` in `scripts/deploy-ota.mjs` at the new box.

An older signed manifest can never roll the list back, and every URL in it must be https.

The signed list moves only the updates and the model files. Every other address is compiled into the page, the
server or a script, and moves with a rebuild:

| Service | Where its address is |
| --- | --- |
| Accounts, sync, shares and the live relay | `VITE_GLYPH_API` at build time, else `https://attack.fm/glyph/api` (`src/app/core/account/api.ts`; the relay's WebSocket address is made from it in `src/app/core/live/transport.ts`). An app reaches a new address only through an update carrying a page built with it. |
| Notion's sign-in | Written into `src/app/plugins/notion/client.ts`. |
| The reader for shared links | `VITE_GLYPH_READER`, else `https://ghostmarkdown.com/read.html` (`src/app/share/share.ts`). |
| Claude's MCP server | `DEFAULT_API` in `mcp/glyph.ts`, and `GLYPH_MCP_ISSUER` / `GLYPH_API_PUBLIC` in `mcp/hosted-main.ts`. |
| The pages allowed to call glyph-api | `ORIGINS` in `server/src/main.rs`. |
| The deploys | `REMOTE` and `URL_` in `scripts/deploy-ota.mjs`, `API` in `scripts/deploy-server.mjs`, `SITE`, `RELEASE` and `DOMAIN` in `scripts/deploy-landing.mjs`. |

**Rotating the signing key:** `node scripts/ota-keygen.mjs --new-key-path <path>` adds the new
public key to the trusted list; ship an `--apk` release so installs trust both; then deploy with
`GLYPH_OTA_KEY=<path>`. Drop the old key from the list in a later APK.

A browser tab at attack.fm/glyph is the same app without a Rust core: **no haptics**, no on-device transcription or
model, and notes live in that browser's `localStorage` rather than in the app's library of Markdown files
(docs/LIBRARY.md).

Credentials come from a gitignored `.env` (`AFM_DEPLOY_HOST` / `AFM_DEPLOY_USER` /
`AFM_DEPLOY_PASS`), read by `scripts/lib/box.mjs` for every deploy. Note the box moved: the current host is the one
AttackFM's `.env` calls `AFM_NEW_DEPLOY_HOST`.
