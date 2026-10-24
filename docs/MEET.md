# Ghost in a Google Meet

GHST-106. Matt: "invite Ghost to meetings for it to automatically join". Ghost joins a Google Meet by itself, records
it with the captions Meet shows, and the recording reaches the person who invited it, sealed to their account. This
page is the service's half (`server/src/meet.rs`, `server/src/meet/ics.rs`, `server/src/store/meet.rs`); the bot that
joins is a separate service on the box, and the app's half downloads and opens the recordings. The spike that showed
it can be done is `meet/spike/README.md`.

## How a meeting is booked

1. The person adds their mail-to-note address (`sneaky_siren33@in.ghostmarkdown.com`, or a name of their own such as `matt@…`, `tauri/docs/MAIL.md`)
   as a guest on a Google Calendar event. Nothing new to turn on: it is the address they already have.
2. Google mails the invitation there. The mail becomes a note as any mail does, and in the same request the service
   reads its calendar part - the `text/calendar` alternative, or the `invite.ics` attachment; Google sends both, and
   they are read once - and books Ghost for the meeting.
3. Or a device says "join this now": `POST /api/v1/meet` with a Meet link books Ghost from now for two hours.

Only an account with an encryption key gets bookings (the recording is sealed to it), and only Google Meet links
(`https://meet.google.com/abc-defg-hij`, from `X-GOOGLE-CONFERENCE`, else the description, the location or `URL`)
are booked. An account has at most 100 meetings booked and still to come, so an address anyone may mail cannot fill
the bot's day.

### Reading the invite

One booking per invite UID (an occurrence of a series is `<UID>#<its start in ms>`, and one changed on its own
`<UID>#<its RECURRENCE-ID in ms>`, the same; a series, below):

| The invite | The booking |
|---|---|
| new, with a Meet link, not over | booked |
| a SEQUENCE lower than the one applied | ignored (an old copy arriving late) |
| a newer one | its link, title and times follow the invite; booked again if it had been called off, or if it moves to a new time after it was over, skipped or failed |
| `METHOD:CANCEL` or `STATUS:CANCELLED`, or no Meet link any more | `cancelled`; or `leave` if Ghost is in it or on its way |

Times: UTC (`…Z`); wall-clock time in a zone, resolved with the invite's own VTIMEZONE block (Google always sends one:
STANDARD and DAYLIGHT, their offsets and yearly rules), or a small table of common IANA names when an invite names a
zone without a block; floating time is read as UTC. All-day events are left out.

### Recurring meetings

Every occurrence is joined, with no new mail (Matt, 2026-10-21: "The ghost bot was invited to join a standup daily but
it's not joining"; v1 booked one occurrence and waited for Google to mail again). The rule is expanded in the event's
own wall-clock time (a weekly 9:00 stays at 9:00 across a change of clocks), skipping EXDATEs and occurrences the
invite changes on their own. DAILY, WEEKLY, MONTHLY, YEARLY with INTERVAL, COUNT, UNTIL, BYDAY (`2TU`, `-1FR`),
BYMONTHDAY and BYMONTH are read; any other rule books only its first occurrence.

- **The series' row** (uid `<UID>`) keeps, beside the link, the title and the SEQUENCE, what expanding the rule needs
  and nothing else, as JSON in `meet_bookings.series` (`ics::Series`): the RRULE, DTSTART's wall-clock time and its
  zone's observances (from the invite's VTIMEZONE), the length, and the starts it does not book (EXDATEs, RECURRENCE-
  IDs). No organizer, no guests. Its `starts_at` and `ends_at` are the occurrence it booked last. It is not a meeting:
  never in the list, never due, not counted toward the 100, and 404 to a skip or the bot.
- **Each occurrence** is a booking like any other, uid `<UID>#<its start as the rule makes it, ms>` - the uid a changed
  occurrence's RECURRENCE-ID gives it, so the change finds it. The invite books the next one to come.
