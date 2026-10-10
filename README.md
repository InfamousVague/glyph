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
| 4 | The editor: live Markdown, the marks and the five effects, tables, links, pictures, the + menu | `editor/` (26k), `format/` | put together 2026-10-08 (`lib/root/note_desk.dart`) and walked on an Android emulator, phone and unfolded, dark and light; the placeholder, comments (the round, the wash, the drawn fence, the thread's card in the app's sheet: `lib/editor/comments`, `lib/comments/ui`) and a canvas framed in a note since 2026-10-09, held by tests and pictures; **not yet on the Fold**; see "What stage 4 left open" |
| 5 | Structured notes: boards, tickets, queries, databases, notebooks, journals, templates | `editor/`, `book/`, `notes/` | in the app 2026-10-08 (`lib/root/note_desk.dart`, `lib/root/library_reads.dart`, `lib/root/ghost_root.dart`): boards, queries and a ticket's panel drawn in a note, the notebook's index and the journal's entries, the + sheet and New notebook, a blank note's names and template cards; **not yet on the Fold**; see "What stages 5 and 6 left open" |
| 6 | Canvas | `canvas/` (3.5k) | in the app 2026-10-08 as a note's own view (`NoteSeams.canvas`), made from the + and from a notebook's index; a team's canvas (6G) since 2026-10-09: its structure in the team's document (`native/src/crdt.rs`, `lib/team/doc.dart`), drawn and edited through it with the other members' pointers (`lib/live/team_canvas.dart`), held to the web's own Yjs and its own canvas adapter, and walked on the emulator 2026-10-09 with the web's client as the other member (its pointer drawn, a card's words reaching it); its comments in the note's own sheet, the card a member has open ringed and Jump to cursor on a canvas since the same day, held by tests; **not yet on the Fold** |
| 7 | Account and sync: keys, the sync engine, organizations and team notes, live typing, notifications, shared links | `core/sync`, `core/orgs`, `core/live`, `share/` | in the app 2026-10-08, **off unless the build is given `--dart-define=GHOST_API=http://…`** (`lib/root/account_wiring.dart`); walked on the emulator against the service run on this Mac (sign up, sync read back by a second device, an organization, a team note, a shared link); links that open the app are followed since 2026-10-09 (`lib/root/ghost_root.dart`, `lib/core/phone_links.dart`: a note, the notifications, an organization, an invitation asked about first, a shared link's copy); live typing since 2026-10-09 (`lib/live/`, `lib/root/account_wiring.dart`, `lib/root/note_desk.dart`): the relay, a team note's room with the others' carets, presence, the nudge, a note of the account's own, proven by two Dart devices and by the web app's own client under Node through the relay on this Mac, and **walked signed in on the emulator 2026-10-09** against the service on this Mac (the walk, the bugs it found and what it did not reach are under "What stage 7 left open"); the "Live typing" switch is the device's own flag since then. The phone's own notifications are not ported |
| 8 | Voice and AI: the recorder, Whisper, meetings and their service, summaries, the language model, fills, the at-work scene | `capture/` (12k), `ai/` (6.5k), `tapes/`, `scene/`, Kotlin (6.5k) | Speak in the app 2026-10-09 (`lib/root/voice_wiring.dart`, `lib/root/capture_route.dart`, `lib/root/ghost_root.dart`): the dock's microphone, a note's own and a journal's spoken entry, the capture screen with its live page, the meeting service and its screen, the + sheet's Meeting, Settings' Recording and AI pages with their real rows; the summary queue, the review's gate and the write-up's configuration (lib/ai's), a spoken note's tape played by the phone, a landing's Undo; walked on an Android emulator; the AI in a note (`NoteAi`), the fills' queue, the gists and the scene since the third pass, run on the emulator with Qwen3.5 2B; **not yet on the Fold**; see "What stage 8 left open" |
| 9 | The rest: backup, export, plugins, the Academy and the guide, diagnostics, updates | `plugins/`, `academy/`, `guide/`, `diag/` | 9A to 9C (the library's folder, backup, export) walked on the emulator 2026-10-09, and in Settings since (`lib/root/ghost_root.dart`); see "What stage 9A to 9C left open". The plugins (in Settings and in a note), the Academy, the walkthrough and the guide's notebook, link previews, Developer's benches and its resets are in the app 2026-10-09 (`lib/root/plugin_ground.dart`, `reset_wiring.dart`, `note_desk.dart`, `ghost_root.dart`); the app's own updates (9I: `lib/core/updates.dart`, `lib/root/update_wiring.dart`, `tool/release.md`) and the invitation's card are in the app 2026-10-09, the updates run on the emulator against a made-up release and **on in no build** until a key and a release address are chosen; a note's place, a picture from the phone, the phone's calendar for a date and a voice memo's player are in the app 2026-10-09 (`Position.kt`, `Pictures.kt`, `DayPick.kt`), walked on the emulator; a film picked, kept and played, and a picture pasted from the clipboard, since the same day (`Films.kt`, `FilmPlayer.kt`), walked there too; the phone's own update notifier is not ported, and what it needs is written down; see "What stage 9's other pieces left open" |
| 10 | Platforms and release: the Fold's wide layouts, Mac, Windows, iPhone; signing; moving a library over from the Tauri app | `core/useWideScreen.ts`, `core/unfold.ts`, `aside/`, app.css `.app-split`, the hinge in `MainActivity.kt` | the Fold's wide layouts in the app 2026-10-09 and compared with the page side by side on an emulator at the unfolded size (1848 x 2448 at 420 dpi, a window of 704 x 933): the aside (`lib/aside/`), the docked sidebar and the aside kept to the device, the unfold and its hinge channel (`lib/core/unfold.dart`, `Hinge.kt`), a mouse's hover on a phone, a fold that keeps the screen it had (`lib/shell/app_shell.dart`); a second leg the same day held the recorder, a notebook's index, a ticket's panel, the note's narrowest pane and the Fold on its side to the page, with the phone's insets and its lines in the phone's own pixels, and was cut short by a restart with the rest of the upright walk not done; **not yet on the Fold**; see "What stage 10's wide layouts left open". Windows, signing and moving a library over are other hands' or not begun. The Mac app builds and runs 2026-10-09 (`macos/`, `tool/build-native.sh mac`): not sandboxed, its files in a folder of its own that is never the Tauri app's, `ghostmd://` claimed, the core bundled universal, the window under its title bar with the lights in the page's row, a menu bar and a desktop's keys, the Mac's half of the channels in Swift, drives and Eject as the Tauri app's, a take and a meeting recorded and transcribed on the fixture, and twenty pictures of it beside the page drawn in WebKit; not signed, not notarised; see "What the Mac app left open". The iPhone app builds and runs in the simulator 2026-10-09 (`ios/`, `tool/build-native.sh ios`): under its own id with its files in its own container, the core static and linked into the app without the engines, no recorder and no AI as the real iPhone app has none, the iPhone's half of the channels in Swift, a bar with Done on the keyboard, and walked from the guide to Settings in dark and light; not on a phone, not signed, nothing uploaded; see "What the iPhone app left open" |

The web app is about 110,000 lines of TypeScript, 21,500 of CSS, 27,000 of Rust and 6,500 of Kotlin, with 5,600
tests. Parity is the bar for every stage; a stage is not done until its screens have been compared with the web app's
on the same phone.

## What the diagrams left open

A ```mermaid fence is drawn as its diagram since 2026-10-10 (`lib/editor/diagrams`; docs/PARITY.md's Missing 3): in
a note, on a canvas's chart card read and open, in the Academy's page and the cheat sheet's row. Mermaid itself
draws it, the 12.0.0 `../glyph` pins (`assets/diagrams/mermaid.min.js`: 5.6 MB in the folder, 1.6 MB of an apk),
on a page of the app's own in the platform's web view, which is never shown: in no window on Android, behind the
app's own view on a Mac and an iPhone. The page is the web app's as far as a diagram can tell (the same settings,
the body's face for measuring, the editor's nest of boxes and the rules that reach a diagram in it), the web view
is photographed where the diagram is, and the note shows the picture. `tool/diagram_page.mjs` brings Mermaid, its
licence and the font rules from `../glyph`; `lib/main_diagrams.dart` is a note of diagrams alone, for a platform's
half of the channel to be looked at with no library under it.

- **Held to the web app** (`tool/diagram_reference.mjs`, the web app's own `Editor` and the page in one browser):
  twelve diagrams, light and dark, Maple Mono and Inter, a phone's width and a wide one. The blocks are the same
  size and the pictures in the same place in all forty-eight, in Chromium and in WebKit; in Chromium thirty-six
  are the same pixel for pixel, and in the other twelve only an edge's pixels differ (a pie's rim, a letter's stem
  drawn a part of a pixel across). What looked wrong is the web app's own: a label is measured in the interface's
  face and drawn in the note's, so in Maple Mono "Friday: drive up" is cut at "Friday: drive", there as here.
- **Seen on the Android emulator** (emulator-5586, API 36, its WebView 133, a debug build, 2026-10-10; pictures in
  the session's scratchpad, `emu/NN-name.png`): a note of six diagrams, dark and light, each its words until its
  picture came (the first some two seconds after the note opened, which is the web view being made and Mermaid
  read; the rest a fifth of a second apart), the one written wrong with "That diagram has a mistake: Parse error
  on line 3:"; the app stopped and opened again showed them without the web
  view being asked; a tap put the caret in the fence, a line typed there asked for nothing, and leaving it asked
  for one picture; two chart cards on a canvas; the Academy's lesson after Show me. A picture took 5 to 64 ms of
  the main thread in all, in strips of at most 160,000 pixels with the note's frames between them.
- **Seen on the Mac** (a debug build of `lib/main_diagrams.dart`, 2026-10-10): the web view behind the app's view
  drew all five and the mistake, as the pictures kept in the app's cache folder show. The iPhone's is the same
  file (`apple/DiagramRenderer.swift`), compiled for it and never run: no iPhone build was made.
- **What differs from the page**, each said where it is written (`lib/editor/diagrams/diagrams.dart`,
  `store.dart`): a picture is a bitmap made for one width at the device's ratio, so a canvas zoomed in past its own
  size shows it soft, and a note at another width asks again once the width is still; a block whose words change
  under it (the Academy's page, a note someone else is writing) keeps the picture it has until the new one is
  made, where the page shows the words in between; one drawn here before waits for its picture as its remembered
  height of nothing; an edge Mermaid animates stands still; a diagram that names a picture on the internet draws
  without it (nothing is fetched); and the pictures kept are bounded (32 MB in memory, 240 in the folder).
- **Not done**: a query shown as a timeline is still the port's own drawing (PARITY's Differs 23), though the same
  store would draw Mermaid's (`drawDiagram` on the page). A phone whose Flutter ratio is not its display's density
  gets a picture at the density and shows it resampled. The first diagram of a run makes the web view on the main
  thread after loading its library off it; how long that stops a frame on a real phone was not measured.

## What stage 10's wide layouts left open

What decides "wide" is the page's own two questions, already in the shell before this stage and unchanged: a header
has more room from 600px (`wideScreen`), and the window is in two panes from 660px wide and 600px tall
(`splitFits`, stamped `data-split` on the root so every rule that asks reads one answer). The Fold opened is a
window of 704 x 933 (2448 x 1848 px at 420 dpi) either way up, so it is split upright and on its side. The page's
containers ask their own widths (`44rem`, `52rem`), and so do the port's.

Looked at side by side with the Tauri app on an emulator set to the Fold's inner display (`wm size 1848x2448`, the
density left at 420, which is the Fold's; pictures in the session's scratchpad, `wide/NN-name-AB.png`), 2026-10-09:

- **Matched as they were found** (ported by the stages that built them): the top bar and its two rows; home, with
  three cards across; the notes' card; Settings' split view with its sections column and its own smoke; a note and
  its More sheet (a sheet is the window's whole width on the page too: nothing becomes a centred card); the
  journal, a row to a line; the + sheet; an empty canvas and its tools; Appearance's Sidebar card.
- **Ported in this stage and matched:** the aside as a card at the right (a notebook's index, the open page
  ringed) and as a docked column; the docked sidebar's column with the home page or a note in the rest; the bar's
  mirrored icon. `test/aside/` holds the card to the page's rectangles at 704 x 933 and 2.625
  (`fixtures/aside_704.json`, read from the app's own WebView); `test/root/wide_test.dart` holds the columns
  (300, the rest, 240), the device's memory of both, and a fold.
- **A press on a card's own icon closed the card and opened it again** (the notes', the bell's): the icons are
  their cards' toggles now (`FloatingCardToggle`), as the page's `[data-sidebar-toggle]` is.
- **Folding and unfolding:** the place is one child of one row whether the window is one pane or two, so a fold
  keeps the note's screen itself: its scroll, its caret, what was typed. The page makes the note again when its
  panes change (`core/useWideScreen.ts` says so of the keyboard); this is kinder than the page and is not the
  page's. Walked on the emulator with `wm size` between the cover's 1248 x 1972 and the inner display: a canvas
  and a recording under way each stayed; a note's scroll is held by the test.
- **The unfold** (the note flattening with the hinge) is the page's machine case for case and the page's
  transforms, fed by `TYPE_HINGE_ANGLE` through `ghost_md/hinge`. **Never seen move:** an emulator has no hinge, and
  the Fold has not had this build. On One UI the hinge sensor's readings while the app is handed from the cover to
  the inner display are what the page was tuned on; whether Flutter's surface is up in time to draw the first of
  them is unknown.

A second leg, 2026-10-09, on the same emulator, upright, on its side (`wm size 2448x1848`, a window of 933 x 704)
and at the cover's width. It was cut short by a restart of the Mac that night, and the walk is paused. Its pictures
(`wide/21` to `44`) were in the session's scratchpad under `/private/tmp` with the first leg's and went with the
restart: what each showed is said here, and what was measured is in the tests named.

How the two were driven, for whoever goes on: the Tauri app through its WebView's devtools socket (`adb forward
tcp:<port> localabstract:webview_devtools_remote_<pid>`, forwarded again whenever the app restarts: a button pressed
by its label, `getBoundingClientRect` and `getComputedStyle` read, a Settings pane scrolled by its `scrollTop`), and
this app by `uiautomator dump`, whose nodes are its semantics labels with their rectangles (a tap on a label's
middle). Two Settings pages are brought to the same place by reading where this app shows a heading and scrolling
the page's pane until its own is there. A fling does not stop where it is left: drag with `input motionevent`, the
finger held still before it lifts.

- **The phone's insets are whole CSS pixels, rounded up** (`packages/glacier/lib/src/tokens/theme.dart`), as a
  WebView gives them to the page: the emulator's status bar is 159 device pixels unfolded (61px to the page, 60.57
  here before), 128 at the cover's width (49) and 120 on its side (46), which stood everything under the bar a
  device pixel high beside the page. Up, because Chromium's `adjustInsetForScale` is a ceiling as it is remembered;
  the three bars measured would each come to the same whole pixel rounded to the nearest, so a bar whose fraction
  is under a half (the Fold's has not been read) is where the two would part, and is not settled.
- **The recorder**, both apps recording silence (the Tauri app given the microphone with `pm grant`): the top
  line, the empty page, the ghost, the hint and the card of things to say, upright, at the cover's width and on its
  side. Its top line was never off by the 19px: the page's line is as tall as its word, an `.app-word` with the
  touch target's least height (56.96px), so its words stand 20px under where `.top`'s padding alone would put
  them, on the page as here (measured on both, and within a device pixel of each other). What was off and is not
  now: the lines' heights (a line of things to say is 18.45px, the small capitals and headings a line of
  `line-height: normal` in the phone's pixels; the card's foot stood five device pixels short), the hint (the page
  says "Press the side key to stop" wherever its host can tell the screen went off, which the phone can with or
  without the assistant; `lib/root/voice_wiring.dart`), and the Fold on its side, too short for the note's page,
  the ghost and the hint over the card: there the page keeps the note's page the top line's room and lets the hint
  run over the body's foot, where this had the ghost under the top line's glass. Held by the page's rectangles
  read from the Tauri app's WebView: `test/capture_ui/fixtures/rest-704x933.json` and `rest-933x704.json`.
- **The meeting screen** matched, once both had been asked about notifications (the page's third line, "Let
  Ghost.md tell you when it is written up", is there until they have): the cassette, the two lines, the buttons.
- **A notebook's index under its words**: `:global(.app-split) .editor .cm-editor .cm-content { padding-block-end:
  var(--glacier-space-8) }` has four classes to beat the theme's two, and so beats `.preface`'s and `.peek`'s
  three: on the split layout every editor inside the panes keeps that room under its last line, a notebook's words
  and a card's preview with them. That is the 37px, and a phone's width has none of it (looked at there too). The
  panes wear the page's class (`GlacierScope(classes: {'app-split'})`, `lib/shell/app_shell.dart`) and
  `LookEnv.splitRoom` is the rule; a note in the panes had kept the phone's tall room under its last line
  (`--glacier-space-24`) and has the paragraph's now, by the rule: a note's foot was not looked at beside the
  page. The index is held by `test/root/wide_test.dart`.
- **A ticket's panel is as narrow as the page's and no narrower** (`lib/editor/tickets/ticket_panel.dart`): its
  least is its narrowest content's, worked out as the page's comes out (the names' column and its gap, the values'
  `minmax(0, 1fr)` being nothing when a grid is asked how narrow it can be; what it waits on, the title whole
  because it is `nowrap` and the key at one letter because the editor's words break anywhere; the head; the foot),
  where it was 300 for every ticket. In the 164px pane the Example project's third ticket is the page's 196.15,
  its rows, its day beside its cross, its links and its Add where the page has them
  (`test/editor/tickets/ticket_narrow_test.dart`). The row that ran over at 300 was a day's: a Row gave the chip
  all the room and its cross 6.5px. A value too long for its column is cut with no ellipsis, as the page's chip
  is, a flex row whose words `text-overflow` does not reach; a notebook's card cuts a page's name the same way.
- **A page's bar in that pane** gives way as the page's does: the mark, the notebook's name and the count each
  lose room in proportion to their width (`lib/book/book_nav.dart`, `test/book_ui/reference_test.dart`).
- **What the page asks of the screen's pointer is asked of the screen**, not of what is plugged in
  (`lib/shell/wide_screen.dart` `mousePointer`, `hoverPointer`). Asked of the Tauri app's own page on the
  emulator, whose touch screens are styluses too: `(any-pointer: fine)` true, `(pointer: fine)` false, `(pointer:
  coarse)` true, `(hover: hover)` false, `(any-hover: hover)` false. A page's two questions are about the primary
  pointer, which Chromium on Android makes the coarse one while there is one. Three places here asked something
  else and ask the platform now: a folder's More and a notification's cross waited to be pointed at while a mouse
  was connected, the + in the gutter took its hover ink from any mouse, and a canvas's picked card had eight
  handles after a mouse's press. What a mouse gets on a phone is what asks the event: an unguarded `:hover`, a
  right-click's menu, a card dragged without being picked. **Not tried with a real mouse** (`adb emu event mouse`
  was not to be used), so `(hover: hover)` with a mouse and nothing else was not asked.
- **The lines of a line box are the phone's own pixels.** A face's ascent and descent are rounded to a device
  pixel and half a line's leading floored to one: in the editor (`lib/editor/looks/look.dart` `_box`, held by the
  page's content areas for the note's words and four sizes of heading, `test/editor/view/device_lines_test.dart`)
  and in `ExactLines` for a line with a height of its own (`leadedBaseline`, Settings' title). `ExactLines` also
  takes the exact line for a style the engine drew a pixel beside its rounding: the app's `pageText` says 20 for a
  label the page makes 20.57 and whose rounding is 21, so no line was taken for exact and a sheet's rows with a
  hint stood five device pixels short each. Seen after: a sheet's rows on the page's (the More sheet on its side);
  a note's paragraphs a steady one device pixel high where they had drifted one to two; Settings' title one low
  where it was two.
- **On its side**, beside the page: a note, the sidebar docked beside it, a ticket with the aside, Settings, an
  empty canvas, a notebook, a journal, home, the + sheet, the More sheet, the palette, the recorder. They matched
  but for the bottom inset, what is said above, and three things that are not the layout's: this build's + sheet
  has no "From a shared link" (no account), its cards carry a gist (it has a model), and the two apps' recent notes
  are in another order.
- **Upright, the rest, as far as it got:** the notifications card matched. All notes matched but for a notebook's
  card (above). Settings' pages at their tops (Account, Organizations, Workspaces, Notifications, Library folder,
  Backup, Export, Appearance, Recording, AI), and Appearance down its length at the same scroll but for the
  typeface cards' stretch, showed nothing out of place. They were looked at a quarter of their size, several to a
  sheet, so a row a few pixels off would not have shown, and nothing on them was measured. What differed was each
  app's own state (Notifications' "On this phone" card, About's updates, a model downloaded here) and one thing
  that is the page's fault: the chosen interface-size card's label is drawn in the paper's colour there, ink.css's
  rule for the segmented control's chosen label (`[role='radiogroup'] > label[data-selected] > span:last-child`)
  reaching the card's, and cannot be read; here it is in ink, as the card's own stylesheet says.

Still open:

- **Changed after the last build the emulator had, and so held by their tests and not seen beside the page:**
  the recorder on its side, Settings' way back on the page's line (it stood two device pixels low), the command
  palette's headings and rows on the page's lines (its seventh row stood two low), and a notebook's card cutting
  a page's name with no ellipsis.
- **A heading's words in a note** still stand off the page's on the Fold after the lines were put in the phone's
  pixels: the note's name two device pixels low, a section three high, three hashes one low, the paragraphs one
  high (the Fold on its side, "How to format a note"). The look's numbers are the page's, so what is left is in how
  a line of several boxes is set (the dimmed marks, the count beside the name) and was not found.
- **The recorder's chip and its confirm card were not seen beside the page**: they need words, and both apps
  recorded silence. They are held by the page drawn in Chromium at 390 and 1200 only. The page speaks a script
  with `?simulate` in its address, in the Tauri app too, and a debug build here plays `<dataDir>/fixture.wav` with
  `GHOST_MIC_FIXTURE`; neither was used.
- **Upright, not reached:** each top-bar style (Ledger was chosen in both and shot, and the pictures never
  looked at; Masthead and Islands not chosen), a board, each query view, a ticket's panel at the whole width (seen
  on its side, within two device pixels), a canvas with cards and its selection bar, the tape on a spoken note,
  the Academy, the guide. Settings' Plugins page has no pair at its top, and the pages' feet were not all caught
  at the same scroll.
- **The first leg's pictures were not gone through one by one** for their one and two pixels: what was found on
  the way is above. Seen and left: a tab's name and a notebook row's title about a pixel low at the cover's width
  (before the look-and-feel pass's own change to the bar's lines that day), and a ticket's panel one device pixel
  longer than the page's.
- **How the emulator was left** (`ghostflutter`, emulator-5584): `wm size 1848x2448` still set (`wm size reset`);
  both apps' top bar on Ledger, where they had Classic; Sidebar on Docked, the columns hidden; the Tauri app given
  the microphone and notifications by `pm grant`, and its meeting screen's Allow pressed once.
- **The aside's version history** (`AsideHistory`, a desktop's: the page leaves it out on a phone, `!isMobile`).
  `AsidePanel` has the two tabs and takes the history as a widget; nothing gives it one, and the bar's History
  button still opens the More sheet's page. It wants the open note's live words and its restore from the note's
  desk, and is the Mac's to wire.
- **The note between a docked sidebar and a docked aside** is 164px wide on the Fold (704 less 300 less 240), on
  the page as here, and its panel and its bar are the page's there now. Its own lines are not: the page lays the
  whole note out as wide as the panel's least (244px for the third ticket) and the pane cuts it, and its editor
  can be dragged sideways (`.cm-scroller { overflow: auto }`); here the lines wrap in the pane's 164 and nothing
  moves sideways. The bar's two sides, whose columns are nothing at that width, draw nothing here, where the
  page's are their padding with no arrow in it.
- **The bottom inset.** The emulator's WebView (Chrome 133) gives the page no `safe-area-inset-bottom` under the
  gesture bar, so the page's dock, sheets and the guide's button sit 24px lower than the port's, which reads the
  phone's own inset. Its page is also taller than its window by a fraction (933.33px in 932.57 unfolded, 752 in
  751.24 at the cover's width), which is two device pixels more on whatever stands on the page's foot. The Fold's
  WebView is newer and may give the page the inset; not settled here.
- **Pictures in other folders that fail at wide sizes on this Mac** (`test/sidebar` "wide", `test/note` "at 840")
  moved by a few pixels while the Mac's own work was in the tree (the bar's left edge and the status inset are a
  Mac's there under a test run on one); they were not redrawn here. `test/editor/plus/plus_reference_test.dart`'s
  fifty pictures failed by a hundredth of a percent each on 2026-10-09, with this leg's change to the + and
  without it.

## What the Mac app left open

**What is there (2026-10-09, second pass).** `tool/build-native.sh mac` then `flutter build macos --debug` (or
`--release`) makes `Ghost Flutter.app`: bundle id `com.mattssoftware.glyph.flutter`, the Tauri Mac app's icon,
macOS 13.1 and later, Apple silicon and Intel in one file, as the Tauri app is. It installs beside the Tauri app.

- **It is not sandboxed** (Matt, 2026-10-09: "un sandbox it"), as the Tauri Mac app is not. Its library, settings
  and models are in a folder of its own, `~/Library/Application Support/com.mattssoftware.glyph.flutter`, its caches
  in `~/Library/Caches/com.mattssoftware.glyph.flutter`, and what it remembers in its own defaults
  (`~/Library/Preferences/com.mattssoftware.glyph.flutter.plist`, through `shared_preferences`). With no sandbox
  between them, **only the app's own code keeps it out of the Tauri app's
  `~/Library/Application Support/com.mattssoftware.glyph`**, so that is held twice: the Swift that names the two
  directories answers nothing for a build with the Tauri app's id or for a path that is its folder or inside it
  (`macos/Runner/GhostChannels.swift` `ownDirectory`), and the Dart refuses the answer the same way before the core
  is opened (`lib/core/mac_app.dart` `isRealAppPath`, `DevicePaths.own`), with a test of every way a path could be
  made to mean that folder (`test/core/mac_app_test.dart`). Its secrets are Keychain items under the service
  `com.mattssoftware.glyph.flutter.secure`. A debug build has no service, no mirror and no updates, as on the phone.
- **What a sandboxed run left behind**: the first pass ran sandboxed, so `~/Library/Containers/
  com.mattssoftware.glyph.flutter` holds that pass's test notes, a test recording and a copy of the small voice
  model. Nothing reads it now and nothing was moved out of it; it is left where it is, and can be thrown away.
- **It claims `ghostmd://`** (Matt: "claim it"): `CFBundleURLTypes` in `macos/Runner/Info.plist`, and the app
  delegate hands each link to the links' channel at launch and while it runs, where the root follows it as on the
  phone (a note, the notifications, an organization, an invitation, something shared). **On a Mac with both apps
  installed macOS hands a `ghostmd://` link to one of them, and it is macOS that chooses.** On this Mac the Tauri
  app in /Applications is still the one chosen (asked of `NSWorkspace`, read only, before and after); the built
  app in `build/` is listed among those that claim it. No link was ever opened through the system here: the tour
  hands a link to the app's own delegate (`link:`), which is how a note's link, the notifications' and an
  organization's were seen to be followed.
- **The core** is the same Rust (`native/`), built per architecture and joined (`macos/Core/libghost_core.dylib`,
  not in git), copied into the app's `Contents/Frameworks` and signed by Xcode's "Bundle the core" phase
  (`tool/bundle-mac-core.sh`), and opened from there by its whole path. Cargo's own `strip` is off for this build:
  with a deployment target set, Xcode 27's `strip` leaves proc-macro libraries macOS 27 will not load.
- **The window** is the Tauri app's (`tauri.conf.json`): 1280 x 820, never under 360 x 560, under a transparent
  title bar with no title, the three lights set into whichever row is the page's top one
  (`lib/shell/desktop/mac_lights.dart`): the tab bar's, the recorder's own line, the guide's bar. The row's empty
  ground drags the window and zooms it on a double click; Settings starts under the lights' row.
- **The menu bar and the keys** (`macos/Runner/AppDelegate.swift`, `lib/shell/desktop/desktop_commands.dart`,
  `lib/root/desktop_wiring.dart`): New Note (Command-N), Sync Now (Command-R, with its toast), Find (Command-F:
  the open note's find bar, which the page reaches only from a note's menu), the palette (Command-K), Settings
  (Command-comma), and the Mac's own Edit, View and Window items. The editor's keys were walked with a keyboard's
  events (typing, the arrows, Command-Z and Command-Shift-Z, Command-A, Command-Left), a click, a drag, a double
  and a triple click select as the page's do, and the right button opens the note's own menu.
- **Voice and meetings.** The Mac's microphone is `macos/Runner/MicChannel.swift`. A meeting is the recorder
  itself in meeting mode, offered from the + as in the Tauri Mac app (`lib/root/capture_route.dart`), and the Mac's
  own sound goes into it through the Tauri app's Core Audio tap, included as it is and mixed into every chunk the
  capture is pushed (`native/src/kept/system_audio.rs`, `system_audio/mac.rs`, `lib/capture/core_system_sound.dart`).
  A take and a meeting were each walked start to end on the fixture (`--dart-define=GHOST_MIC_FIXTURE=true`,
  `<dataDir>/fixture.wav`): heard through the Swift half, transcribed live, landed as a note with its tape.
- **Folders, drives and files.** A chosen library folder is its plain path (`library_inspect {path}`, no bookmark).
  Backup is the Tauri Mac app's own page: the core lists the removable drives (`backup_drives`: `/Volumes` and
  `diskutil`, its lines), a backup goes to a drive by its path with nothing to allow first, and Eject is
  `diskutil eject`. Export is the Mac's save panel handing the core a descriptor.

