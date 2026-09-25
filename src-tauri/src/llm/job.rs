//! What a generation is, in the words the worker, a run and its reports all
//! use: the request the page makes, the output or failure it gets back, the
//! progress reported on the way, the job the worker queues, the limits every
//! count is held to, and the cores a run takes.
//!
//! Kept apart from `engine` so the worker, `generate` and `report` each depend
//! on this and not on one another. `engine` re-exports what callers outside
//! `llm` name, so they still say `llm::engine::Request`.

use std::path::PathBuf;
use std::sync::atomic::AtomicBool;
use std::sync::mpsc::Sender;
use std::sync::Arc;

use serde::Serialize;

use super::hardware::Hardware;

/// The most tokens a context is ever made for. A long note and a long
/// rewrite together; past this the page is told the note is too long.
pub const MAX_CONTEXT_TOKENS: u32 = 8192;

/// The most a caller may ask to generate in one run.
pub const MAX_OUTPUT_TOKENS: u32 = 4096;

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

/// Where a generation is.
#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Phase {
    Loading,
    Prefill,
    Generating,
    Done,
    Error,
    Cancelled,
}

/// One report, as `ai://progress` carries it to the page.
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Progress {
    pub id: String,
    pub phase: Phase,
    pub prompt_tokens: u32,
    pub prompt_tokens_done: u32,
    pub output_tokens: u32,
    pub tokens_per_second: f32,
    pub elapsed_ms: u64,
    /// Everything written so far.
    pub partial: String,
    /// `partial` starts with reasoning (see `Output::thinking`).
    pub thinking: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    /// The phone under the model at this report (hardware.rs); None where it cannot be read.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hardware: Option<Hardware>,
}

/// Where reports go: the page's callback, called on the worker thread.
pub(super) type ProgressFn = Box<dyn FnMut(Progress) + Send>;

/// How many cores generation uses. The emulator has four; the Fold has eight,
/// two of them small. Six keeps off the little cores and leaves one for the
/// page to stay responsive on.
pub(super) fn threads() -> i32 {
    std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4).clamp(2, 6) as i32
}
