//! The Tauri seam for dictation: its commands and events, and nothing the
//! engine does not already do.
//!
//! `whisper/` owns transcription and has to stay free of `tauri::` types for
//! the reason note.rs gives - an Android capture process could drive it with
//! no Tauri running. This module is the adapter the webview reaches it
//! through: it resolves the app's data directory, holds the loaded model and
//! the one capture in progress in managed state, and turns engine events into
//! `app.emit` calls. Every decision about what to transcribe, when, and what
//! counts as silence is on the other side. The live capture is here; the
//! model downloads are `capture_commands/models.rs` and the pass that improves
//! a saved recording is `capture_commands/refine.rs`.
//!
//! THE CONTRACT WITH THE PAGE, which the page is written against:
//!
//! - `capture_model_status() -> ModelStatus`
//! - `capture_fetch_model() -> ModelStatus`, emitting `capture://model-progress`
//!   `{ receivedBytes, totalBytes }`
//! - `capture_refine_model_status()` and `capture_fetch_refine_model()`, the
//!   same for the refine model, emitting `capture://refine-model-progress`
//! - `capture_refine({ id, fromMs, promptTail }) -> [{ text, startMs, endMs }]`,
//!   emitting `capture://refine-progress { id, percent }`
//! - `capture_start()`, then `capture_push(<raw bytes>)` repeatedly, then
//!   `capture_stop({ recordAs?, append? }) -> { transcript, recordedMs }` or
//!   `capture_cancel()`. With `recordAs` (a note id) the audio is kept: it is
//!   written to `<app_data_dir>/recordings/<id>.wav` - added to the end of that
//!   file when `append` is set - and `recordedMs` is the file's whole length.
//!   Decided at stop, not start, because which note a side-key capture belongs
//!   to is only known a moment after it has begun. Without `recordAs` nothing
//!   is kept and `recordedMs` is null.
//! - `capture_reassign_recording({ fromId, toId, append? }) -> recordedMs`
//!   moves a kept take to the note it turned out to belong to (null when there
//!   was no audio), and `capture_discard_recording({ id })` removes one no note
//!   took.
//! - `http://rec.localhost/<id>.wav` (the `rec` scheme, recordings.rs) serves a
//!   kept recording to an `<audio>` element, byte ranges included, so it can
//!   seek.
//! - `transcribe_wav(path) -> Transcript`
//! - `capture://partial { text }` REPLACES the partial line; an empty `text`
//!   clears it, and one follows every commit whose audio the partial described.
//! - `capture://segment { text, startMs, endMs }` appends.
//! - `capture_rewind(toMs)` winds the tape back: resolves once
//!   `capture://rewound { toMs, segments }` has been emitted, whose `segments`
//!   is every committed segment that still stands - the page REPLACES its list
//!   with it. Chain it after the pushes like one: it applies to the audio
//!   pushed before it, and what is pushed after it records from `toMs`.
//! - `capture://error { message }` means the capture stopped transcribing;
//!   `capture_stop` will then reject with the same message.
//!
//! Two rules the page has to keep, because nothing on this side can:
//!
//! AWAIT EACH `capture_push` BEFORE SENDING THE NEXT. PCM applied out of order
//! is noise, and invoke order is not execution order: on Android, wry hands
//! every IPC request to Rust from WebViewClient.shouldInterceptRequest, which
//! the platform calls off the UI thread, and two invokes in flight together
//! can run in either order whether the command is sync or async. A promise
//! chain costs one round trip per 250 ms of audio.
//!
//! AWAIT `capture_start` BEFORE THE FIRST PUSH. A push with no capture running
//! is rejected rather than buffered, because a buffer that outlives a capture
//! is how the tail of one dictation ends up at the head of the next.
//!
//! On iOS every command exists with the same signature and rejects (or, for the
//! status, answers "not present"): capture there will be Apple's
//! SpeechTranscriber, and a page written against one surface is a page that
//! does not need a platform switch to load.

use serde::Serialize;
use tauri::{AppHandle, Manager, State};