**Each channel** (`MethodChannel(` in `lib/`), and its Mac half:

| Channel | On the Mac |
| ------- | ---------- |
| `ghost_md/device_paths` | Swift: the app's own two directories, never the Tauri app's |
| `ghost_md/open` | Swift: `NSWorkspace`, the same schemes; `geo:` opens Maps |
| `ghost_md/secure_store` | Swift: the Keychain, one generic password a name, under this app's own service |
| `ghost.md/reset` | Swift: forgets the Keychain's service; no meeting service to be recording, no work queue to cancel |
| `ghost_md/files` | Swift: the folder panel for Library folder and the save panel for Export. The drives, the backup and Eject are the core's, not a channel's |
| `ghost_md/pictures` | Swift: an open panel for a picture, shrunk to 1600 px and turned as the phone's is; a picture or words off the clipboard |
| `ghost_md/tape` and its events | Swift: `AVAudioPlayer` on `<dataDir>/recordings/<id>.wav` (one file for the Mac and the iPhone) |
| `ghost_md/mic` and its events | Swift: the microphone, its permission, System Settings, the debug fixture |
| `ghost_md/links` | Swift keeps each `ghostmd://` link macOS hands the app until the page takes it |
| `ghost_md/window` | Mac only: the lights, the drag, the menu's choices, and a debug build's tour |
| `ghost_md/meeting` and its events | none: it is the phone's meeting service, assistant and side key. A Mac's meeting needs none of it |
| `ghost_md/updates` | none: it installs an APK. No build looks for updates on a Mac |
| `ghost_md/day` | none: it is Android's calendar; a date is typed or taken from the menu's own days |
| `ghost_md/location` | none, as in the Tauri Mac app (`core/location.ts`, `why: 'mac'`) |
| `ghost_md/films`, `ghost_md/film` | none, as on the page, where films are Android's alone |
| `ghost_md/front` | none: it holds frames while Android takes the app from the front |

