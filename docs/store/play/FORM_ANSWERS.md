# Form answers

Every question the Play Console asks that has one right answer for Ghost.md, in the Console's own order, with the
answer and where it comes from. Where the answer is Matt's to make, it says so. Written against the app at 1.8.0-20
and the 1.9.0 spec (docs/DESIGN.md §127), the privacy policy (landing/privacy.html), and Play's Data safety help
page, read on 2026-09-27.

## Create app

| Field | Answer |
|---|---|
| App name | Ghost.md (the listing's title is in LISTING.md) |
| Default language | English (United Kingdom), en-GB |
| App or game | App |
| Free or paid | Free. A free app cannot be made paid later. |
| Developer Program Policies | Confirm |
| US export laws | Confirm. The app uses standard encryption (AES-256-GCM through the platform's own crypto, TLS). Whether a separate export filing is wanted is Matt's to check; most apps using standard encryption for their own data need none. |

## Store settings

| Field | Answer |
|---|---|
| App category | Productivity |
| Tags | Notes, Productivity. Add Voice recorder if the list offers it. Play's tag list is fixed; pick the closest. |
| Contact email | infamousvaguerat@gmail.com (the address on the privacy page) |
| Contact phone | None |
| Website | https://ghostmarkdown.com |
| External marketing | Matt's choice. On by default; it lets Google advertise the app outside Play. |

## App content, in the Console's order

### Privacy policy

`https://ghostmarkdown.com/privacy.html`

### Ads

Contains ads: **No.** (No ad SDK, no advertising id: privacy.html, "What we don't do".)

### App access

**All functionality in my app is available without special access.**

An account is optional and can be made inside the app for free, so a reviewer needs nothing from us. Still, paste
this into the instructions box if the Console offers one, because two things draw a second look:

```
Ghost.md needs no account. Everything works signed out; an account only syncs notes between devices and can be created in Settings > Account.

Two things a reviewer may notice:

1. The app registers as a digital assistant (VoiceInteractionService). That is only so that holding the side key starts a voice note, from the lock screen too. It offers no other assistant functions and listens to nothing in the background; the microphone is open only while a recording is on screen.

2. The AI features (the review after a recording, Format, Summarize, Enhance) run on the device with a model the person downloads from Settings > Formatting > Model (2.7 GB for the default). Nothing is sent to a server. Without the model the app says "The AI needs a model on the phone." and everything else works.

Voice notes need the RECORD_AUDIO permission, asked for on the first recording.
```

### Content ratings (IARC questionnaire)

| Question | Answer |
|---|---|
| Category | Utility, Productivity, Communication or Other |
| Violence, sexual content, language, controlled substances, gambling, horror | No to each |
| Users interact or exchange content with other users | No. A person can send a read-only link to a note, but there is no messaging, no feed and no way for one user to reach another inside the app. |
| User-generated content shared publicly | No. Shared links are unlisted and read-only, and the reading page asks search engines not to index it. |
| Shares the user's location | No |
| Purchases of digital goods | No |
| Sponsored ads | No |

Expected rating: Everyone (ESRB), PEGI 3, and the equivalents.

### Target audience and content

| Question | Answer |
|---|---|
| Target age groups | 13 to 15, 16 to 17, 18 and over (docs/store/PLAY_STORE.md: "13 and over"; the privacy page says the app is not directed at children under 13). |
| Unintentionally appeals to children | No. |
| Store listing or ads that could appeal to children | No. |

Choosing 18 and over only would shorten the questionnaire. Matt's call; 13 and over is the plan.

### News apps

News app: **No.**

### COVID-19 contact tracing and status apps

**No**, the app is not one of these.

### Data safety

Read against Play's rules as its help page states them (2026-09-27):

- "User data that is sent off device, but that is unreadable by you or anyone other than the sender and recipient
  as a result of end-to-end encryption does not need to be disclosed."
- Data "only stored in memory and retained for no longer than necessary to service the specific request in
  real-time" is ephemeral processing and need not be disclosed.
- An IP address is declared only "where developers use IP addresses as a means to determine location". Ghost.md does
  not. The web server's access logs (IP address, time, address requested; privacy.html) are kept for security and are
  not used for anything else, and IP address is not a Play data type on its own, so nothing is declared for them.

**Collects or shares any of the required user data types:** Yes.

**All collected user data encrypted in transit:** Yes (HTTPS everywhere).

**A way for users to request deletion:** Yes: `https://ghostmarkdown.com/delete-account.html`, and Settings › Account › Delete account in the app.

Data types:

| Data type | Collected | Shared | Optional or required | Purpose | Why |
|---|---|---|---|---|---|
| Personal info › User IDs | Yes | No | Optional (only with an account) | Account management | The handle, kept in the clear so a person can sign in. |
| Device or other IDs | Yes | No | Optional (only with an account) | Account management | A public key per signed-in device, and its kind ("Android"), so a device can stay signed in. |
| Messages, Files and docs, Audio, Photos and videos (the notes, recordings and pictures) | **No** | | | | End-to-end encrypted on the device with a key the server never holds; Play's own words above say this need not be disclosed. |
| Location, Contacts, Calendar, Health, Financial info, App activity, Web browsing, Crash logs, Diagnostics, Advertising id | No | | | | Not collected at all. There is no analytics, crash reporting or advertising SDK. |

Two flows pass data through the server in memory only, and are ephemeral processing under Play's definition:
signing in to Notion (the tokens are held up to ten minutes until the device collects them) and the hosted Claude
connector (while it is connected, the notes' key is held in memory so Claude can read and write notes; it is never
written to disk and is forgotten on disconnect, sign-out or restart). The privacy policy says both.

Security practices section:

| Question | Answer |
|---|---|
| Independent security review | No |
| Committed to follow the Play Families policy | No (not a children's app) |

### Government apps

**No.**

### Financial features

**No financial features.** (No payments, loans, banking, crypto.)

### Health

**No health features.**

### Advertising ID

Uses advertising ID: **No.**

### Foreground service permissions (only once the 1.9.0 build is uploaded)

The 1.9.0 manifest declares `FOREGROUND_SERVICE_MICROPHONE`, `FOREGROUND_SERVICE_MEDIA_PROCESSING` and
`FOREGROUND_SERVICE_SPECIAL_USE` for the meeting service (docs/DESIGN.md §127 section 3b). Play asks for a
declaration per type, each with a description and a link to a video showing the feature. The video is a screen
recording on the phone that only Matt can make; an unlisted YouTube link is what the form takes.

| Type | Description to paste |
|---|---|
| Microphone | Records a meeting the person starts with a tap on Meeting. The screen can go off and the app can be left; the recording carries on and can be stopped from its notification, which is shown the whole time. |
| Media processing | After the meeting is stopped, the recording is transcribed and summarised on the device, with progress in the same notification. No data leaves the device. |
| Special use | On Android 14 only, the same on-device write-up of a meeting recording after it ends, because the media processing type exists from Android 15. |

Video to record: tap + › Meeting, let the screen go off, wake it, show the "Recording · 0:40" notification, tap Stop,
show "Listening to the recording", then "Written up: Meeting, …". Two minutes is enough.

If the uploaded build is 1.8.x, this section does not appear and nothing is needed.

### Photo and video permissions

Not asked: the app uses the system picker and declares no `READ_MEDIA_*` permission.

## Permissions the manifest declares, for the record

From `src-tauri/gen/android/app/src/main/AndroidManifest.xml`, with `src/store/AndroidManifest.xml` merged in by
`GLYPH_STORE=play`:

| Permission | Why |
|---|---|
| INTERNET | Sync, shares, model downloads, plugins |
| RECORD_AUDIO, MODIFY_AUDIO_SETTINGS | Voice notes |
| POST_NOTIFICATIONS | Update alerts (off until switched on); in 1.9.0 also "Written up" for a meeting |
| REQUEST_INSTALL_PACKAGES | **Removed** in the Play build |
| 1.9.0: FOREGROUND_SERVICE, FOREGROUND_SERVICE_MICROPHONE, FOREGROUND_SERVICE_MEDIA_PROCESSING, FOREGROUND_SERVICE_SPECIAL_USE, WAKE_LOCK | The meeting service |

No SMS, call log, location, contacts or accessibility permissions, so the sensitive-permissions declaration does not
apply.

## Release page

| Field | Answer |
|---|---|
| App bundle | `GLYPH_STORE=play npm run android:build -- --aab --target aarch64`, signed with the upload key (PLAY_STORE.md step 2) |
| Release name | 1.9.0 (Play fills it from the bundle's version name) |
| Release notes | RELEASE_NOTES.md |
| Countries | All countries, or Matt's choice |

## Two decisions only Matt can make (from PLAY_STORE.md)

1. Personal or organisation developer account. Personal means a closed test with 12 testers for 14 days before
   production.
2. What to tell the people who installed the APK: the Play copy is signed with a different key and cannot update over
   the sideloaded app; ask them to sign in and sync first, or keep the APK beside Play.