use crate::paths;

#[cfg(target_os = "ios")]
use crate::unsupported::{on_ios, TRANSCRIPTION};

#[cfg(not(target_os = "ios"))]
use std::sync::{atomic::AtomicBool, Arc, Mutex};

// Every value behind these locks is either whole or `None`, so a lock some
// earlier command panicked while holding is recovered, not obeyed: refusing
// every capture for the rest of the process over one panic is how a bug
// becomes a brick. See `crate::lock`.
#[cfg(not(target_os = "ios"))]
use crate::lock::lock;

#[cfg(not(target_os = "ios"))]
use tauri::Emitter;

#[cfg(not(target_os = "ios"))]
use crate::whisper::{
    engine::{Engine, Session},
    model,
    stream::Event,
    worker::Capture,
};

pub mod models;
pub mod refine;

/// What `transcribe_wav` measured.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Transcript {
    pub text: String,
    /// Length of the audio in the file.
    pub audio_ms: u64,
    /// Inference alone - not the WAV read and not the model load, which is
    /// `ModelStatus`'s business and happens once. The number to divide
    /// `audioMs` by for a real-time factor.
    pub elapsed_ms: u64,
    pub model: String,
}

/// The loaded model and the capture in progress, for the life of the process.
///
/// The model is cached here rather than loaded per capture because a load is a
/// read of the whole file - 60 MB from flash on the first press after the page
/// cache has let it go - and a press that waits for that every time is a press
/// that loses the first word. See the benchmark in `whisper/tests.rs`. It is never
/// unloaded. That is ~60 MB of weights kept resident in the app process, which
/// on an 11 GB phone is the right trade against a load on every press, and is
/// the first thing to revisit if the OS starts killing the app in the
/// background.
#[derive(Default)]
pub struct CaptureState {
    #[cfg(not(target_os = "ios"))]
    engine: Mutex<Option<Arc<Engine>>>,
    #[cfg(not(target_os = "ios"))]
    capture: Mutex<Option<Capture>>,
    /// Held across a download so that two taps on "download" are one download:
    /// both would otherwise write the same `.part` file at once.
    #[cfg(not(target_os = "ios"))]
    fetching: tauri::async_runtime::Mutex<()>,
    /// The same, for the refine model's download.
    #[cfg(not(target_os = "ios"))]
    fetching_refine: tauri::async_runtime::Mutex<()>,
    /// Set by `capture_start` so a refine pass in progress stops within one
    /// graph computation: a person who has started talking again gets the CPU.
    #[cfg(not(target_os = "ios"))]
    refine_abort: Arc<AtomicBool>,
    /// Whether a refine pass is running; a second is refused, not queued.
    #[cfg(not(target_os = "ios"))]
    refining: AtomicBool,
}

/// Hands the capture state to Tauri. Called once, from `setup`.
///
/// Opens nothing and touches no file on the way: a first launch with no model
/// must still start, and resolving directories here would make a platform with
/// no data directory fail the whole app over a feature it may never use.
pub fn install(app: &tauri::App) {
    app.manage(CaptureState::default());
}

/// Cancels any capture in progress, waiting for its thread. Called on
/// `RunEvent::Exit`.
///
/// Not tidiness: whisper.cpp is C++ with static state, and a worker thread
/// still inside a decode while `exit()` runs the C++ static destructors is a
/// crash at quit - which on macOS is a crash-report dialog for an app that did
/// nothing wrong. The abort flag ends the decode within one graph computation,
/// so the join is short.
pub fn shutdown(app: &AppHandle) {
    #[cfg(not(target_os = "ios"))]
    if let Some(state) = app.try_state::<CaptureState>() {
        if let Some(capture) = lock(&state.capture).take() {
            capture.cancel();
        }
    }
    #[cfg(target_os = "ios")]
    let _ = app;
}