**Beside the page, measured** (`…/scratchpad/mac/ab/`, pairs `NN-name-A.png` the page, `-B.png` Ghost Flutter,
`-AB.png` both). The Tauri app was not opened. The page is ../glyph's own, built with `vite build` into the
scratchpad by a config kept there (nothing written in ../glyph, no `.env` read, a dead API address) and drawn by
Playwright's WebKit at 1280 x 820 and two device pixels to one, with `data-titlebar=overlay`, on the starter notes it
seeds itself; the Flutter app is its debug build's own window, walked by the tour to the same screen, its starter
notes given the page's order. Twenty pairs: home (and scrolled), a note, the sidebar docked, Settings, the
palette, find, a board (and scrolled), a notebook and its side panel, a canvas, the + sheet, home, a note and
Settings in light, and a mouse over a card, a row, a bar's button and the dock's. Between 0.2% (the canvas) and
3.4% of pixels differ by more than a step of 24, the lights and the words' edges among them, and 5.8% on the
board scrolled, where a card's line break moves what is under it; landmarks read on both sides (Recent, Today, a
card's title, the palette's rows, Settings' rows) agree to half a pixel, and a mouse over each of the four draws
the same hover and the same pointer. What it found:

- **Fixed: a desktop's scrollbar.** The page styles one for a view under a header (app.css `[data-under-header]`),
  which takes 12 px from the view, so the home page sat 6 px to the right of the page's and had no thumb. Now
  `lib/shell/desktop/desktop_scrollbar.dart`: the thumb is the page's to the pixel (6 px at x 1271 to 1277, from
  the header's foot, the same length and ink). A note's page takes none, as measured on the page.
