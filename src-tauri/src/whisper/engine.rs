//! whisper.cpp itself: a loaded model, and the per-capture state that runs
//! inference against it.
//!
//! Two types because they have two lifetimes. An `Engine` is the model's
//! weights: reading and preparing 60 MB of tensors, measured at 28-34 ms for
//! base.en and 84-89 ms for small.en on an M5 with the file already in the page
//! cache - and a phone reading it cold from flash will be slower by however
//! much its storage is. Loaded once and shared, so no press after the first
//! pays for it. A `Session` is whisper.cpp's `whisper_state`: the KV caches
//! and compute buffers one inference at a time runs in, 2-7 ms to create. One per capture, reused for every window of that capture, and never
//! shared between two threads - which is what lets a whole-file benchmark run
//! against the same `Engine` while a capture is live without either corrupting
//! the other.
//!
//! `stream.rs` decides WHAT to transcribe and never sees any of this; a
//! `Session` is simply its `Transcribe`. Everything whisper.cpp-shaped - the
//! params, the prompt tokens, the abort hook, the padding - is here.

use std::ffi::c_void;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::{Arc, Once};
use std::time::{Duration, Instant};

use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters, WhisperState};

use super::stream::{Pass, Transcribe};
use super::{text, SAMPLE_RATE};

/// The shortest window handed to whisper.cpp: one second.
///
/// whisper.cpp refuses input under 100 ms outright ("input is too short") and
/// is unreliable on anything much under a second - the decoder has a 30 s
/// mel window with almost nothing in it. A final "okay." after a pause is
/// exactly that short, so it is padded with silence rather than lost.
const MIN_WINDOW: usize = SAMPLE_RATE;

/// A loaded model, safe to share between threads.
pub struct Engine {
    context: WhisperContext,
    name: String,
    threads: i32,
    loaded_in: Duration,
}

impl Engine {
    /// Loads the model file at `path`.
    ///
    /// whisper.cpp's own logging is switched off first, once per process. It
    /// writes a page of tensor names to stderr on every load, which on Android
    /// goes nowhere and in `cargo test` buries the one line that failed. The
    /// numbers worth keeping from it - how long the load took - are measured
    /// here instead and kept on the `Engine`.
    ///
    /// Threads are `min(4, cores)`, which is whisper.cpp's own default. On an
    /// eight-core phone it leaves half the cores for the things that must not
    /// stutter while a window decodes: the webview, and the audio capture that
    /// is feeding this in the first place.
    pub fn load(path: &Path) -> Result<Engine, String> {
        static QUIET: Once = Once::new();
        QUIET.call_once(whisper_rs::install_logging_hooks);

        let started = Instant::now();
        // No GPU: there is none this build knows how to use on the phone, and
        // on the Mac the benchmark should measure the CPU path the phone runs.
        let mut parameters = WhisperContextParameters::default();
        parameters.use_gpu(false);
        let context = WhisperContext::new_with_params(path, parameters)
            .map_err(|e| format!("cannot load the model at {}: {e}", path.display()))?;
        let threads = std::thread::available_parallelism()
            .map(|n| n.get())
            .unwrap_or(4)
            .min(4) as i32;
        let name = path
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        Ok(Engine {
            context,
            name,
            threads,
            loaded_in: started.elapsed(),
        })
    }

    /// The model's file name.
    pub fn name(&self) -> &str {
        &self.name
    }

    /// How long `load` took.
    pub fn loaded_in(&self) -> Duration {
        self.loaded_in
    }
}

/// One capture's inference state against a shared `Engine`.
pub struct Session {
    engine: Arc<Engine>,
    state: WhisperState,
    abort: Arc<AtomicBool>,
}

/// whisper.cpp's abort hook: polled between graph computations, and a `true`
/// ends the inference early with an error.
///
/// SAFETY: `data` is the `AtomicBool` inside `Session::abort`, which the
/// session keeps alive for as long as a `full` call can be running, since
/// `full` borrows the session mutably for its whole duration.
unsafe extern "C" fn should_abort(data: *mut c_void) -> bool {
    (*(data as *const AtomicBool)).load(Ordering::Relaxed)
}

