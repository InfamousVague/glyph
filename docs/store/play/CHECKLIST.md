# Play Console, step by step

The order the Play Console asks for things, and which file in this folder (and which picture in the pack) each step
takes. The pictures live outside the repo, in the pack folder this was delivered with; the markdown is here. Tick
the boxes as you go.

Before the Console: the three things only Matt can do are in docs/store/PLAY_STORE.md: the developer account
(personal or organisation), the upload key, and what to tell the people who installed the APK.

## 1. The account and the app

- [ ] Sign in to the Play Console with the developer account. A personal account made after 13 November 2023 will
      have to run the closed test in step 8 before production.
- [ ] Create app: name `Ghost.md`, default language **English (United Kingdom)**, App, Free. Accept the developer
      programme policies and the US export laws declaration.

## 2. Set up your app (the dashboard's list, in its order)

- [ ] **Privacy policy:** `https://ghostmarkdown.com/privacy.html` (FORMS.md › Privacy policy).
- [ ] **App access:** "All or some functionality is restricted", the instruction set from FORMS.md › App access,
      and a test account made for the purpose. Do not type a real password anywhere but the Console.
- [ ] **Ads:** No (FORMS.md › Ads).
- [ ] **Content rating:** the questionnaire, answers in FORMS.md › Content rating. Expect "rated for everyone".
- [ ] **Target audience and content:** 13 and over, not appealing to children (FORMS.md › Target audience).
- [ ] **News apps:** No.
- [ ] **COVID-19 contact tracing and status apps:** No.
- [ ] **Data safety:** the tables in FORMS.md › Data safety. Two types collected, nothing shared, encrypted in
      transit, deletion offered, the account deletion URL `https://ghostmarkdown.com/delete-account.html`.
- [ ] **Government apps:** No.
- [ ] **Financial features:** none.
- [ ] **Health:** none.
- [ ] **Advertising ID:** No.
- [ ] **Foreground service permissions:** only if the uploaded bundle is 1.9.0 with the meeting service. Then
      FORMS.md › Foreground service permissions, with a video link.

## 3. Store settings

- [ ] App category Productivity, tags, contact email `infamousvaguerat@gmail.com`, website
      `https://ghostmarkdown.com`, external marketing off (FORMS.md › Store settings).

## 4. Main store listing

- [ ] App name: LISTING.md › App name.
- [ ] Short description: LISTING.md › Short description (80 characters).
- [ ] Full description: LISTING.md › Full description. Leave the MEETINGS block out unless the upload is 1.9.0.
- [ ] App icon: upload `app-icon.png` (512 × 512).
- [ ] Feature graphic: upload `feature-graphic.png` (1,024 × 500).
- [ ] Phone screenshots: upload `phone-screenshot-01.png` to `phone-screenshot-08.png`, in that order. The first
      two are what search results show.
- [ ] 7-inch tablet screenshots: upload `tablet-7-inch-screenshot-01.png` to `-03.png`.
- [ ] 10-inch tablet screenshots: upload `tablet-10-inch-screenshot-01.png` to `-03.png`.
- [ ] Video: none.
- [ ] Save. The Console shows a preview; check the short description does not wrap awkwardly under the name.

## 5. App signing and the bundle

- [ ] Make the upload key (PLAY_STORE.md step 2), point `GLYPH_ANDROID_SIGNING` at its signing file, and back
      the keystore up.
- [ ] Build: `GLYPH_STORE=play npm run android:build -- --aab --target aarch64`. The bundle is at
      `src-tauri/gen/android/app/build/outputs/bundle/universalRelease/app-universal-release.aab`.
- [ ] On the first upload, choose Play App Signing with a Google-generated app signing key. The upload key's
      certificate is registered from that first bundle.

## 6. Closed testing release

- [ ] Testing › Closed testing › Create track (or use the default "Alpha"), then Create release.
- [ ] Upload the bundle. Release name: the version, e.g. `1.9.0 (1)`.
- [ ] Release notes: LISTING.md › Release notes, in en-GB.
- [ ] Testers: a list of email addresses, or a Google Group. For a personal account, at least 12 people, opted in
      for 14 days without a break. Share the opt-in link the Console gives.
- [ ] Review the release and roll it out to the track. The first review can take a few days.

## 7. While the test runs

- [ ] Answer the reviewers if they write. The review notes in FORMS.md say what the assistant role and the
      over-the-air bundle are for.
- [ ] Read the pre-launch report the Console makes from the bundle (crashes, accessibility, screenshots from its
      own devices).
- [ ] Decide what to tell the APK installs (PLAY_STORE.md › Decisions).

## 8. Production

- [ ] Personal account: after 14 days with 12 testers, Dashboard › Apply for production access, and answer the
      three-part form (about the test, the app, and readiness). An organisation account skips this.
- [ ] Production › Create release: promote the tested bundle, or upload the same one. Release notes again.
- [ ] Countries: all, or the list wanted.
- [ ] Roll out. Production review runs again.

## 9. After the listing is live

- [ ] Open the listing on a phone and check the screenshots and the description read as intended.
- [ ] Update docs/store/PLAY_STORE.md: the date it went live, the version, and the answers given where they
      differed from this pack.
- [ ] For every later release: bump `package.json` and `src-tauri/tauri.conf.json`, build with `GLYPH_STORE=play`,
      write 500 characters of release notes, and redo the content rating only if the app gains a way for people to
      write to each other.

## The words check

Before pasting, this folder was read for the banned list: em and en dashes, exclamation marks, emoji, "seamless",
"effortless", "elevate", "unlock", "unleash", "supercharge", "game-changer", "powerful", "intuitive", "robust",
"cutting-edge", "next-level", "leverage", "empower", "streamline", "revolutionise", "journey", "dive in", "look no
further", "whether you're", "Imagine", "In today's", "With Ghost.md,", "Download now", "best", "ultimate". The grep:

```
grep -rnE "—|–|!|seamless|effortless|elevat|unlock|unleash|supercharge|game-chang|powerful|intuitive|robust|cutting-edge|next-level|leverag|empower|streamlin|revolutioni|journey|dive in|look no further|whether you|Imagine|In today|With Ghost\.md,|Download now|\bbest\b|ultimate" docs/store/play/
```

It should print nothing but this list's own lines.
