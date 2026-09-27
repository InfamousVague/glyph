//! Where the speech is in a recording nobody dictated into: the stretches a
//! meeting's write-up (`write_up.rs`) transcribes one at a time, found by
//! running the energy VAD over the file in chunks without ever holding the
//! hour in memory.
//!
//! Whisper over an hour of silence and cross-talk without a VAD repeats
//! phrases and answers the quiet with "Thank you."; spans keep the quiet away
//! from it and bound the audio in memory to one window. The rules are
//! `stream.rs`'s, applied after the fact rather than as the audio arrives: a
//! span starts after `ONSET_FRAMES` voiced frames, closes after `PAUSE` of
//! quiet once `MIN_SPEECH` of speech has come (or after `LONG_PAUSE` whatever
//! came), keeps `SILENCE_KEEP` of quiet either side so a soft consonant stays
//! with its word, and is split at the longest pause inside it once it would
//! pass `WINDOW_CAP`, whisper's window less margin. The last span is clamped
//! to where the samples end (`wav::data_end`), so a header a kill left short
//! loses nothing.

use std::path::Path;

use super::stream::{LONG_PAUSE, MIN_SPEECH, ONSET_FRAMES, PAUSE, SILENCE_KEEP, WINDOW_CAP};
use super::vad::{Vad, FRAME};
use super::{ms_to_samples, samples_to_ms, wav};

/// How much of the file is read at a time: 30 s, a whole number of frames.
const CHUNK_MS: u64 = 30_000;

/// The state the streamer keeps for a window, kept here for a file.
#[derive(Default)]
struct Finder {
    spans: Vec<(usize, usize)>,
    /// Where the next span may start: the end of the last one.
    floor: usize,
    /// Start of the first speech in the open span, if there has been any.
    first_speech: Option<usize>,
    /// End of the most recent speech frame.
    last_speech_end: usize,
    voiced_streak: usize,
    /// Samples of quiet since the last speech frame.
    quiet_run: usize,
    /// The longest pause inside the open span so far: where it started, how long.
    longest_pause: Option<(usize, usize)>,
}

impl Finder {
    /// One classified frame, starting at `frame_start`; `now` is its end.
    fn classify(&mut self, frame_start: usize, now: usize, voiced: bool) {
        self.voiced_streak = if voiced { self.voiced_streak + 1 } else { 0 };
        if self.voiced_streak >= ONSET_FRAMES {
            if self.first_speech.is_none() {
                // The onset began with the first frame of the streak, which was
                // provisionally counted as quiet.
                let onset = frame_start - (ONSET_FRAMES - 1) * FRAME;
                self.first_speech = Some(onset.max(self.floor));
                self.longest_pause = None;
            } else if self.quiet_run > 0 {
                let pause = (self.last_speech_end, self.quiet_run);
                if self.longest_pause.is_none_or(|(_, len)| pause.1 > len) {
                    self.longest_pause = Some(pause);
                }
            }
            self.last_speech_end = now;
            self.quiet_run = 0;
        } else {
            self.quiet_run += FRAME;
        }

        let Some(first) = self.first_speech else { return };
        let speech = self.last_speech_end - first;
        let paused = (self.quiet_run >= PAUSE && speech >= MIN_SPEECH) || self.quiet_run >= LONG_PAUSE;
        if paused {
            self.close(first, self.last_speech_end + SILENCE_KEEP);
        } else if now - first >= WINDOW_CAP {
            match self.longest_pause {
                Some((at, len)) if len >= FRAME => {
                    // Split at the middle of the longest pause; the speech
                    // after it opens the next span, its longest pause forgotten.
                    let cut = at + len / 2;
                    self.spans.push((first.saturating_sub(SILENCE_KEEP).max(self.floor), cut));
                    self.floor = cut;
                    self.first_speech = Some(cut);
                    self.longest_pause = None;
                }
                // Twenty-eight seconds without a single quiet frame: cut here.
                _ => self.close(first, now),
            }
        }
    }

    /// Closes the open span from `first` to `end`, `SILENCE_KEEP` of quiet
    /// kept in front of it, and none of the last span's audio taken again.
    fn close(&mut self, first: usize, end: usize) {
        let start = first.saturating_sub(SILENCE_KEEP).max(self.floor);
        let end = end.max(start);
        self.spans.push((start, end));
        self.floor = end;
        self.first_speech = None;
        self.longest_pause = None;
    }

    /// The end of the file: whatever speech is still open closes there.
    fn finish(&mut self, total: usize) -> Vec<(usize, usize)> {
        if let Some(first) = self.first_speech {
            self.close(first, (self.last_speech_end + SILENCE_KEEP).min(total));
        }
        std::mem::take(&mut self.spans)
            .into_iter()
            .map(|(start, end)| (start.min(total), end.min(total)))
            .filter(|(start, end)| end > start)
            .collect()
    }
}

