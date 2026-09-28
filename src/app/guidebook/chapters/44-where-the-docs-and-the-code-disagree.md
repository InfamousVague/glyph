# Where the docs and the code disagree

_Where a doc, a comment or the app's own words say one thing and the code does another, checked at 1.8.0-12, and what the app tells you to say checked again after DESIGN §127. Believe the code._

Each entry gives the claim and then what the code does, both with paths. This chapter holds the disagreements that cut across chapters. Most chapters in this half also end with their own doc's, and the Doc by doc table at the end says where each one is.

## What the app tells you to say

- **The model's download.** The welcome guide's Choose your model page (`src/app/guide/pages/Model.tsx`) says the chosen model downloads the first time you ask the robot on a note. Nothing fetches it then. With no model on the phone, a run or a spoken ask shows the reason `availability()` gives (`src/app/ai/available.ts`, shown by `src/app/editor/useNoteAi.ts`), and no caller reads the `get` it answers. Only “get it now” on that page and Get in Settings › Recording › Model download a model.

The voice memo cue, tables, books and boards by voice, and Notion by voice were listed here until DESIGN §127 cut what the recorder could no longer do and put right every line that taught it. The canvas's cue words were put right before that.

## Updates and generations

- **When to raise `BUNDLE_REQUIRES`.** The header of `src-tauri/src/ota.rs` says to bump both generation numbers when the page starts depending on a new command. The page gates each feature on its own threshold instead, through `hasNativeGeneration` (`src/app/core/nativeGeneration.ts`; `FILES_GENERATION = 18` in `src/app/core/libraryFiles.ts`, `SYNC_GENERATION = 16` in `src/app/core/sync/engine.ts`), and hides it on an older binary. On main, `BUNDLE_REQUIRES` stood at 1 while `NATIVE_GENERATION` climbed to 18 at 1.7.2. Both went to 19 at 1.8.0, when every note write came to need the revision-checked commands (DESIGN §114, "The AI in the note"). At 1.9.0 `NATIVE_GENERATION` went to 20 for meetings on Android and `BUNDLE_REQUIRES` stayed at 19, the way the header does not describe: the page gates every meeting call with `hasNativeGeneration(20)` (`MEETING_GENERATION` in `src/app/capture/meeting.ts`) and runs on a generation-19 phone without Meeting. The film in a note took it to 21 the same way (`VIDEO_GENERATION` in `src/app/core/videos.ts`). Raised for one new command, it would send every older phone to the APK.
- **Store builds and the air.** The comment on `STORE` in `ota.rs` says a store build's web bundle still updates over the air, which both stores allow. That holds for Play. An App Store build runs on iOS, where the fetch and the install are not built, `ota_check` answers "Over-the-air updates are Android-only." (`src-tauri/src/unsupported.rs`), and `src/app/core/ota.ts` never asks. That answer is narrower than the code in its turn: the Mac app takes updates over the air too.

## Comments that outlived their code

- **The recorder's buttons.** The header of `src/app/capture/CaptureScreen.tsx` says Discard and Done are the only buttons. The line at the top is a button as well (it shows what the pipeline has done), and a recording aimed at a note has New note beside it.
- **A back swipe at home.** The header of `src/app/App.tsx` says the home page lets Android put the app behind the home screen. `tookBack` in `src/app/core/back.ts` answers every back gesture as taken, so a swipe never leaves the app.
- **The browser's recogniser.** `browser()` in `src/app/capture/engine.ts` is commented “Chrome only”. `startCapture` chooses it for every page outside Tauri, and it runs wherever `webkitSpeechRecognition` exists, which is Edge and Safari as well as Chrome.
- **The pinched size.** The comment on `writeZoom` in `src/app/editor/pinchZoom.ts` says the size is not kept. It is written under `glyph-note-zoom`, and every note opens at it, as the file's own header says.
- **A model on the desktop.** `src/app/notes/peek.ts` says a desktop has no model. `src-tauri/Cargo.toml` builds llama.cpp for every target but iOS, and `src-tauri/src/ai_commands.rs` refuses only there, so the Mac app runs a model once one is downloaded.
- **Build-time settings.** `src/vite-env.d.ts` says the page reads none. `src/app/core/account/api.ts` and `src/app/share/share.ts` read two, the service's address and the reader page's, each falling back to its public default.
- **The size of the tree.** `eslint.config.js` says the tree "is five files old" and that its one non-null assertion is the root mount in `src/main.tsx`. `src/` holds hundreds of files and, outside the tests, over a hundred `!` assertions. The reason the rule is off still holds; the counts do not.

## DESIGN.md

- **Its early sections.** §5 keeps the notes in `glyph.sqlite`. Since 1.3.0 the first launch reads that file once through `src-tauri/src/store.rs` and renames it `glyph.sqlite.moved` (`src-tauri/src/library/move_in.rs`), and the notes are Markdown files ([[The library on disk]]).
- **Its numbers repeat.** §30, §49, §50 and §119 each head two sections, and 34 sections have no number at all. Cite a section as DESIGN §N with its title, and never renumber.
- **It reads forward.** §117 put the note's prompt bar behind a toggle, and §122, the same day, removed the bar and the toggle with it. A section is true of the day it is dated, and a later one may undo it.

## Doc by doc

The chapters that end with their own doc's disagreements:

| Doc or code | Where the list is |
|---|---|
| `docs/instruction-voice-commands.md` | [[Reading a command, writing it safely]], under Known gaps |
| Editor comments: `glyphLines.ts`, `links.ts`, `language.ts`, `wispFormat.ts`, `tables.ts`, `drawnBlock.ts` | [[The editor and its language]] |
| `docs/BOARDS.md`, `docs/BOOKS.md`, `docs/CANVAS.md`, and the clip example in `core/clips.ts` | [[Formats that stay Markdown]] |
| `docs/PLUGINS.md`, and `InlineFormat`'s comment | [[The plugin seam]] |
| `docs/LIBRARY.md` | [[The library on disk]] |
| `docs/SYNC.md` | [[Sync and the end-to-end keys]] |
| `docs/LIVE.md` | [[Live typing over a relay]] |
| `docs/MCP.md`, and the Claude page in Settings | [[The Claude connector, inside]] |

## Read next

- [[Working on Ghost.md]]
- [[Ghost.md in one page]]
