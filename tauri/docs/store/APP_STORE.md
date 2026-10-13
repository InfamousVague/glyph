# Ghost.md on the App Store

**2026-10-02: the first version goes to review notes only and iPhone only** (Matt chose both that day). Voice still
does not work on iOS, so the iPhone app leaves out every way into a recording (`core/platform.ts` `recordsVoice`) and
does not look for the voice model, and its listing (docs/store/apple/listing.md) says nothing of voice. Build 1.10.0
was signed, uploaded and processed (VALID) and is attached to version 1.10.0 of the app record, Ghost Markdown
(6818598896), with the listing, seven screenshots, the category, the age rating, a free price and availability set
through the App Store Connect API. What follows the 2026-09-24 plan below is how that build was made.

## Already done

- **Delete account** in the app (guideline 5.1.1(v)), and the server endpoint behind it. The same work as Play's.
- **Privacy policy** at `landing/privacy.html`, linked from Settings › Account › Privacy.
- **Privacy manifest:** `src-tauri/gen/apple/glyph_iOS/PrivacyInfo.xcprivacy`.
  - No tracking.
  - Collected, only with an account: User ID, User Content, Photos, Audio, linked to the user, for app function.
  - Precise Location and Coarse Location, optional, for app function, linked to the user only with an account (DESIGN
    §134; the manifest and the App Privacy answers need this added when iOS can tag a note).
  - Required-reason APIs: FileTimestamp C617.1, DiskSpace E174.1, SystemBootTime 35F9.1, UserDefaults CA92.1.
- **The icon set has no alpha channel.** App Store Connect rejects an icon with one.
- **Info.plist** (`src-tauri/Info.ios.plist`):
  - the name under the icon is Ghost.md;
  - the microphone string is accurate;
  - `NSLocationWhenInUseUsageDescription`, in the microphone's voice, is still to add beside it when iOS tags notes
    (`Info.macos.plist` has the Mac's already);
  - `ghostmd://` links are claimed;
  - export compliance is `false`, with the reason: all encryption on iOS is Apple's own WebCrypto.
- **The iOS library compiles again** (`cargo check --target aarch64-apple-ios`). `libc` was missing there.
- **No other platform named** in what an iPhone shows (guideline 2.3.10): the guide's side-key page and the home
  screen's empty state.
- **Updates:** Settings says "Ghost.md updates through the App Store". It no longer runs checks that fail, shows APK
  lines, or shows attack.fm's release list.

## Steps

1. **Voice capture on iOS.** This is the blocker. whisper and llama aren't built for iOS; the plan is Apple's
   SpeechTranscriber (DESIGN §6.3, milestone 7). Until then:
   - tapping Speak fails;
   - "The voice model didn't download" shows at every launch;
   - formatting isn't available.

   The other way is to ship a notes-only first version with voice hidden on iOS. That's a decision for Matt.
2. **Adding pictures.** On iOS, adding a picture fails: the picker is Android's `GlyphHost`. It needs a web file input
   or a native picker. With the native picker comes `NSPhotoLibraryUsageDescription`.
3. **A real device build.** Only a simulator build has been made (2026-09-11).
   - Build with release signing (team F6ZAL7ANAD).
   - `src-tauri/gen/apple/ExportOptions.plist` needs `method = app-store-connect`.
   - `src-tauri/gen/apple/project.yml` hardcodes version 0.1.0. Make the archive carry the app's version (1.8.0
     today, `src-tauri/tauri.conf.json`).
   - Check that the built plist keeps both URL schemes: the deep-link plugin replaces `CFBundleURLTypes`. The
     generated `src-tauri/gen/apple/glyph_iOS/Info.plist` in the repository is an older snapshot and lists `glyph`
     alone; `src-tauri/Info.ios.plist` names both.
4. **App Store Connect: create the app** (`com.mattssoftware.glyph`, category Productivity). Then fill in:
   - the privacy policy URL, and infamousvaguerat@gmail.com as the contact;
   - App Privacy answers, which must match the manifest;
   - age rating 4+;
   - export compliance: exempt;
   - screenshots for the 6.9" iPhone, and the 13" iPad while iPad is on (`TARGETED_DEVICE_FAMILY` 1,2, XcodeGen's
     default, since `src-tauri/gen/apple/project.yml` does not set it). Or turn iPad off;
   - review notes: accounts are optional, and Claude connects through MCP;
   - sign-in information (App Review › Sign-In Information): the demo account below.

### The reviewers' demo account

A Ghost.md account for App Review, with the app's own examples in it (2026-10-02, Matt: "create a 'test' 'test' user
for apple reviewers to login with with some examples"). The password is `testapple`, since the app asks for at least
eight characters (core/account/account.ts `passwordProblem`).

