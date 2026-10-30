//! Dictation's commands and events (the `voice` feature): what `tauri/src-tauri/src/capture_commands.rs`,
//! `capture_commands/models.rs` and `capture_commands/refine.rs` are to the Tauri app, command for command, over
//! the same engine (`whisper/`, included as it is). Every decision about what to transcribe, when, and what
//! counts as silence is the engine's; this file resolves the directories, holds the loaded model and the one
//! capture in progress, and turns engine events into `events::emit`.
//!
//! NO ALWAYS-ON MICROPHONE. Nothing here opens a microphone at all: audio is pushed in, by `capture_push` or by
//! `ghost_capture_push` from the phone's `DictationMic`, and only between a `capture_start` and its stop or
//! cancel. A push with no capture running is refused, never buffered.
//!
//! THE COMMANDS. "job" means the command answers `{id}` at once and the value given is the `ok` of its
//! `job://end` (work.rs), since the app's worker isolate is serial and none of these may hold it; the rest answer
//! directly. The value is in every case the JSON the Tauri command resolved with, and a refusal is its sentence.
//!
//! - `capture_model_status` -> `{present, name, path, bytes}`; `capture_refine_model_status` the same for the
//!   refine model.
//! - `capture_fetch_model {mirrors?}` (job) -> the status, emitting `capture://model-progress {receivedBytes,
//!   totalBytes}`; `capture_fetch_refine_model {mirrors?}` (job) with `capture://refine-model-progress`.
//!   `mirrors` is models.rs's.
//! - `capture_start {partials?, keep?}` (job) -> `null`: loads the model if it is not loaded and starts a capture;
//!   one already running is cancelled, not refused. Await its end before the first push. With `partials: false`
//!   no guesses run, and with `keep: false` no sample is kept (whisper/stream.rs `Mode`): the words of a meeting
//!   the phone's meeting service records (Matt, 2026-10-30), answered `{partials, keep}` so the app knows the core
//!   took them; a core from before ignores them, runs a dictation and answers `null`.
//! - `capture_push {pcm}` -> `null`: base64 of little-endian f32, 16 kHz mono. Returns at once; inference never
//!   runs here. Await each before the next: the isolate applies them in the order sent.
//! - `capture_stop {recordAs?, append?}` (job) -> `{transcript, recordedMs}`. With `recordAs` the audio is kept
//!   as `<dataDir>/recordings/<id>.wav` (added to its end with `append`) and `recordedMs` is the file's length.
//! - `capture_rewind {toMs}` (job) -> `null`, once `capture://rewound` has gone out.
//! - `capture_cancel` (job) -> `null`. Nothing running is success.
//! - `capture_reassign_recording {fromId, toId, append?}` (job) -> `recordedMs | null`;
//!   `capture_discard_recording {id}` -> `null`.
//! - `capture_refine {id, fromMs, promptTail}` (job) -> `[{text, startMs, endMs}]`, emitting
//!   `capture://refine-progress {id, percent}` (`id` is the note's). Refused with "busy", "model missing" or
//!   "no such recording"; ends "cancelled" when a capture starts mid-pass.
//! - `transcribe_wav {path}` (job) -> `{text, audioMs, elapsedMs, model}`.
//!
//! THE EVENTS a capture emits, from its own thread: `capture://partial {text}` REPLACES the partial line,
//! `capture://segment {text, startMs, endMs}` appends, `capture://rewound {toMs, segments}` replaces the list,
//! `capture://error {message}` means the capture stopped transcribing (its stop then rejects the same).
//!
//! What differs from capture_commands.rs:
//!
//! - **No Tauri state.** The state is this process's ([`STATE`]), since the phone's microphone pushes into it
//!   from Kotlin with no command and no core in hand.
//! - **`ghost_capture_push(samples, count)`** is the plain C door for audio (and, on Android, the JNI function
//!   `DictationMic.push` beside it): the same push without base64 or the isolate. 0 when taken, 1 when no
//!   capture is running, 2 for a null pointer.
//! - **The Mac's system-audio tap** (system_audio.rs, Core Audio) is kept/system_audio.rs: its commands are
//!   there, and [`push`] adds the computer's sound into each chunk while a tap is open, as `capture_push` does
//!   in the Tauri app. A capture's start, stop and cancel close the tap. A phone's meeting takes other apps'
//!   sound in Kotlin (OtherApps.kt).

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::dispatch::{read, Core};
use crate::lock::lock;
use crate::model_files::ModelStatus;
use crate::whisper::{
    engine::{Engine, Session},
    model,
    stream::{Event, Mode},
    worker::Capture,
};

const COMMANDS: &[&str] = &[
    "capture_model_status",
    "capture_fetch_model",
    "capture_refine_model_status",
    "capture_fetch_refine_model",
    "capture_refine",
    "capture_start",
    "capture_push",
    "capture_stop",
    "capture_reassign_recording",
    "capture_discard_recording",
    "capture_rewind",
    "capture_cancel",
    "transcribe_wav",
];

pub fn has(command: &str) -> bool {
    COMMANDS.contains(&command)
}

