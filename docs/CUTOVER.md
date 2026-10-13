# Replacing Ghost.md's Tauri app with this one

Matt, 2026-10-11: the Flutter app ships as the next update OVER the Tauri app, for everyone, when it is ready.
Updates use the Tauri app's own update signing key and release address. Release builds always talk to the real
service. The phone assistant, the side key and "Record note" are off behind a developer flag. The port's extra
sentence on a refused save stays. And in GitHub, `main` of the `glyph` repository becomes this app, with the Tauri
code kept on a branch.

This file is what that takes on Android: what is built (branch `cutover`), what was proven and how, what was not,
and what whoever publishes has to do, in order. **Nothing in sections 1 to 4 and 6 has been published, deployed or put on a
phone.** The Tauri app's tree was read and never changed for them. Section 5, the repository's move, is done.
Section 7 is the same for the Mac, where almost nothing is where it is on a phone, and section 8 for the iPhone,
which is the Mac's carry inside an app's container and the App Store's rules around it.

Paths under `src/`, `src-tauri/`, `scripts/` are the Tauri app's, which is `tauri/` of this repository since the
move (`../glyph` while this was written); everything else is the root's.

## 1. What the Tauri app keeps on a phone, and what becomes of each

An update installs over the Tauri app under the same id, so this app wakes in the Tauri app's data folder,
`/data/user/0/com.mattssoftware.glyph`. This app was built on the same folder layout (lib/core/native/device_paths.dart)
and on the Tauri app's own Rust library (native/src/lib.rs includes `src-tauri/src/library` by path), so most of it
is simply read where it lies.

| What | Where the Tauri app keeps it | In this app |
| --- | --- | --- |
| The notes, their versions files, the index | `Library/` and `Library/.glyph/` (src-tauri/src/paths.rs:51; library/versions.rs, index.rs) | Read in place: the same Rust. |
| A library folder the person chose, and its grant | `library-root.json` (library/root.rs:35), `trees/<key>/`, `index/<key>.sqlite`; the grant is Android's, taken in files/LibraryTree.kt:120 | Read in place (the same Rust, and `com.mattssoftware.glyph.files.LibraryTree` under the same class name). Android keeps a persisted grant for the id across an update. |
| Recordings, pictures, films, models, a write-up's files | `recordings/`, `images/`, `video/`, `models/`, `jobs/` (paths.rs:56-75) | Read in place. |
| The notes before 1.3.0 | `glyph.sqlite` (src-tauri/src/store.rs) | Moved in by the same `library/move_in.rs`, on the first open. |
| Preferences (with the workspaces, the trash, the open tabs and tab groups, the shares), drafts, kept places, tape ids, sync cursors (`glyph-sync-<account>-…`), plugin settings, once-flags: every `glyph-…` key | the web view's `localStorage`, origin `http://tauri.localhost` (src/app/core/stored.ts; `app_webview/Default/Local Storage/leveldb`) | **Carried** into SharedPreferences under the same key with the same text (lib/core/stored_device.dart reads them as the page did). |
| The session | `localStorage`, `glyph-account-session` (core/account/keystore.ts:29) | **Carried** into the secure store under the same name. |
| The account key (AES-256-GCM), the device's signing key (Ed25519), the account's key pair (P-256) | IndexedDB `glyph-account`, store `keys`, as `CryptoKey`s made **not extractable** (keystore.ts:30-31, 78-85; core/sync/crypto.ts:113-118, 191-193; core/orgs/wrap.ts:37-45) | **Carried** into the secure store as `account`, `device`, `encryption`, each its 32 bytes, read from IndexedDB's files and proven first (below). |
| A team note's document and what was typed and not yet sent | IndexedDB `glyph-team`, store `docs` (core/team/docs.ts:26-27) | **Carried** to `team/<account id>/<note id>.json` (lib/team/docs.dart). |
| GitHub's token | `localStorage`, `glyph-github-token` (plugins/github/repos.ts:33) | **Carried** into the secure store, same name. |
| Slack's webhooks, Notion's sign-in | `slack.json`, `notion.json` (src-tauri/src/slack.rs:59, notion.rs:82) | **Carried** into the secure store: `glyph-slack-webhook:<id>`, `glyph-notion-account`. |
| A meeting in hand, what was asked about notifications, the bell's cursor, a refused location, the backup drive | Kotlin's own files: `glyph_meeting`, `glyph_recordings`, `glyph_notices`, `glyph_location`, `glyph-backup-drives` | Read in place: the ported Kotlin uses the same names. |
| Queued write-ups and the bell's worker | WorkManager, `glyph-write-ups`, `glyph-write-ups-charging`, `glyph-notices` | Carry on: the workers have the same class names (`com.mattssoftware.glyph.recordings.RecordingWorker`, `…notices.NoticeWorker`). |
| The update check's worker | WorkManager, `glyph-update-alerts`, `glyph-update-alerts-now` (updates/UpdateAlerts.kt:33-34) | **Let go of** by name after the carry: this app has no such worker (section 3). |
| Notification channels | `glyph_recordings`, `glyph_notices`, `glyph_updates` | The first two are the same ids, so a person's settings for them stand. `glyph_updates` stays in the phone's list with nothing posting to it. |
| Downloaded pages | `ota/` (src-tauri/src/ota.rs) | Left where it is. Nothing reads it; it is a few megabytes. |

Not carried, on purpose or by necessity:

- `glyph-shares` and `glyph-workspaces`, the two keys the page itself folded into the preferences long ago
  (share/share.ts:241, core/workspaces.ts:86). They are copied like every other key but nothing here reads them, so
  a phone that went from a version before those migrations straight to this app would lose its share list and its
  workspaces. Every version since reads and removes them on its first launch.
- The spoken assistant role. A phone where Ghost.md was the digital assistant loses that with the update, since the
  service is disabled by default now (section 4).
- Anything on Windows. Sections 1 to 4 are Android's; the Mac's carry is section 7 and the iPhone's section 8.

### How it is carried (lib/carry/)

On the first launch in a folder a Tauri app's web view left (`app_webview/Default/Local Storage/leveldb` is there
and `carry/tauri-carry.json` is not), in two halves:

1. **`settings`, before a preference is read** (lib/main.dart `_remembered`). The keys' bytes are read from
   IndexedDB's files first (lib/carry/leveldb.dart, web_stores.dart: a read-only LevelDB reader with Snappy, and
   Chromium's serialised `CryptoKey`), because once a web view has the database open its files may move. Then a web
   view that is never shown loads one page at `http://tauri.localhost`, answered by the app itself with no network
   (android/…/TauriCarry.kt), and hands back all of `localStorage`, the team documents, the public half of each
   pair, and a few bytes sealed under the page's own account key. Every `glyph-` key but the two secrets is written
   to SharedPreferences, read back from the phone, and only then marked.
2. **`secrets`, once the core is loaded and before the account is made** (`_opened`). Each key is proven before it
   is believed: a pair's private key raised in the core must answer the public key stored beside it and the one
   the page exported; the account key must open what the page sealed. Then session, keys, GitHub, Slack and Notion
   go into the secure store (Android Keystore, android/…/SecureStore.kt), each read back.

