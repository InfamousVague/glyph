//! What the two doors into the engines share when neither can see the other's
//! state: the page's capture commands hold theirs in Tauri-managed state
//! (`CaptureState`, `AiState`), and a meeting's write-up arrives over JNI with
//! no Tauri in sight (`recording_jobs.rs`, `write_up.rs`), so the few facts
//! they must agree on live here as crate-level statics. Every target, no Tauri
//! types, so both sides can name them.
//!
//! - Whether a capture is running (`capturing`), derived from the capture slot
//!   under its own lock after every change of it, never stored by hand: a stop
//!   for an old capture racing a new start cannot clear the flag while the new
//!   capture runs. A write-up refuses to start against one.
//! - The one small.en at a time (`WRITE_UP`): a recording's refine pass and a
//!   meeting's write-up both load the 190 MB model, and the second to arrive is
//!   told "busy" rather than loading it twice. Tried, never waited on.
//! - The abort every background job watches (`abort_jobs`), raised with a
//!   reason (`abort_with`): a dictation starting mid-write-up wins the cores
//!   ("capturing"), a foreground generation preempts a background piece
//!   ("busy"), the app quitting ends a piece before C++'s destructors run
//!   ("shutdown"), and Kotlin's cancel says "cancel", "thermal", "timeout" or
//!   "meeting". The job reads the reason once the flag has ended its work.
//! - The one lock every `.progress` write takes (`PROGRESS_FILE`), under which
//!   a writer re-reads the file's phase first, so a cancel cannot be undone by
//!   the watcher's next tick (`jobs::Progress::save`).
//! - Which note's write-up is on (`RUNNING_JOB`), for the cancel that waits
//!   for it to clear.
//! - The one rule for a background job's cores (`background_threads`): half of
//!   what the foreground would take, never under two, applied to whisper's
//!   `min(4, cores)` and llama's `clamp(2, 6)` alike, and only while the app is
//!   in front, since with it closed nobody is typing.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};

use crate::lock::{lock, try_lock};

/// Whether a capture is running: see `set_capturing`.
static CAPTURING: AtomicBool = AtomicBool::new(false);

/// Records whether the capture slot holds a capture. Called under that slot's
/// own lock after every change of it, so the flag is what the slot says and
/// never what a racing command believed.
pub fn set_capturing(on: bool) {
    CAPTURING.store(on, Ordering::SeqCst);
}

/// Whether a capture is running now.
pub fn capturing() -> bool {
    CAPTURING.load(Ordering::SeqCst)
}

/// The one small.en at a time: held for a refine pass or a write-up.
pub static WRITE_UP: Mutex<()> = Mutex::new(());

/// The `WRITE_UP` guard if nothing holds it, `None` if something does. A
/// guard poisoned by a panic is handed over rather than refused, for the reason
/// `lock` gives: "busy" for the life of the process is a brick.
pub fn try_write_up() -> Option<MutexGuard<'static, ()>> {
    try_lock(&WRITE_UP)
}

/// Held for every write to a `jobs/<id>.progress` in this process.
pub static PROGRESS_FILE: Mutex<()> = Mutex::new(());

/// The abort flag, shared with every session and generation a background job
/// makes. An `Arc` because `Session::new` and `Llm::generate` take one; a bare
/// static cannot be.
static ABORT: OnceLock<Arc<AtomicBool>> = OnceLock::new();

/// Why the abort was raised, if it was.
static ABORT_REASON: Mutex<Option<String>> = Mutex::new(None);

/// The flag every background job watches. Lowered by `write_up::run` at its
/// start (`clear_abort`); raised by `abort_with`.
pub fn abort_jobs() -> Arc<AtomicBool> {
    Arc::clone(ABORT.get_or_init(|| Arc::new(AtomicBool::new(false))))
}

/// Raises the flag and records why. The reason stands until the next
/// `clear_abort`, so a job that ended can still read it.
pub fn abort_with(reason: &str) {
    *lock(&ABORT_REASON) = Some(reason.to_string());
    abort_jobs().store(true, Ordering::SeqCst);
}

/// The reason the flag was last raised for, or "capturing" when it was raised
/// with none recorded (the flag can be stored directly by a caller with only
/// the `Arc`).
pub fn abort_reason() -> String {
    lock(&ABORT_REASON).clone().unwrap_or_else(|| "capturing".to_string())
}

/// Lowers the flag and forgets the reason: what a job does before it begins,
/// so a reason from the last job is never read as this one's.
pub fn clear_abort() {
    *lock(&ABORT_REASON) = None;
    abort_jobs().store(false, Ordering::SeqCst);
}

/// The note id whose write-up `write_up::run` is on, or `None`. Cleared by the
/// run's drop guard however the run ends, a panic included.
pub static RUNNING_JOB: Mutex<Option<String>> = Mutex::new(None);

/// How many cores a background job takes while the app is in front: half of
/// what the foreground would, never under two.
pub fn background_threads(foreground: i32) -> i32 {
    (foreground / 2).max(2)
}

/// The statics above are one per process, and the tests run in parallel: a
/// test that raises the abort or holds `WRITE_UP` would trip a write-up test
/// running beside it. Every test that touches them takes this first.
#[cfg(test)]
pub(crate) static TEST_SERIAL: Mutex<()> = Mutex::new(());

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_background_job_takes_half_the_cores_and_never_under_two() {
        assert_eq!(background_threads(6), 3);
        assert_eq!(background_threads(4), 2);
        assert_eq!(background_threads(3), 2);
        assert_eq!(background_threads(2), 2);
        assert_eq!(background_threads(1), 2);
    }

    #[test]
    fn an_abort_carries_its_reason_until_the_next_job_clears_it() {
        let _one = lock(&TEST_SERIAL);
        let flag = abort_jobs();
        clear_abort();
        assert!(!flag.load(Ordering::SeqCst));
        assert_eq!(abort_reason(), "capturing", "a flag raised with no reason recorded is a capture");
        abort_with("thermal");
        assert!(flag.load(Ordering::SeqCst), "the same Arc every caller holds");
        assert_eq!(abort_reason(), "thermal");
        clear_abort();
        assert!(!abort_jobs().load(Ordering::SeqCst));
        assert_eq!(abort_reason(), "capturing");
    }

    #[test]
    fn the_write_up_lock_is_tried_never_waited_on_and_survives_a_panic() {
        let _one = lock(&TEST_SERIAL);
        let held = try_write_up().expect("free");
        assert!(try_write_up().is_none(), "busy while held");
        drop(held);
        let _ = std::thread::spawn(|| {
            let _guard = WRITE_UP.lock().unwrap();
            panic!("a pass dies with the guard");
        })
        .join();
        assert!(WRITE_UP.is_poisoned());
        assert!(try_write_up().is_some(), "recovered, or every later pass would be refused");
    }
}
