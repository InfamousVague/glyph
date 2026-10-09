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
//! - `saf`: off Android only, the stand-in for the folder chosen through Android's picker. On a phone it is the
//!   Tauri app's own saf.rs, included below, calling this app's port of its Kotlin
//!   (android/…/glyph/files/LibraryTree.kt).
//! - `kept`: the few functions `delete_note`, the reset and the library's move need from files that do name
//!   Tauri, copied word for word.
//! - `dispatch`: the commands, each doing what its `#[tauri::command]` in commands.rs or library_commands.rs
//!   does, taking the same camelCase JSON the web page sent to `invoke`.
//! - `crypto`, `crdt`, `files`: stage 7 (docs/STAGE7.md). The account's keys and the sealed wire, as the web app
//!   asks them of WebCrypto; Yjs documents, by `yrs`; and the files sync carries. Each lists its commands.
//! - `ffi`: the C functions Dart calls (lib/core/native/ghost_worker.dart).
//! - `events`, `work`: stage 8B. Events from any Rust thread to the app, and the long job: a command that
//!   answers an id at once, works on a thread of its own and reports by events.
//! - `capture`, `ai`, `recording`, `models` (the `voice` feature): stage 8C. The Tauri app's dictation, language
//!   model and write-up commands, each answering the JSON its `#[tauri::command]` answered and emitting the web's
//!   event names; and the audio door the phone's microphone pushes through (`ghost_capture_push`, and its JNI
//!   twin for `DictationMic.kt`).
//! - `smoke` (the `voice` feature): stage 8A's one command per engine, proving each through the C functions.
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

// Stage 9A, a folder chosen through Android's picker: Rust's calls into Kotlin (files/LibraryTree.kt), which
// `library_root::open_root` and the backup stand on. Compiled for Android only, as in the Tauri app; anywhere else
// src/saf.rs answers that no such folder can be opened, which is true there.
#[cfg(target_os = "android")]
#[path = "../../../glyph/src-tauri/src/saf.rs"]
pub mod saf;

// Every note onto a removable drive, as plain files (stage 9B). Here from 9A on, since saf.rs writes a drive's
// tree as this file's `Target`.
#[path = "../../../glyph/src-tauri/src/backup.rs"]
pub mod backup;

// Everything the app keeps, as one zip to carry away (stage 9C): the archive, written as a stream.
#[path = "../../../glyph/src-tauri/src/export.rs"]
pub mod export;

// A meeting's write-up files, for the two a deleted note takes with it.
#[path = "../../../glyph/src-tauri/src/jobs.rs"]
pub mod jobs;

// Stage 8A, the engines (the `voice` feature; docs/STAGES_5_6_8_9.md). All Tauri-free but model_files.rs, which
// names `tauri::async_runtime`: shims/tauri answers to that name with those two functions.

// A recording's phrases as the paragraphs of its transcript.
#[cfg(feature = "voice")]
#[path = "../../../glyph/src-tauri/src/transcript.rs"]
pub mod transcript;

// Speech to text: whisper.cpp, the streaming core, WAV files.
#[cfg(feature = "voice")]
#[path = "../../../glyph/src-tauri/src/whisper/mod.rs"]
pub mod whisper;

// A model file, whichever engine reads it, and its verified, resumable download.
#[cfg(feature = "voice")]
#[path = "../../../glyph/src-tauri/src/model_files.rs"]
pub mod model_files;

// The language model: llama.cpp, the prompt, the catalogue.
#[cfg(feature = "voice")]
#[path = "../../../glyph/src-tauri/src/llm/mod.rs"]
pub mod llm;

// A meeting's write-up, start to end. Called by the JNI door below on the phone, and by recording.rs's three
// `write_up_*` commands everywhere.
#[cfg(feature = "voice")]
#[path = "../../../glyph/src-tauri/src/write_up.rs"]
pub mod write_up;

// The JNI door the meeting service and its WorkManager job call: finish, run, cancel. Its symbols name the
// Kotlin class `com.mattssoftware.glyph.recordings.RecordingJob`.
#[cfg(all(feature = "voice", target_os = "android"))]
#[path = "../../../glyph/src-tauri/src/recording_jobs.rs"]
pub mod recording_jobs;

// write_up.rs asks `crate::recordings` where a note's recording is: the two functions held in `kept`.
#[cfg(feature = "voice")]
pub use kept::recordings;

// The reset's own lines ask `crate::library_commands` which folders are a chosen library's bookkeeping.
pub use kept::library_commands;

// kept/videos.rs names the pictures as the Tauri app's videos.rs does (`crate::images::adopt`, for a film's poster).
pub use kept::images;

#[cfg(test)]
#[path = "../../../glyph/src-tauri/src/test_support/temp.rs"]
pub mod test_support;

#[cfg(feature = "voice")]
pub mod ai;
#[cfg(feature = "voice")]
pub mod capture;
pub mod crdt;
pub mod crdt_wire;
pub mod crypto;
pub mod dispatch;
pub mod events;
pub mod ffi;
pub mod files;
pub mod kept;
#[cfg(feature = "voice")]
pub mod models;
pub mod paths;
#[cfg(feature = "voice")]
pub mod recording;
#[cfg(not(target_os = "android"))]
pub mod saf;
#[cfg(feature = "voice")]
pub mod smoke;
pub mod work;