/// whisper.cpp's progress hook: a percentage, stored for whoever is watching.
///
/// SAFETY: `user_data` is the `AtomicI32` passed to `transcribe_timed`, which
/// the caller keeps borrowed for the whole `full` call.
unsafe extern "C" fn on_progress(
    _ctx: *mut whisper_rs_sys::whisper_context,
    _state: *mut whisper_rs_sys::whisper_state,
    progress: std::os::raw::c_int,
    user_data: *mut c_void,
) {
    (*(user_data as *const AtomicI32)).store(progress, Ordering::Relaxed);
}

/// One phrase whisper found, with its place in the audio it was given.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TimedText {
    pub text: String,
    pub start_ms: u64,
    pub end_ms: u64,
}

impl Session {
    /// A fresh `whisper_state` for `engine`. Setting `abort` from any thread
    /// ends the inference in progress within one graph computation.
    pub fn new(engine: Arc<Engine>, abort: Arc<AtomicBool>) -> Result<Session, String> {
        let state = engine
            .context
            .create_state()
            .map_err(|e| format!("cannot create whisper state: {e}"))?;
        Ok(Session { engine, state, abort })
    }

    /// Whole-file transcription, for `transcribe_wav` and the benchmark: one
    /// `full` call over everything, with whisper.cpp doing its own 30 s seeking,
    /// and the result through the same non-speech scrub as a capture.
    pub fn transcribe_all(&mut self, audio: &[f32]) -> Result<String, String> {
        let raw = self.transcribe(audio, "", Pass::Commit)?;
        Ok(text::clean(&raw))
    }

    /// The phrases of `audio` with their times, for the pass that improves a
    /// saved recording: one `full` call with a commit's parameters, whisper.cpp
    /// seeking through it 30 s at a time, and each of its segments scrubbed the
    /// way a committed one is (`text::clean`, then the echo guard), empty ones
    /// dropped. Times are milliseconds from the start of `audio`, clamped to
    /// its length - whisper's last timestamp can land past the final sample.
    /// `progress` receives whisper.cpp's percentage as the call runs.
    pub fn transcribe_timed(&mut self, audio: &[f32], prompt: &str, progress: &AtomicI32) -> Result<Vec<TimedText>, String> {
        let length_ms = (audio.len() as u64 * 1000) / SAMPLE_RATE as u64;
        self.run(audio, prompt, Pass::Commit, Some(progress))?;
        let mut out = Vec::new();
        for segment in self.state.as_iter() {
            let piece = segment
                .to_str_lossy()
                .map_err(|e| format!("whisper returned no text: {e}"))?;
            let words = text::without_prompt_echo(&text::clean(&piece));
            if words.is_empty() {
                continue;
            }
            // Centiseconds, and never negative in practice; clamp anyway.
            let start_ms = (segment.start_timestamp().max(0) as u64 * 10).min(length_ms);
            let end_ms = (segment.end_timestamp().max(0) as u64 * 10).clamp(start_ms, length_ms);
            out.push(TimedText { text: words, start_ms, end_ms });
        }
        Ok(out)
    }
}

