//! The thread that drives a `Streamer`, so that handing over audio never waits
//! for a model.
//!
//! Deliberately thin. Every decision about what to transcribe is
//! `stream.rs`'s, and it is tested there without a thread in sight; this
//! module is a mailbox, a loop, and the two ways out of it. Its whole reason to
//! exist is that `push` is called from an IPC handler (or, later, a JNI audio
//! callback) that must return in microseconds, while a `tick` can spend a
//! second or more inside whisper.cpp.
//!
//! The mailbox is a `Mutex<Vec<f32>>` that `push` appends to and the worker
//! swaps out, rather than a channel of chunks. The difference is what happens
//! behind a slow inference: a channel queues one message per 250 ms push and
//! the worker then drains them one lock at a time; the swap takes everything
//! that arrived in one move, and the streamer classifies it in one `feed`.
//!
//! Stopping has two meanings and they must not be confused. STOP is "I have
//! finished talking": the worker takes whatever audio is left, commits it, and
//! hands back the transcript, however long that last inference takes. CANCEL is
//! "throw it away": the abort flag cuts short any inference in progress, and
//! nothing more is emitted. Dropping a `Capture` without either is a cancel,
//! which is what an app exiting mid-dictation needs.
//!
//! REWIND is neither: the capture carries on from an earlier moment. It borrows
//! the abort flag to cut short an inference about audio that is about to stop
//! existing, and the worker clears the flag again when it takes the request -
//! both under the mailbox lock, so a rewind can never clear a cancel's abort
//! without the worker also seeing the cancel. The request carries the audio
//! pushed before it, because audio pushed after it belongs after the moment.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc, Condvar, Mutex};
use std::thread::JoinHandle;
use std::time::Duration;

use super::stream::{Event, Failure, Streamer, Transcribe};

/// How often the worker wakes to feed and tick when nothing has told it to.
///
/// 100 ms is below anything the eye reads as lag on a partial, and a wake that
/// finds nothing due is a lock, a swap and a few comparisons.
const WAKE: Duration = Duration::from_millis(100);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Command {
    Run,
    Stop,
    Cancel,
}

/// A rewind waiting for the worker: the moment, the audio pushed before it was
/// asked for, and who to tell when it has happened.
struct Rewind {
    to_ms: u64,
    before: Vec<f32>,
    done: mpsc::Sender<()>,
}

struct Mailbox {
    audio: Vec<f32>,
    command: Command,
    rewind: Option<Rewind>,
    /// Set by the worker when it has exited, so `push` stops hoarding audio
    /// nobody will read.
    closed: bool,
}

struct Shared {
    mailbox: Mutex<Mailbox>,
    wake: Condvar,
}

impl Shared {
    /// The mailbox, recovered if a panic poisoned it. The worker cannot panic
    /// while holding this lock - it only swaps a Vec under it - so a poisoned
    /// lock can only mean a panic somewhere that held it for a moment, and
    /// refusing all further audio over that would be worse than the panic.
    fn lock(&self) -> std::sync::MutexGuard<'_, Mailbox> {
        self.mailbox.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

/// What a stopped capture leaves behind: its words, and the audio they came from.
#[derive(Debug, Default)]
pub struct Stopped {
    pub transcript: String,
    /// 16 kHz mono 16-bit, the whole recording from the first sample pushed.
    pub recording: Vec<i16>,
}

/// A capture in progress.
pub struct Capture {
    shared: Arc<Shared>,
    abort: Arc<AtomicBool>,
    thread: Option<JoinHandle<Result<Stopped, String>>>,
}

impl Capture {
    /// Starts the worker thread over `transcriber`, delivering events to
    /// `sink` from that thread.
    ///
    /// `abort` must be the flag the transcriber itself polls (for a `Session`,
    /// the one it was created with). It is passed in rather than asked for so
    /// that `Transcribe` stays a one-method trait a test can implement in five
    /// lines.
    pub fn start<T, F>(transcriber: T, abort: Arc<AtomicBool>, mut sink: F) -> Capture
    where
        T: Transcribe + Send + 'static,
        F: FnMut(Event) + Send + 'static,
    {
        let shared = Arc::new(Shared {
            mailbox: Mutex::new(Mailbox {
                audio: Vec::new(),
                command: Command::Run,
                rewind: None,
                closed: false,
            }),
            wake: Condvar::new(),
        });
        let worker_shared = Arc::clone(&shared);
        let worker_abort = Arc::clone(&abort);
        let thread = std::thread::Builder::new()
            .name("glyph-whisper".to_string())
            .spawn(move || {
                let outcome = run(&worker_shared, &worker_abort, transcriber, &mut sink);
                let mut mailbox = worker_shared.lock();
                mailbox.closed = true;
                // Nobody will apply it: dropping the sender tells the waiter so.
                mailbox.rewind = None;
                outcome
            })
            // Spawning fails only when the OS is out of threads or memory, and
            // a capture that cannot start must say so loudly; there is nothing
            // to fall back to.
            .expect("the transcription worker thread could not be started");
        Capture {
            shared,
            abort,
            thread: Some(thread),
        }
    }

