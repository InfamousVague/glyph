//! Live dictation as a state machine: samples in, partial and committed text
//! out, and no threads, no clock and no model in sight.
//!
//! `worker.rs` owns the thread and the timer, `engine.rs` owns whisper.cpp,
//! and the page owns what the words look like. This module owns every DECISION
//! in between: when a window is worth transcribing, when a phrase is finished,
//! where to cut it, and what the person is shown in the meantime. Those are the
//! parts that are easy to get subtly wrong and impossible to see going wrong on
//! a phone, so they live where a test can drive them one 250 ms chunk at a
//! time and get the same events every run.
//!
//! The shape is whisper.cpp's `stream` example - re-transcribe the uncommitted
//! audio every so often and show it as a guess; commit it when the speaker
//! pauses - with one change that is the reason this is a state machine at all.
//! In the example, and in the brief this was written from, "is there a pause?"
//! is asked of the trailing 600 ms at the moment the timer fires. That makes
//! the transcript depend on WHEN the timer fired: an inference that runs long
//! on a busy phone lets two seconds of audio pile up, a pause in the middle of
//! them is never trailing when anyone looks, and the phrase either side of it
//! is committed as one. Here every 20 ms frame is classified as it is FED, a
//! pause is recorded as a cut at the moment it happens in the audio, and `tick`
//! commits whatever cuts are waiting. Commits are a function of the audio
//! alone. Only partials depend on timing, and a partial is a guess by
//! definition.
//!
//! The rules, each with its constant below:
//!
//! - A PAUSE of 600 ms after at least 1.5 s of speech cuts a phrase. So does a
//!   pause of 1.2 s after any speech at all, so that "buy milk", said and then
//!   left alone, is committed rather than re-transcribed until the 20 s cap.
//! - The cut goes in the MIDDLE of the pause, not at its end: the committed
//!   window keeps 300 ms of trailing quiet (a soft final consonant below the
//!   threshold stays with its word) and the next window starts with 300 ms of
//!   lead-in.
//! - Twenty seconds without a pause forces a cut, at the quietest 200 ms of the
//!   last four. Whisper's window is 30 s and a window near it is slow to
//!   decode, and the quietest moment is the least likely to be inside a word.
//! - Audio with no speech in it is dropped after two seconds, keeping 300 ms,
//!   and is NEVER sent to the model. Whisper hallucinates on silence, and the
//!   only reliable defence is not asking.
//! - A partial runs when at least 1 s of uncommitted audio holds speech, 700 ms
//!   of new audio has arrived since the last one, and some of that new audio
//!   was speech. The last condition is what stops a speaker who has gone quiet
//!   from costing an inference every 700 ms to learn nothing new.
//! - Committed text only changes by REWIND. The person can wind the tape back
//!   to any moment and talk over it: every segment that ends after that moment
//!   is dropped, the audio between the last kept segment and the moment is
//!   transcribed again, and what is said next continues from there. So the
//!   whole recording is kept (as 16-bit PCM, ~1.9 MB a minute), not just the
//!   uncommitted window - without it there is nothing to re-transcribe.

//!
//! What the streamer says - its events, and the one trait a transcriber has
//! to implement - is `stream/events.rs`; its tests are `stream/tests.rs`.

use std::collections::VecDeque;

use super::vad::{self, Vad, FRAME};
use super::{ms_to_samples, samples_to_ms, text};

mod events;
#[cfg(test)]
mod tests;

pub use events::{Event, Failure, Partial, Pass, Rewound, Segment, Transcribe};

/// A phrase is finished when this much quiet follows it...
const PAUSE: usize = ms_to_samples(600);
/// ...provided at least this much speech came before the quiet.
const MIN_SPEECH: usize = ms_to_samples(1_500);
/// Quiet this long finishes ANY phrase, however short.
const LONG_PAUSE: usize = ms_to_samples(1_200);
/// Uncommitted audio never grows past this without a cut.
const FORCE_COMMIT: usize = ms_to_samples(20_000);
/// How far back from the force point to look for somewhere quiet to cut.
const FORCE_SEARCH: usize = ms_to_samples(4_000);
/// The quiet stretch a forced cut is centred in.
const FORCE_QUIET: usize = ms_to_samples(200);
/// Audio with no speech in it is dropped once it reaches this...
const SILENCE_DROP: usize = ms_to_samples(2_000);
/// ...keeping this much, as lead-in for whatever is said next.
const SILENCE_KEEP: usize = ms_to_samples(300);
/// The least uncommitted audio a partial is run on.
const PARTIAL_MIN: usize = ms_to_samples(1_000);
/// New audio between one partial and the next.
const PARTIAL_STEP: usize = ms_to_samples(700);
/// The longest window ever handed to the model: whisper's 30 s, less margin.
const WINDOW_CAP: usize = ms_to_samples(28_000);
/// How much committed text rides along as the prompt, after the cue
/// vocabulary. See `text::prompt`.
const PROMPT_CHARS: usize = 200;
/// Consecutive voiced frames before the VAD's opinion counts as speech: 40 ms.
/// One loud frame is a click, a tap on the glass, a key; no syllable is that
/// short.
const ONSET_FRAMES: usize = 2;

