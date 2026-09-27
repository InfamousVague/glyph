# The Play Console's forms, answered

What to enter in each form, in the order the Console's dashboard lists them for a new app. Every answer says where it
comes from: the privacy policy (`landing/privacy.html`, live at https://ghostmarkdown.com/privacy.html), the plan
(`docs/store/PLAY_STORE.md`), the Android manifest, or the code. Read against the app at 1.8.0-20, the meetings work
on the `meetings/kotlin` branch, and Play's help pages as they read on 2026-09-27 (the data safety page, the testing
requirements page, the graphic assets page, the create-app page and the foreground service page). Where the Console
words a question differently on the day, its wording wins and the answer stays the same.

Nothing here is a secret. No password, key or token appears in this file, and none should be added to it. A test
account, if you choose to give reviewers one, is made on the day and typed into the Console alone.

## Create app

Play Console › All apps › Create app.

| Field | Enter |
|---|---|
| App name | Ghost.md |
| Default language | English (United Kingdom). The copy is spelt for it. |
| App or game | App |
| Free or paid | Free. Play never lets a free app become paid later. |
| Developer Program Policies | Tick. |
| US export laws | Tick. Ghost.md uses standard encryption for its own data (TLS, and AES-256-GCM through the platform's own libraries), which is the ordinary case and needs no filing of its own. |
| Play App Signing terms | Accept. The upload key steps are in CHECKLIST.md. |

## Select an app category and provide contact details

Store presence › Store settings, under Grow in the left menu.

| Field | Enter |
|---|---|
| App or game | App |
| Category | Productivity |
| Tags | Up to five from Play's fixed list, which the Console shows and its help pages do not print. Take the nearest to notes, note-taking, voice recorder, productivity and Markdown, in that order, and skip any that is not offered. |
| Contact email | infamousvaguerat@gmail.com. It is shown on the listing and is the address on the privacy page. |
| Contact phone | Leave empty. |
| Website | https://ghostmarkdown.com |
| External marketing | Your choice. On lets Google advertise the app outside Play. Off is the quiet answer and changes nothing else. |

## Let us know about the content of your app

Policy › App content. The dashboard lists these eleven in this order. Each opens its own form.

### Privacy policy

`https://ghostmarkdown.com/privacy.html`

Live, checked from outside on 2026-09-25 (PLAY_STORE.md). It is the page Settings › About › Privacy policy opens, and
it names the same contact address as the Console.

### App access

The form asks whether any part of the app is restricted by a login, a membership, a location or another credential.

**Answer: All functionality in my app is available without special access.**

Everything works signed out: notes, voice notes, transcription and the AI on the phone, the tapes, boards, books,
canvases, the Guide. An account is optional. It adds sync between devices, live typing and read-only share links, and
anyone can make one inside the app, free, with any handle and password (Settings › Account, then Create account).
There is no membership, no code and no gate by place. Delete account sits in the same pane.

If you would rather hand reviewers an account, the other answer is "All or some functionality is restricted". Then
add one instruction set named `Optional account`, with the handle and password of a throwaway account you make on the
day, and paste the paragraph below into its instructions box. That box is also the one place in the Console to say a
word about the digital assistant role before a reviewer asks. Under the first answer there is no such box, which is
fine: if the review comes back with a question about the assistant role or the AI, the same paragraph is the reply.

```
Ghost.md works in full without an account: notes, voice notes, transcription and the AI on the device, boards, books and canvases. An account is optional. It adds sync between devices, live typing and read-only share links, and can be made in Settings > Account with any handle and password. Delete account is in the same place. The app registers as a digital assistant (a VoiceInteractionService) only so that holding the side key starts a voice note. It listens to nothing in the background, and the microphone is open only while the recorder is on screen or a meeting the person started is being recorded, with a notification showing the whole time. The AI features run on the device with a model downloaded from Settings > Formatting. Without one the app says so and everything else works.
```

### Ads

**No.** There is no ad SDK, no ad code and no advertising id (privacy page, "What we don't do").

### Content ratings

Start the questionnaire. Email address: infamousvaguerat@gmail.com (IARC writes to it). Category: **Utility,
Productivity, Communication, or Other.** Then, as the questionnaire asks:

| The questionnaire asks about | Answer | Why |
|---|---|---|
| Violence, sexual content, nudity, profanity or crude humour, drugs, alcohol, tobacco, gambling, horror or fear | No to each | A notes app. The only words of its own are the Guide and the Academy. |
| Users interacting or exchanging content with other users (text, voice, pictures, audio) | No | Nothing inside the app reaches another person. A shared link is one note, read-only, sent outside the app by the person who made it, and nobody can write back. Live typing runs between one person's own devices. Should the Console read a sendable link as an exchange, answer Yes there and No to anything about unmoderated or unrestricted content: the link is unlisted and read-only. |
| User-generated content that other users can see | No | Shared links are unlisted (an id nobody can guess, a key that lives only in the link) and read-only. There is no feed, no profile and no search over other people's notes. |
| Sharing the user's location with other users | No | The app never reads location. |
| Buying digital goods or currency in the app | No | Nothing is paid. |
| A web browser, a search engine, or unrestricted internet access | No | Links open in the phone's own browser. |
| Ads, sponsored content or product placement | No | None. |
| Spending real money, or gambling | No | None. |

Expected result: rated for everyone (IARC 3+, ESRB Everyone, PEGI 3, USK 0, and the others the questionnaire covers).
Redo the questionnaire if a later release lets people write to each other.

### Target audience and content

| Question | Answer |
|---|---|
| Target age groups | 13 to 15, 16 to 17, and 18 and over. No group under 13. |
| Whether the app could unintentionally appeal to children, if the Console asks it | No. |
| Whether the store listing could unintentionally appeal to children, if the Console asks it | No. |
| Ads that could appeal to children | Not asked, since there are no ads. |

Why 13 and over: it is the plan's answer, and the privacy page says the app is not directed at children under 13 and
knowingly collects nothing from them. 18 and over alone is also true. Both are honest; 13 and over is the plan.

### News apps

**No.**

### COVID-19 contact tracing and status apps

**My app is not a publicly available COVID-19 contact tracing or status app.**

### Data safety

Play's rules, from its help page as read on 2026-09-27:

- Collecting means transmitting data off the device.
- Data processed on the device and never sent off it is not disclosed.
- Data sent off the device that nobody but the sender and recipient can read, because of end-to-end encryption, is
  not disclosed.
- Data processed ephemerally (in memory only, for no longer than one request takes) goes in the form, and Play then
  leaves it off the listing.
- An IP address is declared by its use. Play's own example is an app that uses it to work out a location. Ghost.md
  never does.

The opening questions:

| The form asks whether | Answer |
|---|---|
| the app collects or shares any of the listed data types | Yes |
| all collected data is encrypted in transit | Yes. Everything is HTTPS: the sync service and the model and update downloads at attack.fm, the site at ghostmarkdown.com, and Hugging Face when attack.fm cannot be reached. A release build sets `usesCleartextTraffic` to false (`build.gradle.kts`). |
| there is a way for users to request that their data is deleted | Yes |

Account creation and deletion:

| The form asks whether | Answer |
|---|---|
| the app lets users create an account | Yes, inside the app, with a handle and a password. |
| there is a way to request that the account is deleted | Yes. In the app: Settings › Account › Delete account, with the password. On the web: `https://ghostmarkdown.com/delete-account.html`, which is the URL the form takes. Deletion is at once and for good: the account, synced notes, recordings, pictures, settings, shared links, devices and recovery codes. |
| users can ask for some data to be deleted without deleting the account | Yes. Delete a note, remove a recording or a picture from one, or stop a shared link (Settings › Account › Shared links), and the next sync removes it from the server. |

The data types. The table is the plan's (PLAY_STORE.md), with the form's columns filled in. Every type not named
here is **not collected and not shared**.

| Data type | Collected | Shared | Ephemeral | Required or optional | Purpose | Why |
|---|---|---|---|---|---|---|
| Personal info › User IDs | Yes | No | No | Optional: only with an account | Account management | The handle, kept in the clear so a person can sign in, with when the account was made and last signed in to. |
| Device or other IDs | Yes | No | No | Optional: only with an account | Account management | One public key per signed-in device, and its kind ("Android"), so a device can stay signed in. |
| Files and docs, Audio files, Photos and videos, Messages (the notes, their recordings and pictures, and settings) | No | | | | | Sealed on the device with AES-256-GCM under a key the server never holds. Play's end-to-end rule says this is not disclosed. The one exception is the hosted Claude connection, below. |
| Location, Name, Email address, Financial info, Health and fitness, Calendar, Contacts, App activity, Web browsing, Crash logs, Diagnostics, the advertising id | No | | | | | Not collected. There is no analytics, crash reporting or advertising SDK. Voice, the review, the formatting and the summaries run on the phone. |

**The hosted Claude connection.** While a person has Claude connected through the hosted connector, the server holds
their notes' key in memory and decrypts a note for each request Claude makes, then forgets it. Nothing is written to
disk, and the key goes when they disconnect, sign out everywhere, leave it a week, or the server restarts. For that
person, and only while it is connected, the end-to-end rule does not hold, so the honest form entry is **Files and
docs: collected, ephemeral, optional, purpose App functionality, not shared** (the person chose Claude and started
each request themselves, which Play does not count as sharing). Ephemeral data is not shown on the listing, so the
entry costs nothing there. Notion's sign-in tokens pass through the server the same way for at most ten minutes;
they are not one of Play's data types.

**Open item: the IP address in the web server's access logs.** The privacy page says the sync service keeps an IP
address in memory only, to limit sign-in attempts, and that the web server keeps ordinary access logs (IP address,
time, and the address asked for) for security and troubleshooting. The rate limiter's use is ephemeral and the
address is not used for location, so nothing follows from it. The logs are the question, and the box cannot be
logged into today. On a day it can:

1. Open the Caddyfile on the box and look for the `log` directive: whether access logs are on, where they are
   written, and how long they are kept (Caddy's `roll_keep` and `roll_keep_for`).
2. If they are kept: declare **Device or other IDs** a second time, for the purpose **Fraud prevention, security and
   compliance**, required (every request leaves a line, signed in or not), not shared. Play has no type named "IP
   address"; this is the nearest, and the privacy page already says the logs exist.
3. If they are off, or go only to a journal that discards them within days: nothing more to declare, and the
   privacy page's sentence about access logs can be softened to match.

Security practices, the form's last section:

| Question | Answer |
|---|---|
| Independent security review | No. It is an optional badge for apps checked by a lab against the MASVS standard, and none has been. |
| Commits to the Play Families policy | Not asked of an app that is not for children. If it is, No. |

### Government apps

**No.** Not made by or for a government.

### Financial features

**My app doesn't provide any financial features.**

### Health

**My app doesn't have any health features.**

## Declarations the Console asks for when the bundle calls for them

Under Policy › App content, below the eleven above. Two are asked of every app; the third appears only once a 1.9.0
bundle is uploaded.

### Advertising ID

Asked of every app that targets Android 13 or later, which this one does (targetSdk 36). **No.** The manifest has no
`com.google.android.gms.permission.AD_ID`, and nothing in the app reads the id.

### Photo and video permissions

Not asked. The app declares no `READ_MEDIA_IMAGES` or `READ_MEDIA_VIDEO`; pictures come through the system picker.

### Foreground service permissions (1.9.0 only)

1.8.0 has no foreground service, so the form does not appear for it. The 1.9.0 meeting service (`MeetingService.kt`
on the `meetings/kotlin` branch, commit 909b491 as read on 2026-09-27) records under the **microphone** type, then
writes the meeting up under **media processing** on Android 15 and later and under **special use** on Android 14,
where that type does not exist. WorkManager's own foreground service carries the same two write-up types for the
retry path, and both services name the special use as "Writing up a meeting recording on the device" in the
manifest. The service also holds a partial wake lock.

Play asks per type, not per service, once a bundle declaring the types is uploaded. For each type the form wants: a
description of what the feature does, what happens to the person if the system defers or stops it, a use case
picked from Play's list (or written in when none fits), and a link to a video showing it. Read the built service
before pasting: docs/DESIGN.md §127 sections 3, 4 and 5 were still headed "To come" when this was written, and the
page's way of starting a meeting is not on main, so check the word the app uses for it.

| Type | Description to paste | If the system stops it |
|---|---|---|
| Microphone | Records a meeting the person started by hand in the app. The screen can go off and the app can be left; the recording carries on, and a notification shows the whole time, reading Recording with the elapsed time and offering Stop and Discard. After two hours it asks whether to keep going. The microphone is open for that recording and nothing else. | The recording ends where it stopped. The tape and its words are kept, and the note says so. |
| Media processing | After the meeting is stopped, the recording is transcribed and summarised on the device, in the same service, with progress in the same notification: Writing up, then Listening to the recording with a percentage, then the summary. Nothing leaves the phone. When it is done a notification reads Written up with the note's title and the first line of the summary; on the lock screen it says only that a recording was written up. | The write-up resumes when the app is next opened, or from Write up now on the Tapes shelf. |
| Special use | The same write-up of a meeting recording on Android 14, where the media processing type does not exist. | As above. |

The use case from Play's list: for the microphone, the nearest to voice recording or background audio recording; for
the other two, media transcoding or processing. The video: a screen recording on the phone, two minutes is enough,
showing a meeting started, the screen going off, the notification, the meeting stopped, and the summary arriving
under the title. An unlisted YouTube link is what the form takes. Only you can record it.

## The permissions the manifest declares

For the record, from `src-tauri/gen/android/app/src/main/AndroidManifest.xml` with
`src-tauri/gen/android/app/src/store/AndroidManifest.xml` merged over it by `GLYPH_STORE=play`.

| Permission | Why it is there |
|---|---|
| INTERNET | Sync, shares, model downloads, the plugins |
| RECORD_AUDIO, MODIFY_AUDIO_SETTINGS | Voice notes. Asked for at the first recording. |
| POST_NOTIFICATIONS | Update alerts, off until switched on in Settings. In 1.9.0, the meeting's notification too. |
| REQUEST_INSTALL_PACKAGES | Removed from the Play build. |
| 1.9.0: FOREGROUND_SERVICE, FOREGROUND_SERVICE_MICROPHONE, FOREGROUND_SERVICE_MEDIA_PROCESSING, FOREGROUND_SERVICE_SPECIAL_USE, WAKE_LOCK | The meeting service. |

No SMS, call log, location, contacts, all-files or accessibility permission, so the sensitive-permissions
declaration does not apply. Two things in the manifest can draw a reviewer's eye and are explained in the App access
paragraph above: the voice interaction service and the assistant intent, which exist so that a held side key opens
the recorder, and the recognition service beside them, which the assistant role requires and which does nothing.

## The release form

Test and release › Testing › Closed testing, or Test and release › Production › Create new release.

| Field | Enter |
|---|---|
| App bundle | `app-universal-release.aab`, built and signed as CHECKLIST.md says. |
| Release name | Play fills it from the bundle (the version name and code). Leave it. |
| Release notes | The block in `copy/whats-new.md`, in the en-GB box. |
| Countries and regions | All, or your choice. Set once under the track's Countries/regions tab. |
