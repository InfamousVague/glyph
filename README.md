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
| 6 | Canvas | `canvas/` (3.5k) | in the app 2026-10-08 as a note's own view (`NoteSeams.canvas`), made from the + and from a notebook's index; a team's canvas (6G) since 2026-10-09: its structure in the team's document (`native/src/crdt.rs`, `lib/team/doc.dart`), drawn and edited through it with the other members' pointers (`lib/live/team_canvas.dart`), held to the web's own Yjs and its own canvas adapter, and walked on the emulator 2026-10-09 with the web's client as the other member (its pointer drawn, a card's words reaching it); **not yet on the Fold** |
| 7 | Account and sync: keys, the sync engine, organizations and team notes, live typing, notifications, shared links | `core/sync`, `core/orgs`, `core/live`, `share/` | in the app 2026-10-08, **off unless the build is given `--dart-define=GHOST_API=http://…`** (`lib/root/account_wiring.dart`); walked on the emulator against the service run on this Mac (sign up, sync read back by a second device, an organization, a team note, a shared link); links that open the app are followed since 2026-10-09 (`lib/root/ghost_root.dart`, `lib/core/phone_links.dart`: a note, the notifications, an organization, an invitation asked about first, a shared link's copy); live typing since 2026-10-09 (`lib/live/`, `lib/root/account_wiring.dart`, `lib/root/note_desk.dart`): the relay, a team note's room with the others' carets, presence, the nudge, a note of the account's own, proven by two Dart devices and by the web app's own client under Node through the relay on this Mac, and **walked signed in on the emulator 2026-10-09** against the service on this Mac (the walk, the bugs it found and what it did not reach are under "What stage 7 left open"); the "Live typing" switch is the device's own flag since then. The phone's own notifications are not ported |
| 8 | Voice and AI: the recorder, Whisper, meetings and their service, summaries, the language model, fills, the at-work scene | `capture/` (12k), `ai/` (6.5k), `tapes/`, `scene/`, Kotlin (6.5k) | Speak in the app 2026-10-09 (`lib/root/voice_wiring.dart`, `lib/root/capture_route.dart`, `lib/root/ghost_root.dart`): the dock's microphone, a note's own and a journal's spoken entry, the capture screen with its live page, the meeting service and its screen, the + sheet's Meeting, Settings' Recording and AI pages with their real rows; the summary queue, the review's gate and the write-up's configuration (lib/ai's), a spoken note's tape played by the phone, a landing's Undo; walked on an Android emulator; the AI in a note (`NoteAi`), the fills' queue, the gists and the scene since the third pass, run on the emulator with Qwen3.5 2B; **not yet on the Fold**; see "What stage 8 left open" |
| 9 | The rest: backup, export, plugins, the Academy and the guide, diagnostics, updates | `plugins/`, `academy/`, `guide/`, `diag/` | 9A to 9C (the library's folder, backup, export) walked on the emulator 2026-10-09, and in Settings since (`lib/root/ghost_root.dart`); see "What stage 9A to 9C left open". The plugins (in Settings and in a note), the Academy, the walkthrough and the guide's notebook, link previews, Developer's benches and its resets are in the app 2026-10-09 (`lib/root/plugin_ground.dart`, `reset_wiring.dart`, `note_desk.dart`, `ghost_root.dart`); the app's own updates (9I: `lib/core/updates.dart`, `lib/root/update_wiring.dart`, `tool/release.md`) and the invitation's card are in the app 2026-10-09, the updates run on the emulator against a made-up release and **on in no build** until a key and a release address are chosen; a note's place, a picture from the phone, the phone's calendar for a date and a voice memo's player are in the app 2026-10-09 (`Position.kt`, `Pictures.kt`, `DayPick.kt`), walked on the emulator; a film picked, kept and played, and a picture pasted from the clipboard, since the same day (`Films.kt`, `FilmPlayer.kt`), walked there too; the phone's own update notifier is not ported, and what it needs is written down; see "What stage 9's other pieces left open" |
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
  - **The app's own updates** (9I; `lib/core/updates.dart`, checked by the core's `update_read` and
    `update_verify`, `native/src/kept/updates.rs`, the Tauri app's lines; `UpdateInstaller.kt`): a signed `apk.json`
    from this app's OWN release address, said at build time (`--dart-define=GHOST_UPDATES=https://…`); the download
    into `<cacheDir>/updates` with its progress; the file handed to Android's installer only at the size and
    SHA-256 the signed description gives, with the "allow installs from this app" page the first time; looked for
    four seconds after launch, on a return after a minute, and every two minutes in front; never with "Nothing
    leaves the phone" on, and not installed while a meeting records. One `Updates` (made in `lib/main.dart`) feeds
    the launch screen's line, Settings › About's Updates row with Install and Check for updates, and the card above
    the notes (`lib/root/update_wiring.dart`). **It is on in no build as things stand:** never in a debug build,
    never without `GHOST_UPDATES`, never at the Tauri app's addresses, and never while
    `lib/core/update_keys.dart` lists no key, which it does not. `tool/release.md` is what a release must build,
    sign and upload, and the decisions still open (the release build is signed with the debug key, and an APK
    cannot update one signed with another; which key signs `apk.json`; where releases live).
    What differs from the web: no web bundle, so nothing is ever "ready" to reload; the signature's context is
    this app's own (`ghost-flutter-apk\0`), so a description signed for Ghost.md never passes here; a signed file
    cannot move the app to another address; a failed look says so in About.
  - **The invitation's card** above the notes (`InviteWaiting`, `lib/root/update_wiring.dart`): the newest
    invitation still pending whose organization the account is still invited to, with `InviteActions`' Accept and
    Decline; accepted, the organization opens. Only in a build with an account.
- **The phone, reached since 2026-10-09** (hand-written channels, no plugin; `Position.kt`, `Pictures.kt`,
  `DayPick.kt` beside `OpenLink.kt`):
  - **A note keeps its place.** `ghost_md/location` is the permission, its prompt and a fix from the platform's
    own providers (`lib/core/phone_position.dart`; the manifest now declares coarse and fine). What
    `lib/core/location.dart` left of `core/location.ts` is `lib/core/place_tags.dart` (`PlaceTags`: the tag that
    waits for a note's first words or a recording's better ones, new notes tagged when Settings says so, the held
    box, the watchers, the kept refusal), the note's half is `lib/note/note_screen.dart`'s as it is
    `NoteScreen.tsx`'s (Add my location, Remove location, a name arriving, the box held under the byline), and the
    root gives it to everything that makes a note: the + sheet's Note (asked before it is shown, so the box is
    there from its first frame; the first ask is said in the app's words with Allow location on it), a journal's
    entry and its place switch, a take's own new note once the recorder has gone (`CaptureRouteWorld.tagNew`,
    `EntryAim.tag`), the take-back and the Trash (`forgetTag`), the sweep at launch and after a better-words pass.
    A canvas, a notebook, the guide, a shared link's copy and a note made for a title are the app's and are never
    tagged. The map card is `NoteSeams.mapCard`, quiet for a draft's waiting tag, with OpenStreetMap's tiles
    (`lib/editor/media/map_tiles.dart`, the app named to the tile server) where the map switch is on and Local
    only is off; the name is Nominatim's through `geocodePlace(geocodeFetcher())`; a tap opens `geo:`. The +'s
    A place writes a place line with its card under it. Settings' Location card asks for its one fix and says a
    refusal with Open settings. A toast is lifted over the keyboard now (the introduction was under it).
  - **A picture from the phone**: Android's chooser, the picture shrunk to 1600 px and turned the right way up
    (`Pictures.kt`), moved among the library's pictures under a fresh name by the core (`sync_put_file_path`, so
    sync carries it as any picture), from the band's Add image, the +'s Picture and a canvas's picture card
    (`lib/core/phone_pictures.dart`).
  - **Pick a date** is Android's own calendar (`DayPick.kt`, `lib/core/phone_day.dart`), on a list item's date
    page, in a ticket's panel and in a query.
  - **A voice memo** left in a spoken note plays where it sits, a stretch of the note's recording on the app's
    one player (`lib/tapes/clip_player.dart`, the editor told its tape through `tapeSource`).
  - **The More sheet's "Linked to"** is the registry's links and actions (`NoteSeams.plugins`,
    `lib/note/note_settings.dart` `NotePlugins`): a link's page inside the sheet, an action run on the note
    through its editor, its places a page where it has several. **The walkthrough's model page** reads the
    phone's models (`PhoneGuideModels`). `claudeHandle` is set at launch.
  - **Seen on the emulator (2026-10-09, debug):** a new note's introduction toast over the keyboard, Allow
    location raising Android's prompt, "While using the app", the box held and then the tag landing with the
    note's first words (`location:` and `place: "Mendocino County, California"` in its file, the name asked of
    Nominatim) and its card drawn with tiles, the pin and the credit; Remove location and Add my location from
    the More sheet; Settings' Location card; the band's Add image opening the photo picker, a 2400 x 1800 picture
    chosen and kept as a 60 KB JPEG in `images/` with its line written and drawn; the +'s A picture and A place
    rows, A place writing its line with its map under it; Pick a date opening the phone's calendar and the day
    written on the item; the More sheet's Notion board and GitHub repo rows and GitHub's page; a memo's player in
    a spoken note playing its three seconds and stopping; a table's cells drawing their blanks and a filled
    answer; the AI's strip with the page started under it.
    **Not exercised there:** the position the emulator was told (`adb emu geo fix` answered OK and the phone's
    providers kept their own place, in California); a refusal and its footnote, a blocked phone and Open
    settings; a journal's entry and its place switch; a take's note tagged after the recorder; a locked phone; a
    canvas's picture card; a picture that cannot be read; the model page's download; a plugin's action run on a
    connected service. Each is held by tests.
  - **A film** (2026-10-09; `Films.kt`, `FilmPlayer.kt`, `lib/core/films.dart`, `lib/core/phone_films.dart`,
    `native/src/kept/videos.rs`): the +'s A video opens the Photo Picker (the web's `media/VideoPick.kt`, its
    rules line for line: 1 MB blocks, 500 MB kept free, the poster a frame a second in, upright, 1600 px), the
    core adopts the film and its poster from the cache's `picked/` and nowhere else (`save_video`,
    `discard_picked`, with the Tauri app's own lines between the marks, the hourly sweep of `picked/` and the
    weekly one of films no note names at launch), and the line is written where the caret was, "Adding the
    video." said a moment after the copy starts. Its card plays it in place: there is no WebView, so the phone's
    `MediaPlayer` draws into a texture of Flutter's (`TextureRegistry.createSurfaceProducer`, turned by the app
    where the texture does not turn it) laid over the poster, with the line of ink along the foot, the disc gone
    while it plays, one film pausing another, and full screen as a layer over the app that plays the card's own
    film (the page made a second element and handed the time back). A film that will not open, or fails as it
    plays, is asked about again and its card says which. `video/` is kept out of Google's backup, as the Tauri
    app's rules keep it. No binary is older than the films here, so nothing says "Update Ghost.md to play this
    video." **Seen on the emulator:** the +'s A video, the Photo Picker, a 6 s MP4 pushed to the gallery chosen
    and kept (`video/<uuid>.mp4`, its poster among the pictures, `picked/` left empty), its card with the disc,
    0:06 and Full screen, playing in place with its line, full screen on black with its close and its line,
    paused by a tap, closed by the back gesture with the card left where the layer stopped; and the note read
    back by a second device, which has the still. **Not exercised there:** a film too big for the phone, a kind
    that is not kept, a film filmed on its side, one that fails as it plays, a note left while its film is being
    copied (each held by tests but the turn, which only a phone's camera makes), and anything on Vulkan.
  - **A picture on the clipboard is pasted** by the band's Paste (`PhoneClipboard` over `Pictures.kt`'s
    `clipboard`, the web's `readClipboard`): shrunk into `picked/` as the chooser's is and adopted
    (`ContextBand.onPasteImage`). Seen on the emulator for words only (Copy, then Paste over a selection): adb
    cannot put a picture on the clipboard, so the picture's road is held by tests.
  - **Still open of it:** a canvas has no film card of its own to add, as on the web; a film's line in a card of
    words, and on a note's card on the home page, is not drawn as its still (the page draws both through its
    editor's `peek`: `lib/home/note_peek.dart` says a picture is its line, and a film is the same). A place
    line's name that comes later than three seconds is written only while its line is the newest change, without
    the web's count of the note's own tag landing meanwhile (`tagSteps`). The map note's header on a phone is the
    card inset, where the page's is the page's whole width with square corners.
- **Not wired, each with its seam:**
  - **A board card's plugin rows** (`drawnBoards(actions:)`, `cardActions`): left as the web app has them. Its
    own `Editor.tsx` calls `drawnBoards()` with none, so a card's menu there has no plugin's rows either; the seam
    is one line in `lib/root/note_desk.dart` (the desk already has `itemSend` and `lineOffers`, which are its two
    halves) if that is wanted here.
  - **The editor's parser reading `plugins.formats()`**: the desk gives it the app's own marks.
  - **The phone's own update notifier** (9I; the web's `updates/UpdateCheckWorker.kt`, `UpdateAlerts.kt` and
    Rust's `peek`): nothing looks for an update while the app is closed, and About has no "Update alerts" switch.
    **Not ported, and not because it is long**: the update client is on in no build (no key, no address, below),
    so a worker could be neither run nor seen, and three things it stands on do not exist where a worker can
    reach them. Precisely what is missing, in the order to build it:
    1. **Where the release is and which keys sign it, readable without Dart.** Both are Dart's today: the
       address is a `--dart-define` (`GHOST_UPDATES`, read by `Updates.forBuild`) and the keys a Dart list
       (`lib/core/update_keys.dart`), and a WorkManager job runs in a process where no Dart has started. Either
       the Gradle build reads the same define into `BuildConfig` and the keys move to a file both sides read (a
       Kotlin twin held by a test, as `VideoPick`'s extensions are), or the app writes
       `<dataDir>/updates.json` (`{source, keys, localOnly, installedCode}`) each time `Updates` is made and each
       time Local only changes, and the worker reads that. The second needs no build change and never looks for
       a build that has not been opened once.
    2. **The check without Dart.** The Tauri worker calls one JNI function that does everything in Rust
       (`UpdateCheck.run(otaDir)` to `ota::peek`, its own HTTP client and its compiled-in keys). The Flutter
       core has no HTTP client (Dart fetches, and `update_read {body, signature, keys, http}` only verifies), so
       the worker must make the two requests itself (`apk.json`, `apk.json.sig`, `Cache-Control: no-cache`,
       https only, no redirect to another host) and hand the bytes to a new door in the core: a
       `Java_com_mattssoftware_ghost_1md_UpdateCheck_read` beside `recording_jobs.rs`'s, over
       `kept::updates::read_signed`, answering the release's `version` and `versionCode` or nothing. The
       library is loaded by `System.loadLibrary("ghost_core")` as `RecordingJob.kt` loads it.
    3. **The alerts themselves** (`UpdateAlerts.kt`, ninety-six lines, portable as written): the preference
       (`glyph_update_alerts`: `enabled`, `last_notified_apk`), the channel, `canNotify`, the periodic request
       (every six hours, on any network, kept across restarts) and the one-off look on enabling. The manifest
       already declares `POST_NOTIFICATIONS` and Gradle already has `androidx.work`. Only the APK half of the
       worker applies (`apkCode > installedCode && apkCode > lastApk`, "Ghost.md 0.2.0 is ready to install",
       "Open Ghost.md to install the new version."): there is no web bundle to be "out".
    4. **The switch**: a channel (`ghost_md/update_alerts`: `state`, `enable` with Android 13's notification
       prompt answered through `onRequestPermissionsResult`, `disable`) and its Dart half given to
       `SettingsUpdates.alerts` (`lib/root/update_wiring.dart` gives none; the row and its words are drawn by
       `lib/settings/panes/about_pane.dart` already).
    5. **Never where the client never looks**: a debug build, a build with no `GHOST_UPDATES`, an empty key
       list, Local only, the Tauri app's addresses. The worker must refuse each by itself, since nothing of
       `lib/core/updates.dart` runs beside it.
  - **What's new** (About's list of releases, the web's `releases.json`): `SettingsUpdates.releases` is given
    none, so the page says "No updates to show yet." A release publishes no such file (`tool/release.md`).
- **Checked where:** on the emulator (2026-10-09): Settings › Plugins ("4 of 5 on"); a link's card reading
  "Example Domain"; the walkthrough on a first launch, a page turned, Skip; the Academy's contents and its switch,
  scrolled and left; the smoke bench with its frame times; the scene bench saying the scene is not in the build;
  and **Reset local data**, pressed twice: the notes, the recordings and the secure store's files gone, the three
  models kept, the starter notes written, the app back on the welcome walkthrough with its microphone. **Not
  walked:** a plugin connected to its service, a swipe or a suggestion from one. **Reset everything, signed in**,
  was walked 2026-10-09 (below, with stage 7's walk): the account forgotten, the way in shown again, the starter
  notes written, the pictures, the films and the models gone; it left `<dataDir>/team`, the team notes' documents,
  which a reset now takes too (`FileDocs.forgetAll`).
- **The updates, on the emulator** (2026-10-09; a debug build with the test run's two defines, a made-up release
  served from the Mac over http, signed by a throwaway key): the launch screen's "Checking for updates"; the card
  "Ghost.md 0.2.0 is out." with Install; "Downloading Ghost.md 0.2.0, 11 of 104 MB." with its bar; the file
  verified and Android's "Do you want to update this app?" (cancelled, not installed); with installs not yet
  allowed, Android's "Install unknown apps", "Allow from this source", for Ghost Flutter; and with one bit flipped
  in the served APK, "Ghost.md 0.2.0 didn't install. the APK did not match its published checksum" with Try again,
  the updates directory left empty. **Not seen:** the card's "Let Ghost.md install apps, then come back.",
  "waiting on Android" after a cancel, About's Updates rows on a phone, a finished install, anything on the Fold.
- **Found there, and open:** with the update's card on the home page, the app leaving the front (Home, or
  Android's settings page opening over it) ended the process three times out of three, SIGSEGV on the raster
  thread inside libflutter.so (Impeller on OpenGL ES); the same build's card did not survive it with the system's
  animations off either, and a build with no card went Home and came back. Not narrowed further: `_UpdateCard`
  (`lib/notes/notices.dart`: its `_Holo` painter, its shadow over a clip) is the first place to look, on the Fold
  (Vulkan) before anywhere. Until it is, the "allow installs" step kills the app on the emulator; the verified file
  is still in the cache, so Install after reopening carries on.

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
- **The AI in a note is on the desk** (third pass, 2026-10-09; `lib/root/note_desk.dart`, `ghost_root.dart`,
  `scene_play.dart`; docs/STAGE8_AI.md's list; `test/root/ai_test.dart`): one `NoteAi` to an open note, its
  extensions in the editor (the marks given without `wispTyping`, `wispStill` and `wispPace` filled), `NoteAiLayer`
  and `EditorTextPanels` over the page, the More sheet's AI rows, the spoken instruction and the review a note was
  opened with, the tape's Summarize, `AtWork` over the window; and at launch `noteOwner`, `usePluginContext`, one
  `AvailabilityController` and one `DeviceFactsController`, `startFills`, and the gists for the home page and All
  notes (`onRefineHold(pauseGists)`, `gistVisible`, `gistsCameBack`). The recorder's page takes `wispArrivals()`
  and `wispRipples` over the microphone's level; Developer's bench plays lib/scene from its script.
  **Run on the emulator with the model that is there (Qwen3.5 2B, with small.en to listen again):** after a take
  from the fixture, the review end to end (the scene's steps, "1 place where the two models heard different
  words", thinking out loud, then the note with "North Wind" struck and "Northwind" beside Keep and Revert); the
  tape's Summarize through the queue (`## Summary` and its list landing as tracked changes, the AI's `authors`);
  a `{?what is the capital of France}` blank drawn with its Fill pill and filled (`??Paris??`, "Filled 1 blank with
  Qwen3.5 2B"); Continue from the More sheet (two lines written, Revert taking them out).
  **Not run:** a meeting written up with words and its summary landing (the meeting service hears the emulator's
  silent microphone; the fixture is the dictation microphone's only), an instruction on a selection, a spoken
  instruction, the scene in the bench after it was given lib/scene, the gists.
  **Since (2026-10-09):** the strip's room is kept clear by the page (`NoteAiLayer.onRoom` to
  `NoteSeams.headRoom`: the page starts that much lower while the strip is up); a blank and a filled answer are
  drawn in a table's cell (`drawCell`: `GlyphTable` holds a box of its own in place of that cell's words,
  `HeldCell`, laid out where `TableLayout` puts it, and the table is drawn again when its blanks change); such a
  cell asks for its whole width up to 18em, where the page lets its words wrap. `claudeHandle` is set;
  `resumeParked()` is called when Local only is switched off; the bench is told when its scene has left
  (`AtWork.onGone`). Seen on the emulator: a table's two blanks as squares with their icons and a filled answer
  with its dotted line, Fill 2 after the last row, and the strip ("Loading Qwen3.5 2B.") with the byline and the
  words under it. **Not run:** a fill in a cell to its end (the emulator's model writes three tokens a second),
  a tap on a cell's filled answer opening its panel (held by a test), the bench.
- **What a recording wrote into a note is said, with its Undo** (`editor/useLanding.ts`, on the desk): an edit in
  the note's editor that takes out exactly what went in. Its writes to OTHER notes are reversed with it since
  2026-10-09: a command's write is the core's `apply_command` (`NoteLibrary.applyCommandMutation`, which
  `LibraryRecorderStore` asks) and the Undo takes each back through `undo_command`
  (`NoteLibrary.undoCommandMutation`); a note changed since is left as it is and the toast says so. Held by tests
  (`test/root/landing_undo_test.dart`, and across the real core in `test/native/command_mutations_test.dart`),
  **not walked on a device**. The page's `latestCommandMutation`, the undo offered again after the app was
  stopped (`shell/useHousekeeping.ts`), is not ported.
- **A spoken note's tape** is at its top (`NoteSeams.head`) with Play, Add and Remove with its Undo, and its
  phrases under its words (`NoteSeams.tail`), played by `PhoneTapePlayer` over `TapePlayer.kt` (a `MediaPlayer` on
  `recordings/<id>.wav`). A voice memo's clip in a note is played on the same player
  (`lib/tapes/clip_player.dart`; see stage 9's other pieces): the tape's Play afterwards goes on from where the
  memo stopped, the app having one voice where the page had an element for each. There is no shelf: the web's
  went with its dashboard (lib/tapes/shelf.dart's header), and a recording is a note's row and All notes' Tapes
  switch.
- **The voice model's line** is above the notes while it is being fetched or has failed (`Notices`'
  `VoiceModelStatus`); the update's card and the invitation's are not given (`core/ota.ts`,
  `settings/InviteActions.tsx`).
- **The side key and the launcher shortcut** are behind the build's own switch as on the web (`GHOST_ASSISTANT=1`,
  `DeviceMeetingHost.assistantEnabled`): without it a launch is never a recording and the key's events are
  dropped (`Voice.assistant`). With it the route starts a capture at launch and from the key, and a second press
  stops it; that path is held by tests and was **not walked on a device** (no build with the assistant was made).
- **Other apps' sound in a meeting** is asked for where the switch is on and the phone can (`Voice.sound`); the
  screen-share consent was not walked.
- **A take's own new note and a spoken entry are tagged** once the recorder has gone, quietly over a locked
  phone (see stage 9's other pieces); held by tests, not walked.
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

## What stage 7 left open

Live typing and a team's canvas (docs/STAGE7.md, "Live typing and team notes"; `lib/live/`, a port of
`../glyph/src/app/core/live` with its own cases in `test/live/`). The CRDT and its awareness are the Rust core's
(`native/src/crdt.rs`, yrs), so everything that touches a document is a call away: `lib/team/text_log.dart` and
`lib/live/editor_binding.dart` say what that asks of an editor bound to one.

- **How it was proven.** `tool/local-server.sh start`, then
  `GHOST_E2E_API=http://127.0.0.1:<port>/api flutter test --no-pub test/live` runs, through the real relay
  (`../glyph/server` `live.rs`) with the real crypto: two Dart devices in a note of one account's and in a team's
  note with carets, presence and the nudge (`test/live/local_server_test.dart`); and the Flutter side with the WEB
  app's own live code under Node (`tool/web_live.mjs`: its transport, hub, session, team rooms, its Yjs, its
  y-protocols, its canvas adapter) in the same note at once, both ways (`test/live/web_test.dart`): a team's note,
  a note of the account's own made by either and adopted by the other, a team's canvas, and the emoji below.
  Without the variable those are skipped and the rest runs over a relay in memory. The others' carets as they are
  drawn are in `test/live/shots/`.
- **Walked signed in on the emulator** (2026-10-09; a debug build given
  `--dart-define=GHOST_API=http://10.0.2.2:<port>/api`, the service of `tool/local-server.sh` on this Mac and
  nothing else, a second account made by a Dart test device, and the web's own client under Node as that account
  in the rooms). **Seen:** the way in and Create an account, the recovery codes, the Account page top to bottom
  (the hero with "Synced just now", Sync with its three rows, Your colour, Shared links once there was one,
  Privacy, Location, Delete account); twelve notes read back by a second device at the real 600,000 rounds
  (`test/root/second_device_test.dart`); Settings › Organizations empty, New organization, the organization's
  sheet (Members, Your colour here, Invite, Invite by link) and an invitation sent by handle, then accepted by
  the other account; an invitation from the other account as the row under Invitations and as **the card above
  the notes**, its Accept opening the organization; the organization's page (the hero, New, Notes, Members with
  their roles, Your colour, Activity) and its settings' six pages (General, Members, Workspace, Notifications,
  Report, Delete); a team note made from the organization's New and read by the other account; **the web's
  client typing into it, its line arriving as it was typed, its caret with its name over it moving and its
  selection washed**, and the phone's own typing and caret arriving there; **"walk-… is here now"** on the home
  page's cards and on the member's row with its dot, while a second device held the organizations' rooms; **a
  team canvas with the other member's pointer and name over the cards**, moving, and a card written on the phone
  read by the web's client; **Live typing switched on** and a note of the account's own typed into from the
  account's other device, the words landing in the open note; a shared link made from the More sheet (Copy the
  link, Share where it was written, Stop sharing, "The link is copied.") and its row under Shared links; Sign
  out (the organizations gone from home, the notes still here), Sign in again; and **Reset everything** signed
  in.
- **What the walk found, each fixed:**
  - An organization's settings list threw `not a colour: "16%"` in place of its Report row on the dark side:
    settings.css gives every `[data-hue]` `--hue: var(--hue-dark)` there, Report asks for a hue it does not name,
    and the token engine resolved the missing reference to an empty word where the page has no value at all and
    takes the fallback. Fixed in the engine (`packages/glacier` `Tokens`, with its case in `tokens_test.dart`).
  - A team's canvas became an error the first time another member's change arrived: the view opened the camera
    on the body handed to it anew while its host was being built, and the host, which follows the camera for the
    pointers, asked to be drawn again inside its own build. It waits for the frame to end now
    (`lib/live/team_canvas.dart`, `test/live/team_canvas_host_test.dart`).
  - Leaving a team's note threw inside its desk's `dispose`: the room's last word of where this device is
    reached the root (presence) and the desk (the team's binding gone) as the tree was locked, the dispose
    stopped half way, and the desk's listeners stayed behind to be called on a state that was gone. Neither
    draws from there now (`lib/root/ghost_root.dart`, `lib/root/note_desk.dart`). Held by the walk repeated, not
    by a test: a desk with a team's room wants the relay and the core under a widget test.
  - The keyboard stayed up over the organization that had just been made, and after Invite: a form's word takes
    the focus from its field as it is pressed, as a tap on the page's button does (`FormSubmit`).
  - Reset everything left `<dataDir>/team/<account>`, every team note's document: a reset takes them now
    (`lib/root/reset_wiring.dart`, `test/root/reset_test.dart`).
- **Found and left:** a card being written on a team's canvas when another member's change arrives keeps its
  editor but the view is fitted to the canvas again (the body handed to the view anew, as said below). The
  organization's New (`OrgAction`) and the rows of the + sheet are not in the tree a screen reader is given
  (`uiautomator` lists neither). A debug build's errors did not reach logcat on this emulator (Android 16); the
  walk kept them in a file through `FlutterError.onError`, in a build of its own that was never committed.
- **Not reached by the walk:** an invitation's Decline, an invitation by link, a role changed and a member
  removed, a rename and a colour picked, Mute, the audit log, Jump to cursor, a comment, Lost the password and
  a recovery code, Password and recovery codes, Delete account, two phones (the other party was always a script),
  and the Fold.
- **The "Live typing" switch** (the page's Settings › Account › Sync, its own row and words) is the device's own
  flag since 2026-10-09: `AccountServices.liveTyping` is `LiveEnabled` (`lib/live/enabled.dart`, kept under the
  page's own key `glyph-live`), wired in `lib/root/account_wiring.dart`, off until set, and read as a note is
  opened. A team's notes do not ask: they are live by being the team's.
- **The relay's socket** is held only while a room is: an organization's own and its `sync` room once signed in and
  in one, a note's while it is open. It is let go while the app is behind another (`onPause`) and tried again as it
  comes back, its rooms joined again; the page leaves that to the browser.
- **Undo in a live note is the editor's own history**, with what arrives kept out of it, where the page swaps in
  `Y.UndoManager`: either takes back this person's typing and leaves the others'.
- **A selection of another member's across lines** is washed over each line's words; the page washes the lines
  between whole, an empty line among them too.
- **A note open in an editor bound to its document is the editor's** (`TeamDoc.editing`): a pass posts what was
  typed and applies what the log brings, and neither reads the saved note into the document nor writes the
  document into the note. The page's pass reconciles from the saved note, a save's delay behind its editor.
- **Jump to cursor** opens a note at a member's caret (`NoteDeskWorld.takeJump`); a member's spot on a canvas is
  not gone to (`CanvasView` has no `goTo`).
- **On a team's canvas** the card a member has open is not said or drawn (`card` in the room), this device's
  pointer is where a finger is down and nowhere once it lifts, and a change that arrives while a card is being
  dragged is the body handed to the view anew. A canvas has no comment sheet yet, so its threads are carried and
  merged and not shown.
- **A session that meets another history after a drop ends**, as the page's does (`LiveSession` on a different
  seed): the note is live again the next time it is opened.
- **The web's bug with an emoji, and what is done about it here.** `applyTextDiff`
  (`../glyph/src/app/core/team/textDiff.ts`) finds the common head and foot of two wordings by UTF-16 code unit,
  so when they differ inside a character of two units (😀 made 😁: the same first half) it deletes and inserts
  half a character. Yjs, cutting a block of text between the halves, writes U+FFFD over both; the half it was
  given to insert is a lone surrogate in the writer's memory and U+FFFD on the wire. Every other member reads
  U+FFFD twice where the emoji was, and the writer's own copy differs from theirs until it is loaded again. It is
  reached by `reconcile` (words that reach a team note without its editor: a capture, the connector, a sync of
  the library) and by a card's words on a canvas. The fix there is to draw the head and the foot back to whole
  characters, as `native/src/crdt.rs` `stretch` does. Here the core used to refuse such an update, and this copy
  stopped following the note; now where an update cuts is read from its bytes first (`native/src/crdt_wire.rs`)
  and the character written as U+FFFD twice in this copy too, which is what the web holds: the same words, and a
  document the web still reads (`native/tests/yjs_vectors.rs`, `tool/yjs_vectors.mjs check`,
  `test/live/web_test.dart`).
- **`test/e2e/local_server_test.dart`'s password-free sign-in** failed once when run beside `test/live` (the
  service gave the same token twice within a second) and passes alone.

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
  gives the journal its tab again, and the place waiting for the note's first words goes with it
  (`TakeBack.forgetTag`). Seen on the emulator for a new note named from its blank page
  and left; an entry's is held by tests.
- **A blank page's cards have A map at the top** where the phone can say where it is (`TemplateCards.canLocate`,
  its header `MapPicture`), dimmed with the reason under Local only or a refusal that stands; pressed, the note's
  box is held and its place asked for. **A new note, a journal's entry and a journal keep their place** (Tag new
  notes, a journal's place switch; see stage 9's other pieces). Not walked: the card, and an entry.
