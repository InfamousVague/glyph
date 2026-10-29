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
| Ring | In the header, beside You, in every header version: one arc per running job in its colour. Gone when idle; one bloom when all finish. A still red dot when something needs you. |
| Tray | A card hanging under the ring (as History's does); a sheet on a phone. Live rows (icon, title, live line, progress, Stop/Open), then **Today** ("3 summaries, 12 banners, 40 notes synced, 1 failed"), then **Past 7 days** behind More. |
| In place | Banner shimmer where the banner will land; "Writing the summary…" streaming into the meeting note; per-note sync marks (blue arrow → tick) in lists and the note's header; upload progress on share rows, pictures and recordings. |
| Results | A result chip slides in from the edge ("Banner ready · View"), replacing most toasts; a batch gives one chip. |
| Other devices | In the tray, labelled with the device ("Writing on your Mac", its icon); in the ring, slightly dimmed. |
| Cost | Jobs over about 20 credits or 2 minutes ask first ("12 banners · ~72 Lovart credits · ~4 min", Start / Cancel); smaller ones just run, with the estimate in the tray and a live credit count. |
| Failures | Red row with the cause in plain words and one fix (Top up, Sign in again, Retry); network blips retry on their own. |
| Sound | A soft chime and a light tap when a job the person started and that ran over ~30 s finishes; nothing for sync or small jobs; off with the app's sounds setting. |
| OS surfaces | Android progress notifications (and Samsung's Now Bar where offered) for recording, write-ups, banner runs and uploads; the Mac's Dock icon progress ring and badge; a Mac menu bar item with the ring and a mini tray; iPhone Live Activities (Dynamic Island, lock screen) for write-ups and uploads. |
| Simple mode | The ring, tray, chips and in-place marks all show; the tray's Past 7 days and per-device detail sit behind More. |

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
log), `attempt` / `retryAt`, `shownHere` (the person is looking at what it makes: no chip).

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
  bloom does; the bar listens to it), `ActivityRingPainter` / `RingArc`.
- `activity_tray.dart`: `ActivityTray`, `ActivityRow`, `JobBar`, `TrayButton`.
- `activity_chips.dart`: `ActivityChips` (mounted by the shell under the header), `ActivityChip.of(job)`.
- `activity_cost.dart`: `askJobCost(context, estimate, title:)`, true at once under 20 credits and 2 minutes.
- `activity_chime.dart`: `startActivityChime()`, `SoundEvent.jobDone` and a light tap, off with interface sounds.

### The jobs on it, and where each registers

| Job id | Kind | Where |
|---|---|---|
| `lovart-banners` (and `lovart-banners@<device>` elsewhere) | images | `lib/plugins/lovart/banner_run.dart` `_run`, `tellElsewhere` |
| `banner:<note>` | images | `lib/plugins/lovart/banners.dart` `make` (outside a run), `makeBanner` |
| `lovart-cue:…`, `lovart-cues:<note>`, `lovart-inspiration:<note>` | images | `lib/plugins/lovart/lovart.dart`, `meetings.dart` (`making.dart` `lovartPictureJob`) |
| `summary:<note>` (and another device's claim) | ai | `lib/ai/summaries.dart` `_lookOnce`, `_summarize`; `lib/ai/summary_handoff.dart` `jobsElsewhere` |
| `sync` | sync | `lib/sync/engine.dart` `_once`, `_run` (own and team passes; shown after 1 s or once it moves something) |
| `meeting-recording`, `write-up:<note>` | audio | `lib/capture/meeting_live.dart` `followOnRecord`; `lib/meet/tape.dart` `CoreWriteUps` |
| `refine:<note>`, `refine-model` | audio, downloads | `lib/capture/refine.dart` |
| `voice-over:<note>` | audio | `lib/plugins/elevenlabs/voice_over.dart` `makeVoiceOver` |
| `share-audio:<note>` | audio | `lib/share/share.dart` `_sendAudio` |
| `model:<id>`, `voice-model`, `update` | downloads | `lib/ai/backend.dart` `ModelsController.fetch`; `lib/capture/voice_model.dart`; `lib/core/updates.dart` `installApk` |
| `slack:<note>`, `slack-post:<note>` | meetings | `lib/plugins/slack/meetings.dart` `_try`; `slack.dart` `_post` |
| `fetch:<plugin>` | sync | `lib/plugins/details_cache.dart` (Notion, GitHub; shown after 1 s, not logged) |
| `calendar:ical`, `calendar:google` | sync | `lib/calendar/calendar.dart` (shown after 1 s, not logged) |
| `meet:<booking>` | meetings | `lib/meet/meet_in.dart` `meetBotJobs` (the bot's, elsewhere) |

Toasts replaced by chips: the banner run's end (`ghost_root.dart` `_bannerRunEnded`) and "Summarized “title”" with
Open (`root_voice.dart`).
