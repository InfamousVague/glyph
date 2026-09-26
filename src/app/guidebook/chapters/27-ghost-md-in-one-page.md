# Ghost.md in one page

_What Ghost.md is made of and how the pieces meet, for a reader who can read code and has not opened the repo._

---

## What happens

Ghost.md is a notes app. Its notes are Markdown files, and its voice capture is transcribed on the device. It is four codebases in one repository.

The app's visible name is Ghost.md. The repo, the ids, the keys, the salts and the URLs are still glyph. The Android id is `com.mattssoftware.glyph`. Every key the page stores is `glyph-<thing>` (`src/app/core/stored.ts`), and a password or a recovery code is salted with `glyph/v1/` and the handle before it becomes a key (`passwordSalt` and `recoverySalt` in `src/app/core/sync/crypto.ts`). Renaming any of them would orphan something already on a phone.

**The page.** React 19, TypeScript and Vite 7, with CodeMirror 6 for the editor and Yjs for live typing. The UI kit is Glacier, vendored under `vendor/@glacier` (`icons`, `react`, `tokens`), so nothing for it comes from a registry. `index.html` loads `src/main.tsx`, which mounts `App` from `src/app/App.tsx`. The same page runs in a browser at attack.fm/glyph, where the notes live in `localStorage`, and inside the app, where every note call goes to Rust (`src/app/core/store.ts`).

**The shell.** Tauri 2, in `src-tauri`. `src-tauri/src/main.rs` calls `glyph_lib::run()` in `src-tauri/src/lib.rs`, which registers three URI schemes (`ota`, `rec`, `img`), four plugins and 51 commands. The shell owns the library of Markdown files (`src-tauri/src/library/`), transcription with whisper.cpp (`src-tauri/src/whisper/`), the language models with llama.cpp (`src-tauri/src/llm/`) and over-the-air updates (`src-tauri/src/ota.rs`). Both engines are built for every target except iOS. The Android half is hand-written Kotlin under `src-tauri/gen/android`: the activity, the assistant services the side key reaches, the Files app provider and the update-alert worker.

**The server.** glyph-api, in `server/`: axum and one SQLite file. It serves accounts, end-to-end encrypted sync, shared links, live typing's relay, Notion sign-in and a door to the hosted connector, all under `/glyph/api/` (`server/src/main.rs`), beside the formatting route it began as, which nothing in the app calls any more. It keeps ciphertext, and cannot read a note.

**The connector.** An MCP server in `mcp/` that gives Claude the notes as tools: list, read, search, create, update, append, pin and archive, and which account it is signed in to (`mcp/server.ts`). It runs on a person's own computer as `glyph-mcp.mjs` under Node, or hosted at attack.fm/glyph/api/mcp. It imports the page's own modules for titles and list placement, so words it appends land the way a spoken "add" does.

**One spoken note, end to end.** Holding the side key reaches `GlyphInteractionService`, the voice interaction service that makes Ghost.md the phone's assistant. Its session starts `MainActivity` with a capture action and hides at once. From a cold start the page collects the request with `GlyphHost.takeLaunch()`; into a running app it is pushed as `window.__glyph.capture()` (`src/app/core/host.ts`). Either way `src/app/shell/useCaptureRoute.ts` puts the capture screen up. `src/app/capture/CaptureScreen.tsx` opens the microphone, and `src/app/capture/engine.ts` streams the samples to whisper.cpp through `capture_start` and `capture_push`. Phrases come back as events that are only shown. At Done, `capture_stop` keeps the audio as `recordings/<id>.wav` and returns the whole transcript, which `src/app/ai/instruction.ts` reads once. Plain words become Markdown (`takeMarkdown` in `src/app/capture/take.ts`) and go through `src/app/capture/takeWriter.ts` to `createNote`, which invokes `create_note`. The library writes `Inbox/<title>.md` with its front matter and brings `.glyph/index.sqlite` up to date (`src-tauri/src/library/mod.rs`); if the list is showing a workspace, the note is filed there and its file moves to `workspaces/<name>/`. The save fires `glyph:note-saved`. On a signed-in device, about four seconds later `src/app/core/sync/engine.ts` starts a sync, and `src/app/core/sync/notes.ts` seals the note with the account key (AES-256-GCM, `crypto.ts`) and PUTs it to `/glyph/api/v1/notes/<id>`. glyph-api keeps the ciphertext with the note's id, a revision number and a time, and nothing it could read (`server/src/store.rs`).