- **The + sheet's Meeting** is there where a meeting can be recorded (stage 8), and **From a shared link** in a
  build with an account's service; neither from an organization's +.
- **A canvas** has the phone's picture chooser for its picture card (not walked) and opens no link (as a note), no
  comment sheet (`CanvasView.threads`), is not framed in a note from the + (`AddConfig.canvases`). A team's canvas
  (6G) is its structure in the team's document (see "What stage 7 left open"). A canvas renamed from its tab is
  written to the store and not through its open screen (`rename`).
- **A board's card has no plugin's rows** (`drawnBoards(actions:)`), as on the web (see stage 9's other pieces).
  A date in a ticket's panel or a query is picked from the phone's calendar (`dayPicker`); seen on a list item's
  date page, not in a panel or a query.
- **`Notices`**: the voice model's line (stage 8), the update's card and the invitation's (stage 9,
  `lib/root/update_wiring.dart`) are on the home page. `RefiningNotice` and the sidebar's notices are still given
  nothing.
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
- **Not drawn yet on a note's page:** the placeholder ("Write something.") and comments. (The AI's rows, the place row
  and the map card came with stages 8 and 9; the blank page's names and template cards, a notebook's bar and foot, and
  the canvas, the notebook and the journal themselves came with stages 5 and 6.)
- **What needs the phone is added** since 2026-10-09: a picture, a film, a place and a day from the calendar (see
  stage 9's other pieces). A link card's tap, a canvas's link card and Settings' links are handed to the
  phone since 2026-10-09 (`lib/core/open_link.dart` over `ghost_md/open`; seen opening Chrome on the emulator).
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
  will find it: seen on the emulator, the link put on the clipboard reads `https://ghostmarkdown.com/read.html#…`
  (nothing is asked of that address by making it; it was not opened).
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
  window), `AppIcon` does not read `IconTheme`, and the engine makes every line of text a whole logical pixel tall, whatever
  its style says: wrap a `Text` in the kit's `ExactLines` (`ExactLines.of(text)`, or `normal: true` for a line of
  `line-height: normal`, which is rounded in device pixels as Chromium rounds it) where a column of them must end
  where the page's does. Settings' rows, captions and choice cards and the walkthrough's paragraphs wear it; the
  rest of the app's text does not yet.
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
