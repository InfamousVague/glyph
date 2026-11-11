# Ghost.md on Google Play: the Flutter app

The Play build of the Flutter app, first made at 2.4.25 on 2026-11-05. The Console's app (`com.mattssoftware.glyph`,
"Ghost.md: Notes in Markdown") was made on 2026-10-05 for the Tauri app (tauri/docs/store/play/, and
console-2026-10-05.md there for what it holds). This folder is the Flutter app's:

- `listing.md`: the name, short and full description, and 2.4.25's release notes; `check.mjs` counts and checks them.
- `forms.md`: the App content declarations, as changes from 2026-10-05: data safety, location, foreground services,
  target audience, content rating, app access.

## The build

```sh
tool/cutover-build.sh 2.4.28 --play        # build/play/ghost-md-2.4.28.aab
```

The cutover build (id `com.mattssoftware.glyph`, version code 2004025 from the version name) as an App Bundle, with
three things only the Play build has:

- **No updater.** `--dart-define=GHOST_STORE=play` (lib/core/updates.dart `playStoreBuild`): no update check,
  download, Install, tray badge or Check for updates; About says "Ghost.md updates through Google Play." The What's
  new card after an update stays (it reads the bundled changelog).
- **No REQUEST_INSTALL_PACKAGES and no installer FileProvider.** `GHOST_STORE=play` lays
  android/app/src/play/AndroidManifest.xml over the release manifest (android/app/build.gradle.kts `ghostPlay`).
- **No ACCESS_BACKGROUND_LOCATION** (the same manifest, 2026-11-05), so no background location declaration: place
  reminders ring only while the app is open (forms.md, "Location permissions"), and nothing asks for "Allow all the
  time".
- **Foreground services: the microphone only** (2026-11-11; 2.4.27 kept the write-up too, 2026-11-09, after Play rejected the update on
  2026-11-06 under "Permissions for Foreground Services"; forms.md has the declaration). The same manifest removes
  FOREGROUND_SERVICE_SPECIAL_USE, FOREGROUND_SERVICE_MEDIA_PROJECTION and FOREGROUND_SERVICE_MEDIA_PROCESSING, every
  special-use property, the long-jobs
  service (BackgroundJobService) and WorkManager's foreground types; MeetingService is `microphone`.
  The Kotlin reads what is declared (glyph/capture/ForegroundTypes.kt) and Dart hides "Include sound from other apps"
  (`playStoreBuild`). What a Play user loses: long jobs pause in the background (their notification says so), no
  other apps' sound in meetings, and the write-up after Stop is WorkManager's ordinary work, not a foreground service.
- **arm64 only**, as the core is: Flutter's Gradle plugin lists three ABIs, and DataStore ships a .so for the other
  two, which would have Play offer the app to phones it cannot run on.
- **Signed with the upload key**, `~/.config/glyph/play-signing.properties` (keystore `play-upload.keystore`, alias
  `upload`), registered with Play App Signing on 2026-10-05. Not the sideload key: its certificate reads
  `CN=Android Debug`, which Play refuses as a debug build.

No watch app (`GHOST_WEAR=0`): that would be a Wear OS release of its own. The sideload APK (no `--play`) is exactly
as it was: the same command, manifest, ABIs and key.