    /// Hands audio to the worker. Returns immediately; never runs inference.
    pub fn push(&self, samples: &[f32]) {
        let mut mailbox = self.shared.lock();
        if !mailbox.closed && mailbox.command == Command::Run {
            mailbox.audio.extend_from_slice(samples);
        }
    }

    /// Asks the worker to wind back to `to_ms` (see `Streamer::rewind`), cutting
    /// short any inference in progress. Returns at once with a receiver that
    /// hears once the rewind has happened and its events have been delivered;
    /// it disconnects instead if the capture ends first.
    ///
    /// A receiver rather than a wait so the caller can let go of whatever lock
    /// it found this capture under before waiting on it.
    pub fn rewind(&self, to_ms: u64) -> Result<mpsc::Receiver<()>, String> {
        let (done, heard) = mpsc::channel();
        {
            let mut mailbox = self.shared.lock();
            if mailbox.closed || mailbox.command != Command::Run {
                return Err("the capture has ended".to_string());
            }
            if mailbox.rewind.is_some() {
                return Err("a rewind is already under way".to_string());
            }
            let before = std::mem::take(&mut mailbox.audio);
            mailbox.rewind = Some(Rewind { to_ms, before, done });
            self.abort.store(true, Ordering::Relaxed);
        }
        self.shared.wake.notify_all();
        Ok(heard)
    }

    /// Commits the remaining audio, waits for that final inference, and
    /// returns the whole transcript with its recording - or the error that
    /// ended the capture early, if one did.
    pub fn stop(mut self) -> Result<Stopped, String> {
        self.signal(Command::Stop);
        self.join()
    }

    /// Ends the capture without committing anything further, cutting short any
    /// inference in progress.
    pub fn cancel(mut self) {
        self.cancel_now();
    }

    fn cancel_now(&mut self) {
        self.abort.store(true, Ordering::Relaxed);
        self.signal(Command::Cancel);
        // Cancelled: whatever the worker returns is being thrown away.
        let _ = self.join();
    }

    fn signal(&self, command: Command) {
        self.shared.lock().command = command;
        self.shared.wake.notify_all();
    }