/// The cached engine, loading it on first use.
///
/// The load runs on the blocking pool: it is a 60 MB file read and tensor
/// setup (31 ms warm on an M5, unmeasured cold on the phone), and on the async
/// runtime it would stall every command queued behind it for that long. Two
/// callers racing here can both load; the second to finish wins the cache and
/// the first's copy is dropped when its capture ends, which is a wasted load
/// in a case that takes two presses inside one load time, and not worth a lock
/// held across an await.
#[cfg(not(target_os = "ios"))]
async fn engine(app: &AppHandle, state: &CaptureState) -> Result<Arc<Engine>, String> {
    if let Some(engine) = lock(&state.engine).clone() {
        return Ok(engine);
    }
    let status = crate::model_files::status(&paths::models_dir(app)?, &model::ACTIVE);
    if !status.present {
        return Err(format!(
            "The transcription model ({}) has not been downloaded yet - call capture_fetch_model first.",
            status.name
        ));
    }
    let path = std::path::PathBuf::from(status.path);
    let engine = tauri::async_runtime::spawn_blocking(move || Engine::load(&path))
        .await
        .map_err(|e| format!("the model load did not finish: {e}"))??;
    let engine = Arc::new(engine);
    *lock(&state.engine) = Some(Arc::clone(&engine));
    Ok(engine)
}

/// One engine event, as the page hears it.
#[cfg(not(target_os = "ios"))]
fn emit(app: &AppHandle, event: Event) {
    // An event the webview is not there to hear (reloading, or closed) is not
    // a failure of the capture.
    let _ = match event {
        Event::Partial(partial) => app.emit("capture://partial", partial),
        Event::Segment(segment) => app.emit("capture://segment", segment),
        Event::Rewound(rewound) => app.emit("capture://rewound", rewound),
        Event::Error(failure) => app.emit("capture://error", failure),
    };
}

/// What `capture_stop` answers with.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Finished {
    pub transcript: String,
    /// The kept recording's whole length, or null when nothing was kept.
    pub recorded_ms: Option<u64>,
}

/// Loads the model if it is not already loaded and starts a capture.
///
/// A capture already running is cancelled, not refused. The case that
/// produces one is a webview that reloaded mid-dictation (a dev reload, or the
/// OS recreating the activity) and so never called stop, and refusing would
/// leave the Record screen unable to record until the app is killed.
#[tauri::command]
pub async fn capture_start(app: AppHandle, state: State<'_, CaptureState>) -> Result<(), String> {
    #[cfg(target_os = "ios")]
    return on_ios(TRANSCRIPTION, (app, state));
    #[cfg(not(target_os = "ios"))]
    {
        state
            .refine_abort
            .store(true, std::sync::atomic::Ordering::Relaxed);
        let engine = engine(&app, &state).await?;
        let abort = Arc::new(AtomicBool::new(false));
        let session = Session::new(engine, Arc::clone(&abort))?;
        let emitter = app.clone();
        let capture = Capture::start(session, abort, move |event| emit(&emitter, event));
        let previous = lock(&state.capture).replace(capture);
        if let Some(previous) = previous {
            // Joined off the async runtime; see `Capture::cancel`.
            tauri::async_runtime::spawn_blocking(move || previous.cancel());
        }
        Ok(())
    }
}

