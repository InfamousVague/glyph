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
   - review notes: accounts are optional, and Claude connects through MCP.
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
