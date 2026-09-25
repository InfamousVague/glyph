//! When a generation tells the page how it is going, and what each report
//! carries: its phase, how far the prompt and the answer have got, the text so
//! far, and the phone under it - at most every [`REPORT_EVERY`], and at every
//! change of phase. The report's shape, `Progress`, is `job.rs`.

use std::time::{Duration, Instant};

use super::hardware::Sampler;
use super::job::{threads, Phase, Progress, ProgressFn};

/// Progress is reported at most this often, besides every change of phase.
/// Every report carries the whole text so far and becomes an IPC event and a
/// render; 120 ms is a word or two at a phone's pace.
const REPORT_EVERY: Duration = Duration::from_millis(120);

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
        if self.due(phase, Instant::now()) {
            self.send(progress, phase, counts, Some(partial.to_string()));
        }
    }

    /// Whether a report of `phase` at `now` is news: the first, a change of
    /// phase, or [`REPORT_EVERY`] since the last report.
    fn due(&self, phase: Phase, now: Instant) -> bool {
        match self.last {
            Some((last_phase, at)) => last_phase != phase || now.duration_since(at) >= REPORT_EVERY,
            None => true,
        }
    }

    /// Reports now, whatever was last said: how a run's first word and its end are told.
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    /// A progress callback, and what it was told.
    fn heard() -> (ProgressFn, Arc<Mutex<Vec<Progress>>>) {
        let told = Arc::new(Mutex::new(Vec::new()));
        let into = Arc::clone(&told);
        (Box::new(move |progress| into.lock().unwrap().push(progress)), told)
    }

    fn phases(told: &Mutex<Vec<Progress>>) -> Vec<Phase> {
        told.lock().unwrap().iter().map(|progress| progress.phase).collect()
    }

    #[test]
    fn the_first_report_and_every_change_of_phase_are_told_at_once() {
        let (mut progress, told) = heard();
        let mut report = Reporter::new("job", Instant::now());
        let counts = Counts { prompt_tokens: 40, prompt_tokens_done: 12, ..Counts::default() };
        report.tick(&mut progress, Phase::Prefill, counts, "");
        report.tick(&mut progress, Phase::Generating, counts, "Ship");
        assert_eq!(phases(&told), [Phase::Prefill, Phase::Generating]);
        let last = told.lock().unwrap().pop().unwrap();
        assert_eq!((last.id.as_str(), last.partial.as_str()), ("job", "Ship"), "a report carries the text so far");
        assert_eq!((last.prompt_tokens, last.prompt_tokens_done), (40, 12));
        assert_eq!(last.message, None);
    }

    #[test]
    fn the_same_phase_is_told_again_only_after_the_interval() {
        let mut report = Reporter::new("job", Instant::now());
        let (mut progress, _) = heard();
        report.send(&mut progress, Phase::Generating, Counts::default(), None);
        let (_, at) = report.last.unwrap();
        assert!(!report.due(Phase::Generating, at + Duration::from_millis(50)), "a word or two later is not news");
        assert!(!report.due(Phase::Generating, at + REPORT_EVERY - Duration::from_millis(1)));
        assert!(report.due(Phase::Generating, at + REPORT_EVERY), "the interval itself is");
        assert!(report.due(Phase::Done, at), "a new phase is news at once");
    }

    #[test]
    fn a_sent_report_says_why_it_ended() {
        let (mut progress, told) = heard();
        let mut report = Reporter::new("job", Instant::now());
        report.message = Some("cancelled".into());
        report.send(&mut progress, Phase::Cancelled, Counts::default(), None);
        let last = told.lock().unwrap().pop().unwrap();
        assert_eq!((last.phase, last.message.as_deref(), last.partial.as_str()), (Phase::Cancelled, Some("cancelled"), ""));
    }
}