/// Appends audio to the running capture: little-endian `f32` samples, 16 kHz
/// mono. Returns at once; inference never runs here.
///
/// The samples arrive in either of two envelopes, and the second is the one the
/// phone actually uses. Raw bytes (`InvokeBody::Raw`) are the natural shape and
/// work on the desktop. On ANDROID THEY NEVER ARRIVE: Android's WebView gives
/// `shouldInterceptRequest` no access to a request's body, so Tauri carries
/// every payload across the JavaScript bridge as JSON instead, and a
/// `Uint8Array` handed to `invoke` shows up here as a JSON value. The first
/// version accepted only raw bytes, and on the Fold it rejected every chunk -
/// measured with the page's real invoke, 2026-09-12 - which means a held side
/// key would have opened a capture screen that transcribed nothing, ever. So
/// the page sends `{ "pcm": "<base64 of the bytes>" }`, which is the same
/// bytes in a string both bridges carry, and raw bytes stay accepted.
///
/// Sync rather than `async` because the whole of its work is a decode and a
/// lock held for a `Vec::extend` - microseconds - and a hop to the async
/// runtime would cost more than the work. See the module header for the
/// ordering rule the page must keep.
#[tauri::command]
pub fn capture_push(
    request: tauri::ipc::Request<'_>,
    state: State<'_, CaptureState>,
) -> Result<(), String> {
    #[cfg(target_os = "ios")]
    return on_ios(TRANSCRIPTION, (request, state));
    #[cfg(not(target_os = "ios"))]
    {
        use base64::Engine as _;
        let decoded;
        let bytes: &[u8] = match request.body() {
            tauri::ipc::InvokeBody::Raw(bytes) => bytes,
            tauri::ipc::InvokeBody::Json(value) => {
                let Some(pcm) = value.get("pcm").and_then(|pcm| pcm.as_str()) else {
                    return Err(
                        "capture_push takes raw bytes or { \"pcm\": base64 } of little-endian f32 PCM".to_string(),
                    );
                };
                decoded = base64::engine::general_purpose::STANDARD
                    .decode(pcm)
                    .map_err(|e| format!("capture_push got pcm that is not valid base64: {e}"))?;
                &decoded
            }
        };
        if !bytes.len().is_multiple_of(4) {
            return Err(format!(
                "capture_push got {} bytes, which is not a whole number of f32 samples",
                bytes.len()
            ));
        }
        let samples = crate::whisper::f32_samples(bytes);
        match lock(&state.capture).as_ref() {
            Some(capture) => {
                capture.push(&samples);
                Ok(())
            }
            None => {
                Err("No capture is running - await capture_start before pushing audio.".to_string())
            }
        }
    }
}

/// Commits whatever audio remains, waits for that last inference, and answers
/// with the whole committed transcript.
#[tauri::command]
pub async fn capture_stop(
    app: AppHandle,
    state: State<'_, CaptureState>,
    record_as: Option<String>,
    append: Option<bool>,
) -> Result<Finished, String> {
    #[cfg(target_os = "ios")]
    return on_ios(TRANSCRIPTION, (app, state, record_as, append));
    #[cfg(not(target_os = "ios"))]
    {
        let capture = lock(&state.capture)
            .take()
            .ok_or("No capture is running.")?;
        let append = append.unwrap_or(false);
        let stopped = tauri::async_runtime::spawn_blocking(move || capture.stop())
            .await
            .map_err(|e| format!("the capture did not stop cleanly: {e}"))??;

        // The tape, kept beside the note. Written off the async runtime: a
        // minute of audio is two megabytes, and a phone's flash is not fast.
        let mut recorded_ms = None;
        if let Some(id) = record_as {
            if !stopped.recording.is_empty() {
                let dir = paths::recordings_dir(&app)?;
                let path = crate::recordings::recording_file(&dir, &id).ok_or("not a note id")?;
                let recording = stopped.recording;
                let samples = tauri::async_runtime::spawn_blocking(move || {
                    std::fs::create_dir_all(&dir)
                        .map_err(|e| format!("could not make the recordings folder: {e}"))?;
                    crate::whisper::wav::write_pcm16(&path, &recording, append)
                })
                .await
                .map_err(|e| format!("the recording was not written: {e}"))??;
                recorded_ms = Some(crate::whisper::samples_to_ms(samples));
            }
        }
        Ok(Finished {
            transcript: stopped.transcript,
            recorded_ms,
        })
    }
}

