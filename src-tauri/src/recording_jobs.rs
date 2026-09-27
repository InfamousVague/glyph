//! The Rust half of a meeting's write-up on Android: three JNI entry points
//! the meeting service and the WorkManager job call, with the app closed,
//! answering JSON. The bodies are `write_up::{finish, run, cancel}`; this
//! file is the door, shaped like `update_alerts.rs`.
//!
//! No Tauri in the process is assumed: the Kotlin side
//! (`recordings/RecordingJob.kt`) loads `glyph_lib` itself, because a
//! WorkManager job can start the process with no activity, and calls these on
//! its own threads. Paths only: Kotlin hands over `context.dataDir`, and
//! `write_up` joins the library, the recordings, the models and the jobs under
//! it, the same names the app resolves through `paths.rs`.
//!
//! A panic must not unwind into the JVM (undefined behaviour across `extern
//! "system"`), so every body runs under `catch_unwind` and a panic becomes an
//! `error` field like any other failure.

use std::path::PathBuf;

use jni::objects::{JClass, JString};
use jni::sys::jstring;
use jni::JNIEnv;

/// The JSON answer for a body that could not read its strings, or panicked.
fn error(message: &str) -> String {
    serde_json::json!({ "error": message }).to_string()
}

/// A JNI string as Rust's, or `None` when the JVM could not hand it over.
fn string(env: &mut JNIEnv<'_>, value: &JString<'_>) -> Option<String> {
    env.get_string(value).ok().map(Into::into)
}

/// `answer` handed back to the JVM; null only if it could not be given a
/// string at all.
fn reply(env: &JNIEnv<'_>, answer: String) -> jstring {
    env.new_string(answer).map(|s| s.into_raw()).unwrap_or(std::ptr::null_mut())
}

/// `RecordingJob.finish(dataDir, noteId, title): String?` - the recording
/// closed: its header put right, its length on the note, its write-up queued.
/// `{"recordedMs": n}` or `{"error": "..."}`.
#[no_mangle]
pub extern "system" fn Java_com_mattssoftware_glyph_recordings_RecordingJob_finish<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    data_dir: JString<'local>,
    note_id: JString<'local>,
    title: JString<'local>,
) -> jstring {
    let dir = string(&mut env, &data_dir);
    let id = string(&mut env, &note_id);
    let title = string(&mut env, &title).unwrap_or_default();
    let answer = std::panic::catch_unwind(move || {
        let (Some(dir), Some(id)) = (dir, id) else { return error("no directory") };
        match crate::write_up::finish(&PathBuf::from(dir), &id, &title) {
            Ok(recorded_ms) => serde_json::json!({ "recordedMs": recorded_ms }).to_string(),
            Err(message) => error(&message),
        }
    })
    .unwrap_or_else(|_| error("the write-up panicked"));
    reply(&env, answer)
}

/// `RecordingJob.run(dataDir, noteId, options): String?` - the write-up, as
/// far as it gets this time: `write_up::Answer` as JSON (`done`, `retry`,
/// `needsModel`, `error`, `cancelled`, `gone`, `alreadyDone`). Blocks for as
/// long as it runs; progress is the `.progress` file.
#[no_mangle]
pub extern "system" fn Java_com_mattssoftware_glyph_recordings_RecordingJob_run<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    data_dir: JString<'local>,
    note_id: JString<'local>,
    options: JString<'local>,
) -> jstring {
    let dir = string(&mut env, &data_dir);
    let id = string(&mut env, &note_id);
    let options = string(&mut env, &options).unwrap_or_default();
    let answer = std::panic::catch_unwind(move || {
        let (Some(dir), Some(id)) = (dir, id) else { return error("no directory") };
        let options: crate::write_up::Options = serde_json::from_str(&options).unwrap_or_default();
        crate::write_up::run(&PathBuf::from(dir), &id, &options).to_json()
    })
    .unwrap_or_else(|_| error("the write-up panicked"));
    reply(&env, answer)
}

/// `RecordingJob.cancel(dataDir, noteId, reason): String?` - a run for the
/// note ended with `reason` ("cancel", "thermal", "timeout", "meeting");
/// `{"cancelled": true}` when there was one to end.
#[no_mangle]
pub extern "system" fn Java_com_mattssoftware_glyph_recordings_RecordingJob_cancel<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    data_dir: JString<'local>,
    note_id: JString<'local>,
    reason: JString<'local>,
) -> jstring {
    let dir = string(&mut env, &data_dir);
    let id = string(&mut env, &note_id);
    let reason = string(&mut env, &reason).unwrap_or_else(|| "cancel".to_string());
    let answer = std::panic::catch_unwind(move || {
        let (Some(dir), Some(id)) = (dir, id) else { return error("no directory") };
        let cancelled = crate::write_up::cancel(&PathBuf::from(dir), &id, &reason);
        serde_json::json!({ "cancelled": cancelled }).to_string()
    })
    .unwrap_or_else(|_| error("the write-up panicked"));
    reply(&env, answer)
}