- **Moving on**: once the occurrence booked last is over (its end has passed) or not live (done, failed, skipped,
  cancelled), the next one still to come is booked as a new booking, `booked`, with a fresh id. Run whenever bookings
  are read - the bot's `due` (every 20 s), the device's `GET /api/v1/meet` - and by the hourly sweep. A fresh row per
  occurrence, rather than one row moved on, because each occurrence keeps its own history: the bot remembers the ids
  it has handled for as long as it runs (`meet/bot/lib/decide.mjs`) and would never join a reused id again, a take's
  `meeting` names the occurrence it recorded, and the device lists each past occurrence with its own state.
- **A skip** (`DELETE /api/v1/meet/{id}`) skips that occurrence: the series moves on to the next at once.
- **An occurrence the account has a booking for already** (changed or called off on its own, `<UID>#<ms>`) is that
  booking's: the series moves past it. One called off on its own in a mail of its own before the series reached it is
  kept as `cancelled`, with no link, so the series passes over it.
- **An update** (a higher SEQUENCE; Google mails the whole VCALENDAR) brings the series' rule, link and title up to
  date, and the occurrence it reads as next follows the invite. If the update takes away the occurrence booked last
  (a new time, an UNTIL sooner) before it has begun, that booking is deleted; one changed on its own since (a later
  SEQUENCE) is left to its own invite.
- **Called off** (`METHOD:CANCEL`, `STATUS:CANCELLED`, or no Meet link any more): the series is `cancelled`, and each
  of its occurrences still to come is `cancelled`, or `leave` if Ghost is in it.
- **Over** (COUNT, UNTIL): the series is `done`.
- **The limit** holds: a new series needs room for its first occurrence, and a series with no room waits, its link
  kept, until there is.