- **Fixed: the foot of every page.** The 28 px fade at a desktop page's foot was one gradient with stops a few
  pixels apart on a very long line, and the Mac's engine drew it as a cut 28 px above the window's edge: the last
  row's second line was not there. Two short ramps now (`lib/art/wisp_strips.dart` `fadeRamps`); the row fades to
  the edge as the page's does.
- **Fixed: under the lights.** The recorder's first line and the guide's dots began under the window's buttons
  (the page has no rule for either, so the Tauri app's may too); they start after the buttons' room now.
- **Fixed: words.** The + sheet named Android's "sound from other apps" on a Mac; the review's toast said "this
  phone" (it does on the page too, wherever it runs; a Mac says "this Mac" here).
- **Not fixed, and whose it is.** The side panel has no History tab, so a plain note's bar has no Side panel
  button where the page's has (the wide layouts'). Find's field has no clear button and does not select what it
  opens with (the editor's). A board's card fits "Get the photos back" on one line where the page breaks after
  "photos", the columns and cards being the same to the pixel (the editor's boards), and a notebook row's status
  and arrows sit a few pixels further in. Playwright's WebKit draws no backdrop blur, so the page's header and the
  palette's scrim show the page sharp behind them: the blur strip under a desktop's header and the scrim's blur
  were seen in the port and could not be compared.
  The page's + sheet in a browser has no Meeting row to compare, and its fourth Recent card is one of two
  notes made in the same millisecond.

**What a signed release needs** (none of it done here: nothing was signed, notarised or published). The shared
set-up is the Tauri app's (`../glyph/scripts/deploy-ota.mjs --desktop`): team `F6ZAL7ANAD`, the Developer ID
Application certificate in the keychain, and the App Store Connect key every MattsSoftware app notarises with
(`~/.config/mattssoftware/signing/asc-api.env`).

1. `tool/build-native.sh mac` (both architectures), then the release build with the identity and the hardened
   runtime given as build settings, since the project signs "to run locally" and leaves the runtime off (an ad hoc
   build with it cannot load its own frameworks): `FLUTTER_XCODE_CODE_SIGN_STYLE=Manual
   FLUTTER_XCODE_DEVELOPMENT_TEAM=F6ZAL7ANAD FLUTTER_XCODE_CODE_SIGN_IDENTITY="Developer ID Application: …"
   FLUTTER_XCODE_ENABLE_HARDENED_RUNTIME=YES FLUTTER_XCODE_OTHER_CODE_SIGN_FLAGS=--timestamp
   FLUTTER_XCODE_CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO flutter build macos --release`. Untried. The last of those
   keeps `get-task-allow` out, which notarisation refuses. The core is signed with the same identity, the runtime
   and a timestamp by `tool/bundle-mac-core.sh`.
2. **The entitlements are a non-sandboxed app's**: `macos/Runner/Release.entitlements` holds
   `com.apple.security.device.audio-input` and nothing else, as the Tauri app's does. Under the hardened runtime
   that one is what opens the microphone (without it: no prompt, and a recording of silence); the network, a chosen
   folder and a drive need none. The Info.plist says why for each thing macOS asks about: the microphone, the Mac's
   own sound (`NSAudioCaptureUsageDescription`, for the tap), and Documents, Desktop, Downloads, a drive, a server
   and a file provider's folder for a library kept there.
3. The checks `deploy-ota.mjs` makes of the Tauri app, made of this one before anything goes out: `codesign
   --verify --deep --strict`; the team; `runtime` among the flags; the audio-input entitlement and
   `NSMicrophoneUsageDescription`; both architectures in the executable **and** in
   `Contents/Frameworks/libghost_core.dylib`.
4. A disk image made, then the image sent to Apple and stapled as well as the app (`xcrun notarytool submit … --wait`,
   `xcrun stapler staple`).
5. Decisions: which id it ships under; where its updates come from; and what happens to `ghostmd://` on a Mac that
   has the Tauri app too.

**Left open:**

- **The real microphone and the Mac's own sound were not listened through.** A take and a meeting played the
  fixture; opening the device would have recorded the room of the person using this Mac, and opening the tap would
  have raised macOS's consent and recorded what the Mac was playing. The tap is the Tauri app's file unchanged, its
  mixer has a test of its own here, and `system_audio_available` answers; `system_audio_start` was never called.
  `noiseSuppression` and `autoGainControl` are heard by the microphone and not acted on.
- **A panel's own buttons were not pressed.** The folder, save and picture panels were each put up as the sheet
  they are and closed again by the tour, with what they are taken to have chosen said by the tour (a folder and a
  file of its own in the scratchpad), since a panel is drawn by a process of macOS's and its buttons are a hand's:
  Library folder went on to look into the folder and ask "Use vault?", Export wrote its zip there, and a picture
  was kept. A folder really chosen by a hand, and the move into it, were not walked.
- **No drive was plugged in**: Backup lists none and says "Plug in a drive"; the list, a backup onto a drive and
  Eject are the Tauri app's lines over the same `backup.rs`, tested as far as a Mac with no drive can be.
- **A drag of the window was not made.** The strip is under the bar's empty ground in the running app and tells
  the window to follow, which answers that no button is down: a real drag needs a real mouse.
- **The side panel's History and its button on a plain note**, find's clear button, and a board card's line
  break, as found beside the page (above).
- **The fill hint in a note's settings** ("Nothing leaves this Mac") is not in the port for any device.
- **The Keychain after a rebuild**: an ad hoc build is a different signature each time, so macOS may ask before a
  later build reads a secret an earlier one kept. A signed build does not ask.
- **The Intel half was built and not run** (no Intel Mac here).
- **Moving a library over from the Tauri Mac app** is not done, and is not to be done by reaching into its
  folder: choosing a folder in Library folder that both apps can use, or an export and an import, are the ways.

To look at it without touching the screen: a debug build walks itself from a script in its environment and writes
the window's picture into its temporary folder (`lib/shell/desktop/mac_tour.dart`).

## What the iPhone app left open

**What is there (2026-10-09).** `tool/build-native.sh ios` then `flutter build ios --simulator --debug --no-pub` makes
`build/ios/iphonesimulator/Runner.app`: bundle id `com.mattssoftware.glyph.flutter`, named "Ghost Flutter", the real
iPhone app's icon, iOS 15 and later, an iPhone's alone (`TARGETED_DEVICE_FAMILY` 1, as the real app's first version
is). It installs beside the real app and shares nothing with it: an iPhone app sees only its own container, its
library is `<container>/Library/Application Support/com.mattssoftware.glyph.flutter/Library`, and
`ios/Runner/GhostChannels.swift` refuses to name a data directory at all for a build carrying the real app's id. Its
secrets are Keychain items under the service `com.mattssoftware.glyph.flutter.secure`, kept for this device alone
(`apple/Keychain.swift`). A debug build has no service, no mirror and no updates, as on every platform.

- **The core** is the same Rust (`native/`) as a STATIC library, since iOS loads no loose dylib out of an app:
  `cargo rustc --crate-type staticlib` for `aarch64-apple-ios-sim` and `aarch64-apple-ios`, kept apart in
  `ios/Core/GhostCore.xcframework` (not in git) and linked into the Runner. Nothing compiled there calls it, so
  `ios/Runner/GhostCoreKeep.c` names its five functions in a table the linker must keep, the Runner strips only what
  is not global (`STRIP_STYLE`), and Dart finds them in the app's own process (`lib/core/native/ghost_worker.dart`
  `openCore`, `DynamicLibrary.process()`). A build with no library for what is being built stops and says so
  (`tool/find-ios-core.sh`). The simulator is Apple silicon's alone (`EXCLUDED_ARCHS` leaves x86_64 out: there is no
  Intel slice of the core). Cargo's `strip` is off, for the Mac's reason.
