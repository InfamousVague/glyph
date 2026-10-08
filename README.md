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
| 4 | The editor: live Markdown, the marks and the five effects, tables, links, pictures, the + menu | `editor/` (26k), `format/` | |
| 5 | Structured notes: boards, tickets, queries, databases, notebooks, journals, templates | `editor/`, `book/`, `notes/` | |
| 6 | Canvas | `canvas/` (3.5k) | |
| 7 | Account and sync: keys, the sync engine, organizations and team notes, live typing, notifications, shared links | `core/sync`, `core/orgs`, `core/live`, `share/` | |
| 8 | Voice and AI: the recorder, Whisper, meetings and their service, summaries, the language model, fills, the at-work scene | `capture/` (12k), `ai/` (6.5k), `tapes/`, `scene/`, Kotlin (6.5k) | |
| 9 | The rest: backup, export, plugins, the Academy and the guide, diagnostics, updates | `plugins/`, `academy/`, `guide/`, `diag/` | |
| 10 | Platforms and release: the Fold's wide layouts, Mac, Windows, iPhone; signing; moving a library over from the Tauri app | | |

The web app is about 110,000 lines of TypeScript, 21,500 of CSS, 27,000 of Rust and 6,500 of Kotlin, with 5,600
tests. Parity is the bar for every stage; a stage is not done until its screens have been compared with the web app's
on the same phone.

## What stage 2 left open

- **Stand-ins until their stage:** the notes are the store screenshots' invented library in memory (`SampleLibrary`;
  stage 3, planned in `docs/STAGE3.md`); an opened note is its title over its Markdown as written (stage 4); every
  Settings section but Appearance opens a card that says it is not ported; the notifications card is empty and Speak,
  organizations, notebooks and journals have no way in yet.
- **Not wired though built:** `NoteActions` (delete with the web's Undo toast; the root keeps a plain trash),
  `NewSheet` (the dock's + makes a note directly), `Notices`, `TemplateCards`.
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
