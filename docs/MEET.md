# Ghost in a Google Meet

GHST-106. Matt: "invite Ghost to meetings for it to automatically join". Ghost joins a Google Meet by itself, records
it with the captions Meet shows, and the recording reaches the person who invited it, sealed to their account. This
page is the service's half (`server/src/meet.rs`, `server/src/meet/ics.rs`, `server/src/store/meet.rs`); the bot that
joins is a separate service on the box, and the app's half downloads and opens the recordings. The spike that showed
it can be done is `meet/spike/README.md`.

## How a meeting is booked

1. The person adds their mail-to-note address (`<16 letters and digits>@in.ghostmarkdown.com`, `tauri/docs/MAIL.md`)
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

One booking per invite UID (an occurrence changed on its own is `<UID>#<its RECURRENCE-ID in ms>`):

| The invite | The booking |
|---|---|
| new, with a Meet link, not over | booked |
| a SEQUENCE lower than the one applied | ignored (an old copy arriving late) |
| a newer one | its link, title and times follow the invite; booked again if it had been called off, or if it moves to a new time after it was over, skipped or failed |
| `METHOD:CANCEL` or `STATUS:CANCELLED`, or no Meet link any more | `cancelled`; or `leave` if Ghost is in it or on its way |

Times: UTC (`…Z`); wall-clock time in a zone, resolved with the invite's own VTIMEZONE block (Google always sends one:
STANDARD and DAYLIGHT, their offsets and yearly rules), or a small table of common IANA names when an invite names a
zone without a block; floating time is read as UTC. All-day events are left out.

Recurring meetings, v1: only the next occurrence that has not ended is booked, expanded in the event's own wall-clock
time (a weekly 9:00 stays at 9:00 across a change of clocks), skipping EXDATEs and occurrences the invite books on
their own. DAILY, WEEKLY, MONTHLY, YEARLY with INTERVAL, COUNT, UNTIL, BYDAY (`2TU`, `-1FR`), BYMONTHDAY and BYMONTH
are read; any other rule books only its first occurrence. The occurrence after is booked when Google mails the invite
again (any change to the event does). Booking every occurrence is the next step.

## What is in the clear, and for how long

The bot has no key, so a booking keeps what joining needs in the clear: the Meet link, the title the app shows, the
start and the end. The organizer and the guest list are read and dropped. **Only until the meeting is done**: the
hourly sweep (with the hook inbox's, `server/src/hooks.rs`) blanks the title and the link an hour after the meeting
ended, marks a booking the bot never finished `failed` (`missed`), and deletes the booking thirty days after it ended.

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
   its audio as it does a recorded meeting's; and its write-up asked for (`MeetDevice.writeUp`).
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

### Settings › Account › Ghost in meetings

lib/meet/ui/meet_card.dart, beside Email to a note and drawn only once that address exists and the service has the
meeting routes; in Simple too (the Account page is one of its sections). It says what Ghost does; the invite address
with Copy ("Add this address as a guest on a Google Calendar invite."); the meetings from `GET meet` with their state
in words (Booked, Joining, In the meeting, Leaving, Written up, Couldn't join: Ghost was signed out of Google / nobody
let Ghost in / the meeting refused Ghost / …, Skipped, Cancelled), Don't join on one to come and Leave now on one Ghost
is in (`DELETE meet/{id}`); and "Send Ghost to a meeting now", a Meet link sent to `POST meet` after the account's
encryption key is seen to. Its footer: "The meeting's sound passes through Ghost.md's server while it records, sealed
to your account as it arrives; it is written up on your device."