/// A committed segment and the exact sample its audio ends on. `Segment`'s
/// times are rounded to milliseconds; a rewind has to cut on the sample.
#[derive(Debug, Clone)]
struct Committed {
    segment: Segment,
    end: usize,
}

/// A decided cut: everything before `at` (an absolute sample index) is a
/// finished window. `speech` is false for a window that is only being dropped.
#[derive(Debug, Clone, Copy)]
struct Cut {
    at: usize,
    speech: bool,
}

/// One capture's worth of state. Create one per press of the side key.
pub struct Streamer<T: Transcribe> {
    transcriber: T,
    vad: Vad,

    /// The uncommitted audio. `audio[0]` is absolute sample `base`.
    audio: Vec<f32>,
    /// Per-frame RMS for every classified frame of `audio`, for finding the
    /// quietest place to force a cut.
    energy: Vec<f32>,
    base: usize,

    /// Absolute sample index up to which frames have been classified. Always
    /// a whole number of frames.
    classified: usize,
    /// Where the window being accumulated by the VAD starts: `base`, or the
    /// last cut decided but not yet committed.
    span_start: usize,
    /// Start of the first speech in that window, if there has been any.
    first_speech: Option<usize>,
    /// End of the most recent speech frame.
    last_speech_end: usize,
    voiced_streak: usize,
    quiet_run: usize,
    cuts: VecDeque<Cut>,

    /// End of the audio the last partial covered.
    partial_end: usize,
    /// Whether speech has been classified since that partial ran.
    speech_since_partial: bool,
    /// Whether the page is currently showing non-empty partial text.
    showing_partial: bool,

    committed: Vec<Committed>,
    /// Every sample fed since the capture began, sample 0 first, as 16-bit PCM.
    recording: Vec<i16>,
}

impl<T: Transcribe> Streamer<T> {
    pub fn new(transcriber: T) -> Streamer<T> {
        Streamer {
            transcriber,
            vad: Vad::new(),
            audio: Vec::new(),
            energy: Vec::new(),
            base: 0,
            classified: 0,
            span_start: 0,
            first_speech: None,
            last_speech_end: 0,
            voiced_streak: 0,
            quiet_run: 0,
            cuts: VecDeque::new(),
            partial_end: 0,
            speech_since_partial: false,
            showing_partial: false,
            committed: Vec::new(),
            recording: Vec::new(),
        }
    }

    /// Appends audio and classifies every whole frame of it. Never transcribes.
    ///
    /// This is where pauses are found and cuts are decided - see the module
    /// header for why that happens here and not in `tick`.
    pub fn feed(&mut self, samples: &[f32]) {
        self.recording.extend(samples.iter().map(|&s| to_pcm(s)));
        self.take_in(samples);
    }

    /// Adds audio to the uncommitted window and classifies it, without
    /// recording it: `feed` for new audio, and a rewind for audio re-heard.
    fn take_in(&mut self, samples: &[f32]) {
        self.audio.extend_from_slice(samples);
        let end = self.base + self.audio.len();
        while self.classified + FRAME <= end {
            let from = self.classified - self.base;
            let (voiced, rms) = self.vad.frame(&self.audio[from..from + FRAME]);
            self.energy.push(rms);
            let frame_start = self.classified;
            self.classified += FRAME;
            self.classify(frame_start, voiced);
        }
    }

