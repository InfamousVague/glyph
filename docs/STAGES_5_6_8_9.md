# Stages 5, 6, 8, 9 and a list for 10: what was read in ../glyph (2026-10-08), and the pieces

Holds for all: the worker isolate is serial (a long job must return an id at once and report by events); the
Rust-to-Dart event path is unbuilt (`native/src/ffi.rs` keeps a listener nothing calls) and stages 8 and 9 need it;
a Rust file that names `tauri::` cannot be `#[path]`-included (answers: `native/src/kept/` copies held by a test, or a
shim); native reach is hand-written channels, no plugins. `src/app/query` is really `core/query`; `src/read` is the
shared-link web page, not a port target.

## Stage 5, structured notes (about 11.5k TS + 3.9k CSS left; ~4.5k pure; no native)
One gesture carries boards, query lanes, book rows and canvas cards: `core/holdDrag.ts` + `useCarry.ts` (build once,
first; a raw Listener + a recognizer that claims at HOLD_MS + an overlay ghost, not LongPressDraggable). Gantt is
Mermaid on the web: a CustomPainter here. Seams exist: `NoteSeams.book/journal/bookBar/bookFoot`, `ContextBand.boards`,
`AddGates.board/database`, `DrawnBlock`.
Pieces: 5A query core (`lib/core/query/`) · 5B properties, template, tickets and books core (`lib/core/properties.dart`,
`template.dart`, `lib/book/*` logic) · 5C carry and pickers (`lib/core/hold_drag.dart`, `lib/editor/fields/`,
`ticket_mark`, `group_chip`) · 5D boards in the editor (`lib/editor/boards/`) · 5E queries in the editor
(`lib/editor/queries/`) · 5F tickets in the editor (`lib/editor/tickets/`) · 5G notebook (`lib/book/book_view` …) ·
5H journal and templates · 5I shell wiring. Order: A, B, C, D together; E after A+C; F after B+C; G, H after B; I last.

## Stage 6, canvas (3.5k; 1.3k pure)
Custom, not InteractiveViewer: a camera ChangeNotifier read at paint, `gestures.ts` ported to a raw Listener, cards as
widgets under one transform (`MarkdownView` for text cards, only near the viewport), lines/grid/minimap as painters,
selection chrome in screen space. The JSON must be written exactly (Obsidian opens it). Team canvases need
`Y.Map`/`Y.Array`/nested text in `native/src/crdt.rs`, proven against the web's Yjs.
Pieces: 6A model (`lib/canvas/` pure files) · 6B camera and gestures · 6C view and cards · 6D selection · 6E minimap ·
6F frames in a note and the book's mark · 6G team canvas. Order: A first with B and G's Rust half; C; then D, E, F.

## Stage 8, voice and AI
Both engines are Tauri-free (`whisper/*` 2.9k, `llm/*` 2.2k, `write_up.rs`, `transcript.rs`, `recording_jobs.rs`);
`model_files.rs` names `tauri::async_runtime` (a local shim crate named `tauri`, or a held copy). There must be ONE
ggml: whisper built against llama's through the vendored `whisper-rs-sys` (`[patch.crates-io]`), `llama-cpp-2 = "=0.1.156"`.
The web app's NDK is 26.3; Flutter's script takes 28.x: pick one. Dictation has no microphone to port (the WebView
recorded): a new Kotlin `AudioRecord` pushing into Rust over JNI. Meetings: `MeetingService.kt` and friends ported
nearly verbatim (JNI symbols are tied to package `com.mattssoftware.glyph.*`). Events keep the web's names
(`capture://partial` …) through `NativeCallable.listener`; Rust allocates each buffer, Dart frees it.
Models: ggml-base.en-q5_1 (60 MB), ggml-small.en-q5_1 (190 MB), Qwen3.5 2B/4B/9B (1.3/2.7/5.7 GB), gemma-4-E4B (5 GB);
local copies for tests in ../glyph/models.
Pieces: 8A engines build · 8B events and async jobs · 8C native commands · 8D dictation mic · 8E meetings ·
8F assistant and side key · 8G1 spoken marks · 8G2 commands and routing · 8G3 take and session · 8H capture UI ·
8I AI runs and format · 8J fills · 8K editor AI surface · 8L tapes, scene, settings.
Order: A and B first; G1–G3, I, J at once (pure); C after A+B; D, E, F after C; H after G3+C; K after I+C; L last.

8I, 8J, 8K and 8L's scene, with 9E's list of the plugins that ship, are in lib/ and not yet called from lib/root:
docs/STAGE8_AI.md is what is where and every seam the root has to call (2026-10-09).

## Stage 9, the rest
Web-bundle OTA has nothing to carry over; what remains is the signed `apk.json`, fetch, verify, install. `backup.rs`
and `export.rs` are Tauri-free; SAF (`LibraryTree.kt`, the real `saf.rs`) is the keystone for a chosen folder, backup
and the write-up. Notion, Slack, geocode and link preview become Dart over HttpClient; their secrets go in the
Keystore store. A development build must not pull the real app's updates.
Pieces: 9A SAF and library folder · 9B backup · 9C export · 9D reset and diagnostics · 9E plugin core ·
9F Notion, GitHub, Slack, Claude · 9G links out · 9H academy, guide, guidebook · 9I updates and phone notices.
Order: A first (B needs it); C, D, E, G, H independent; F after E; I needs 8B and the signing decision.

## Stage 10
Wide layouts (useWideScreen, unfold, the hinge channel, the aside, hover); Mac (real data dir, dylib bundled and
signed, mic, system audio, drives, notarisation); Windows (no project yet; MSVC runner; no certificate held); iPhone
(the web app builds no engines for iOS); Android signing (release is on the debug key; which id and key); size and
speed; moving a library over (separate sandboxes: install over with the same id and key, or export/import, or a shared
folder, or sync); replacing OTA (signed APK self-update, a store, or code push).

Defaults taken where a choice was needed: gantt as a painter; the `tauri` shim crate if it compiles, else a held copy;
secrets in the Keystore store; the app stays `com.mattssoftware.glyph.flutter` on its own key until Matt decides.