/// What `transcribe_wav` measured.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Transcript {
    pub text: String,
    /// Length of the audio in the file.
    pub audio_ms: u64,
    /// Inference alone: not the WAV read and not the model load.
    pub elapsed_ms: u64,
    pub model: String,
}

/// What `capture_stop` answers with.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Finished {
    pub transcript: String,
    /// The kept recording's whole length, or null when nothing was kept.
    pub recorded_ms: Option<u64>,
}

/// `capture://refine-progress`, as the page read it.
#[derive(Debug, Clone, Serialize)]
struct RefineProgress {
    id: String,
    percent: i32,
}

/// The loaded model and the capture in progress, for the life of the process: capture_commands.rs's
/// `CaptureState`, with its reasons (a load is a read of the whole file, and a press that waits for one loses
/// its first word).
#[derive(Default)]
struct State {
    /// The engine and the file it was loaded from: a different file (a test's other folder) is loaded afresh.
    engine: Mutex<Option<(PathBuf, Arc<Engine>)>>,
    capture: Mutex<Option<Capture>>,
    /// Held across a download so that two taps on "download" are one download.
    fetching: Mutex<()>,
    fetching_refine: Mutex<()>,
    /// Set by `capture_start` so a refine pass in progress stops within one graph computation.
    refine_abort: Arc<AtomicBool>,
    /// Whether a refine pass is running; a second is refused, not queued.
    refining: AtomicBool,
}

static STATE: OnceLock<State> = OnceLock::new();

fn state() -> &'static State {
    STATE.get_or_init(State::default)
}

/// Takes the running capture out of its slot, if there is one, and tells the guards what the slot now holds.
fn take_capture() -> Option<Capture> {
    crate::guards::change_capture(&state().capture, Option::take)
}

/// The cached engine, loading it on first use. Called on a job's thread, never inside a command.
fn engine(models: &Path) -> Result<Arc<Engine>, String> {
    let status = crate::model_files::status(models, &model::ACTIVE);
    if !status.present {
        return Err(format!("The transcription model ({}) has not been downloaded yet - call capture_fetch_model first.", status.name));
    }
    let path = PathBuf::from(status.path);
    if let Some((loaded, engine)) = lock(&state().engine).as_ref() {
        if *loaded == path {
            return Ok(Arc::clone(engine));
        }
    }
    let engine = Arc::new(Engine::load(&path)?);
    *lock(&state().engine) = Some((path, Arc::clone(&engine)));
    Ok(engine)
}

/// One engine event, as the app hears it.
fn emit(event: Event) {
    match event {
        Event::Partial(partial) => crate::events::emit("capture://partial", &partial),
        Event::Segment(segment) => crate::events::emit("capture://segment", &segment),
        Event::Rewound(rewound) => crate::events::emit("capture://rewound", &rewound),
        Event::Error(failure) => crate::events::emit("capture://error", &failure),
    }
}

/// Audio for the running capture; `false` when none is running. What `capture_push`, the C door and the JNI
/// door all come to. A lock held for a `Vec::extend`, and no inference.
pub fn push(samples: &[f32]) -> bool {
    match lock(&state().capture).as_ref() {
        Some(capture) => {
            // The computer's sound, when a meeting on the Mac asked for it (kept/system_audio.rs): nothing otherwise,
            // and then the chunk is pushed as it came, without a copy.
            let system = crate::kept::system_audio::state();
            if system.capturing() {
                let mut mixed = samples.to_vec();
                system.mix_into(&mut mixed);
                capture.push(&mixed);
            } else {
                capture.push(samples);
            }
            true
        }
        None => false,
    }
}

/// The plain C door for audio: `count` f32 samples at 16 kHz mono, copied before it returns. 0 when the running
/// capture took them, 1 when no capture is running (they are dropped, never kept for the next), 2 for a null
/// pointer. Callable from any thread; the caller keeps the order.
///
/// # Safety
/// `samples` must point to `count` readable f32 values.
#[no_mangle]
pub unsafe extern "C" fn ghost_capture_push(samples: *const f32, count: usize) -> i32 {
    if samples.is_null() {
        return 2;
    }
    // SAFETY: the caller's promise above.
    let samples = unsafe { std::slice::from_raw_parts(samples, count) };
    match std::panic::catch_unwind(|| push(samples)) {
        Ok(true) => 0,
        _ => 1,
    }
}

/// `DictationMic.push(samples, count): Int` (android/…/glyph/capture/DictationMic.kt): the phone's microphone
/// straight into the running capture, from the thread that reads it. The answer is `ghost_capture_push`'s; 2
/// too when the JVM would not hand the array over.
#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_mattssoftware_glyph_capture_DictationMic_push<'local>(
    env: jni::JNIEnv<'local>,
    _class: jni::objects::JClass<'local>,
    samples: jni::objects::JFloatArray<'local>,
    count: jni::sys::jint,
) -> jni::sys::jint {
    let mut copied = vec![0f32; count.max(0) as usize];
    if env.get_float_array_region(&samples, 0, &mut copied).is_err() {
        return 2;
    }
    match std::panic::catch_unwind(|| push(&copied)) {
        Ok(true) => 0,
        _ => 1,
    }
}