impl Transcribe for Session {
    /// Runs whisper.cpp over one window.
    ///
    /// The parameters, and why each is what it is:
    ///
    /// - Greedy, `best_of` 1. Beam search is several decoders at once; on a
    ///   phone CPU that is the difference between a partial every second and a
    ///   partial every few.
    /// - `no_context`. This state is REUSED for every window of a capture, and
    ///   whisper.cpp otherwise carries the previous call's text forward as
    ///   context - which here would be a stale partial of audio that has since
    ///   been committed, or re-guessed. The continuity that context is for comes
    ///   from the prompt instead, which is only ever COMMITTED text.
    /// - The prompt goes in as TOKENS (`set_tokens`), not `set_initial_prompt`.
    ///   whisper.cpp tokenises an initial prompt into exactly these tokens
    ///   itself (whisper_full_with_state, "tokenize the initial prompt"), so the
    ///   model sees the same thing - but whisper-rs 0.16's `set_initial_prompt`
    ///   hands whisper.cpp a `CString::into_raw` that nothing ever frees, and
    ///   this runs every 700 ms for as long as somebody is talking.
    /// - No `set_language`. whisper.cpp's default params already say "en"
    ///   (whisper_full_default_params), and whisper-rs's setter leaks a
    ///   `CString` per call the same way.
    /// - `suppress_blank` and `suppress_nst`: no leading blank, and no
    ///   non-speech tokens - the `[BLANK_AUDIO]` family, at the decoder, before
    ///   `text::clean` has to catch them.
    /// - Partials only: `no_timestamps`, and no temperature fallback. Timestamp
    ///   tokens are decoder steps a guess does not need, and a fallback re-runs
    ///   the whole decode at a higher temperature when the first pass looks
    ///   uncertain - which on a half-finished phrase it usually does, and which
    ///   would turn one inference into up to six. A commit keeps both, because
    ///   that text stands.
    ///
    /// And one that is deliberately NOT set, because it is the obvious next
    /// speed-up and it was measured: `audio_ctx`. whisper.cpp pads every window
    /// to 30 s and encodes all 1500 frames of it, so a 2 s partial costs the
    /// same encoder time as a 28 s one - on an M5, ~270 ms per inference whatever
    /// the window. Sizing the encoder to the window (frames = ms / 20, plus 64)
    /// cut that to ~100 ms for partials and ~65 ms for commits on the fixture,
    /// with the final transcript unchanged. It also produced, in 2 of 15
    /// partials, whisper's repetition loop - "Then, then, then, then, ..." to
    /// the token limit, and one sentence repeated twenty times - each taking
    /// 500 ms to generate. A loop on the partial line is garbage flashed at the
    /// person dictating; the same loop in a commit is garbage in their note.
    /// If the phone proves too slow without it, the way in is `audio_ctx` for
    /// partials only, behind a repetition check that retries at full context -
    /// not this parameter on its own.
    fn transcribe(&mut self, audio: &[f32], prompt: &str, pass: Pass) -> Result<String, String> {
        self.run(audio, prompt, pass, None)?;
        let mut out = String::new();
        for segment in self.state.as_iter() {
            let piece = segment
                .to_str_lossy()
                .map_err(|e| format!("whisper returned no text: {e}"))?;
            out.push_str(&piece);
        }
        Ok(out)
    }
}

impl Session {
    /// One `full` call over `audio` with the parameters `transcribe` documents,
    /// leaving the result in the state for the caller to read.
    fn run(&mut self, audio: &[f32], prompt: &str, pass: Pass, progress: Option<&AtomicI32>) -> Result<(), String> {
        let padded;
        let audio = if audio.len() < MIN_WINDOW {
            let mut with_quiet = audio.to_vec();
            with_quiet.resize(MIN_WINDOW, 0.0);
            padded = with_quiet;
            &padded[..]
        } else {
            audio
        };

        // A byte-level BPE never makes more tokens than there are bytes, so a
        // buffer the length of the prompt can never be too small. That matters
        // beyond tidiness: whisper.cpp answers a too-small buffer with MINUS the
        // count it needed, and whisper-rs 0.16 only treats -1 as an error - any
        // other negative goes straight into `Vec::set_len`. A prompt that
        // cannot tokenise is dropped, not fatal: the window is still worth
        // transcribing without it.
        let tokens = if prompt.is_empty() {
            Vec::new()
        } else {
            self.engine
                .context
                .tokenize(prompt, prompt.len() + 1)
                .unwrap_or_default()
        };

        let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
        params.set_n_threads(self.engine.threads);
        params.set_translate(false);
        params.set_no_context(true);
        params.set_suppress_blank(true);
        params.set_suppress_nst(true);
        params.set_print_special(false);
        params.set_print_progress(false);
        params.set_print_realtime(false);
        params.set_print_timestamps(false);
        params.set_tokens(&tokens);
        if pass == Pass::Partial {
            params.set_no_timestamps(true);
            params.set_temperature_inc(0.0);
        }
        // SAFETY: see `should_abort`. The raw hook rather than
        // `set_abort_callback_safe`, which boxes its closure with
        // `Box::into_raw` on every call and never frees it.
        unsafe {
            params.set_abort_callback(Some(should_abort));
            params.set_abort_callback_user_data(Arc::as_ptr(&self.abort) as *mut c_void);
            // SAFETY: see `on_progress`; `progress` outlives this call.
            if let Some(progress) = progress {
                params.set_progress_callback(Some(on_progress));
                params.set_progress_callback_user_data(progress as *const AtomicI32 as *mut c_void);
            }
        }

        self.state
            .full(params, audio)
            .map_err(|e| format!("whisper could not transcribe: {e}"))?;
        Ok(())
    }
}