A booking of v1 (one occurrence under the series' UID) becomes that occurrence's own (`<UID>#<ms>`, same id) when the
series is mailed again, and the series is booked beside it.

**One occurrence alone.** The organizer may add Ghost to one occurrence only ("This event"): Google mails a VEVENT
with a RECURRENCE-ID and no RRULE. That is one meeting, booked if it is still to come; mailed after it ended, as
happened to Matt's stand-up on 2026-10-21, it books nothing, and the mail is a note as any mail is.

## What is in the clear, and for how long

The bot has no key, so a booking keeps what joining needs in the clear: the Meet link, the title the app shows, the
start and the end. The organizer and the guest list are read and dropped. **Only until the meeting is done**: the
hourly sweep (with the hook inbox's, `server/src/hooks.rs`) blanks the title and the link an hour after the meeting
ended, marks a booking the bot never finished `failed` (`missed`), and deletes the booking thirty days after it ended.
A recurring meeting's own row keeps its title, link and rule while it has occurrences to come (each occurrence is
blanked and deleted on its own, as any booking); once it is over or called off it is blanked an hour after its last
occurrence ended (or it was called off) and deleted thirty days after.

The recording and its captions are never kept in the clear, on disk or in a log: they are sealed to the account's
encryption PUBLIC key in the request that uploads them, the clear bytes are wiped, and only the sealed copy is kept,
until a device of the account takes it. The service cannot open it. (The bot, which made it, holds the clear copy
until its upload is answered; that is the bot's to delete.)

## Routes

All times are ms since the epoch. Ids are base64url.

### A device's (signed in, `Authorization: Bearer <session token>`)

| | Request | Answer |
|---|---|---|
| `GET /api/v1/meet` | | `{ meetings: [Meeting] }`: those not over, and the last 7 days', soonest first |
| `POST /api/v1/meet` | `{ url, title? }` | `{ meeting: Meeting }`, booked now for 2 h. 400 not a Meet link, 409 no encryption key yet, 429 100 already to come |
| `DELETE /api/v1/meet/{id}` | | `{ meeting: Meeting }`: `skipped` if it had not started, `leave` if Ghost is joining or in it, as it was otherwise. 404 not the account's |
| `GET /api/v1/meet/takes` | | `{ takes: [{ id, meeting, size, at, wrapped }] }`, oldest first |
| `GET /api/v1/meet/takes/{id}` | | the sealed take, raw `application/octet-stream`; headers `x-glyph-wrapped` (the wrapped key) and `x-glyph-meeting`. 404 not waiting |
| `DELETE /api/v1/meet/takes/{id}` | | 204: taken |

`Meeting` is `{ id, title, url, startsAt, endsAt, state, detail }`; `title`, `url` and `detail` may be null (`title` and
`url` are null once swept). `state` is one of `booked`, `joining`, `in_call`, `leave`, `done`, `failed`, `skipped`,
`cancelled`.

A take is answered raw, not as base64 in JSON: a meeting is tens of megabytes (Opus at 32 kbit/s is about 15 MB an
hour), which base64 would make a third larger and the phone would hold twice. The headers are exposed to a browser
page by the service's CORS layer.

### The bot's (`/api/internal/meet`, this machine only)

Answered only when the connection's peer is loopback, no proxy header is present (`X-Forwarded-For`, `Forwarded`,
`X-Forwarded-Host`, `X-Forwarded-Proto`, `X-Real-IP` - Caddy connects from loopback too, and always sets
`X-Forwarded-For`), and `Authorization: Bearer <GLYPH_MEET_TOKEN>` matches (compared as SHA-256 digests, in constant
time). From anywhere else the answer is the service's 404 `{ "error": "no such route" }`; a wrong token on this
machine is 401. Without `GLYPH_MEET_TOKEN` the routes are not mounted. The bot calls `http://127.0.0.1:8796`.

| | Request | Answer |
|---|---|---|
| `GET /api/internal/meet/due` | | `{ meetings: [{ id, url, title, startsAt, endsAt, state, announce }] }`: state `booked`, `joining`, `in_call` or `leave`, from 2 minutes before `startsAt` until 15 minutes after `endsAt`, oldest first. `announce` is the line to post in the meeting's chat |
| `POST /api/internal/meet/{id}/state` | `{ state, detail? }`, state `joining`, `in_call`, `done`, `failed` or `skipped`; detail free text, at most 200 characters (`signed_out`, `not admitted`, `meeting ended`) | `{ id, state }`. 409 `{ error, id, state }` with the state that stands when the meeting is over (`done`, `failed`, `skipped`, `cancelled`) or the bot was asked to `leave` and says `joining`/`in_call`: leave, and do not join again. 400 another state, 404 no such meeting |
| `PUT /api/internal/meet/{id}/take` | `multipart/form-data`: `audio` (the recording; its Content-Type is kept, `audio/webm` if absent or odd), `captions` (NDJSON, optional), `startedAt` and `endedAt` (ms as text, optional) | `{ take, size }`, and the meeting is `done`. 400 no audio or unreadable, 404 no such meeting, 409 the meeting was skipped or cancelled, or its account has no key |

`announce`: "Ghost.md is taking notes for this meeting. The recording goes to the person who invited it, sealed to
their account."

The bot's loop: poll `due` (every 15 to 30 seconds); for a `booked` one, post `joining`, join, post `in_call` once in;
watch for `leave` in `due` (a device skipped it, or the organizer cancelled it) and leave; on leaving, upload the take
(which sets `done`), or post `failed` with a detail when nothing was recorded (`not admitted`, `signed_out`).

Limits: audio 300 MB, captions 20 MB, the upload's body 321 MB. The service holds the upload in memory while it seals
it (about twice the take at its peak); a take is written to disk only sealed.

## What is sealed: `GMT1`

The take, before it is sealed: the four bytes `GMT1`, the head's length as four bytes big-endian, the head as JSON,
then the captions' bytes, then the audio's (the mail's `GML1`, for a meeting):

```json
{ "v": 1, "meeting": "<booking id>", "title": "Roadmap review, Q4", "startedAt": 1792159500000,
  "endedAt": 1792163100000, "mime": "audio/webm;codecs=opus", "captionsBytes": 1234, "audioBytes": 15000000 }
```

`title` may be null. `startedAt` is the upload's, else the booking's start; `endedAt` the upload's, else the moment it
arrived. The captions are passed through as the bot sent them.

## The seal

As a mail's (`tauri/docs/MAIL.md`, "The seal"), with contexts of its own, so a take's seal opens as no mail's, and a
seal moved onto another take opens nothing:

1. **The key**: a fresh 32-byte key wrapped to the account's encryption public key by ECIES (`wrap_for`, as an
   organization key is wrapped), context **`meet-take:<take id>`**. Base64url, in the list's `wrapped` and the
   `x-glyph-wrapped` header.
2. **The take** under that key, as `sealBytes` seals: a version byte (1), a 12-byte IV, AES-256-GCM over the `GMT1`
   bytes with **`meet:<take id>`** as associated data. This is the file's whole content and the download's body.

A device opens it with what it has: `unwrap_with(pair, wrapped, 'meet-take:<id>')`, `seal_key_import`,
`open(bytes, 'meet:<id>')`; then reads `GMT1`, and deletes the take. `server/src/meet_tests.rs`
`a_take_is_sealed_on_arrival_kept_only_sealed_and_opened_by_the_account_alone` does the same in Rust, and reads every
file the service keeps to find no byte of the recording in the clear.

The sealed file is `<data>/recordings/<account id>/meet/<take id>.take`, beside the account's recordings, and goes with
the account. A take waits until a device takes it; it does not expire.

## The environment

`GLYPH_MEET_TOKEN`: the bot's bearer token, 32 to 200 letters, digits, `-` or `_` (`openssl rand -hex 32`). In
`tauri/.env`; `node scripts/deploy-server.mjs` writes it into the box's `/opt/glyph-api/glyph-api.env` as it writes
`GLYPH_MAILGUN_SIGNING_KEY`, and the bot's own service reads the same value. Unset, invites are still booked and listed,
and nothing joins them.

Caddy needs no change: `/api/internal/*` reaches the service like any `/api/*` path and is answered 404 because the
request came through Caddy. Refusing `/api/internal/*` in Caddy as well would be a second lock on the same door.

## The bot and the box

`meet/bot/` is the bot: a Node service (ESM, Node 18 or newer, one dependency, `playwright-core` 1.59.1) that drives
the box's installed Google Chrome. `meet/box/` holds its units and `meetctl`; `scripts/setup-meet-box.mjs` installs
all of it. Everything the spike found (`meet/spike/README.md`) is kept: a signed-in profile, never an anonymous guest;
no automation markers; Chrome's own sandbox; no microphone, camera or fake devices; the meeting heard by capturing the
bot's own tab.

### What it does

- **The loop** (`bot.mjs`, `lib/decide.mjs`): `GET due` every 20 s. One meeting at a time, the earliest first; the
  others wait, and one that would be joined more than 10 minutes late is posted `failed: busy`. A meeting whose end
  has passed is posted `skipped: time_up`. A meeting is joined again after a restart if it is still `joining` or
  `in_call`; a 409 to `joining` or `in_call` means it is not Ghost's any more, and it is never tried again. Only
  `https://meet.google.com/<code>` links are opened.
- **The lobby** (`lib/meet.mjs`): `joining`; the link; a "Your name" box or a Sign in button is `failed: signed_out`
  and the end of it; "Continue without microphone and camera", microphone and camera off; then the first of "Join
  now", "Ask to join" or "Switch here" (a seat of its own left behind). "You can't join this video call" is
  `failed: refused`; denied, or 10 minutes without being let in, is `failed: not_admitted`; a meeting already over is
  `skipped: meeting_ended`. In the call when the Leave button is attached (Meet hides its tray until the pointer
  moves). A stop during the lobby leaves the meeting `joining`, for the next run.
- **The call**: `in_call`; the `announce` line in the chat (opened, typed, Enter, closed; a meeting with chat off is
  let be); captions on ("Turn on captions", else "c", asked again if they go away); the tab captured into a
  MediaRecorder, Opus/WebM, a 5-second slice appended to `/var/lib/glyph-meet/work/<id>.webm` as it comes, so a crash
  loses at most one.
- **The captions** (`lib/captions.mjs`): the region `[role=region][aria-label*=aption]`, read twice a second as blocks
  of `name\ntext`, become NDJSON lines `{ at, speaker, text }` (`at` in ms since the recording began) in
  `<id>.captions.ndjson`. A block is matched to itself across reads by speaker and words in common (it grows, gets
  revised, scrolls off the top, loses its head in a long turn); its words are written once it has been still for 2 s
  or a newer block appears under it; growth after that gives only the new words; a repeat of the same line by the
  same speaker within 30 s is dropped.
- **Leaving**, on the first of: the page says the call is over (the Leave button gone, with "You left the meeting",
  "The meeting has ended", removed, or three reads with no button at all); `due` says `leave`; alone (a people count
  of 1, from the People button or the tiles) for 2 minutes, counted from the booked start at the earliest and, when
  nobody else has come at all, not before 10 minutes past it; 10 minutes past the booked end; 3 hours in; the service
  stopping. The recorder is stopped and its last slice flushed, Leave pressed, Chrome closed.
- **The take**: `PUT take` with `audio`, `captions`, `startedAt` and `endedAt`, tried 5 times (2, 6, 18, 54 s apart;
  once when the service is stopping). Taken: both files deleted, then `done` posted again with why the call ended
  (`alone`, `time_up`, ...). Refused with 409 (called off, skipped): deleted all the same. Anything else: both moved to
  `work/failed/` and `failed: upload` posted. Files a killed run left behind are moved to `work/failed/` at start.
- **The log** (journald): ids, states, details, byte counts, sound levels and people counts; never a title, a link, or
  a word of the captions or the chat (`lib/log.mjs` drops any other field).

`node --test` in `meet/bot` tests the captions diff, the decisions (alone, time up, busy, which meeting), the API
client against a stand-in server (the multipart body, the token, no proxy headers, 409, the retries), the upload's
keep-or-delete, Chrome's switches and the log's filter. Joining a real Meet is tested only by hand.

### The units

| Unit | Runs | |
|---|---|---|
| `glyph-meet-xvfb` | `Xvfb :71 -screen 0 1280x800x24 -nolisten tcp` as `glyph-meet` | enabled; Chrome needs a window, Meet turns headless browsers away |
| `glyph-meet-pulse` | `pulseaudio -n` as `glyph-meet`, one null sink, socket `/run/glyph-meet-pulse/native` | enabled; Chrome plays the meeting to it, the tab capture takes it from there |
| `glyph-meet` | `node /opt/glyph-meet/bot/bot.mjs` as `glyph-meet` | enabled when the token is there; `MemoryMax=3G`, `CPUQuota=200%`, `Nice=5` |
| `glyph-meet-signin` | `node bot.mjs --signin`: a plain Chrome at accounts.google.com | on demand; `Conflicts=glyph-meet` (one Chrome on the profile) |
| `glyph-meet-vnc` | `x11vnc -display :71 -localhost -rfbport 5901`, no password | on demand; loopback only, reached through an SSH tunnel |

PulseAudio is a system unit run as the bot's user rather than PulseAudio's own user unit: a user unit needs a user
manager for a system account (`loginctl enable-linger`) and cannot be ordered against a system unit, and `pulseaudio
--system` is the mode its authors warn against. A server install of Ubuntu has no PipeWire to compete with it.

The bot shares the real `/tmp` with Xvfb (the X socket is `/tmp/.X11-unix/X71`), so it has no `PrivateTmp`; Chrome's
temporary files go to `TMPDIR=/var/lib/glyph-meet/tmp` instead. Chrome keeps its sandbox, which on Ubuntu is built on
unprivileged user namespaces: so no `RestrictNamespaces`, `PrivateUsers` or `SystemCallFilter`, and no
`MemoryDenyWriteExecute` (V8 is a JIT). `NoNewPrivileges` stays: it would break only the setuid fallback.

On Linux both Chromes, the sign-in one and the bot's, run with `--password-store=basic`: a system account has no
keyring, and the profile's cookies must be sealed and opened the same way, or Chrome throws them away. The Mac (the
spike) uses the real keychain instead. Meet's buttons are found by their English names, so Chrome runs with
`--lang=en-US` and Ghost's Google account must be set to English.

