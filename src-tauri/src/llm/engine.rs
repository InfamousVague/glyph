//! llama.cpp: one worker thread, one model, generations one at a time.
//!
//! WHY A THREAD OF ITS OWN. A llama.cpp context borrows its model, so the two
//! cannot live side by side in a struct without unsafe code; on a thread's
//! stack they are two locals, and the context is dropped before the model by
//! the language. The thread also keeps a generation - a minute of CPU on a
//! phone - off the async runtime that serves every other command.
//!
//! The loop is two loops. The outer one loads a model for the job in hand; the
//! inner one serves jobs with it until one names a different file, nothing has
//! arrived for [`IDLE`], the app asks for it to be unloaded, or the engine is
//! shut down. Leaving the inner loop drops the context and then the model,
//! which is how gigabytes of mapped weights and a KV cache go back to a phone
//! that has stopped formatting.
//!
//! THE CONTEXT IS SIZED TO THE JOB. A KV cache is allocated for the whole
//! window when a context is made, and 8,192 tokens on a 9B model is over a
//! gigabyte - on a phone, memory the rest of the app and the OS want. So a
//! context is made for what the job needs (prompt plus the most it may
//! write, rounded up), kept for the next job if it fits, and remade when one
//! needs more. The prefix snapshot survives a remake: it is the model's KV
//! data for sequence 0, and it restores into any context of that model with
//! room for it.
//!
//! C++ EXCEPTIONS END THE PROCESS. Rust cannot catch one, and llama.cpp throws
//! from a few places given bad input - so every count is checked here before
//!
//! This file is the worker and its handle; one run's prefill and generation
//! are `generate.rs`, and the progress it reports is `report.rs`.

use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use llama_cpp_2::context::LlamaContext;
use llama_cpp_2::llama_backend::LlamaBackend;
use llama_cpp_2::model::params::LlamaModelParams;
use llama_cpp_2::model::LlamaModel;
use llama_cpp_2::LogOptions;
use serde::Serialize;

use super::generate::{generate, Snapshot};
use super::report::{Counts, ProgressFn, Reporter};

pub use super::report::{Phase, Progress};

/// The most tokens a context is ever made for. A long note and a long
/// rewrite together; past this the page is told the note is too long.
pub const MAX_CONTEXT_TOKENS: u32 = 8192;

/// The most a caller may ask to generate in one run.
pub const MAX_OUTPUT_TOKENS: u32 = 4096;

/// How long a loaded model waits for another job before it is dropped.
pub const IDLE: Duration = Duration::from_secs(5 * 60);

/// One generation, as the page asks for it.
#[derive(Debug, Clone)]
pub struct Request {
    pub id: String,
    pub system: String,
    pub context: Option<String>,
    pub prompt: String,
    pub max_tokens: u32,
    /// 0 is greedy. The page sends 0.3 for a rewrite.
    pub temperature: f32,
    /// Leave reasoning on for a model whose template has it: no empty thought.
    pub think: bool,
    /// Thinking tokens before the thought is closed for the model (0: no limit).
    pub think_budget: u32,
    /// Native-owned constrained output, never accepted from an IPC request.
    pub grammar: Option<&'static str>,
}

/// What one generation wrote, and what it cost.
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Output {
    pub text: String,
    pub prompt_tokens: u32,
    pub output_tokens: u32,
    /// Wall time for the whole run, load included.
    pub ms: u64,
    /// Prompt tokens restored from the prefix snapshot rather than decoded.
    pub cached_tokens: u32,
    pub prefill_ms: u64,
    pub load_ms: u64,
    /// Generation speed alone, tokens a second.
    pub tokens_per_second: f32,
    /// Stopped by `max_tokens` rather than by the model finishing.
    pub truncated: bool,
    /// The text starts with the model's reasoning, up to `</think>`: thinking
    /// was asked for and the model's template has it.
    pub thinking: bool,
}

/// Why a generation ended without its output.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Failure {
    Cancelled,
    Error(String),
}

impl std::fmt::Display for Failure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Failure::Cancelled => f.write_str("cancelled"),
            Failure::Error(message) => f.write_str(message),
        }
    }
}

/// A generation waiting for, or running on, the worker.
pub(super) struct Job {
    pub(super) model: PathBuf,
    pub(super) request: Request,
    pub(super) cancel: Arc<AtomicBool>,
    pub(super) progress: ProgressFn,
    pub(super) reply: Sender<Result<Output, Failure>>,
}

enum Message {
    Run(Box<Job>),
    /// Drop the loaded model now rather than after [`IDLE`]: Settings is
    /// deleting its file, or the app wants the memory back.
    Unload,
    Shutdown,
}

/// The engine: a handle to the worker thread.
pub struct Llm {
    jobs: Sender<Message>,
    thread: Mutex<Option<JoinHandle<()>>>,
}

impl Llm {
    /// Starts the worker. Nothing is loaded until the first job.
    pub fn start() -> Llm {
        let (jobs, inbox) = mpsc::channel();
        let thread = std::thread::Builder::new()
            .name("glyph-llm".into())
            .spawn(move || serve(inbox))
            .expect("the OS starts a thread");
        Llm {
            jobs,
            thread: Mutex::new(Some(thread)),
        }
    }

