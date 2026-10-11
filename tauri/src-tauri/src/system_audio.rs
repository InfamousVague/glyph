//! The computer's own sound, mixed into a meeting's microphone (docs/DESIGN.md
//! "Meetings with the computer's sound"). Matt: "can you make it so that the app
//! can listen to the microphone and system audio so that we can record meetings
//! with raw audio?"
//!
//! The Mac only. Android's other apps are heard by the meeting service itself
//! (capture/MeetingService.kt, AudioPlaybackCapture), because there the
//! microphone is Kotlin's and so is the file; here the microphone is the page's
//! (capture/audio.ts) and every sample of it already passes through
//! `capture_push`. So that is where the computer's sound goes in: a Core Audio
//! process tap (`mac.rs`, macOS 14.2 and later) hands this module float frames
//! on Core Audio's own thread and clock, they are brought to 16 kHz mono and
//! kept in a short ring, and each microphone chunk takes as many of them as it
//! has samples and adds them in (`Mixer::mix_into`). One stream comes out, at
//! the rate and in the shape every tape already is - 16 kHz mono PCM16, which
//! whisper/wav.rs, the write-up's `read_span` and Kotlin's WavSpool all assume -
//! and the live transcription hears both sides of the call, because it is fed
//! from the same push.
//!
//! WHY MIXED AT THE PUSH, NOT IN A SECOND TRACK. A second file would have to be
//! kept in step with the first through rewinds, appends and moves
//! (`capture_reassign_recording`), and the write-up reads one file; a sum made
//! before the samples reach the worker has none of that, and the tape is the
//! meeting as the room and the call both sounded.
//!
//! TWO CLOCKS. The microphone's chunks arrive every 200 ms from the WebView's
//! audio clock; the tap's frames arrive every 10 ms or so from the output
//! device's. Taking "whatever has arrived, up to the chunk's length" lets the
//! ring settle at the jitter between them on its own: a chunk that finds fewer
//! samples than it needs leaves the rest of itself microphone-only, and the
//! ring is that much fuller for the next one, after which it no longer runs
//! short. A ring that grows past a second (the two clocks drifting apart over
//! an hour, or the page's held-back first chunks not yet sent) drops its oldest
//! samples, so the far side is never heard more than a second late.
//!
//! The commands, for the page (capture/systemSound.ts):
//!
//! - `system_audio_available() -> { supported, reason }`: whether this Mac can
//!   tap its sound at all (14.2 or later), and the sentence to show when not.
//! - `system_audio_start() -> { capturing, reason }`: the tap opened for the
//!   running capture. The first one on a Mac raises the "System Audio Recording
//!   Only" consent (NSAudioCaptureUsageDescription, Info.macos.plist).
//! - `system_audio_status() -> { capturing, heard }`: whether anything but
//!   silence has come through, which is how a refused consent shows (the tap
//!   delivers zeros rather than an error), or a computer playing nothing.
//! - `system_audio_stop()`. `capture_stop`, `capture_cancel`, a new
//!   `capture_start` and the app's exit stop it too, so a page that reloaded
//!   mid-meeting cannot leave the tap open behind it.

// Off the Mac nothing feeds the mixer (no tap), so its feeding half is unread
// there; it is compiled and tested everywhere all the same.
#![cfg_attr(not(target_os = "macos"), allow(dead_code))]

use std::collections::VecDeque;
use std::sync::Mutex;

use serde::Serialize;

#[cfg(target_os = "macos")]
mod mac;

/// The rate every tape is kept at (whisper/mod.rs `SAMPLE_RATE`).
pub const RATE: f64 = 16_000.0;

/// The most the computer's sound may run behind the microphone: one second of it.
const MOST_BEHIND: usize = 16_000;

/// Anything above this is heard: about -80 dBFS, below any sound a speaker
/// makes and above the zeros a refused consent delivers.
const HEARD_ABOVE: f32 = 1.0e-4;

/// Where the sum starts to be bent rather than passed straight through: below
/// it the mix is the plain sum of the two, which is what "raw audio" asks for.
const KNEE: f32 = 0.8;