It never deletes and never overwrites: the web view's storage, `slack.json` and `notion.json` stay, and a name this
app already holds is left alone, so a half cut short runs again from the top on the next launch and comes to the
same place. `carry/tauri-carry.json` is the marker, `carry/tauri-carry.log` a line for each step (names and
counts, never a token, a key or a note's words). With no web view to ask, `localStorage` is read from its files as
well. A key that will not prove itself is not carried: the person is then signed in and asked for their password
once, as on any device that lost its key; nothing is lost, since the service holds the account key wrapped.

**Why the keys are read from files.** No page, and so no web view, can export a `CryptoKey` made not extractable.
Chromium writes its bytes to disk in the clear all the same. If a future WebView stops doing that, or moves
IndexedDB to another format, the files give nothing, the proof has nothing to prove, and that phone asks for the
password once.

### Proven

- **Tests** (`flutter test test/carry`, 13): the reader against the Tauri app's real storage from an emulator
  (`test/carry/fixtures/phone_*`, with what the page itself answered for `localStorage` beside it: 19 of 19 keys
  identical), against a desktop Chrome 154's for Ed25519 and for records compacted into a Snappy-packed table;
  the newest write wins over a deleted earlier account's keys; the whole carry with the real core's crypto, ending
  in `DeviceKeyStore` reading a signed-in device; once only; cut short and run again; nothing overwritten; no web
  view; a key that does not prove itself; a phone the Tauri app was never on.
- **On emulator-5584** (API 36, WebView 133), three times, the last with the release build. The Tauri app 1.15.0
  that was installed there (its APK is byte for byte `src-tauri/gen/android/app/build/outputs/apk/universal/release/app-universal-release.apk`,
  signed with the release certificate) was used offline: a pinned note written, a meeting recorded (a 0:16 tape),
  the Dawn theme chosen, a workspace made and filtered by, five tabs open. A made-up signed-in state was put into
  its page through the web view's debugging socket the way keystore.ts keeps one (an earlier account's keys written
  and deleted first), which the Tauri app itself then showed as "cutover · not synced". Then `adb install -r` of
  this app built with `GHOST_CUTOVER=1` at 2.0.0: **Android took it as an update** (`firstInstallTime` kept, the
  same uid, the data in place), and the first launch showed the same theme, tabs, filter, pinned note with its
  words, the meeting with its tape and Play. The log: 18 keys and one team document carried, "the account key
  opened what the page sealed", "the encryption key answers its public key, the page's too", six secrets carried.
  The phone's store against what the page had answered: every key identical. A second launch carried nothing.
- **A chosen library folder.** In the Tauri app the library was moved to a folder picked through Android's picker
  (`Documents/CutoverNotes`), then this app was installed over it: the grant was still persisted for the uid, the
  notes were listed from the folder, and a sentence typed in this app was in the file in that folder.
- **The release build** (`tool/cutover-build.sh 2.0.0`: 58 MB, not debuggable, no cleartext traffic, signed by the
  pinned certificate) installed over the Tauri app the same way: the carry ran through the web view as before, and
  Settings › Account read "cutover", "End-to-end encrypted", "The sync service could not be reached" (the emulator
  was offline throughout, so nothing was sent anywhere).

### Not proven, and what would prove it

- **A real account against the real service after the update.** The keys are proven to be the page's keys; that the
  service then accepts the session and the engine syncs was not run (no account was made, and no build here may
  talk to the service). Proof: the owner's own phone, or a spare, signed in on the Tauri app, updated, with a note
  edited on each side.
- **An Ed25519 device key from a phone.** The emulators' WebView (133) has no Ed25519, so the page kept no device
  key there; the format is proven from desktop Chrome 154 only. A phone with WebView 137 or later proves it: the log
  must say "the device key answers its public key, the page's too". If it does not, the app makes a new device key,
  as it does on any new device.
- **Samsung's WebView and a long-used phone.** Proof is the same first launch on the Fold: read
  `carry/tauri-carry.log` (a debug build: `adb shell run-as com.mattssoftware.glyph cat carry/tauri-carry.log`).
- **A phone on a Tauri version before the page's own migrations** (see "Not carried").

## 2. The id, the version and the signing

`GHOST_CUTOVER=1` (Gradle) with `--dart-define=GHOST_CUTOVER=true` (Dart) make the build that replaces the Tauri
app; `tool/cutover-build.sh <version>` gives both. Not the default: every other build is still
`com.mattssoftware.glyph.flutter`, "Ghost Flutter", beside the real app.

- **Id** `com.mattssoftware.glyph`, **name** "Ghost.md".
- **Version code** from the version name the way Tauri made it (major × 1,000,000 + minor × 1,000 + patch); the
  build is refused unless it is above the Tauri app's last, **1.15.0 = 1015000**
  (src-tauri/gen/android/app/tauri.properties, build.gradle.kts:77). 2.0.0 is 2000000.
- **The launcher's activity keeps the Tauri app's name**, `com.mattssoftware.glyph.MainActivity` (their manifest,
  line 103), as an alias of this app's own. A home screen holds an icon and a pinned shortcut by that name and
  drops them when it goes.
