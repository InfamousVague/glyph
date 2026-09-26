# Over the air, and releases

_How a change reaches every phone without a new app, why a bad update cannot lock a phone out, and what a release does, in order._

The spine is the header of `src-tauri/src/ota.rs`. The work is split under `src-tauri/src/ota/`, one file a job, and the page's half is `src/app/core/ota.ts`.

## Two frontends, one page

Every binary carries a frontend, the embedded one, compiled in by Tauri. It can also run a newer one it downloaded, verified and kept under `<app data>/ota/`, served to the webview by a custom scheme, `ota` (`ota/scheme.rs`), at the files' real relative paths: `http://ota.localhost/` on Android and Windows, `ota://localhost/` on Apple platforms. Because the paths are real, the update is simply `dist/`, the same build the website serves. `ota.json` lists every file under `dist/assets/` with its size and SHA-256, and an install reuses any file the active bundle or the APK already holds (`ota/install.rs`), so a release that only touched the code downloads little more than its script and styles.

The document itself never moves. `index.html` is always the embedded one, at the app's own origin, so storage, the native bridge and the microphone permission are the same whichever frontend runs. Its inline loader, plain ES5 at the end of `body`, asks `ota_claim_boot` what to run, adds that bundle's stylesheets and then its script. It never removes the embedded script tag: each copy of `src/main.tsx` asks `window.__glyphBoot` whether it is the chosen one, and only that one mounts. In a browser, or on the dev server, the loader does nothing.

## The boot wager

Four rules, in `ota/boot.rs`, keep a bad bundle from locking anyone out.