/// A streaming resampler to 16 kHz: each output sample is the mean of the input
/// samples its window covers.
///
/// The page's own (capture/audio.ts `createResampler`), ported: a box average is
/// a crude low-pass, but it is the low-pass decimation needs to keep the band
/// above 8 kHz from folding back over the speech, and Whisper was trained on far
/// rougher audio than this. Its position carries across calls, so a buffer
/// boundary never clicks or drops a sample.
#[derive(Debug, Clone)]
pub struct Resampler {
    step: f64,
    carry: Vec<f32>,
    position: f64,
}

impl Resampler {
    pub fn new(from_rate: f64, to_rate: f64) -> Resampler {
        let step = if from_rate > 0.0 && to_rate > 0.0 { from_rate / to_rate } else { 1.0 };
        Resampler { step, carry: Vec::new(), position: 0.0 }
    }

    /// The input resampled, appended to `out`.
    pub fn process(&mut self, input: &[f32], out: &mut impl Extend<f32>) {
        if (self.step - 1.0).abs() < f64::EPSILON {
            out.extend(input.iter().copied());
            return;
        }
        self.carry.extend_from_slice(input);
        let step = self.step;
        let mut position = self.position;
        let buffer = &self.carry;
        // Straight into `out`, one at a time: this runs on Core Audio's thread,
        // and a Vec made per buffer is an allocation there every 10 ms.
        while position + step <= buffer.len() as f64 {
            let start = position.floor() as usize;
            let end = (position + step).floor() as usize;
            let sample = if end <= start {
                buffer[start]
            } else {
                buffer[start..end].iter().sum::<f32>() / (end - start) as f32
            };
            out.extend(std::iter::once(sample));
            position += step;
        }
        let consumed = (position.floor() as usize).min(self.carry.len());
        self.carry.drain(..consumed);
        self.position = position - consumed as f64;
    }
}

/// The sum of two samples, kept inside [-1, 1]: unchanged up to the knee, then
/// bent smoothly towards full scale so a loud call over a loud room is softened
/// rather than clipped into a square wave Whisper hears as noise.
pub fn soft_clip(x: f32) -> f32 {
    let size = x.abs();
    if size <= KNEE {
        return x;
    }
    let room = 1.0 - KNEE;
    let bent = KNEE + room * ((size - KNEE) / room).tanh();
    bent.copysign(x)
}

struct Inner {
    running: bool,
    resampler: Resampler,
    /// The computer's sound at 16 kHz, waiting for the microphone's next chunk.
    ring: VecDeque<f32>,
    /// One device buffer brought to mono, kept so the audio thread allocates
    /// nothing once the first buffer has sized it.
    mono: Vec<f32>,
    heard: bool,
}

/// The ring between the tap's thread and `capture_push`, and the work at both
/// of its ends. Tauri-free and platform-free, so the mixing is tested on every
/// host with synthetic buffers.
///
/// One lock, held for a resample of 10 ms of audio on one side and a sum of
/// 200 ms on the other: microseconds, so the audio thread waiting on it is a
/// wait it never notices.
pub struct Mixer {
    inner: Mutex<Inner>,
}

impl Default for Mixer {
    fn default() -> Self {
        Mixer {
            inner: Mutex::new(Inner {
                running: false,
                resampler: Resampler::new(RATE, RATE),
                ring: VecDeque::new(),
                mono: Vec::new(),
                heard: false,
            }),
        }
    }
}