- **What the system and other apps hold the app by**, the same in every build of this app: the `ghostmd` scheme
  (their line 137; ChromeOS's action added), the capture action `com.mattssoftware.glyph.CAPTURE` and the shortcut
  id `capture` (behind the assistant's switch), the documents provider's authority `<id>.library` (their line 234),
  the services' and workers' class names, the channel ids, the same permissions and no more, minSdk 24, targetSdk 36.
  The Tauri app's `<id>.fileprovider` (their line 223) is not kept: nothing outside the app holds an address in it.
- **Backup rules.** Theirs leave `video/` out of the cloud (res/xml/glyph_backup_rules.xml); this app's also leave
  out the index, which is a cache. Nothing a backup had is lost by that.
- **Signing.** Android installs an update only over the same certificate, pinned in src-tauri/apk-signer.sha256:6
  (`3ca686b5…63aa`). The release build is signed from the file the Tauri build reads
  (src-tauri/gen/android/app/build.gradle.kts:26, 81): `~/.config/glyph/android-signing.properties`, or the file
  `$GLYPH_ANDROID_SIGNING` names, with the properties `storeFile`, `storePassword`, `keyAlias`, `keyPassword`; the
  keystore itself is `~/.config/glyph/glyph-android.keystore`. Without the file a release is signed with the
  machine's debug key. **On this Mac those are the same certificate** (the Tauri build's own comment calls its key
  "the copied debug keystore"; `~/.android/debug.keystore` has the pinned fingerprint), which is why a debug build
  installed over the release app on the emulator. On any other machine a build without the file cannot update
  anybody. `tool/release_apk.mjs` checks the certificate against the pin and refuses anything else.

## 3. Updates

**What an update can be here.** The Tauri app had two: a new page swapped in under the same binary (`ota.json`,
src-tauri/src/ota.rs), which is how almost every change reached people, and a new APK when the binary changed
(`apk.json`, src-tauri/src/ota/apk.rs). A Flutter app is compiled code, and Android does not let an app replace its
own code: **every update of this app is a new APK that the person confirms on Android's install screen**, having
once allowed Ghost.md to install apps. The only other road is a store. So "updates" from here on means: the app
looks, says a version is out, downloads and checks it, and hands it to Android. That is built
(lib/core/updates.dart, native/src/kept/updates.rs, android/…/UpdateInstaller.kt) and was walked on an emulator
against a made-up release before today; what changed today is who it believes and where it looks:

- it trusts Ghost.md's own key, the one line of src-tauri/ota-trusted-keys.txt:11 (lib/core/update_keys.dart);
- the build that replaces the Tauri app looks at the Tauri app's address, the one line of
  src-tauri/ota-sources.txt:18, `https://attack.fm/glyph` (the directory scripts/deploy-ota.mjs:110 publishes to);
  every other build is still refused that address;
- it reads its own signature file, `apk.json.flutter.sig`, beside the Tauri app's `apk.json.sig` over the same
  `apk.json`. The same key signs both; the two apps sign different contexts (`ghost-flutter-apk\0`, `glyph-apk\0`),
  and this app's context is compiled into the core, which may not be rebuilt here. Folding the two into one
  signature is a one-line change in native/src/kept/updates.rs for whoever next builds the core.

A debug build never looks, as before.

### The thirteen rows of docs/PARITY.md

| Row (section) | Becomes |
| --- | --- |
| The launch screen's update line (1) | On in the replacing release: "Checking for updates", "2.0.1 is out". Drawn from `Updates`, built. |
| Home's notice: an update ready (3) | On: Install, progress, "didn't install". There is no Reload, since there is no page. |
| The update's card on a wide window (5) | On, the same notice in the sidebar. |
| About: the line under the version (33) | On: the build's date (`GHOST_BUILD`) and where updates come from. |
| About › Updates: where it stands, Install, Check for updates (33) | On. Reload never applies. |
| A new app found, downloaded, checked, handed to the installer (36) | On. |
| Looked for after launch, on a return, every two minutes in front (36) | On. |
| Update alerts with the app closed (36) | **Not built.** It needs `UpdateCheckWorker`/`UpdateAlerts` ported under their class names (a worker that asks the core to read `apk.json` and posts to `glyph_updates`), about 250 lines of Kotlin and a JNI door. Until then nothing looks while the app is closed, and the Tauri app's queued check is cancelled by the carry. |
| About › Alerts: Update alerts (33) | **Not built**: the row is drawn only when given the switch above. |
| What's new, once, after an update (36) | **Not built.** The page read `changelog.json` beside `ota.json` (scripts/deploy-ota.mjs:465), which this app's updater does not fetch. It needs that file fetched, the last seen build kept (`glyph-seen-build`, which is carried), and the sheet. |
| About › What's new (33), the list of releases (36) | **Not built**: About's section is ported and is handed no releases, for the same reason. |
| A model mirror moved by a signed update (27) | **Not applicable as it was**: `sources` and `services` rode on `ota.json`. The mirrors are a build's own. |

So seven are on by configuration, in the replacing release only, and six are still to do; none is faked.

### How the Tauri app's installs are offered this app

The page update cannot do it: `ota.json` swaps web files under the same binary. The APK road can. An installed
Tauri app offers "Install" when the signed `apk.json` at its address has a version newer than its own or a `native`
above its own 27 (src/app/core/ota.ts:236-239; apk.rs:28-33), downloads `glyph.apk` beside it, checks the SHA-256,
and hands it to Android (MainActivity.kt:985). So publishing this app as `glyph.apk` with an `apk.json` saying
2.0.0, signed with the same key, IS the update: each install offers it the next time it looks (four seconds after
launch; with alerts on, a notification within about six hours), and the download page's Android link
(landing/index.html:523, `/glyph.apk`, served from the same directory) gives it to new people.

`node tool/release_apk.mjs <the release apk>` writes the four files into `build/cutover/` and uploads nothing. It
was run with a throwaway key: this app's core read `apk.json` by `apk.json.flutter.sig` and refused `apk.json.sig`,
and `apk.json.sig` verified by scripts/ota-sign.mjs's rule (the context, then the bytes).

Not proven: a real Tauri install offering it. That needs the real signing key and the real address, which is
publishing. The safe order makes it a small step: see section 6.

There is no copy on Google Play (docs/store/PLAY_STORE.md: blocked on the upload key), so no store is involved. The
Play build of the Tauri app (`GLYPH_STORE=play`) neither offers nor fetches an APK; if one is ever published there,
this app would need a build without `REQUEST_INSTALL_PACKAGES` and with `Updates` off.

## 4. Defaults

- **The service.** A release told nothing is on `https://ghostmarkdown.com/api`, the page's own `API_BASE`
  (src/app/core/account/api.ts:14). A debug or profile build still has no account unless given `GHOST_API`, and
  still refuses the real service (lib/root/account_wiring.dart `accountBase`, with its tests).
- **The assistant, the side key, "Record note".** Off in every build (`GHOST_ASSISTANT=1` turns them on for a
  build). A developer turns them on for one phone: Settings › Developer › Work in progress › Voice assistant, a
  device flag `glyph-wip-assistant` that a reset keeps, as `voice/assistant-flag`'s DESIGN §146 has it
  (lib/core/wip.dart, android/…/AssistantSwitch.kt). Unlike that branch, which could only decline a key the phone
  still sent, the switch enables or disables the manifest's four components and publishes or removes the shortcut.
  Two things that branch's switch also did are NOT done here: it silenced the spoken commands in the recorder
  ("Hey Ghost", "add a note to …"), and it changed home's empty line, which here still says "hold the side key and
  say it". The card is the page's last, where the branch has it first, so the rest of the page stays held to
  `main`'s page rect for rect. On the emulator the release build offered no assistant service and answered no
  capture action; the switch itself is held by a widget test and was not pressed on a phone.

## 5. The repository: `main` of `glyph` is this app

Done 2026-10-11. `main` of the `glyph` repository has this app at its root, the Tauri app whole under `tauri/`, and
the service, the connector, the landing page and the Windows workflow where they were. One repository, both
histories, nothing deleted: every Tauri file was moved by `git mv` (`git log --follow tauri/<path>` reaches its
history), and this app's own history came in by a merge of its `main` (`c42175b2`).

| Where | What | Deployed from |
| --- | --- | --- |
| the root | this app | `tool/cutover-build.sh <version>`, `node tool/release_apk.mjs build/app/outputs/flutter-apk/app-release.apk`, then `node scripts/deploy-flutter-apk.mjs` (reads `build/cutover`; `--print` checks the four files and logs in nowhere) |
| `tauri/` | the web app, the Mac app, the Windows app, the reader page (`read.html`, `src/read`) | `cd tauri && node scripts/deploy-ota.mjs` (never `--apk`: it is refused), `cd tauri && node scripts/deploy-windows.mjs` |
| `server/` | glyph-api | `node scripts/deploy-server.mjs` from the root (or `cd tauri && npm run deploy:server`, the same script) |
| `mcp/` | Claude's connector | the hosted one: `node scripts/deploy-server.mjs --mcp-only`; the one-file local one: `cd tauri && node scripts/deploy-ota.mjs --mcp`. Both build it with `node scripts/build-mcp.mjs` (root), which needs `npm ci` done in `tauri/` |
| `landing/` | ghostmarkdown.com | `node scripts/deploy-landing.mjs [--caddy]` from the root; its `parts/` are built by `cd tauri && npm run build:landing` |
| `.github/workflows/windows.yml` | the Windows installer | on a push to the branch `windows`; every step runs in `tauri/` |

**What was changed for it**, beyond the move:

- **This app reads `tauri/` where it read `../glyph`**: the `#[path]`s of `native/src/lib.rs` and `native/src/kept/`
  (`../../tauri/src-tauri/src/…`, `../../../tauri/…`), `native/Cargo.toml` (`../tauri/src-tauri/vendor/whisper-rs-sys`),
  `native/.cargo/config.toml` (the toolchain file, `GLYPH_REPO_DIR`, `GLYPH_MODELS_DIR`), every tool and test that
  named `../glyph` (one `../` fewer each), and the eleven tools and three fixture scripts that named
  `/Users/matt/Development/Apps/glyph/` or `…/ghost-flutter/` outright, which now find the tree from their own file
  (`new URL('../tauri/', import.meta.url)`). `tool/local-server.sh` copies `server/` from the root, not from the
  Tauri tree. The Tauri app's node_modules are `tauri/node_modules` and its models `tauri/models`.
- **The root's `scripts/`** holds the four scripts above and `scripts/lib/paths.mjs` and `env.mjs`. Everything else
  they share (the box's one login, `run`, `say`, the `.env` parser) is imported from `tauri/scripts/lib/`, so
  `deploy-ota.mjs` and `deploy-server.mjs` cannot come to disagree about the shared connection.
- **There is one `.env`, and it is `tauri/.env`** (Vite reads its `VITE_*` keys from beside `tauri/package.json`). The
  root's scripts read it from there, and read a `.env` at the root only when `tauri/.env` is absent.
- **`mcp/` reads `../tauri/src/…`**, and `mcp/node_modules` is a committed link to `../tauri/node_modules`, which is
  what lets `tsc -p ../mcp`, Vitest and esbuild resolve its packages. `tauri/vitest.config.ts` runs `../mcp/*.test.ts`
  and lets Vite serve the folder above; `npm run typecheck` in `tauri/` checks `../mcp`. **`npm run lint` in `tauri/`
  no longer reaches `mcp/`** (a flat ESLint config does not lint above its own folder): lint it by path, or give it a
  config of its own.
- **`tauri/scripts/`**: `lib/paths.mjs` has `ROOT` (`tauri/`) and `REPO` (one up); `deploy-ota.mjs` finds the
  connector's bundle and `build-mcp.mjs` under `REPO`; `landing-assets.mjs`, `landing-icons.mjs`, `landing-shots.mjs`,
  `vite.landing.config.ts` and the two `src/landing` tests write and read `../landing`; the test report runs
  `../server/Cargo.toml` and fingerprints `../server/src`, `../scripts` and `../mcp` with the rest.
- **`.gitignore`**: the root's is this app's, with `/mcp/dist`, `.env` and what a pulled checkout is left holding
  at the root (`/node_modules/`, `/dist/`, `/models/`, `/src-tauri/`); `tauri/.gitignore` is the Tauri app's own,
  unchanged but for `/mcp/dist`; `server/.gitignore` is as it was.

**What was run before `main` moved**, in a fresh clone: the core built from the new paths
(`GHOST_VOICE=0 tool/build-native.sh host`); `flutter analyze lib`; `flutter test` over `test/native`, `test/team`,
`test/live`, `test/editor/view/reference_test.dart`, `test/home`, `test/root/typing_budget_test.dart` and
`test/carry`; the kit's tests; eight fixture tools run again and writing the same bytes; in `tauri/`, `tsc`,
`tsc -p ../mcp`, the whole Vitest suite, `build:landing` (the same bytes) and `build-mcp.mjs`; `cargo metadata` for
`tauri/src-tauri`, `server` and `native`. **Not run:** any deploy, any login, an APK, the Mac or Windows build, the
Tauri app's cargo tests, `tool/check.sh` whole.

**A checkout that was pulled across the move** has its tracked files in `tauri/` and its ignored ones still at the
root, because git moves only what it tracks. Move them: `mv .env node_modules dist models tauri/` (those that
exist), and `src-tauri/target` and `src-tauri/gen/android`'s build folders into `tauri/src-tauri/` or delete them
(`rm -rf src-tauri`: they are build output). `mcp/dist` and `server/target` stay where they are. A worktree or
branch begun before the move merges `main` like any other: git follows the renames, and a file it created at the
old root (a new file under `src/`, say) has to be moved into `tauri/` by hand. **Nobody deploys from a checkout
older than the move**: a deploy ships the tree it is run from, so an older checkout publishes an older web app
over the live one, and one from before `6cd2d7de` also deletes this app's signature from the box
(`apk.json.flutter.sig`) and can place a Tauri APK over this app. It is the hazard the Windows download already met.

**The branch `windows`** is still the old layout, with the old workflow, and builds as it did. It takes the new
workflow when it next merges `main`; until then do not copy the new `windows.yml` onto it alone.

**The way back.** The tag `tauri-last-main` and the branch `tauri` are `main` as it stood before the move
(`6cd2d7de`). Putting `main` back is `git push --force-with-lease origin tauri-last-main:main`, which needs the
owner's word; without rewriting anything, `git revert -m 1` of the merge and a revert of the two commits before it
does the same to the tree. The published APK is the other half and has no way back on a phone that took it: Android
will not install 1.15.0 over 2.0.0. What can be undone is the offer (put the previous `apk.json`, `apk.json.sig` and
`glyph.apk` back: `scripts/deploy-flutter-apk.mjs` keeps the three beside the release, in
`/opt/attackfm-site/glyph.apk-before-<stamp>`), and a phone that already updated keeps this app and its carried
data; the Tauri app's own files are still under it, untouched, for as long as the carry's rule stands.

If the owner wants `main` to hold nothing of Tauri at all, that is another move: copy the twenty Rust files and
`vendor/whisper-rs-sys` into `native/`, and build the web app, the reader page, the Mac and Windows apps only from
the `tauri` branch. It splits one Rust library into two copies; it is not recommended while both apps ship.

## 6. To publish, in order

1. Merge `cutover` into `main` of this repository. This branch changes nothing native, so the core needs no rebuild for it.
2. On a spare phone, or the Fold with the owner's say: sign in on the Tauri app, leave an unsynced note, then
   `adb install -r` the release from `tool/cutover-build.sh 2.0.0` (pick the version). Read
   `carry/tauri-carry.log`, edit a note on each side, see both arrive. This is the proof this file lacks.
3. The two guards in `tauri/scripts/deploy-ota.mjs` (it spares `apk.json.flutter.sig` and refuses `--apk`): done,
   `6cd2d7de`. No deploy.
4. `node tool/test_report.mjs`, then `tool/cutover-build.sh <version>` on the Mac that has
   `~/.config/glyph/android-signing.properties`.
5. `node tool/release_apk.mjs build/app/outputs/flutter-apk/app-release.apk`: it refuses a wrong id, a debuggable
   build, a version code not above 1015000, another certificate, or a key the apps do not trust.
6. `node scripts/deploy-flutter-apk.mjs` does this step in one login. By hand it is: keep copies of the live `glyph.apk`, `apk.json` and `apk.json.sig`. On the box, into `/opt/attackfm-site/glyph` (one login; the limits on logins apply): `glyph.apk` first, whole,
   then `apk.json.flutter.sig`, then `apk.json` and `apk.json.sig` together, last. Until that last pair lands no
   installed app sees anything. Check `https://attack.fm/glyph/apk.json` against `build/cutover/apk.json`, and the
   size `glyph.apk` is served at.
7. Watch one Tauri install offer it and take it. Then say so in the changelog the Tauri page reads, if wanted.
8. The repository move (section 5): done; it did not gate the release.

## 7. The Mac

Matt, 2026-10-12: "Carry notes over first". The Mac app that replaces the Tauri Mac app is built and its carry is
proven on a copy of a real Mac's data. **Nothing in this section has been signed with a Developer ID, notarised,
published or installed**, and the Tauri app's own files were only ever read.

### What the Tauri Mac app (1.15.0) keeps, and where

A Mac is not a phone: the page's storage is not in the app's folder, and it is WebKit's, not Chromium's.

| What | Where |
| --- | --- |
| The notes, their `.versions` files, each note's sidecar, the core's index | `~/Library/Application Support/com.mattssoftware.glyph/Library/`, `Library/.glyph/notes/`, `Library/.glyph/index.sqlite` |
| Pictures, recordings, films, models | `…/com.mattssoftware.glyph/images/`, `recordings/`, `video/`, `models/` |
| A library folder the person chose, and its index | `…/library-root.json` (`{"kind":"folder","path":…}`), `…/index/<key>.sqlite` |
| Downloaded pages, a write-up's config, the notes before 1.3.0 | `…/ota/`, `…/jobs/`, `…/glyph.sqlite` |
| Slack's webhooks, Notion's sign-in | `…/slack.json`, `…/notion.json`, in the clear, mode 0600. The Rust uses no Keychain. |
| Every `glyph-…` key of `localStorage`: the preferences (with the workspaces, the trash, the open tabs, the shares), the sync's cursors and marks (`glyph-sync-<account>-…`), versions not yet written beside a note (`glyph-versions-…`), the once-flags | `~/Library/WebKit/com.mattssoftware.glyph/WebsiteData/Default/<hash>/<hash>/LocalStorage/localstorage.sqlite3`, the folder of the origin `tauri://localhost`; a value is UTF-16 text in a BLOB |
| The session (`glyph-account-session`: token, handle, account id) and GitHub's token (`glyph-github-token`) | the same `localStorage`, in the clear |
| The account key (AES-256-GCM), the device's signing key (Ed25519), the account's pair (P-256), each a `CryptoKey` that cannot be exported | `…/<hash>/<hash>/IndexedDB/<hash of "glyph-account">/IndexedDB.sqlite3`, store `keys`. **Wrapped**, unlike Chromium's: each is AES-128-GCM under a fresh key that is itself wrapped (RFC 3394) under WebKit's "WebCrypto Master Key". |
| WebKit's master key for this app | The login Keychain: a generic password, account `com.apple.WebKit.WebCrypto.master+com.mattssoftware.glyph`, label "Glyph WebCrypto Master Key". Its access list is the app that made it. |
| A team note's document, with what was typed and not yet sent | `…/IndexedDB/<hash of "glyph-team">/IndexedDB.sqlite3`, store `docs`, in WebKit's `SerializedScriptValue` |

Nothing is kept in `~/Library/Preferences` (there is no `com.mattssoftware.glyph.plist`), and `~/Library/Caches/com.mattssoftware.glyph` holds nothing of the person's.

### Where the replacing app keeps its own, and why

**`~/Library/Application Support/com.mattssoftware.glyph.v2`** (and `~/Library/Caches/com.mattssoftware.glyph.v2`),
`cutoverFolder` in macos/Runner/GhostChannels.swift. The build has the Tauri app's bundle id, since it is that app's
next version (the same icon in the Dock, the same `ghostmd:` links, the same Keychain identity); it does not have
its folder.

- Not the Tauri app's folder. That folder and `~/Library/WebKit/com.mattssoftware.glyph` are **the way back**: this
  app never writes, moves or removes anything in either, so somebody who puts 1.15.0 back finds every note, setting
  and key as that app left them. (What they would not find is what was written in this app since.)
- Not a folder inside it. The rule every build is held to, in Swift (`ownDirectory`) and in Dart (`isRealAppPath`,
  `DevicePaths.own`), is "no path with a folder named exactly `com.mattssoftware.glyph` in it is ever opened or
  written". A sibling keeps that rule whole, with nothing carved out of it for one build. The Tauri app's reset
  and export also walk named children of its folder; a sibling can never be one of them.
- Not `com.mattssoftware.glyph.flutter`, where a development build ("Ghost Flutter") keeps made-up notes: a
  person's library and a build under test never share a folder.

Beside the folder, the app keeps its preferences in `~/Library/Preferences/com.mattssoftware.glyph.plist` (the
system's store for the bundle id, every key prefixed `flutter.`; the Tauri app keeps no such file) and its secrets
in the login Keychain under the service `com.mattssoftware.glyph.secure`. Every other Mac build is unchanged:
"Ghost Flutter", `com.mattssoftware.glyph.flutter`, its own folder, and no carry.

### What is carried, and what is not (lib/carry/mac_carry.dart)

On the first launch, in three halves, each marked in `…glyph.v2/carry/tauri-carry.json` and logged in
`carry/tauri-carry.log` (counts and names of settings; never a note's name or words, a key, a token or the
session). A reset does not remove `carry/`, so notes erased in this app do not come back from the Tauri app's.

1. **`files`, before the core is opened.** Copied into this app's folder, each file under another name until it
   is whole, with the time it was last written, and never over a file already there: `Library/` (the notes, the
   `.versions` files, the sidecars and `library.json`), `images/`, `recordings/`, `video/`, `library-root.json`,
   `glyph.sqlite`. A file is cloned where the disk can (APFS: no bytes copied) and copied where it cannot.
2. **`settings`**: every `glyph-` key of `localStorage` but the two secrets into the preferences, text for text,
   and the team documents to `team/<account>/<note>.json`. Read from **copies** of WebKit's SQLite files, made in
   a temporary folder with their `-wal` and `-shm` and removed after (lib/carry/webkit_stores.dart): the originals
   are never opened by SQLite at all. It does not run until `files` is done, so the sync's cursors are never
   carried over half a library, which would read the missing notes as deleted.
3. **`secrets`**: the session, GitHub's token, Slack's webhooks, Notion's sign-in and the three keys into the
   Keychain, each read back.

**The keys, and the same rule as on a phone: a key is proven before it is believed.** The app reads WebKit's master
key from the Keychain (read, never changed; `GhostChannels.webCryptoMasterKey`), with the Keychain told not to ask
the person: an app the Keychain takes for the Tauri app (the same bundle id, signed by the same team) is handed it
in silence, and any other build is refused in silence. With it each key is unwrapped in Dart
(lib/carry/aes_unwrap.dart), GCM's tag checked. Then:

- the device's key and the account's pair must each, raised in the core, answer the public key WebKit kept beside it;
- the account key must open something the page itself sealed under it: a notification's words, of which the page
  keeps its sealed copies in `localStorage` (`glyph-sync-<account>-notifications`, context `notification:<id>`).
  With none of those to try, it is carried on the tag alone, which says the bytes are the ones WebKit wrapped.

A key that cannot be read or does not prove itself is not carried. The person is then signed in and asked for
their password once, as on a device that lost its key; nothing is lost, since the service holds the account key
wrapped.

Not carried:

- `Library/.glyph/index.sqlite`, and a chosen folder's `index/`: the core makes its index again from the notes.
  The one thing lost with it is the undo log of spoken commands.
- **Models.** Cloned where the disk can, which costs no space and leaves two files that cannot change each other;
  where it cannot (not APFS, or another volume), left to be downloaded again. They are gigabytes, never a
  person's writing, and a link into the Tauri app's folder would be a way to write to it. Never a `.part`.
- `ota/`, `jobs/`: nothing in this app reads them.
- `slack.json`, `notion.json` as files: their contents go to the Keychain, not to a second file in the clear.
- **A library folder the person chose** is not copied: `library-root.json` is, and the same folder is opened where
  it is, as on a phone. It is the person's folder; both apps would then write the same notes.
- A Mac whose WebKit still keeps the older layout (`WebsiteData/LocalStorage/` and `WebsiteData/IndexedDB/` with
  no `Default/<hash>/<hash>/` for the origin; on this Mac those two folders are there and empty): its files are
  carried, its settings and session are not, and the person signs in again. Not built, because there was no such
  storage to hold a reader to.
- The Tauri app's window place, and anything of the system's (`ghostmd:` is claimed by the same id as before).

With nothing to carry (no Tauri folder and no storage for `tauri://localhost`) all three halves are marked at once
and nothing is asked of anything, ever.

### The build, and updates

`tool/cutover-build-mac.sh 2.0.3` leaves `build/release-mac/Ghost.md.app`: "Ghost.md", `com.mattssoftware.glyph`,
version 2.0.3, build 2000003, stamped with `GHOST_BUILD` and `GHOST_COMMIT`, universal (the app, Flutter's two
frameworks and the Rust core are each `x86_64 arm64`; the script refuses a bundle in which any is not). It is the
one switch in two halves, as on Android: `GHOST_CUTOVER=1` in the build's environment (the name and the id,
macos/Runner/Configs/AppInfo.xcconfig) and `--dart-define=GHOST_CUTOVER=true` (the carry). A release is on
`https://ghostmarkdown.com/api` by itself. The app is signed ad hoc, as every local build is;
`node scripts/deploy-flutter-mac.mjs --prepare build/release-mac/Ghost.md.app` signs and notarises it.

**Updates: the Mac app has none of its own.** `Updates.forBuild` hands a Mac nothing (lib/core/updates.dart), the
script gives the build no address, and About says "Updates from: Nowhere in this build". A new version reaches a
Mac as a new download. The Tauri Mac app, for its part, offers its people the 2.x download
(tauri/src/app/core/macSuccessor.ts); it migrates nothing itself.

### Proven

- **The readers, against a real WebKit.** tool/webkit_fixture.swift runs a WKWebView at `tauri://localhost` that
  keeps what the page keeps the way it keeps it (keys that cannot be exported, an Ed25519 key generated in place,
  a key written and deleted first, team documents, 70,000 characters in one `localStorage` value), handing WebKit
  a master key of its own so that no Keychain is touched. `flutter test test/carry/webkit_stores_test.dart` reads
  that storage with the app's reader and finds every value the page said it wrote: the account key's bytes, the
  pair's scalar and public point, an Ed25519 seed, and each private key raised in the core answers its public
  key. The same tests run against storage made in Dart in the same layout, so they pass from a fresh checkout
  (the WebKit fixture holds made-up keys and is not in git; where it is absent that group is skipped and says so).
- **The crypto**, against FIPS 197, RFC 3394 and the GCM specification's own vectors (test/carry/aes_unwrap_test.dart).
- **The carry** (test/carry/mac_carry_test.dart, 18): a whole made-up Mac carried and read back by `DeviceKeyStore`;
  once only; never over a file already here; cut short (a note that cannot be read) carries no setting and no
  session, and run again is whole; no master key; the wrong master key; an account key that does not open what the
  page sealed; no sealed thing to try; models cloned or left; a chosen folder; a signed-out app; a Mac the Tauri
  app was never on; the guard; and that not a byte, name or time of the Tauri app's folders changes.
- **On a copy of this Mac's real data** (2026-10-12; `test/carry/mac_carry_proof_test.dart` says how the copy is
  made, and prints numbers only). The Tauri app's folder without `models` and its WebKit folder, cloned into
  `build/`, and the carry run over the clone:

  | | The Tauri app kept | Carried |
  | --- | --- | --- |
  | Notes | 338 | 338, and the core lists 338 on the carried library |
  | `.versions` files | 20 | 20 |
  | Sidecars | 13 | 13 |
  | Pictures | 28 | 28 |
  | Recordings | 12 | 12 |
  | Films | 0 | 0 |
  | `localStorage` keys | 23, all `glyph-` | 22 into the preferences, the session into the secure store |
  | Workspaces | 4, in the preferences | with the preferences |
  | Versions held in `localStorage` | 1 | with the settings |
  | Team documents | 109 | 109 |
  | A session | yes | yes |
  | Stored keys | 3 records, 5 wrapped keys (account, device, encryption) | **found, not opened** (below) |
  | Things the page sealed under the account key | 94 | what the account key will be proven on |

  412 files the same byte for byte and time for time, none missing; nothing that could not be read; and the copy
  itself unchanged afterwards (1,248 files and folders, each length, time and hash). GitHub, Slack and Notion are
  not set up on this Mac, so none was there to carry.
- **The built app, started once on the copy.** `build/release-mac/Ghost.md.app`'s own binary, in a copy whose bundle
  id was changed to `com.mattssoftware.glyph.carryproof` (so that its preferences could not land in the real id's),
  with `CFFIXED_USER_HOME` naming a folder under `build/` whose `Library` held the copy, under `sandbox-exec` with
  the network and every real folder of the Tauri app's denied, and with the `secrets` half marked done by hand so
  that it could not sign in. It opened a window, copied the files itself (338 notes, 28 pictures, 12 recordings),
  carried the settings (22 keys, 109 team documents), and its core made an index of **338 notes** in the carried
  library. The copy still matched the real folders file for file afterwards, and the real `~/Library` was as it
  had been once the proof's own preferences file was removed. The copy was then deleted.
- **The Keychain question** (the query `webCryptoMasterKey` makes, on an item made and removed for the purpose): a
  program that made the item reads it; another program is refused at once, with no panel.

### Not proven, and what would prove it

- **The keys on real data.** WebKit's master key was never read: only a build signed as the Tauri app is handed it
  without asking, and nothing here may be signed. The first signed build, started on a Mac with the Tauri app's
  data, proves it or does not: `~/Library/Application Support/com.mattssoftware.glyph.v2/carry/tauri-carry.log`
  must say "WebKit's key opened 3 of 3 stored keys", "the account key opened what the page sealed", and that the
  device and encryption keys answer their public keys. If the Keychain refuses (the log says "the Keychain did not
  give WebKit's key"), the app is signed in and asks for the password once: worse, not broken.
- **That the Keychain takes the signed Flutter app for the Tauri app.** It should: the item's access list is the
  app's designated requirement (the id and the team), which is how each Tauri update kept reading it. It is the
  one thing above this cannot show without the certificate.
- **The exact build's own folder.** The run on the copy had another bundle id, so `folderName`'s one line (the
  Tauri id gives `com.mattssoftware.glyph.v2`) was held by a test of the source and by the build's settings, not
  by a launch. The unchanged build was not started against the copy because the system keeps preferences by
  bundle id wherever the home is said to be, and they would have gone into the real id's file.
- **A real account against the real service after the carry**, as on Android: the session and the sync's cursors
  are carried; that the service takes them and the engine syncs was not run.
- **An Intel Mac**, a Mac on an older macOS (WebKit's serialisation is version 15 here), a library of thousands of
  notes, and a chosen library folder with real notes in it.

### To publish, in order

1. `tool/cutover-build-mac.sh <version>` from a clean `main`.
2. `node scripts/deploy-flutter-mac.mjs --prepare build/release-mac/Ghost.md.app` (signs, notarises, makes the image).
3. **Before anything is uploaded**, on a Mac with the Tauri app's data and with the Tauri app quit: start the
   signed app from where `--prepare` left it and read `carry/tauri-carry.log`. This is the proof this section
   lacks. To try it without the real folders, `GHOST_CARRY_LIBRARY=<a copy of ~/Library>` makes the carry read from
   the copy; the app's own folder and preferences are still the real ones, so do that on a spare account.
4. The way back for one Mac: quit, delete `~/Library/Application Support/com.mattssoftware.glyph.v2` and
   `~/Library/Preferences/com.mattssoftware.glyph.plist`, remove the Keychain items of the service
   `com.mattssoftware.glyph.secure`, and put 1.15.0 back. Its folder and its web view's storage were never touched.

## 8. The iPhone

Matt, 2026-10-13: the Tauri iPhone app, 1.10.0, was accepted into the App Store (Ghost Markdown, 6818598896,
`com.mattssoftware.glyph`, iPhone only, notes only), and the next version sent for review is this app ("Option b
now"). The build that does that is made and signed, and its carry was walked end to end in a simulator over data
the Tauri app itself made. **Nothing in this section has been uploaded to App Store Connect or TestFlight, and no
real iPhone has run it.**

### What the Tauri iPhone app keeps, and where

Seen in the container of the Tauri app built from `tauri/` as it stands (1.15.0's page; the nearest thing to 1.10.0
that builds) in an iPhone 18 Pro simulator on iOS 27.0. Tauri names its folders on an iPhone as it does on a Mac
(`dirs`' `data_dir` is `$HOME/Library/Application Support`, and an iPhone app's `$HOME` is its container), and the
web view is the same WebKit, so inside the container the layout is the Mac's `~/Library`, file for file:

| What | Where, under `<container>/Library` |
| --- | --- |
| The notes (an organization's under `orgs/<its name>/`), their `.versions` files, each note's sidecar, `library.json`, the core's index | `Application Support/com.mattssoftware.glyph/Library/`, `…/Library/.glyph/` |
| Pictures | `Application Support/com.mattssoftware.glyph/images/` |
| The page updater's own note of itself | `Application Support/com.mattssoftware.glyph/ota/installed.json` (an iPhone downloads no page) |
| Every `glyph-…` key of `localStorage`: the preferences (theme, workspaces, tabs, the trash), the workspace filtered by, the sync's cursors and marks, the bell's rows, the session (`glyph-account-session`), GitHub's token | `WebKit/com.mattssoftware.glyph/WebsiteData/Default/<hash>/<hash>/LocalStorage/localstorage.sqlite3`, the origin `tauri://localhost` |
| The account key, the device's signing key (an iPhone's WebKit has Ed25519), the account's pair, each a `CryptoKey` that cannot be exported; the team notes' documents | `…/<hash>/<hash>/IndexedDB/<hash>/IndexedDB.sqlite3`, one to a database; each key wrapped under WebKit's master key as on the Mac |
| WebKit's master key for the app | The Keychain: a generic password, account `com.apple.WebKit.WebCrypto.master+com.mattssoftware.glyph`, no service, in the app's own access group `F6ZAL7ANAD.com.mattssoftware.glyph`, readable while the phone is unlocked (`ak`), not synchronised |
| WebKit's own caches, the launch pictures, the saved scene | `Caches/com.mattssoftware.glyph/WebKit/`, `Caches/com.apple.WebKit.*`, `SplashBoard/`, `Saved Application State/` |

**Nothing else.** `Library/Preferences` is empty (no `com.mattssoftware.glyph.plist`), `Documents` is empty, and
there is no `recordings/`, `video/`, `models/`, `slack.json` or `notion.json`: an iPhone's Tauri app records
nothing, runs no model, and its Slack and Notion commands are not built (tauri/src-tauri/src/unsupported.rs).

**Who can see it, and what a backup takes.** The app shares no documents (`UIFileSharingEnabled` and
`LSSupportsOpeningDocumentsInPlace` are in neither app's Info.plist, and `Documents` holds nothing), so nothing of
it is shown in Files. Everything under `Library` but `Caches` is in an iCloud or computer backup, and nothing in
the Tauri app marks a file as left out of one: the notes, the pictures and the page's storage are all backed up.
The master key's class goes to another phone only in an encrypted backup or an iCloud one.

### Where this app keeps its own, and why

**`<container>/Library/Application Support/com.mattssoftware.glyph.v2`** (and `Library/Caches/com.mattssoftware.glyph.v2`),
`cutoverFolder` in ios/Runner/GhostChannels.swift: the Mac's answer, for the Mac's reasons (section 7). An update
from the App Store keeps the app's container, so this build wakes beside everything 1.10.0 kept (iOS gives the
container a new path at each update, and the files inside it are the same files).

- Not the Tauri app's folder and not inside it. This app never writes, moves or removes anything in
  `Application Support/com.mattssoftware.glyph` or `WebKit/com.mattssoftware.glyph`: the rule every build is held
  to in Swift (`ownDirectory`), in Dart (`isRealAppPath`, `DevicePaths.own`) and in the tests stays whole, with
  nothing carved out for a phone. An iPhone cannot be put back to an earlier version from the store, so here the
  untouched folders are less a way back than a second copy: if a carry goes wrong on somebody's phone, what they
  wrote is still there to be read by a fixed build.
- Beside it, under the same two parents, so it is kept exactly as the old folder was: in a backup, not in Files;
  the cache in neither. A folder under `Documents` would have shown people's notes in Files; a folder under
  `Caches` or `tmp` would have left them out of a backup and let the system delete them.
- The copy costs no room: each file is a clone on the phone's APFS (`clonefile`), a second name for the same
  blocks. A backup counts both, which for notes and pictures is small.

Beside the folder: the preferences in the system's own store for the id (`Library/Preferences/com.mattssoftware.glyph.plist`,
every key prefixed `flutter.`; the Tauri app keeps no such file), and the secrets in the Keychain under the service
`com.mattssoftware.glyph.secure`, this device only, after first unlock (apple/Keychain.swift). Every other iPhone
build is unchanged: "Ghost Flutter", `com.mattssoftware.glyph.flutter`, a container of its own, and no carry.

### What is carried, and what is not (lib/carry/iphone_carry.dart)

The Mac's carry, called over the container's `Library` (the same three halves, the same marker
`…glyph.v2/carry/tauri-carry.json`, the same log beside it, once only):

1. **`files`**, before the core is opened: `Library/` whole (notes, `.versions`, sidecars, `library.json`),
   `images/`, and `recordings/`, `video/`, `library-root.json`, `glyph.sqlite` if a phone ever has them.
2. **`settings`**: every `glyph-` key of `localStorage` but the two secrets, text for text, and the team
   documents; read from copies of WebKit's SQLite files (with their `-wal` and `-shm`) made in the app's temporary
   folder and removed, with the system's SQLite (`/usr/lib/libsqlite3.dylib`, which an iPhone has).
3. **`secrets`**: the session, GitHub's token and the three keys into the Keychain, each read back. The keys are
   opened under WebKit's master key, which the Keychain hands to this build because it is signed into the same
   access group (the same team and the same id: `tool/cutover-build-ios.sh` refuses an IPA whose
   `application-identifier` is anything but `F6ZAL7ANAD.com.mattssoftware.glyph`), and **proven before they are
   believed**, as everywhere: a pair must answer its public key, the account key must open something the page
   sealed. A key that cannot be read or proven is not carried, and the person is asked for their password once.

Not carried: the core's index (made again), `ota/`, WebKit's caches, and what an iPhone's Tauri app never had.
With nothing to carry (a new install) all three halves are marked at once and nothing is asked of anything.

### The build

`tool/cutover-build-ios.sh 2.0.5` leaves `build/ios-store/Ghost.md-2.0.5-2000005.ipa`: "Ghost.md",
`com.mattssoftware.glyph`, version 2.0.5, **build 2000005**, iPhone only (`UIDeviceFamily` [1]), arm64, iOS 15 and
later, release, compiled with `--no-load_cse`, stamped `GHOST_BUILD` and `GHOST_COMMIT`, on
`https://ghostmarkdown.com/api` by itself, signed "Apple Distribution: Matt Wisniewski (F6ZAL7ANAD)" with the
profile Xcode keeps ("iOS Team Store Provisioning Profile: com.mattssoftware.glyph"), about 40 MB. It is the one
switch in two halves, as on Android and the Mac: `GHOST_CUTOVER=1` in the build's environment (the name and the
id, ios/Flutter/AppInfo.xcconfig) and `--dart-define=GHOST_CUTOVER=true` (the carry). The script checks what it
built (id, version, build, name, devices, the link scheme, the camera's sentence and no microphone's, the privacy
manifest, the core's five functions, the signature, the access group) and **uploads nothing**.

**The build number.** `CFBundleVersion` is one to three whole numbers with dots, compared number by number, and
each upload must be above the last. The store holds "1.10.0". This build's is the version made into one number the
way the phone's version code and the Mac's build are (2.0.5 is 2000005): above 1.10.0 at its first number. The
same version uploaded again is `--build 2`, which gives `2000005.2`.

`tool/cutover-build-ios.sh 2.0.5 --simulator --api http://127.0.0.1:<port>/api` makes the same app for a
simulator (a debug build, which is all a simulator runs), with a local service: what the proof below installed.

### Proven, in a simulator (2026-10-13)

A simulator made for it ("ghost-cutover", iPhone 18 Pro, iOS 27.0: the newest runtime that makes an ordinary
iPhone; 27.1 here makes only the folding one), a throwaway service on this Mac (`tool/local-server.sh`), and an
account made on it. Nothing asked ghostmarkdown.com or attack.fm: the Tauri app was built from a scratch copy of
`tauri/` with no `.env`, `VITE_GLYPH_API` naming the local service, and the two addresses its page asks at launch
(the changelog's and the Mac successor's) pointed at a closed port. Nothing in `tauri/` was changed.

1. **The Tauri app, used.** `npx tauri ios build --debug --target aarch64-sim`, installed, launched. Driven
   through its own page over the simulator's web inspector (its buttons clicked and its fields typed into by
   script; no finger can be sent to a simulator from here): an account made with its Sign up form; four notes
   typed (accents, a table, a to-do, a link between notes); a picture added through "Add image" (the phone's
   chooser cannot be pressed, so the page's file input was answered with a picture drawn on a canvas, and the app
   shrank and kept it itself); the Boreal theme, a font and an accent chosen; a workspace made and filtered by; an
   organization made and a note filed in it (a team document); one note edited on the phone and on a second
   device apart (the web client of `tool/web_client.mjs`, signed in to the same account), which the app kept
   twice and recorded as a sealed row in the bell; and a last note written with the page's requests failing as
   they do with no network, so it was never sent. The app was then stopped.
2. **What it left**: 14 notes, 1 `.versions` file, 1 sidecar, 2 pictures; 15 keys of `localStorage`; 3 key
   records (5 wrapped keys); 1 team document; 1 sealed notification; a session. 40 files and 28 folders in its two
   folders, each recorded with its length, time and hash.
3. **The update.** `xcrun simctl install` of this app's simulator build over it (an upgrade: the data stayed, in a
   container with a new path), and one launch. The log, whole:

   ```text
   files: 14 notes, 3 index files left, 1 sidecars, 1 versions files, 2 pictures; 0 could not be copied
   read copies of WebKit’s files: 15 keys of localStorage, 1 team documents, 5 wrapped keys
   settings: carried 15 (… 14 keys …), 1 team documents, left 0 this app already held (), failed 0 ()
   secrets: the account key opened what the page sealed
   secrets: the device key answers its public key
   secrets: the encryption key answers its public key
   secrets: WebKit’s key opened 3 of 3 stored keys (account, device, encryption)
   secrets: carried 4 (glyph-account-session, account, device, encryption), left 0 this app already held (), failed 0 ()
   ```

   The 18 carried files are byte for byte the Tauri app's. The first screen was the Tauri app's last: the same
   theme, the same open tabs, the same workspace filter, the unsent note, the bell's dot.
4. **The same account, syncing.** Without anyone signing in: Settings › Account read "cutover", "End-to-end
   encrypted", "Synced just now"; the note never sent reached the second device; a note and a line in the team
   note written on the second device arrived in this app; a note typed in this app arrived on the second device.
5. **Nothing of the Tauri app's changed**: after six launches and the syncing, its two folders matched the record
   of step 2 file for file (length, time, hash), and later launches added nothing to the log.

The pictures before and after are in `build/ios-proof/` (not in git; made-up notes only).

Tests (`flutter test test/carry/iphone_carry_test.dart`, 14): a made-up container in that layout carried whole and
read back by `DeviceKeyStore`; once only; no key from the Keychain; a disk that will not clone; a new install; the
guard in Dart and in the iPhone's Swift (word for word the Mac's); what a build is without the switch and with
it; the Info.plist, the privacy manifest and the script's promises.

### Not proven, and what would prove it

- **A real iPhone.** The simulator's Keychain put WebKit's key in the access group `F6ZAL7ANAD.com.mattssoftware.glyph`
  and handed it to this app's build, which carries the same `application-identifier`; a phone enforces the same
  rule from the signature, and the IPA's is checked, but no phone has run it. Proof: a phone with 1.10.0 from the
  store, signed in, with an unsent note; this build from TestFlight installed over it; then the first screen, and
  Settings › Account saying the handle and "Synced". If the Keychain refuses, the app is signed in and asks for
  the password once. The log is in the app's container, which a TestFlight build does not let anyone read off a
  phone: a development-signed build of the same commit installed over a development-signed Tauri build shows it
  (Xcode › Devices › Download Container), or About could be given a line that says how the carry went.
- **1.10.0 itself.** The Tauri app here was built from today's `tauri/` (its page is 1.15.0's). The storage
  layout is WebKit's and Tauri's, not the page's, and the keys' names have not changed since 1.10.0
  (`glyph-account`, `keys`), but the build in the store was not the one carried from.
