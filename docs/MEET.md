# Ghost in a Google Meet and Zoom

GHST-106. Matt: "invite Ghost to meetings for it to automatically join". Ghost joins a Google Meet, or a Zoom
(below, "Zoom"; Matt, 2026-10-26), by itself, records
it with the captions Meet shows, and the recording reaches the person who invited it, sealed to their account. This
page is the service's half (`server/src/meet.rs`, `server/src/meet/ics.rs`, `server/src/store/meet.rs`); the bot that
joins is a separate service on the box, and the app's half downloads and opens the recordings. The spike that showed
it can be done is `meet/spike/README.md`.

## Two plugins, one address

Matt, 2026-10-26: "Make sure the Google Meet and the Zoom plugins are two different plugins", and the same day: "I want
settings / meetings to be broken up into three plugins where each zoom, Google meets and discord handle their own
meetings". In the app Ghost in meetings is two plugins (lib/plugins/meetings/), each with its own catalogue entry,
Market listing, switch and page in Settings; Settings › Meetings, the one page every kind shared, is gone. Discord's
calls are the Discord plugin's (docs/DISCORD.md), listed with the same list (`MeetingsList(kind: 'discord')`).

| | Google Meet | Zoom |
|---|---|---|
| id | `google-meet` | `zoom` |
| kind (the service's word) | `meet` | `zoom` |
| icon | Lucide `users` | Lucide `laptop` |
| hue | orange | mint |
| ships | on | on |

**The icons are not the services' marks** (docs/store/, "no third-party brands"), as Slack's hash and Discord's speech
bubble are not theirs; the Lucide set the app carries has no camera, so a group of people for Meet and a laptop, Ghost
joining from a browser, for Zoom.

**Both ship on.** Google Meet is what every account with Ghost in meetings had before it was a plugin, and Zoom is what
Matt asked for the same day. Not on an iPhone, where Ghost in meetings is not offered (the Market says "Android ·
Desktop").

**What a switch governs.**

- **The app**: the plugin's page is listed in Settings (for a signed-in account whose service has the meeting routes,
  in Simple too, as Meetings was), and Join takes that kind: `MeetIn.sendNow` refuses a kind whose plugin is off with
  the service's own words, "Turn on the Zoom plugin to send Ghost to Zoom calls.", without asking it. A link of the
  other kind pasted on a page says which page takes it ("That is a Zoom link. Send it from the Zoom plugin's page.").
- **The service**: invites are booked there, from mail, while no device is awake, so the account keeps which kinds it
  wants (`PUT /api/v1/meet/kinds`, below; `meet_kinds`, one JSON row an account, in the clear, since which services
  Ghost may join says nothing of a meeting; no row is every kind on). An invite whose link is of a kind turned off
  books nothing, and the mail's note ends "Ghost wasn't booked: the Zoom plugin is off. Turn it on in Ghost.md to have
  Ghost join."; an update that moves a booking onto such a link moves it and skips it, with "The Zoom plugin is off.";
  a cancellation is applied whatever the kind. "Join now" with such a link is 400, "Turn on the Zoom plugin to send
  Ghost to Zoom calls.". A series of a kind turned off books no next occurrence: it waits, as it waits for room.
  Turning a kind off skips every booking of it still to come (`skipped`, and `leave` for one Ghost is joining or in,
  the bot reading it and going); turning it on again books those skipped for that reason, while still to come. A skip
  of the person's own, or a cancellation, is not undone.
- **Sending it**: the device sends the switches when one moves (MeetIn hears the registry), and keeps what the service
  has not taken (`glyph-meet-kinds-unsent`) for the next sync pass, which sends it first (lib/meet/meet_kinds.dart).
  Only a switch that moved is sent, never the switches as a pass finds them: a device yet to have the account's
  switches would otherwise send its defaults over a choice made elsewhere.
- **The account's other devices**: the switch travels sealed as Claude's, Slack's and Discord's do
  (lib/sync/connections.dart `syncedSwitches`, `plugin:google-meet`, `plugin:zoom`).
- **The bot**: nothing; it joins what is booked, and nothing of a kind turned off is.
- **Both off**: nothing of meetings is in Settings. The meetings already filed are notes, and stay on the home page's
  shelf of recordings, every kind.

**One address.** An invite is booked by the link in it, so the Email to a note address takes invites of every kind: the
Google Meet and the Zoom pages each show it on their invite card, saying "The same address works for Meet and Zoom
invites.", with Copy, a name of one's own and a new address, and a change on either is the other's. Email to a note
itself (what a mail becomes, Turn off) is Account's card again, whole, as it was before 2026-10-24.

A link from before to Settings › Meetings (`meetings`) lands on the Google Meet page, or Zoom's where only Zoom is on,
or the Market with neither; its Post to Slack and Post to Discord land on those plugins' pages, where the two sections
are now (lib/settings/settings_sections.dart `meetingsLanding`).

## How a meeting is booked

1. The person adds their mail-to-note address (`sneaky_siren33@in.ghostmarkdown.com`, or a name of their own such as `matt@…`, `tauri/docs/MAIL.md`)
   as a guest on a Google Calendar event. Nothing new to turn on: it is the address they already have.
2. Google mails the invitation there. The mail becomes a note as any mail does, and in the same request the service
   reads its calendar part - the `text/calendar` alternative, or the `invite.ics` attachment; Google sends both, and
   they are read once - and books Ghost for the meeting.
3. Or a device says "join this now": `POST /api/v1/meet` with a Meet or Zoom link books Ghost from now for two hours.

Only an account with an encryption key gets bookings (the recording is sealed to it), and only Google Meet links
(`https://meet.google.com/abc-defg-hij`, from `X-GOOGLE-CONFERENCE`, else the description, the location or `URL`)
and Zoom links (`https://<host>.zoom.us/j/<id>?pwd=…`, `zoom.us/wc/join/<id>`, `zoom.us/my/<name>`; "Zoom", below)
are booked. An account has at most 100 meetings booked and still to come, so an address anyone may mail cannot fill
the bot's day.

### Reading the invite

One booking per invite UID (an occurrence of a series is `<UID>#<its start in ms>`, and one changed on its own
`<UID>#<its RECURRENCE-ID in ms>`, the same; a series, below):

| The invite | The booking |
|---|---|
| new, with a Meet or Zoom link, not over | booked |
| a SEQUENCE lower than the one applied | ignored (an old copy arriving late) |
| a newer one | its link, title and times follow the invite; booked again if it had been called off, or if it moves to a new time after it was over, skipped or failed |
| `METHOD:CANCEL` or `STATUS:CANCELLED`, or no Meet or Zoom link any more | `cancelled`; or `leave` if Ghost is in it or on its way |

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
- **Stopped by the person** ("Stop joining" on Settings › Meetings, `DELETE /api/v1/meet/series/{id}`; Matt,
  2026-10-24: "show recurring meetings in the meetings UI"): each occurrence still to come is `cancelled` ("You asked
  Ghost to stop joining this meeting."), the one Ghost is joining or in is `leave`, and the past ones and their takes
  are left as they are. The series' row is marked `stopped` (`meet_bookings.stopped`) and loses its title and link at
  once, and is kept for as long as its rule runs, moved along the rule booking nothing, so that an update of the invite
  - a higher SEQUENCE, one occurrence changed on its own, the event moved or given a new link - finds it stopped and
  books nothing. Such an update still brings the rule up to date (it is what the row is moved along and ended by), and
  a cancellation or an end (COUNT, UNTIL) makes it `cancelled` or `done`, swept as any series. Invited afresh - a new
  Calendar event, so a new UID - it is a new series, and booked.
- **The limit** holds: a new series needs room for its first occurrence, and a series with no room waits, its link
  kept, until there is.

A booking of v1 (one occurrence under the series' UID) becomes that occurrence's own (`<UID>#<ms>`, same id) when the
series is mailed again, and the series is booked beside it.

**One occurrence alone.** The organizer may add Ghost to one occurrence only ("This event"): Google mails a VEVENT
with a RECURRENCE-ID and no RRULE. That is one meeting, booked if it is still to come; mailed after it ended, as
happened to Matt's stand-up on 2026-10-21, it books nothing, and the mail is a note as any mail is.

## Zoom

Matt, 2026-10-26: "While you're at it also consider zoom meetings". Ghost joins a Zoom the way it joins a Meet: booked
from a calendar invite mailed to the address, or by "join now" with a pasted link; the same bot, Chrome and recorder;
the same leave rules, take and note. What differs is how it gets in: **as a guest, by name, through Zoom's web
client**, never signed in to Zoom.

### The links

`server/src/meet/ics.rs` `zoom_url` reads three shapes and books each in one form; anything else is not booked:

| Written | Booked |
|---|---|
| `https://us06web.zoom.us/j/83512345678?pwd=…` (any one name under zoom.us, or none) | `https://us06web.zoom.us/j/83512345678?pwd=…` |
| `https://zoom.us/wc/join/83512345678?pwd=…` | `https://zoom.us/j/83512345678?pwd=…` |
| `https://zoom.us/my/sam.lee` | `https://zoom.us/my/sam.lee` |

The id is nine to eleven digits; the passcode (`pwd`) keeps its case and is the one part of the query kept; a full stop
after a link is the sentence's. Not booked: a webinar (`/w/`), a host's start link (`/s/`, which would sign in as the
host), a host that only ends in zoom.us (`notzoom.us`, `zoom.us.example`), two names under it, more path after the id.
"Join now" checks a typed link whole (`typed_zoom_url`), as a Meet link is checked, and the app checks it first the same
way (lib/meet/meet_in.dart `zoomLink`).

In an invite the link is looked for where a Meet's is: X-GOOGLE-CONFERENCE and RFC 7986's CONFERENCE, then DESCRIPTION,
LOCATION and URL, the first Meet or Zoom link in each, whichever comes first in it. One exception: **a Zoom link in the
location wins over a Meet in the conference**, because Calendar can add a Meet to every event by itself while the
location is where a person puts the room they mean. Read and tested: Zoom's own invite (`PRODID:-//zoom.us//iCalendar
Event//EN`, `METHOD:PUBLISH`, the link in LOCATION and in Zoom's invite text, a VTIMEZONE), a Google Calendar event on
Zoom (no Meet of Google's, the link in the location and the description), an update that moves a meeting from Zoom to
Meet and back (the same booking), and one that takes the link away (`cancelled`, "The invite no longer has a Google
Meet or Zoom link.").

`kind` (`meet` or `zoom`) is read from the link wherever a booking is said: the device's `Meeting` and `Series`, the
bot's `due`, and a take's `GMT1` head (so the note says "Zoom's captions"). Since the two became plugins it is kept too
(`meet_bookings.kind`, filled from the link for rows from before): once the sweep blanks the link the kind stays, so a
meeting over is still listed on its own plugin's page. It is null only for a row blanked before kinds were kept, which
the app lists as Google Meet's, the one kind there was until then.

### The bot in a Zoom

`meet/bot/lib/session.mjs` picks the page by the link (`decide.mjs` `platformOf`): `lib/meet.mjs` for Meet,
`lib/zoom.mjs` for Zoom, the same exports; the browser and the recorder both use are `lib/browser.mjs`. What Zoom's
words mean is `lib/zoomtext.mjs`, tested in `test/zoom.test.mjs`. `bot.mjs` opens only the shapes above
(`isZoomUrl`), and posts `failed: bad_url` for anything else.

1. **The page.** `/j/<id>?pwd=<p>` is opened as the web client, `https://app.zoom.us/wc/join/<id>?pwd=<p>`. A personal
   link is opened as it is, and the web client's page read off where Zoom moves to or its "Join from your browser"
   link (`resolvedWebClientUrl`).
2. **The lobby** (90 s to find Join): a cookie banner answered with the fewest cookies; a dialog's "I Agree", "Got it",
   "Continue" pressed (terms, recording notices: staying is consenting, as for a person); "Continue without microphone
   and camera", Mute and Stop Video if offered; the name box filled with **Ghost (notetaker)**; then **Join**. A
   passcode box with nothing in it, when the link brought no passcode (or Zoom has not taken it in 10 s), is
   `failed: passcode_needed`: Ghost has none to type.
3. **Given up on at once, never answered**: a captcha (`failed: captcha`, by its frame or its words); a sign-in wall
   (`failed: sign_in_required`: Zoom's `/signin`, a company's single sign-on, "authorized attendees only", "Sign in
   to join"); joining from the browser turned off (`failed: no_browser_join`). Also `passcode_wrong`, `invalid_link`,
   `refused` (removed, locked, full), `unsupported_browser`, and `skipped: meeting_ended`.
4. **The waiting room** (or a host not yet there): waited in for `admitMs` (10 minutes), then `failed: not_admitted`.
5. **In the call** when the Leave button is attached. `ready` joins the meeting's sound ("Join Audio by Computer";
   without it the web client plays nothing and the recording is silence), mutes and stops video again, and presses
   the opening notices away. Then the same `announce` line in the chat, captions on, the recorder, as for Meet.
6. **Captions**, where the host lets a participant see them: "Show Captions" on the footer, else the Captions / CC /
   Live Transcript button's "Show captions" / "Show subtitle", else the same under More; a language dialog saved as
   it is. Asked for again every 30 s while none show, as for Meet; Ghost never asks the host to turn them on. Each
   caption's speaker is the name Zoom draws on it, else a `Name: words` line, else the name on the tile Zoom marks as
   speaking, else "Someone"; the blocks go through the same `CaptionTimeline` into `{at, speaker, text}` NDJSON.
   Without captions the take is the sound alone, and the device's write-up has no names to give the transcript.
7. **People**: the number on the Participants button (its accessible name, Zoom's own "particpants" included, or its
   badge), else the video tiles; Ghost counted. The same alone, few-left and overrun rules.
8. **The end**: the Leave button gone with "ended by host", "removed", or Zoom's `/postattendee` or `/wc/leave` page,
   or three reads with no button. Leaving is Leave, then "Leave Meeting" (never "End Meeting for All").

### What the host must allow

- **Guests**: "Only authenticated users can join" off, or Ghost meets a sign-in wall.
- **Joining from the browser**: "Show a Join from your browser link" on (an account setting the host's admin may
  lock), or `no_browser_join`.
- **The passcode in the link**: Zoom's default ("Embed passcode in invite link for one-click join"); with it off,
  `passcode_needed`.
- **The waiting room**: someone lets "Ghost (notetaker)" in within 10 minutes, as for a Meet's "Ask to join".
- **Captions**: "Automated captions" (or a live transcript) on for the meeting, and shown to participants; otherwise
  sound only.
- **Chat**: open to everyone, or the announcement is let go (`announce_skipped`).

### Known limits

- **Not yet run against a live Zoom.** Meet's selectors came from the spike; Zoom's are written from Zoom's
  accessible names and its long-standing wording, defensively, and are the first thing to check in a test call.
- **Zoom may turn the bot away**: its web client watches for automation, can show a captcha to a guest it doubts, and
  changes often. A captcha is never solved: the meeting fails with `captcha` and the person sees "Zoom asked Ghost to
  prove it is a person".
- **The sound needs "Join Audio by Computer"**, and the bot has no microphone (no fake devices, as for Meet). If Zoom
  will not join computer audio without a microphone permission, the recording is silent (the log's `level` reads
  -100s): the fix would be a muted fake microphone, which the spike avoided for Meet; decide after a test call.
- **Speakers** come from captions when Zoom names them, else from the active-speaker tile, which lags a turn now and
  then; a caption block whose speaker changes between reads can be written twice.
- One Chrome profile: a Zoom is joined while signed in to Ghost's Google account. Zoom is not offered it.

### The selectors (lib/zoom.mjs)

| What | Found by |
|---|---|
| Join | button named exactly "Join" |
| Name | textbox named "Your Name"/"Name", else `#input-for-name` |
| Passcode | textbox named "Passcode"/"Password", else `#input-for-pwd` |
| Captcha | `iframe[src*=recaptcha]`, `hcaptcha`, `arkoselabs`, `[id*=captcha]`, or its words |
| No devices | button "Continue without microphone and camera" (or audio/video) |
| Mic, camera | buttons "Mute", "Stop Video" |
| Notices | a dialog's "Got it", "I Agree", "Agree", "Continue", "OK", "I understand", "Not now" (never Close) |
| Cookies | "Reject all", "Decline", "Necessary cookies only" |
| Sound | a dialog's or the footer's "Join Audio by Computer" / "Join Audio" / "Computer Audio" |
| In the call | button named "Leave", else `button.footer__leave-btn`, `button[aria-label^=Leave]` |
| Leave | "Leave", then "Leave Meeting" |
| Chat | button "Chat" / "open the chat pane"; textbox "Type message here…", else a contenteditable in the chat |
| Captions | "Show Captions" / "Show Subtitle"; the "Captions", "CC", "Live Transcript" button; under "More" |
| Caption text | `[aria-label*=caption][aria-live]`, `[class*=live-transcription-subtitle]`, `[class*=subtitle][aria-live]`, `[class*=caption][aria-live]`, `[id*=subtitle]`; a name in `[class*=name]`, `[class*=speaker]` |
| Active speaker | `[class*=speaker-active] [class*=avatar-name]`, `[class*=active-speaker] [class*=name]`, `[class*=speaking] [class*=name]` |
| People | a button whose name or text says "participants" ("particpants"): `[n]` or a number in its name, else its `[class*=counter]` badge; else the tiles |
| Ended | "ended by host", "removed", a `/postattendee` or `/wc/leave` page |

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
| `GET /api/v1/meet` | | `{ meetings: [Meeting], series: [Series], next }`: those not over, and the last 7 days', soonest first, as before pages; `next` the cursor for those older, or null |
| `GET /api/v1/meet?limit=20` | | `{ meetings, series, next }`: every one not over (`endsAt` after now), soonest first, then the first `limit` (1 to 100) of those over, the latest ended first; `next` the cursor for the page after, or null on the last |
| `GET /api/v1/meet?before=<next>&limit=20` | | `{ meetings, next }`: the page of those over after the cursor, in the same order; `limit` 20 when not given. 400 a cursor this list did not give |
| `POST /api/v1/meet` | `{ url, title? }` | `{ meeting: Meeting }`, booked now for 2 h. 400 not a Meet or Zoom link, or one of a kind turned off ("Turn on the Zoom plugin to send Ghost to Zoom calls."), 409 no encryption key yet, 429 100 already to come |
| `DELETE /api/v1/meet/{id}` | | `{ meeting: Meeting }`: `skipped` if it had not started, `leave` if Ghost is joining or in it, as it was otherwise. 404 not the account's |
| `DELETE /api/v1/meet/series/{id}` | | `{ series: { id, stopped: true }, meetings: [Meeting] }`: the series stopped (above), with the occurrences that changed. 404 not the account's, or not a series; a series stopped already answers with none changed |
| `GET /api/v1/meet/takes` | | `{ takes: [{ id, meeting, size, at, wrapped }] }`, oldest first |
| `GET /api/v1/meet/takes/{id}` | | the sealed take, raw `application/octet-stream`; headers `x-glyph-wrapped` (the wrapped key) and `x-glyph-meeting`. 404 not waiting |
| `DELETE /api/v1/meet/takes/{id}` | | 204: taken |
| `GET /api/v1/meet/kinds` | | `{ meet, zoom }`: which kinds Ghost is booked into, each `true` until a device says otherwise |
| `PUT /api/v1/meet/kinds` | `{ meet?, zoom? }` | `{ meet, zoom }` as they stand; a kind not named stays. What is booked of a kind turned off is skipped, of one turned on again booked again ("Two plugins", above). 400 a key that is not a kind, or a value that is not `true` or `false` |

`Meeting` is `{ id, title, url, kind, startsAt, endsAt, state, detail, series? }`; `title`, `url`, `kind` and `detail`
may be null (`title` and `url` are null once swept, and the app says "A meeting"; `kind`, `meet` or `zoom`, is kept
after the link is swept, and null only for a row swept before kinds were kept). `state` is one of `booked`, `joining`,
`in_call`, `leave`, `done`, `failed`, `skipped`, `cancelled`. `series`, in the list only, is the id of the series an
occurrence is of.

`Series` is a series running and not stopped: `{ id, title, kind, rule, time, zone, offset, next, until, count }`. `rule` is
the rule in words, made on the server (`ics::rule_words`): "Daily at 9:30", "Every 3 days at 9:30", "Every weekday at
9:30", "Weekly on Tue and Thu at 11:00", "Every 2 weeks on Mon at 9:30", "Monthly on the 2nd Tuesday at 9:30",
"Monthly on the last Friday at 9:30", "Monthly on the 1st and 15th at 9:30", "Yearly on 15 Jan at 9:30", and
"Repeats" for a rule it cannot say shortly (BYSETPOS, BYHOUR and other parts it does not read, every Tuesday of a
month, ...). The time is DTSTART's wall-clock time, in the 24-hour clock. `time` is that time (`HH:MM`), `zone` the
invite's TZID (null for UTC), `offset` how many minutes that zone is ahead of UTC at the next occurrence: the app names
the zone ("New York time") only where its own clock differs then. `next` is `{ id, startsAt, endsAt, state, joins }`,
the next occurrence not yet over (`joins` false once skipped or called off; `id` null and `state` `waiting` while the
series waits for room under the limit). `until` (ms) and `count` are the rule's, or null.

**Pages.** A cursor is `<its end, ms>:<its id>` of the last meeting of a page; the next page is the meetings over that
come after it in the order (latest end first, then the larger id first), so a meeting ending meanwhile does not move
a page, and two that ended together are neither repeated nor dropped where a page ends between them. The history
reaches back as far as bookings are kept: thirty days. The answer with no `limit` and no `before` is the one an app
from before pages reads, unchanged but for `series` and `next`, which it does not read.

**Which first.** The new app asks `?limit=20`; an older service, which reads no query, answers its one list (no
`series`, no `next`), and the app shows that list as it is, with no recurring group and no Show more. An older app asks
with no query, and the new service answers what it always did.

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
| `GET /api/internal/meet/due` | | `{ meetings: [{ id, url, kind, title, startsAt, endsAt, state, announce }] }`: state `booked`, `joining`, `in_call` or `leave`, from 2 minutes before `startsAt` until 15 minutes after `endsAt`, oldest first. `announce` is the line to post in the meeting's chat. A Discord call's booking (uid `discord:…`, docs/DISCORD_CALLS.md) is never listed: it is the Discord bot's |
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
{ "v": 1, "meeting": "<booking id>", "title": "Roadmap review, Q4", "kind": "meet", "startedAt": 1792159500000,
  "endedAt": 1792163100000, "mime": "audio/webm;codecs=opus", "captionsBytes": 1234, "audioBytes": 15000000 }
```

`title` may be null; `kind` is `meet` or `zoom` (none from a service before Zoom, read as Meet). `startedAt` is the upload's, else the booking's start; `endedAt` the upload's, else the moment it
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
  `https://meet.google.com/<code>` links and the Zoom links above are opened, each by its own page (`session.mjs`,
  "Zoom").
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
  nobody else has come at all, not before 10 minutes past it; after a big group (5 in the call at once, Ghost
  counted), down to Ghost and one more for 2 minutes (`few_left`; Matt, 2026-10-26: "it should leave when it's one of
  the last people in chat after a big group"; the big group read from the People button alone, as a presentation can
  be a tile of its own); 10 minutes past the booked end only when the people cannot be counted (no count read for 3
  minutes, so a read fumbled now and then is not that),
  since a meeting running over is stayed in while it goes on ("it doesn't leave meetings that are running over"); 3
  hours in; the service stopping. The recorder is stopped and its last slice flushed, Leave pressed, Chrome closed.
- **The take**: `PUT take` with `audio`, `captions`, `startedAt` and `endedAt`, tried 5 times (2, 6, 18, 54 s apart;
  once when the service is stopping). Taken: both files deleted, then `done` posted again with why the call ended
  (`alone`, `time_up`, ...). Refused with 409 (called off, skipped): deleted all the same. Anything else: both moved to
  `work/failed/` and `failed: upload` posted. Files a killed run left behind are moved to `work/failed/` at start.
- **The log** (journald): ids, states, details, byte counts, sound levels and people counts; never a title, a link, or
  a word of the captions or the chat (`lib/log.mjs` drops any other field).

`node --test` in `meet/bot` tests the captions diff, the decisions (alone, time up, busy, which meeting), the API
client against a stand-in server (the multipart body, the token, no proxy headers, 409, the retries), the upload's
keep-or-delete, Chrome's switches, the log's filter, and Zoom's links and words (`test/zoom.test.mjs`). Joining a real
Meet or Zoom is tested only by hand.

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

The pass runs at once when the service says a take was kept (Matt, 2026-10-24: "meetings don't load on the phone app
right away I have to wait several minutes for them to sync"): the relay pokes every signed-in device of the account,
`{ t: "poke", what: "take" }`, and the device syncs 400 ms later rather than at its next pass up to five minutes on;
`meet` reads Settings › Meetings' list again, which also reads itself as the page opens when its last read is ten
seconds old or more (tauri/docs/LIVE.md, "Pokes"; lib/live/poke.dart; server/src/live.rs, POKES).

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

### The plugins' pages: Google Meet and Zoom

Settings › Meetings (GHST-110, 2026-10-23 to 2026-10-26) is each meeting plugin's own page now, one a kind
(lib/plugins/meetings/meeting_pane.dart over lib/meet/ui/meet_card.dart; "Two plugins, one address", above). Each is
listed while its plugin is on, for a signed-in account whose service has the meeting routes (`meetingPluginOffered`),
in Simple too; its row reads "Ghost is booked for N meetings" of its kind, or "Invite Ghost to a Google Meet" / "Invite
Ghost to a Zoom call". With no Email to a note address yet the page says "Ghost is invited by your Email to a note
address. Turn one on in Settings › Account, then invite Ghost here.", with a word to Account. With one, in order:

- **Invite Ghost** (`MeetInviteCard`): a link of the page's kind, Join beside it, sent to `POST meet` after the
  account's encryption key is seen to; then the address with Copy, "Choose a name…" and a refresh icon ("Make a new
  address"; Matt, 2026-10-24), which asks "Make a new address?" in the card, then runs `POST mail/address`. Its hint
  says "The same address works for Meet and Zoom invites." What a press did, or why it failed, is said under it.
- **Recurring** (Matt, 2026-10-24: "show recurring meetings in the meetings UI"), where the service lists series of
  the page's kind: a row a series, its rule in words with its zone where the phone's clock differs, how it ends, and
  "Next: Mon 27 Oct". "Stop joining" asks first, then runs `DELETE meet/series/{id}`.
- **Ghost in Google Meet** / **Ghost in Zoom** (`MeetingsList`, the one list for every kind, Discord's too): Check now,
  then the meetings of the page's kind from `GET meet`, their state in words (Booked, Joining, In the meeting, Written
  up / Being written up / Not written up yet, Couldn't join: …, Skipped, Cancelled), Don't join and Leave now. A Zoom
  Ghost could not join says what its host would have to allow. A meeting whose note is here is pressed to open it.
  Those to come first, then those over by day; twenty over at first, and Show more loads on, reading further pages
  (five at most a press) until one brings a meeting of the page's kind, since the service pages every kind together.
  Its footer says where the sound goes, and how long meetings are kept.
- **What the host must allow**, on the Zoom page alone: guests, joining from the browser, the passcode in the link, the
  waiting room, captions (the Zoom section's list, above).
- **Recordings** (Sync meeting recordings, and how many stayed on this phone; not on an iPhone) and **Sorting** (Sort
  meetings into workspaces): about meetings of every kind, one setting each, the same on both pages
  (lib/meet/ui/meeting_settings.dart).

Post to Slack and Post to Discord, which were Settings › Meetings' too, are sections of the Slack and Discord plugins'
own pages.

### Home › Upcoming meetings

lib/home/home_meetings.dart (Matt, 2026-10-23: "adding a home page section for upcoming meetings"): a card among home's
notices, on the advanced page and Simple's, listing the meetings still to come or going on (`booked`, `joining`,
`in_call`, not yet past their end), the soonest first, four at most: a booked one with when it is ("Today, 14:00"),
one Ghost is joining or in with where it stands ("In the meeting"). Nothing at all when there are none or the service
has no meeting routes. Its foot, **Meetings**, opened Settings › Meetings. Taken off home on 2026-10-24 (Matt: "remove the
upcoming meetings from the home page"), with its tests; the shelf of recordings stays, every kind on it. A booked occurrence of a recurring meeting
(the list's `series`) has the repeat mark for its calendar, as on Settings › Meetings. Tests:
test/meet/home_meetings_test.dart, test/meet/meet_recurring_test.dart.