impl Mixer {
    fn lock(&self) -> std::sync::MutexGuard<'_, Inner> {
        crate::lock::lock(&self.inner)
    }

    /// Ready for a tap whose frames come at `device_rate`: anything left from an
    /// earlier one is dropped, so a meeting never starts with the end of the last.
    pub fn begin(&self, device_rate: f64) {
        let mut inner = self.lock();
        inner.running = true;
        inner.resampler = Resampler::new(device_rate, RATE);
        inner.ring.clear();
        inner.heard = false;
    }

    /// No more of the computer's sound: the microphone goes on alone.
    pub fn end(&self) {
        let mut inner = self.lock();
        inner.running = false;
        inner.ring.clear();
    }

    pub fn running(&self) -> bool {
        self.lock().running
    }

    pub fn heard(&self) -> bool {
        self.lock().heard
    }

    /// From the tap's thread: `frames` interleaved samples of `channels`
    /// channels, averaged to mono, brought to 16 kHz and kept for the
    /// microphone's next chunk.
    pub fn hear(&self, frames: &[f32], channels: usize) {
        let channels = channels.max(1);
        let mut guard = self.lock();
        let inner = &mut *guard;
        if !inner.running {
            return;
        }
        inner.mono.clear();
        if channels == 1 {
            inner.mono.extend_from_slice(frames);
        } else {
            let share = 1.0 / channels as f32;
            inner.mono.extend(frames.chunks_exact(channels).map(|frame| frame.iter().sum::<f32>() * share));
        }
        if !inner.heard && inner.mono.iter().any(|s| s.abs() > HEARD_ABOVE) {
            inner.heard = true;
        }
        inner.resampler.process(&inner.mono, &mut inner.ring);
        if inner.ring.len() > MOST_BEHIND {
            let over = inner.ring.len() - MOST_BEHIND;
            inner.ring.drain(..over);
        }
    }

    /// From `capture_push`: the computer's sound added into a microphone chunk,
    /// as much of it as has arrived, up to the chunk's length. Nothing when no
    /// tap is running, which is every capture that is not a meeting with the
    /// switch on.
    pub fn mix_into(&self, mic: &mut [f32]) {
        let mut inner = self.lock();
        if !inner.running || inner.ring.is_empty() {
            return;
        }
        let take = mic.len().min(inner.ring.len());
        for (sample, system) in mic.iter_mut().zip(inner.ring.drain(..take)) {
            *sample = soft_clip(*sample + system);
        }
    }

    #[cfg(test)]
    fn waiting(&self) -> usize {
        self.lock().ring.len()
    }
}

/// What `system_audio_available` answers.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct Availability {
    pub supported: bool,
    /// Why not, in the app's words; null when it is supported.
    pub reason: Option<String>,
}

/// What `system_audio_start` answers: the tap is open, or why it is not, in
/// which case the meeting records the microphone alone.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct Started {
    pub capturing: bool,
    pub reason: Option<String>,
}

/// What `system_audio_status` answers.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct Status {
    pub capturing: bool,
    /// Anything but silence has come through since the tap opened.
    pub heard: bool,
}

/// Said where there is no tap to open: every platform but the Mac.
#[cfg_attr(target_os = "macos", allow(dead_code))]
pub const NOT_HERE: &str = "Only the Mac app can record the computer's sound.";

/// The mixer and the open tap, for the life of the process.
#[derive(Default)]
pub struct SystemAudioState {
    mixer: std::sync::Arc<Mixer>,
    #[cfg(target_os = "macos")]
    tap: Mutex<Option<mac::Tap>>,
}

impl SystemAudioState {
    /// The computer's sound added into a microphone chunk (`Mixer::mix_into`).
    pub fn mix_into(&self, mic: &mut [f32]) {
        self.mixer.mix_into(mic);
    }

    /// The tap closed, if one is open. Called from the capture's stop, cancel
    /// and start, and at exit.
    pub fn stop(&self) {
        self.mixer.end();
        #[cfg(target_os = "macos")]
        {
            let tap = crate::lock::lock(&self.tap).take();
            drop(tap);
        }
    }
}

/// Hands the state to Tauri. Called once, from `setup`. Opens nothing.
pub fn install(app: &tauri::App) {
    use tauri::Manager;
    app.manage(SystemAudioState::default());
}

/// The tap closed, from anywhere holding the app (capture_commands.rs).
pub fn stop(app: &tauri::AppHandle) {
    use tauri::Manager;
    if let Some(state) = app.try_state::<SystemAudioState>() {
        state.stop();
    }
}

#[tauri::command]
pub fn system_audio_available() -> Availability {
    #[cfg(target_os = "macos")]
    return match mac::unsupported() {
        None => Availability { supported: true, reason: None },
        Some(reason) => Availability { supported: false, reason: Some(reason.to_string()) },
    };
    #[cfg(not(target_os = "macos"))]
    Availability { supported: false, reason: Some(NOT_HERE.to_string()) }
}

