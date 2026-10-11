//! What a `Streamer` says, and to whom: the events the capture worker turns
//! into `capture://` events for the page, and the one-method trait a
//! transcriber implements so the streamer can be driven with no model at all.

use serde::Serialize;

/// Which kind of inference a window is for. The engine tunes for speed on one
/// and for accuracy on the other; see `engine::Session`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Pass {
    /// A guess at uncommitted audio that will be superseded within a second.
    Partial,
    /// The text that will stand.
    Commit,
}

/// Anything that turns a window of 16 kHz mono audio into text.
///
/// A trait so that the state machine can be tested with a transcriber that
/// counts its calls and never loads a model - which is how the silence rule is
/// proved to send NOTHING to the model, rather than merely to hide what came
/// back.
pub trait Transcribe {
    fn transcribe(&mut self, audio: &[f32], prompt: &str, pass: Pass) -> Result<String, String>;
}

/// The best current guess at the uncommitted audio. Each one REPLACES the one
/// before; an empty `text` clears it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Partial {
    pub text: String,
}

/// Committed text. Revised only by a rewind, which drops whole segments. Times
/// are from the start of the capture on the recording's own timeline, and
/// consecutive segments never overlap.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Segment {
    pub text: String,
    pub start_ms: u64,
    pub end_ms: u64,
}

/// Something failed and the capture has stopped transcribing. Never produced
/// by `Streamer` itself - its failures are `Err`s - but by the worker that
/// drives it, so the page has one stream of events to listen to.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Failure {
    pub message: String,
}

/// The tape was wound back to `to_ms`. `segments` is EVERY committed segment
/// that still stands, in order - the page replaces its list with it rather
/// than counting, so a segment whose event was lost to an aborted tick cannot
/// leave the two sides disagreeing.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Rewound {
    pub to_ms: u64,
    pub segments: Vec<Segment>,
}

/// One thing the page is told, in the order it should apply them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    Partial(Partial),
    Segment(Segment),
    Rewound(Rewound),
    Error(Failure),
}
