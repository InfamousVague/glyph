//! Which 20 ms of audio are somebody talking: energy against the room.
//!
//! This is not a speech detector in the sense whisper.cpp's Silero VAD is, and
//! it is not trying to be one. It has two jobs, and energy is enough for both:
//! finding the PAUSES that `stream.rs` commits text at, and keeping near-silent
//! audio away from a model that answers silence with "Thank you." A cough will
//! read as speech here, and that is fine - the model gets a window with a cough
//! in it and says nothing, which costs one inference. What would not be fine is
//! the reverse, and a threshold ten decibels over the room errs the right way.
//!
//! Silero was the alternative and was measured against what it buys: a second
//! model file to download and verify, a second context to load on every
//! capture, and inference on every 30 ms chunk on the phone's CPU - to answer a
//! question ("is this quieter than the room?") that a square root answers.
//!
//! The ROOM is the quietest frame in the last three seconds. A minimum rather
//! than an average, because an average over a window with speech in it is
//! mostly speech; the minimum is the gap between two words, which is the room
//! even while somebody is talking. Three seconds because natural speech never
//! runs that long without a stop consonant or a breath - and because it is
//! also how long a person waits for the app to notice that the dishwasher
//! started.

use std::collections::VecDeque;

use super::ms_to_samples;

/// One analysis frame: 20 ms, which is 320 samples at 16 kHz.
///
/// Short enough that the silence between two words spans several frames, long
/// enough that one frame's RMS is not a single glottal pulse.
pub const FRAME: usize = ms_to_samples(20);

/// How many frames the room is remembered for: three seconds.
const FLOOR_FRAMES: usize = 150;

/// How much audio the noise floor remembers - what a rewind replays into a
/// fresh `Vad` so it judges the room as the old one did.
pub const MEMORY: usize = FLOOR_FRAMES * FRAME;

/// How far over the room a frame has to be to count as voiced: +10 dB, which
/// is an amplitude ratio of 3.16.
///
/// NOT YET MEASURED on the Fold's microphone, and it is the first number to
/// check when it is: the `say` fixture the tests use has digital silence
/// between phrases, against which any threshold at all separates cleanly.
/// Ten is chosen to sit well under close-talked speech over a quiet room and
/// well over the frame-to-frame wobble of steady background noise, and the
/// failure it risks is the cheap one (see the module header).
const VOICED_OVER_FLOOR: f32 = 3.16;

/// A frame quieter than this is never speech, however quiet the room is.
///
/// -50 dBFS. The floor-relative test alone breaks in exactly the case that
/// matters most: digital silence, where the room is 0.0 and anything at all -
/// dither, a fan three rooms away - is infinitely louder than it. A phone
/// microphone behind the browser's noise suppression sits well below this;
/// a person speaking softly at arm's length sits well above it.
const ABSOLUTE_FLOOR: f32 = 0.003;

/// The rolling room and the one decision made against it.
pub struct Vad {
    recent: VecDeque<f32>,
}

impl Default for Vad {
    fn default() -> Self {
        Vad::new()
    }
}

impl Vad {
    pub fn new() -> Vad {
        Vad {
            recent: VecDeque::with_capacity(FLOOR_FRAMES),
        }
    }

    /// Classifies one frame and folds it into the room. Returns whether the
    /// frame is loud enough to be speech, and its RMS for callers that need
    /// to find the quietest place to cut.
    ///
    /// The frame joins the room BEFORE it is judged. That is what lets the
    /// very first frame of a capture be silence rather than an unknown: a
    /// room of one frame compared with itself is never 10 dB louder than
    /// itself.
    /// Hears `samples` for the noise floor only, whole frames, judging nothing.
    pub fn prime(&mut self, samples: &[f32]) {
        for frame in samples.chunks_exact(FRAME) {
            self.frame(frame);
        }
    }

    pub fn frame(&mut self, samples: &[f32]) -> (bool, f32) {
        let rms = rms(samples);
        if self.recent.len() == FLOOR_FRAMES {
            self.recent.pop_front();
        }
        self.recent.push_back(rms);
        let floor = self.recent.iter().copied().fold(f32::INFINITY, f32::min);
        let voiced = rms > (floor * VOICED_OVER_FLOOR).max(ABSOLUTE_FLOOR);
        (voiced, rms)
    }
}

/// Root mean square of a frame. Zero for an empty one, rather than NaN.
pub fn rms(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }
    let sum: f32 = samples.iter().map(|s| s * s).sum();
    (sum / samples.len() as f32).sqrt()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tone(amplitude: f32) -> Vec<f32> {
        (0..FRAME)
            .map(|i| amplitude * (i as f32 * 0.2).sin())
            .collect()
    }

    #[test]
    fn digital_silence_and_faint_noise_are_not_speech() {
        let mut vad = Vad::new();
        for _ in 0..50 {
            assert!(!vad.frame(&vec![0.0; FRAME]).0);
        }
        // Faint noise over digital silence is infinitely louder than the room
        // - the case ABSOLUTE_FLOOR exists for.
        assert!(!vad.frame(&tone(0.002)).0);
    }

    #[test]
    fn speech_over_a_quiet_room_is_speech() {
        let mut vad = Vad::new();
        for _ in 0..20 {
            vad.frame(&tone(0.005));
        }
        assert!(vad.frame(&tone(0.1)).0);
        // The room is the MINIMUM, so ten frames of speech do not raise it.
        for _ in 0..10 {
            assert!(vad.frame(&tone(0.1)).0);
        }
    }

    #[test]
    fn a_louder_room_raises_the_bar_once_it_has_been_heard_for_three_seconds() {
        let mut vad = Vad::new();
        for _ in 0..20 {
            vad.frame(&tone(0.004));
        }
        // A fan starts. At first it is speech - the room is still the quiet one.
        assert!(vad.frame(&tone(0.02)).0);
        for _ in 0..FLOOR_FRAMES {
            vad.frame(&tone(0.02));
        }
        // Three seconds of fan and the fan IS the room.
        assert!(!vad.frame(&tone(0.02)).0);
    }
}
