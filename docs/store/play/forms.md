# Play Console forms for 2.4.25: what changes from 2026-10-05

The eleven App content declarations were answered on 2026-10-05 for the Tauri app at 1.14.0
(tauri/docs/store/play/console-2026-10-05.md, which records what the Console holds). This file answers them again for
the Flutter app's Play build at 2.4.25 (`tool/cutover-build.sh 2.4.25 --play`), read against its merged manifest
(`bundletool dump manifest`), the code and the privacy page (landing/privacy.html, last updated 4 November 2026).
Each section says what changed. Where nothing changed it says so, and the Console's answer stands.

Nothing here is a secret. The reviewers' account's password is in tauri/docs/store/APP_STORE.md and is typed into the
Console alone.

## Privacy policy: unchanged

`https://ghostmarkdown.com/privacy.html`. Account deletion: `https://ghostmarkdown.com/delete-account.html`.

**Brought up to date on 2026-11-05** (landing/privacy.html, "Last updated 5 November 2026"; not deployed with this
change): the in-app AI assistant on the person's own key and what goes straight to the provider, pictures in the AI
chat, each plugin by name and what it sends (Lovart, ElevenLabs, Notion, GitHub, Back up to git, Figma, Calendar,
Slack and Discord, Meet and Zoom, Email to a note, Publishing and forms, Todoist), the map tiles' rough area, place
reminders in each build, Google Play services (document scanner, text reading, location, Wear OS), and updates: the
Play build is updated by Play and never checks attack.fm.

## Ads: unchanged

No. No ad SDK, no `AD_ID` permission in the merged manifest.

## App access: unchanged in kind, one sentence more

"All or some functionality is restricted", with the demo account (handle `test`, the password in
tauri/docs/store/APP_STORE.md). Matt checks it still signs in and holds the examples. Instructions to paste:

```
An account is optional: notes, voice notes, transcription on the phone, boards, notebooks and canvases all work without one. To try sync and organizations, sign in under Settings > Account with the demo account. The AI assistant needs the person's own key from an AI provider (Settings > AI); without one the app says so and everything else works. The app sends optional anonymous usage statistics (feature counts, no content, no account link), which can be turned off in Settings > Privacy or during onboarding. The microphone is open only while a recording the person started is running, with a notification the whole time. The voice assistant service in the manifest is disabled in this build and is not offered as the phone's assistant. Account deletion is under Settings > Account > Delete account.
```

## Content rating: one new answer

