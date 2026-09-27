# Play Console, step by step

The order the Console walks a new app, and at each step which file to paste or upload. **You** marks what only you
can do. **Done** marks what is prepared and waiting in this folder.

The words are in the Markdown files beside this one, in the repo under `docs/store/play/` on the `store/play-assets`
branch: the listing copy in `copy/`, the form answers in `forms.md`. The pictures are not in the repo. They are in
the pack folder,
`/private/tmp/claude-501/-Users-matt-Development-Apps-glyph/d8404dd2-3ec4-4534-82c0-8df83377f14d/scratchpad/store/play/`,
under the names this file uses. Copy that folder somewhere that lasts before the scratchpad is cleared.

What the code already has is in `docs/store/PLAY_STORE.md`: the Play build (`GLYPH_STORE=play`), Delete account in
the app and on the web, the privacy and account-deletion pages, targetSdk 36 and 16 KB pages. Those are done.

## Before the Console

1. **You: decide the two things only you can** (PLAY_STORE.md, "Decisions for Matt").
   - Personal or organisation developer account. A personal account made after 13 November 2023 must run a closed
     test with 12 testers opted in for 14 days before it can apply for production. An organisation account is not
     held to it.
   - What to tell the people who installed the APK. The Play copy is signed with a different key, so it cannot update
     over the sideloaded app, and uninstalling that app deletes the notes that are only on the phone. Ask them to sign
     in and sync first, or keep the APK beside Play (the build without `GLYPH_STORE`).

2. **Done: the pack holds no secrets.** No password, key or token is in any file here, and the library in the
   pictures is invented (Sam, Ana and Ali are names and nothing more). To check again after an edit:
   `grep -ril "password=\|token=\|BEGIN PRIVATE" docs/store/play/` finds nothing but the placeholder lines in
   this file.

## 1. Create app

**You.** Play Console › All apps › Create app. The answers are in `forms.md` › Create app: Ghost.md, English (United
Kingdom), App, Free, both declarations ticked, Play App Signing accepted.

## 2. Set up your app › Let us know about the content of your app

**Done: every answer is in `forms.md`.** The dashboard lists the forms in this order, and each row opens one. The
Console lets you fill them in any order, but nothing can be released until all are done.

| Form | Where the answer is |
|---|---|
| Privacy policy | `forms.md` › Privacy policy: `https://ghostmarkdown.com/privacy.html` |
| App access | `forms.md` › App access: all functionality available without special access, and the paragraph to keep for a reviewer's question |
| Ads | No |
| Content ratings | `forms.md` › Content ratings: the email, the category, the answers row by row |
| Target audience and content | `forms.md` › Target audience: 13 and over, no appeal to children |
| News apps | No |
| COVID-19 contact tracing and status apps | No |
| Data safety | `forms.md` › Data safety: the opening questions, account deletion with its URL, the data types table, the Claude connection entry, and the one open item (the access logs) |
| Government apps | No |
| Financial features | None |
| Health | None |

Then, further down the same App content page:

| Form | Where the answer is |
|---|---|
| Advertising ID | No (`forms.md` › Advertising ID) |
| Photo and video permissions | Not asked |
| Foreground service permissions | Appears only after a 1.9.0 bundle is uploaded. `forms.md` › Foreground service permissions has the three descriptions, what happens when the system stops each, and the use case to pick. **You** record the video it asks for. |

**You: the open item.** The Data safety form's IP-address question waits on the box's Caddy config, which cannot be
read today. `forms.md` says what to look for and what to enter either way. Everything else in the form can be filled
now and the one row added later; the form can be edited after publishing.

## 3. Set up your app › Select an app category and provide contact details

**Done.** Store presence › Store settings. `forms.md` › Select an app category: App, Productivity, the tags,
infamousvaguerat@gmail.com, https://ghostmarkdown.com, no phone.

## 4. Set up your app › Set up your store listing

Store presence › Main store listing. **Done: every field has a file.** Paste each fenced block without its heading.