    fn classify(&mut self, frame_start: usize, voiced: bool) {
        self.voiced_streak = if voiced { self.voiced_streak + 1 } else { 0 };
        if self.voiced_streak >= ONSET_FRAMES {
            if self.first_speech.is_none() {
                // The onset began with the first frame of the streak, which
                // was provisionally counted as quiet.
                let onset = frame_start - (ONSET_FRAMES - 1) * FRAME;
                self.first_speech = Some(onset.max(self.span_start));
            }
            self.last_speech_end = self.classified;
            self.quiet_run = 0;
            self.speech_since_partial = true;
        } else {
            self.quiet_run += FRAME;
        }

        let now = self.classified;
        match self.first_speech {
            Some(first) => {
                let speech = self.last_speech_end - first;
                let paused = (self.quiet_run >= PAUSE && speech >= MIN_SPEECH)
                    || self.quiet_run >= LONG_PAUSE;
                if paused {
                    self.decide(self.last_speech_end + PAUSE / 2, true);
                } else if now - self.span_start >= FORCE_COMMIT {
                    let at = self.quietest_cut(now);
                    self.decide(at, true);
                    // Speech after the forced cut starts the next window's
                    // count; the cut is mid-speech by definition.
                    if self.last_speech_end > at {
                        self.first_speech = Some(at);
                    }
                }
            }
            None if now - self.span_start >= SILENCE_DROP => {
                self.decide(now - SILENCE_KEEP, false);
            }
            None => {}
        }
    }

    fn decide(&mut self, at: usize, speech: bool) {
        self.cuts.push_back(Cut { at, speech });
        self.span_start = at;
        self.first_speech = None;
    }

    /// The middle of the quietest `FORCE_QUIET` in the last `FORCE_SEARCH`
    /// before `now`, on a frame boundary.
    fn quietest_cut(&self, now: usize) -> usize {
        let window = FORCE_QUIET / FRAME;
        let first_frame = (now - FORCE_SEARCH - self.base) / FRAME;
        let last_frame = (now - self.base) / FRAME - window;
        let mut best = (f32::INFINITY, first_frame);
        let mut sum: f32 = self.energy[first_frame..first_frame + window].iter().sum();
        for start in first_frame..=last_frame {
            if start > first_frame {
                sum += self.energy[start + window - 1] - self.energy[start - 1];
            }
            if sum < best.0 {
                best = (sum, start);
            }
        }
        self.base + (best.1 + window / 2) * FRAME
    }

    /// Does whatever inference is due: every decided cut is committed, then a
    /// partial if one is warranted. Returns the events in the order the page
    /// should apply them.
    ///
    /// Cheap when nothing is due, so the worker can call it on a short timer.
    /// When it is not cheap it is exactly one inference per decided cut plus
    /// at most one partial, and it does not return until they are done.
    pub fn tick(&mut self) -> Result<Vec<Event>, String> {
        let mut events = Vec::new();
        let committed_any = self.commit_decided(&mut events)?;
        let partial_ran = self.maybe_partial(&mut events)?;
        if committed_any && !partial_ran {
            self.clear_partial(&mut events);
        }
        Ok(events)
    }

    /// Commits everything left, including the audio after the last cut, and
    /// clears the partial. What a press of Stop runs.
    ///
    /// The final window is transcribed only if it holds speech - the silence
    /// rule does not relax because the person has stopped talking.
    pub fn finish(&mut self) -> Result<Vec<Event>, String> {
        let mut events = Vec::new();
        self.commit_decided(&mut events)?;
        let end = self.base + self.audio.len();
        if end > self.base {
            let speech = self.first_speech.is_some();
            self.commit(Cut { at: end, speech }, &mut events)?;
        }
        self.clear_partial(&mut events);
        Ok(events)
    }

    /// Everything committed so far, as one string.
    pub fn transcript(&self) -> String {
        self.committed
            .iter()
            .map(|c| c.segment.text.as_str())
            .collect::<Vec<_>>()
            .join(" ")
    }

    /// Winds the tape back to `to_ms` so what is said next records over what
    /// came after it.
    ///
    /// Segments are dropped WHOLE: one that ends after the moment is gone, and
    /// the audio from the last segment that stands up to the moment goes back
    /// into the uncommitted window, to be transcribed again as the start of
    /// whatever is said next. Cutting a segment's text mid-way would mean
    /// guessing which words were said before the moment, and whisper's word
    /// times are not good enough to guess with.
    ///
    /// The window state is rebuilt at that segment's end, as though the
    /// capture had just committed it, and the VAD is primed with the few
    /// seconds before it so its noise floor matches the room rather than
    /// starting from nothing. A moment past the end of the recording is the end
    /// of the recording. Never transcribes.
    pub fn rewind(&mut self, to_ms: u64) -> Vec<Event> {
        let mut events = Vec::new();
        let to = ms_to_samples(to_ms).min(self.recording.len()) / FRAME * FRAME;
        let kept = self.committed.iter().take_while(|c| c.end <= to).count();
        self.committed.truncate(kept);
        let from = self.committed.last().map_or(0, |c| c.end);
        self.recording.truncate(to);
        self.clear_partial(&mut events);

        self.vad = Vad::new();
        let prime_from = from.saturating_sub(vad::MEMORY) / FRAME * FRAME;
        self.vad.prime(&from_pcm(&self.recording[prime_from..from]));
        self.audio.clear();
        self.energy.clear();
        self.base = from;
        self.classified = from;
        self.span_start = from;
        self.first_speech = None;
        self.last_speech_end = from;
        self.voiced_streak = 0;
        self.quiet_run = 0;
        self.cuts.clear();
        self.partial_end = from;
        self.speech_since_partial = false;
        let again = from_pcm(&self.recording[from..to]);
        self.take_in(&again);

        events.push(Event::Rewound(Rewound {
            to_ms: samples_to_ms(to),
            segments: self.committed.iter().map(|c| c.segment.clone()).collect(),
        }));
        events
    }