- **Without the engines, as the real iPhone app is.** The Tauri app builds neither whisper.cpp nor llama.cpp for
  iOS (`src-tauri/Cargo.toml`, `src/unsupported.rs`), and its page leaves out every way into a recording there
  (`core/platform.ts` `recordsVoice`: "Notes-only first version"). So the iPhone's core is the notes-only one
  whatever `GHOST_VOICE` says, nothing of voice is made (`lib/core/iphone_app.dart` `recordsVoice`,
  `lib/main.dart`), and there is no microphone in the dock, in a note, on a tape, in the palette or in the + sheet,
  no Recording, AI, Library folder or Backup in Settings, and the guide says "Notes you type."
  `GHOST_IOS_VOICE=1 tool/build-native.sh ios` asks for the engines all the same and is **untried**: it would also
  want a microphone in Swift (the Mac's `MicChannel.swift` is `AVAudioEngine` and close, less an `AVAudioSession`),
  `NSMicrophoneUsageDescription`, and a decision, since the real app ships without.
- **What the real iPhone app's page answers, answered here** (`lib/root/iphone_wiring.dart`, each with its rule):
  About says "Ghost.md updates through the App Store." and lists no releases; Export says "Exporting isn’t on iPhone
  yet."; the Location card and a note's Add my location say "Ghost.md can’t find where you are on this device yet."
  and the +'s A place is not drawn; the + beside a line has no A picture or A video, while the note's own menu and a
  canvas add a picture (the page's file input there; here the phone's own menu of Photo Library, Take Photo and
  Choose File); the More sheet keeps its AI rows and a press says "The AI is not on iOS yet."; a tape synced from
  another device offers no Add; Notion and Slack are listed and their requests are refused in Rust's words
  ("Notion is not available on iOS yet."), GitHub works, and no link's preview is fetched.
- **An iPhone's page** (`lib/app/iphone_page.dart`): the phone's text size and Bold Text are left alone, as a web
  view leaves the page's px and rem; the keyboard has a bar with Done on it, in the page's paper, where WebKit lays
  its own accessory bar, and every screen is laid out above both (they all read `MediaQuery.viewInsets`); the
  status bar's ink follows the phone's light or dark, as the real app's does; a selection has the phone's own
  handles, a bar and a knob in the caret's colour, and a caret has none (`GlacierTextSelectionControls`); success,
  warning and error are the phone's notification haptics.
- **How a page scrolls is said once** (`lib/core/page_scroll.dart`, put over the app in `lib/app/ghost_app.dart`):
  an iPhone's rubber band and momentum, a Mac's, and a list that stops at its ends on Android, as each platform's
  own engine scrolls the web app's page. No screen names its physics any more (Home, All notes, an organization's
  page and its log, Settings, the guide, the + list, the band, a table, a board, a query, a card's words), and a
  screen with a behaviour of its own extends the app's. A page under a pull to refresh holds its top for the pull
  and stretches at its foot (`pullRestPhysics`). A board's lanes keep their own snap, and the tabs' row its coast.
- **`ghostmd://` is claimed** in the Info.plist, as the real iPhone app claims it (`src-tauri/Info.ios.plist`), and
  a link is handed to the page through the scene (`GhostChannels` as a `FlutterSceneLifeCycleDelegate`). `glyph://`,
  which the real app keeps for a shortcut nothing answers, is not. An iPhone with both apps hands a link to
  whichever it chooses.

**Each channel, and its iPhone half** (`MethodChannel(` and `EventChannel(` in `lib/`):

| Channel | On the iPhone |
| ------- | ------------- |
| `ghost_md/device_paths` | Swift: `<Application Support>/<bundle id>` and `<Caches>/<bundle id>` in the app's container |
| `ghost_md/open` | Swift: `UIApplication.open`, the same five schemes; `geo:` opens Maps |
| `ghost_md/secure_store` | Swift: the Keychain (`apple/Keychain.swift`), this device only, after first unlock |
| `ghost.md/reset` | Swift: forgets the Keychain's service; no meeting to be recording, no work queue |
| `ghost_md/links` | Swift: `ghostmd://` links from the scene, kept until the page takes them |
| `ghost_md/pictures` | Swift: a menu of `PHPickerViewController`, the camera and the Files picker, the picture shrunk to 1600 px and turned (`apple/PictureKeep.swift`); a picture or words off `UIPasteboard` |
| `ghost_md/tape` and its events | Swift: the Mac's own file (`macos/Runner/TapeChannel.swift`, compiled into both), with the audio session set to playback |
| `ghost_md/day` | Swift: `UIDatePicker` in a sheet (`DayChannel.swift`), where the page's date input opened the phone's calendar |
| `ghost_md/mic` and its events | none: the real iPhone app records nothing. No recorder is made |
| `ghost_md/meeting` and its events | none: Android's service, assistant and side key. No Meeting in the + sheet |
| `ghost_md/files` | none: no library folder, no export, no backup on an iPhone, as on the page; Export says so and the other two are not listed |
| `ghost_md/location` | none: the page's `locateHere` answers `ios` there, and the Dart says its sentence |
| `ghost_md/films`, `ghost_md/film` and its events | none: films are Android's alone |
| `ghost_md/updates` | none: it installs an APK. About says the App Store updates the app |
| `ghost_md/hinge`, `ghost_md/front` | none: the Fold's hinge, and Android taking the app from the front |
| `ghost_md/window` | none: the Mac's window |

**Walked in the simulator** (my own iPhone 18 Pro on iOS 27.0, 402 x 874 at 3, safe areas 62 and 34; the newest
runtime here, 27.1, has only the folding iPhone Duo, which was not walked), by a debug build's tour of itself
(`lib/shell/phone_tour.dart`, `tool/ios-tour.sh`: a finger's events given to Flutter's own gestures, words typed
through the keyboard's own client, pictures by `xcrun simctl io`; nothing is ever sent to the Mac's screen). Seen,
in dark and then light: the walkthrough's four pages ("Notes you type.", the theme, the models with no line about
getting one, the hand-over) and its "Not yet" on a relaunch; home with no microphone in its dock, beside the real
app's App Store picture of it; the sidebar's card, the bell, the palette with the keyboard and its bar; a note,
typed into, Done, held for its band, More with its AI rows and the toast; the + sheet (no Meeting), a blank note's
names and templates, the + list and its More; a board, a notebook's ticket beside the real app's; a canvas, a card
written, and the phone's picture menu; Settings' eight sections, Account with its ghosts and the Location card,
Appearance to its end, About, Export, and a swipe across Settings going back; each channel asked something harmless
(paths, a secret written, read and removed, a tape, the links, a reset, a refused scheme, and the absent ones
saying they are absent). The wisp's smoke at a page's top and foot and the dotwork ghosts draw on Impeller over
Metal; the faces are the app's own. A second walk the same evening, in dark, saw what the first had not reached:
Settings › About › Examples' canvas made and opened with its ten cards, the sidebar with Browse files among its
tools, Settings › Plugins and Notion's own page, a `{?…}` blank drawn in a note with no Fill, the find bar resting
on the keyboard's bar with its count, and a ticket's Due sheet with the phone's calendar opened from Pick a date.
The pictures of both walks were the session's own and are not kept.

