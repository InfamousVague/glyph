# Ghost.md in Flutter

A port of Ghost.md (`../glyph`: Tauri, a React page, a Rust core, Kotlin for Android) to Flutter, started 2026-10-07
at Matt's ask: "change the architecture ... to flutter ... maintain parity of features and the UI kit porting used
glacier components one to one, maintain the animations and effects and as you build each stage deploy a ghost flutter
version on my fold".

It installs beside the real app, never over it: Android id `com.mattssoftware.glyph.flutter`, named "Ghost Flutter",
with data of its own.

## How it is put together

- `packages/glacier/` is the Glacier UI kit in Flutter.
  - **Tokens are not transcribed.** `lib/src/tokens/` reads the web kit's own `tokens.css` and then the app's
    `ink.css`, `app.css` and `typefaces.css` (copied by `tool/sync-design.sh`), keeps every rule made of `:root`,
    `data-` attributes and classes, and resolves custom properties through the same cascade: specificity, order,
    inheritance into a scoped subtree (`.app-inverse`, `data-hue`), `var()`, `calc()`, `clamp()` against the window,
    `oklch()`, `color-mix()`, shadows, gradients, easings. `t.len('glacier-space-3')`, `t.color('app-ink')`,
    `t.lenOf('calc(var(--glacier-space-10) * 0.74)')`. So a CSS rule ports line by line, and a change to the web
    app's theme arrives by copying the stylesheet.
  - `test/tokens_test.dart` holds the engine to the page itself: `test/fixtures/web_tokens_375.json` is what
    Ghost.md's page computed for a set of properties (lengths by a probe's width, colours by a canvas pixel) in
    light, in dark and inside `.app-inverse`. Lengths agree to 0.02 px and colours to one step of 255.
  - `lib/src/motion/` is `@glacier/motion` (the named motions, speeds, easings, springs, press depths, stagger);
    `lib/src/haptics/` is the kit's haptics (one listener for every press, the feedback bus, `useHaptics`);
    `lib/src/components/` is one widget per `@glacier/react` component the app uses.
- `lib/` is the app. `assets/fonts/` are the web app's own faces converted from woff2 (`tool/fonts.py`).
- **Text is set the way the page sets it.** `t.text('sm')` is a step of the kit's scale with the kit's leading and
  tracking, right inside kit components. Page text outside them has `line-height: normal`: `t.textAt(px, ...)`. Both
  ask for Inter's optical size for their size, which a browser applies by itself; without it a 28 px title is 5%
  too wide. Change a style's size with `Tokens.resized`, never `copyWith(fontSize:)`.
- **A screen is held to the page by measurement.** `test/launch/launch_screen_test.dart` is the pattern: rectangles
  read from the web app with `getBoundingClientRect` at 390 x 844, asserted to half a pixel, and a picture of the
  screen (`test/support/render.dart`, written to a `shots/` folder beside the test) looked at beside the page's.

## Stages

Each stage ends installed on the Fold. Sizes are the web app's non-test source the stage has to carry.

