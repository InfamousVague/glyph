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
//! ONE WORKER FOR BOTH DOORS. The page reaches this through `ai_commands`; a
//! meeting's write-up reaches it over JNI with no Tauri in the process
//! (`write_up.rs`). So the worker is a crate-level `OnceLock` (`shared`),
//! started on the first job from either side, and never two models loaded
//! twice. A foreground job (the page's) is served before any background one
//! waiting in the queue, and one already running is preempted: `generate`
//! raises `guards::abort_with("busy")` before it sends, the write-up's piece
//! ends with `Cancelled`, and the write-up retries later.
//!
//! THE CONTEXT IS SIZED TO THE JOB. A KV cache is allocated for the whole
//! window when a context is made, and 8,192 tokens on a 9B model is over a
//! gigabyte - on a phone, memory the rest of the app and the OS want. So a
//! context is made for what the job needs (prompt plus the most it may
//! write, rounded up), kept for the next job if it fits, and remade when one
//! needs more, or a different number of cores (llama-cpp-2 0.1.156 has no
//! run-time thread setter). The prefix snapshot survives a remake: it is the
//! model's KV data for sequence 0, and it restores into any context of that
//! model with room for it.
//!
//! C++ EXCEPTIONS END THE PROCESS. Rust cannot catch one, and llama.cpp throws
//! from a few places given bad input - so every count is checked in
//! `generate.rs` before it reaches C++.
//!
//! This file is the worker and its handle. One run's prefill and generation
//! are `generate.rs`, when and what it reports is `report.rs`, and the words
//! all three use - a request, its output, its progress, a job - are `job.rs`.

use std::collections::VecDeque;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use llama_cpp_2::llama_backend::LlamaBackend;
use llama_cpp_2::model::params::LlamaModelParams;
use llama_cpp_2::model::LlamaModel;
use llama_cpp_2::LogOptions;

use super::generate::{generate, Kept, Snapshot};
use super::job::{threads, threads_background, Job};
use super::report::{Counts, Reporter};

pub use super::job::{Failure, Output, Phase, Progress, Request, MAX_CONTEXT_TOKENS, MAX_OUTPUT_TOKENS};

/// How long a loaded model waits for another job before it is dropped.
pub const IDLE: Duration = Duration::from_secs(5 * 60);

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

/// The one worker both doors share; see the module header.
static SHARED: OnceLock<Llm> = OnceLock::new();

/// Whether the worker is on a background job now, for the preemption in
/// `Llm::generate`.
static BACKGROUND_RUNNING: AtomicBool = AtomicBool::new(false);

/// The shared worker, started on first use. Nothing is loaded until the first
/// job, so a launch pays nothing for a feature it may not use.
pub fn shared() -> &'static Llm {
    SHARED.get_or_init(Llm::start)
}

/// The shared worker if anything has started it: for an unload or a shutdown,
/// neither of which is worth starting a worker to do.
pub fn started() -> Option<&'static Llm> {
    SHARED.get()
}

