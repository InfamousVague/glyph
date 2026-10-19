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
| `glyph-meet-xvfb` | `Xvfb :99 -screen 0 1280x800x24 -nolisten tcp` as `glyph-meet` | enabled; Chrome needs a window, Meet turns headless browsers away |
| `glyph-meet-pulse` | `pulseaudio -n` as `glyph-meet`, one null sink, socket `/run/glyph-meet-pulse/native` | enabled; Chrome plays the meeting to it, the tab capture takes it from there |
| `glyph-meet` | `node /opt/glyph-meet/bot/bot.mjs` as `glyph-meet` | enabled when the token is there; `MemoryMax=3G`, `CPUQuota=200%`, `Nice=5` |
| `glyph-meet-signin` | `node bot.mjs --signin`: a plain Chrome at accounts.google.com | on demand; `Conflicts=glyph-meet` (one Chrome on the profile) |
| `glyph-meet-vnc` | `x11vnc -display :99 -localhost -rfbport 5901`, no password | on demand; loopback only, reached through an SSH tunnel |

PulseAudio is a system unit run as the bot's user rather than PulseAudio's own user unit: a user unit needs a user
manager for a system account (`loginctl enable-linger`) and cannot be ordered against a system unit, and `pulseaudio
--system` is the mode its authors warn against. A server install of Ubuntu has no PipeWire to compete with it.

The bot shares the real `/tmp` with Xvfb (the X socket is `/tmp/.X11-unix/X99`), so it has no `PrivateTmp`; Chrome's
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
