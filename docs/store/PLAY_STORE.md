# Ghost.md on Google Play

The plan for listing the Android app, as of 2026-09-24. The app is ready for Play once the steps below are done. The
code-side blockers found in the audit are fixed (DESIGN §113).

## Already done

- **Delete account**, in the app (Settings › Account › Delete account, with the password) and on the web
  (`landing/delete-account.html`, the URL Play asks for). The server deletes the account and everything it keeps:
  notes, recordings, pictures, settings, shared links, devices, recovery codes (`DELETE /glyph/api/v1/account`).
- **Privacy policy** at `landing/privacy.html`, linked from Settings › About › Privacy policy.
- **A Play build** (`GLYPH_STORE=play`): no APK self-update and no `REQUEST_INSTALL_PACKAGES` (Play forbids both). The
  web bundle still updates over the air. That is JavaScript in the WebView, which Play allows.
- **16 KB pages.** The C++ runtime is linked statically, so there is no `libc++_shared.so`, and `libglyph_lib.so` is
  linked at 16 KB. Checked on the built AAB: one `.so`, LOAD alignment 0x4000. Checked on the arm64 emulator: the app
  runs, and both whisper and llama pass their tests.
- **targetSdk 36** (Play's floor from 31 August 2026). The Android TV entries Tauri's template added are gone.

Build the upload:

```
GLYPH_STORE=play npm run android:build -- --aab --target aarch64
# src-tauri/gen/android/app/build/outputs/bundle/universalRelease/app-universal-release.aab
```

## Steps

1. **Decide the three things only you can** (below).
2. **Make an upload key.** Every APK so far is signed with Android's debug certificate (`CN=Android Debug`), and Play
   refuses uploads signed with it.
   - Make the key:

     ```
     keytool -genkeypair -v -keystore ~/.config/glyph/play-upload.keystore -alias upload -keyalg RSA -keysize 4096 -validity 10000
     ```

   - Write a second signing file for it, and point `GLYPH_ANDROID_SIGNING` at that file for Play builds.
   - Enrol in Play App Signing, with a Google-generated app key.
   - Back up the keystore and its password.
3. **Deploy what the app now calls:**
   - glyph-api, for the delete endpoint.
   - The landing pages (`node scripts/deploy-landing.mjs`).
   - Then an OTA, so installed apps get the Delete account button.
4. **Play Console: create the app** (Ghost.md, `com.mattssoftware.glyph`, free). Then fill in:
   - **Store listing:** short and full description, the 512 icon, a 1024×500 feature graphic, phone screenshots and
     tablet screenshots (use the Fold opened out).
   - **Privacy policy:** `https://ghostmarkdown.com/privacy.html`.
   - **Contact email:** infamousvaguerat@gmail.com, the same as the privacy page.
   - **Account deletion:** `https://ghostmarkdown.com/delete-account.html`.
   - **App access:** everything works without an account. Say so, or give reviewers a test account.
   - **Ads:** none.
   - **Content rating:** notes, no public feed. Shared links are unlisted and read-only.
   - **Target audience:** 13 and over.
   - **Data safety:** the answers below.
5. **Closed test, then production.** A personal developer account must run a closed test with 12 testers for 14 days
   before production. An organisation account can skip this.

## Data safety answers

| Data | Collected? | Why |
|---|---|---|
| User IDs (the handle) | Yes, optional (only with an account), not shared | Account management |
| Device or other IDs (a device's public key and kind, e.g. "Android") | Yes, optional, not shared | Account management |
| Notes, audio, photos | **No** | End-to-end encrypted, so we can't read them. Play counts that as not collected. |
| Anything else (location, contacts, analytics, crash logs) | No | |

Also answer:
- **Encrypted in transit:** yes.
- **Users can request deletion:** yes (the URL above).

If the box's Caddy access logs (IP address and time) are kept, also declare "IP address" as collected for security.
Find that out before answering.

## Decisions for Matt

- **Personal or organisation developer account.** A personal account means the 12-tester, 14-day closed test.
- **What happens to people who installed the APK.** The Play copy is signed with a different key, so it can't update
  over the sideloaded app. Uninstalling the old app deletes the notes that are only on that phone. Ask them to sign in
  and sync, or copy the notes out, first. Or keep offering the APK beside Play (the build without `GLYPH_STORE`).

## Worth tidying, not blockers

- `allowBackup` is Android's default (on), so Android's backup may include the app's files. The privacy page says so.
- Tauri's `file_paths.xml` shares the whole external storage root. Only the APK installer uses it, and the Play build
  never installs.
- The digital-assistant role and the voice interaction service can draw extra review. They exist for the side key.
  Describe that in the review notes.