/// The cores a job takes: the foreground count, or half of it for a write-up
/// while the app is in front (`guards::background_threads`).
pub fn threads_for(app_in_front: bool) -> i32 {
    if app_in_front {
        threads_background()
    } else {
        threads()
    }
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
    /// returned channel. Progress is delivered from the worker thread. A
    /// foreground request preempts a background job in hand.
    pub fn generate(
        &self,
        model: &Path,
        request: Request,
        cancel: Arc<AtomicBool>,
        progress: impl FnMut(Progress) + Send + 'static,
    ) -> Receiver<Result<Output, Failure>> {
        self.generate_with_threads(model, request, threads(), cancel, progress)
    }

    /// `generate`, with the cores chosen by the caller (`threads_for`).
    pub fn generate_with_threads(
        &self,
        model: &Path,
        request: Request,
        threads: i32,
        cancel: Arc<AtomicBool>,
        progress: impl FnMut(Progress) + Send + 'static,
    ) -> Receiver<Result<Output, Failure>> {
        if !request.background && BACKGROUND_RUNNING.load(Ordering::SeqCst) {
            crate::guards::abort_with("busy");
        }
        let (reply, answer) = mpsc::channel();
        let job = Job {
            model: model.to_path_buf(),
            request,
            cancel,
            progress: Box::new(progress),
            reply,
            threads,
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

/// The next message: everything waiting is drained into `queue` first, and
/// then a `Shutdown` goes before anything, a foreground job before any
/// background one, and otherwise the oldest. With `wait`, at most that long
/// for one to arrive; without, as long as it takes.
fn next_message(inbox: &Receiver<Message>, queue: &mut VecDeque<Message>, wait: Option<Duration>) -> Result<Message, RecvTimeoutError> {
    while let Ok(message) = inbox.try_recv() {
        queue.push_back(message);
    }
    if queue.is_empty() {
        let message = match wait {
            Some(timeout) => inbox.recv_timeout(timeout)?,
            None => inbox.recv().map_err(|_| RecvTimeoutError::Disconnected)?,
        };
        queue.push_back(message);
        while let Ok(message) = inbox.try_recv() {
            queue.push_back(message);
        }
    }
    let pick = queue
        .iter()
        .position(|m| matches!(m, Message::Shutdown))
        .or_else(|| queue.iter().position(|m| matches!(m, Message::Run(job) if !job.request.background)))
        .unwrap_or(0);
    Ok(queue.remove(pick).expect("the queue is not empty"))
}

/// The worker's loop: a model loaded for the job in hand, then kept for every
/// job that names the same file until another file, [`IDLE`], an unload or a
/// shutdown lets it go - the module header's two loops.
fn serve(inbox: Receiver<Message>) {
    let mut queue: VecDeque<Message> = VecDeque::new();
    let mut next: Option<Box<Job>> = None;
    loop {
        let mut job = match next.take() {
            Some(job) => job,
            None => match next_message(&inbox, &mut queue, None) {
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
        let mut ctx: Option<Kept<'_>> = None;
        let mut snapshot: Option<Snapshot> = None;
        let mut current = Some((job, report, started, load_ms));
        loop {
            let (mut job, mut report, started, load_ms) = match current.take() {
                Some(first) => first,
                None => match next_message(&inbox, &mut queue, Some(IDLE)) {
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
            BACKGROUND_RUNNING.store(job.request.background, Ordering::SeqCst);
            let result = generate(backend, &model, &mut ctx, &mut snapshot, &mut job, &mut report, &mut counts, started, load_ms);
            BACKGROUND_RUNNING.store(false, Ordering::SeqCst);
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

#[cfg(test)]
mod tests {
    use super::*;

    fn job(id: &str, background: bool) -> Message {
        let (reply, _answer) = mpsc::channel();
        Message::Run(Box::new(Job {
            model: Path::new("/models/x.gguf").to_path_buf(),
            request: Request {
                id: id.into(),
                system: String::new(),
                context: None,
                prompt: String::new(),
                max_tokens: 1,
                temperature: 0.0,
                think: false,
                think_budget: 0,
                grammar: None,
                background,
            },
            cancel: Arc::default(),
            progress: Box::new(|_| {}),
            reply,
            threads: 2,
        }))
    }

    fn id_of(message: &Message) -> String {
        match message {
            Message::Run(job) => job.request.id.clone(),
            Message::Unload => "unload".into(),
            Message::Shutdown => "shutdown".into(),
        }
    }

    #[test]
    fn a_foreground_job_is_served_before_the_background_ones_waiting_and_a_shutdown_before_all() {
        let (sender, inbox) = mpsc::channel();
        let mut queue = VecDeque::new();
        for message in [job("piece-1", true), job("piece-2", true), job("format", false), job("piece-3", true)] {
            sender.send(message).unwrap();
        }
        let order: Vec<String> = (0..4).map(|_| id_of(&next_message(&inbox, &mut queue, None).unwrap())).collect();
        assert_eq!(order, ["format", "piece-1", "piece-2", "piece-3"]);
        sender.send(job("piece-4", true)).unwrap();
        sender.send(Message::Unload).unwrap();
        sender.send(Message::Shutdown).unwrap();
        assert_eq!(id_of(&next_message(&inbox, &mut queue, Some(Duration::from_millis(10))).unwrap()), "shutdown");
        assert_eq!(id_of(&next_message(&inbox, &mut queue, None).unwrap()), "piece-4");
        assert_eq!(id_of(&next_message(&inbox, &mut queue, None).unwrap()), "unload");
        assert_eq!(next_message(&inbox, &mut queue, Some(Duration::from_millis(10))).err(), Some(RecvTimeoutError::Timeout));
        drop(sender);
        assert_eq!(next_message(&inbox, &mut queue, None).err(), Some(RecvTimeoutError::Disconnected));
    }
}
