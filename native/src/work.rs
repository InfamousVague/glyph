//! Long jobs: a command that takes more than a moment answers with an id at once and does its work on a thread
//! of its own, reporting by events (events.rs).
//!
//! Why: the app's worker isolate is serial (lib/core/native/ghost_worker.dart). A command that transcribed or
//! generated inside `ghost_invoke` would hold every save and every `list_notes` behind it for as long as it
//! ran, and its own progress events with them.
//!
//! ```rust,ignore
//! // in a command:
//! let id = crate::work::start("transcribe", move |job| {
//!     while more && !job.cancelled() {
//!         job.emit("capture://partial", json!({ "text": so_far }));   // any event, any number
//!     }
//!     Ok(json!({ "text": all }))                                       // becomes job://end's `ok`
//! })?;
//! Ok(json!({ "id": id }))
//! ```
//!
//! The rules a job keeps:
//!
//! - **It never holds the notes' lock while it works.** It takes `NotesStore::lock()` for one read or one write
//!   and lets go, as a command does. A lock held across a decode is the serial isolate again by another road.
//! - **It ends with exactly one `job://end`**: `{"id", "kind", "ok": <value>}` or `{"id", "kind", "err":
//!   "<sentence>"}`. A panic is an `err` (the sentence ffi.rs gives one). By the time it is emitted the job is
//!   no longer in `jobs_running`.
//! - **Its own events carry its id** (the web's payloads already do: `ai://progress` has `id`), since several
//!   jobs may run and the app's stream is one.
//! - **It watches `job.cancelled()`**, or hands `job.cancel_flag()` to an engine that takes an abort flag (both
//!   do). `job_cancel {id}` raises it; what the job answers after that is its own business (usually an `err`).
//!
//! Commands here: `job_cancel {id}` -> whether such a job was running; `jobs_running` -> `[{id, kind}]`. With
//! the `test-hooks` feature: `test_emit {event, payload}` (emitted from another thread, answers at once) and
//! `test_long_job {ms, ticks}` (a job that reads the library `ticks` times over `ms`, a `test://tick` each).

use std::collections::HashMap;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use serde::Deserialize;
use serde_json::{json, Value};

use crate::dispatch::Core;

/// The event every job ends with.
pub const END: &str = "job://end";

/// A job, as its own work sees it.
pub struct Job {
    pub id: String,
    pub kind: &'static str,
    cancel: Arc<AtomicBool>,
}

impl Job {
    /// Whether `job_cancel` asked this job to stop.
    pub fn cancelled(&self) -> bool {
        self.cancel.load(Ordering::SeqCst)
    }

    /// The same, as the flag both engines take (`whisper::engine::Session::new`, `Llm::generate`).
    pub fn cancel_flag(&self) -> Arc<AtomicBool> {
        Arc::clone(&self.cancel)
    }

    /// An event of this job's. `payload` should carry `self.id` under the key the web's event has it.
    pub fn emit(&self, event: &str, payload: Value) {
        crate::events::emit(event, &payload);
    }
}

struct Running {
    kind: &'static str,
    cancel: Arc<AtomicBool>,
}

static RUNNING: Mutex<Option<HashMap<String, Running>>> = Mutex::new(None);

fn running<R>(with: impl FnOnce(&mut HashMap<String, Running>) -> R) -> R {
    with(crate::lock::lock(&RUNNING).get_or_insert_with(HashMap::new))
}

/// Starts `work` on a thread of its own and answers its id. See the module's header for what `work` owes.
pub fn start(kind: &'static str, work: impl FnOnce(&Job) -> Result<Value, String> + Send + 'static) -> Result<String, String> {
    let id = crate::note::new_id();
    let cancel = Arc::new(AtomicBool::new(false));
    running(|jobs| jobs.insert(id.clone(), Running { kind, cancel: Arc::clone(&cancel) }));
    let job = Job { id: id.clone(), kind, cancel };
    let spawned = std::thread::Builder::new().name(format!("ghost-job-{kind}")).spawn(move || {
        let result = catch_unwind(AssertUnwindSafe(|| work(&job)));
        running(|jobs| jobs.remove(&job.id));
        let said = match result {
            Ok(Ok(value)) => json!({ "id": job.id, "kind": job.kind, "ok": value }),
            Ok(Err(sentence)) => json!({ "id": job.id, "kind": job.kind, "err": sentence }),
            Err(payload) => json!({ "id": job.id, "kind": job.kind, "err": crate::ffi::panic_said(payload) }),
        };
        crate::events::emit(END, &said);
    });
    if let Err(e) = spawned {
        running(|jobs| jobs.remove(&id));
        return Err(format!("Ghost.md's core could not start a thread for that: {e}"));
    }
    Ok(id)
}

/// Asks job `id` to stop; `false` when no such job is running.
pub fn cancel(id: &str) -> bool {
    running(|jobs| jobs.get(id).map(|job| job.cancel.store(true, Ordering::SeqCst)).is_some())
}

const COMMANDS: &[&str] = &["job_cancel", "jobs_running"];
#[cfg(any(test, feature = "test-hooks"))]
const TEST_COMMANDS: &[&str] = &["test_emit", "test_long_job"];

/// Whether `command` is one of this file's that needs no library.
pub fn has(command: &str) -> bool {
    COMMANDS.contains(&command)
}