    /// Queues a generation with the model at `model`, answering on the
    /// returned channel. Progress is delivered from the worker thread.
    pub fn generate(
        &self,
        model: &Path,
        request: Request,
        cancel: Arc<AtomicBool>,
        progress: impl FnMut(Progress) + Send + 'static,
    ) -> Receiver<Result<Output, Failure>> {
        let (reply, answer) = mpsc::channel();
        let job = Job {
            model: model.to_path_buf(),
            request,
            cancel,
            progress: Box::new(progress),
            reply,
        };
        if let Err(mpsc::SendError(Message::Run(job))) = self.jobs.send(Message::Run(Box::new(job))) {
            let _ = job.reply.send(Err(Failure::Error("the formatting engine has stopped".into())));
        }
        answer
    }

    /// Drops the loaded model after the job it is on (cancel that first).
    pub fn unload(&self) {
        let _ = self.jobs.send(Message::Unload);
    }

    /// Stops the worker after the job it is on, and waits for it. Cancel that
    /// job first (its flag) for this to be quick.
    pub fn shutdown(&self) {
        let _ = self.jobs.send(Message::Shutdown);
        let thread = crate::lock::lock(&self.thread).take();
        if let Some(thread) = thread {
            let _ = thread.join();
        }
    }
}

/// llama.cpp's process-wide backend, initialised once and never freed:
/// `LlamaBackend::init` refuses a second call in the same process, and freeing
/// it while whisper shares its ggml would pull buffers from under a capture.
fn backend() -> Result<&'static LlamaBackend, String> {
    static BACKEND: OnceLock<Result<LlamaBackend, String>> = OnceLock::new();
    BACKEND
        .get_or_init(|| {
            // Silence llama.cpp's per-tensor load chatter. Failures still come
            // back as errors, which is where they are read.
            llama_cpp_2::send_logs_to_tracing(LogOptions::default().with_logs_enabled(false));
            LlamaBackend::init().map_err(|e| format!("cannot start llama.cpp: {e}"))
        })
        .as_ref()
        .map_err(Clone::clone)
}

/// How many cores generation uses. The emulator has four; the Fold has eight,
/// two of them small. Six keeps off the little cores and leaves one for the
/// page to stay responsive on.
pub(super) fn threads() -> i32 {
    std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4).clamp(2, 6) as i32
}

/// The worker's loop: a model loaded for the job in hand, then kept for every
/// job that names the same file until another file, [`IDLE`], an unload or a
/// shutdown lets it go - the module header's two loops.
fn serve(inbox: Receiver<Message>) {
    let mut next: Option<Box<Job>> = None;
    loop {
        let mut job = match next.take() {
            Some(job) => job,
            None => match inbox.recv() {
                Ok(Message::Run(job)) => job,
                Ok(Message::Unload) => continue,
                Ok(Message::Shutdown) | Err(_) => return,
            },
        };

        let started = Instant::now();
        let mut report = Reporter::new(&job.request.id, started);
        report.send(&mut job.progress, Phase::Loading, Counts::default(), None);
        let loading = (|| -> Result<(&'static LlamaBackend, LlamaModel), String> {
            let backend = backend()?;
            let params = LlamaModelParams::default().with_n_gpu_layers(0);
            let model = LlamaModel::load_from_file(backend, &job.model, &params)
                .map_err(|e| format!("cannot load the model at {}: {e}", job.model.display()))?;
            Ok((backend, model))
        })();
        let (backend, model) = match loading {
            Ok(pair) => pair,
            Err(message) => {
                fail(*job, &mut report, Failure::Error(message), Counts::default());
                continue;
            }
        };
        let load_ms = started.elapsed().as_millis() as u64;

        let model_path = job.model.clone();
        // The context, made for the first job and remade when one needs more.
        let mut ctx: Option<LlamaContext<'_>> = None;
        let mut snapshot: Option<Snapshot> = None;
        let mut current = Some((job, report, started, load_ms));
        loop {
            let (mut job, mut report, started, load_ms) = match current.take() {
                Some(first) => first,
                None => match inbox.recv_timeout(IDLE) {
                    Ok(Message::Run(job)) if job.model != model_path => {
                        next = Some(job);
                        break;
                    }
                    Ok(Message::Run(job)) => {
                        let started = Instant::now();
                        let report = Reporter::new(&job.request.id, started);
                        (job, report, started, 0)
                    }
                    Ok(Message::Unload) | Err(RecvTimeoutError::Timeout) => break,
                    Ok(Message::Shutdown) | Err(RecvTimeoutError::Disconnected) => return,
                },
            };
            let mut counts = Counts::default();
            let result = generate(backend, &model, &mut ctx, &mut snapshot, &mut job, &mut report, &mut counts, started, load_ms);
            match result {
                Ok(output) => {
                    report.send(&mut job.progress, Phase::Done, counts, Some(output.text.clone()));
                    let _ = job.reply.send(Ok(output));
                }
                Err(failure) => fail(*job, &mut report, failure, counts),
            }
        }
        // `ctx` and then `model` drop here, in reverse order of declaration.
    }
}

/// Ends a job with `failure`: its last report, and its answer.
fn fail(mut job: Job, report: &mut Reporter, failure: Failure, counts: Counts) {
    let phase = if failure == Failure::Cancelled { Phase::Cancelled } else { Phase::Error };
    report.message = Some(failure.to_string());
    report.send(&mut job.progress, phase, counts, None);
    let _ = job.reply.send(Err(failure));
}
