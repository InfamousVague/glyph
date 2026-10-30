# Activity: what the app is doing, shown

Matt, 2026-10-29: "Let's theorize how we can improve the flow of things in the app, better show users what background
processes are happening with vivid colors and iconography and more", then "Do them all", with his answers to each
choice below. Built straight (no mockup, no developer switch) and shipped all at once.

## The decisions

| Item | Choice |
|---|---|
| Colour | Vivid by default while work runs; the app is monochrome at rest. A **Calm** setting (Settings › Appearance) turns the colours to ink and keeps the motion. |
| Palette | Drawn from the Market's plugin tile gradients, so a plugin's work wears its tile's colour (Lovart amber-pink, Meet orange). Light and dark tuned for contrast. |
| Kinds | Sync blue, AI writing violet, images amber-pink, audio teal, meetings orange, downloads/updates green, needs-you red (still), waiting grey (dimmed, still). |
| Motion | Gentle and purposeful: reels turn (audio), the brush draws (images), arrows circle (sync), the sparkle shimmers (AI), a people glyph pulses (meetings), a ring fills (downloads). Reduced motion stops it. |
| The record | One record of running work: `lib/core/background_jobs.dart` grows from the device hint into the app's registry. Every job: kind, title, state (queued, running, waiting, done, failed), progress (fraction or indeterminate), what it waits on (Wi-Fi, charger, credits, your Mac, sign-in), Stop, Open result, device it runs on. |
| Jobs on it | All of them: banners, summaries and write-ups, own and team sync, recording, transcription and Better words, share uploads, model and update downloads, Slack posts, ElevenLabs read-alouds, Notion/GitHub/Calendar fetches, the Meet/Zoom bot. |
| Ring | In the header, beside You, in every header version: one arc per running job in its colour. Always there; grey when idle (a thin ring in the ink's grey, Calm too, still a button that opens the tray: "Nothing running now.", Today, Past 7 days). One bloom when all finish, then grey again. A still red dot when something needs you. A sync's arc fills as it goes and never sweeps. |
| Tray | A card hanging under the ring (as History's does); a sheet on a phone. Live rows (icon, title, live line, progress, Stop/Open), then **Today** ("3 summaries, 12 banners, 40 notes synced, 1 failed"), then **Past 7 days** behind More. |
| In place | Banner shimmer where the banner will land; "Writing the summary…" streaming into the meeting note; per-note sync marks (blue arrow → tick) in lists and the note's header; upload progress on share rows, pictures and recordings. |
| Results | A result chip slides in from the edge ("Banner ready · View"), replacing most toasts; a batch gives one chip. |
| Other devices | In the tray, labelled with the device ("Writing on your Mac", its icon); in the ring, slightly dimmed. |
| Cost | Jobs over about 20 credits or 2 minutes ask first ("12 banners · ~72 Lovart credits · ~4 min", Start / Cancel); smaller ones just run, with the estimate in the tray and a live credit count. |
| Failures | Red row with the cause in plain words and one fix (Top up, Sign in again, Retry); network blips retry on their own. |
| Sound | A soft chime and a light tap when a job the person started and that ran over ~30 s finishes; nothing for sync or small jobs; off with the app's sounds setting. |
| OS surfaces | Android progress notifications (and Samsung's Now Bar where offered) for recording, write-ups, banner runs and uploads; the Mac's Dock icon progress ring and badge; a Mac menu bar item with the ring and a mini tray; iPhone Live Activities (Dynamic Island, lock screen) for write-ups and uploads. |
| Updates (2026-10-30) | The app's own updates in the tray alone (Matt: "show the updates stuff in the activity drawer only now with a badge and when an update is available show the badge"): a green badge with an up arrow on the ring while one waits, idle or not; an **Update** section first in the tray; no home card, no chip, no toast. Below. |
| Plugin marks (2026-10-30) | A plugin's work wears its vendor's mark in place of its kind's glyph (Matt: "use plugin vendor logo icons for activity updates related to plugins"), the kind's colour still its accent. Below. |
| Simple mode | The ring, tray, chips and in-place marks all show; the tray's Past 7 days and per-device detail sit behind More. On simple mode's plain pages, which have no bar, the ring floats at the top right only while something runs: there is no bar for an idle one to sit in. |

## The API

Built 2026-10-29. The record is `lib/core/background_jobs.dart` (with `lib/core/activity_log.dart`); what draws it is
`lib/activity/`. Everything below is what the in-place marks and the OS surfaces build on: they read the record, they
never keep a list of jobs of their own.

### The record: `activity`

`Activity activity` is the app's one record (a test swaps it with `useActivity(Activity(clock: …, store: …))` and puts
a fresh one back). It is a `ValueListenable<List<Job>>`:

- `activity.value`: the jobs to show, this device's in the order begun, then the other devices' (`Job.here` false).
  Live ones (`queued`, `running`, `waiting`) and failed ones until dismissed or begun again. A job begun with
  `showAfter` is left out until it has run that long or is `show()`n.
- `activity.live`, `activity.idle`, `activity.needsYou` (the red dot), `activity[id]`, `activity.handle(id)`.
- `activity.events`: a broadcast `Stream<JobEvent>`, `started` / `changed` / `ended` (the job as it is after) and
  `allDone` (the last live job ended well: the bloom). A job kept back by `showAfter` is told of only once shown, and
  one that ends unseen is never told of (a sync pass that moved nothing). **The OS surfaces hear this.**
- `activity.blooms` (counts the blooms), `activity.lastEnded`, `activity.log` (below), `activity.onChime`.
- `activity.update` (`UpdateOffer?`): the app's own update, told by `Updates` (lib/core/updates.dart `offer`) at every
  change; `activity.showUpdate()` opens the tray at its Update section, `updateWanted` / `updateSeen()` while it is up.
  Below, "The app's updates".
- `activity.elsewhere(source, jobs)`: what the account's other devices (or the meeting bot) are doing, as `source`
  knows it; each call replaces that source's list. Never logged here. Sources today: `summary-handoff`,
  `lovart-claim`, `meet-bot`.

### A job

`Job` is a value: `id` (the same for every pass of the same work), `kind` (`JobKind.sync | ai | images | audio |
meetings | downloads`), `title`, `state` (`JobState.queued | running | waiting | done | failed`), `fraction` (0–1, or
null for an indeterminate bar), `steps` ("2 of 3 parts"), `line` (what it does now), `waitingOn` (`WaitingOn.wifi |
charger | credits | otherDevice | signIn | network | model | turn`), `onStop`, `onOpen`, `device` / `deviceName` (null
is this device), `placeWords`, `startedAt` / `endedAt` / `took`, `personStarted`, `estimate` (`JobEstimate`: credits,
provider, duration, count), `spent` (credits so far), `cause` and `fix` (`JobFix`: Top up, Sign in again, Retry,
Open), `result` (`JobResult`: the chip's words, its action, `onOpen`), `tally` (`JobTally`, what it counts for in the
log), `attempt` / `retryAt`, `shownHere` (the person is looking at what it makes: no chip), `plugin` (the manifest id of
the plugin whose work it is, said where the job begins: below, "Plugin marks"). The log's rows keep `plugin` too.

Derived: `look` (`JobLook`, the kind while running, `needsYou` for a failure or a wait only the person can end,
`waiting` for any other wait, dimmed and still), `liveLine` ("Writing the summary, 2 of 3 parts", "Waiting for
Wi-Fi", the cause), `deviceWords` ("on your Mac").

### Running a job

```dart
final job = activity.begin('summary:$noteId', kind: JobKind.ai, title: 'Summary of Standup',
    line: 'Writing the summary', onOpen: activityRoutes.noteOpener(noteId), shownHere: activityRoutes.noteShown(noteId));
job.progress(done: 2, total: 3, steps: '2 of 3 parts');   // or fraction:, line:
job.waiting(WaitingOn.wifi);                              // dimmed, still; progress() runs it again
job.update(spent: 30, onStop: stop);
job.done(result: JobResult('Summarized “Standup”', action: 'Open', onOpen: …), tally: const JobTally('summary', 'summaries'));
job.failed('Lovart is out of credits', fix: activityRoutes.topUp(Uri.parse(lovartBillingUrl)));
job.stopped();                                            // went quietly: a Stop, a hold, a turn tried later
```

- `begin` on a live id is the same job (its words told again); on a failed one it starts afresh.
- A handle whose job has ended does nothing, so the code that runs it never asks.
- `showAfter: Duration` keeps it out of sight until then (a Timer, cancelled as it ends); `job.show()` shows it now.
- `done(quiet: true)` counts it and gives no chip and no chime.
- `retrying(job, attempt, backoff: blipBackoff)` runs `attempt`, and after a network blip (`isNetworkBlip`) says
  "Trying again in 8 s" (waiting on the network) and tries again at 2, 8 and 30 s; the last failure, or anything else,
  is thrown on for the caller to `failed`.
- `activityRoutes` (told by the root): `openNote`, `showing`, `openLink`, `openPlugin`, and `noteOpener(id)`,
  `noteShown(id)`, `topUp(uri)`, `signIn(pluginId)` built on them, so code deep in a plugin need not know how a note
  is opened.

- `job.write(sofar)` tells the words a job has written so far (Claude streaming a meeting's summary, the phone's model's
  partial text); `activity.wordsOf(id)` is a `ValueListenable<String>` of them, '' until it writes and once it ends.
  Kept off the `Job`: a change every few letters is never told to the ring, the tray, `events` or the OS surfaces.

### The app's updates

Matt, 2026-10-30: "show the updates stuff in the activity drawer only now with a badge and when an update is available
show the badge". The tray is the one place the app speaks of its own updates.

- **The record.** `Updates` (lib/core/updates.dart) tells `activity.update` an `UpdateOffer` at every change: its
  `stage` (`notChecked`, `checking`, `upToDate`, `checkFailed`, then the waiting ones, `available`, `downloading`,
  `installing`, `needsPermission`, `ready`, `restarting`, `failed`), the version offered and running, `notes` (what's
  new, where the release says: the core's `update_read` answer carries no such field today, so none is shown yet), why
  it failed, and Install / Restart / Check. `badge` is a waiting stage. A disposed `Updates` takes back its own.
- **The badge.** While `badge` holds the ring wears a small dot in the downloads' green with an up arrow at its top end
  corner (`activity-ring:update`), on the idle grey ring too; Calm draws it in ink, simple mode the same, and simple
  mode's plain pages float the ring for it. Where something needs the person the red dot takes the corner and the
  update says itself in the tray. The ring's label adds "update available".
- **The tray's Update section** (`activity_tray.dart` `UpdateSection`, `activity-tray:update`) is the tray's first
  thing while the badge is up: "Ghost.md 2.3.86 is ready", what's new, and its one action (Install; Open while Android's
  installer is put away; Restart to update on the Mac once the new app is in place). The download is the `update` job,
  drawn in the section as its own row with its bar (not again among the rest); a failure is that row red with Retry
  (a meeting being recorded, a refused installer or restart: each fails the job, so the ring's red dot shows). The job
  never gives a chip (`shownHere` true): the update is the tray's to say.
- **Settings › About** keeps the version, its Updates row ("Ghost.md 2.3.86 is waiting in Activity.") and Check for
  updates, which looks again, shuts Settings and opens the tray at the section (`activity.showUpdate()`), which then
  says where the check stands even with nothing waiting ("Ghost.md 2.3.85 is up to date"). About's own Install and
  Restart to update are gone.
- **Gone**: the holographic update card above the notes and in the sidebar (lib/notes/notices.dart `UpdateNotice`),
  and the download's "The update is ready · Restart" chip. **Kept**: the launch screen's line of the check it runs as
  the app opens ("Checking for updates", "Ghost.md 2.3.86 is out", "Updated to Ghost.md 2.3.86"), which is the
  launch's checklist rather than an announcement; and the OS surfaces of the download job (an Android progress
  notification once it has run 10 s, the Mac's Dock ring and menu bar row), which show any job. There is no other OS
  surface for updates: the phone's own notifier (`UpdateCheckWorker.kt`) was never ported, and the Mac has no update
  prompt of its own.

### Plugin marks

Matt, 2026-10-30: "use plugin vendor logo icons for activity updates related to plugins". A job begun with `plugin:`
(`Job.plugin`, the plugin's manifest id) wears that plugin's mark in place of its kind's glyph (lib/activity/
job_mark.dart `JobMark`, drawn by `JobGlyph` where it is given `plugin`): its tray row, its line in Today and the Past
7 days, its result chip (where the dot was) and the ring's middle while it leads. The kind's colour stays its accent:
the row's wash, its bar, the ring's arc, the chip's rim. Which mark is lib/plugins/brands.dart's, drawn as the Market's
badge draws it: in the brand's colour where that stands out from the paper (`brandInkOn`), else the ink; Google Meet's
white on its tile where the row has one (the tray's 30 px round), else its mark; a plugin with no mark (Slack, OpenAI,
Aster, Zoom's camera, Custom AI) its own glyph in the kind's colour. Calm draws them in ink. A waiting job's mark is
dimmed; a job that needs the person keeps the still red dot whoever's it is; a failed chip keeps its red dot. A build
with `GHOST_STORE_NEUTRAL=true` (`brandMarksShown` false) draws the kind's glyph for every job.

The OS surfaces keep the kinds' glyphs: Android's notifications draw `res/drawable/ghost_job_*` and the Mac's menu bar
its own symbols, and the marks are Dart path data (lib/art/brand_marks.g.dart) with no drawable or image on either side
to hand them.

### In place

Built 2026-10-29, reading the record and the sync's own bookkeeping, never a list of their own:

- **Banner shimmer** (`lib/activity/banner_shimmer.dart`, drawn by `lib/note/note_banner.dart` `NoteBannerView`): while
  `lovartBannerMaking` holds the note (one made alone or in a notebook's run, whose banners are not jobs of their own)
  or its `banner:<note>` job is live, a band at the banner's shape in the images' colour, a sheen sweeping and the brush
  stroke drawing; the band fades away over the picture as it lands. Cards in the lists draw no banners, so none there.
- **Summary writing** (`lib/editor/ai/summary_writing.dart`, an editor extension the note's screen adds in
  `lib/root/note_desk.dart`): while `summary:<note>` is live (here or another device's) and the note has no
  `## Summary`, a block at `summaryPlace` says "Writing the summary…" with the sparkle, the job's `steps` and
  `deviceWords`, and `wordsOf` streaming in. A decoration only: the note's words and their sync are never touched.
- **Sync marks** (`lib/sync/sync_marks.dart` `noteSyncMarks`, drawn by `lib/activity/sync_mark.dart` `NoteSyncMarked`
  in the cards, the icon view's tiles, the sidebar's rows and the tabs): waiting is the account's fingerprint
  (`SyncState.notes`, told by the engine as it reads and saves it) against the note's own `mark`, or for a team's note
  the channel's word (`teamSeen` in `lib/team/sync.dart` `_push`); `sent` (a tick for 1.6 s) and `failed` (red, the
  reason on hover or a long press) come from `_send` / `_sendCounted` and the channel. Nothing signed out, with Local
  only, or for a note live with another device.
- **Uploads**: a share's recording reads `share-audio:<note>` (`lib/share/ui/share_rows.dart`, a `JobBar` under the
  row's line); a picture or a recording going (`noteSyncMarks.sending`, told by `sendFile` in `lib/sync/notes.dart`)
  is `FileSendingBar` along the picture's foot (`lib/editor/media/images.dart` `KeptPicture`) and under the note's tape
  (`lib/tapes/note_tape.dart`).

### The log

`activity.log` (`ActivityLog`, a `ChangeNotifier`): kept on this device under `glyph-activity` in the stored
settings. `today` and `past` (the seven days before, newest first) are `ActivityDay`s: `counts` by tally, `failed`,
`rows` (the last 20 jobs; a sync is a count, never a row) and `words` ("3 summaries, 12 banners, 40 notes synced, 1
failed"). Eight days kept, 12 counts a day at most.

### The device half

`BackgroundJobs` / `ChannelBackgroundJobs` (`ghost_md/jobs`: Android's foreground service, the Mac's App Nap) is as
it was, and still told by the banner run, Lovart's and ElevenLabs' holds and Claude's write-up. What the device says
back on the channel is heard by `JobsHeard` (one handler per channel, so every `ChannelBackgroundJobs.onStop` and the
OS surfaces each hear it; before, the last instance to set the handler took it).

### The OS surfaces

`lib/activity/activity_surfaces.dart` (`ActivitySurfaces`, started by the root with `startActivitySurfaces()`) hears
`activity.events` and tells the device over the same `ghost_md/jobs`:

- `activityLook {calm, menuBarAlways}` first, and as either changes (a device drops what an earlier run left then);
- `activity {event, job?, jobs}`: `event` is `started`, `changed`, `ended` or `allDone`; `job` is `surfaceJob(job)`
  (`id`, `kind`, `look`, `state`, `title`, `line` (the live line), `fraction`, `steps`, `colour` / `colourDark`
  (0xAARRGGBB, `surfaceColours`, left out in Calm), `stoppable`, `openable`, `here`, `device`, `personStarted`,
  `startedAt` (ms), `cause`, `result`); `jobs` is every job that surface shows now, so a device can always be made
  what it is told. A job's moves are told at most every 500 ms; a change of state, look, title or Stop at once.
- back: `activityStop {id}` (the job's `onStop`) and `activityOpen {id}` (its `onOpen`, or its result's once ended).

Which jobs (`onSurface`): **Android** the banner run, `share-audio:*`, and any job the person started that has run
10 s (`promotable`), never sync nor `meeting-recording` / `write-up:*` (the meeting service's own notification says
those); **the Mac** everything the ring shows, other devices' too, and a failed job until dismissed; **an iPhone**
`write-up:*`, `summary:*` and `share-audio:*`.

- Android (`ActivityNotices.kt`, `ActivityNoticeModel.kt`): one notification per job on the "Activity" channel (low,
  silent), grouped under a summary from two, the kind's glyph (`res/drawable/ghost_job_*`) and colour, a bar, Stop
  (`ActivityStopReceiver`) and a tap that opens the job (`MainActivity.onNewIntent`). API 36 and later:
  `Notification.ProgressStyle`, asked to be promoted (a Live Update: the status bar chip, Samsung's Now Bar; the
  manifest has `POST_PROMOTED_NOTIFICATIONS`); below, an ongoing notification with `setProgress`. A failure is a
  notification with its cause. The foreground service holds the app up by one of these where any shows.
- Mac (`macos/Runner/ActivitySurfaces.swift`): the ring and badge on the Dock icon while work runs; the menu bar's
  ring (while work runs, or always with Settings › Appearance › Activity › Always show in the menu bar,
  `Preferences.menuBarAlways`, which stays on the Mac) and its mini tray: each job, its bar, Stop, Open Ghost.md.
- iPhone (`ios/Runner/JobsChannel.swift`, the `GhostActivity` widget extension in `ios/GhostActivity`, the shared
  `ios/Runner/GhostJobAttributes.swift`): a Live Activity per job, lock screen and Dynamic Island, from iOS 16.2; a
  tap is `ghostmd://activity?id=…`.

### What draws it

- `lib/activity/activity_look.dart`: `jobColour(tokens, look)`, `kindColour`, the `--activity-*` tokens
  (assets/css/app.css; Calm stamps `data-calm` and turns them to ink), `JobGlyph` (moves only while running and the
  device allows motion), `activityMoves(context)`.
- `activity_ring.dart`: `ActivityRing` (key `header:activity`), `activityShown` (true while something shows or the
  bloom does; simple mode's floating ring listens to it, and the ring to end its bloom's tick), `ActivityRingPainter`
  / `RingArc`. The bar always draws the ring (Matt, 2026-10-29: "Keep the activity indicator always showing just have
  it gray put when nothing is happening"): idle, the painter draws its track alone (`idle`, `app-ink-3`, the ink's
  grey, `idleStroke` 1.5) on the arcs' own line, no glyph, nothing moving, labelled "Activity: nothing running". Its room is
  kept in every version: the rows that had none for it give a spare tool or Back and Forward to their ••• where the
  row is a 360 phone's or a narrowed Mac's (`lib/shell/header_toolbar.dart` `HeaderParts.cramped`, `snugRoom`).
- `activity_tray.dart`: `ActivityTray`, `UpdateSection`, `ActivityRow`, `JobBar`, `TrayButton`.
- `job_mark.dart`: `JobMark`, `markedPlugin(id)` (null in a store-shot build), `marksOnTile`, `activityCalm`.
- `activity_chips.dart`: `ActivityChips` (mounted by the shell under the header), `ActivityChip.of(job)`.
- `activity_cost.dart`: `askJobCost(context, estimate, title:)`, true at once under 20 credits and 2 minutes.
- `activity_chime.dart`: `startActivityChime()`, `SoundEvent.jobDone` and a light tap, off with interface sounds.

### The jobs on it, and where each registers

| Job id | Kind | Plugin | Where |
|---|---|---|---|
| `lovart-banners` (and `lovart-banners@<device>` elsewhere) | images | `lovart` | `lib/plugins/lovart/banner_run.dart` `_run`, `bannerJobsElsewhere` |
| `banner:<note>` | images | `lovart` | `lib/plugins/lovart/banners.dart` `make` (outside a run), `makeBanner` |
| `lovart-cue:…`, `lovart-cues:<note>`, `lovart-inspiration:<note>` | images | `lovart` | `lib/plugins/lovart/lovart.dart`, `meetings.dart` (`making.dart` `lovartPictureJob`) |
| `summary:<note>` (and another device's claim) | ai | the provider writing it, `MeetingClaude.pluginId` (`claude`, `openai`, `gemini`, `aster`, `custom-ai`); none for the device's own model, nor for another device's claim, which does not say whose | `lib/ai/summaries.dart` `_lookOnce`, `_summarize`; `lib/ai/summary_handoff.dart` `jobsElsewhere` |
| `sync` | sync | | `lib/sync/engine.dart` `_once`, `_run` (own and team passes; shown after 1 s or once it moves something; its bar fills, below) |
| `meeting-recording`, `write-up:<note>` | audio | | `lib/capture/meeting_live.dart` `followOnRecord`; `lib/meet/tape.dart` `CoreWriteUps` |
| `refine:<note>`, `refine-model` | audio, downloads | | `lib/capture/refine.dart` |
| `voice-over:<note>` | audio | `elevenlabs` | `lib/plugins/elevenlabs/voice_over.dart` `makeVoiceOver` |
| `share-audio:<note>` | audio | | `lib/share/share.dart` `_sendAudio` |
| `model:<id>`, `voice-model`, `update` | downloads | | `lib/ai/backend.dart` `ModelsController.fetch`; `lib/capture/voice_model.dart`; `lib/core/updates.dart` `installApk` (drawn in the tray's Update section, above) |
| `slack:<note>`, `slack-post:<note>` | meetings | `slack` | `lib/plugins/slack/meetings.dart` `_try`; `slack.dart` `_post` |
| `discord:<note>`, `discord-post:<note>` | meetings | `discord` | `lib/plugins/discord/meetings.dart` `_try`; `discord.dart` `_post` (2026-10-30, as Slack's) |
| `fetch:<plugin>` | sync | the plugin's (`notion`, `github`) | `lib/plugins/details_cache.dart` (shown after 1 s, not logged) |
| `calendar:ical`, `calendar:google` | sync | `calendar` for Google's (it wears Google Calendar's mark); none for an iCal address | `lib/calendar/calendar.dart` (shown after 1 s, not logged) |
| `meet:<booking>` | meetings | by the meeting's kind: `google-meet`, `zoom`, `discord` | `lib/meet/meet_in.dart` `meetBotJobs` (the bot's, elsewhere) |

Todoist and Things run no job of their own on the record today; one begun with their id would wear their marks.

**The sync's bar fills, never sweeps** (Matt, 2026-10-29: "Also don't spin the progress bar on the sync just make it
fill as it's being synced"). The passes tell what they find to do and do (`lib/sync/notes.dart` `SyncProgress`, handed
as `SyncContext.progress` and `TeamPass.progress`): the account's feed rows to merge (per page), its notes to send or
delete (found before any is sent), each picture, file or read text sent or fetched; each team's rows taken, the
histories and pictures fetched after them, each recording fetched, each log read, each team note put and each row
deleted. The engine sums them for the rolling job (`SyncCount`): the bar never goes back within the job, and work
found as it goes takes up the room that is left rather than pinning it: each time the count grows, what is left to do
is laid over what is left of the bar, `shown + (1 − shown) × done since / (left then + 1)`, the one more being room kept
for work the pass may still find (the teams' rows after the account's notes). So the bar is under 1 while the pass
runs and fills to 1 as the job ends well (`SyncCount.finish`). Told as more is found and at most once a whole percent as
it goes; the line is "Syncing, 12 of 40" (the tray: Syncing, and "12 of 40" under it). Before anything is counted the
bar is empty at 0. Any job of the sync kind begun with no fraction is at 0 (`Activity.begin`), so the
calendar's and the plugins' fetches never sweep either. Mail, meetings and webhooks filed in a pass are not counted.

Toasts replaced by chips: the banner run's end (`ghost_root.dart` `_bannerRunEnded`) and "Summarized “title”" with
Open (`root_voice.dart`).