| Step | What happens |
|---|---|
| `ota_claim_boot` | The one call that changes state at launch. It stakes the bundle it hands out as `pending` in `state.json`. |
| `ota_boot_ok` | The frontend that mounted reports its build (`settleBoot`, the first thing the Shell's housekeeping does in `src/app/shell/useHousekeeping.ts`, before any update check). A match clears the stake. The embedded frontend mounting clears it too, without counting against the bundle, which was never tried. |
| The next claim | A stake still standing means a launch ran the bundle and it never mounted: a strike. Two strikes quarantine the build for good, and the app falls back to the previous bundle or the embedded one. One is not enough, because the phone killing the app in its first second is ordinary. |
| `ota_boot_failed` | The loader's escape in the same launch: a stylesheet or script that will not load, a bundle that throws while starting, or one not mounted within 8 seconds is quarantined at once, and the embedded frontend mounts. |

An answer to the claim slower than 1.5 seconds boots the embedded frontend. A download no newer than the APK's own frontend is dropped at the claim, so a new APK installed over an old update runs its own.

## Native generations

A bundle can only run on a binary that has the commands it calls. Two numbers in `ota.rs` say which.

- **`NATIVE_GENERATION`** is what this binary provides: 19 at 1.8.0. Its doc comment lists what each generation brought, from signed manifests (2) through the library of Markdown files (15) and sync (16) to revision-checked note writes and guarded commands (19). A generation never goes backwards.
- **`BUNDLE_REQUIRES`** is what the page built from this tree needs. `vite.config.ts` reads it out of `ota.rs` (`scripts/lib/otaRs.mjs`, which stops the build if it is no longer a literal) and stamps it into `ota.json` as `native`. It is 19 at 1.8.0 as well, so a phone on an older APK is answered `needs-native` and offered the new APK instead of the update. A compile-time test keeps it at or under `NATIVE_GENERATION`.

Never stamp `NATIVE_GENERATION` into `ota.json`. That is how AttackFM, where this system was learned, once locked every older binary out of every later update. The deploy writes `NATIVE_GENERATION` into `apk.json`, where it belongs: it is what the APK provides.

Most features leave `BUNDLE_REQUIRES` alone. Each gates itself on its own threshold through `hasNativeGeneration` (`src/app/core/nativeGeneration.ts`), such as `FILES_GENERATION = 18` in `src/app/core/libraryFiles.ts`, and hides on an older binary rather than calling a command it lacks.

## Trust is a key, not a domain

`ota.json` and `apk.json` are Ed25519-signed, with a detached `.sig` beside each and a context prefix, so a signature for one kind of file cannot pass as the other (`scripts/ota-sign.mjs`, `ota/fetch.rs`). The app accepts a manifest only if a key compiled in from `src-tauri/ota-trusted-keys.txt` signed exactly its bytes, and parses it only after the signature holds. Every file is then checked against its SHA-256, and a downloaded one against its size as well; the bundle is staged and renamed into place whole.

So any host may serve updates, a redirect cannot inject one, and a domain that lapses and changes hands can stop updates but cannot ship code. A key is rotated by listing two: ship an APK that trusts both, sign with the new, drop the old in a later APK. The private half never enters the repository; without it, no installed app takes another update until a new APK is installed by hand. The APK itself is fetched by Rust (`ota/apk.rs`), checked against its signed SHA-256 as it streams, and handed to Android's installer.

## Where updates come from

`src-tauri/ota-sources.txt` is compiled in and published. Today it has one line, `https://attack.fm/glyph`. The deploy stamps it into the signed `ota.json` as `sources`, and an app that verifies that manifest remembers the list (`ota/sources.rs`) and tries it first, with the compiled list always after it. An older signed manifest can never roll the list back. So moving to a new domain is a publish, not a new APK; the README's "Moving to another domain" is the procedure.

Android and the Mac app take updates over the air. iOS takes none: the fetch and the install are not built there, `ota_check` refuses, and `core/ota.ts` never asks. Neither does a staging build, a dev build, or a phone with Settings › Formatting › Local only on.

## When the app looks

`useUpdates` in `src/app/core/ota.ts` looks four seconds after launch, whenever the app comes back after a minute or more, and every two minutes while it is in front, and installs quietly. The home page then says "A new version of Ghost.md is ready." with Reload; a cold start picks it up anyway. A newer APK gets a card of its own, with Install. Settings › About has the rest: the Updates line (`src/app/settings/updateLines.ts`), Check for updates, and What's new, every release from `changelog.json` (`src/app/core/changelog.ts`).

Update alerts, on Android and off by default in Settings › About, come from a WorkManager job (`updates/UpdateCheckWorker.kt`) that runs about every six hours with the app closed. It calls into Rust (`src-tauri/src/update_alerts.rs`, then `ota::peek`), which verifies exactly as `ota_check` does and installs nothing. One release alerts once.

## A release, in order

`node scripts/deploy-ota.mjs`, or `npm run deploy:ota`, publishes to attack.fm/glyph.

1. It refuses to start without a signing key the app trusts.
2. It runs every test suite (`scripts/test-report.mjs`). A failure, or a suite that did not run, stops it before anything is built.
3. It numbers the release, one past the live `ota.json` on the same version or 1 on a new one: 1.8.0-12 is the twelfth update published on 1.8.0. A live manifest it cannot read stops it rather than guessing.
4. It builds the web app once (`npm run build`: `tsc`, then Vite, which writes `dist/ota.json`) and checks that the manifest's entry is the script `index.html` loads.
5. With `--apk`, it builds the release APK with Vite told not to run again. BUILD ONCE: a second build would stamp a new build id, and the APK would carry a different frontend from the one published. Then it checks the file: signed by the pinned certificate (`src-tauri/apk-signer.sha256`), not debuggable, and newer than the live APK.
6. It writes `changelog.json`, the live list merged with `scripts/changelog-seed.json`, each release with its notes or "Fixes and polish.", and signs the manifests.
7. It uploads, placing the manifests LAST, each by an atomic rename. ORDER IS THE SAFETY: a phone reading mid-deploy sees the old manifest, which fails verification and is tried again later, or the new one with every file in place.
8. It checks what came back as a phone would: the page serves this build, `ota.json` verifies against its signature, and the entry's SHA-256 matches.

| Flag | What it adds |
|---|---|
| `--apk` | The APK, for a change to Rust, Kotlin or the Android manifest |
| `--same-version` | Republish an APK whose version is not newer |
| `--desktop` | The Mac app: universal, signed, not yet notarised, with `desktop.json` |
| `--mcp` | Claude's connector as one file, at attack.fm/glyph/mcp/glyph-mcp.mjs |
| `--notes "…"` | What changed: the What's new line and the alert's text, 2,000 bytes at most, counted as the phone counts them, so a curly quote is three |
| `--release <n>` | The number by hand, after a rollback put an older manifest back |
| `--skip-tests` | Ship without the tests; if the code changed after the report in the tree was made, the build's Test results page says its report is from other code |

A native change needs `--apk` and a version bump. The version is written twice, in `package.json` (the page and the release number) and `src-tauri/tauri.conf.json` (the APK and the Mac app), and no test compares them, so change both. `src-tauri/Cargo.toml`'s own version is not the app's.

An installed app never takes a build older than the one it has, so putting an older manifest back does not take any phone back. To undo a bad release, publish a fixed one. A release that cannot boot undoes itself.

## The other ways out

- **ghostmarkdown.com** is `landing/`, published by `scripts/deploy-landing.mjs`. Its downloads and versions are the release's own files, so a release updates it with nothing to do there, and share links open the reader page the last release published.
- **attack.fm/glyph/install.html** (`public/install.html`) reads `apk.json` and `desktop.json` beside it. It is static on purpose: it is the way back when the app's own bundle is broken.
- **The Play build** is `GLYPH_STORE=play` at compile time (`src-tauri/gen/android/app/build.gradle.kts`, and `STORE` in `ota.rs`). It never looks for, fetches or offers an APK; its web bundle still updates over the air. `docs/store/PLAY_STORE.md` is the plan, and `docs/store/APP_STORE.md` says why the iPhone app is not ready.
- **The staging app** is `GLYPH_STAGING=1`: the same code as `com.mattssoftware.glyph.staging`, beside the real app with its own data and no update checks, for walking through a build as a new person sees it.

## Read next

- [[Tests, and the report that ships]]
- [[The native half]]
- [[Working on Ghost.md]]