- **An older iOS.** WebKit's serialisation and its folder layout were read on iOS 27.0. An iPhone whose WebKit
  keeps the older layout (no `Default/<hash>/<hash>/`) carries its files and not its settings or session, as on
  the Mac: the person signs in again and nothing is lost.
- **A phone restored from a backup onto another phone** before updating: the files come, and the master key
  comes only with an encrypted or iCloud backup. Without it, the password is asked once.
- **A release build's first launch.** The simulator's build is a debug one (a simulator runs no other). The
  release differs in the compiler, not in the carry's code; the first TestFlight launch is its proof.
- **A real account against the real service**, as on Android and the Mac.

### Store compliance for this binary

- **Privacy manifest**: `ios/Runner/PrivacyInfo.xcprivacy`, in the app. No tracking. Collected, only with an
  account, linked, for app function: User ID, Other User Content, Photos or Videos, Audio (the Tauri app's four,
  which the store's App Privacy answers already match; no location, which an iPhone build does not find).
  Required-reason APIs for the app's own code, read from what the core links: FileTimestamp C617.1, DiskSpace
  E174.1, SystemBootTime 35F9.1, UserDefaults CA92.1. The engine and `shared_preferences_foundation` (the one
  plugin) carry their own manifests.
- **Info.plist**: the name Ghost.md; the camera's sentence (Take Photo in the picture menu) and no other: no
  microphone, speech, location or photo-library sentence, since the build opens none of them (`PHPicker` needs
  none); `ghostmd://` claimed, `glyph://` dropped (the Tauri app claimed it for a shortcut nothing answered);
  no universal links (the Tauri app had none); the scene manifest; portrait and both landscapes; arm64 and Metal.
  **No entitlements file**, as the Tauri app's was empty.
- **Export compliance: see below. Flagged for Matt.**
- **Delete account**: Settings › Account › Delete account (lib/settings/panes/account_pane.dart).
- **Updates**: About says "Ghost.md updates through the App Store." and lists no releases; an iPhone build has no
  `ghost_md/updates` channel, checks no address and can install nothing.
- **Other platforms' names** (guideline 2.3.10), where an iPhone can reach them. Each is the page's own, so
  1.10.0 was accepted with it, and none was changed here: the "How Ghost.md works" example canvas says "Tap the
  microphone, or press the side key" (and the reviewers' demo account holds that canvas); the Academy's video
  lesson says "on Android"; three sentences that a core too old for a feature would say name attack.fm ("Sync
  needs the newest Ghost.md. Install it from attack.fm/glyph."), which this app's core never is.
- **Voice**: no way into a recording is drawn (`recordsVoice`). Two rows still speak of it, as the Tauri page's
  do: Settings › Account's "Sync meeting recordings" switch and the line under it about "the model you
  downloaded". Hiding both on an iPhone is a small change and a departure from the page; not made.
- **The reviewers' demo account** (tauri/docs/store/APP_STORE.md) stands as written: the release is on the same
  service, and the handle and the examples are an account's, not an app's.
- **Shown broken on an iPhone**: nothing found in the walk. One thing was wrong and is mended: on a dark theme with
  the phone set to light, the status bar's ink was dark on dark; it now follows the page (lib/app/ghost_app.dart).

### Export compliance

The Tauri app answered `ITSAppUsesNonExemptEncryption` false, truthfully: on an iPhone every cipher it used was
Apple's (WebCrypto in WKWebView, and WebKit's HTTPS). This app's are not Apple's: it seals notes in the Rust core
(native/src/crypto.rs: AES-256-GCM, PBKDF2 and HKDF over SHA-256, ECDH on P-256, Ed25519, with the `aes-gcm`,
`sha2`, `hmac`, `hkdf`, `p256` and `ed25519-dalek` crates), and its HTTPS is Dart's own (BoringSSL, inside
Flutter's engine), not `URLSession`. All of it is standard, published cryptography; none is proprietary.

Apple's own words, fetched 2026-10-13:

- "Set the value to `NO` if your app—including any third-party libraries it links against—doesn't use
  encryption, or if it only uses forms of encryption that are exempt from export compliance documentation
  requirements. Otherwise, set it to `YES`." and "Typically, the use of encryption that's built into the operating
  system—for example, when your app makes HTTPS connections using URLSession—is exempt from export documentation
  upload requirements, whereas the use of proprietary encryption is not." (Complying with Encryption Export
  Regulations)