**What a TestFlight or App Store build needs** (none of it done: nothing was signed with a distribution identity,
uploaded, or asked of App Store Connect). The real app's own road is `../glyph/docs/store/APP_STORE.md` and
`~/Development/Apps/ghost-md-app-store-pack`; what carries over and what does not:

1. **Which app it is.** The store's record is Ghost Markdown (6818598896), `com.mattssoftware.glyph`, whose build
   1.10.0 is uploaded; this project is `com.mattssoftware.glyph.flutter`. Either a record of its own under that id
   (a TestFlight beside the real app, sharing nothing), or the real id, which makes it the real app's update: then
   its number must be above 1.10.0, the name under the icon is Ghost.md, `GhostChannels.dirs()` must stop refusing
   that id, and the Tauri app's library (`<Application Support>/com.mattssoftware.glyph`, the same layout) is there
   to be opened, which wants proving before anyone's notes ride on it. The version is `pubspec.yaml`'s (0.1.0+1) and
   `ghostVersion`'s, said twice.
2. **Signing**, as the real app's: team `F6ZAL7ANAD` (already the project's), automatic signing with the team's
   App Store Connect key (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` in
   `~/.config/mattssoftware/signing/asc-api.env`) handed to `xcodebuild` as `-allowProvisioningUpdates` with the
   key, Xcode making the store profile itself, and the export's method `app-store-connect`. `flutter build ipa`
   does not pass a key: build with `flutter build ios --release --no-codesign` and archive with `xcodebuild`, or
   sign from a Mac whose Xcode is signed in. Run the export with `/usr/bin` first in `PATH` (Homebrew's rsync
   broke the real app's). **Entitlements: none**, as the real app's file is empty; the Keychain needs none.
3. **The library for a phone**: `tool/build-native.sh ios` builds `aarch64-apple-ios` too. A release link drops
   what nothing reaches and strips symbols: the keep table and `STRIP_STYLE = non-global` are there for it. An
   unsigned release was built to see (`flutter build ios --release --no-codesign`, 40 MB): the core's five
   functions are global in its `Runner` (`nm -gU Runner.app/Runner | grep ghost_`), it is an iPhone's alone, and
   the tour is not in it. **It was not run**: there is no phone here, so whether it opens its notes on one is the
   first thing to check.
4. **A privacy manifest** (`PrivacyInfo.xcprivacy` in the Runner; there is none yet). The real app's
   (`src-tauri/gen/apple/glyph_iOS/PrivacyInfo.xcprivacy`) is the model: no tracking; with an account, User ID, User
   Content and Photos linked to the user for app function (no Audio while nothing records); required-reason APIs
   FileTimestamp C617.1 (the library, SQLite), SystemBootTime 35F9.1 (`Instant`), UserDefaults CA92.1
   (`shared_preferences`), and DiskSpace E174.1 only if something still asks (the engine's did). The App Privacy
   answers must match it.
5. **Export compliance is not the real app's answer.** Its `ITSAppUsesNonExemptEncryption` is `false` because all
   its encryption on iOS is Apple's WebCrypto. This app's is its own, in the Rust core (`native/src/crypto.rs`:
   AES-GCM, PBKDF2, P-256, Ed25519), so the question has to be answered again for standard algorithms the app
   carries itself. The key is not in this Info.plist.
6. **The Info.plist as it stands**: the scene manifest (iOS 26 and later stop an app without one), `ghostmd://`,
   the camera's sentence (the real app's words), the Productivity category, arm64 and Metal, portrait and the two
   landscapes. No microphone or location sentence, and no photo library one (`PHPicker` needs none).
7. **The service**: a release names it at build time (`--dart-define=GHOST_API=…`, docs/STAGE7.md); without one
   the app has no account, and the store's review notes and demo account (`APP_STORE.md`) are about one.
8. **Words that name another platform** (guideline 2.3.10), each the page's own and so the real app's too: "press
   the side key" on the How Ghost.md works canvas, "on Android" in the Academy's video lesson, the guidebook's
   chapters, and the new sheet's "typed or said".