/// The speech spans of the 16 kHz mono recording at `path`, in order, as
/// `(from_ms, to_ms)` on the recording's own timeline.
pub fn find(path: &Path) -> Result<Vec<(u64, u64)>, String> {
    let total_ms = wav::duration_ms(path)?;
    let total = ms_to_samples(total_ms);
    let mut vad = Vad::new();
    let mut finder = Finder::default();
    let mut position = 0;
    let mut from_ms = 0;
    while from_ms < total_ms {
        let to_ms = (from_ms + CHUNK_MS).min(total_ms);
        let audio = wav::read_span(path, from_ms, to_ms)?;
        for frame in audio.chunks_exact(FRAME) {
            let (voiced, _) = vad.frame(frame);
            let frame_start = position;
            position += FRAME;
            finder.classify(frame_start, position, voiced);
        }
        from_ms = to_ms;
    }
    Ok(finder.finish(total).into_iter().map(|(start, end)| (samples_to_ms(start), samples_to_ms(end))).collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TempDir;

    /// Syllables: 160 ms of loud noise, 60 ms of a dip, repeated - speech as
    /// the VAD sees it, with the gaps between syllables that keep the room
    /// honest (the streamer's tests use the same).
    fn speech(ms: usize) -> Vec<f32> {
        let mut state = 0x2545_f491_u32;
        (0..ms_to_samples(ms as u64))
            .map(|i| {
                state ^= state << 13;
                state ^= state >> 17;
                state ^= state << 5;
                let noise = (state as f32 / u32::MAX as f32) * 2.0 - 1.0;
                let in_dip = (i % ms_to_samples(220)) >= ms_to_samples(160);
                noise * if in_dip { 0.004 } else { 0.2 }
            })
            .collect()
    }

    fn silence(ms: usize) -> Vec<f32> {
        vec![0.0; ms_to_samples(ms as u64)]
    }

    fn written(dir: &TempDir, name: &str, audio: &[f32]) -> std::path::PathBuf {
        let path = dir.join(name);
        let pcm: Vec<i16> = audio.iter().map(|s| (s.clamp(-1.0, 1.0) * i16::MAX as f32) as i16).collect();
        wav::write_pcm16(&path, &pcm, false).unwrap();
        path
    }

    fn near(got: u64, want: u64, within: u64) -> bool {
        got.abs_diff(want) <= within
    }

    #[test]
    fn speech_either_side_of_a_pause_is_two_spans_with_quiet_kept_round_them() {
        let dir = TempDir::new("spans");
        let mut audio = silence(1000);
        audio.extend(speech(3000));
        audio.extend(silence(2000));
        audio.extend(speech(2500));
        audio.extend(silence(500));
        let path = written(&dir, "two.wav", &audio);
        let spans = find(&path).unwrap();
        assert_eq!(spans.len(), 2, "{spans:?}");
        assert!(near(spans[0].0, 700, 100) && near(spans[0].1, 4300, 150), "{spans:?}");
        assert!(near(spans[1].0, 5700, 100) && near(spans[1].1, 8800, 150), "{spans:?}");
        assert!(spans[0].1 <= spans[1].0, "never overlapping");
    }

    #[test]
    fn silence_alone_is_no_span_and_a_short_word_alone_is_one() {
        let dir = TempDir::new("spans-quiet");
        assert!(find(&written(&dir, "quiet.wav", &silence(20_000))).unwrap().is_empty());
        let mut audio = silence(2000);
        audio.extend(speech(600));
        audio.extend(silence(3000));
        let spans = find(&written(&dir, "word.wav", &audio)).unwrap();
        assert_eq!(spans.len(), 1, "a long pause closes any speech: {spans:?}");
        assert!(near(spans[0].0, 1700, 100) && near(spans[0].1, 2900, 150), "{spans:?}");
    }

    #[test]
    fn long_speech_is_split_at_its_pauses_and_never_passes_the_window() {
        let dir = TempDir::new("spans-long");
        let mut audio = Vec::new();
        for _ in 0..4 {
            audio.extend(speech(20_000));
            audio.extend(silence(400));
        }
        let path = written(&dir, "long.wav", &audio);
        let spans = find(&path).unwrap();
        assert!(spans.len() >= 3, "{spans:?}");
        for (from, to) in &spans {
            assert!(to - from <= 28_000, "{spans:?}");
        }
        for pair in spans.windows(2) {
            assert!(pair[0].1 <= pair[1].0, "{spans:?}");
        }
        let covered: u64 = spans.iter().map(|(from, to)| to - from).sum();
        assert!(covered >= 79_000, "the speech is all inside the spans: {covered} ms of {spans:?}");
        assert!(spans.last().unwrap().1 <= 81_600, "the last span ends inside the file: {spans:?}");
    }

    #[test]
    fn a_header_a_kill_left_short_still_yields_the_last_span() {
        let dir = TempDir::new("spans-short");
        let mut audio = speech(3000);
        audio.extend(silence(2000));
        audio.extend(speech(3000));
        let path = written(&dir, "killed.wav", &audio);
        // The meeting service's header from before the last five seconds.
        let mut bytes = std::fs::read(&path).unwrap();
        bytes[40..44].copy_from_slice(&(ms_to_samples(3000) as u32 * 2).to_le_bytes());
        std::fs::write(&path, &bytes).unwrap();
        let spans = find(&path).unwrap();
        assert_eq!(spans.len(), 2, "{spans:?}");
        assert!(near(spans[1].1, 8000, 150), "clamped to the samples that landed: {spans:?}");
    }
}