- The table of App Store Connect Help, "Export compliance documentation for encryption": "Your app uses encryption
  limited to that within the Apple operating system": "No documentation required in App Store Connect." "Your app
  uses an industry standard algorithm, not provided within the Apple operating system": "Upload your French
  encryption declaration in App Store Connect." with the note "French encryption declaration form is only required
  if you're distributing your app on the App Store in France." Proprietary algorithms: a CCATS and the French
  declaration.
- "If your app uses exempt forms of encryption, you might alternatively be required to submit a year-end
  self-classification report to the U.S. government." (the same page as the first)

So, without deciding the law for anybody: **this binary falls in the second row**, where the Tauri one was in the
first. The Info.plist says `true`, which makes App Store Connect ask its questions for the build rather than wave
it through on the old answer. The ways on, for Matt:

1. Answer the questions as they are (standard algorithms, not Apple's), and either file the French declaration or
   take France out of where the app is sold.
2. Make the iPhone build's encryption Apple's (CryptoKit and CommonCrypto behind the core's crypto, and HTTPS
   through `URLSession`), and put `false` back with the Tauri app's reason. What that takes is set out below.

Whether a yearly self-classification report is owed in either case is a question of the U.S. rules that Apple's
pages point at and do not answer, and is not answered here.

### What the listing no longer matches

- **The screenshots** were shot from the Tauri page in WebKit. This app draws the same screens from the same
  design, but they are not pictures of this binary: shoot the seven again from the simulator build
  (`tool/ios-tour.sh` takes them) before the version is sent.
- **What's New** has no text for 2.0.5. Nothing a person sees is new by design; "A new engine under the same
  app. Your notes, settings and sign-in carry over." is the honest whole of it.
- **The description, subtitle, keywords and promotional text** name nothing this app lacks on an iPhone, as far
  as was walked (notes, the marks, pictures from photos or the camera, boards, tickets, queries, notebooks,
  journals, a canvas, workspaces, organizations, sync, a shared link, delete account). docs/PARITY.md is the list
  to hold it to before sending.
- **The App Privacy answers** stand (the manifest declares the same four).
- **The export compliance answer** in App Store Connect is the one above.

### To publish, in order

1. `tool/cutover-build-ios.sh <version>` from a clean, pushed `main`. It prints the IPA's path.
2. Decide export compliance (above). If the answer becomes Apple's own encryption only, that is a new build.
3. Upload, which nothing here does: with the suite's key,
   `xcrun altool --validate-app -f <the ipa> -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"` and then
   the same with `--upload-app` (the key file is found from `~/.appstoreconnect/private_keys/` or
   `API_PRIVATE_KEYS_DIR`), as 1.10.0 was sent; or Transporter.
4. **Before it is sent for review**, on a real iPhone that has 1.10.0 from the store, signed in, with a note
   written offline: install the build from TestFlight over it. The first screen must be the old app's last, and
   Settings › Account must say the handle and then "Synced". That is the proof this section lacks.
5. In App Store Connect: a new version 2.0.5 on the record, the build attached, What's New, the seven
   screenshots shot again, the export compliance answers, the review notes and demo account as before; check the
   demo account still holds its examples.
6. There is no way back on a phone: the App Store installs no earlier version. The Tauri app's folders are still
   in the container, untouched, for a later build to read if this one's carry failed somebody.