/// Move a stopped temporary capture to the note whose mutation was confirmed.
#[tauri::command]
pub async fn capture_reassign_recording(
    app: AppHandle,
    from_id: String,
    to_id: String,
    append: Option<bool>,
) -> Result<Option<u64>, String> {
    #[cfg(target_os = "ios")]
    return on_ios(TRANSCRIPTION, (app, from_id, to_id, append));
    #[cfg(not(target_os = "ios"))]
    {
        let dir = paths::recordings_dir(&app)?;
        let from = crate::recordings::recording_file(&dir, &from_id).ok_or("not a note id")?;
        let to = crate::recordings::recording_file(&dir, &to_id).ok_or("not a note id")?;
        let count = tauri::async_runtime::spawn_blocking(move || {
            crate::whisper::wav::move_or_append(&from, &to, append.unwrap_or(false))
        })
        .await
        .map_err(|e| format!("the recording did not move cleanly: {e}"))??;
        Ok((count > 0).then_some(crate::whisper::samples_to_ms(count)))
    }
}

/// Remove a stopped capture that was rejected or cancelled before it had a note.
#[tauri::command]
pub async fn capture_discard_recording(app: AppHandle, id: String) -> Result<(), String> {
    let dir = paths::recordings_dir(&app)?;
    let path = crate::recordings::recording_file(&dir, &id).ok_or("not a note id")?;
    tauri::async_runtime::spawn_blocking(move || {
        crate::fsx::remove_file_if_present(&path)
            .map_err(|e| format!("could not remove the temporary recording: {e}"))
    })
    .await
    .map_err(|e| format!("the temporary recording did not clean up: {e}"))?
}

/// Winds the running capture back to `to_ms`, so what is pushed next records
/// over everything after it. Resolves once `capture://rewound` has gone out.
#[tauri::command]
pub async fn capture_rewind(state: State<'_, CaptureState>, to_ms: u64) -> Result<(), String> {
    #[cfg(target_os = "ios")]
    return on_ios(TRANSCRIPTION, (state, to_ms));
    #[cfg(not(target_os = "ios"))]
    {
        // Asked for under the lock, waited for outside it, so pushes and a
        // cancel are never held up behind a rewind.
        let heard = lock(&state.capture)
            .as_ref()
            .ok_or("No capture is running.")?
            .rewind(to_ms)?;
        tauri::async_runtime::spawn_blocking(move || {
            heard.recv_timeout(std::time::Duration::from_secs(15))
        })
        .await
        .map_err(|e| format!("the rewind did not finish: {e}"))?
        .map_err(|_| "The capture ended before the rewind could happen.".to_string())
    }
}

/// Ends the capture without committing anything further. Cancelling when
/// nothing is running succeeds: the page wanted no capture, and has none.
#[tauri::command]
pub async fn capture_cancel(state: State<'_, CaptureState>) -> Result<(), String> {
    #[cfg(target_os = "ios")]
    return on_ios(TRANSCRIPTION, state);
    #[cfg(not(target_os = "ios"))]
    {
        let Some(capture) = lock(&state.capture).take() else {
            return Ok(());
        };
        tauri::async_runtime::spawn_blocking(move || capture.cancel())
            .await
            .map_err(|e| format!("the capture did not cancel cleanly: {e}"))
    }
}

/// Transcribes a whole 16 kHz WAV file in one pass, for benchmarking on the
/// device. Uses the cached model, loading it first if it has to.
#[tauri::command]
pub async fn transcribe_wav(
    app: AppHandle,
    state: State<'_, CaptureState>,
    path: String,
) -> Result<Transcript, String> {
    #[cfg(target_os = "ios")]
    return on_ios(TRANSCRIPTION, (app, state, path));
    #[cfg(not(target_os = "ios"))]
    {
        use crate::whisper::{samples_to_ms, wav};
        let engine = engine(&app, &state).await?;
        tauri::async_runtime::spawn_blocking(move || {
            let audio = wav::read(std::path::Path::new(&path))?;
            let mut session = Session::new(Arc::clone(&engine), Arc::new(AtomicBool::new(false)))?;
            let started = std::time::Instant::now();
            let text = session.transcribe_all(&audio)?;
            Ok(Transcript {
                text,
                audio_ms: samples_to_ms(audio.len()),
                elapsed_ms: started.elapsed().as_millis() as u64,
                model: engine.name().to_string(),
            })
        })
        .await
        .map_err(|e| format!("the transcription did not finish: {e}"))?
    }
}
