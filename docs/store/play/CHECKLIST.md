# Play Console, step by step

The order the Console asks for things, and which file in this folder to paste or upload at each step. The words are
in the Markdown files beside this one, in the repo. The pictures are not in the repo: they are in
`/private/tmp/claude-501/-Users-matt-Development-Apps-glyph/d8404dd2-3ec4-4534-82c0-8df83377f14d/scratchpad/store/play/`,
under the same names this file uses. Copy that folder somewhere safe before the scratchpad is cleared.

What is already done in the code is in docs/store/PLAY_STORE.md: the Play build, delete account, the privacy and
delete-account pages, targetSdk 36, 16 KB pages.

## Before the Console

- [ ] **Decide** personal or organisation account, and what to tell APK users (FORM_ANSWERS.md, last section).
- [ ] **Make the upload key** and enrol in Play App Signing (PLAY_STORE.md step 2). Back up the keystore.
- [ ] **Build the bundle**: `GLYPH_STORE=play npm run android:build -- --aab --target aarch64`, signed with that key.
      Confirm the build is the one the copy describes: with Meeting in the + sheet, or edit LISTING.md and
      RELEASE_NOTES.md as they say.
- [ ] **Check the pack has no secrets**: `grep -ril "token\|password\|sshpass" docs/store/play/` should find only the
      words in FORM_ANSWERS.md's table headings. The seed library in the pictures is invented.

## 1. Create app

Play Console › All apps › Create app. Answers: FORM_ANSWERS.md › Create app.

## 2. Dashboard › Set up your app

Each row opens a form. In the order the Console lists them:

- [ ] **Set privacy policy**: `https://ghostmarkdown.com/privacy.html`
- [ ] **App access**: FORM_ANSWERS.md › App access (choose the first option; paste the note into the instructions box).
- [ ] **Ads**: No.
- [ ] **Content rating**: start the questionnaire, email infamousvaguerat@gmail.com, category and answers in
      FORM_ANSWERS.md › Content ratings.
- [ ] **Target audience**: FORM_ANSWERS.md › Target audience and content.
- [ ] **News apps**: No.
- [ ] **COVID-19 apps**: No.
- [ ] **Data safety**: FORM_ANSWERS.md › Data safety, row by row.
- [ ] **Government apps**: No.
- [ ] **Financial features**: none.
- [ ] **Health**: none.
- [ ] **Advertising ID**: No.
- [ ] **Foreground service permissions** (appears after a 1.9.0 bundle is uploaded): FORM_ANSWERS.md › Foreground
      service permissions, one entry per type, with the video link Matt records.

## 3. Store settings

Grow › Store presence › Store settings. FORM_ANSWERS.md › Store settings: category Productivity, tags, contact email,
website.

## 4. Main store listing

Grow › Store presence › Main store listing.

| Field | Paste or upload |
|---|---|
| App name | LISTING.md › App name |
| Short description | LISTING.md › Short description |
| Full description | LISTING.md › Full description |
| App icon (512 × 512 PNG) | `app-icon-512.png` |
| Feature graphic (1024 × 500) | `feature-graphic-1024x500.jpg` |
| Phone screenshots (2 to 8) | `phone-screenshots/01-home.png` to `08-a-meeting-written-up.png`, in that order. 1242 × 2208, 9:16. The two `spare-*.png` files are extras to swap in, not to add: Play takes eight. |
| 7-inch tablet screenshots | `tablet-7in-screenshots/01-home.png` to `04-plugins.png`. 2184 × 1968, the Fold opened out. |
| 10-inch tablet screenshots | `tablet-10in-screenshots/01-home.png` to `04-the-academy.png`. 2560 × 1600. |
| Video | None. |

Every screenshot is a 24-bit PNG with no alpha channel, which Play requires; the feature graphic is a JPEG for the
same reason. Save, then check the preview on the right of the page reads as the phone does.

## 5. Testing, then production

- [ ] **Closed testing** (a personal account must: 12 testers, 14 days): Test and release › Testing › Closed testing ›
      Create track › Create release. Upload the bundle, paste RELEASE_NOTES.md into the release notes box, choose
      countries, review, roll out. Add the testers' emails as a list. Wait the 14 days, then apply for production
      access from the dashboard.
- [ ] **Production**: Test and release › Production › Create new release. The same bundle, the same notes.
- [ ] **Pre-launch report**: read it under Test and release › Pre-launch report once the bundle has been processed;
      it runs the app on test devices and lists crashes and accessibility notes.
- [ ] **Send for review**: Publishing overview › Send changes for review. A first review takes days rather than
      hours; the assistant role and the AI features are the two things a reviewer is most likely to ask about, and
      the App access note answers both.

## 6. After the first release

- [ ] Point ghostmarkdown.com's Android button at the Play listing, or keep the APK beside it (Matt's decision 2).
- [ ] Each later release: a new bundle with a higher version code, RELEASE_NOTES.md gains a section, and the store
      listing only changes when the app does.

## The pack, file by file

| File | What it is |
|---|---|
| CHECKLIST.md | This page |
| LISTING.md | Title, short and full description, captions |
| RELEASE_NOTES.md | The What's new box |
| FORM_ANSWERS.md | Every Console question with its answer |
| FEATURES.md | The map of the app's features the copy was written from, and which six lead |
| app-icon-512.png | The app icon, 512 × 512 |
| feature-graphic-1024x500.jpg | The feature graphic |
| phone-screenshots/ | Eight phone screenshots and two spares |
| tablet-7in-screenshots/ | Four, at the Fold's inner screen size |
| tablet-10in-screenshots/ | Four, at 2560 × 1600 |
| FORMS.md, REQUIREMENTS.md, SCREENSHOTS.md | A parallel run of the same task wrote these (commit 5adab6d). They overlap FORM_ANSWERS.md and FEATURES.md; where two answers differ, the Console's own help page and the privacy policy decide. |

The pictures were taken over the web build (`npx vite build` of the `store/play-assets` worktree) in headless
Chromium at the phone's pixel density, over an invented library. The review scene is the app's own bench script
(`?scene=heat`), which plays the review as it runs on a phone.
