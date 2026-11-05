# Anonymous usage stats

Matt, 2026-11-04: "setup full posthog metrics across every plugin and every function in the app cleanly … set up all
the posthog dashboard info as well". Product analytics through PostHog, privacy first: on by default, off in one tap,
never content, never who.

## The short of it

- **One front door:** `lib/core/metrics.dart`. Everything goes through `track(MetricEvent, props)`, and every event is
  a member of the `MetricEvent` enum with the props it may carry and their shapes. A prop that is not in its event's
  schema, or not of its shape, is dropped before it is queued (and a debug build asserts).
- **Where it goes:** PostHog, project 710697, **US region** (`https://us.i.posthog.com` for capture,
  `https://us.posthog.com` for the API and dashboards). The env file said EU; the API answered on US, and the file
  was corrected on 2026-11-04.
- **Who:** a random install ID (a v4 UUID made on this device the first time it sends), kept in the device's own
  storage (`glyph-metrics-id`) beside the haptics switch. Never tied to the account, handle, email or organization,
  never sent to glyph-api, never synced (`lib/sync/prefs.dart` does not carry it). A reset (Settings › Developer ›
  Reset, `lib/core/reset.dart`) clears every `glyph-` key, it among them.
- **No person profiles** (`$process_person_profile: false` on every event), **no GeoIP** (`$geoip_disable: true`),
  `$ip` sent as null, and the project's *Discard client IP data* is on. No session replay, no surveys, no autocapture,
  no heatmaps, no console or performance capture, no exception autocapture: all held off on the project by
  `tool/posthog/setup_dashboards.mjs`.

## Why our own client, not posthog_flutter

posthog_flutter wraps the native Android and iOS SDKs. Those bring session replay, autocapture of screens and taps,
person profiles, surveys and feature-flag polling, each of which would have to be held off by configuration on every
platform and checked again on every SDK update, and none of it reaches the web build or behaves the same on macOS.
What the app needs is small: a queue, a batch POST, a retry. `Metrics` is about 400 lines of plain Dart over
PostHog's capture API (`POST <host>/batch/`), using the app's own `Fetcher` (`lib/account/api.dart` `ioFetcher`), so
nothing is sent that this file does not write, and the tests can hold it to that with a fake transport.

## How it goes

- `track` only appends to an in-memory queue. Nothing waits for it and it never throws.
- Sent as one batch every 30 seconds while anything is queued, at once at 20 events, and as the app goes behind
  another (`AppLifecycleListener.onHide` in `lib/root/metrics_wiring.dart`).
- A batch that does not go stays at the head of the queue for the next try. As the app is hidden the queue is written
  to the device (`glyph-metrics-queue`, at most 500 events), so a killed app sends it at the next launch. Each event
  has its own `uuid`, so a batch sent twice is counted once.
- At most 200 of one event (of one plugin's action, of one job's code) a run: a loop never floods.
- **Off when:** the build has no project key (every debug build, and a release built without the env file), the
  switch is off, or Local only is on. Local only also drops what was queued.
- Events tracked before the root starts the real client (the walkthrough opening as the root is made) are held by the
  placeholder, at most 50, and handed over; they go only if the real client sends.

## The switch