| # | Stage | From `../glyph` | State |
| - | ----- | --------------- | ----- |
| 0 | Ground: project, token engine, motion, haptics, fonts | `vendor/@glacier/tokens`, `@glacier/motion`, `ink.css`, `app.css` | done |
| 1 | The kit: Switch, SegmentedControl, DensitySelector, ProgressBar, Pill, Toast, Input, SearchField, Kbd, CommandPalette, Popover, Menu, and a gallery of them on the phone | `@glacier/react` (12 of its components, ~4k lines) | done 2026-10-07, on the Fold |
| 2 | The shell: launch, the tab bar in its four styles, home, All notes, the sidebar, notifications, the command bar, the app's sheet, a note's menu and the + sheet, Settings with its kit and a live Appearance page; the art: wisp and smoke as shaders, the ghost, the icons | `shell/`, `home/`, `launch/`, `art/`, `commands/`, `settings/` kit, most of `notes/` (~15k) | on the Fold 2026-10-07; see "What stage 2 left open" |
| 3 | The library: the web app's Rust library included unchanged behind FFI (`native/`), a worker isolate, notes as Markdown files in the app's own folder, trash and workspaces as the web's preferences, search, starter notes | `src-tauri/src/library` (kept), `core/store.ts`, `trash.ts`, `workspaces.ts`, `noteFolders.ts` | on the Fold 2026-10-07; a chosen folder, sync and moving a Tauri library over come later |
| 4 | The editor: live Markdown, the marks and the five effects, tables, links, pictures, the + menu | `editor/` (26k), `format/` | put together 2026-10-08 (`lib/root/note_desk.dart`) and walked on an Android emulator, phone and unfolded, dark and light; **not yet on the Fold**; see "What stage 4 left open" |
| 5 | Structured notes: boards, tickets, queries, databases, notebooks, journals, templates | `editor/`, `book/`, `notes/` | in the app 2026-10-08 (`lib/root/note_desk.dart`, `lib/root/library_reads.dart`, `lib/root/ghost_root.dart`): boards, queries and a ticket's panel drawn in a note, the notebook's index and the journal's entries, the + sheet and New notebook, a blank note's names and template cards; **not yet on the Fold**; see "What stages 5 and 6 left open" |
| 6 | Canvas | `canvas/` (3.5k) | in the app 2026-10-08 as a note's own view (`NoteSeams.canvas`), made from the + and from a notebook's index; a team's canvas (6G) is not ported; **not yet on the Fold** |
| 7 | Account and sync: keys, the sync engine, organizations and team notes, live typing, notifications, shared links | `core/sync`, `core/orgs`, `core/live`, `share/` | in the app 2026-10-08, **off unless the build is given `--dart-define=GHOST_API=http://…`** (`lib/root/account_wiring.dart`); walked on the emulator against the service run on this Mac (sign up, sync read back by a second device, an organization, a team note, a shared link); links that open the app are followed since 2026-10-09 (`lib/root/ghost_root.dart`, `lib/core/phone_links.dart`: a note, the notifications, an organization, an invitation asked about first, a shared link's copy); live typing and the phone's own notifications are not ported |
| 8 | Voice and AI: the recorder, Whisper, meetings and their service, summaries, the language model, fills, the at-work scene | `capture/` (12k), `ai/` (6.5k), `tapes/`, `scene/`, Kotlin (6.5k) | Speak in the app 2026-10-09 (`lib/root/voice_wiring.dart`, `lib/root/capture_route.dart`, `lib/root/ghost_root.dart`): the dock's microphone, a note's own and a journal's spoken entry, the capture screen with its live page, the meeting service and its screen, the + sheet's Meeting, Settings' Recording and AI pages with their real rows; the summary queue, the review's gate and the write-up's configuration (lib/ai's), a spoken note's tape played by the phone, a landing's Undo; walked on an Android emulator; the AI in a note (`NoteAi`), the fills and the scene are not wired; **not yet on the Fold**; see "What stage 8 left open" |
| 9 | The rest: backup, export, plugins, the Academy and the guide, diagnostics, updates | `plugins/`, `academy/`, `guide/`, `diag/` | 9A to 9C (the library's folder, backup, export) walked on the emulator 2026-10-09, and in Settings since (`lib/root/ghost_root.dart`); see "What stage 9A to 9C left open". The plugins (in Settings and in a note), the Academy, the walkthrough and the guide's notebook, link previews, Developer's benches and its resets are in the app 2026-10-09 (`lib/root/plugin_ground.dart`, `reset_wiring.dart`, `note_desk.dart`, `ghost_root.dart`); a note's place, updates and the phone's notices are not; see "What stage 9's other pieces left open" |
| 10 | Platforms and release: the Fold's wide layouts, Mac, Windows, iPhone; signing; moving a library over from the Tauri app | | |

The web app is about 110,000 lines of TypeScript, 21,500 of CSS, 27,000 of Rust and 6,500 of Kotlin, with 5,600
tests. Parity is the bar for every stage; a stage is not done until its screens have been compared with the web app's
on the same phone.

## What stage 9's other pieces left open

`lib/main.dart` calls `installPlugins()` (`lib/root/plugin_ground.dart`) before the first screen; the rest is
`lib/root/ghost_root.dart`, `note_desk.dart` and `reset_wiring.dart`. `test/root/rest_test.dart` and
`reset_test.dart` hold the wiring.

- **In the app:**
  - **The plugins:** the five that ship, Settings › Plugins drawing their cards; their hosts on the Keystore's
    secure store, `openLink`, and `pluginFetcher`, which follows no redirect and, in a build that is not a release,
    refuses ghostmarkdown.com and attack.fm outright (Notion's manifest names ghostmarkdown.com); each plugin's
    secrets warmed at launch; Local only followed (`plugins.preferencesChanged`). In a note: a swipe on a list
    item and the words offered after a line (`itemSend`, `lineOffers`), a linked to-do kept in step with its task
    (`doneSyncs`), a linked row's menu (`MediaSeams.linkMenus`), and `LinkMarks` at the note's top
    (`NoteSeams.head`), its press the More sheet. In the recorder: their spoken formattings and tips.
  - **The secure store takes a colon in a name** (`SecureStore.kt`): Slack keeps each channel's webhook under
    `glyph-slack-webhook:<id>`, which the store's rule (letters, digits, `-`, `_`) refused, so a webhook could not
    have been kept on a phone. The Tauri app had neither side of this (its webhooks were a file of Rust's); the
    names are this port's, and the store's rule was the one to change.
  - **The walkthrough** (`GuideController`, `Guide`): up on a first launch that is not the side key's capture, from
    Settings › About and the palette after, stepping aside for a recorder; the capture route's "Not yet" asks it.
    **The guide as a notebook** (`addGuideBook`) from Settings › About, added once and opened.
  - **The Academy** through `academyBuilder`, from Settings › About and the palette, its cheat sheet opening
    Settings at that page.
  - **Link previews:** `KeptLinkPreviews(fetch: linkPreviewFetch())` as a note's `MediaSeams.previewer`, asked only
    with Link previews on and "Nothing leaves the phone" off.
  - **Developer:** `showWispBench`, `showSceneBench`, and the two resets (`lib/core/reset.dart` over
    `resetGroundFor`): the account forgotten first, the phone's half (`PhoneReset`), every plugin's secret by name
    with Slack's webhooks one to a channel (`slackSecretNames`), the device's memory cleared but what is spared,
    and the app built anew (`lib/main.dart` `_Runs`, the page's `window.location.reload()`).
- **Not wired, each with its seam:**
  - **A note keeping its place** (the web's geotag switch, on by default for notes the person makes): nothing
    here can say where the phone is. It wants a Kotlin half for the device's position and its permission (there
    is none under `android/`, and the manifest asks for no location), then what `lib/core/location.dart`'s header
    lists as not ported (`pendingTag`, `tagNewNotesIfWanted`, `tagEntryIfWanted`, the held box, the watchers, the
    kept refusal) over `Locations`, with `geocodeFetcher()` (`lib/core/geocode.dart`) for the name. Its seams in
    what is wired: `NoteSeams.location` and `mapCard`, `TemplateCards.canLocate`, `TakeBack.forgetTag`, the
    capture route's `tagAfter`, a journal's place switch.
  - **The More sheet's "Linked to" rows** (`NoteSeams.linked`: each plugin's link, its page and its actions), a
    board card's plugin rows (`drawnBoards(actions:)`), the editor's parser reading `plugins.formats()` (the desk
    gives it the app's own marks), and `usePluginContext` / `claudeHandle` (docs/STAGE8_AI.md, "At launch", 1).
  - **The walkthrough's model page** (`Guide(models:)`): a phone with none to fetch, as far as it is told.
  - **The scene the bench plays** (`showSceneBench(scene:)`): lib/scene landed after this pass and is not given
    to the bench; the bench says the scene is not in the build.
  - **Updates and the phone's own notices** (9I): `Notices`' update card and the launch screen's `updates`.
- **Checked where:** on the emulator (2026-10-09): Settings › Plugins ("4 of 5 on"); a link's card reading
  "Example Domain"; the walkthrough on a first launch, a page turned, Skip; the Academy's contents and its switch,
  scrolled and left; the smoke bench with its frame times; the scene bench saying the scene is not in the build;
  and **Reset local data**, pressed twice: the notes, the recordings and the secure store's files gone, the three
  models kept, the starter notes written, the app back on the welcome walkthrough with its microphone. **Not
  walked:** a plugin connected to its service, a swipe or a suggestion from one, Reset everything, a reset signed
  in.

## What stage 8 left open

Speak is put together by `lib/root/voice_wiring.dart` (a `Voice`: the recorder over the core's Whisper and the
phone's microphone, the meeting service's store, the models on the phone, the summary queue) and
`lib/root/capture_route.dart` (where a capture begins and ends, `shell/useCaptureRoute.ts`); `lib/main.dart` attaches
the phone's halves before the first frame and `lib/root/ghost_root.dart` gives the shell its capture and meeting
screens. `test/root/voice_test.dart` holds the wiring. There is no always-on microphone: one is opened by a
recorder's screen that is on screen.

- **A debug build fetches a model from nowhere.** `--dart-define=GHOST_MODELS=http://10.0.2.2:8765` names a server
  on this Mac (the files of `../glyph/models`); with none, the one mirror is `http://127.0.0.1:9`, where nothing
  listens, and Get says it could not. The real mirrors are refused in a build that is not a release
  (`voiceMirrors`). **Never hand the core an empty list:** it reads one as none given and falls back to attack.fm
  and Hugging Face (`native/src/models.rs` `mirrors`); a debug build did exactly that once, on the emulator, on
  2026-10-09, before the list was given its one address.
- **`--dart-define=GHOST_MIC_FIXTURE=true`**, a debug build's only, plays `<dataDir>/fixture.wav` in place of the
  microphone (an emulator's hears silence): `adb push ../glyph/models/fixture.wav /data/local/tmp/` and
  `run-as com.mattssoftware.glyph.flutter cp /data/local/tmp/fixture.wav fixture.wav`.
- **Summaries and the review's gate are lib/ai's, wired** (`Voice.summaries`, a `Summaries` over the phone's
  write-up, the better words' queue and the notes): a take's summary and whether its review can run are asked of
  it by the recorder, a meeting's write-up is queued as the phone's own and dropped with the meeting, its
  configuration is kept current (`keepJobConfigCurrent`), `MeetingLive.writeUpRunningNow` is the last look at the
  phone's jobs, a summary that landed is said with Open, and a `ghostmd://note/…` link lands a waiting result
  first (`landNativeResult`). **Not walked on a device:** no meeting with words in it was written up after this
  was wired, and the model on the emulator is not the one the preferences choose.
- **The AI in a note is not on the desk** (`NoteAi`, lib/ai/note_ai.dart; docs/STAGE8_AI.md, "For each open
  note"): its files, the fills' panel and lib/scene were committed (d33f491, 2bff511, 15ce774) only after this pass's
  desk was finished, and it has not been put on since: the next thing to wire, by that document's list. So a spoken instruction and a review the note opened with
  (`NoteDesk.ask`, `NoteDesk.review`, from `ScreenNote`) are carried to the desk and not run, the review therefore
  never draws though the recorder may hand one over, the tape has no Summarize (`NoteTape.summary`,
  `NoteAi.canSummarize`), the More sheet has no AI rows (`NoteSeams.onAi`), and the fills' queue, the gists, the
  device facts and the availability's controller of that document's "At launch" (5, 6, 8, 9) are not started.
- **What a recording wrote into a note is said, with its Undo** (`editor/useLanding.ts`, on the desk): an edit in
  the note's editor that takes out exactly what went in. Its writes to OTHER notes are not reversed: the store
  keeps no log of a command's change (`LibraryRecorderStore`, where the core's `apply_command` and `undo_command`
  are not bound), so each is counted as changed since and the toast says so.
- **A spoken note's tape** is at its top (`NoteSeams.head`) with Play, Add and Remove with its Undo, and its
  phrases under its words (`NoteSeams.tail`), played by `PhoneTapePlayer` over `TapePlayer.kt` (a `MediaPlayer` on
  `recordings/<id>.wav`). A voice memo's clip in a note (`MediaSeams.clipPlayer`, `tape`) is not given the player
  yet, and there is no shelf to give it to: the web's went with its dashboard (lib/tapes/shelf.dart's header), and
  a recording is a note's row and All notes' Tapes switch.
- **The voice model's line** is above the notes while it is being fetched or has failed (`Notices`'
  `VoiceModelStatus`); the update's card and the invitation's are not given (`core/ota.ts`,
  `settings/InviteActions.tsx`).
- **The side key and the launcher shortcut** are behind the build's own switch as on the web (`GHOST_ASSISTANT=1`,
  `DeviceMeetingHost.assistantEnabled`): without it a launch is never a recording and the key's events are
  dropped (`Voice.assistant`). With it the route starts a capture at launch and from the key, and a second press
  stops it; that path is held by tests and was **not walked on a device** (no build with the assistant was made).
- **Other apps' sound in a meeting** is asked for where the switch is on and the phone can (`Voice.sound`); the
  screen-share consent was not walked.
- **No place is asked for** after a take's new note or a spoken entry (see stage 9's other pieces).
- **Settings › Recording's Tapes** sums the lengths of the notes whose audio was not removed here; the web also
  asks each file whether it is on this device (`headStatus`; `TapePlayer.onDevice` could answer it now).
- **Checked where:** on an Android emulator (2026-10-09, debug, dark): the dock's microphone, the system's
  microphone prompt answered, a take of silence with the card of things to say and the ghost listening, Discard;
  a take from the fixture, its words arriving on the live page with the rings and the smoke, Done, the note on the
  home page with its length, the better words' pass changing a word a moment later; the + sheet's Meeting, the
  cassette screen and the service's notification, the dock's microphone opening the meeting instead while it
  records, Done, the note written up with `## Transcript`; Settings › Recording and Settings › AI (Qwen3.5 2B here
  and in use, Get refused by the mirror that is not there); and, after the second pass, the spoken note's tape
  playing with its phrases lit in turn. **Not exercised there:** a note's own Speak, a journal's spoken entry and
  a landing's Undo (held by tests), a real voice, a meeting with anything said, the lock screen, the side key.
  **Still to see on the Fold:** all of it under a real voice.

## What stages 5 and 6 left open

The pieces (docs/STAGES_5_6_8_9.md) are in the app: each open note's desk (`lib/root/note_desk.dart`) lists
`drawnBoards()`, `tickets(…)` and `queries(…)` among its extensions and tells them when the library changes, and
gives the note's screen its canvas, its notebook's index, its journal and the bar and foot a page wears; the root
(`lib/root/ghost_root.dart`) answers what they ask of the app as `App.tsx` does, over one reading of the library per
change (`lib/root/library_reads.dart`). `test/root/structured_test.dart` holds the wiring.

- **An entry or a named note nobody wrote in is taken back** since 2026-10-09 (`lib/root/take_back.dart`,
  `App.tsx`'s `takeBack` with its own conditions; `test/root/take_back_test.dart` holds each one that must not
  delete): looked at whenever the screen or the open tabs change and at launch, a delete with no Trash and no
  toast. The record is written before the line and the note now, as on the web, and Back from an untouched entry
  gives the journal its tab again. What it lacks is the place waiting for the note's first words
  (`TakeBack.forgetTag`), which nothing keeps yet. Seen on the emulator for a new note named from its blank page
  and left; an entry's is held by tests.
- **A blank page's cards have no map.** A map at the top is left out (`TemplateCards.canLocate` is false: nothing
  says where the phone is), and a template with a map asks for no place.
- **A new note, a journal's entry and a journal keep no place** (Tag new notes, a journal's place switch): the
  switch is drawn in the New notebook sheet and written to the journal, and nothing reads it.
