//! The computer's own sound, mixed into a meeting's microphone on the Mac: `../glyph/src-tauri/src/system_audio.rs`,
//! whose four commands take Tauri's state and its runtime and so cannot be included whole. The mixer, the
//! resampler, what each command answers and the state that holds the open tap are that file's own lines between
//! the marks, which `kept::tests` holds to the original (its header says why the sound is mixed at the push, and
//! how the two clocks are kept together). The tap itself, `system_audio/mac.rs` (a Core Audio process tap, macOS
//! 14.2 and later), is included as it is.
//!
//! The commands, each as its `#[tauri::command]` there:
//!
//! - `system_audio_available` -> `{supported, reason}`: whether this Mac can tap its sound at all.
//! - `system_audio_start` (a job, work.rs) -> `{capturing, reason}`: the tap opened for the running capture. The
//!   first one on a Mac raises the "System Audio Recording Only" consent (NSAudioCaptureUsageDescription in
//!   macos/Runner/Info.plist). A job because creating the aggregate device is a round trip to coreaudiod, where
//!   the Tauri command hopped to its blocking pool.
//! - `system_audio_status` -> `{capturing, heard}`.
//! - `system_audio_stop` -> `null`. A capture's start, stop and cancel close the tap too (capture.rs).
//!
//! What differs: the state is this process's ([`state`]), where Tauri managed one; and capture.rs adds the
//! computer's sound into every chunk pushed (`capture_push`, `ghost_capture_push`), which is where the Mac app's
//! microphone (macos/Runner/MicChannel.swift, through Dart) arrives, as the page's did.

// Off the Mac nothing feeds the mixer (no tap), so its feeding half is unread there; and `Mixer::waiting` is read
// only by the original's own tests, which run in its suite.
#![allow(dead_code)]

#[cfg(target_os = "macos")]
#[path = "../../../../glyph/src-tauri/src/system_audio/mac.rs"]
mod mac;

// copied:begin
use std::collections::VecDeque;
use std::sync::Mutex;

use serde::Serialize;

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
// copied:end

use serde_json::Value;

impl SystemAudioState {
    /// Whether a tap is open: capture.rs copies a chunk to mix into only then.
    pub fn capturing(&self) -> bool {
        self.mixer.running()
    }
}

static STATE: std::sync::OnceLock<SystemAudioState> = std::sync::OnceLock::new();

/// The mixer and the open tap, for the life of the process.
pub fn state() -> &'static SystemAudioState {
    STATE.get_or_init(SystemAudioState::default)
}

const COMMANDS: &[&str] = &["system_audio_available", "system_audio_start", "system_audio_status", "system_audio_stop"];

/// Whether `command` is one of this file's.
pub fn has(command: &str) -> bool {
    COMMANDS.contains(&command)
}

fn answer<T: Serialize>(value: T) -> Result<Value, String> {
    serde_json::to_value(value).map_err(|e| format!("the answer could not be written: {e}"))
}

/// Whether this Mac can tap its sound, and why not where it cannot.
fn available() -> Availability {
    #[cfg(target_os = "macos")]
    return match mac::unsupported() {
        None => Availability { supported: true, reason: None },
        Some(reason) => Availability { supported: false, reason: Some(reason.to_string()) },
    };
    #[cfg(not(target_os = "macos"))]
    Availability { supported: false, reason: Some(NOT_HERE.to_string()) }
}

/// Opens the tap, on a job's thread.
fn start() -> Result<Started, String> {
    #[cfg(target_os = "macos")]
    {
        if let Some(reason) = mac::unsupported() {
            return Ok(Started { capturing: false, reason: Some(reason.to_string()) });
        }
        // One tap at a time: a second start replaces the first.
        state().stop();
        match mac::Tap::open(std::sync::Arc::clone(&state().mixer)) {
            Ok(tap) => {
                *crate::lock::lock(&state().tap) = Some(tap);
                Ok(Started { capturing: true, reason: None })
            }
            Err(reason) => {
                state().mixer.end();
                Ok(Started { capturing: false, reason: Some(reason) })
            }
        }
    }
    #[cfg(not(target_os = "macos"))]
    Ok(Started { capturing: false, reason: Some(NOT_HERE.to_string()) })
}

/// One of this file's commands.
pub fn call(command: &str) -> Result<Value, String> {
    match command {
        "system_audio_available" => answer(available()),
        "system_audio_start" => {
            let id = crate::work::start("system-audio-start", |_job| answer(start()?))?;
            Ok(serde_json::json!({ "id": id }))
        }
        "system_audio_status" => answer(Status { capturing: state().mixer.running(), heard: state().mixer.heard() }),
        "system_audio_stop" => {
            state().stop();
            Ok(Value::Null)
        }
        _ => Err(format!("Ghost.md's core has no command named {command}.")),
    }
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
    fn nothing_is_added_until_a_tap_is_open_and_then_the_far_side_is_in_the_chunk() {
        let mixer = Mixer::default();
        let mut mic = vec![0.0f32; 3_200];
        mixer.mix_into(&mut mic);
        assert!(mic.iter().all(|s| *s == 0.0) && !mixer.running() && !mixer.heard());
        // A second of a 440 Hz tone from a 48 kHz stereo device, then a microphone chunk of silence: the tone is in it.
        mixer.begin(48_000.0);
        let mono = tone(48_000.0, 440.0, 1.0, 0.5);
        let stereo: Vec<f32> = mono.iter().flat_map(|s| [*s, *s]).collect();
        mixer.hear(&stereo, 2);
        assert!(mixer.running() && mixer.heard());
        mixer.mix_into(&mut mic);
        assert!(rms(&mic) > 0.2, "the computer's sound is in the microphone's chunk: {}", rms(&mic));
        mixer.end();
        let mut after = vec![0.0f32; 3_200];
        mixer.mix_into(&mut after);
        assert!(after.iter().all(|s| *s == 0.0) && !mixer.running());
    }

    #[test]
    fn the_commands_answer_without_opening_anything() {
        assert!(has("system_audio_available") && has("system_audio_start") && has("system_audio_status") && has("system_audio_stop") && !has("capture_start"));
        // Asked, never started here: a start raises macOS's consent and listens to what the Mac plays.
        let said = call("system_audio_available").unwrap();
        assert!(said["supported"].is_boolean());
        #[cfg(not(target_os = "macos"))]
        assert_eq!(said, serde_json::json!({"supported": false, "reason": NOT_HERE}));
        assert_eq!(call("system_audio_status"), Ok(serde_json::json!({"capturing": false, "heard": false})));
        assert_eq!(call("system_audio_stop"), Ok(Value::Null));
    }
}
