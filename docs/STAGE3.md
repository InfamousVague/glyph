# Stage 3, the library: what was read in tauri/ (2026-10-07), and the plan

Read, not built. Paths are in `tauri/`.

## What the library is
- Markdown files: `<app data>/Library/**/*.md` is the truth; `.glyph/index.sqlite` is a cache Rust rebuilds. `store.rs`
  is only the pre-1.3.0 migration. Search is page-side over `list_notes`' bodies; nothing watches the folder (the page
  re-asks on resume and after its own writes); Rust emits no library events.
- Pure Rust (no Tauri type): `note.rs`, `library/**`, `library_root.rs`, `fsx.rs`, `lock.rs`, `guards.rs`, `store.rs`.
  `tools/host-tests/src/lib.rs` already includes them by `#[path]` with four dependencies.
- Tauri glue to redo by hand: `commands.rs` (`install`, each command = lock + one `Library` call, plus the pure
  `into_mutation` and `delete_with_files` that live in it), `paths.rs` (only its string constants are needed).

## Commands stage 3 exposes (args as JSON, camelCase; errors are a sentence)
`init {dataDir, cacheDir}` (new, idempotent), `list_notes`, `get_note {id}`, `create_note {id, body, source}`,
`update_note {id, body, expectedRevision}`, `delete_note {id}`, `set_note_starred {id, starred}`,
`set_note_archived {id, archived}`, `store_apply {note}`, `set_note_recording`, `apply_command_mutation`,
`undo_command_mutation`, `latest_command_mutation`, `versions_read {id}`, `versions_write {id, text}`, `library_root`.

## Shape
- `native/` crate `ghost_core` (cdylib + rlib) that `#[path]`-includes the real files from `tauri/src-tauri/src`,
  with a `paths` shim (constants, held to the original by a test) and an Android `saf` stub that answers Err.
  Dependencies: rusqlite 0.40.2 bundled, serde, serde_json, uuid v4.
- C ABI: `ghost_invoke(cmd, args_json) -> {"ok": ..} | {"err": ".."}`, `ghost_free`, `ghost_set_listener` (unused
  yet); `catch_unwind` round the dispatcher. Dart: one long-lived worker isolate owns the library; never the UI isolate.
- Build: `tool/build-native.sh` → `cargo build --release --target aarch64-linux-android` (NDK 28.2.13676358, API 24,
  `-Wl,-z,max-page-size=16384`) → `android/app/src/main/jniLibs/arm64-v8a/libghost_core.so`. The same crate builds as a
  dylib on the Mac for `cargo test` and Dart tests.

## Stays in Dart (the web's localStorage)
`glyph-preferences` (with workspaces `{list, notes}`, trash `{id: ms}`, tab groups), the device-only keys, open tabs.
Workspaces are a preference and the folder follows (`get_note` then `store_apply` with a new `path`). Delete in the UI
is the trash preference; Rust's `delete_note` is "for good". The tree is derived.

## Traps
- `store_apply` overwrites the sidecar: always `get_note` first, never apply a note from `list_notes`.
- `revision` lives in the index only; never keep it. `updatedAt` is the file's mtime.
- Ids are file names (`fsx::plain_id`); the app mints UUID v4. A title change renames the file, so `path` moves.
- A blank new note is a draft in memory with no file until it has words.
- The body may carry its own front-matter block; never merge it with the library's.
- `source` is a free string. Dart never opens `index.sqlite`.
- Unknown until built: `library_root.rs` under `#[path]` for Android; whether Tauri's data dir is `context.dataDir`;
  `list_notes` on 2,000 notes.

## Pieces
1. Native crate and build. 2. Dart binding and isolate. 3. `NoteLibrary` over it, wired into the root.
4. Workspaces, trash and preferences persistence. 5. Search. 6. Device paths, lifecycle, versions, backup rules.