9. Then the checks `APP_STORE.md` lists (version and build, `UIDeviceFamily` [1], the distribution signature, both
   the scheme and the scene delegate in the built plist, the icon without alpha, which it is), `altool
   --validate-app`, and the upload: Matt's to do.

**Left open:**

- **Not on a phone.** Everything above is the simulator's. The phone's slice of the core is built and links into
  an unsigned release that nothing has run; Impeller on a phone's GPU, the Taptic Engine and a real keyboard are
  unseen.
- **The system's own screens were shown and not pressed.** Nothing here sends a touch to UIKit: the picture menu
  was seen and its three choosers were not opened, so `PHPicker`'s file, a HEIC, a photo just taken and the Files
  picker have not been through `PictureKeep` on an iPhone (it is the Mac's ImageIO code). The date sheet was
  seen and no day was pressed in it. A `ghostmd://` link was not opened (the simulator asks before it hands one
  over), nor a picture pasted (an iPhone asks before a paste is read).
- **The keyboard is not WebKit's.** Read rule by rule in ../glyph: the page has no code of its own for an iPhone's
  keyboard. What it has for any keyboard is `core/keyboard.ts` (up when the visual viewport is 150px shorter),
  the caret kept in sight on a viewport's resize (`Editor.tsx`), the band and the + list placed inside the visual
  viewport (`menuRoom.ts`, `PopMenu.tsx`, `AddList.tsx`), and a find bar and a dock fixed to the page's foot; the
  port keeps each of those from `viewInsets`. What differs is the page's height: `#root` is `100dvh`, which an
  iPhone's keyboard does not shorten, so the real app's page stays as tall as it was and WebKit pans it until
  the caret shows, where the port lays the page out above the keyboard (the page's own stated rule, and its
  Android half's), with the dock and the find bar riding it. WebKit's accessory bar is left as it comes (the
  Tauri app gives wry no builder for it); the port's bar is the app's drawing of it, without its two arrows.
  **None of this was compared with the real app, which was not run here**: where its find bar and dock end up
  under WebKit's pan is not known. A hardware keyboard raises no bar.
- **Scrolling was not seen stretching.** The rule is one now (above) and held by `test/core/page_scroll_test.dart`.
  The app ran with it in the simulator (Home, Settings, Plugins, the sidebar, a note, the sheets), but a picture
  is taken too late to catch a band, so neither the stretch nor the pull to refresh beside it has been seen: both
  want a finger on a phone.
  **The Mac changes with it and was not run:** Home, Settings and the rest stretch under a trackpad now, as a
  note there already did, where they stopped dead before.
- **The status bar follows the phone**, as the real app's does (the page never tells its window a theme), so
  under Dark on a light phone its ink is dark on a dark page, there as here. Seen only with both dark.
- **The handles are Flutter's copy of the phone's shapes, in the caret's colour** (`--glacier-accent-solid`, which
  the page gives its editor as `caret-color`; WebKit tints an editable's selection with the caret's colour, as its
  source is remembered, not as seen in the real app). Not looked at since they left the system's blue. The
  selection itself is the page's `::selection` block, and whether WebKit on an iPhone draws that or its own tint
  is not known. The loupe over a dragged handle is still the editor's own. The note's menu is the page's own
  band, as on the page, never the system's callout.
- **A canvas's card being written is not brought above the keyboard** (seen: the card half under the tools). A
  camera moved up by what the card is short was written for it and taken out again unseen.
- **`{?…}` blanks are drawn with no Fill**, as the page draws them on an iPhone (`iPhoneBlanks`). A tap on one
  opens nothing, there being no AI's layer to draw its panel; what the page's tap does there was not compared.
- **Browse files is drawn and its press opens nothing**, as on the page, where the press fails and nothing is
  said (`lib/core/library_files.dart`).
- **Seen in the walk and not an iPhone's alone:** Settings › About › Examples' four rows were dimmed and could
  not be pressed **on every platform**, the root never having given them a press; they make their note and open
  it now (`_openExample`, `test/root/examples_test.dart`), the sample note and the canvas without the picture the
  page keeps for them. Left for whose they are: the palette shows `⌘N` and its keys' footer on a phone; a
  relaunch came up on Home twice and on the open note once.
- **The haptics cannot be felt in a simulator.** The typing tick is the phone's selection click, where the page
  asks for a soft impact, which Flutter does not have.
- **Landscape, the phone's text size turned up, the iPhone Duo and an iPad** were not looked at. The text size is
  told to be left alone (`iPhoneMedia`, held by a test); the app is an iPhone's alone.
- **One Keychain and one picture file for both Apple targets** (`apple/`): the Mac's Runner compiles them too and
  its own copies are gone. The Mac app was built with them and **not launched**, so a secret kept and read back by
  that build has not been seen.
- **Moving a library over from the real iPhone app** is item 1 above, or sync.

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
  - **A film's line, and a picture's, is drawn as its still wherever a note is drawn small** since 2026-10-09: on
    a note's card on the home page, in the sidebar's rows and in a card of words on a canvas, from the pictures
    the app keeps (`PeekPictures` over the app in `lib/root/ghost_root.dart`, `peekExtensions` in
    `lib/home/note_peek.dart`, `CardWords.pictures`), as the page's `peek` draws them. Held by
    `test/home/peek_pictures_test.dart`; not looked at on a device.
  - **Still open of it:** a canvas has no film card of its own to add, as on the web. A place
    line's name that comes later than three seconds is written only while its line is the newest change, without
    the web's count of the note's own tag landing meanwhile (`tagSteps`). The map note's header on a phone is the
    card inset, where the page's is the page's whole width with square corners.
- **Not wired, each with its seam:**
  - **A board card's plugin rows** (`drawnBoards(actions:)`, `cardActions`): left as the web app has them. Its
    own `Editor.tsx` calls `drawnBoards()` with none, so a card's menu there has no plugin's rows either; the seam
    is one line in `lib/root/note_desk.dart` (the desk already has `itemSend` and `lineOffers`, which are its two
    halves) if that is wanted here.
  - **The editor's parser reads `plugins.formats()`** since 2026-10-09 (`noteFormats`, `lib/root/note_desk.dart`):
    the switched-on plugins' formattings, read as a note's editor is made, with the band's Style page and the +'s
    effects read as each is drawn. Ghost.md's own marks switched off are in none of the three in the next note
    opened. Where nothing was ever put in the registry (a test that builds a note without the app's launch) it is
    the app's own marks.
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
- **Settings › Recording's Tapes** counts what the web counts (2026-10-09): the lengths of the tapes whose audio
  is on this device, which is not one the row removed here nor one whose file says it is elsewhere (a synced note
  whose audio stayed where it was made). Each tape's file is asked through the player as the card is put up
  (`lib/settings/tapes_here.dart` over `TapePlayer.onDevice`, the web's `headStatus`;
  `SettingsFeatures.onCountTapes`), and the sums are `lib/settings/tapes.dart` (`settings/tapes.ts`). Held by
  tests; **not walked on a device.**
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
- **Found and left:** a card being written on a team's canvas when another member's change arrived kept its
  editor but the view was fitted to the canvas again; it is not fitted again since 2026-10-09 (below). The
  organization's New (`OrgAction`) and the rows of the + sheet were not in `uiautomator`'s list. Off the device
  both are in the tree the app hands a screen reader, reached from its root, each a button with a tap: New as
  "New in this organization", a row as its words and its line together (`test/root/semantics_test.dart`,
  `test/account_ui/reference_test.dart`). Neither is a `text` there, only a content description, which may be
  all the walk's search missed: not reproduced, and not looked at again on the emulator. A debug build's errors did not reach logcat on this emulator (Android 16); the
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
- **A selection of another member's across lines** washes the lines between its first and its last whole, an empty
  one among them too, as y-codemirror's does on the page (`cm-yLineSelection`, with that rule's own margin), since
  2026-10-09.
- **A note open in an editor bound to its document is the editor's** (`TeamDoc.editing`): a pass posts what was
  typed and applies what the log brings, and neither reads the saved note into the document nor writes the
  document into the note. The page's pass reconciles from the saved note, a save's delay behind its editor.
- **Jump to cursor** opens a note at a member's caret (`NoteDeskWorld.takeJump`), and a canvas centred on a
  member's spot since 2026-10-09 (`CanvasView.goTo`: the desk keeps a jump that is a spot for its canvas). Held by
  `test/canvas/team_view_test.dart`; the dashboard's press through to a canvas was not walked.
- **On a team's canvas** the card a member has open is ringed in their colour with their handle on its corner, and
  the card this device opens is said in the room (`card`; `TeamCanvasPeople`, `CanvasView.onEditing` and
  `editedBy`), since 2026-10-09; and the view is no longer fitted again for a member's change, as the page's is
  not (`CanvasView.team`). This device's pointer is where a finger is down and nowhere once it lifts, and a change
  that arrives while a card is being dragged is still the body handed to the view anew. Its threads are in the
  note's own sheet (next).
- **Comments** (../glyph docs/SHARED.md, S8 and S9; 2026-10-09). In a note: each `[^c1]` a round in its author's
  colour and the words round a selection washed in it, the ```comments fence drawn as the list of its threads
  (`lib/editor/comments/comments.dart`), the thread's card and the new comment's field in the app's sheet with
  replies, Resolve, Reopen and Delete thread (`lib/comments/ui/`), Comment on the press-and-hold band, in the bar
  and in More with the threads' count, and Add a comment on a note's menu. On a canvas: the same sheet from a
  card's round and its bar (`lib/canvas/canvas_comments.dart`). Each member's colour is read with the organization
  the note is filed in (`lib/comments/ui/note_colours.dart`), and is ink anywhere else. In a team's note a comment
  is a few edits through the bound editor, so it rides the team's document as typing does
  (`test/live/comments_test.dart`: two members, the real CRDT, a relay in memory). The page has no notification of
  a comment's own and neither has this: its audit-log line and the profile card's counts wait on the page too.
  Held by the page's own cases and by pictures (`test/comments/shots`, `test/editor/comments/shots`,
  `test/canvas/shots/comments-*.png`); **not walked on a device.** Found and left: an Undo in a live note, after
  another member wrote at the very same place, can take out the wrong letters. What arrives is put into the
  editor as the least change between two wordings (`spliceBetween`, `lib/team/text_log.dart`), not as the
  document's own insertion, and the editor's history maps its undo through that; the page's `Y.UndoManager` has
  no such step. The seam is the core handing the editor yrs's own delta.
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
- **A canvas** has the phone's picture chooser for its picture card (not walked) and opens no link (as a note).
  Since 2026-10-09 its comments are in the note's own sheet; it is framed in a note by `![[Its name]]` on a line
  of its own, from the +'s A canvas (`lib/editor/media/canvas_frames.dart`, `AddConfig.canvases`); and renamed
  from its tab while it is being read, it is named through its open screen (`lib/note/open_screen.dart`). A
  team's canvas (6G) is its structure in the team's document (see "What stage 7 left open"). Held by tests and
  pictures; none of the three walked on a device.
- **A board's card has no plugin's rows** (`drawnBoards(actions:)`), as on the web (see stage 9's other pieces).
  A date in a ticket's panel or a query is picked from the phone's calendar (`dayPicker`); seen on a list item's
  date page, not in a panel or a query.
- **`Notices`**: the voice model's line (stage 8), the update's card and the invitation's (stage 9,
  `lib/root/update_wiring.dart`) are on the home page, and the sidebar carries the update's card on a window in
  two panes, docked or as a card (App.tsx `notices`), since 2026-10-09. `RefiningNotice` is given nothing because
  the page gives it nothing: it is drawn nowhere there since the dashboard went.
- **The aside** (the open note's notebook beside it on a wide window, `aside/`) came with stage 10 (`lib/aside/`).
- **A note opened with the caret at its end** (a journal's new entry) keeps its heading and the notebook's bar in
  sight as the keyboard comes up, since f39b16c: the editor's nearest scroll counted its margins when asking
  whether the caret was in sight, so a caret in plain sight was moved up to them. `test/root/entry_keyboard_test.dart`
  holds the journal's case through the app put together; not seen again on the emulator.
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
- **The notes' folder in the phone's Files app** (2026-10-09): the app lists its library there as a place of its
  own, read-only (`glyph/files/LibraryDocuments.kt`, the Tauri app's line for line; the authority is this app's
  id's, `com.mattssoftware.glyph.flutter.library`, and the place wears the app's own name, "Ghost Flutter"), and
  the sidebar's Browse files opens it (`lib/core/library_files.dart`; `browseFiles` on `ghost_md/files`,
  `ghost_md/LibraryFiles.kt`). The web offers it in the sidebar and nowhere in Settings, so there is no row there.
  Held by tests and by the Kotlin compiling; **not walked on a device.** **Not on a Mac:** the web's
  `library_reveal` (Finder) is not in this core, and `LibraryFiles(reveal:)` is where a Mac's way goes.

## What stage 4 left open

The editor's pieces (docs/STAGE4.md) are assembled for each open note by `lib/root/note_desk.dart`, and the account's
(docs/STAGE7.md) by `lib/root/account_wiring.dart`; `lib/root/ghost_root.dart` is where both meet the shell.

- **The account is off by default.** `flutter build apk --debug --no-pub --dart-define=GHOST_API=http://10.0.2.2:<port>/api`
  after `tool/local-server.sh start` gives a build with one (10.0.2.2 is this Mac from the emulator; cleartext is
  allowed in the debug manifest only). With no define nothing of the account is made and every screen is the
  signed-out one, whose way in says the build has no service. A define naming ghostmarkdown.com or attack.fm is
  refused in a build that is not a release (`accountBase`), and by the `Api`'s assert after it.
  `test/root/second_device_test.dart` is the second device that reads back what a phone wrote.
- **Drawn on a note's page since 2026-10-09:** the placeholder ("Write something.", `lib/editor/placeholder.dart`)
  and comments (see "What stage 7 left open"). (The AI's rows, the place row
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
- **Wave has its icon** since 2026-10-09: the made set answers to the other names lucide keeps for an icon (`waves`
  is `waves-horizontal`; `tool/lucide.dart` `aliases`).
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
- **One preview of a note** since 2026-10-09: the sidebar draws the home page's (`lib/home/note_peek.dart`,
  `NotePeek.plain`), and `BookPlaceMark` and `OrgMark` are each one widget (`lib/notes/`, handed on by
  `lib/home/marks.dart`).
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
  the feel of swipes and of holding a tab. `lucide_icons_flutter` left the app's pubspec 2026-10-09; the kit keeps it for its own tests.

## What stage 1 left open

- **Not ported from the kit:** the `skeleton` prop everywhere, the `shape` system (ShapeLayer), `ContextMenu`, and the
  kit's `LocaleProvider` (the few strings are local, English first; the palette's are in eight languages).
