//! Ghost.md's core for the Flutter app: the Tauri app's notes library, as it is, behind a C ABI.
//!
//! `#[path]` points at the REAL files in `../glyph/src-tauri/src`, the way that repo's own
//! `tools/host-tests/src/lib.rs` does, so there is no second library to drift: a note written by this crate is
//! the file the Tauri app would have written, because the same lines wrote it. The files included hold no
//! `tauri::` type (note.rs says why that is a rule there), and this crate is what the rule now pays for.
//!
//! What is this crate's own:
//!
//! - `paths`: the directory names, which the original keeps beside code that needs a Tauri `AppHandle`.
//! - `saf`: the folder chosen through Android's picker, which the Tauri app reaches over JNI into its own
//!   Kotlin. The Flutter app has no such Kotlin yet, so this one answers that it cannot.
//! - `kept`: the few functions `delete_note` needs from three files that do name Tauri, copied word for word.
//! - `dispatch`: the commands, each doing what its `#[tauri::command]` in commands.rs or library_commands.rs
//!   does, taking the same camelCase JSON the web page sent to `invoke`.
//! - `crypto`, `crdt`, `files`: stage 7 (docs/STAGE7.md). The account's keys and the sealed wire, as the web app
//!   asks them of WebCrypto; Yjs documents, by `yrs`; and the files sync carries. Each lists its commands.
//! - `ffi`: the three C functions Dart calls (lib/core/native/ghost_worker.dart).
//!
//! Never built from inside ../glyph, and it builds nothing there: cargo's target directory is `native/target`.
//!
//! ```sh
//! tool/build-native.sh        # the tests, the Mac's library for Dart's tests, the phone's .so
//! ```

// Declared at the top level so each `#[path]` resolves against src/, one predictable base.
#[path = "../../../glyph/src-tauri/src/note.rs"]
pub mod note;

#[path = "../../../glyph/src-tauri/src/fsx.rs"]
pub mod fsx;

#[path = "../../../glyph/src-tauri/src/lock.rs"]
pub mod lock;

// The process's locks. Only `PROGRESS_FILE` is used yet (a deleted note's write-up); the rest are the capture's
// and the write-up's, which arrive with stage 8.
#[path = "../../../glyph/src-tauri/src/guards.rs"]
pub mod guards;

// The database the notes lived in before 1.3.0: `library/move_in.rs` reads it once.
#[path = "../../../glyph/src-tauri/src/store.rs"]
pub mod store;

#[path = "../../../glyph/src-tauri/src/library/mod.rs"]
pub mod library;

#[path = "../../../glyph/src-tauri/src/library_root.rs"]
pub mod library_root;

// A meeting's write-up files, for the two a deleted note takes with it.
#[path = "../../../glyph/src-tauri/src/jobs.rs"]
pub mod jobs;

#[cfg(test)]
#[path = "../../../glyph/src-tauri/src/test_support/temp.rs"]
pub mod test_support;

pub mod crdt;
pub mod crypto;
pub mod dispatch;
pub mod ffi;
pub mod files;
pub mod kept;
pub mod paths;
pub mod saf;