Settings › Privacy › **Anonymous usage stats** (`lib/settings/usage_stats.dart`, `UsageStatsRow`), and the same
switch on the walkthrough's privacy page (`GuideUsageStats`, `GuidePage.sync`). Both are `usageStatsPref`
(`glyph-usage-stats`, a `DeviceFlag`, on by default, this device's own). Both show in Simple mode, being a privacy
control, with shorter words. Off: the queue dropped, the ID deleted, nothing more queued (`Metrics.reset`). On again:
a fresh ID at the next event.

## Super properties (on every event)

| Prop | Value |
|---|---|
| `app_version` | `GHOST_VERSION`, e.g. `2.4.19` |
| `app_build` | `GHOST_BUILD` stamp, where the build has one |
| `platform` | `android`, `ios`, `macos` (`web`, `windows`, `linux` exist but send nothing yet) |
| `form_factor` | `phone`, `fold`, `tablet`, `desktop` (from the platform and the window: under 600 short side a phone; Android near-square a Fold's inner screen) |
| `simple` | Simple mode, a bool |
| `lang` | the device's language code alone (`en`), never the region |
| `plugins_on` | the ids of the plugins switched on, sorted, as `,a,b,c,` so a filter "contains `,notion,`" works |
| `plugin_count` | how many |

Plus `distinct_id` (the install ID), `$process_person_profile: false`, `$geoip_disable: true`, `$ip: null`,
`$lib: ghost-md`.

## The events

Buckets: durations `<1s 1-5s 5-30s 30s-2m 2-10m 10-60m >1h`; counts `0 1 2-5 6-20 21-100 101-500 >500`; cold start
`<1s 1-2s 2-4s 4-8s >8s`.

| Event | Props | Sent from |
|---|---|---|
| `app_opened` | `cold` (bool), `start` (cold start bucket) | `lib/root/metrics_wiring.dart`: once at start, and on each resume (`cold: false`). The DAU signal. |
| `screen_viewed` | `screen`: `list notes note capture meeting academy organization collection market tickets` | `lib/shell/app_shell.dart` `_change` |
| `settings_opened` | `pane`: a section id (`theme`, `account`, …) | `lib/settings/settings_screen.dart` `_activeId` |
| `changelog_viewed` | | the same, for the changelog page |
| `note_created` | `source`: `editor`, `capture` | `lib/core/core_library.dart` `createNote` |
| `note_opened` | | `app_shell.dart`, a note's screen with another note than before |
| `note_edited` | | `core_library.dart` `update`, once per note per run (`trackNoteEdited`; the id is hashed in memory and never sent) |
| `note_trashed`, `note_restored`, `note_deleted` | | `core_library.dart` `putInTrash`, `takeFromTrash`, `destroy` |
| `folder_created`, `folder_deleted`, `workspace_created`, `workspace_deleted` | | `lib/core/workspaces.dart` |
| `search_used` | `results` (count bucket) | `lib/home/home_screen.dart`, two seconds after the query stops changing (`trackSearchSoon`); never the query |
| `plugin_enabled`, `plugin_disabled` | `plugin` | `lib/plugins/registry.dart` `setEnabled` (the person's switch; another device's `setSwitch` is not counted) |
| `plugin_active` | `plugin` | `metrics_wiring.dart`, each plugin that is on, once a calendar day |
| `plugin_setup_started` | `plugin` | a plugin's page in Settings entered (`plugin:<id>`) |
| `plugin_setup_finished`, `plugin_disconnected` | `plugin` | `lib/plugins/host.dart` `write`: a plugin's secret going from none to some, or back |
| `plugin_action` | `plugin`, `action` (code), `choice` (an id from a list in the app), `count` (bucket), `ok` (bool) | see below |
| `job_started` | `job` (the job id's code before its first `:`), `kind`, `plugin`, `person` | `lib/core/background_jobs.dart` `Activity.begin`: every background job at once |
| `job_finished`, `job_stopped` | `job`, `kind`, `plugin`, `took` | `Activity._end` |
| `job_failed` | `job`, `kind`, `plugin`, `took`, `fix` (`topUp signIn retry open none`) | `Activity._end`; never the cause's words |
| `recording_started`, `recording_finished` | `mode` (`note`, `meeting`), `took` | `app_shell.dart`, the capture and meeting screens coming and going |
| `ai_used` | `feature: request`, `provider`: `claude openai gemini custom aster local` | each provider's stream: `lib/claude/messages_api.dart`, `lib/plugins/openai/chat_api.dart`, `lib/plugins/gemini/gemini_api.dart`, `lib/ai/native_backend.dart` |
| `ai_image_attached` | `count` (bucket), `provider`: `claude openai gemini custom aster` | `lib/claude/claude_runner.dart` `_sent`: a message sent to the assistant with pictures; never the pictures, their names or their sizes |
| `signed_up`, `signed_in`, `signed_out` | | `lib/account/account.dart` |
| `org_created`, `org_joined` | | `lib/orgs/orgs.dart` `createOrg`, `joinByLink`, an invite accepted |
| `invite_sent` | `way`: `email`, `link`, `handle` | `orgs.dart` |
| `note_shared` | | `lib/share/share.dart` `shareNote` |
| `sync_failed` | `reason`: `http_<status>`, `timeout`, `network`, or the error's type lowercased | `lib/sync/engine.dart` `_endJob` |
| `update_installed` | | `metrics_wiring.dart`: this launch's version is not the last launch's (`glyph-metrics-version`) |
| `setting_changed` | `setting`, and `value` (a word from that setting's list) or `on` (bool) | `metrics_wiring.dart`, the preferences diffed against `settingWords`; a setting not in that map is never named |
| `onboarding_started`, `onboarding_step` (`step`), `onboarding_finished` (`step` it was closed on) | | `lib/guide/guide_state.dart` |
| `error_caught` | `type` (the Dart type's name, without type arguments), `source` (`framework`, `platform`) | `lib/diag/error_log.dart`, once per type per run. A custom event, not `$exception`: no message and no stack leave the device. |

`plugin_action`'s actions, by plugin:

- every plugin: `note_action` (`choice`: the action's id) and `item_action` from the registry; `links_read`
  (`count`) from `lib/plugins/details_cache.dart`, a batch of its links drawn (Figma frames, GitHub pull requests,
  Notion pages).
- `lovart`: `style_chosen` (`choice`: `painterly pencil journal photo`), `model_chosen` (`choice`: the tool id, or
  `auto`), `banner_run_started` (`count`: images asked; × `lovartCreditsPerImage` is the credits).
- `notion`: `import_started` (`choice`: `new`, `again`), `import_finished` / `import_stopped` (`count`),
  `import_failed`, `import_removed` (`count`), `sync_run` (`count`, `ok`; a pass that changed nothing is not sent).

And every plugin's background work is a job, so `job_*` covers: Lovart's header images (`banner`, `lovart-banners`,
`lovart-work`), Notion's import and sync (`notion-import`), Slack and Discord posts (`slack-post`, `slack`,
`discord-post`, `discord`), ElevenLabs voice-overs (`elevenlabs-voice-over`), Cleanup (`cleanup`), the
contradiction finder (`contradictions`), Git backup (`git-backup`), Automations' rules (`rule`), Time tracking
(`timer`), note buttons (`button`), AI summaries and write-ups (`summary`, `write-up`, `claude-write-up`, `refine`),
downloads (`model`, `voice-model`, `refine-model`, `update`), the folder indexes (`index`), the Trash emptied
(`trash-empty`) and the calendar's reads (sync kind: failures only). A sync's passes are not counted, only a failed one.

## What is never sent

Note titles, bodies or ids; file, folder, workspace or organization names; search queries; prompts; URLs; emails;
handles; error messages; Notion, GitHub, Figma, Slack or any other service's ids; the account's id; the device's
name; precise times of anything but the event itself; raw durations (only buckets).

## What isn't covered, and why

- **Gantt, Planning, Boards, Forms, Tickets' own edits** are writes to notes (front matter, board lines): they show as
  `note_edited`, and their screens as `screen_viewed` (`tickets`, `collection`). A per-feature action would need a
  call at each of their many write sites; none of them has a shared choke point yet.
- **Market installs** of themes and fonts: a theme chosen is `setting_changed theme`; a plugin added is
  `plugin_enabled`. The Market screen itself is `screen_viewed market`.
- **Academy lessons**: `screen_viewed academy` only.
- **Transcription** on its own: a recording's `recording_finished`, and the write-up's `write-up` job.
- **Crash stacks**: deliberately not sent. A Dart stack names files and functions only, but a framework error's
  context can quote widget text, so only the type leaves the device. A native crash (the process killed) is not seen.
- **The web build**: wired, but `tool/build-web.sh` passes no key, so it sends nothing.

## Adding an event: the rules

1. Add it to `MetricEvent` with a snake_case name and every prop it may carry, each a `FlagProp`, `NumberProp`,
   `WordProp({...})`, `CodeProp` (a code from the app's source), `ChoiceProp` (an id from a list in the app),
   `PluginProp` or a bucket. Never a free string.
2. Call `track` (or `trackPlugin`) from the narrowest **shared** place that sees it: a store, a registry, a host, the
   activity; not from each button.
3. Never pass anything the person typed or named, or another service's id. Counts go through `countBucket`, times
   through `durationBucket`.
4. Add it to the table above, and to a dashboard in `tool/posthog/setup_dashboards.mjs` if it answers a question.
5. `flutter test test/core/metrics_test.dart`: the allow-list walk and the fake session's guard must pass.

## Builds

The project key (public, `phc_…`) and the host reach a release through `--dart-define=POSTHOG_KEY` and
`POSTHOG_HOST`, read by `tool/posthog-defines.sh` from `~/.config/mattssoftware/posthog.env` (only those two
lines; the personal key in the same file is never sourced). `tool/cutover-build.sh` (release only),
`tool/cutover-build-mac.sh`, `tool/cutover-build-ios.sh` (the store build, not the simulator's) and
`tool/cutover-build-mac-store.sh` (not a tour) source it. No file, no key: no analytics.

## The dashboards

`node tool/posthog/setup_dashboards.mjs` makes or updates, by name, six dashboards and their insights, and holds the
project's privacy settings. It is idempotent. `--test` also sends three events from a throwaway install tagged
`test: true` (every insight filters `test` out) and reads them back through the query API.

- Ghost.md · Overview: https://us.posthog.com/project/710697/dashboard/2304613
- Ghost.md · Plugins: https://us.posthog.com/project/710697/dashboard/2304614
- Ghost.md · Notes & editing: https://us.posthog.com/project/710697/dashboard/2304615
- Ghost.md · Jobs & reliability: https://us.posthog.com/project/710697/dashboard/2304617
- Ghost.md · AI & Lovart: https://us.posthog.com/project/710697/dashboard/2304618
- Ghost.md · Growth: https://us.posthog.com/project/710697/dashboard/2304619

Store answers: `docs/store/analytics-disclosures.md`. The policy: `landing/privacy.html`, "Anonymous usage statistics".