/// Opens the tap. Off the async runtime: creating the aggregate device and
/// starting it is a round trip to coreaudiod, and the first start on a Mac is
/// where the consent is raised.
#[tauri::command]
pub async fn system_audio_start(state: tauri::State<'_, SystemAudioState>) -> Result<Started, String> {
    #[cfg(target_os = "macos")]
    {
        if let Some(reason) = mac::unsupported() {
            return Ok(Started { capturing: false, reason: Some(reason.to_string()) });
        }
        // One tap at a time: a second start replaces the first.
        state.stop();
        let mixer = std::sync::Arc::clone(&state.mixer);
        let opened = tauri::async_runtime::spawn_blocking(move || mac::Tap::open(mixer))
            .await
            .map_err(|e| format!("the computer's sound did not open: {e}"))?;
        match opened {
            Ok(tap) => {
                *crate::lock::lock(&state.tap) = Some(tap);
                Ok(Started { capturing: true, reason: None })
            }
            Err(reason) => {
                state.mixer.end();
                Ok(Started { capturing: false, reason: Some(reason) })
            }
        }
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = state;
        Ok(Started { capturing: false, reason: Some(NOT_HERE.to_string()) })
    }
}

#[tauri::command]
pub fn system_audio_status(state: tauri::State<'_, SystemAudioState>) -> Status {
    Status { capturing: state.mixer.running(), heard: state.mixer.heard() }
}