- **Three files do the same job** and want merging: `css_effects.dart`, `field_core.dart` and the private painters in
  `menu.dart` / `popover.dart` each draw inset shadows, outer shadows and a glass backdrop.
- **A panel over the page takes the page's own tokens** since 2026-10-09, as the web kit's portal takes the
  body's: a popover's panel, a menu's and the command palette are built under `GlacierRootScope`
  (`Tokens.rootTokens`). A toast is not.
- **Hover styles** showed on Android only once a key had been pressed (Flutter's highlight mode). Since stage 10 the
  kit's pressable hears a mouse over it by a mouse region of its own, in either mode (`pressable.dart`).
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
tool/build-native.sh mac                    # the Mac app's core, both architectures: macos/Core/libghost_core.dylib
flutter build macos --debug                 # build/macos/Build/Products/Debug/Ghost Flutter.app
tool/build-native.sh ios                    # the iPhone app's core, static, the simulator's and the phone's: ios/Core/GhostCore.xcframework
flutter build ios --simulator --debug       # build/ios/iphonesimulator/Runner.app
xcrun simctl install <udid> build/ios/iphonesimulator/Runner.app && xcrun simctl launch <udid> com.mattssoftware.glyph.flutter
tool/ios-tour.sh <udid> /tmp/shots 'wait:7000;shot:home'    # a debug build walks itself; the pictures are the simulator's
```

`tool/sync-design.sh` refreshes the stylesheets from `../glyph`; run the kit's tests after it.

**The suite is `tool/check.sh`**: the kit, then every folder of `test/` in a run of its own, the analyzer (and that
the last commit imports nothing git was never given), `test/e2e` and `test/live` against the service on this Mac, and
cargo's tests. Every `flutter test` in it is `--concurrency=2`, one check runs at a time on the Mac and each run waits
while the load is over 40; a failing test is named with the first line of why, and the exit is 1 if anything failed.

```sh
tool/check.sh                          # everything
tool/check.sh --since <rev>            # the quick one: the kit and the folders that what changed since <rev> can reach, and the analyzer
tool/check.sh --quick                  # the same for what is not committed yet (--since HEAD)
tool/check.sh --since <rev> --list     # says what that would run and which changed file reaches each; runs nothing
tool/check.sh app root editor          # those folders; also: kit, analyze, server, native, pictures
tool/check.sh test test/root/root_test.dart    # one run of whatever is named, with the same limits and report
```

`--since` follows the tests' own imports and the paths they name, so a change in `lib/home` runs `test/home`,
`test/root` and `test/diag` and a change to the token engine runs nearly everything; it does not start the service or
cargo, and says so when what changed asks for them. The script's head says the rest: what `--since` cannot see, where
each run's report is kept (`build/check/`), and why a stale picture is drawn again by its whole file and never by one
test's name.