/// Whether `command` is one of this file's that works on the open core.
pub fn has_with_core(command: &str) -> bool {
    #[cfg(any(test, feature = "test-hooks"))]
    if TEST_COMMANDS.contains(&command) {
        return true;
    }
    let _ = command;
    false
}

#[derive(Deserialize)]
struct ById {
    id: String,
}

pub fn call(command: &str, args: Value) -> Result<Value, String> {
    match command {
        "job_cancel" => {
            let ById { id } = crate::dispatch::read(command, args)?;
            Ok(Value::Bool(cancel(&id)))
        }
        "jobs_running" => Ok(running(|jobs| jobs.iter().map(|(id, job)| json!({ "id": id, "kind": job.kind })).collect())),
        _ => Err(format!("Ghost.md's core has no command named {command}.")),
    }
}

#[cfg(any(test, feature = "test-hooks"))]
#[derive(Deserialize)]
struct Emit {
    event: String,
    #[serde(default)]
    payload: Value,
}

#[cfg(any(test, feature = "test-hooks"))]
#[derive(Deserialize)]
struct Long {
    ms: u64,
    ticks: u64,
}

/// The commands that start work on the core. `core` is the `Arc`, for the thread to keep.
pub fn call_with_core(core: &Arc<Core>, command: &str, args: Value) -> Result<Value, String> {
    match command {
        // An event from a thread that is not the caller's, after the command has answered.
        #[cfg(any(test, feature = "test-hooks"))]
        "test_emit" => {
            let Emit { event, payload } = crate::dispatch::read(command, args)?;
            std::thread::spawn(move || crate::events::emit(&event, &payload));
            Ok(Value::Null)
        }
        // A job shaped like the real ones: `ms` of work in `ticks` steps, the library read for a moment at each
        // and never held between, a `test://tick {id, n, notes}` after each, cancellable.
        #[cfg(any(test, feature = "test-hooks"))]
        "test_long_job" => {
            let Long { ms, ticks } = crate::dispatch::read(command, args)?;
            let core = Arc::clone(core);
            let id = start("test", move |job| {
                let step = std::time::Duration::from_millis(ms / ticks.max(1));
                for n in 1..=ticks {
                    std::thread::sleep(step);
                    if job.cancelled() {
                        return Err(format!("cancelled after {} ticks", n - 1));
                    }
                    let notes = core.notes().lock().list_notes().map_err(|e| e.to_string())?.len();
                    job.emit("test://tick", json!({ "id": job.id, "n": n, "notes": notes }));
                }
                Ok(json!({ "ticks": ticks }))
            })?;
            Ok(json!({ "id": id }))
        }
        _ => {
            let _ = (core, args);
            Err(format!("Ghost.md's core has no command named {command}."))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::events::tests::{heard, wait_for};
    use std::time::{Duration, Instant};

    fn ended(id: &str) -> Value {
        let id = id.to_string();
        wait_for(Duration::from_secs(20), move |event, payload| event == END && payload["id"] == id.as_str()).expect("the job ends")
    }

    #[test]
    fn a_job_answers_at_once_and_ends_with_one_event() {
        // The work waits to be told to go on, so "the id came back first" is a fact and not a race.
        let (go, wait) = std::sync::mpsc::channel::<()>();
        let id = start("test", move |job| {
            wait.recv().map_err(|e| e.to_string())?;
            job.emit("test://step", json!({ "id": job.id, "n": 1 }));
            Ok(json!({ "made": 7 }))
        })
        .unwrap();
        assert!(call("jobs_running", json!({})).unwrap().as_array().unwrap().iter().any(|job| job["id"] == id.as_str() && job["kind"] == "test"));
        assert!(heard(|_, payload| payload["id"] == id.as_str()).is_empty(), "nothing said before the work");
        go.send(()).unwrap();
        assert_eq!(ended(&id), json!({ "id": id, "kind": "test", "ok": { "made": 7 } }));
        assert!(!call("jobs_running", json!({})).unwrap().as_array().unwrap().iter().any(|job| job["id"] == id.as_str()), "gone before its end is said");
        let mine = heard(|_, payload| payload["id"] == id.as_str());
        assert_eq!(mine.iter().map(|(event, _)| event.as_str()).collect::<Vec<_>>(), ["test://step", END]);
        assert_eq!(call("job_cancel", json!({ "id": id })).unwrap(), false, "nothing to cancel once it has ended");
    }

    #[test]
    fn a_refusal_and_a_panic_are_an_err() {
        let refused = start("test", |_| Err("the model is not there".to_string())).unwrap();
        assert_eq!(ended(&refused)["err"], "the model is not there");
        let died = start("test", |_| panic!("the decoder fell over")).unwrap();
        assert_eq!(ended(&died)["err"], "Ghost.md's core stopped in the middle of that: the decoder fell over");
    }

    #[test]
    fn a_job_is_cancelled_by_its_id() {
        let id = start("test", |job| {
            let until = Instant::now() + Duration::from_secs(10);
            while !job.cancelled() {
                assert!(Instant::now() < until, "never cancelled");
                std::thread::sleep(Duration::from_millis(5));
            }
            Err("stopped".to_string())
        })
        .unwrap();
        assert_eq!(call("job_cancel", json!({ "id": id })).unwrap(), true);
        assert_eq!(ended(&id)["err"], "stopped");
        assert_eq!(call("job_cancel", json!({ "id": "nobody" })).unwrap(), false);
    }
}