The files: `/opt/glyph-meet/bot` (root's; the previous one kept as `bot.prev`), `/opt/glyph-meet/meetctl`,
`/opt/glyph-meet/glyph-meet.env` (`GLYPH_MEET_TOKEN`, root:glyph-meet 0640), `/var/lib/glyph-meet` (0700: `profile/`,
`work/`, `work/failed/`, `tmp/`).

### Setting it up, signing Ghost in, deploying

`GLYPH_MEET_TOKEN` goes in `tauri/.env` first (see "The environment"), and `node scripts/deploy-server.mjs` gives it to
glyph-api. Then, from this Mac (each run is one login on the box; mind the box's limit of three an hour, ten minutes
apart):

1. `node scripts/setup-meet-box.mjs --setup --signin`: packages, Chrome (held), the user, the code, the token, the
   units; and the sign-in browser and VNC started. It prints the OS, glibc, the user-namespace setting and Node, and
   stops if `/usr/bin/node` is older than 18.
2. `ssh -L 5901:localhost:5901 <AFM_DEPLOY_USER>@<AFM_DEPLOY_HOST>` (the script prints it filled in), then
   `vnc://localhost:5901` in Screen Sharing; sign in to Ghost's account in the Chrome there.
3. In that same ssh session: `/opt/glyph-meet/meetctl signin-done`. It closes the browser and VNC, prints
   `SIGNED_IN yes`, and starts the bot. (`node scripts/setup-meet-box.mjs --signin-done` does the same from the Mac,
   for one more login.)

A later deploy of the bot is `node scripts/setup-meet-box.mjs` again: it ships the code, keeps the previous as
`bot.prev`, checks the sign-in and restarts the bot, but restarts nothing while a meeting is under way (then
`/opt/glyph-meet/meetctl restart` after it). `--print` shows what would run without logging in. On the box,
`/opt/glyph-meet/meetctl status | check | restart` and `journalctl -u glyph-meet`. Chrome is held: to move it on,
`sudo apt-mark unhold google-chrome-stable && sudo apt-get install --only-upgrade google-chrome-stable && sudo
apt-mark hold google-chrome-stable`, then a test call. Rollback: `sudo rm -rf /opt/glyph-meet/bot && sudo mv
/opt/glyph-meet/bot.prev /opt/glyph-meet/bot && /opt/glyph-meet/meetctl restart`.

## On the device

The app's half (lib/meet). The device opens each take and writes the meeting up itself, as it writes up a meeting
recorded on it: summaries on the device, never on the server.

### The step of a sync pass

`syncMeet` (lib/meet/meet_in.dart) is a step of every pass (lib/sync/engine.dart `meetIn`), after the mail's and before
the notes, so the notes step sends the new note on. It runs on every device; it is quiet against a service with no
meeting routes. For each take in `GET meet/takes`:

1. The note's id is made from the take's (`meetNoteId`, as a mail's from the mail's). A note already there was filed
   before, here or on another device: the take only goes from the service.
2. `GET meet/takes/{id}` (raw), opened with the list's `wrapped` and the account's pair (`openSealedTake`), read as
   `GMT1` (lib/meet/gmt.dart). One that will not open is left for a newer app.
3. The sound is kept as the note's recording (`MeetDevice.keepTape`, below). A device that cannot keep it (an iPhone,
   which records nothing; a sound it cannot read) leaves the take on the service for a day for one that can, then files
   it from the captions alone. A take with no sound is filed from its captions at once.
