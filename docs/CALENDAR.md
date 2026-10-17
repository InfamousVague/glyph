# Google Calendar in Ghost.md

Matt, 2026-10-17: "add Google calendar support". Two layers, so it works the day it ships and does more once Google is
set up for it.

## 1. Reading a calendar, with nothing to set up

Google Calendar gives every calendar a "Secret address in iCal format" (Settings › the calendar › Integrate
calendar). Pasted into Ghost.md (Settings › Calendar › Add a calendar address), the app fetches it (an `.ics` file,
RFC 5545) when the app opens and every 30 minutes while it is open, and keeps the events on the device. Any calendar
that publishes an iCal address works: iCloud's public link, Outlook's, Fastmail's.

- The address is a secret: it is kept on the device and in the account's sealed settings, never in a note, never
  logged, never sent anywhere but to fetch it.
- Fetching obeys the app's switches: nothing with Local only on.
- Recurring events (RRULE with COUNT/UNTIL/BYDAY, EXDATE) are expanded for the window the app shows: 60 days back,
  400 days ahead.

## 2. Two-way, with Google sign-in

### The server (glyph-api, server/src/google.rs), as Notion's sign-in is (server/src/notion.rs)

    GET  /api/google/start?state&challenge  -> 302 to Google's consent screen
    GET  /api/google/callback?code&state     -> a page to go back to Ghost.md
    POST /api/google/claim  { state, verifier }  -> tokens | 202 pending | 404
    POST /api/google/refresh { refreshToken }    -> tokens

- Configured by GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in the service's environment file; without them every route
  answers 503 `{ "error": "Google sign-in is not set up yet." }` and nothing else changes.
- Scopes: `https://www.googleapis.com/auth/calendar.events` and
  `https://www.googleapis.com/auth/calendar.calendarlist.readonly`; `access_type=offline`, `prompt=consent`, so a
  refresh token comes back.
- Redirect URI: `https://ghostmarkdown.com/api/google/callback`.
- Tokens answer as `{ accessToken, refreshToken?, expiresIn, scope }`. Nothing is written to disk; state held in
  memory for ten minutes, as Notion's.

### The app

- Settings › Calendar › Connect Google Calendar (shown when `start` does not answer 503): opens `start` in the
  browser with a fresh state and PKCE challenge, then claims (polling `claim` every 2 seconds for up to 10 minutes,
  and again when the app comes back to the front). The refresh token is kept as the iCal addresses are.
- Then it reads the account's calendars (calendarList) and the events of the ones ticked (events.list with
  singleEvents=true over the same window), every 15 minutes while open and on opening, replacing any iCal address
  for the same calendar.
- **To-dos on the calendar** (a switch, off until turned on, and a calendar to put them in): every open to-do with a
  due date (`📅 YYYY-MM-DD`) becomes an all-day event titled with the to-do's words, its description a link back
  (`ghostmd://note/<id>`). The event's id is derived from the note id and the to-do's anchor or words, so the same
  to-do updates the same event: a changed date moves it, a ticked or removed to-do deletes it. Events the app did not
  make are never changed.

## Where events show

- A query's new kind, `from: events` (QUERIES.md): records with `title`, `start`, `end`, `allDay`, `location`,
  `calendar`; `show: list | table | calendar | gantt | count`; `where:` on any of them (`start >= today`).
- A tasks calendar (`from: tasks` with `show: calendar`) shows the day's events too, quieter than the to-dos.
- The home page's Today: today's events above the to-dos.

## Ownership

| Part | Where |
| --- | --- |
| Server sign-in | server/src/google.rs (new), wired in server/src/main.rs |
| Calendar sources, store, sync, settings, query kind, home | lib/calendar/* (new), lib/core/query/*, lib/editor/queries/*, lib/settings/panes/*, lib/home/* |
