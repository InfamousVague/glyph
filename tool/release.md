# What a release must build, sign and upload

**Decided 2026-10-11, and this file is older than the decision.** This app replaces the Tauri app as its next
version: it is signed with the Tauri app's certificate, its updates are signed with the Tauri app's update key and
live at the Tauri app's address, and its id becomes `com.mattssoftware.glyph`. `docs/CUTOVER.md` says how, and
`tool/cutover-build.sh` and `tool/release_apk.mjs` are the build and the packing. The four questions below are
answered there; what follows still describes what the client checks, with two changes: the signature this app reads
is `apk.json.flutter.sig`, and `apk.json` carries `native` and `build` for the Tauri installs that read it too.

For the app's own updates (lib/core/updates.dart, native/src/kept/updates.rs, android/…/ghost_md/UpdateInstaller.kt)
to find a release and trust it. **No script does this yet, nothing has been published, and no key has been made:**
this is what one has to do, written from what the client checks. The Tauri app's own equivalent, for reference, is
`tauri/scripts/deploy-ota.mjs` (with `ota-sign.mjs` and `ota-keygen.mjs`), which also publishes a web bundle; this
app has none, so only its `--apk` half has anything to carry over.

## What is still to be decided (the owner's)

1. **The APK signing key.** `android/app/build.gradle.kts` still signs the release build with the **debug** key
   (`signingConfig = signingConfigs.getByName("debug")`). Android installs an update only over an app signed by the
   same certificate, so whatever key signs the first build people install is the key every later one must be signed
   with: **an APK cannot update one signed with a different key**, and moving off the debug key later means everyone
   reinstalls, losing what is on the phone. Decide it before the first release goes out. (The Tauri app keeps its own
   at `~/.config/glyph/glyph-android.keystore` with `android-signing.properties`, its certificate pinned in
   `tauri/src-tauri/apk-signer.sha256`, which `deploy-ota.mjs` checks with `apksigner verify --print-certs` before
   it publishes. It cannot be this app's unless this app is to share that certificate.)
2. **The update signing key** (Ed25519), whose public half goes in `lib/core/update_keys.dart`. That list is
   **empty, and an empty list means no update check at all**. A key of this app's own, or the Tauri app's
   (`~/.config/glyph/ota-signing-key.pem`, public half in `tauri/src-tauri/ota-trusted-keys.txt`): either is safe,
   because the two apps sign different contexts (below), so a description signed for one can never pass as the
   other's. Without the private key no installed build accepts another update; back it up.
3. **Where releases live**: one https base address of this app's own, given to the build as `GHOST_UPDATES`. Not the
   Tauri app's (`https://attack.fm/glyph`, `https://ghostmarkdown.com/glyph`: the client refuses both outright). It
   cannot be moved by a signed file as the Tauri app's `sources` can; a build looks where it was built to look.
4. **Whether the app keeps the id `com.mattssoftware.glyph.flutter`** (docs/STAGES_5_6_8_9.md, stage 10).

## The build

```sh
node tool/test_report.mjs             # the whole suite, and what it did, into the build (below)
tool/build-native.sh android          # the core, with the engines (the default)
flutter build apk --release --target-platform android-arm64 \
  --build-name=0.2.0 --build-number=2000 \
  --dart-define=GHOST_UPDATES=https://<host>/<path> \
  --dart-define=GHOST_BUILD=$(date -u +%Y%m%d%H%M%S) \
  --dart-define=GHOST_SOURCE=$(node tool/test_report.mjs --source)
```

- **The test report is made first, before every release build**, and never after a change to the code: `node
  tool/test_report.mjs` runs `tool/check.sh` whole and writes what every test did to `assets/diag/test_report.json`,
  which the build carries and Settings › Test results (Developer mode) shows, as `tauri/scripts/test-report.mjs`
  does for the Tauri app (`deploy-ota.mjs` runs that before it builds). It exits 1 if anything failed or did not
  run: do not build then. `GHOST_SOURCE` is the fingerprint of the code the build is made from; the report holds the
  one its tests ran on, and the page says "The code changed after these tests ran" when the two are not the same.
  A build made without either is a development build: with no report the page says "No test report in this build.",
  which is what the repository's own `assets/diag/test_report.json` is (`node tool/test_report.mjs --clear` puts it
  back; commit the written one with the release only if the release's commit is to keep it, as the Tauri app's does).