| Field | Paste or upload |
|---|---|
| App name | `copy/listing.md` › App name: `Ghost.md` |
| Short description | `copy/listing.md` › Short description (the first block; the second is a spare) |
| Full description | `copy/listing.md` › Full description. Read its two conditions first: the MEETINGS section is 1.9.0's, and the one emoji is the heat effect's own syntax. |
| App icon | `graphics/icon-512.png`, 512 × 512, 32-bit PNG with every pixel opaque, 594 KB: the app's own icon (`src-tauri/icons/icon.png`, re-encoded). Play draws its own rounded mask over it. `graphics/icon-512-preview.md` says where it came from. |
| Feature graphic | `graphics/feature-1024x500.png`, 1024 × 500, 24-bit PNG with no alpha: the listening ghost on ruled paper beside the wordmark and the line "Notes you say or type." `copy/feature-graphic.md` is the design and `graphics/feature-1024x500-preview.md` says how it was made. The two files in `graphics/spares/` (the waving ghost, and a dark version) are swaps, not uploads. |
| Phone screenshots | Eight, in this order, from `screenshots/phone/`: `01-speak.png`, `02-hey-ghost.png`, `03-tapes.png`, `04-the-review.png`, `05-a-meeting.png`, `06-the-marks.png`, `07-a-board.png`, `08-home.png`. 1080 × 1920 (9:16), 24-bit PNG with no alpha, each a real screen under its caption on the app's paper. `copy/screenshots.md` says what each shows and its caption. Play takes at most eight; the four in `screenshots/phone/spares/` (`09-the-tapes-shelf.png`, `10-a-canvas.png`, `11-things-to-say.png`, `12-a-spoken-note.png`) are swaps, not additions. |
| 7-inch tablet screenshots | From `screenshots/tablet/`: `01-home.png`, `02-a-tape.png`, `03-a-canvas.png`, `04-a-book.png`. 1812 × 2176, the Fold opened out with the sidebar docked. `screenshots/tablet/spares/` holds `05-a-board.png` and `06-a-meeting.png` as swaps. |
| 10-inch tablet screenshots | The same four files. Both tablet slots take 1812 × 2176 (the 7-inch slot takes sides of 320 to 3840 px, the 10-inch 1080 to 7680, each with the long side under twice the short), so upload the set twice. |
| Video | None. |

Save, then read the preview on the right of the page as a phone would show it: the first two or three screenshots
and the short description are what a search result shows.

**The screenshots, as they stand on 2026-09-27 at 18:23.** The names above are the ones `../shots/compose.mjs`
writes, from the raw screens `../shots/shoot.mjs` puts in `screenshots/raw/`. All eight phone pictures and the four
phone spares were in place, at 1080 × 1920 with no alpha; the tablet set was still being made. Check the folder before the day: `file screenshots/phone/*.png screenshots/tablet/*.png` should print
eight files at 1080 x 1920 and four at 1812 x 2176, all "8-bit/color RGB" and none "RGBA". If a picture is not
there, an earlier set of real screens at 1.8.0-20 is in `../old-pack/phone-screenshots/` (1242 × 2208, no alpha,
dark page, no caption; `01-home.png` to `08-a-meeting-written-up.png`, and two `spare-*.png`), with
`../old-pack/tablet-7in-screenshots/` (2184 × 1968) and `../old-pack/tablet-10in-screenshots/` (2560 × 1600). They
can go up as they are and be swapped later; the listing can be edited after publishing.

## 5. The upload key and the bundle

1. **You: make the upload key.** Every APK so far is signed with Android's debug certificate, which Play refuses.

   ```
   keytool -genkeypair -v -keystore ~/.config/glyph/play-upload.keystore -alias upload -keyalg RSA -keysize 4096 -validity 10000
   ```

   It asks for a keystore password, a key password and a name. Then write a second signing file, which
   `src-tauri/gen/android/app/build.gradle.kts` reads by these four keys:

   ```
   # ~/.config/glyph/play-signing.properties, chmod 600
   storeFile=/Users/matt/.config/glyph/play-upload.keystore
   storePassword=<the keystore password>
   keyAlias=upload
   keyPassword=<the key password>
   ```

   Back up the keystore and both passwords somewhere that is not this Mac. Lose them and no later release can be
   uploaded without asking Google to reset the upload key.

2. **You: build the bundle**, pointed at that file.

   ```
   GLYPH_ANDROID_SIGNING=$HOME/.config/glyph/play-signing.properties GLYPH_STORE=play npm run android:build -- --aab --target aarch64
   ```

   It lands at `src-tauri/gen/android/app/build/outputs/bundle/universalRelease/app-universal-release.aab`. Check
   its signer is the new key and not the debug one:

   ```
   keytool -printcert -jarfile src-tauri/gen/android/app/build/outputs/bundle/universalRelease/app-universal-release.aab | grep Owner
   ```

   Two things to know about versions. Play needs a higher version code on every upload, and Tauri makes the code from
   the version in `src-tauri/tauri.conf.json` (1.8.0 is 1008000, as `src-tauri/gen/android/app/tauri.properties`
   shows; 1.9.0 will be 1009000), so a new Play release is a version bump, not a `-N` build. And the copy describes
   1.9.0: if the bundle is 1.8.0, cut the MEETINGS section from `copy/listing.md`, the "Meetings record" sentence
   from `copy/whats-new.md`, and put `screenshots/phone/spares/09-the-tapes-shelf.png` in place of picture 5, as
   those files say.

## 6. Test and release › Testing, then Production

1. **You: choose countries.** Under the track, Countries/regions › Add countries/regions. All, or your choice.