- **The + sheet's Meeting** is there where a meeting can be recorded (stage 8), and **From a shared link** in a
  build with an account's service; neither from an organization's +.
- **A canvas** has no picture picker and opens no link (as a note), no comment sheet (`CanvasView.threads`), is not
  framed in a note from the + (`AddConfig.canvases`), and a team's canvas (6G) is not ported. A canvas renamed from
  its tab is written to the store and not through its open screen (`rename`).
- **A board's card has no plugin's rows** (`drawnBoards(actions:)`), and a date in a ticket's panel or a query is
  not picked from a calendar (`dayPicker`).
- **`Notices`** has the voice model's line (stage 8); the update card waits for stage 9's updates and the
  invitation for its buttons (`InviteActions`).
- **The aside** (the open note's notebook beside it on a wide window, `aside/`) is still the shell's placeholder.
- **A note opened with the caret at its end** (a journal's new entry) is scrolled until that line is at the top of
  the page as the keyboard comes up, its heading and the notebook's bar above it out of sight until the page is
  pulled down (seen on the emulator; the editor's own keeping of the caret clear of the keyboard, not looked into).
- **Checked where:** on an Android emulator (Gboard, dark) by hand, 2026-10-08: the + sheet and its Note, Entry in
  Journal, Canvas and Notebook; a blank note's names and cards, and A day pressed; Launch week's board, a card moved
  by its chevron; the Example project's index, a page opened from it with the notebook's bar and its ticket's panel,
  a status picked; A ticket board from the +'s A database, its list, and a status picked there written into the
  other note and drawn again; an entry made and its journal's months; a canvas made, a card added by a double tap
  and written in, the canvas dragged and fitted. **Not exercised there:** a pinch on the canvas and a card carried
  between lanes (adb sends one finger and no hold-and-drag worth trusting; both are held by the pieces' own tests).
  **Still to see on the Fold:** those two under a real finger, the canvas's cards' words on Vulkan, the keyboard's
  own toolbar over a canvas card being written in.

## What stage 9A to 9C left open

The library's folder, the backup and the export (docs/STAGES_5_6_8_9.md), with three small channels: an address
handed to the phone (`ghost_md/open`), a reset's phone half (`ghost.md/reset`) and links that open the app
(`ghost_md/links`). `lib/main_files.dart` is all of it alone on a phone, and says how each was walked.

- **Wired in `lib/root`** (2026-10-09): `GhostRoot(native:)` is the whole core, and Settings is handed
  `LibraryFolder`, `Backups.overCore` and `ExportAll.overCore` over it; `PhoneReset` is the phone's half of
  Developer's resets (`lib/root/reset_wiring.dart`). Seen on the emulator: Library folder saying where the notes
  are and how many, its picker opened and left; Export everything saved through Android's own dialog ("Exported 9
  notes and 11 other files, 33 MB"). Backup's page was not walked again (it wants a USB drive, below).
- **Android only.** The Mac's folder panel, its drives and Eject, and its save panel (`library_choose_folder`,
  `backup_drives`, `backup_eject`, `export_save`) are stage 10's.
- **A backup wants a USB drive.** Android 11 and later grant no app the top of an SD card ("Can't use this
  folder"), which is where a backup goes, and the same is true of the Tauri app. On the emulator, whose one drive is
  an SD card, the backup was written into a folder picked on it (`lib/main_files.dart`, "Back up into a folder");
  the page's own road, allow then back up, has not been walked to its end on any device.
- **`ghostmd://` is the real app's scheme too:** on a phone with both, Android asks which opens a link.
- **Not ported:** the notes' folder in the phone's Files app (`LibraryDocuments.kt`, `library_reveal`).

## What stage 4 left open

The editor's pieces (docs/STAGE4.md) are assembled for each open note by `lib/root/note_desk.dart`, and the account's
(docs/STAGE7.md) by `lib/root/account_wiring.dart`; `lib/root/ghost_root.dart` is where both meet the shell.

- **The account is off by default.** `flutter build apk --debug --no-pub --dart-define=GHOST_API=http://10.0.2.2:<port>/api`
  after `tool/local-server.sh start` gives a build with one (10.0.2.2 is this Mac from the emulator; cleartext is
  allowed in the debug manifest only). With no define nothing of the account is made and every screen is the
  signed-out one, whose way in says the build has no service. A define naming ghostmarkdown.com or attack.fm is
  refused in a build that is not a release (`accountBase`), and by the `Api`'s assert after it.
  `test/root/second_device_test.dart` is the second device that reads back what a phone wrote.
- **Not drawn yet on a note's page:** the placeholder ("Write something."), comments, the AI's rows, the place row
  and the map card. (The blank page's names and template cards, a notebook's bar and foot, and the canvas, the
  notebook and the journal themselves came with stages 5 and 6.)
- **Nothing can be added that needs the phone:** no picture picker (the band's Add image and the +'s Picture are not
  offered; a picture a note already names is drawn from the kept files), no place, film or voice memo, no calendar
  for Pick a date. A link card's tap, a canvas's link card and Settings' links are handed to the phone since
  2026-10-09 (`lib/core/open_link.dart` over `ghost_md/open`; seen opening Chrome on the emulator).
- **A new note is opened ready to type** since stages 5 and 6 were wired (the shell's `openNote` carries a caret),
  from the + sheet's Note.
- **Links that open the app** are followed once the notes are read (`lib/root/ghost_root.dart` over
  `lib/core/phone_links.dart`, as `shell/useAppLinks.ts`; `test/root/links_test.dart`): `ghostmd://note/<id>`
  where the note was left, `ghostmd://notifications`, `ghostmd://org/<id>` in a build with an account,
  `ghostmd://join/<code>` asked about before anything is joined, and a shared link's copy. The first two were seen
  on the emulator; the other three need an account's service and are held by tests. Android also hands Flutter
  each address as a route to push, which put a second copy of the app over the first: `lib/app/ghost_app.dart`
  takes every pushed route and drops it, and the manifest's `flutter_deeplinking_enabled` is `false` now too. A
  note link lands a waiting summary first (`landNativeResult`).
- **A shared link** made by a build on a local service still names the real reader page (lib/share), where nothing
  will find it.
- **Icons the generated set lacks** fall back: Wave's on the Style page and in the +'s list (`waves` is not in
  `lib/art/lucide.g.dart`).
- **Checked where:** on the emulator (Gboard, Impeller on OpenGL ES) by hand: typing, Enter in a list, a to-do's box,
  the band and its Style and field pages, the + and its list, a table, find and replace, a chip's menu, each of the
  twelve marks with the smoke and the five effects moving, a kept picture, links between notes, the bookmark, saving
  to the note's file, the unfolded size, dark and light. **Still to see on the Fold:** composing and autocorrect
  with Samsung Keyboard and a CJK keyboard, the selection's handles and loupe under a real finger, the band's place
  beside the crease, the effects and the smoke on Vulkan, typing in a long note, and the pinch.

## What stage 2 left open

- **Stand-ins until their stage:** the notes are the store screenshots' invented library in memory (`SampleLibrary`;
  stage 3, planned in `docs/STAGE3.md`); an opened note is its title over its Markdown as written (stage 4); Settings'
  Library folder, Backup and Plugins open a card that says they are not ported, and its signed-in pages wait for
  the account; the notifications card is empty (organizations came with stage 7; notebooks, journals and canvases with stages 5
  and 6, from the +; Speak with stage 8).
- **Not wired though built:** `Notices` (see "What stages 5 and 6 left open"). `NoteActions` (delete, archive and
  pin with the web's Undo toast, the Trash), `NewSheet` and `TemplateCards` are wired now.
- **Two previews of a note:** the drawn one (`lib/home/note_peek.dart`) and the sidebar's two plain lines
  (`lib/notes/note_peek.dart`); the sidebar should take the drawn one, and a dense card wants it clipped to 4.2 lines
  where it is 6.2. `BookPlaceMark` and `OrgMark` exist twice the same way.
- **Kit gaps the ports worked round:** no stylesheet or inline style on `GlacierTheme` (Settings appends rules to the
  sheet; the shell lays a second root to stamp `data-topbar`), no root font size (the interface scale magnifies the
  window), `AppIcon` does not read `IconTheme`, a line height given as a multiple rounds to a whole pixel.
- **Checked where:** every screen's rectangles against the web page in tests; the whole app on an Android emulator
  (Impeller on OpenGL ES: home, scrolling under the smoke, the sidebar, Settings, a note, the command bar, the
  unfolded width). **Not yet looked at on the Fold itself**, whose Impeller is Vulkan: the smoke shaders, the glass,
  the feel of swipes and of holding a tab. `lucide_icons_flutter` is no longer used and can leave pubspec.

## What stage 1 left open

- **Not ported from the kit:** the `skeleton` prop everywhere, the `shape` system (ShapeLayer), `ContextMenu`, and the
  kit's `LocaleProvider` (the few strings are local, English first; the palette's are in eight languages).
- **Three files do the same job** and want merging: `css_effects.dart`, `field_core.dart` and the private painters in
  `menu.dart` / `popover.dart` each draw inset shadows, outer shadows and a glass backdrop.
- **A panel over the page takes the tokens where its trigger is**, where the web kit's portal took the body's.
  `Tokens.rootTokens` is there for it; the popover, menu and palette do not use it yet.
- **Hover styles** only show on Android once a key has been pressed (Flutter's highlight mode); a mouse on the Fold's
  desktop mode will want that looked at in stage 10.
- **Checked against the web kit:** the tokens (35 values measured on the page), the palette's logic (the kit's own 48
  cases), the positioning maths and arrow outlines (string for string), and the fields and palette by pixels against
  Chromium drawing the kit's CSS. **Not yet compared side by side on the phone** with the web app: the switch, the
  segmented control, the density selector, the pill, the toast and the menu, whose sizes and colours are asserted
  against the tokens in tests but were only looked at, not measured, on the device.
- **On the device (2026-10-07, Fold 8, Android 17, Impeller):** a bounded backdrop blur filled only part of a menu's
  panel, so the glass uses an ordinary blur under its clip.

## Working on it

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ANDROID_HOME=$HOME/Library/Android/sdk
(cd packages/glacier && flutter test)       # the kit, tokens against the page first
tool/build-native.sh                        # the Rust core: cargo test, the Mac dylib, the phone's .so
flutter analyze && flutter test             # the app
flutter build apk --debug --target-platform android-arm64   # -t lib/main_kit.dart, lib/art/main.dart or lib/main_launch.dart for one gallery alone
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

`tool/sync-design.sh` refreshes the stylesheets from `../glyph`; run the kit's tests after it.