- `--build-name` is the version people read (pubspec's `version`, and `ghostVersion` in
  lib/settings/panes/about_pane.dart, which a test holds to it). `--build-number` is Android's `versionCode`: **it
  must rise with every release**, since Android refuses an APK whose code is lower than the installed one, and the
  client offers a release whose version or whose code is higher than the installed app's.
- `GHOST_UPDATES`: the base address, https, no query; a trailing slash is dropped. Without it the build never looks.
- `GHOST_BUILD`: when it was built, UTC, fourteen digits; About's line under the version. Optional.
- A **debug** build never looks, whatever it is given. `GHOST_UPDATES_TEST=true` and `GHOST_UPDATES_TEST_KEY=<public
  key>` turn the check on in a debug build for a test run (an `http://` address, a throwaway key) and are read by
  nothing else: a release ignores both.
- Check the certificate before publishing, as `deploy-ota.mjs` does: `apksigner verify --print-certs app-release.apk`
  against the pinned SHA-256 of the key chosen in (1).

## The three files, under the base address

| File | What it is |
| --- | --- |
| `<name>.apk` | The release APK, exactly as built and signed. Any name of letters, digits, `.`, `_` and `-`. |
| `apk.json` | What the release is (below). The client parses it only after its signature verifies. |
| `apk.json.sig` | The detached signature of `apk.json`: base64, one line. |

`apk.json`, the Tauri app's shape (`ApkInfo`, `tauri/src-tauri/src/ota/manifest.rs`) without its `native`:

```json
{
  "version": "0.2.0",
  "versionCode": 2000,
  "sha256": "<lowercase hex SHA-256 of the APK's bytes, 64 characters>",
  "bytes": 104857600,
  "url": "ghost-flutter.apk"
}
```

- `version`, `versionCode`: the APK's own (`aapt dump badging`), or the client offers an update that Android then
  refuses, or installs one and offers it again.
- `sha256`, `bytes`: of the file served. The client refuses a download one byte longer than `bytes`, and hands
  nothing to Android unless the finished file is exactly `bytes` long and hashes to `sha256`.
- `url`: the APK's name beside `apk.json` (no `/`), or a whole `https://` address (a release asset on another host).
  Either way the signed hash decides.
- A `native` field is accepted and ignored: there is no web bundle here for a native generation to gate.

## The signature

Ed25519 over **the context `ghost-flutter-apk\0` followed by the exact bytes of `apk.json` as published** (so
sign the file that is uploaded, not a re-serialised copy), written base64 to `apk.json.sig`. The Tauri app signs
`glyph-apk\0` + bytes (`ota-sign.mjs` `CONTEXT.apk`); the different context is deliberate.

```js
import { createPrivateKey, sign } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
const body = readFileSync('apk.json');
const key = createPrivateKey(readFileSync(process.env.GHOST_UPDATE_KEY));   // an Ed25519 PEM, outside the repo
writeFileSync('apk.json.sig', sign(null, Buffer.concat([Buffer.from('ghost-flutter-apk\0', 'utf8'), body]), key).toString('base64') + '\n');
```

The public half, as `lib/core/update_keys.dart` lists it, is the raw 32-byte key in base64
(`ota-sign.mjs` `publicKeyBase64`: the JWK's `x`, base64url turned to base64). A fixture signed this way by a
throwaway key is `native/tests/fixtures/update/`, read by the Rust tests and by test/core/updates_test.dart.

To rotate the key: ship a build that lists the old key and the new one, move signing to the new key, drop the old
line in a later build.

## The order to upload in

1. The APK, under its final name.
2. `apk.json.sig`, then `apk.json` **last**: an installed app that reads a new `apk.json` beside an old signature, or
   before its APK is there, says it could not check, or fails the download, until the rest lands. (`deploy-ota.mjs`
   stages everything and places the manifests last for the same reason.)
3. Read the three back and verify them as the client does (`deploy-ota.mjs` does: signature against the trusted
   keys, hash of the served APK against `apk.json`).

Serve `apk.json` and its signature uncached or briefly cached; the client asks with `Cache-Control: no-cache`.

## What the client then does

Looks four seconds after launch, on every return to the app a minute or more after it last looked, and every two
minutes while in front; never with "Nothing leaves the phone" on. A newer release is the card above the notes, a line
on the launch screen and Settings › About's Updates row; Install downloads it into `<cacheDir>/updates`, verifies it,
and hands it to Android, which asks once to allow installs from this app and confirms every install on its own
screen. Not while a meeting records. Nothing looks while the app is closed (the Tauri app's `UpdateCheckWorker.kt` is
not ported), and there is no list of releases ("What's new", the Tauri app's `releases.json`).