**The size of it, at HEAD.** `src/app` is 435 source files and about 57,300 lines of TypeScript, with 62 stylesheets; 339 test files sit beside the sources under `src/`. The largest page file is `src/app/capture/CaptureScreen.tsx`, at 966 lines. The app's Rust is 69 files and about 15,300 lines, its tests included. glyph-api is 33 files and about 7,100 lines. The connector is ten source files and about 1,500 lines, with its tests beside them.

## The pieces

| Piece | File | What it does |
|---|---|---|
| Loader | `index.html` | Asks `ota_claim_boot` which frontend runs; falls back to the embedded one |
| Mount | `src/main.tsx` | The stylesheets in order, then one `App` |
| Shell | `src/app/App.tsx`, `src/app/shell/` | Which screen is up, and everything drawn over it |
| Notes door | `src/app/core/store.ts` | Typed calls to Rust, or `localStorage` in a browser |
| Preferences | `src/app/core/preferences.ts` | Settings, plus the tabs, workspaces, trash and shares |
| Editor | `src/app/editor/Editor.tsx` | CodeMirror 6 and the extensions that draw the marks |
| Recorder | `src/app/capture/CaptureScreen.tsx` | One capture, from microphone to note |
| Sync | `src/app/core/sync/engine.ts` | When to sync; sealing is `crypto.ts` |
| Native core | `src-tauri/src/lib.rs` | Schemes, plugins, setup and the 51 commands |
| Library | `src-tauri/src/library/mod.rs` | Notes as files, with an index over them |
| Updates | `src-tauri/src/ota.rs` | Signed bundles, the boot wager, native generations |
| Android | `src-tauri/gen/android/app/src/main/java/com/mattssoftware/glyph/MainActivity.kt` | The side key, the back gesture, the bridge to the page |
| Server | `server/src/main.rs` | Every route under `/glyph/api/` |
| Connector | `mcp/server.ts` | Notes as tools for Claude |

## Things that surprise people

- **There is no router.** `src/app/App.tsx` holds one piece of state for it, the `Screen` union in `src/app/shell/screen.ts`, which has five members. Settings, the welcome guide, the palette and the rest are sheets over whichever screen is up.
- **A note is a file, and the database is only a cache.** `src-tauri/src/library/mod.rs` keeps each note as a `.md` file with front matter. `.glyph/index.sqlite` makes the list instant and is rebuilt from the files whenever they disagree. A new note has no file at all until its first words.
- **The trash, the workspaces and the open tabs are preferences.** `src/app/core/trash.ts` and `src/app/core/workspaces.ts` keep them in `src/app/core/preferences.ts`, because a column in the native store is a native change and an APK. A preference ships over the air, and `src/app/core/sync/prefs.ts` lists them among the settings that sync. Filing a note in a workspace also moves its file to `workspaces/<name>/` (`src/app/core/noteFolders.ts`).
- **A recording's commands are read once, at Done, and a command may only add.** While the microphone is live a phrase is only shown (`src/app/capture/take.ts`). After the stop the whole transcript is read (`src/app/ai/instruction.ts`). A run said in words into a note, such as "fix the spelling", opens that note with the run on it. A command that names a note may only add to it or make a new list (`permitted` in `src/app/capture/finalInstruction.ts`), and it is offered on a card before anything is written. Rust refuses any other kind of command write: `into_mutation` in `src-tauri/src/commands.rs` takes `append` or `create` and nothing else.
- **Every bundle built from main needs native generation 19.** `vite.config.ts` stamps `BUNDLE_REQUIRES` from `src-tauri/src/ota.rs` into `ota.json`. A phone with an older binary reports `needs-native` and is offered the APK instead of the page.
- **The test report is compiled into the app.** `scripts/test-report.mjs` writes `src/app/diag/testReport.generated.json`, and `src/app/diag/testReport.ts` imports it. Settings shows it under Test results once developer mode is on, and `buildMatch` says whether the report came from this build's code. `scripts/deploy-ota.mjs` runs the report first and refuses to ship a failure, unless it is told `--skip-tests`, when the page says its report is from other code.

## Where the docs disagree

`docs/DESIGN.md` is a dated log, so its early sections describe an app that has moved on: §5 still keeps the notes in `glyph.sqlite`, which the first launch of 1.3.0 or later reads once through `src-tauri/src/store.rs` and renames `glyph.sqlite.moved` (`src-tauri/src/library/move_in.rs`).
A few comments have drifted from the code beside them, such as `App.tsx`'s line that a back swipe at home leaves the app; `tookBack` in `src/app/core/back.ts` never lets it.
[[Where the docs and the code disagree]] collects the disagreements that cut across chapters, these two among them, and lists the chapters that end with their own doc's. Believe the code.

## Read next

- [[No router, five screens]]
- [[The native half]]
- [[The library on disk]]
