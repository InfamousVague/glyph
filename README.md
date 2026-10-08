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
| 7 | Account and sync: keys, the sync engine, organizations and team notes, live typing, notifications, shared links | `core/sync`, `core/orgs`, `core/live`, `share/` | in the app 2026-10-08, **off unless the build is given `--dart-define=GHOST_API=http://…`** (`lib/root/account_wiring.dart`); walked on the emulator against the service run on this Mac (sign up, sync read back by a second device, an organization, a team note, a shared link); live typing, links that open the app and the phone's own notifications are not ported |
| 8 | Voice and AI: the recorder, Whisper, meetings and their service, summaries, the language model, fills, the at-work scene | `capture/` (12k), `ai/` (6.5k), `tapes/`, `scene/`, Kotlin (6.5k) | |
| 9 | The rest: backup, export, plugins, the Academy and the guide, diagnostics, updates | `plugins/`, `academy/`, `guide/`, `diag/` | |
| 10 | Platforms and release: the Fold's wide layouts, Mac, Windows, iPhone; signing; moving a library over from the Tauri app | | |

The web app is about 110,000 lines of TypeScript, 21,500 of CSS, 27,000 of Rust and 6,500 of Kotlin, with 5,600
tests. Parity is the bar for every stage; a stage is not done until its screens have been compared with the web app's
on the same phone.

## What stages 5 and 6 left open

The pieces (docs/STAGES_5_6_8_9.md) are in the app: each open note's desk (`lib/root/note_desk.dart`) lists
`drawnBoards()`, `tickets(…)` and `queries(…)` among its extensions and tells them when the library changes, and
gives the note's screen its canvas, its notebook's index, its journal and the bar and foot a page wears; the root
(`lib/root/ghost_root.dart`) answers what they ask of the app as `App.tsx` does, over one reading of the library per
change (`lib/root/library_reads.dart`). `test/root/structured_test.dart` holds the wiring.

- **An entry or a named note nobody wrote in is not taken back.** `App.tsx` deletes a journal's entry, or a new note
  given a name or a template from its blank page, once it is left untouched (`takeBack`), with its line in the
  journal. The records are kept here (core/untouched.dart) and nothing reads them when a note is left.
- **A blank page's cards have no map.** A map at the top is left out (`TemplateCards.canLocate` is false: nothing
  says where the phone is), and a template with a map asks for no place.
- **A new note, a journal's entry and a journal keep no place** (Tag new notes, a journal's place switch): the
  switch is drawn in the New notebook sheet and written to the journal, and nothing reads it.
- **The + sheet has no Meeting and no From a shared link**: recording is stage 8's to wire, and a shared link's copy
  is the account's (`forkShared`).
- **A canvas** has no picture picker and opens no link (as a note), no comment sheet (`CanvasView.threads`), is not
  framed in a note from the + (`AddConfig.canvases`), and a team's canvas (6G) is not ported. A canvas renamed from
  its tab is written to the store and not through its open screen (`rename`).
- **A board's card has no plugin's rows** (`drawnBoards(actions:)`), and a date in a ticket's panel or a query is
  not picked from a calendar (`dayPicker`).
- **`Notices` is still not wired**: the update card waits for stage 9's updates, the invitation for its buttons
  (`InviteActions`), the voice model's line for stage 8.
- **The aside** (the open note's notebook beside it on a wide window, `aside/`) is still the shell's placeholder.
- **Checked where:** on the Android emulator, by hand, 2026-10-08 (see the commit that wired them); in tests, the
  wiring and each piece's own. **Still to see on the Fold:** a card carried between a board's lanes and a query's
  under a real finger, the canvas's pinch and its cards' words on Vulkan, the keyboard's own toolbar over a canvas
  card being written in.

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
  for Pick a date, and a link's tap opens nothing (no way to hand an address to the phone).
- **A new note is opened ready to type** since stages 5 and 6 were wired (the shell's `openNote` carries a caret),
  from the + sheet's Note.
- **Links that open the app** (`ghostmd://join/…`, a shared link) have no Android intent behind them: an invitation
  is answered from its notification, and `JoinInvites` only asks about a code held from before.
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
  the account; the notifications card is empty and Speak has
  no way in yet (organizations came with stage 7; notebooks, journals and canvases with stages 5 and 6, from the +).
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
