# Replacing Ghost.md's Tauri app with this one

Matt, 2026-10-11: the Flutter app ships as the next update OVER the Tauri app, for everyone, when it is ready.
Updates use the Tauri app's own update signing key and release address. Release builds always talk to the real
service. The phone assistant, the side key and "Record note" are off behind a developer flag. The port's extra
sentence on a refused save stays. And in GitHub, `main` of the `glyph` repository becomes this app, with the Tauri
code kept on a branch.

This file is what that takes on Android: what is built (branch `cutover`), what was proven and how, what was not,
and what whoever publishes has to do, in order. **Nothing in sections 1 to 4 and 6 has been published, deployed or put on a
phone.** The Tauri app's tree was read and never changed for them. Section 5, the repository's move, is done.

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
- Anything on an iPhone, a Mac or Windows. This is Android's.

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