The core is not rebuilt by the script: check `libghost_core.so` is newer than `git log -1 -- native/src
tauri/src-tauri/src` first (2.4.25's: the .so 2026-10-31 19:50, the last core change 18:27 that day).

## 2.4.28 as built (2026-11-11: the microphone only)

| Check | Result |
|---|---|
| File | build/play/ghost-md-2.4.28.aab, 89,161,356 bytes, SHA-256 `9c89ace4856330f98cce54ff89cffd3e8327b2530fdb333a08eaec57163b0501` |
| Package, version | com.mattssoftware.glyph, versionCode 2004028, versionName 2.4.28 |
| Foreground service permissions | FOREGROUND_SERVICE, FOREGROUND_SERVICE_MICROPHONE only (`strings` of base/manifest/AndroidManifest.xml and the merged release manifest) |
| Services | MeetingService `microphone`; no REQUEST_INSTALL_PACKAGES, ACCESS_BACKGROUND_LOCATION, special use or BackgroundJobService |
| Tests | ForegroundTypesTest (JVM, 6/6), test/settings/play_fgs_test.dart (7/7) |

## 2.4.27 as built (2026-11-09: microphone and media processing only) — never sent

| Check | Result |
|---|---|
| File | build/play/ghost-md-2.4.27.aab, 89,150,842 bytes, SHA-256 `0c988d066e9f96fa3fcde5b6f154297c30ee4b2b1f32f29cd5c594a6509073d5` |
| Package, version | com.mattssoftware.glyph, versionCode 2004027, versionName 2.4.27 (2.4.26 was the newest in the changelog; 2.4.25 the bundle Play rejected) |
| Signature | the upload key, certificate SHA-256 `0D:C9:…:B3:76` as below |
| Foreground service permissions | FOREGROUND_SERVICE, FOREGROUND_SERVICE_MICROPHONE, FOREGROUND_SERVICE_MEDIA_PROCESSING only (`bundletool dump manifest`) |
| Services | MeetingService `0x2080` (microphone 0x80 + mediaProcessing 0x2000); SystemForegroundService no type; BackgroundJobService absent; no PROPERTY_SPECIAL_USE_FGS_SUBTYPE |
| Sideload APK | the same version's merged manifest is identical to 2.4.26's but for versionCode/versionName (`diff` of build/app/intermediates/merged_manifests/release/…, before and after) |
| Emulator (API 36, ghostflutter2) | a meeting: `dumpsys activity services` types=0x80 while recording (screen off, app left), 0x2000 from Stop until written up, then none. A model download, app sent home: no service at all, its notification "Pauses while Ghost.md is in the background", and Android cut its network once the app was cached (it failed with Retry on return). |
| Declaration video | fgs-2026-11/meeting-mic-and-writeup.mp4, 82 s, 720 px: + › Meeting, the recording notification, Home, screen off and on, back, Done, "Listening to the recording" › "Summarizing" › "Written up" (that stretch at 4x), the note. Make-up meeting: macOS `say` speech fed to the emulator's microphone through its gRPC injectAudio, host microphone off. |

## 2.4.25 as built (2026-11-05, rebuilt the same evening without background location)

| Check | Result |
|---|---|
| File | build/play/ghost-md-2.4.25.aab, 89,040,255 bytes, SHA-256 `a52082d48c46889ae029ad5c73dd3860d2a09089b9c14d3e40b6ab5f76d6a155` |
| Package, version | com.mattssoftware.glyph, versionCode 2004025, versionName 2.4.25 |
| SDK | minSdk 24, targetSdk 36 (Play's floor for new apps and updates is 35) |
| Signature | `jarsigner -verify`: verified. CN=Matt Wisniewski, O=MattsSoftware, C=US, RSA 4096, SHA384withRSA |
| Upload certificate SHA-256 | `0D:C9:03:90:69:0B:2C:C2:1A:96:C2:1F:28:3D:24:27:1A:67:3E:C0:6D:33:35:1D:FA:AA:C9:AA:26:C1:B3:76` |
| Upload certificate SHA-1 | `96:A0:BF:AF:E5:4D:E5:A0:EB:A9:1F:0C:AD:E4:EB:2E:24:0D:9C:C2` |
| REQUEST_INSTALL_PACKAGES, ACCESS_BACKGROUND_LOCATION, updates provider, AD_ID | absent from the bundle's manifest (`bundletool dump manifest`) |
| Special use subtype | BackgroundJobService's reads "Long jobs the person starts in the app and can stop from the notification at any time: …" |
| Native libraries | arm64-v8a only: libapp, libflutter, libghost_core, libdatastore_shared_counter |
| 16 KB pages | `bundletool build-apks` then `zipalign -c -P 16` on all 249 splits: verification successful; every .so stored uncompressed; ELF LOAD alignment 0x4000 (core, DataStore) and 0x10000 (Flutter) |
| Usage stats | on (the PostHog key from tool/posthog-defines.sh) |

bundletool is not installed; it runs from Gradle's cache (`com.android.tools.build:bundletool:1.18.3` and its
dependencies on the class path, `--aapt2` from build-tools 36).

## Screenshots

Play wants: phone screenshots, 2 to 8 (each side 320 to 3,840 px, the long side at most twice the short; 1080 px or
more to be featured); 7-inch and 10-inch tablet screenshots, up to 8 each (optional, but needed to be featured on
tablets, and the Fold opened is a tablet); the feature graphic, 1024 x 500; the icon, 512 x 512.

What exists:

| Where | What | State |
|---|---|---|
| ~/Development/Apps/ghost-md-play-pack/graphics/feature-1024x500.png | the dotwork ghost, "Ghost.md, Notes you say or type." | **Fine.** No UI in it. |
| ghost-md-play-pack/graphics/icon-512.png | the icon | Fine, if the launcher icon has not changed since September. |
| ghost-md-play-pack/screenshots/phone, phone-light (1080 x 1920, 8 each) | Speak, Hey Ghost, the review, a meeting, the marks, a query, a ticket, home | **Stale.** The Tauri app's look (Sept/Oct 1); the Flutter app's home, dock and recorder differ. |
| ghost-md-play-pack/screenshots/tablet, tablet-16x9 (1812 x 2176, 2560 x 1440) | home, query, tape, canvas, ticket | **Stale**, the same way. |
| What the Console holds (2026-10-05) | 7 phone shots, the App Store's padded to 1080 x 1920 | The Flutter app at 2.0.5, closer but a month old. |
| ~/Development/Apps/ghost-md-app-store-pack/screenshots/2026-10-19-flutter-neutral-v2/ | iphone-6.9 (1320 x 2868) and iphone-duo (2007 x 2853), 10 each, brand-neutral | The Flutter app at 2.2.1. The iPhone set is too tall for Play (2.17:1) and needs padding or a crop to 2:1. It shows no microphone, which the Android app has. |

New shots of the Flutter app on Android (recorder, AI chat with a picture, To-dos, Wrapped, a board, home with
widgets, and the Fold opened for tablets) need the phone or an emulator, a brand-neutral build
(`GHOST_STORE_NEUTRAL=true`, debug, never main) and the colour rule in tauri/docs/store/apple/listing.md. Not made
on 2026-11-05.

## For Matt

1. Upload `build/play/ghost-md-2.4.28.aab` (2.4.25 was rejected for its foreground services; 2.4.27 was never sent). Closed testing "Alpha" has 1014000 (1.14.0, the Tauri app).
2. **People who sideloaded the APK cannot move to Play by updating.** Play signs with Google's key, the APK with
   ours, and both are `com.mattssoftware.glyph`: Android refuses either over the other. They uninstall first, which
   deletes notes only on that phone, so they sign in and sync (or export) before. The Play copy also never gets the
   OTA, and the sideload copy never Play's updates.
3. The privacy page is brought up to date in landing/privacy.html (5 November 2026); deploy the landing site before
   review.
4. No background location declaration any more (forms.md). Foreground services from 2.4.28: the microphone only,
   the one video (forms.md, "What to paste, per type"); no special use, no clip of a long job.
5. Before review: check the demo account `test` still signs in with its examples; consider a Report row for AI output
   (forms.md).
6. Screenshots of the Flutter app on Android.
7. A personal account's 12 testers for 14 days before production, if not done.