The 2026-10-05 answers stand (All Other App Types; users share content in organizations; block and report; shares
location with other users: yes, a team note's geotag). New: if the questionnaire asks about **generative AI**, answer
Yes: the assistant (on the person's own key) writes text into their own notes, and the header-image plugin draws
pictures for them. Nothing it makes is published. Expected result unchanged: Everyone / PEGI 3 / IARC 3+.

**Risk to know about:** Play's AI-Generated Content policy asks apps with generative AI to let people report or flag
offensive output in the app. Ghost.md has no such button for the assistant's answers or a header image. Reviewers
may ask; a "Report" row in the chat's and the banner's menus (a mailto to the contact address) would answer it.

## Target audience: recommend 18 and over (changed)

Was 13-15, 16-17, 18+. Recommend **18 and over** now: the AI assistant runs on the person's own provider key, and
the providers' API terms are for adults; the app has organizations with invitations by email and handle; and it
keeps the listing out of Play's teen checks. 13+ is still honest (the privacy page says it is not for under 13s), but
18+ is the simpler one to defend. "Appeals to children": No.

## News, COVID-19, government, financial, health: unchanged

None.

## Advertising ID: unchanged

No.

## Data safety (changed: analytics, location, AI, email, calendar)

Opening questions, unchanged: collects or shares required data, **Yes**; encrypted in transit, **Yes** (everything
is HTTPS; a release has no cleartext traffic); a way to request deletion, **Yes**; accounts by username and password,
deletion at the URL above. Independent security review: No.

The data types, in the Console's order. Every type not listed is **not collected**.

| Console type | Collected | Shared | Ephemeral | Required? | Purposes | What and why (the change from 10-05) |
|---|---|---|---|---|---|---|
| Location › Approximate location | Yes | Yes | No | Optional | App functionality | **New row.** A rough tag (two decimals) sent to OpenStreetMap for the place's name. |
| Location › Precise location | Yes | Yes | No | Optional | App functionality | As 10-05: tiles and the place's name from OpenStreetMap, asked at three decimals (about 100 m). **Now on by default** for new notes once the person allows location (Settings › Account › Location turns it off). In sync it is inside the note's encrypted front matter, so not collected by us. Place reminders stay on the phone (in this build, checked while the app is open). |
| Personal info › Email address | Yes | No | No | Optional | App functionality | **New row.** An organization's invitation by email: the address kept until the invitation is used, ends or expires, and one email sent through the email provider (a processor). Also the sender's address on mail sent to the account's email-to-note address. |
| Personal info › User IDs | Yes | No | No | Optional | App functionality, Account management | Unchanged: the handle. |
| Messages › Emails | Yes | No | No | Optional | App functionality | **New row.** Email to a note (a plugin, off by default): the service receives the mail in the clear and seals it at once to the account's key. The email provider keeps its usual logs, so not ephemeral. |
| Photos and videos › Photos | Yes | No | No | Optional | App functionality | **New row.** A picture given to the AI chat goes from the phone to the AI provider the person chose with their own key. User-initiated, so Play does not count it as sharing. |
| Files and docs | Yes | No | No | Optional | App functionality | **Changed from ephemeral only.** As 10-05, the hosted connector reads notes for the person's own AI assistant (ephemeral there). New: the in-app assistant sends what is asked and the notes it reads to the provider the person picked, with their own key; the plugins the person switches on send the text they act on (header-image prompts, voice-overs, tasks to a team wiki or chat). All started by the person, so not sharing; not ephemeral, as the provider keeps it under its own terms. |
| Calendar › Calendar events | Yes | No | No | Optional | App functionality | **New row.** With the calendar plugin on and signed in, dated to-dos are written to the person's own calendar, and events are read onto Today. The sign-in passes through our server. |
| Contacts | No | | | | | Read on the phone only, never sent. |
| App activity › App interactions | Yes | No | No | Optional | Analytics, App functionality | **Changed.** New: the anonymous usage stats (screens, features, plugins on, job outcomes, buckets), on by default, off in Settings › Privacy. As 10-05: the live-editing relay (ephemeral, App functionality). Play has one ephemeral switch per type: answer No, since the stats are kept. |
| App info and performance › Crash logs | Yes | No | No | Optional | Analytics | **New row.** An uncaught error's type name, never its message or stack. |
| App info and performance › Diagnostics | Yes | No | No | Optional | Analytics | **New row.** Start-up time and job durations as buckets. Also covers the anonymous diagnostics Google's on-phone text reading may send. |
| Device or other IDs | Yes | No | No | Required | Analytics, Account management, Fraud prevention and security | **Changed: Analytics added.** As 10-05: the web server's access log (IP address) and each signed-in device's public key. New: the usage stats' random install ID (not linked to the account; deleted when the stats are turned off). Required, because the access log is. |

The AI providers, in one line for anyone who asks: the person picks the provider and pastes their own key; the app
sends the request straight from the phone to that provider when they ask something. Play's definition of sharing
leaves out a transfer the user starts and expects, so it is **collected (it leaves the phone), not shared**, purpose
App functionality, optional. Nothing reaches our servers.

## Sensitive permissions and foreground services (changed)

The Play build's merged manifest asks for: INTERNET, ACCESS_NETWORK_STATE, RECORD_AUDIO, MODIFY_AUDIO_SETTINGS,
POST_NOTIFICATIONS, POST_PROMOTED_NOTIFICATIONS, FOREGROUND_SERVICE, FOREGROUND_SERVICE_MICROPHONE,
FOREGROUND_SERVICE_MEDIA_PROCESSING, WAKE_LOCK,
ACCESS_COARSE_LOCATION, ACCESS_FINE_LOCATION, SCHEDULE_EXACT_ALARM, RECEIVE_BOOT_COMPLETED, READ_CONTACTS, and the
app's own DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION. **REQUEST_INSTALL_PACKAGES, ACCESS_BACKGROUND_LOCATION,
FOREGROUND_SERVICE_SPECIAL_USE and FOREGROUND_SERVICE_MEDIA_PROJECTION are gone** (android/app/src/play/AndroidManifest.xml). No SYSTEM_ALERT_WINDOW,
QUERY_ALL_PACKAGES, MANAGE_EXTERNAL_STORAGE, READ_MEDIA_*, SMS, call log, accessibility or USE_EXACT_ALARM.

### Location permissions: no declaration (background location taken out, 2026-11-05)

ACCESS_BACKGROUND_LOCATION is removed from the Play build (`tools:node="remove"` in
android/app/src/play/AndroidManifest.xml), so Play asks for no background location declaration and no video. The
sideload APK keeps it.

What changes in the Play build: no geofence registers without it, so **place reminders ring only while the app is
open**. reminders/Places.kt reads the manifest (`backgroundDeclared`): the access is `whileOpen`, "Allow all the time"
and the app's sheet before it are never shown, and while the activity is resumed the fused location is asked about
once a minute (balanced power) and a place rings as the phone comes inside it (what was inside at the last look is
kept, so opening the app on arriving rings, and a to-do written at the shop does not). Dart says the same from
`--dart-define=GHOST_STORE=play` (lib/reminders/place_host.dart `placesInFrontOnly`): the plugin's page says "Allowed
while the app is open", and its setup's three voiced steps show their own words, unspoken
(lib/plugins/places/places_setup.dart `placesInFrontCaptions`). Tests: test/reminders/place_host_test.dart, places_test,
plugin_setups_test, play_store_test.

Foreground location (geotags, Add my location, place reminders in front) needs no declaration of its own.

### Foreground service permissions (changed 2026-11-09: microphone and media processing only)

Play rejected the update on 2026-11-06 (Policy status, "Update rejected", all three under "Permissions for Foreground
Services": no material user impact if deferred, not initiated by or perceptible to the user, permission not or
incorrectly declared). Matt's decision, 2026-11-09: "Keep mic + write-up only". From 2.4.27 the Play build declares
**only** these two types, both on capture/MeetingService:

| Type | Service | Play's task (preset list) | When it runs |
|---|---|---|---|
| Microphone | capture/MeetingService | Background Audio Access | While a meeting the person started by hand records. |
| Media processing | capture/MeetingService | Media transcoding | The write-up the person's Stop starts at once (Android 15 and later). |

**Removed from the Play build** (android/app/src/play/AndroidManifest.xml, `tools:node="remove"` /
`tools:replace` / `tools:remove`; the code reads what is declared, glyph/capture/ForegroundTypes.kt):

- **Special use**, everywhere: FOREGROUND_SERVICE_SPECIAL_USE, every PROPERTY_SPECIAL_USE_FGS_SUBTYPE, and
  ghost_md/BackgroundJobService whole. Long jobs (header images, voice-overs, imports, git backup, Wrapped's pass, AI
  summaries) run while the app is open; behind another app or with the screen off Android freezes the app within
  seconds, the job pauses, its notification says "Paused while Ghost.md is in the background. Open it to go on."
  (ActivityNotices.kt `paused`), and it carries on when the app comes back. A request cut off by the freeze is tried
  again (the jobs' network-blip retry). If Android kills the app meanwhile the job ends with it.
- **Media projection**: "Include sound from other apps" is not offered (no switch in Settings or the + sheet, not in
  Settings' search, never asked for); meetings record the microphone only.
- **WorkManager's foreground service types**: SystemForegroundService has no type, and RecordingWorker never calls
  setForegroundAsync. The write-up's retry path (a kill mid-write-up, a hot phone, "Write up now") is ordinary
  WorkManager work, its progress a plain notification.
- **Android 14** (no media processing type, special use gone): the write-up after Stop is ordinary WorkManager work
  (the chain request MeetingService already makes), started at once, about ten minutes per run and resumed where it
  left off, with a plain progress notification. Android 15+ is unchanged: the foreground write-up.

The sideload APK keeps all four types, the job service and the worker's types: its merged manifest is byte for byte
the same as before (docs/store/play/README.md, 2.4.27).

#### What to paste, per type

Each type asks: the task (preset list), a description of the functionality, the user impact if deferred or
interrupted, and a video link.

**Microphone**

- Task: **Background Audio Access** (the preset; Google's description: "voice recording").
- Description: `Ghost.md records a meeting only after the person taps Meeting in the app and starts it. The recording keeps going while the screen is off or another app is open, so a whole meeting is captured with the phone on the table. A notification with Stop and Discard shows for the entire recording, and the microphone is used for that recording and nothing else. The recording ends when the person presses Stop.`
- User impact if deferred or interrupted: `The meeting would not be recorded. If the start were deferred, the first part of the meeting would be lost; if the service were paused or stopped, everything said after that point would be missing from the recording and from the notes written from it, and it cannot be recorded again later.`
- Video: docs/store/play/fgs-2026-11/meeting-mic-and-writeup.mp4, uploaded by Matt (YouTube, unlisted) and the link
  pasted here.

**Media processing**

- Task: **Media transcoding** (the preset; Google's description: "time-consuming operations on media assets, like
  converting media to different formats"). The write-up converts the meeting's audio into text. If the Console
  offers no closer match, choose Other and paste the description.
- Description: `When the person presses Stop on a meeting they recorded, Ghost.md immediately converts the recording into text on the device: it transcribes the audio and writes up the meeting note. This starts only from that Stop and runs until the note is written, typically a few minutes, with a notification showing its progress the whole time. Nothing leaves the phone.`
- User impact if deferred or interrupted: `The person is waiting for the meeting note they just asked for. If the work were deferred or paused, the note would stay empty until the app was opened again, and a long recording would take far longer to write up because it would restart its current part each time it was interrupted.`
- Video: the same video (the Stop, then the progress notification until the note is written).

Do not tick or describe special use, media projection, data sync or any other type: the bundle declares none.

### Other permissions, no form

| Permission | Play form? | One line |
|---|---|---|
| RECORD_AUDIO, MODIFY_AUDIO_SETTINGS | No | Dictation and meetings; asked at the first recording, open only while recording. |
| READ_CONTACTS | No (not a restricted group) | Settings › Contacts, off until switched on: a person named on a to-do gets their picture and a tap to call or write. Read only, never sent. |
| SCHEDULE_EXACT_ALARM | No (USE_EXACT_ALARM is the one with a form) | Reminders ring on their minute once the person allows Alarms and reminders; otherwise a few minutes late. |
| RECEIVE_BOOT_COMPLETED | No | Arms the reminders again after a restart. No service is started. |
| POST_NOTIFICATIONS, POST_PROMOTED_NOTIFICATIONS | No | Recording, write-up and reminder notifications; a long job's progress (or that it is paused) as a Live Update. |
| ACCESS_COARSE/FINE_LOCATION | No | Where a note was written, after the person allows it; place reminders while the app is open. |
| WAKE_LOCK | No | Keeps the CPU on while a meeting records with the screen off. |
| VoiceInteractionService (in the manifest, disabled) | No | `@bool/ghost_assistant` is false: the app is not offered as the phone's assistant. Said in the App access notes. |

## Store settings: unchanged

Category Productivity. Tags, up to five from Play's list, nearest to: Notes, Productivity, To-do list, Voice
recorder, Calendar. Contact infamousvaguerat@gmail.com, website https://ghostmarkdown.com.