4. The note is written through the door a note from another device comes in by (`LocalNotes.apply`), with the
   recording's length; marked a meeting in `prefs.meetings` ({noteId: startedAt}), so Sync meeting recordings governs
   its audio as it does a recorded meeting's (on unless turned off, since 2026-10-23, GHST-112: the audio goes to
   the account's other devices, and filed in a team's folder to every member); the meeting it was of kept against it
   in the synced preference `meetingNotes` ({meetingId: noteId}, in `Preferences.more`), so Settings › Meetings opens
   it; and its write-up asked for (`MeetDevice.writeUp`).
5. Only then `DELETE meet/takes/{id}`.

Every pass also names the speakers of a meeting whose write-up has come (the list `glyph-meet-pending` in the
device's storage), below.

### The note

Filed on a device that will write it up:

```markdown
# Roadmap review, Q4

Ghost was in this meeting on 18 Oct, 14:00 to 14:45. It is being written up on your device.

## Captions

**Sam Lee (0:04):** Good morning everyone. Let's start with the launch checklist.

**Daniel (0:15):** Thanks. The pricing page is drafted.
```

The title is the invite's, or `Meeting, 18 Oct 14:00` (lib/capture/meeting.dart `meetingTitle`) with none. The
captions wait under `## Captions` rather than `## Transcript` because the write-up takes words already under
`## Transcript` as a transcript the person corrected (write_up.rs `kept_transcript`) and would summarise them instead of
listening. The write-up then appends `## Transcript` with Whisper's words and keeps its timed phrases beside the note;
the next pass gives each phrase the speaker whose caption turn overlaps it longest (lib/meet/speakers.dart: a turn runs
from a speaker's first caption to the next speaker's, moved a second earlier for the captions' lag; a phrase no turn
overlaps takes the nearest turn's speaker within four seconds, or none), writes the transcript as `**Name:** words`
paragraphs, drops `## Captions` and the "being written up" words, and the summary lands above as any meeting's does
(lib/ai/summaries.dart, a native job). The turns are read back from the note itself, so whichever of the account's
devices wrote it up can name them.

Filed from the captions alone, the captions are the transcript at once, `**Name:** words`, and the first line says why
("This is from Meet's captions: the recording could not be kept on this device.", or "No sound came with it").

### The sound: transcribing a file

The core's write-up (tauri/src-tauri/src/write_up.rs, compiled into the Flutter core with the `voice` feature)
already transcribes a FILE: `recordings/<note id>.wav`, 16 kHz mono 16-bit PCM, its speech spans found and each read
from disk and put through Whisper (small.en, or base.en where only that is here). It never needed the microphone. So
a take's sound only has to become that file:

1. Dart reads the WebM (lib/meet/webm.dart: EBML entered rather than skipped, so a live recording's Segment and
   Clusters of unknown size read as known ones; the first `A_OPUS` track; all three lacings) off the UI isolate, and
   writes its Opus packets to a file, `GOP1`: the magic, the head's length (u32 BE), the head as JSON `{v, channels,
   preSkip, codecDelayNs, seekPreRollNs, packets, samples, headBytes}`, the `OpusHead`, then each packet as its length
   (u32 BE), its samples at 48 kHz (u32 BE) and its bytes.
2. `ghost_md/meet_audio` `opusToWav {packets, wav}` -> `{ms}` decodes them with the platform's own Opus decoder, mixes
   to mono, takes 48 kHz to 16 kHz and writes the WAV a chunk at a time (an hour is never held whole):
   - **macOS**: macos/Runner/MeetAudio.swift, `AVAudioConverter` from `kAudioFormatOpus`, then a second converter
     for the rate at its best quality. Checked against ffmpeg on test/meet/fixtures/two_tones.webm: correlation
     0.9996, 2.5 ms apart, 11 ms longer (ffmpeg trims the last packet's padding). To check it again, outside the app:
     write the fixture's packets with `packedForDecoder(readWebmOpus(bytes))`, then
     `swiftc -O -o decode macos/Runner/MeetAudio.swift main.swift` with a `main.swift` that calls
     `MeetAudio.opusToWav(packets:wav:)`.
   - **Android**: android/…/ghost_md/MeetAudio.kt, MediaCodec's Opus decoder given the `OpusHead`, the codec delay and
     the seek pre-roll as `csd-0`, `csd-1`, `csd-2` (so it drops the pre-skip itself), then a windowed-sinc low-pass
     at 7.2 kHz and every third sample. Compiled against android-36; not yet run on a phone.
   - **iPhone**: nothing (no model, no write-up): the captions path above.
3. The core moves the WAV into place as the note's recording (`CoreFiles.adopt`, the rules a synced recording is kept
   by), and it plays on the note's tape like any meeting's.

The write-up is then asked for as a meeting recorded here asks for it, Write up straight away honoured: on Android
the meeting service's `writeUp` (WorkManager, which keeps to the battery rule itself, and posts its own "written up"
notification as for any meeting); on the Mac the core's `write_up_run`, run by the app (lib/meet/tape.dart
`CoreWriteUps`, one at a time, a hold tried again a minute later), the Mac counting as plugged in. The summary is the
summary queue's native job where Summaries are on; the Mac's queue now reads the core's write-up states and results as
Android's does (lib/root/voice_wiring.dart), so Try again, Write up now and a model arriving ask the Mac's runner.

### Settings › Meetings

A section of its own on the Account card, after Notifications (GHST-110; Matt, 2026-10-23: "Make the meeting section
its own section in settings and move the invite card to the top"). It was a card on Account until then. Settings lists
it for a signed-in account whose service has the meeting routes (`meetingsOffered`), in Simple too; its row reads
"Ghost is booked for N meetings", or "Invite Ghost to a Google Meet". The page is lib/settings/panes/meetings_pane.dart
over lib/meet/ui/meet_card.dart. Since 2026-10-24 (Matt: "remove the meetings stuff from the account page the account
settings page is overwhelming move all google meet related stuff to under the meet section") everything about
meetings is here and nothing on Account. With no Email to a note address yet it says "Ghost is invited by your Email
to a note address. Turn one on below, then invite Ghost here.", over the Email to a note card that turns one on. With
one:

- **Invite Ghost**, first: "Send Ghost to a meeting now", a Meet link sent to `POST meet` after the account's
  encryption key is seen to; then the address with Copy and a refresh icon ("Make a new address"; Matt, 2026-10-24:
  "add a refresh button next to the email so i can regeenrate the email"), which asks "Make a new address?" in the
  card, with Make it and Cancel, then runs `POST mail/address` (the old address takes no more invites or mail) and
  draws the new one. The only place the address is shown. What a press did, or why it failed, is said under it.
- **Ghost in meetings**: what Ghost does; the meetings from `GET meet` with their state in words (Booked, Joining, In
  the meeting, Leaving, Written up / Being written up / Not written up yet, Couldn't join: Ghost was signed out of
  Google / nobody let Ghost in / the meeting refused Ghost / …, Skipped, Cancelled), Don't join on one to come and
  Leave now on one Ghost is in (`DELETE meet/{id}`). A meeting whose note is here is pressed to open it (Settings
  shuts; Matt, 2026-10-24: "add the ability to click a meeting to jump to the associated note"): the note kept
  against it (`meetingNotes`), or, for one filed before that was kept, Ghost's note whose recording began while the
  meeting was on (`meetingNoteFor`). Its footer: "The meeting's sound passes through Ghost.md's server while it
  records, sealed to your account as it arrives; it is written up on your device."
- **Email to a note**: what a mail to the address becomes, Turn off, and what the server sees (mail_card.dart).
  Account keeps a single row pointing here. A service with no meeting routes has no Meetings, and keeps the whole card
  on Account.
- **Recordings**: Sync meeting recordings, and how many recordings stayed on this phone (not on an iPhone).

Decided: "the invite card" read as the ways to invite Ghost, the link and the address together, so both are on top.

### Home › Upcoming meetings

lib/home/home_meetings.dart (Matt, 2026-10-23: "adding a home page section for upcoming meetings"): a card among home's
notices, on the advanced page and Simple's, listing the meetings still to come or going on (`booked`, `joining`,
`in_call`, not yet past their end), the soonest first, four at most: a booked one with when it is ("Today, 14:00"),
one Ghost is joining or in with where it stands ("In the meeting"). Nothing at all when there are none or the service
has no meeting routes. Its foot, **Meetings**, opens Settings › Meetings. Tests: test/meet/home_meetings_test.dart.