#[tauri::command]
pub async fn system_audio_stop(state: tauri::State<'_, SystemAudioState>) -> Result<(), String> {
    state.stop();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tone(rate: f64, hz: f64, seconds: f64, level: f32) -> Vec<f32> {
        let n = (rate * seconds) as usize;
        (0..n).map(|i| level * (2.0 * std::f64::consts::PI * hz * i as f64 / rate).sin() as f32).collect()
    }

    fn rms(samples: &[f32]) -> f32 {
        (samples.iter().map(|s| s * s).sum::<f32>() / samples.len().max(1) as f32).sqrt()
    }

    #[test]
    fn a_48k_stream_comes_out_at_16k_whatever_the_buffer_sizes() {
        let input = tone(48_000.0, 440.0, 1.0, 0.5);
        let mut whole = Vec::new();
        Resampler::new(48_000.0, RATE).process(&input, &mut whole);
        // Fed in Core Audio's odd buffer sizes, the same samples come out.
        let mut pieces = Vec::new();
        let mut resampler = Resampler::new(48_000.0, RATE);
        let mut at = 0;
        for size in [512usize, 471, 1024, 7, 333].iter().cycle() {
            if at >= input.len() {
                break;
            }
            let end = (at + size).min(input.len());
            resampler.process(&input[at..end], &mut pieces);
            at = end;
        }
        assert_eq!(whole.len(), 16_000);
        assert_eq!(pieces.len(), whole.len());
        for (a, b) in whole.iter().zip(&pieces) {
            assert!((a - b).abs() < 1e-6);
        }
        // A 440 Hz tone keeps its level: the box average only bites near 8 kHz.
        assert!((rms(&whole) - rms(&input)).abs() < 0.02, "{} vs {}", rms(&whole), rms(&input));
    }

    #[test]
    fn a_44_1k_stream_keeps_its_length_in_time() {
        let input = tone(44_100.0, 300.0, 2.0, 0.3);
        let mut out = Vec::new();
        let mut resampler = Resampler::new(44_100.0, RATE);
        for chunk in input.chunks(441) {
            resampler.process(chunk, &mut out);
        }
        // Two seconds in, two seconds out, give or take the sample still carried.
        assert!((out.len() as i64 - 32_000).abs() <= 1, "{}", out.len());
    }

    #[test]
    fn soft_clip_passes_the_quiet_and_bends_the_loud() {
        assert_eq!(soft_clip(0.5), 0.5);
        assert_eq!(soft_clip(-0.8), -0.8);
        assert!(soft_clip(1.6) < 1.0 && soft_clip(1.6) > 0.95);
        // Never past full scale, however loud: at three times it, exactly full scale.
        assert!(soft_clip(-3.0) >= -1.0 && soft_clip(-3.0) < -0.99);
        // Continuous at the knee, and still rising after it.
        assert!((soft_clip(0.8001) - 0.8001).abs() < 1e-3);
        assert!(soft_clip(0.9) < soft_clip(1.0));
    }

    #[test]
    fn nothing_is_added_while_no_tap_runs() {
        let mixer = Mixer::default();
        mixer.hear(&[0.5; 480], 1);
        let mut mic = vec![0.1f32; 3_200];
        mixer.mix_into(&mut mic);
        assert!(mic.iter().all(|s| *s == 0.1));
    }

    #[test]
    fn both_sides_are_in_the_chunk_and_the_stereo_is_averaged() {
        let mixer = Mixer::default();
        mixer.begin(48_000.0);
        // 200 ms of a stereo tap: left at 0.3, right at 0.1, which is 0.2 mono.
        let stereo: Vec<f32> = (0..9_600).flat_map(|_| [0.3f32, 0.1]).collect();
        for buffer in stereo.chunks(2 * 480) {
            mixer.hear(buffer, 2);
        }
        assert_eq!(mixer.waiting(), 3_200);
        let mut mic = vec![0.25f32; 3_200];
        mixer.mix_into(&mut mic);
        assert!(mic.iter().all(|s| (s - 0.45).abs() < 1e-5), "{:?}", &mic[..4]);
        assert_eq!(mixer.waiting(), 0);
        assert!(mixer.heard());
    }

    #[test]
    fn a_short_ring_fills_the_front_of_the_chunk_and_the_rest_waits_for_the_next() {
        let mixer = Mixer::default();
        mixer.begin(RATE);
        mixer.hear(&[0.5; 1_000], 1);
        let mut mic = vec![0.0f32; 3_200];
        mixer.mix_into(&mut mic);
        assert!(mic[..1_000].iter().all(|s| *s == 0.5));
        assert!(mic[1_000..].iter().all(|s| *s == 0.0));
        // The next 3 200 arrive while the next chunk is recorded; it takes them all.
        mixer.hear(&[0.25; 3_200], 1);
        let mut next = vec![0.0f32; 3_200];
        mixer.mix_into(&mut next);
        assert!(next.iter().all(|s| *s == 0.25));
    }

    #[test]
    fn a_ring_that_runs_ahead_keeps_only_the_last_second() {
        let mixer = Mixer::default();
        mixer.begin(RATE);
        // Three seconds with no microphone chunk to take them: the oldest two go.
        for second in 0..3 {
            mixer.hear(&vec![second as f32 * 0.1; 16_000], 1);
        }
        assert_eq!(mixer.waiting(), MOST_BEHIND);
        let mut mic = vec![0.0f32; 100];
        mixer.mix_into(&mut mic);
        assert!(mic.iter().all(|s| (s - 0.2).abs() < 1e-6), "the newest second is what is left");
    }

    #[test]
    fn silence_is_not_heard_and_a_new_tap_starts_empty() {
        let mixer = Mixer::default();
        mixer.begin(RATE);
        mixer.hear(&[0.0; 1_600], 1);
        assert!(!mixer.heard(), "zeros are what a refused consent delivers");
        mixer.hear(&[0.01; 1_600], 1);
        assert!(mixer.heard());
        mixer.begin(48_000.0);
        assert_eq!(mixer.waiting(), 0);
        assert!(!mixer.heard());
        mixer.end();
        assert!(!mixer.running());
    }

    #[test]
    fn a_loud_call_over_a_loud_room_stays_inside_full_scale() {
        let mixer = Mixer::default();
        mixer.begin(RATE);
        mixer.hear(&tone(RATE, 200.0, 0.2, 0.9), 1);
        let mut mic = tone(RATE, 200.0, 0.2, 0.9);
        mixer.mix_into(&mut mic);
        assert!(mic.iter().all(|s| s.abs() <= 1.0));
        assert!(mic.iter().any(|s| s.abs() > 0.95), "the peaks are bent, not halved");
    }
}