2. **You: closed testing** (a personal account must; an organisation account may go straight to 3). Test and
   release › Testing › Closed testing › Create track (call it "Alpha" or whatever you like) › Create new release.
   - Upload `app-universal-release.aab`. On the first upload the Console enrols the app in Play App Signing; keep
     the recommended choice, a Google-generated app signing key, and the upload key stays yours.
   - Release notes: the block in `copy/whats-new.md`, into the en-GB box. **Done.**
   - Testers: a list of email addresses, or a Google Group. Twelve people who stay opted in for fourteen days, so
     ask for fifteen. Send them the opt-in link the track gives you.
   - Review the release and roll it out. Play's own review of the app starts here and can take days the first time.
   - After fourteen days: Dashboard › Apply for production access, three short sections about the test, the app and
     whether it is ready. Google says it answers within about seven days.

3. **You: production.** Test and release › Production › Create new release. The same bundle and the same notes. Roll
   out.

4. **Read the pre-launch report** once the bundle has been processed (Test and release › Pre-launch report): Play runs
   the app on its own devices and lists crashes, accessibility notes and what it saw.

5. **You: send for review.** Publishing overview › Send changes for review. Anything a reviewer asks about the
   assistant role or the AI is answered by the paragraph in `forms.md` › App access.

## 7. After the first release

- Point ghostmarkdown.com's Android button at the Play listing, or keep the APK beside it (decision 2).
- Each later release: bump the version in `src-tauri/tauri.conf.json`, build and upload a new bundle, and add a section
  to `copy/whats-new.md`. The listing and the forms change only when the app does; the Data safety form is the one
  to re-read at every release that touches sync, sharing or the plugins.

## The pack, file by file

| File | What it is |
|---|---|
| `CHECKLIST.md` | This page |
| `forms.md` | Every Console form with its answer, in the Console's order |
| `FEATURES.md` | The map of the app's features the copy was written from |
| `copy/listing.md` | App name, short description, full description |
| `copy/whats-new.md` | The release notes |
| `copy/screenshots.md` | What each screenshot shows, its file name and its caption |
| `copy/feature-graphic.md` | What the feature graphic shows and how it is laid out |
| `copy/check.mjs` | `node check.mjs` in that folder counts the blocks against Play's limits and reads them for the banned words |
| `graphics/icon-512.png` | The icon, 512 × 512 |
| `graphics/feature-1024x500.png` | The feature graphic, 1024 × 500 |
| `graphics/icon-512-preview.md`, `graphics/feature-1024x500-preview.md` | Where each graphic came from and how it was checked |
| `graphics/spares/` | Two other feature graphics, not for upload unless chosen instead |
| `screenshots/phone/01-speak.png` to `08-home.png` | The eight phone screenshots |
| `screenshots/phone/spares/` | Four phone pictures to swap in, not to add |
| `screenshots/tablet/01-home.png` to `04-a-book.png` | The four tablet screenshots, for both tablet slots |
| `screenshots/tablet/spares/` | Two tablet pictures to swap in, not to add |
| `screenshots/raw/` | The bare screens the pictures were made from, not for upload |

The Markdown lives in the repo on the `store/play-assets` branch; the pictures live only in the pack folder.

## The tablet screenshots, read against Play's rule, and the plain set

Added on 2026-09-27 at 18:30, after Play's preview assets page was read again. The tablet slots take 16:9 or 9:16
pictures only, with sides between 1080 and 7680 px, so the Fold's near-square set in `screenshots/tablet/` cannot
be uploaded as it is. Upload this instead, in both tablet slots:

| Field | Upload |
|---|---|
| 7-inch tablet screenshots | `screenshots/tablet-16x9/01-home.png`, `02-a-tape.png`, `03-a-canvas.png`, `04-a-book.png`: 2560 × 1440, 24-bit PNG with no alpha, the landscape screen with the sidebar docked under its caption. `screenshots/tablet-16x9/spares/` holds `05-a-board.png` and `06-a-meeting.png` as swaps. `screenshots/tablet-16x9-light/` is the same set in the light theme, should the phone set go up light. |
| 10-inch tablet screenshots | The same four files. |

Check before the day: `file screenshots/tablet-16x9/*.png` should print four files at 2560 x 1440, all "8-bit/color
RGB" and none "RGBA". `node ../shots/verify.mjs screenshots/tablet-16x9 screenshots/plain` reads every picture
against the limits and prints "All within the limits."

If Play's review turns a captioned picture down for the words above the screen, `screenshots/plain/` (dark) and
`screenshots/plain-light/` hold every picture with no caption and no frame, under the same names: `phone/` at
1080 × 1920 and `tablet/` at 2400 × 1350. Swap the one turned down for its plain twin and resubmit. The section "The
plain set" in `copy/screenshots.md` says why the captioned ones are within the rule as written.

Files this adds to the pack: `screenshots/tablet-16x9/` and `-light/` (the tablet pictures to upload), `screenshots/plain/`
and `plain-light/` (the uncaptioned twins), and in `screenshots/raw/` the `tablet-*` raws beside the `fold-*` ones.
