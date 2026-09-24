# Ghost.md on the App Store

The plan for listing the iPhone and iPad app, as of 2026-09-24. **The iOS app isn't ready to submit.** Voice notes don't
work on iOS yet, and a notes app whose main feature fails on every launch would be rejected (guidelines 2.1 and 4.2).
Everything else Apple asks for is fixed or listed below (DESIGN §113).

## Already done

- **Delete account** in the app (guideline 5.1.1(v)), and the server endpoint behind it. The same work as Play's.
- **Privacy policy** at `landing/privacy.html`, linked from Settings › About.
- **Privacy manifest:** `src-tauri/gen/apple/glyph_iOS/PrivacyInfo.xcprivacy`.
  - No tracking.
  - Collected, only with an account: User ID, User Content, Photos, Audio, linked to the user, for app function.
  - Required-reason APIs: FileTimestamp C617.1, DiskSpace E174.1, SystemBootTime 35F9.1, UserDefaults CA92.1.
- **The icon set has no alpha channel.** App Store Connect rejects an icon with one.
- **Info.plist** (`src-tauri/Info.ios.plist`):
  - the name under the icon is Ghost.md;
  - the microphone string is accurate;
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
   - `ExportOptions.plist` needs `method = app-store-connect`.
   - `project.yml` hardcodes version 0.1.0. Make the archive carry 1.7.x.
   - Check that the built plist keeps both URL schemes: the deep-link plugin replaces `CFBundleURLTypes`.
4. **App Store Connect: create the app** (`com.mattssoftware.glyph`, category Productivity). Then fill in:
   - the privacy policy URL;
   - App Privacy answers, which must match the manifest;
   - age rating 4+;
   - export compliance: exempt;
   - screenshots for the 6.9" iPhone, and the 13" iPad while iPad is on (`TARGETED_DEVICE_FAMILY` 1,2). Or turn iPad off;
   - review notes: accounts are optional, and Claude connects through MCP.
5. **TestFlight, then submit.**

## Decisions for Matt

- **The contact address.** The same one as Play's.
- **Voice before launch, or notes-only first.**
- **iPad:** keep it, which means iPad screenshots and iPad review, or ship iPhone-only first.

## Rules that don't bite, and why

| Guideline | What it asks | Why it's fine |
|---|---|---|
| 4.8 | Sign in with Apple, if you offer social logins | Ghost.md accounts are its own; the plugins are connections, not ways to sign in |
| 2.5.2 | No downloaded code that changes the app | iOS has no over-the-air bundles (`ota_check` refuses there) |
| 3.1 | In-app purchase for paid features | Nothing is paid |