    /// Milliseconds of audio recorded, on the timeline segment times use.
    pub fn recorded_ms(&self) -> u64 {
        samples_to_ms(self.recording.len())
    }

    /// The whole recording, 16 kHz mono 16-bit, leaving none behind. What a
    /// finished capture keeps as the note's tape.
    pub fn take_recording(&mut self) -> Vec<i16> {
        std::mem::take(&mut self.recording)
    }

    fn commit_decided(&mut self, events: &mut Vec<Event>) -> Result<bool, String> {
        let mut any = false;
        while let Some(cut) = self.cuts.pop_front() {
            if let Err(e) = self.commit(cut, events) {
                // Put it back: a transient failure must not silently drop a
                // phrase, and the worker decides whether there is a retry.
                self.cuts.push_front(cut);
                return Err(e);
            }
            any = true;
        }
        Ok(any)
    }

    fn commit(&mut self, cut: Cut, events: &mut Vec<Event>) -> Result<(), String> {
        let len = cut.at - self.base;
        if cut.speech {
            let prompt = text::prompt(&self.transcript(), PROMPT_CHARS);
            let window = &self.audio[..len.min(WINDOW_CAP)];
            let raw = self.transcriber.transcribe(window, &prompt, Pass::Commit)?;
            let words = text::without_prompt_echo(&text::clean(&raw));
            if !words.is_empty() {
                let segment = Segment {
                    text: words,
                    start_ms: samples_to_ms(self.base),
                    end_ms: samples_to_ms(cut.at),
                };
                events.push(Event::Segment(segment.clone()));
                self.committed.push(Committed { segment, end: cut.at });
            }
        }
        self.audio.drain(..len);
        self.energy.drain(..(len / FRAME).min(self.energy.len()));
        self.base = cut.at;
        if self.span_start < self.base {
            self.span_start = self.base;
        }
        // The next partial is due as soon as there is anything to guess at:
        // the one on screen described audio that has just been committed.
        self.partial_end = self.base;
        self.speech_since_partial = self.first_speech.is_some();
        Ok(())
    }

    fn maybe_partial(&mut self, events: &mut Vec<Event>) -> Result<bool, String> {
        let end = self.base + self.audio.len();
        let due = self.cuts.is_empty()
            && self.first_speech.is_some()
            && self.speech_since_partial
            && end - self.base >= PARTIAL_MIN
            && end - self.partial_end >= PARTIAL_STEP;
        if !due {
            return Ok(false);
        }
        let prompt = text::prompt(&self.transcript(), PROMPT_CHARS);
        let window = &self.audio[..(end - self.base).min(WINDOW_CAP)];
        let raw = self.transcriber.transcribe(window, &prompt, Pass::Partial)?;
        let words = text::without_prompt_echo(&text::clean(&raw));
        self.partial_end = end;
        self.speech_since_partial = false;
        if !words.is_empty() || self.showing_partial {
            self.showing_partial = !words.is_empty();
            events.push(Event::Partial(Partial { text: words }));
        }
        Ok(true)
    }

    fn clear_partial(&mut self, events: &mut Vec<Event>) {
        if self.showing_partial {
            self.showing_partial = false;
            events.push(Event::Partial(Partial { text: String::new() }));
        }
    }
}

fn to_pcm(sample: f32) -> i16 {
    (sample.clamp(-1.0, 1.0) * i16::MAX as f32).round() as i16
}

fn from_pcm(samples: &[i16]) -> Vec<f32> {
    samples.iter().map(|&s| s as f32 / i16::MAX as f32).collect()
}