    fn join(&mut self) -> Result<Stopped, String> {
        match self.thread.take() {
            Some(thread) => thread
                .join()
                .unwrap_or_else(|_| Err("the transcription worker panicked".to_string())),
            None => Err("the capture has already ended".to_string()),
        }
    }
}

impl Drop for Capture {
    /// A capture nobody stopped is cancelled, and the thread is joined rather
    /// than left running against a model that may be about to be dropped.
    fn drop(&mut self) {
        if self.thread.is_some() {
            self.cancel_now();
        }
    }
}

fn run<T: Transcribe>(
    shared: &Shared,
    abort: &AtomicBool,
    transcriber: T,
    sink: &mut impl FnMut(Event),
) -> Result<Stopped, String> {
    let mut streamer = Streamer::new(transcriber);
    let mut incoming = Vec::new();
    loop {
        let (command, rewind) = {
            let mut mailbox = shared.lock();
            if mailbox.command == Command::Run && mailbox.audio.is_empty() && mailbox.rewind.is_none() {
                mailbox = shared
                    .wake
                    .wait_timeout(mailbox, WAKE)
                    .unwrap_or_else(|poisoned| poisoned.into_inner())
                    .0;
            }
            let rewind = mailbox.rewind.take();
            if rewind.is_some() && mailbox.command != Command::Cancel {
                abort.store(false, Ordering::Relaxed);
            }
            std::mem::swap(&mut incoming, &mut mailbox.audio);
            (mailbox.command, rewind)
        };
        if command == Command::Cancel {
            return Err("cancelled".to_string());
        }
        if let Some(rewind) = rewind {
            streamer.feed(&rewind.before);
            streamer.rewind(rewind.to_ms).into_iter().for_each(&mut *sink);
            let _ = rewind.done.send(());
        }
        streamer.feed(&incoming);
        incoming.clear();

        let outcome = if command == Command::Stop {
            streamer.finish()
        } else {
            streamer.tick()
        };
        match outcome {
            Ok(events) => events.into_iter().for_each(&mut *sink),
            Err(message) => {
                // A cancel or a rewind that arrived mid-inference surfaces here
                // as an aborted decode; that is not an error worth telling
                // anyone. A rewind is applied at the top of the loop.
                {
                    let mailbox = shared.lock();
                    if mailbox.command == Command::Cancel {
                        return Err("cancelled".to_string());
                    }
                    if mailbox.rewind.is_some() {
                        continue;
                    }
                }
                sink(Event::Error(Failure {
                    message: message.clone(),
                }));
                return Err(message);
            }
        }
        if command == Command::Stop {
            return Ok(Stopped {
                transcript: streamer.transcript(),
                recording: streamer.take_recording(),
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::whisper::stream::Pass;
    use crate::whisper::ms_to_samples;
    use std::sync::mpsc;

    /// Takes a fixed time per window, answers "hello", and fails on demand.
    struct Slow {
        each: Duration,
        fail: bool,
    }

    impl Transcribe for Slow {
        fn transcribe(&mut self, _: &[f32], _: &str, _: Pass) -> Result<String, String> {
            std::thread::sleep(self.each);
            if self.fail {
                Err("the model fell over".to_string())
            } else {
                Ok("hello".to_string())
            }
        }
    }

    fn loud(ms: u64) -> Vec<f32> {
        (0..ms_to_samples(ms))
            .map(|i| if i % 3520 < 2560 { if i % 2 == 0 { 0.2 } else { -0.2 } } else { 0.0 })
            .collect()
    }

    #[test]
    fn push_returns_at_once_even_while_an_inference_is_running() {
        let abort = Arc::new(AtomicBool::new(false));
        let slow = Slow { each: Duration::from_millis(400), fail: false };
        let capture = Capture::start(slow, Arc::clone(&abort), |_| {});
        let chunk = loud(250);
        let started = std::time::Instant::now();
        for _ in 0..12 {
            capture.push(&chunk);
            std::thread::sleep(Duration::from_millis(25));
        }
        // Twelve pushes and twelve 25 ms sleeps is 300 ms of our own time;
        // anything much past that was a push waiting on the model.
        assert!(started.elapsed() < Duration::from_millis(600), "{:?}", started.elapsed());
        capture.cancel();
    }

    #[test]
    fn stop_commits_what_is_left_and_returns_the_transcript() {
        let abort = Arc::new(AtomicBool::new(false));
        let (tx, rx) = mpsc::channel();
        let capture = Capture::start(
            Slow { each: Duration::from_millis(5), fail: false },
            abort,
            move |event| {
                let _ = tx.send(event);
            },
        );
        capture.push(&loud(1_500));
        let stopped = capture.stop().unwrap();
        let transcript = stopped.transcript;
        assert_eq!(stopped.recording.len(), ms_to_samples(1_500), "the recording is every sample pushed");
        assert_eq!(transcript, "hello");
        let events: Vec<Event> = rx.try_iter().collect();
        assert!(events.iter().any(|e| matches!(e, Event::Segment(s) if s.text == "hello")), "{events:?}");
    }

    #[test]
    fn a_failing_model_is_one_error_event_and_an_error_from_stop() {
        let abort = Arc::new(AtomicBool::new(false));
        let (tx, rx) = mpsc::channel();
        let capture = Capture::start(
            Slow { each: Duration::from_millis(1), fail: true },
            abort,
            move |event| {
                let _ = tx.send(event);
            },
        );
        capture.push(&loud(3_000));
        std::thread::sleep(Duration::from_millis(400));
        assert_eq!(capture.stop().unwrap_err(), "the model fell over");
        let errors = rx.try_iter().filter(|e| matches!(e, Event::Error(_))).count();
        assert_eq!(errors, 1);
    }

    /// Transcribes for a long time unless the abort flag cuts it short.
    struct Abortable {
        abort: Arc<AtomicBool>,
    }

    impl Transcribe for Abortable {
        fn transcribe(&mut self, _: &[f32], _: &str, _: Pass) -> Result<String, String> {
            for _ in 0..500 {
                if self.abort.load(Ordering::Relaxed) {
                    return Err("aborted".to_string());
                }
                std::thread::sleep(Duration::from_millis(10));
            }
            Ok("hello".to_string())
        }
    }

    #[test]
    fn a_rewind_cuts_short_a_running_inference_and_is_not_an_error() {
        let abort = Arc::new(AtomicBool::new(false));
        let (tx, rx) = mpsc::channel();
        let capture = Capture::start(
            Abortable { abort: Arc::clone(&abort) },
            Arc::clone(&abort),
            move |event| {
                let _ = tx.send(event);
            },
        );
        // Long enough speech that a partial is running when the rewind lands.
        capture.push(&loud(3_000));
        std::thread::sleep(Duration::from_millis(300));
        let started = std::time::Instant::now();
        capture
            .rewind(1_000)
            .unwrap()
            .recv_timeout(Duration::from_secs(2))
            .expect("the rewind happened");
        assert!(started.elapsed() < Duration::from_millis(1_000), "{:?}", started.elapsed());
        assert!(!abort.load(Ordering::Relaxed), "the flag is cleared for the next inference");

        let events: Vec<Event> = rx.try_iter().collect();
        assert!(events.iter().any(|e| matches!(e, Event::Rewound(r) if r.to_ms == 1_000)), "{events:?}");
        assert!(!events.iter().any(|e| matches!(e, Event::Error(_))), "{events:?}");
        capture.cancel();
    }

    #[test]
    fn a_rewind_on_an_ended_capture_is_refused_and_its_waiter_is_released() {
        let abort = Arc::new(AtomicBool::new(false));
        let capture = Capture::start(Slow { each: Duration::from_millis(1), fail: true }, abort, |_| {});
        capture.push(&loud(3_000));
        std::thread::sleep(Duration::from_millis(400));
        // The model failed, so the worker has exited.
        assert!(capture.rewind(500).is_err());
        let _ = capture.stop();
    }

    #[test]
    fn dropping_a_capture_cancels_it_and_joins_the_thread() {
        let abort = Arc::new(AtomicBool::new(false));
        let capture = Capture::start(
            Slow { each: Duration::from_millis(1), fail: false },
            Arc::clone(&abort),
            |_| {},
        );
        capture.push(&loud(500));
        drop(capture);
        assert!(abort.load(Ordering::Relaxed), "the abort flag is how a running decode is cut short");
    }
}
