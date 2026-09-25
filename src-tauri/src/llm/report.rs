//! What a generation tells the page as it runs: its phase, how far the prompt
//! and the answer have got, the text so far, and the phone under it - at most
//! every [`REPORT_EVERY`], and at every change of phase.

use std::time::{Duration, Instant};

use serde::Serialize;

use super::engine::threads;
use super::hardware::{Hardware, Sampler};

/// Progress is reported at most this often, besides every change of phase.
/// Every report carries the whole text so far and becomes an IPC event and a
/// render; 120 ms is a word or two at a phone's pace.
const REPORT_EVERY: Duration = Duration::from_millis(120);

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

/// The numbers a report carries, kept by the run as it goes.
#[derive(Debug, Clone, Copy, Default)]
pub(super) struct Counts {
    /// Reasoning is on for this run and the stream begins with it.
    pub(super) thinking: bool,
    pub(super) prompt_tokens: u32,
    pub(super) prompt_tokens_done: u32,
    pub(super) output_tokens: u32,
    pub(super) tokens_per_second: f32,
}

/// One job's reporting: when it started, what it last said, and the sampler
/// that reads the phone for each report.
pub(super) struct Reporter {
    id: String,
    started: Instant,
    last: Option<(Phase, Instant)>,
    pub(super) message: Option<String>,
    /// The phone's readings, one per report.
    sampler: Sampler,
}

impl Reporter {
    pub(super) fn new(id: &str, started: Instant) -> Reporter {
        Reporter {
            id: id.to_string(),
            started,
            last: None,
            message: None,
            sampler: Sampler::new(),
        }
    }

    /// Reports unless the same phase was reported under [`REPORT_EVERY`] ago.
    pub(super) fn tick(&mut self, progress: &mut ProgressFn, phase: Phase, counts: Counts, partial: &str) {
        if let Some((last_phase, at)) = self.last {
            if last_phase == phase && at.elapsed() < REPORT_EVERY {
                return;
            }
        }
        self.send(progress, phase, counts, Some(partial.to_string()));
    }

    pub(super) fn send(&mut self, progress: &mut ProgressFn, phase: Phase, counts: Counts, partial: Option<String>) {
        self.last = Some((phase, Instant::now()));
        progress(Progress {
            id: self.id.clone(),
            phase,
            prompt_tokens: counts.prompt_tokens,
            prompt_tokens_done: counts.prompt_tokens_done,
            output_tokens: counts.output_tokens,
            tokens_per_second: counts.tokens_per_second,
            elapsed_ms: self.started.elapsed().as_millis() as u64,
            partial: partial.unwrap_or_default(),
            thinking: counts.thinking,
            message: self.message.clone(),
            hardware: self.sampler.sample(threads() as u32),
        });
    }
}