#[derive(Deserialize)]
struct Fetch {
    #[serde(default)]
    mirrors: Option<Vec<String>>,
}

#[derive(Deserialize)]
struct Push {
    pcm: String,
}

/// `capture_start`'s arguments, each its dictation's when left out (whisper/stream.rs `Mode`): `partials` false runs no
/// guesses, `keep` false keeps no samples (a meeting whose own service records it; nothing to stop with `recordAs`).
#[derive(Deserialize, Default)]
struct Start {
    #[serde(default)]
    partials: Option<bool>,
    #[serde(default)]
    keep: Option<bool>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Stop {
    #[serde(default)]
    record_as: Option<String>,
    #[serde(default)]
    append: Option<bool>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Reassign {
    from_id: String,
    to_id: String,
    #[serde(default)]
    append: Option<bool>,
}

#[derive(Deserialize)]
struct ById {
    id: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Rewind {
    to_ms: u64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Refine {
    id: String,
    from_ms: u64,
    prompt_tail: String,
}

#[derive(Deserialize)]
struct Wav {
    path: String,
}

fn started(kind: &'static str, work: impl FnOnce(&crate::work::Job) -> Result<Value, String> + Send + 'static) -> Result<Value, String> {
    Ok(json!({ "id": crate::work::start(kind, work)? }))
}

fn said<T: Serialize>(value: T) -> Result<Value, String> {
    serde_json::to_value(value).map_err(|e| format!("the answer could not be written: {e}"))
}

pub fn call(core: &Arc<Core>, command: &str, args: Value) -> Result<Value, String> {
    let models = crate::models::dir(core);
    let recordings = core.data_dir().join(crate::paths::RECORDINGS);
    match command {
        "capture_model_status" => said(crate::model_files::status(&models, &model::ACTIVE)),
        "capture_refine_model_status" => said(crate::model_files::status(&models, &model::REFINE)),
        "capture_fetch_model" | "capture_fetch_refine_model" => {
            let Fetch { mirrors } = read(command, args)?;
            let mirrors = crate::models::mirrors(mirrors, model::mirrors_with);
            let refine = command == "capture_fetch_refine_model";
            started("fetch-model", move |_| {
                let (gate, spec, event) = if refine { (&state().fetching_refine, model::REFINE, "capture://refine-model-progress") } else { (&state().fetching, model::ACTIVE, "capture://model-progress") };
                said::<ModelStatus>(crate::models::fetch_reporting(&models, gate, &spec, &mirrors, event, None)?)
            })
        }
        "capture_start" => {
            let Start { partials, keep } = if args.is_null() { Start::default() } else { read(command, args)? };
            let mode = Mode { partials: partials.unwrap_or(true), keep: keep.unwrap_or(true) };
            started("capture-start", move |_| {
                state().refine_abort.store(true, Ordering::Relaxed);
                // A meeting's write-up in progress stops within a graph computation too: a person who has started
                // talking gets the cores (guards.rs). The capture counts as running from here, before its model loads.
                let _starting = crate::guards::capture_starting();
                crate::guards::abort_with("capturing");
                // A tap an earlier capture left open belongs to the capture this replaces: the meeting that wants one
                // asks again once this has started.
                crate::kept::system_audio::state().stop();
                let engine = engine(&models)?;
                let abort = Arc::new(AtomicBool::new(false));
                let session = Session::new(engine, Arc::clone(&abort))?;
                let capture = Capture::start_with(session, abort, emit, mode);
                let previous = crate::guards::change_capture(&state().capture, |slot| slot.replace(capture));
                if let Some(previous) = previous {
                    previous.cancel();
                }
                // A dictation's answer is null, as it always was; a capture of another mode says which, so the app
                // knows this core took the arguments (one from before ran a dictation and answered null).
                Ok(if mode == Mode::DICTATION { Value::Null } else { json!({ "partials": mode.partials, "keep": mode.keep }) })
            })
        }
        "capture_push" => {
            use base64::Engine as _;
            let Push { pcm } = read(command, args).map_err(|_| "capture_push takes { \"pcm\": base64 } of little-endian f32 PCM".to_string())?;
            let bytes = base64::engine::general_purpose::STANDARD.decode(pcm).map_err(|e| format!("capture_push got pcm that is not valid base64: {e}"))?;
            if bytes.len() % 4 != 0 {
                return Err(format!("capture_push got {} bytes, which is not a whole number of f32 samples", bytes.len()));
            }
            if push(&crate::whisper::f32_samples(&bytes)) {
                Ok(Value::Null)
            } else {
                Err("No capture is running - await capture_start before pushing audio.".to_string())
            }
        }
        "capture_stop" => {
            let Stop { record_as, append } = read(command, args)?;
            // Taken here, in the command: a push or a second stop sent after this one finds no capture.
            let capture = take_capture().ok_or("No capture is running.")?;
            crate::kept::system_audio::state().stop();
            started("capture-stop", move |_| {
                let stopped = capture.stop()?;
                let mut recorded_ms = None;
                if let Some(id) = record_as {
                    if !stopped.recording.is_empty() {
                        let path = crate::recordings::recording_file(&recordings, &id).ok_or("not a note id")?;
                        std::fs::create_dir_all(&recordings).map_err(|e| format!("could not make the recordings folder: {e}"))?;
                        let samples = crate::whisper::wav::write_pcm16(&path, &stopped.recording, append.unwrap_or(false))?;
                        recorded_ms = Some(crate::whisper::samples_to_ms(samples));
                    }
                }
                said(Finished { transcript: stopped.transcript, recorded_ms })
            })
        }
        "capture_reassign_recording" => {
            let Reassign { from_id, to_id, append } = read(command, args)?;
            let from = crate::recordings::recording_file(&recordings, &from_id).ok_or("not a note id")?;
            let to = crate::recordings::recording_file(&recordings, &to_id).ok_or("not a note id")?;
            started("capture-reassign", move |_| {
                let count = crate::whisper::wav::move_or_append(&from, &to, append.unwrap_or(false))?;
                said((count > 0).then_some(crate::whisper::samples_to_ms(count)))
            })
        }
        "capture_discard_recording" => {
            let ById { id } = read(command, args)?;
            let path = crate::recordings::recording_file(&recordings, &id).ok_or("not a note id")?;
            crate::fsx::remove_file_if_present(&path).map_err(|e| format!("could not remove the temporary recording: {e}"))?;
            Ok(Value::Null)
        }
        "capture_rewind" => {
            let Rewind { to_ms } = read(command, args)?;
            // Asked for under the lock, waited for outside it, so pushes and a cancel are never held up.
            let heard = lock(&state().capture).as_ref().ok_or("No capture is running.")?.rewind(to_ms)?;
            started("capture-rewind", move |_| {
                heard.recv_timeout(std::time::Duration::from_secs(15)).map_err(|_| "The capture ended before the rewind could happen.".to_string())?;
                Ok(Value::Null)
            })
        }
        "capture_cancel" => {
            let taken = take_capture();
            crate::kept::system_audio::state().stop();
            started("capture-cancel", move |_| {
                if let Some(capture) = taken {
                    capture.cancel();
                }
                Ok(Value::Null)
            })
        }
        "capture_refine" => {
            let Refine { id, from_ms, prompt_tail } = read(command, args)?;
            if lock(&state().capture).is_some() {
                return Err("busy".into());
            }
            let status = crate::model_files::status(&models, &model::REFINE);
            if !status.present {
                return Err("model missing".into());
            }
            let recording = crate::recordings::recording_file(&recordings, &id).ok_or_else(|| "no such recording".to_string())?;
            if state().refining.swap(true, Ordering::SeqCst) {
                return Err("busy".into());
            }
            let abort = Arc::clone(&state().refine_abort);
            abort.store(false, Ordering::Relaxed);
            let asked = started("refine", move |_| {
                struct Done;
                impl Drop for Done {
                    fn drop(&mut self) {
                        state().refining.store(false, Ordering::SeqCst);
                    }
                }
                let _done = Done;
                let result = refine(&PathBuf::from(&status.path), &recording, &id, from_ms, &prompt_tail, Arc::clone(&abort));
                match result {
                    Err(_) if abort.load(Ordering::Relaxed) => Err("cancelled".into()),
                    Ok(segments) => {
                        crate::events::emit("capture://refine-progress", &RefineProgress { id, percent: 100 });
                        said(segments)
                    }
                    Err(e) => Err(e),
                }
            });
            if asked.is_err() {
                state().refining.store(false, Ordering::SeqCst);
            }
            asked
        }
        "transcribe_wav" => {
            let Wav { path } = read(command, args)?;
            started("transcribe", move |job| {
                use crate::whisper::{samples_to_ms, wav};
                let engine = engine(&models)?;
                let audio = wav::read(Path::new(&path))?;
                let mut session = Session::new(Arc::clone(&engine), job.cancel_flag())?;
                let began = std::time::Instant::now();
                let text = session.transcribe_all(&audio)?;
                said(Transcript { text, audio_ms: samples_to_ms(audio.len()), elapsed_ms: began.elapsed().as_millis() as u64, model: engine.name().to_string() })
            })
        }
        _ => Err(format!("Ghost.md's core has no command named {command}.")),
    }
}

/// One refine pass: capture_commands/refine.rs's blocking closure, as it stands.
fn refine(model_path: &Path, recording: &Path, id: &str, from_ms: u64, prompt_tail: &str, abort: Arc<AtomicBool>) -> Result<Vec<crate::note::RecordedSegment>, String> {
    // The one small.en at a time, held for the pass; a meeting's write-up holding it is "busy", as a second
    // pass is.
    let Some(_write_up) = crate::guards::try_write_up() else {
        return Err("busy".into());
    };
    let audio = crate::whisper::wav::read(recording)?;
    let from = crate::whisper::ms_to_samples(from_ms).min(audio.len());
    if audio.len() - from < crate::whisper::ms_to_samples(100) {
        return Ok(Vec::new());
    }
    let prompt = crate::whisper::text::prompt(prompt_tail, 200);
    let engine = Arc::new(Engine::load(model_path)?);
    let mut session = Session::new(engine, abort)?;
    let progress = AtomicI32::new(0);
    let finished = AtomicBool::new(false);
    // A watcher beside the pass turns whisper.cpp's percentage into events a few times a second; the pass
    // itself never waits on anything.
    std::thread::scope(|scope| {
        scope.spawn(|| {
            let mut last = -1;
            while !finished.load(Ordering::Relaxed) {
                // Clamped: whisper.cpp's last report can pass 100 (whisper/tests.rs says why).
                let percent = progress.load(Ordering::Relaxed).clamp(0, 100);
                if percent != last {
                    last = percent;
                    crate::events::emit("capture://refine-progress", &RefineProgress { id: id.to_string(), percent });
                }
                // In short steps, so the pass's end is not held up to a quarter of a second by its watcher.
                for _ in 0..10 {
                    if finished.load(Ordering::Relaxed) {
                        break;
                    }
                    std::thread::sleep(std::time::Duration::from_millis(25));
                }
            }
        });
        let timed = session.transcribe_timed(&audio[from..], &prompt, &progress);
        finished.store(true, Ordering::Relaxed);
        timed
    })
    // Timed phrases from a pass over `[from_ms, end)`, moved onto the whole recording's timeline.
    .map(|timed| timed.into_iter().map(|t| t.offset(from_ms)).collect())
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::events::tests::{heard, wait_for};
    use crate::test_support::TempDir;
    use std::time::Duration;

    /// A command to the tests' own core, answered as `ghost_invoke` answers: `{"ok": value}` or `{"err": sentence}`.
    /// Not through `ffi::answer`, whose core is the process's one, which dispatch.rs's `init` test owns.
    pub(crate) fn asked(command: &str, args: Value) -> Value {
        let (_, _, core) = core().expect("the web app's models, for the tests' core");
        let args = if args.is_null() { json!({}) } else { args };
        match crate::dispatch::call_on(core, command, args) {
            Ok(value) => json!({ "ok": value }),
            Err(sentence) => json!({ "err": sentence }),
        }
    }

    /// A job's end: its `ok`, or its `err` as an `Err`.
    pub(crate) fn job(command: &str, args: Value, limit: Duration) -> Result<Value, String> {
        let begun = asked(command, args);
        let Some(id) = begun["ok"]["id"].as_str().map(str::to_string) else { return Err(begun["err"].as_str().unwrap_or_else(|| panic!("{command}: {begun}")).to_string()) };
        let wanted = id.clone();
        let end = wait_for(limit, move |event, payload| event == crate::work::END && payload["id"] == wanted.as_str()).unwrap_or_else(|| panic!("{command} never ended"));
        match end.get("err") {
            Some(err) => Err(err.as_str().unwrap().to_string()),
            None => Ok(end["ok"].clone()),
        }
    }

    pub(crate) fn models() -> Option<PathBuf> {
        std::env::var_os("GLYPH_MODELS_DIR").map(PathBuf::from).filter(|dir| dir.is_dir()).map(|dir| dir.canonicalize().unwrap())
    }

    /// The voice tests' core: a data directory of their own, whose `models/` holds links to the web app's model
    /// files, which are only ever read. `None` without the models.
    pub(crate) fn core() -> Option<&'static (TempDir, PathBuf, Arc<Core>)> {
        static CORE: OnceLock<Option<(TempDir, PathBuf, Arc<Core>)>> = OnceLock::new();
        CORE.get_or_init(|| {
            let source = models()?;
            let root = TempDir::new("voice-core");
            let data = root.join("data");
            let kept = data.join("models");
            std::fs::create_dir_all(&kept).unwrap();
            let mut files: Vec<PathBuf> = std::fs::read_dir(&source).unwrap().chain(std::fs::read_dir(source.join("llm")).into_iter().flatten()).filter_map(|e| e.ok()).map(|e| e.path()).filter(|p| p.is_file()).collect();
            files.sort();
            for file in files {
                #[cfg(unix)]
                std::os::unix::fs::symlink(&file, kept.join(file.file_name().unwrap())).unwrap();
            }
            let core = Arc::new(Core::open(&data, &root.join("cache")).expect("the tests' core opens"));
            Some((root, data, core))
        })
        .as_ref()
    }

    /// The fixture's samples as the bytes `capture_push` takes, in 200 ms chunks.
    pub(crate) fn chunks(wav: &Path) -> Vec<String> {
        use base64::Engine as _;
        let audio = crate::whisper::wav::read(wav).unwrap();
        audio.chunks(3200).map(|chunk| base64::engine::general_purpose::STANDARD.encode(chunk.iter().flat_map(|s| s.to_le_bytes()).collect::<Vec<u8>>())).collect()
    }

    #[test]
    fn the_models_say_whether_they_are_here() {
        let Some((_, data, _)) = core() else { return eprintln!("SKIPPED: GLYPH_MODELS_DIR is not a folder") };
        let live = asked("capture_model_status", json!({}));
        assert_eq!(live["ok"], json!({ "present": true, "name": "ggml-base.en-q5_1.bin", "path": data.join("models/ggml-base.en-q5_1.bin"), "bytes": 59_721_011u64 }));
        let refine = asked("capture_refine_model_status", Value::Null);
        assert_eq!((refine["ok"]["name"].as_str(), refine["ok"]["bytes"].as_u64()), (Some("ggml-small.en-q5_1.bin"), Some(190_098_681)));
        // There already: the download answers its status and asks no mirror (this one would refuse).
        let fetched = job("capture_fetch_model", json!({ "mirrors": ["http://127.0.0.1:9"] }), Duration::from_secs(20)).unwrap();
        assert_eq!(fetched, live["ok"]);
    }

    /// A whole dictation: start, the fixture in 200 ms chunks at the pace a microphone gives them (four times
    /// over, to keep the test short), a rewind refused politely once it is over, stop keeping the tape.
    #[test]
    fn a_dictation_is_partials_and_segments_and_a_kept_tape() {
        let _one = lock(&crate::guards::TEST_SERIAL);
        let Some((_, data, _)) = core() else { return eprintln!("SKIPPED: GLYPH_MODELS_DIR is not a folder") };
        let wav = models().unwrap().join("fixture.wav");
        assert_eq!(asked("capture_push", json!({ "pcm": "AAAAAA==" }))["err"], "No capture is running - await capture_start before pushing audio.");
        assert_eq!(asked("capture_stop", json!({}))["err"], "No capture is running.");
        let before = heard(|event, _| event.starts_with("capture://")).len();
        let began = std::time::Instant::now();
        assert_eq!(job("capture_start", json!({}), Duration::from_secs(60)), Ok(Value::Null));
        let loaded_ms = began.elapsed().as_millis();
        assert!(crate::guards::capturing());
        assert_eq!(asked("capture_push", json!({ "pcm": "not base64!" }))["err"].as_str().map(|e| e.starts_with("capture_push got pcm that is not valid base64")), Some(true));
        assert_eq!(asked("capture_push", json!({ "pcm": "AAAAAAA=" }))["err"], "capture_push got 5 bytes, which is not a whole number of f32 samples");
        assert_eq!(asked("capture_refine", json!({ "id": "n1", "fromMs": 0, "promptTail": "" }))["err"], "busy", "no refine while a capture runs");
        let chunks = chunks(&wav);
        for (n, pcm) in chunks.iter().enumerate() {
            // The last second goes through the C door, as the phone's microphone sends it.
            if n + 5 >= chunks.len() {
                use base64::Engine as _;
                let samples = crate::whisper::f32_samples(&base64::engine::general_purpose::STANDARD.decode(pcm).unwrap());
                assert_eq!(unsafe { ghost_capture_push(samples.as_ptr(), samples.len()) }, 0);
            } else {
                assert_eq!(asked("capture_push", json!({ "pcm": pcm })), json!({ "ok": null }));
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        let stopped = job("capture_stop", json!({ "recordAs": "take-1" }), Duration::from_secs(120)).unwrap();
        let transcript = stopped["transcript"].as_str().unwrap();
        let events: Vec<(String, Value)> = heard(|event, _| event.starts_with("capture://")).into_iter().skip(before).collect();
        let partials = events.iter().filter(|(event, payload)| event == "capture://partial" && payload["text"].as_str().is_some_and(|t| !t.is_empty())).count();
        let segments: Vec<&Value> = events.iter().filter(|(event, _)| event == "capture://segment").map(|(_, payload)| payload).collect();
        eprintln!("dictation: started in {loaded_ms} ms, {} chunks, {partials} partials, {} segments, {} ms kept: {transcript}", chunks.len(), segments.len(), stopped["recordedMs"]);
        assert!(transcript.split_whitespace().count() >= 5, "{stopped}");
        assert!(partials >= 1, "the words arrive before they are committed");
        assert!(!segments.is_empty() && segments.iter().all(|s| s["text"].is_string() && s["endMs"].as_u64() >= s["startMs"].as_u64()));
        let audio_ms = crate::whisper::samples_to_ms(crate::whisper::wav::read(&wav).unwrap().len());
        assert_eq!(stopped["recordedMs"].as_u64(), Some(audio_ms), "the tape is everything pushed, by either door");
        assert_eq!(crate::whisper::wav::duration_ms(&data.join("recordings/take-1.wav")).unwrap(), audio_ms);
        assert!(!crate::guards::capturing());
        assert_eq!(unsafe { ghost_capture_push([0f32; 4].as_ptr(), 4) }, 1, "nothing is running now");
        assert_eq!(unsafe { ghost_capture_push(std::ptr::null(), 4) }, 2);
        assert_eq!(asked("capture_rewind", json!({ "toMs": 0 }))["err"], "No capture is running.");

        // The take belongs to a note after all; then a second take is added to that note's tape.
        assert_eq!(job("capture_reassign_recording", json!({ "fromId": "take-1", "toId": "note-1" }), Duration::from_secs(20)), Ok(json!(audio_ms)));
        assert!(!data.join("recordings/take-1.wav").exists());
        std::fs::copy(data.join("recordings/note-1.wav"), data.join("recordings/take-2.wav")).unwrap();
        assert_eq!(job("capture_reassign_recording", json!({ "fromId": "take-2", "toId": "note-1", "append": true }), Duration::from_secs(20)), Ok(json!(crate::whisper::samples_to_ms(2 * crate::whisper::wav::read(&wav).unwrap().len()))));
        assert_eq!(job("capture_reassign_recording", json!({ "fromId": "nothing", "toId": "note-1" }), Duration::from_secs(20)), Ok(Value::Null), "no audio is null");
        assert_eq!(asked("capture_reassign_recording", json!({ "fromId": "../x", "toId": "note-1" }))["err"], "not a note id");

        // The whole file in one pass, with the model already loaded.
        let whole = job("transcribe_wav", json!({ "path": wav }), Duration::from_secs(120)).unwrap();
        eprintln!("transcribe_wav: {} ms of audio in {} ms with {}", whole["audioMs"], whole["elapsedMs"], whole["model"]);
        assert_eq!((whole["audioMs"].as_u64(), whole["model"].as_str()), (Some(audio_ms), Some("ggml-base.en-q5_1.bin")));
        assert!(whole["text"].as_str().unwrap().split_whitespace().count() >= 5);

        // A pass over the kept tape with the bigger model, from its second half.
        let refined = job("capture_refine", json!({ "id": "note-1", "fromMs": audio_ms, "promptTail": transcript }), Duration::from_secs(300)).unwrap();
        let refined = refined.as_array().unwrap();
        eprintln!("refine: {} phrases, first {}", refined.len(), refined.first().unwrap_or(&Value::Null));
        assert!(!refined.is_empty() && refined.iter().all(|s| s["startMs"].as_u64() >= Some(audio_ms)), "times are on the whole tape's timeline");
        let progress = heard(|event, payload| event == "capture://refine-progress" && payload["id"] == "note-1");
        assert_eq!(progress.last().unwrap().1, json!({ "id": "note-1", "percent": 100 }));
        assert_eq!(asked("capture_refine", json!({ "id": "../x", "fromMs": 0, "promptTail": "" }))["err"], "no such recording");

        assert_eq!(asked("capture_discard_recording", json!({ "id": "note-1" })), json!({ "ok": null }));
        assert!(!data.join("recordings/note-1.wav").exists());
        assert_eq!(asked("capture_discard_recording", json!({ "id": "note-1" })), json!({ "ok": null }), "gone already is no error");
    }

    #[test]
    fn a_capture_is_wound_back_and_cancelled_and_a_second_start_replaces_the_first() {
        let _one = lock(&crate::guards::TEST_SERIAL);
        let Some(_) = core() else { return eprintln!("SKIPPED: GLYPH_MODELS_DIR is not a folder") };
        let wav = models().unwrap().join("fixture.wav");
        assert_eq!(job("capture_cancel", json!({}), Duration::from_secs(20)), Ok(Value::Null), "cancelling nothing succeeds");
        job("capture_start", json!({}), Duration::from_secs(60)).unwrap();
        for pcm in chunks(&wav).iter().take(20) {
            assert_eq!(asked("capture_push", json!({ "pcm": pcm })), json!({ "ok": null }));
        }
        let before = heard(|event, _| event == "capture://rewound").len();
        assert_eq!(job("capture_rewind", json!({ "toMs": 1000 }), Duration::from_secs(30)), Ok(Value::Null));
        let rewound = heard(|event, _| event == "capture://rewound");
        assert_eq!(rewound.len(), before + 1, "the event has gone out by the time the rewind resolves");
        assert_eq!(rewound.last().unwrap().1["toMs"], 1000);
        assert!(rewound.last().unwrap().1["segments"].is_array());
        // A start with one running: the old one is cancelled, the new one takes the audio.
        job("capture_start", json!({}), Duration::from_secs(60)).unwrap();
        assert_eq!(asked("capture_push", json!({ "pcm": "AAAAAA==" })), json!({ "ok": null }));
        assert_eq!(job("capture_cancel", json!({}), Duration::from_secs(20)), Ok(Value::Null));
        assert!(!crate::guards::capturing());
        assert_eq!(asked("capture_stop", json!({ "recordAs": "n" }))["err"], "No capture is running.");
    }

    #[test]
    fn a_command_with_the_wrong_arguments_says_which() {
        let Some(_) = core() else { return eprintln!("SKIPPED: GLYPH_MODELS_DIR is not a folder") };
        assert_eq!(asked("capture_push", json!({}))["err"], "capture_push takes { \"pcm\": base64 } of little-endian f32 PCM");
        assert!(asked("capture_rewind", json!({}))["err"].as_str().unwrap().starts_with("invalid args for command `capture_rewind`"));
        assert!(asked("capture_refine", json!({ "id": "n" }))["err"].as_str().unwrap().starts_with("invalid args for command `capture_refine`"));
        assert_eq!(asked("capture_discard_recording", json!({ "id": "a/b" }))["err"], "not a note id");
    }

    /// A meeting's words beside its recording (Matt, 2026-10-30: "If possible add real time transcriptions for
    /// meetings"): `capture_start {partials: false, keep: false}` says it took them, guesses at nothing, keeps no tape.
    #[test]
    fn a_meeting_s_capture_says_its_mode_shows_no_guesses_and_keeps_no_tape() {
        let _one = lock(&crate::guards::TEST_SERIAL);
        let Some(_) = core() else { return eprintln!("SKIPPED: GLYPH_MODELS_DIR is not a folder") };
        let wav = models().unwrap().join("fixture.wav");
        assert_eq!(job("capture_start", json!({ "partials": false, "keep": false }), Duration::from_secs(60)), Ok(json!({ "partials": false, "keep": false })));
        let before = heard(|event, _| event.starts_with("capture://")).len();
        for pcm in chunks(&wav) {
            assert_eq!(asked("capture_push", json!({ "pcm": pcm })), json!({ "ok": null }));
            std::thread::sleep(Duration::from_millis(20));
        }
        let stopped = job("capture_stop", json!({ "recordAs": "meeting-words" }), Duration::from_secs(120)).unwrap();
        let events: Vec<(String, Value)> = heard(|event, _| event.starts_with("capture://")).into_iter().skip(before).collect();
        assert!(!events.iter().any(|(event, payload)| event == "capture://partial" && payload["text"].as_str().is_some_and(|t| !t.is_empty())), "no guesses");
        assert!(events.iter().any(|(event, _)| event == "capture://segment"), "the phrases, each once");
        assert!(stopped["transcript"].as_str().unwrap().split_whitespace().count() >= 5, "{stopped}");
        assert_eq!(stopped["recordedMs"], Value::Null, "no tape: the meeting service keeps the recording");
        // A dictation's start answers as it always did.
        assert_eq!(job("capture_start", json!({}), Duration::from_secs(60)), Ok(Value::Null));
        assert_eq!(job("capture_cancel", json!({}), Duration::from_secs(20)), Ok(Value::Null));
    }

    /// Times each window the real model is handed, by pass.
    struct Timed {
        session: Session,
        spent: [Duration; 2],
        calls: [usize; 2],
        audio: [usize; 2],
    }

    impl crate::whisper::stream::Transcribe for Timed {
        fn transcribe(&mut self, audio: &[f32], prompt: &str, pass: crate::whisper::stream::Pass) -> Result<String, String> {
            let which = usize::from(pass == crate::whisper::stream::Pass::Commit);
            let began = std::time::Instant::now();
            let out = self.session.transcribe(audio, prompt, pass);
            self.spent[which] += began.elapsed();
            self.calls[which] += 1;
            self.audio[which] += audio.len();
            out
        }
    }

    /// What the live words cost a minute of talk, measured with the real model on this machine (the cost the
    /// "Live transcript during meetings" setting is decided on; docs/MEET.md, "Live words on this device"). The
    /// fixture over and over with a second's pause between, fed as fast as the model takes it and ticked every
    /// 250 ms of audio, which is the most a capture ever asks: on a slower machine fewer guesses fit, never more.
    /// Prints the numbers; asserts only that a meeting's words cost a fraction of a dictation's.
    #[test]
    fn what_a_meeting_s_live_words_cost_a_minute_of_talk() {
        let _one = lock(&crate::guards::TEST_SERIAL);
        let Some((_, _, core)) = core() else { return eprintln!("SKIPPED: GLYPH_MODELS_DIR is not a folder") };
        let one = crate::whisper::wav::read(&models().unwrap().join("fixture.wav")).unwrap();
        let minute = 60 * crate::whisper::SAMPLE_RATE;
        let mut audio = Vec::with_capacity(minute);
        while audio.len() < minute {
            audio.extend_from_slice(&one);
            audio.extend(std::iter::repeat_n(0.0f32, crate::whisper::SAMPLE_RATE));
        }
        audio.truncate(minute);
        let engine = engine(&crate::models::dir(core)).unwrap();
        let mut spent = Vec::new();
        for mode in [Mode::DICTATION, Mode::MEETING] {
            let session = Session::new(Arc::clone(&engine), Arc::new(AtomicBool::new(false))).unwrap();
            let mut streamer = crate::whisper::stream::Streamer::with_mode(Timed { session, spent: [Duration::ZERO; 2], calls: [0; 2], audio: [0; 2] }, mode);
            let began = std::time::Instant::now();
            for chunk in audio.chunks(crate::whisper::SAMPLE_RATE / 4) {
                streamer.feed(chunk);
                streamer.tick().unwrap();
            }
            streamer.finish().unwrap();
            let wall = began.elapsed();
            let t = streamer.transcriber();
            let total = t.spent[0] + t.spent[1];
            eprintln!(
                "{}: a minute of talk cost {:.1} s of decoding ({} guesses, {:.1} s; {} phrases, {:.1} s; {:.0} s of audio handed over) in {:.1} s, {} threads",
                if mode == Mode::MEETING { "meeting" } else { "dictation" },
                total.as_secs_f64(),
                t.calls[0],
                t.spent[0].as_secs_f64(),
                t.calls[1],
                t.spent[1].as_secs_f64(),
                (t.audio[0] + t.audio[1]) as f64 / crate::whisper::SAMPLE_RATE as f64,
                wall.as_secs_f64(),
                crate::whisper::engine::whisper_threads(),
            );
            spent.push(total);
        }
        assert!(spent[1] * 2 < spent[0], "a meeting's words cost {:?}, a dictation's {:?}", spent[1], spent[0]);
    }
}