| Field | Value |
| --- | --- |
| Handle (App Store Connect's "User name") | `test` |
| Password | `testapple` |

Matt makes it in the app himself, since the agents don't create accounts on the live service:

1. Settings › Account › Sign up, with the handle and password above. Keep the recovery codes with the password.
2. Settings › Examples: add the sample note, the example board, the example canvas and the "How Ghost.md works"
   canvas.
3. Wait for Account to say it has synced, then sign in on a second device or browser to check the examples arrive.

Paste into App Review › Notes:

> Accounts are optional: the app works fully without one, with notes kept on the device. To try sync, sign in under
> Settings › Account with the demo account (handle `test`, password `testapple`); it holds the app's example notes, a
> board and two canvases. Notes are encrypted on the device before they are sent, so the server cannot read them. The
> account can be deleted under Settings › Account › Delete account.

Anyone with the password can sign in and change what it holds, so check it before each submission, and put the
examples back from Settings › Examples if they have gone.
5. **TestFlight, then submit.**

## Decisions for Matt

- **Voice before launch, or notes-only first.**
- **iPad:** keep it, which means iPad screenshots and iPad review, or ship iPhone-only first.

## Rules that don't bite, and why

| Guideline | What it asks | Why it's fine |
|---|---|---|
| 4.8 | Sign in with Apple, if you offer social logins | Ghost.md accounts are its own; the plugins are connections, not ways to sign in |
| 2.5.2 | No downloaded code that changes the app | iOS has no over-the-air bundles (`ota_check` refuses there) |
| 3.1 | In-app purchase for paid features | Nothing is paid |

## Building and uploading, as done on 2026-10-02

Xcode 27.0 (Swift 6.4), Tauri CLI 2.11, from a worktree at main:

1. Signing is automatic with the team's App Store Connect key: `tauri ios build` hands it to `xcodebuild` as
   `-allowProvisioningUpdates` with the key when `APPLE_API_KEY`, `APPLE_API_ISSUER` and `APPLE_API_KEY_PATH` are set.
   Map them from the shared key file (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` in
   `~/.config/mattssoftware/signing/asc-api.env`). Xcode made the "iOS Team Store Provisioning Profile:
   com.mattssoftware.glyph" itself. `project.yml` says `CODE_SIGN_STYLE: Automatic` and `TARGETED_DEVICE_FAMILY: "1"`.
2. `node scripts/ios-clean.mjs && npx tauri ios build --export-method app-store-connect`.
3. Three things broke on the way, each fixed or worked around:
   - `zip` and `minijinja` were listed for every target but iOS, while `export.rs` and `llm/prompt.rs`, which are built
     on iOS, use them. They are shared dependencies now (src-tauri/Cargo.toml).
   - The Swift packages under swift-rs (Tauri's, the haptics and opener plugins'): Xcode 27's SwiftPM keeps the
     `@_cdecl` symbols local, and swift-rs 1.0.8 globalizes only a package's own. SwiftRs's three
     (`release_object`, `retain_object`, `string_from_bytes`) stayed local in every archive and the link failed. The
     workaround: `rustup component add llvm-tools` (swift-rs needs its llvm-objcopy), then in
     `target/aarch64-apple-ios/release/build/tauri-*/out/swift-rs/Tauri/` run llvm-objcopy
     `--globalize-symbol=_release_object --globalize-symbol=_retain_object --globalize-symbol=_string_from_bytes` on
     `release/libTauri.a`, then `xcrun ranlib` on it (the archive's index must list them, or the member is never
     loaded), then delete `deps/libtauri-*.rlib` and `.fingerprint/tauri-*` for that hash so the tauri crate compiles
     again and bundles the patched archive (a static library is bundled into the rlib). A first build can also record
     its search path before SwiftPM has written the archive; deleting that build script's `.fingerprint` entry runs it
     again. A lasting fix is a patched swift-rs (`[patch.crates-io]`) that globalizes SwiftRs's symbols in Tauri's
     archive and re-indexes it.
   - The export's `rsync -E` failed when Homebrew's rsync came first in PATH: run the export with `/usr/bin` first
     (`xcodebuild -exportArchive` with `method app-store-connect` and the same key flags).
4. The checks AttackFM's `testflight.command` makes, all passed: version and build 1.10.0, `UIDeviceFamily` [1],
   signed by Apple Distribution: Matt Wisniewski (F6ZAL7ANAD), every dist asset named in the binary (379 of 379),
   both URL schemes, the scene delegate, the camera and microphone strings, `ITSAppUsesNonExemptEncryption` false.
5. `xcrun altool --validate-app` then `--upload-app -t ios --apiKey ... --apiIssuer ...`.

The next version's build number must be higher than 1.10.0.

## The 2.x build (2026-10-13)

1.10.0 was accepted. The next version sent for review is the Flutter app at the repository's root, under the same
record and id, as an update over it: `docs/CUTOVER.md`, section 8, is the whole of it (what 1.10.0 keeps on an
iPhone, what the new app carries across and how that was proven in a simulator, and what a real iPhone has still
to show). What changes of this file's:

- **The build** is `tool/cutover-build-ios.sh <version>` at the root, not `tauri ios build`. It signs the same way
  (automatic, team F6ZAL7ANAD, the suite's App Store Connect key handed to `xcodebuild`, Xcode keeping "iOS Team
  Store Provisioning Profile: com.mattssoftware.glyph"), runs the export with `/usr/bin` first in `PATH`, makes the
  checks of step 4 above itself, and uploads nothing. None of the three breakages above apply: there is no
  swift-rs and no Tauri in it.
- **The version and the build**: 2.0.5, build 2000005 (one number, above "1.10.0" at its first; a second upload
  of the same version is `--build 2`, 2000005.2).
- **The privacy manifest** is `ios/Runner/PrivacyInfo.xcprivacy`: the same four collected types and the same four
  required-reason APIs as this app's, so the App Privacy answers stand.
- **The Info.plist** is `ios/Runner/Info.plist`: Ghost.md, the camera's sentence, **no microphone sentence** (the
  build opens none), `ghostmd://` and not `glyph://`, the scene manifest, no entitlements.
- **Export compliance is no longer "false: all encryption is Apple's".** The Flutter app seals notes with its own
  Rust (AES-256-GCM, PBKDF2, HKDF, ECDH P-256, Ed25519) and its HTTPS is the engine's BoringSSL. Apple's table puts
  "an industry standard algorithm, not provided within the Apple operating system" under a French encryption
  declaration where the app is sold in France. The key is `true` in the new plist until Matt chooses: answer and
  file, or move the iPhone's encryption onto Apple's frameworks and put `false` back (`docs/CUTOVER.md`, section
  8, "Export compliance").
- **Still true as written**: delete account, the privacy policy, "Ghost.md updates through the App Store", no
  downloaded code, nothing paid, no social sign-in, iPhone only, and the reviewers' demo account.
- **The iPhone's words** (2026-10-13, Matt: fix them before submitting): an iPhone is no longer shown "press the
  side key" (the How Ghost.md works canvas and the sample note are given in typed words), "on Android" (the
  Academy's video lesson), "Sync meeting recordings" or "the model you downloaded" (Settings › Account), the
  walkthrough's model page, or Ghost.md: The Guide in About. `docs/CUTOVER.md`, section 8, lists each and what was
  left. **The reviewers' demo account still holds the canvas made by the Tauri app, with the old card**: sign in
  as it, delete "How Ghost.md works", and add it again from Settings › About › Examples in the new build (or edit
  the first card's words on any device).
- **The listing** (`apple/listing.md`): the seven screenshots stay for now (Matt, 2026-10-13); What's New is
  written; the rest stands.

### Sent so far, and where it stopped (2026-10-13, UTC)

Matt's decisions that day: answer export compliance honestly and take France out of where the app is sold; no
real iPhone test; keep the seven screenshots; fix the iPhone's words; draft What's New and use it; submit as soon
as it is ready, released automatically after approval, to everyone at once; the plain look with the slight blur
behind the header.

Done in App Store Connect, through the API with the suite's key (`ghost-md-app-store-pack/tools/asc.mjs`):

- **France removed from availability** (14:06). Before: 175 territories, 174 available, China alone off. After:
  173 available, China and France off, nothing else changed. France was already marked `CANNOT_SELL` with
  `TRADER_STATUS_NOT_PROVIDED`: the EU trader status has never been given for this account.
- **Version 2.0.5 created** for iOS (14:07), id `5ae0a271-d667-4d63-b228-b3ad1b06cd61`, `PREPARE_FOR_SUBMISSION`,
  release type `AFTER_APPROVAL`, no phased release. The one localization is en-US. Its description, keywords,
  support address, promotional text and the seven `APP_IPHONE_67` screenshots are 1.10.0's (the promotional text
  did not come across by itself and was set again, word for word).
- **What's New** (en-US): see `apple/listing.md`.
- **Review notes**: one sentence added, "Version 2.0.5 is a rebuild of the same app: updating from 1.10.0 keeps
  the person's notes and their sign-in." The contact is there. The demo account is in the notes' own text
  (Username `test`), not in the Sign-In Information fields, which are empty with "required" off: that is how
  1.10.0 was reviewed and accepted, and it was left so. Nobody signed in as it to check it today.

**Not done: no build is uploaded, none is attached, and nothing is submitted.** The build made that day
(`build/ios-store/Ghost.md-2.0.5-2000005.ipa`, from 27db0a5f, the plain look) was refused by
`xcrun altool --validate-app` (14:05):

> Invalid Export Compliance Code. The export compliance key value [] in the app's Info.plist doesn't match the
> key value of the app's export compliance documentation. (90592)

`ITSAppUsesNonExemptEncryption` `true` tells Apple the build needs export documentation, and Apple then wants
the code it gives once that documentation is reviewed (`ITSEncryptionExportComplianceCode`). There is no such
documentation to give for this app with France off. Asked to make the declaration with the honest answers
(proprietary cryptography: no; standard algorithms instead of, or in addition to, Apple's: yes; on the French
store: no), the API answers:

> Cannot create appEncryptionDeclarations unless either containsProprietaryCryptography is True or
> containsThirdPartyCryptography and availableOnFrenchStore are both True

So by Apple's own rule an app with standard algorithms of its own, not sold in France, files nothing and gets no
code, and its Info.plist is meant to say so: Apple's page says of an app that needs no documentation, "update
your app's information property list (Info.plist) file in Xcode to let us know that your app doesn't use
encryption or is exempt from providing documentation", which is the key at `false` (or left out, and the same
answer given for the build in App Store Connect). Matt's decision was that the key stays `true`, and what the key
says is his to say, so nothing was changed and nothing was uploaded. The ways on, each a word from Matt:

**Matt chose the first (2026-10-13): the key is `false`.** The reason is beside it in ios/Runner/Info.plist.
Apple says an exempt app "might" owe a yearly self-classification report to the U.S. government, which is his to
check. Putting France back means revisiting this: the French declaration, the code, `true`, and the EU trader
status.

1. The key `false` (ios/Runner/Info.plist), with the reason beside it: standard algorithms only, none
   proprietary, not sold in France, so exempt from documentation by Apple's table. Then build, upload, attach,
   submit. Whether a yearly self-classification report to the U.S. government is owed is his to look into
   (Apple's page says an app with exempt encryption "might" owe one).
2. The key left out, and the build's question answered in App Store Connect by Matt himself.
3. Keep `true`, put France back and file the French declaration, and use the code Apple gives.


### Sent for review (2026-10-13, UTC)

- **Built again** from b656aca3 at 14:16 with the key at `false`: the same IPA facts (2.0.5, 2000005, iPhone only,
  the privacy manifest, Apple Distribution, the plain look), `ITSAppUsesNonExemptEncryption` false and no
  `ITSEncryptionExportComplianceCode`.
- **Validated** (14:19, "VERIFY SUCCEEDED with no errors") and **uploaded** (14:21, "UPLOAD SUCCEEDED with no
  errors", delivery c178c4e6-fbcd-4eb2-8d01-4a6ec6fbda79) with `xcrun altool`, `API_PRIVATE_KEYS_DIR` naming the
  folder of the suite's key.
- **Processed** by 14:23: build `c178c4e6-fbcd-4eb2-8d01-4a6ec6fbda79`, `VALID`, `usesNonExemptEncryption` false
  as the Info.plist says it, so App Store Connect asked nothing more of it.
- **Attached** to version 2.0.5 (`5ae0a271-d667-4d63-b228-b3ad1b06cd61`); What's New, `AFTER_APPROVAL` and no
  phased release read back as set.
- **Submitted** at 14:23:46 in a review submission of its own, `5345088b-60f0-498e-b522-244704ccb652`: the
  version reads `WAITING_FOR_REVIEW`. The custom product page's submission (97437960-…, waiting since 06:08)
  was not touched and did not stand in the way.
- **For Matt still**: the reviewers' demo account holds the old "How Ghost.md works" canvas ("press the side
  key"); nobody signed in to it. The yearly U.S. self-classification report, if one is owed.

### The screenshots replaced, and sent again (2026-10-13, UTC)

Matt: "Go ahead and update the screenshots and resubmit for approval". A version waiting for review cannot have
its screenshots changed, so it was taken out and sent again, **which puts it at the back of Apple's queue: its
place is counted from 14:58, not 14:23.**

- 14:54:07 the version's submission (5345088b-…) cancelled; by 14:54:20 it read `COMPLETE` and the version
  `DEVELOPER_REJECTED` (Apple's name for "taken back by the developer"), which can be edited.
- 14:54:38 to 14:55:01 the en-US `APP_IPHONE_67` set (4a951c1b-…): the seven new pictures uploaded and each read
  back `COMPLETE` at 1290 x 2796 with our checksum, the seven old ones deleted, the order set. A set holds ten at
  most, so it went three new, four old out, four new, three old out; the old files are still in the pack.
- The build (c178c4e6-…, 2000005), What's New, `AFTER_APPROVAL` and no phased release read back unchanged.
- 14:58:43 submitted again in a new submission, **a02dc6ed-4f02-43d5-b585-c687d01240d7**: the version reads
  `WAITING_FOR_REVIEW`. The custom product page's submission and its pictures, and the macOS version, were not
  touched.

What the seven are and how they are shot again: `apple/listing.md`.
