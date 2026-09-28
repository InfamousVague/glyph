//! A meeting's write-up, with the app closed: the recording finished, its
//! speech transcribed one span at a time, the transcript put into the note,
//! the summary written by the model, and a result left for the page to take.
//! NOT ONE `tauri::` TYPE, for the reason note.rs gives: this is reached over
//! JNI (`recording_jobs.rs`) from a foreground service or a WorkManager job
//! with no Tauri in the process, and it takes the app's data directory as a
//! path (DESIGN §127 section 4).
//!
//! THREE DOORS. `finish` is called once, at Stop: the header the meeting
//! service left short is put right, the note learns its length, and a `queued`
//! progress file is written; it deletes nothing, and any error after the file
//! is written goes into the file, so the sweep retries it. `run` is called by
//! the service straight after, and by the worker for every retry: it resumes
//! from the progress file's checkpoints (the spans found, the phrases so far,
//! the notes on each piece) and answers with how far it got. `cancel` is what
//! Kotlin calls when the person, the heat, Android's budget or a new meeting
//! ends a run: the run stops within one graph computation and says why.
//!
//! WHAT A RUN HOLDS IN MEMORY: one span's audio (at most 28 s) and whisper,
//! then the model and one piece's context - never the hour. The whisper engine
//! and the audio are dropped before the model loads.
//!
//! WHAT IT REFUSES. A capture in progress ("capturing": the person talking
//! gets the cores), a refine pass or another write-up holding the one small.en
//! ("busy"), the battery rule from Settings ("battery"), heat ("thermal"). Each
//! is a hold, not a failure: the progress file says `waiting` and why, and the
//! chain retries. Only an error counts, and after `MAX_TRIES` of those the job
//! is `failed`.
//!
//! THE MODELS. Speech is transcribed with `whisper::model::REFINE` (small.en),
//! the model the refine pass uses, or with the live model (base.en) when only
//! that is on the phone; the summary comes from the language model the page
//! chose (`jobs/config.json`), and with none on the phone the job ends
//! `needsModel` and never downloads. The summary prompts are the page's, read
//! from the config, with a compiled-in copy (`prompts`) for a fresh install
//! whose page has not run yet; a test in llm/tests.rs keeps the copy equal to
//! the page's literal.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};

use crate::guards;
use crate::jobs::{self, JobConfig, JobResult, Phase, Progress, Prompts};
use crate::library::Library;
use crate::llm::engine::{Failure, Request};
use crate::llm::model::LlmSpec;
use crate::lock::lock;
use crate::note::{now_ms, Recording};
use crate::whisper::engine::{whisper_threads, Engine, Session};
use crate::whisper::{model as whisper_model, samples_to_ms, spans, text, wav};

/// Under the default Write up setting, a meeting stopped on battery below this
/// is not written up until the phone charges or is above it.
pub const WRITE_UP_BATTERY: u8 = 50;

/// Counted failures before a job is `failed`. A hold is not one.
pub const MAX_TRIES: u32 = 3;

/// How long `cancel` waits for a run to clear before it marks the file itself.
pub const CANCEL_WAIT: Duration = Duration::from_secs(5);

/// The thermal words (Kotlin's `WriteUp.thermalWord`, from
/// `PowerManager.currentThermalStatus`) at which a run does not start: severe
/// and worse. A test reads each in the Kotlin, so a word renamed there cannot
/// quietly become "none" here.
pub const HOT: [&str; 4] = ["severe", "critical", "emergency", "shutdown"];

/// How much of the previous span rides along as the next one's prompt.
const TAIL_CHARS: usize = 200;

/// How often the watcher rewrites `percent` while a span decodes.
const PROGRESS_EVERY: Duration = Duration::from_secs(2);

/// The page's prompts, compiled in for a phone whose page has not written
/// `jobs/config.json` yet. Each must equal the page's `String.raw` literal in
/// src/app/format/prompt.ts word for word; `llm::tests` reads them by name and
/// says so.
pub mod prompts {
    /// `RECORDING_SUMMARY_PROMPT`.
    pub const SUMMARY: &str = r#"You are the editor inside Ghost.md, a notes app. You receive the words of one recording, exactly as they were transcribed, and you write a short summary of it for the person who recorded it: what was said, what was decided, and what they have to do.

Keep, without exception:
- Only what the recording says. Nothing is added; if it was not said, you do not say it. No guesses about what was meant.
- Names and words you are not sure of, spelled as the recording spells them.
- Every link. You receive links as [the words](link-1) or <link-2>: keep each one exactly as written, its link-1 target included. Never write out an address.
- Who said they would do what. A thing someone else is doing is theirs, never the person recording's.

Write, in this order and nothing else:
- The first line is a level 1 heading (#) that names the recording in its own words: what it was about, or what it was called.
- Then one sentence saying what the recording is. Who was there only if the recording says so.
- Then three to eight points, each its own "- " item of a few words: the things that were said that matter. Other people's actions are points, with the name first, like "- Sam: the press list by Friday." Never a task item: a box is only for the person recording.
- Then, only where something was decided, each decision as its own "- " item beginning "Decided: ".
- Then the things the person recording has to do, said as I, we, my, or their own name: each its own task item, "- [ ] " followed by the task in under ten words, with its when where one was said.
- Short: at most a fifth of the recording's words, and never more than about two hundred. A recording of a few words gets a heading, one sentence and one or two items.

Example. The recording:
ok so that's the March launch settled, we're going with the second week. Sam you'll own the press list, yes? Great. and the site copy is still open, I'll take a first pass at that by Friday. one thing we did decide, no paid ads until the beta closes. and I need to book the venue before the tenth

Its summary:
# March launch settled
A call that fixed the launch date and who does what next.

- The launch is in the second week of March.
- The site copy is still open.
- Sam: the press list.

- Decided: no paid ads until the beta closes.

- [ ] First pass at the site copy by Friday.
- [ ] Book the venue before the tenth.

Plain markdown only: no emoji, no tables, no horizontal rules, no "*" bullets, no numbered lists, no other headings, no labels like "Summary" or "Action items". The answer is the summary and nothing else: no introduction, no explanation, no closing remark, no code fence around it."#;

    /// `RECORDING_NOTES_PROMPT`.
    pub const NOTES: &str = r#"You are the editor inside Ghost.md, a notes app. You receive one part of a long recording, exactly as it was transcribed, and you write notes on that part alone: the points, the decisions and the things to do in it, as items, nothing else.

Keep, without exception:
- Only what this part says. Nothing is added; if it was not said, you do not say it.
- Names and words you are not sure of, spelled as the recording spells them.
- Every link, exactly as written, as [the words](link-1) or <link-2>. Never write out an address.

Write, and nothing else:
- Each thing said that matters as its own "- " item of a few words.
- Each decision as its own "- " item beginning "Decided: ".
- Each thing the person recording has to do, said as I, we, my, or their own name, as its own task item, "- [ ] " followed by the task in under ten words, with its when where one was said.
- Other people's actions as "- " items with the name first, like "- Sam: the press list by Friday." Never a task item.
- At most twelve items for this part. No heading, no numbered lists, no sentence before the items, no closing remark, no code fence."#;

    /// `PIECE_CONTEXT`: the line before each piece, in its prompt.
    pub const PIECE: &str = "Part {n} of {m} of one recording.";

    /// `NOTES_CONTEXT`: the context of the final pass over the joined notes.
    pub const PARTS: &str = "These are notes on the parts of one recording, in order. The recording itself was about {words} words: the summary's length is measured against that, not against these notes.";
}

/// `template` with each `{name}` replaced by its value: the twin of the page's
/// `fill`, so the two sides build the same line from the same template.
pub fn fill(template: &str, values: &[(&str, &str)]) -> String {
    values.iter().fold(template.to_string(), |text, (name, value)| text.replace(&format!("{{{name}}}"), value))
}

/// `n` with a comma every three digits: what the page's
/// `toLocaleString('en')` writes into the parts line.
pub fn thousands(n: usize) -> String {
    let digits = n.to_string();
    let mut out = String::with_capacity(digits.len() + digits.len() / 3);
    for (i, c) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i).is_multiple_of(3) {
            out.push(',');
        }
        out.push(c);
    }
    out
}

/// How much room the summary gets, from the transcript's length: the page's
/// `recordingSummaryBudget`.
pub fn summary_budget(chars: usize) -> u32 {
    let tokens = chars.div_ceil(4);
    (tokens.div_ceil(6) + 96).clamp(200, 1024) as u32
}

/// How much room the notes on one piece get: the page's `recordingNotesBudget`.
pub fn notes_budget(chars: usize) -> u32 {
    let tokens = chars.div_ceil(4);
    (tokens.div_ceil(4) + 64).clamp(128, 512) as u32
}

/// The first line of the model's answer that is not blank, a `#` heading or an
/// item: the sentence the notification shows, as the page's `summaryLine`
/// finds it once the section is written.
pub fn summary_line(answer: &str) -> Option<String> {
    answer
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty() && !line.starts_with('#') && !line.starts_with("- ") && !line.starts_with("* "))
        .map(str::to_string)
}

/// What Kotlin passes `run`, from the phone as it is at that moment. Its keys
/// are the ones `WriteUp.options` puts, and a test holds the two lists equal.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Options {
    /// Write up now: the battery rule does not hold it.
    pub now: bool,
    /// Try again: a `cancelled`, `failed` or `needsModel` file is queued again.
    pub fresh: bool,
    /// When a `fresh` request was made (ms since the epoch). WorkManager
    /// retries a request with the same input after every hold, so a cancel
    /// made after the request (the meeting put in the trash while it waited)
    /// must win over it: `fresh` reopens a `cancelled` file only when the
    /// cancel is older than this. `None` is a request from before the fence,
    /// which reopens as it always did.
    pub requested_at: Option<i64>,
    /// The note's title as recorded, for a progress file that has to be made.
    pub title: Option<String>,
    pub charging: bool,
    pub battery_percent: u8,
    /// `PowerManager.currentThermalStatus` as a word: `none` to `shutdown`.
    pub thermal: String,
    /// The app is in front (somebody may be typing): the write-up takes half the cores.
    pub app_in_front: bool,
}

impl Default for Options {
    fn default() -> Options {
        Options { now: false, fresh: false, requested_at: None, title: None, charging: false, battery_percent: 100, thermal: "none".into(), app_in_front: false }
    }
}

/// What `run` answers, as JSON to Kotlin (`to_json`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Answer {
    /// Written up: the notification's words.
    Done { title: String, line: Option<String>, transcript_chars: usize, summary: bool },
    /// The file says `done` already; nothing to post.
    AlreadyDone,
    /// A partial: the file holds what is done, `waiting` and why. Only an
    /// error sentence counts as a try.
    Retry(String),
    /// The language model is not on the phone; `again` when the file already said so.
    NeedsModel { id: String, again: bool },
    /// `failed`, after `MAX_TRIES`; `again` on a later look at the same failure.
    Error { message: String, again: bool },
    /// The file says `cancelled`, or a cancel ended this run.
    Cancelled,
    /// No recording for the id: nothing to do, and the file is removed.
    Gone,
}

impl Answer {
    /// The shapes in DESIGN §127 section 4, one key each.
    pub fn to_json(&self) -> String {
        let value = match self {
            Answer::Done { title, line, transcript_chars, summary } => {
                serde_json::json!({ "done": true, "title": title, "line": line, "transcriptChars": transcript_chars, "summary": summary })
            }
            Answer::AlreadyDone => serde_json::json!({ "alreadyDone": true }),
            Answer::Retry(reason) => serde_json::json!({ "retry": reason }),
            Answer::NeedsModel { id, again } => serde_json::json!({ "needsModel": id, "again": again }),
            Answer::Error { message, again } => serde_json::json!({ "error": message, "again": again }),
            Answer::Cancelled => serde_json::json!({ "cancelled": true }),
            Answer::Gone => serde_json::json!({ "gone": true }),
        };
        value.to_string()
    }
}

/// The directories under the app's data directory, the names `paths.rs` gives them.
struct Dirs {
    recordings: PathBuf,
    models: PathBuf,
    library: PathBuf,
    jobs: PathBuf,
}

impl Dirs {
    fn of(data_dir: &Path) -> Dirs {
        Dirs {
            recordings: data_dir.join(crate::paths::RECORDINGS),
            models: data_dir.join(crate::paths::MODELS),
            library: data_dir.join(crate::paths::LIBRARY),
            jobs: jobs::dir(data_dir),
        }
    }
}

/// `jobs/config.json` with its blanks filled: what the page would have sent.
struct Config {
    model: String,
    prompts: Prompts,
    one_pass_chars: usize,
    piece_chars: usize,
    temperature: f32,
    write_up: String,
    summaries: String,
}

impl Config {
    fn read(jobs: &Path) -> Config {
        let raw: JobConfig = crate::fsx::read_json_or(&jobs::config_path(jobs), JobConfig::default());
        let or = |value: String, fallback: &str| if value.trim().is_empty() { fallback.to_string() } else { value };
        Config {
            model: or(raw.model, crate::llm::model::DEFAULT.id),
            prompts: Prompts {
                summary: or(raw.prompts.summary, prompts::SUMMARY),
                notes: or(raw.prompts.notes, prompts::NOTES),
                piece: or(raw.prompts.piece, prompts::PIECE),
                parts: or(raw.prompts.parts, prompts::PARTS),
            },
            one_pass_chars: if raw.one_pass_chars == 0 { 20_000 } else { raw.one_pass_chars },
            piece_chars: if raw.piece_chars == 0 { 12_000 } else { raw.piece_chars },
            temperature: if raw.temperature <= 0.0 { 0.3 } else { raw.temperature },
            write_up: or(raw.write_up, "charging"),
            summaries: or(raw.summaries, "meetings"),
        }
    }
}

/// The note's title from its body: its first line without the `#`, or
/// "Meeting" for a note with none.
fn title_of(body: &str) -> String {
    let title = body.lines().map(|line| line.trim().trim_start_matches('#').trim()).find(|line| !line.is_empty()).unwrap_or("");
    if title.is_empty() { "Meeting".to_string() } else { title.to_string() }
}

/// The note's title as the library has it, for a progress file made without
/// one; "Meeting" when the library cannot say.
fn note_title(library: &Path, id: &str) -> String {
    Library::open_fs(library)
        .ok()
        .and_then(|mut library| library.get_note(id).ok().flatten())
        .map(|note| title_of(&note.body))
        .unwrap_or_else(|| "Meeting".to_string())
}

/// Closes a recording: a `queued` progress file, the header put right, the
/// note's length recorded. Answers the recording's length. Deletes nothing:
/// any error after the file is written goes into it, the phase stays
/// `queued`, and the worker's `run` repeats these steps.
pub fn finish(data_dir: &Path, id: &str, title: &str) -> Result<u64, String> {
    let dirs = Dirs::of(data_dir);
    let wav_path = crate::recordings::recording_file(&dirs.recordings, id).ok_or_else(|| "not a note id".to_string())?;
    let path = jobs::progress_path(&dirs.jobs, id);
    let mut progress = Progress::queued(id, title);
    progress.save(&path, true)?;
    let measured = (|| -> Result<u64, String> {
        let samples = wav::patch_header(&wav_path)?;
        let ms = samples_to_ms(samples);
        let mut library = Library::open_fs(&dirs.library).map_err(|e| e.to_string())?;
        let recording = Recording::new(ms as i64, Vec::new())?;
        library.set_recording(id, Some(&recording)).map_err(|e| e.to_string())?.ok_or_else(|| "no such note".to_string())?;
        Ok(ms)
    })();
    match &measured {
        Ok(ms) => progress.recorded_ms = Some(*ms),
        Err(message) => progress.error = Some(message.clone()),
    }
    progress.save(&path, false)?;
    measured
}

/// Ends a run for `id` with `reason`. For `"cancel"` the file is marked
/// `cancelled` too, once the run has cleared or `CANCEL_WAIT` has passed, so
/// the trash and the notification's Discard hold whatever the run does next.
/// A `done` file is left as it is: its result waits in `<id>.json` for the
/// page, and a meeting put in the trash and brought back lands it then rather
/// than being written up a second time. Never takes `WRITE_UP`, so it answers
/// while a refine pass holds it.
pub fn cancel(data_dir: &Path, id: &str, reason: &str) -> bool {
    let running = lock(&guards::RUNNING_JOB).as_deref() == Some(id);
    if running {
        guards::abort_with(reason);
    }
    if reason == "cancel" {
        let deadline = Instant::now() + CANCEL_WAIT;
        while lock(&guards::RUNNING_JOB).as_deref() == Some(id) && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(50));
        }
        let path = jobs::progress_path(&jobs::dir(data_dir), id);
        if let Some(mut progress) = Progress::load(&path).filter(|progress| progress.phase != Phase::Done) {
            progress.phase = Phase::Cancelled;
            progress.waiting_for = None;
            let _ = progress.save(&path, false);
        }
    }
    running
}

/// Why a run stopped short of done.
enum Stop {
    /// Held, and retried later, uncounted: the reason for `waiting_for`.
    Hold(String),
    /// An error, counted.
    Failed(String),
    /// The language model is not on the phone.
    NeedsModel(String),
    /// A cancel ended it, or the file says `cancelled`.
    Cancelled,
}

/// `guards::RUNNING_JOB` set for the run, cleared however it ends.
struct RunningJob;

impl RunningJob {
    fn set(id: &str) -> RunningJob {
        *lock(&guards::RUNNING_JOB) = Some(id.to_string());
        RunningJob
    }
}

impl Drop for RunningJob {
    fn drop(&mut self) {
        *lock(&guards::RUNNING_JOB) = None;
    }
}

/// The language model a run's summary is written with: where its file is, and
/// the cores it takes this run (`llm::threads_for`).
struct Writer {
    path: PathBuf,
    threads: i32,
}

/// One run, from the progress file to an answer.
struct Run<'a> {
    dirs: Dirs,
    id: &'a str,
    options: &'a Options,
    wav: PathBuf,
    path: PathBuf,
    progress: Progress,
    config: Config,
    abort: Arc<AtomicBool>,
}

/// Writes up note `id`'s recording as far as it can this time; see the module
/// header for what it refuses and why.
pub fn run(data_dir: &Path, id: &str, options: &Options) -> Answer {
    let dirs = Dirs::of(data_dir);
    let Some(wav_path) = crate::recordings::recording_file(&dirs.recordings, id) else {
        return Answer::Error { message: "not a note id".into(), again: false };
    };
    let path = jobs::progress_path(&dirs.jobs, id);
    if !wav_path.is_file() {
        let _one = lock(&guards::PROGRESS_FILE);
        let _ = crate::fsx::remove_file_if_present(&path);
        return Answer::Gone;
    }
    let mut progress = match Progress::load(&path) {
        Some(progress) => progress,
        None => Progress::queued(id, &options.title.clone().unwrap_or_else(|| note_title(&dirs.library, id))),
    };

    // The phase, settled before anything runs (DESIGN §127 section 4's rule for a terminal file),
    // and before the holds below, so a `done` file looked at during a capture is still done.
    // A `needsModel` file looked at again without `fresh` says so a second time (`again`), and
    // Kotlin posts nothing; Try again after a download is a fresh look, and the answer is new.
    let was_needs_model = progress.phase == Phase::NeedsModel && !options.fresh;
    // A cancel made after this fresh request was asked for: the request's retry must not undo it.
    let cancelled_since = options.requested_at.is_some_and(|asked| progress.updated_at > asked);
    let mut fresh = false;
    match progress.phase {
        Phase::Done => return Answer::AlreadyDone,
        Phase::Cancelled if cancelled_since => return Answer::Cancelled,
        Phase::Cancelled | Phase::Failed | Phase::NeedsModel if options.fresh => {
            progress.tries = 0;
            progress.phase = Phase::Queued;
            progress.error = None;
            progress.waiting_for = None;
            fresh = true;
        }
        Phase::Cancelled => return Answer::Cancelled,
        Phase::Failed if progress.tries >= MAX_TRIES => {
            return Answer::Error { message: progress.error.clone().unwrap_or_else(|| "The meeting could not be written up.".into()), again: true };
        }
        _ => {}
    }
    if let Err(e) = progress.save(&path, fresh) {
        return Answer::Retry(e);
    }
    if guards::capturing() {
        return hold(&mut progress, &path, "capturing", None);
    }
    let Some(_write_up) = guards::try_write_up() else {
        return hold(&mut progress, &path, "busy", None);
    };

    let config = Config::read(&dirs.jobs);
    if !options.now && config.write_up == "charging" && !options.charging && options.battery_percent < WRITE_UP_BATTERY {
        return hold(&mut progress, &path, "battery", None);
    }
    if HOT.contains(&options.thermal.as_str()) {
        return hold(&mut progress, &path, "thermal", None);
    }

    guards::clear_abort();
    let _running = RunningJob::set(id);
    // A dictation that began between the check above and `clear_abort` raised
    // the flag this run just lowered; it counts as starting from the moment it
    // raised it (`guards::capturing`), so it is seen here instead.
    if guards::capturing() {
        return hold(&mut progress, &path, "capturing", None);
    }
    let mut run = Run { dirs, id, options, wav: wav_path, path: path.clone(), progress, config, abort: guards::abort_jobs() };
    let outcome = run.go();
    let Run { mut progress, .. } = run;
    match outcome {
        Ok(answer) => answer,
        Err(Stop::Cancelled) => Answer::Cancelled,
        Err(Stop::Hold(reason)) if reason == "cancel" => Answer::Cancelled,
        Err(Stop::Hold(reason)) => hold(&mut progress, &path, &reason, None),
        Err(Stop::NeedsModel(model)) => {
            progress.phase = Phase::NeedsModel;
            progress.waiting_for = None;
            match progress.save(&path, false) {
                Ok(true) => Answer::NeedsModel { id: model, again: was_needs_model },
                Ok(false) => Answer::Cancelled,
                Err(e) => Answer::Retry(e),
            }
        }
        Err(Stop::Failed(message)) => {
            progress.tries += 1;
            if progress.tries < MAX_TRIES {
                return hold(&mut progress, &path, "error", Some(message));
            }
            progress.phase = Phase::Failed;
            progress.waiting_for = None;
            progress.error = Some(message.clone());
            match progress.save(&path, false) {
                Ok(true) => Answer::Error { message, again: false },
                Ok(false) => Answer::Cancelled,
                Err(e) => Answer::Retry(e),
            }
        }
    }
}

/// The file marked `waiting` for `reason` (an error's sentence kept beside
/// it), and the answer that says so: the sentence for an error, the reason
/// otherwise. A file that has gone `cancelled` meanwhile is left as it is.
fn hold(progress: &mut Progress, path: &Path, reason: &str, error: Option<String>) -> Answer {
    progress.phase = Phase::Waiting;
    progress.waiting_for = Some(reason.to_string());
    let answer = error.clone().unwrap_or_else(|| reason.to_string());
    progress.error = error;
    match progress.save(path, false) {
        Ok(false) => Answer::Cancelled,
        _ => Answer::Retry(answer),
    }
}

impl Run<'_> {
    /// Writes the progress as it stands; a file gone `cancelled` under the run
    /// ends it.
    fn checkpoint(&self) -> Result<(), Stop> {
        match self.progress.save(&self.path, false) {
            Ok(true) => Ok(()),
            Ok(false) => Err(Stop::Cancelled),
            Err(e) => Err(Stop::Failed(e)),
        }
    }

    /// Why the abort flag was raised, as a stop.
    fn stopped(&self) -> Stop {
        let reason = guards::abort_reason();
        if reason == "cancel" { Stop::Cancelled } else { Stop::Hold(reason) }
    }

    /// Between spans and pieces: a capture that has started, or the flag.
    fn check(&self) -> Result<(), Stop> {
        if self.abort.load(Ordering::SeqCst) {
            return Err(self.stopped());
        }
        if guards::capturing() {
            return Err(Stop::Hold("capturing".into()));
        }
        Ok(())
    }

    /// The four steps in order, each skipped where the file says it is done.
    fn go(&mut self) -> Result<Answer, Stop> {
        // A queued file, or one whose `finish` never got as far as measuring
        // the recording before a hold put it to `waiting`: the header would
        // stay short and the tape would play short.
        if self.progress.phase == Phase::Queued || self.progress.recorded_ms.is_none() {
            self.repeat_finish()?;
        }
        if self.progress.transcript.is_none() && !self.kept_transcript()? {
            self.listen()?;
            self.write_note()?;
        }
        let summary = self.summarize()?;
        self.done(summary)
    }

    /// `finish`'s steps again, each only where it is not already done, for a
    /// `queued` file whose `finish` failed part way (or was never called: a
    /// meeting a kill left unfinished, found by the sweep).
    fn repeat_finish(&mut self) -> Result<(), Stop> {
        let samples = wav::patch_header(&self.wav).map_err(Stop::Failed)?;
        let ms = samples_to_ms(samples);
        let mut library = Library::open_fs(&self.dirs.library).map_err(|e| Stop::Failed(e.to_string()))?;
        let note = library.get_note(self.id).map_err(|e| Stop::Failed(e.to_string()))?.ok_or_else(|| Stop::Failed("no such note".into()))?;
        if note.recording_ms != Some(ms as i64) {
            let recording = Recording::new(ms as i64, self.progress.segments.clone()).map_err(Stop::Failed)?;
            library.set_recording(self.id, Some(&recording)).map_err(|e| Stop::Failed(e.to_string()))?;
        }
        self.progress.recorded_ms = Some(ms);
        self.progress.error = None;
        Ok(())
    }

    /// A job with nothing listened to yet, for a note that already has its
    /// transcript (a write-up asked again after the page took the last
    /// result): the words there are the transcript, as the person may have
    /// corrected them. Listening again would take an hour's decoding to
    /// replace them, and everything after the heading, with the machine's.
    fn kept_transcript(&mut self) -> Result<bool, Stop> {
        if self.progress.spans.is_some() || !self.progress.segments.is_empty() {
            return Ok(false);
        }
        let mut library = Library::open_fs(&self.dirs.library).map_err(|e| Stop::Failed(e.to_string()))?;
        let note = library.get_note(self.id).map_err(|e| Stop::Failed(e.to_string()))?.ok_or_else(|| Stop::Failed("no such note".into()))?;
        let Some(words) = crate::transcript::words_of(&note.body) else { return Ok(false) };
        self.progress.transcript_chars = words.chars().count();
        self.progress.transcript = Some(words);
        self.progress.spans = Some(Vec::new());
        self.progress.percent = 100;
        self.checkpoint()?;
        Ok(true)
    }

    /// The whisper model for the transcript: small.en, or base.en when only
    /// that is here. Neither is `needsModel`, by the whisper file's name.
    fn whisper_model(&self) -> Result<PathBuf, Stop> {
        for spec in [&whisper_model::REFINE, &whisper_model::ACTIVE] {
            let status = crate::model_files::status(&self.dirs.models, spec);
            if status.present {
                return Ok(PathBuf::from(status.path));
            }
        }
        Err(Stop::NeedsModel(whisper_model::REFINE.file.to_string()))
    }

    /// Step one: the speech spans found, then each transcribed with the
    /// previous one's tail as its prompt, checkpointed after every span.
    fn listen(&mut self) -> Result<(), Stop> {
        if self.progress.spans.is_none() {
            let found = spans::find(&self.wav).map_err(Stop::Failed)?;
            self.progress.spans = Some(found);
            self.progress.spans_done = 0;
            self.progress.segments.clear();
        }
        self.progress.phase = Phase::Listening;
        self.progress.waiting_for = None;
        self.checkpoint()?;
        let spans = self.progress.spans.clone().unwrap_or_default();
        if self.progress.spans_done >= spans.len() {
            self.progress.percent = 100;
            return Ok(());
        }
        let speech_total: u64 = spans.iter().map(|(from, to)| to - from).sum::<u64>().max(1);
        let threads = if self.options.app_in_front { guards::background_threads(whisper_threads()) } else { whisper_threads() };
        let model_path = self.whisper_model()?;
        let engine = Arc::new(Engine::load_with_threads(&model_path, threads).map_err(Stop::Failed)?);
        let mut session = Session::new(engine, Arc::clone(&self.abort)).map_err(Stop::Failed)?;
        // The words so far, for the next span's prompt; only the tail is kept.
        let mut committed: String = self.progress.segments.iter().map(|s| s.text.as_str()).collect::<Vec<_>>().join(" ");
        for (index, (from, to)) in spans.iter().copied().enumerate().skip(self.progress.spans_done) {
            self.check()?;
            let audio = wav::read_span(&self.wav, from, to).map_err(Stop::Failed)?;
            let speech_done: u64 = spans[..index].iter().map(|(from, to)| to - from).sum();
            let prompt = text::prompt_plain(&committed, TAIL_CHARS);
            let decoding = AtomicI32::new(0);
            let finished = AtomicBool::new(false);
            let snapshot = self.progress.clone();
            let timed = std::thread::scope(|scope| {
                // A watcher beside the decode keeps the file's percent fresh
                // for the notification, and never writes over a cancel.
                scope.spawn(|| {
                    let mut last = snapshot.percent;
                    while !finished.load(Ordering::Relaxed) {
                        let started = Instant::now();
                        while !finished.load(Ordering::Relaxed) && started.elapsed() < PROGRESS_EVERY {
                            std::thread::sleep(Duration::from_millis(100));
                        }
                        let within = (to - from) * decoding.load(Ordering::Relaxed).clamp(0, 100) as u64 / 100;
                        let percent = ((speech_done + within) * 100 / speech_total).min(100) as u32;
                        if percent != last && !finished.load(Ordering::Relaxed) && !self.abort.load(Ordering::Relaxed) {
                            last = percent;
                            let mut fresh = snapshot.clone();
                            fresh.percent = percent;
                            let _ = fresh.save(&self.path, false);
                        }
                    }
                });
                let timed = session.transcribe_timed(&audio, &prompt, &decoding);
                finished.store(true, Ordering::Relaxed);
                timed
            });
            let timed = match timed {
                Ok(timed) => timed,
                Err(_) if self.abort.load(Ordering::SeqCst) => return Err(self.stopped()),
                Err(message) => return Err(Stop::Failed(message)),
            };
            for phrase in timed {
                if !committed.is_empty() {
                    committed.push(' ');
                }
                committed.push_str(&phrase.text);
                self.progress.segments.push(phrase.offset(from));
            }
            if committed.len() > 4 * TAIL_CHARS {
                let cut = (committed.len() - 2 * TAIL_CHARS..committed.len()).find(|at| committed.is_char_boundary(*at)).unwrap_or(0);
                committed.drain(..cut);
            }
            self.progress.spans_done = index + 1;
            self.progress.percent = ((speech_done + (to - from)) * 100 / speech_total).min(100) as u32;
            self.checkpoint()?;
        }
        // The engine and the audio go before the language model loads.
        drop(session);
        Ok(())
    }

    /// Step two: the phrases beside the note, and the transcript into its body
    /// under the library's guard: a conflict is read again once, then held.
    fn write_note(&mut self) -> Result<(), Stop> {
        let failed = |e: crate::library::LibraryError| Stop::Failed(e.to_string());
        let ms = wav::duration_ms(&self.wav).map_err(Stop::Failed)?;
        let recording = Recording::new(ms as i64, self.progress.segments.clone()).map_err(Stop::Failed)?;
        let mut library = Library::open_fs(&self.dirs.library).map_err(failed)?;
        library.set_recording(self.id, Some(&recording)).map_err(failed)?.ok_or_else(|| Stop::Failed("no such note".into()))?;
        let paragraphs = crate::transcript::paragraphs(&self.progress.segments);
        let mut written = None;
        for _ in 0..2 {
            let note = library.get_note(self.id).map_err(failed)?.ok_or_else(|| Stop::Failed("no such note".into()))?;
            let body = crate::transcript::with_transcript(&note.body, &paragraphs);
            written = library.update_note(self.id, &body, note.revision).map_err(failed)?;
            if written.is_some() {
                break;
            }
        }
        if written.is_none() {
            return Err(Stop::Hold("conflict".into()));
        }
        let transcript = paragraphs.join("\n\n");
        self.progress.transcript_chars = transcript.chars().count();
        self.progress.transcript = Some(transcript);
        self.progress.segments.clear();
        self.progress.recorded_ms = Some(ms);
        self.checkpoint()
    }

    /// One generation on the shared worker, as a background job, with the
    /// cores the app's state allows.
    fn ask(&self, writer: &Writer, what: &str, system: &str, context: Option<String>, prompt: String, max_tokens: u32) -> Result<String, Stop> {
        self.check()?;
        let request = Request {
            id: format!("write-up:{}:{what}", self.id),
            system: system.to_string(),
            context,
            prompt,
            max_tokens,
            temperature: self.config.temperature,
            think: false,
            think_budget: 0,
            grammar: None,
            background: true,
        };
        #[cfg(test)]
        if let Some(answer) = tests::STAND_IN.with(|stand_in| stand_in.borrow_mut().as_mut().map(|answer| answer(&request))) {
            return answer.map_err(Stop::Failed);
        }
        let answer = crate::llm::shared().generate_with_threads(&writer.path, request, writer.threads, Arc::clone(&self.abort), |_| {});
        match answer.recv() {
            Ok(Ok(output)) => Ok(output.text),
            Ok(Err(Failure::Cancelled)) => Err(self.stopped()),
            Ok(Err(Failure::Error(message))) => Err(Stop::Failed(message)),
            Err(_) => Err(Stop::Failed("the formatting engine went away".into())),
        }
    }

    /// Step three: the summary, in one pass or piece by piece with each piece's
    /// notes checkpointed; `None` with summaries off, and `None` when nothing
    /// was heard: a model asked to summarise an empty transcript writes one
    /// anyway, and the prompt's first rule is that nothing is invented (the
    /// page's own queue leaves a tape with no words the same way).
    fn summarize(&mut self) -> Result<Option<String>, Stop> {
        if self.config.summaries == "off" {
            return Ok(None);
        }
        if self.progress.transcript.as_deref().is_none_or(|words| words.trim().is_empty()) {
            return Ok(None);
        }
        // The config's model, else the one the page's rule would pick from what is here (`model_for`): a model
        // downloaded since the page last wrote the config is used rather than the job ending needsModel again.
        let present: Vec<&'static LlmSpec> = crate::llm::model::CATALOGUE.iter().filter(|spec| crate::model_files::status(&self.dirs.models, &spec.spec).present).collect();
        let Some(spec) = crate::llm::model::model_for(&present, &self.config.model) else {
            return Err(Stop::NeedsModel(self.config.model.clone()));
        };
        let status = crate::model_files::status(&self.dirs.models, &spec.spec);
        let writer = Writer { path: PathBuf::from(status.path), threads: crate::llm::threads_for(self.options.app_in_front) };
        self.progress.phase = Phase::Summarizing;
        self.progress.waiting_for = None;
        self.progress.model = Some(spec.id.to_string());
        self.progress.percent = 0;
        self.checkpoint()?;
        let transcript = self.progress.transcript.clone().unwrap_or_default();
        let chars = self.progress.transcript_chars;
        let summary = if chars <= self.config.one_pass_chars {
            self.ask(&writer, "summary", &self.config.prompts.summary, None, transcript, summary_budget(chars))?
        } else {
            let pieces = crate::transcript::pieces(&transcript, self.config.piece_chars);
            let count = pieces.len();
            for (n, piece) in pieces.iter().enumerate() {
                if n < self.progress.pieces.len() {
                    continue;
                }
                let line = fill(&self.config.prompts.piece, &[("n", &(n + 1).to_string()), ("m", &count.to_string())]);
                let notes = self.ask(&writer, &format!("piece-{}", n + 1), &self.config.prompts.notes, None, format!("{line}\n\n{piece}"), notes_budget(piece.chars().count()))?;
                self.progress.pieces.push(notes);
                self.progress.percent = ((n + 1) * 100 / (count + 1)) as u32;
                self.checkpoint()?;
            }
            let words = transcript.split_whitespace().count();
            let context = fill(&self.config.prompts.parts, &[("words", &thousands(words))]);
            let notes = self.progress.pieces.join("\n\n");
            self.ask(&writer, "summary", &self.config.prompts.summary, Some(context), notes, summary_budget(chars))?
        };
        Ok(Some(summary))
    }

    /// Step four: the result for the page, the file `done`, the model let go.
    fn done(&mut self, summary: Option<String>) -> Result<Answer, Stop> {
        let model = self.progress.model.clone().unwrap_or_else(|| self.config.model.clone());
        let result = JobResult { summary: summary.clone(), model, transcript_chars: self.progress.transcript_chars, finished_at: now_ms() };
        let json = serde_json::to_vec(&result).map_err(|e| Stop::Failed(e.to_string()))?;
        crate::fsx::make_dir(&self.dirs.jobs).map_err(Stop::Failed)?;
        crate::fsx::write_atomically(&jobs::result_path(&self.dirs.jobs, self.id), &json).map_err(|e| Stop::Failed(format!("the result could not be written: {e}")))?;
        self.progress.phase = Phase::Done;
        self.progress.percent = 100;
        self.progress.waiting_for = None;
        self.progress.error = None;
        self.checkpoint()?;
        if summary.is_some() {
            if let Some(llm) = crate::llm::started() {
                llm.unload();
            }
        }
        Ok(Answer::Done {
            title: self.progress.title.clone(),
            line: summary.as_deref().and_then(summary_line),
            transcript_chars: self.progress.transcript_chars,
            summary: summary.is_some(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::guards::TEST_SERIAL;
    use crate::llm::model::{QWEN3_5_2B, QWEN3_5_4B};
    use crate::test_support::TempDir;
    use std::cell::RefCell;
    use std::collections::BTreeSet;
    use std::rc::Rc;

    /// Takes the place of the language model while a test holds it: `Run::ask`
    /// hands it the request it would have sent, and its answer is the model's.
    type Answering = Box<dyn FnMut(&Request) -> Result<String, String>>;

    thread_local! {
        pub(super) static STAND_IN: RefCell<Option<Answering>> = const { RefCell::new(None) };
    }

    /// One request as the stand-in saw it: its id, system, context and prompt.
    #[derive(Debug, Clone)]
    struct Asked {
        id: String,
        system: String,
        context: Option<String>,
        prompt: String,
    }

    /// The stand-in in place until the answer is dropped, recording every request.
    struct StandIn(Rc<RefCell<Vec<Asked>>>);

    impl StandIn {
        fn answering(mut answer: impl FnMut(&Request) -> Result<String, String> + 'static) -> StandIn {
            let asked = Rc::new(RefCell::new(Vec::new()));
            let seen = Rc::clone(&asked);
            STAND_IN.with(|stand_in| {
                *stand_in.borrow_mut() = Some(Box::new(move |request: &Request| {
                    seen.borrow_mut().push(Asked { id: request.id.clone(), system: request.system.clone(), context: request.context.clone(), prompt: request.prompt.clone() });
                    answer(request)
                }))
            });
            StandIn(asked)
        }

        fn asked(&self) -> Vec<Asked> {
            self.0.borrow().clone()
        }
    }

    impl Drop for StandIn {
        fn drop(&mut self) {
            STAND_IN.with(|stand_in| *stand_in.borrow_mut() = None);
        }
    }

    /// A language model's file on the phone at its full length, sparse, so the
    /// catalogue counts it present: the stand-in answers in its place.
    fn a_language_model(root: &Path, spec: &LlmSpec) {
        let dir = root.join("models");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::File::create(crate::model_files::path_in(&dir, &spec.spec)).unwrap().set_len(spec.spec.bytes).unwrap();
    }

    fn configure(root: &Path, change: impl FnOnce(&mut JobConfig)) {
        let mut config = JobConfig { model: "qwen3.5-4b".into(), summaries: "off".into(), ..JobConfig::default() };
        change(&mut config);
        std::fs::write(jobs::config_path(&root.join("jobs")), serde_json::to_vec(&config).unwrap()).unwrap();
    }

    /// A job whose listening is done: its transcript in the progress file, as a resumed run finds it.
    fn heard(root: &Path, transcript: &str) {
        let mut progress = Progress::queued("n1", "Meeting");
        progress.spans = Some(vec![]);
        progress.transcript = Some(transcript.to_string());
        progress.transcript_chars = transcript.chars().count();
        progress.save(&jobs::progress_path(&root.join("jobs"), "n1"), false).unwrap();
    }

    /// The job queued again from the start, as a new recording under the id would be.
    fn queued_again(root: &Path) {
        Progress::queued("n1", "Meeting").save(&jobs::progress_path(&root.join("jobs"), "n1"), true).unwrap();
    }

    fn done(line: Option<&str>, transcript_chars: usize, summary: bool) -> Answer {
        Answer::Done { title: "Meeting".into(), line: line.map(str::to_string), transcript_chars, summary }
    }

    /// A Kotlin source under the app's package.
    fn kotlin(file: &str) -> String {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("gen/android/app/src/main/java/com/mattssoftware/glyph").join(file);
        std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()))
    }

    /// A phone with one meeting note and its silent recording: a write-up
    /// that needs no model, because there is no speech to transcribe and
    /// summaries are off.
    fn phone(seconds: usize) -> (TempDir, PathBuf) {
        let root = TempDir::new("write-up");
        let mut library = Library::open_fs(&root.join("Library")).unwrap();
        library.save_note("n1", "# Meeting, 26 Sep 14:05\n", "capture").unwrap();
        std::fs::create_dir_all(root.join("recordings")).unwrap();
        let wav_path = root.join("recordings/n1.wav");
        wav::write_pcm16(&wav_path, &vec![0i16; 16_000 * seconds], false).unwrap();
        let jobs = root.join("jobs");
        std::fs::create_dir_all(&jobs).unwrap();
        let config = JobConfig { model: "qwen3.5-4b".into(), summaries: "off".into(), ..JobConfig::default() };
        std::fs::write(jobs::config_path(&jobs), serde_json::to_vec(&config).unwrap()).unwrap();
        (root, wav_path)
    }

    fn progress_of(root: &Path) -> Progress {
        Progress::load(&jobs::progress_path(&root.join("jobs"), "n1")).expect("a progress file")
    }

    fn body_of(root: &Path) -> String {
        Library::open_fs(&root.join("Library")).unwrap().get_note("n1").unwrap().unwrap().body
    }

    fn now() -> Options {
        Options { now: true, ..Options::default() }
    }

    #[test]
    fn a_silent_meeting_is_finished_and_written_up_to_the_end_without_a_model() {
        let _one = lock(&TEST_SERIAL);
        let (root, wav_path) = phone(4);
        // The meeting service's header, ten seconds behind.
        let mut bytes = std::fs::read(&wav_path).unwrap();
        bytes[40..44].copy_from_slice(&0u32.to_le_bytes());
        std::fs::write(&wav_path, &bytes).unwrap();
        assert_eq!(finish(&root, "n1", "Meeting, 26 Sep 14:05"), Ok(4000));
        let queued = progress_of(&root);
        assert_eq!((queued.phase, queued.recorded_ms, queued.error), (Phase::Queued, Some(4000), None));
        assert_eq!(std::fs::read(&wav_path).unwrap()[40..44], (16_000u32 * 4 * 2).to_le_bytes(), "the header put right");
        let note = Library::open_fs(&root.join("Library")).unwrap().get_note("n1").unwrap().unwrap();
        assert_eq!(note.recording_ms, Some(4000));

        let answer = run(&root, "n1", &now());
        assert_eq!(answer, Answer::Done { title: "Meeting, 26 Sep 14:05".into(), line: None, transcript_chars: 0, summary: false });
        assert_eq!(answer.to_json(), r#"{"done":true,"line":null,"summary":false,"title":"Meeting, 26 Sep 14:05","transcriptChars":0}"#);
        let done = progress_of(&root);
        assert_eq!((done.phase, done.percent, done.spans.as_deref()), (Phase::Done, 100, Some(&[][..])));
        assert_eq!(done.transcript.as_deref(), Some(""));
        let result: JobResult = crate::fsx::read_json(&jobs::result_path(&root.join("jobs"), "n1")).unwrap();
        assert_eq!((result.summary, result.model.as_str(), result.transcript_chars), (None, "qwen3.5-4b", 0));
        assert_eq!(body_of(&root), "# Meeting, 26 Sep 14:05\n\n## Transcript\n", "the note is never wordless on disk");
        assert_eq!(run(&root, "n1", &now()), Answer::AlreadyDone, "nothing to post twice");
        assert!(lock(&guards::RUNNING_JOB).is_none(), "the run cleared itself");
        // A done file looked at during a capture is still done, never put to waiting.
        guards::set_capturing(true);
        assert_eq!(run(&root, "n1", &now()), Answer::AlreadyDone);
        guards::set_capturing(false);
        assert_eq!(progress_of(&root).phase, Phase::Done);
    }

    #[test]
    fn each_terminal_phase_answers_with_and_without_fresh() {
        let _one = lock(&TEST_SERIAL);
        let (root, _) = phone(1);
        let path = jobs::progress_path(&root.join("jobs"), "n1");
        let mut progress = Progress::queued("n1", "Meeting");
        progress.phase = Phase::Cancelled;
        progress.save(&path, false).unwrap();
        assert_eq!(run(&root, "n1", &now()), Answer::Cancelled);
        assert_eq!(run(&root, "n1", &now()).to_json(), r#"{"cancelled":true}"#);
        assert_eq!(run(&root, "n1", &Options { fresh: true, ..now() }), Answer::Done { title: "Meeting".into(), line: None, transcript_chars: 0, summary: false }, "Try again runs a cancelled job");

        let mut failed = Progress::queued("n1", "Meeting");
        failed.phase = Phase::Failed;
        failed.tries = MAX_TRIES;
        failed.error = Some("the disk is full".into());
        failed.save(&path, false).unwrap();
        assert_eq!(run(&root, "n1", &now()), Answer::Error { message: "the disk is full".into(), again: true });
        assert_eq!(run(&root, "n1", &now()).to_json(), r#"{"again":true,"error":"the disk is full"}"#);
        assert_eq!(run(&root, "n1", &Options { fresh: true, ..now() }), Answer::Done { title: "Meeting".into(), line: None, transcript_chars: 0, summary: false });
        assert_eq!(progress_of(&root).tries, 0, "tries reset by a fresh run");

        // Summaries on, listening done, no language model on the phone.
        let config = JobConfig { model: "qwen3.5-4b".into(), summaries: "meetings".into(), ..JobConfig::default() };
        std::fs::write(jobs::config_path(&root.join("jobs")), serde_json::to_vec(&config).unwrap()).unwrap();
        let mut needs = Progress::queued("n1", "Meeting");
        needs.phase = Phase::Listening;
        needs.spans = Some(vec![]);
        needs.transcript = Some("We agreed.".into());
        needs.transcript_chars = 10;
        needs.save(&path, false).unwrap();
        assert_eq!(run(&root, "n1", &now()), Answer::NeedsModel { id: "qwen3.5-4b".into(), again: false });
        assert_eq!(progress_of(&root).phase, Phase::NeedsModel);
        assert_eq!(run(&root, "n1", &now()), Answer::NeedsModel { id: "qwen3.5-4b".into(), again: true }, "the file already said so");
        assert_eq!(run(&root, "n1", &now()).to_json(), r#"{"again":true,"needsModel":"qwen3.5-4b"}"#);
        assert_eq!(run(&root, "n1", &Options { fresh: true, ..now() }), Answer::NeedsModel { id: "qwen3.5-4b".into(), again: false }, "looked at afresh");
        // No WAV: gone, and the file with it.
        std::fs::remove_file(root.join("recordings/n1.wav")).unwrap();
        assert_eq!(run(&root, "n1", &now()), Answer::Gone);
        assert!(!path.exists());
        assert_eq!(run(&root, "../n1", &now()).to_json(), r#"{"again":false,"error":"not a note id"}"#);
    }

    #[test]
    fn a_meeting_where_nothing_was_heard_is_not_summarised_even_with_summaries_on() {
        let _one = lock(&TEST_SERIAL);
        let (root, _) = phone(2);
        let config = JobConfig { model: "qwen3.5-4b".into(), summaries: "meetings".into(), ..JobConfig::default() };
        std::fs::write(jobs::config_path(&root.join("jobs")), serde_json::to_vec(&config).unwrap()).unwrap();
        finish(&root, "n1", "Meeting").unwrap();
        // No model on this phone either: a summary asked for would answer needsModel, so Done says none was.
        assert_eq!(run(&root, "n1", &now()), Answer::Done { title: "Meeting".into(), line: None, transcript_chars: 0, summary: false });
        let result: JobResult = crate::fsx::read_json(&jobs::result_path(&root.join("jobs"), "n1")).unwrap();
        assert_eq!(result.summary, None);
    }

    #[test]
    fn a_write_up_holds_for_the_battery_the_heat_a_capture_and_a_busy_engine() {
        let _one = lock(&TEST_SERIAL);
        let (root, _) = phone(1);
        finish(&root, "n1", "Meeting").unwrap();
        let on_battery = Options { charging: false, battery_percent: 30, ..Options::default() };
        assert_eq!(run(&root, "n1", &on_battery), Answer::Retry("battery".into()));
        let held = progress_of(&root);
        assert_eq!((held.phase, held.waiting_for.as_deref()), (Phase::Waiting, Some("battery")));
        assert_eq!(run(&root, "n1", &Options { battery_percent: 80, ..on_battery.clone() }).to_json(), r#"{"done":true,"line":null,"summary":false,"title":"Meeting","transcriptChars":0}"#, "above half runs");
        // The thermal hold, from Kotlin's reading.
        let mut again = Progress::queued("n1", "Meeting");
        again.spans = Some(vec![]);
        again.save(&jobs::progress_path(&root.join("jobs"), "n1"), false).unwrap();
        assert_eq!(run(&root, "n1", &Options { thermal: "severe".into(), ..now() }), Answer::Retry("thermal".into()));
        assert_eq!(progress_of(&root).waiting_for.as_deref(), Some("thermal"));
        // A capture running: the person talking gets the cores.
        guards::set_capturing(true);
        assert_eq!(run(&root, "n1", &now()), Answer::Retry("capturing".into()));
        guards::set_capturing(false);
        assert_eq!(progress_of(&root).waiting_for.as_deref(), Some("capturing"));
        // A refine pass holding the one small.en.
        let refine = guards::try_write_up().unwrap();
        assert_eq!(run(&root, "n1", &now()), Answer::Retry("busy".into()));
        drop(refine);
        assert_eq!(run(&root, "n1", &now()), Answer::Done { title: "Meeting".into(), line: None, transcript_chars: 0, summary: false }, "and then it runs");
    }

    #[test]
    fn a_cancel_marks_the_file_and_the_watchers_next_tick_cannot_unmark_it() {
        let _one = lock(&TEST_SERIAL);
        let (root, _) = phone(1);
        finish(&root, "n1", "Meeting").unwrap();
        guards::clear_abort();
        // A run in hand for a moment, as the drop guard keeps it.
        let running = std::thread::spawn(|| {
            let _running = RunningJob::set("n1");
            std::thread::sleep(Duration::from_millis(300));
        });
        std::thread::sleep(Duration::from_millis(50));
        let started = Instant::now();
        assert!(cancel(&root, "n1", "cancel"), "there was a run to end");
        assert!(started.elapsed() < CANCEL_WAIT);
        assert_eq!(guards::abort_reason(), "cancel");
        assert!(guards::abort_jobs().load(Ordering::SeqCst));
        running.join().unwrap();
        let cancelled = progress_of(&root);
        assert_eq!(cancelled.phase, Phase::Cancelled);
        let mut tick = cancelled.clone();
        tick.phase = Phase::Listening;
        tick.percent = 40;
        assert!(!tick.save(&jobs::progress_path(&root.join("jobs"), "n1"), false).unwrap(), "the watcher's tick is refused");
        assert_eq!(progress_of(&root).phase, Phase::Cancelled);
        assert!(!cancel(&root, "n1", "thermal"), "nothing running now");
        assert_eq!(run(&root, "n1", &now()), Answer::Cancelled, "and the run honours the mark");
        guards::clear_abort();
    }

    #[test]
    fn a_cancel_answers_within_its_wait_while_a_refine_holds_the_lock() {
        let _one = lock(&TEST_SERIAL);
        let (root, _) = phone(1);
        let _refine = guards::try_write_up().unwrap();
        let started = Instant::now();
        assert!(!cancel(&root, "n1", "cancel"));
        assert!(started.elapsed() < CANCEL_WAIT, "never blocks behind the lock");
        assert!(!jobs::progress_path(&root.join("jobs"), "n1").exists(), "no file is made for a job that never was");
    }

    #[test]
    fn a_write_up_lock_poisoned_by_a_panic_is_recovered_not_busy_forever() {
        let _one = lock(&TEST_SERIAL);
        let _ = std::thread::spawn(|| {
            let _guard = guards::WRITE_UP.lock().unwrap();
            panic!("a pass dies with the guard");
        })
        .join();
        let (root, _) = phone(1);
        finish(&root, "n1", "Meeting").unwrap();
        assert_eq!(run(&root, "n1", &now()), Answer::Done { title: "Meeting".into(), line: None, transcript_chars: 0, summary: false });
    }

    #[test]
    fn finish_on_a_library_that_cannot_open_keeps_the_wav_and_a_queued_file_that_says_so() {
        let _one = lock(&TEST_SERIAL);
        let (root, wav_path) = phone(2);
        std::fs::remove_dir_all(root.join("Library")).unwrap();
        std::fs::write(root.join("Library"), b"in the way").unwrap();
        let error = finish(&root, "n1", "Meeting").unwrap_err();
        assert!(wav_path.exists(), "an hour of audio is never unlinked for a lost race");
        let queued = progress_of(&root);
        assert_eq!(queued.phase, Phase::Queued);
        assert_eq!(queued.error.as_deref(), Some(error.as_str()));
        assert_eq!(queued.recorded_ms, None);
        // The sweep's retry, once the library is back: `run` repeats finish's steps.
        std::fs::remove_file(root.join("Library")).unwrap();
        let mut library = Library::open_fs(&root.join("Library")).unwrap();
        library.save_note("n1", "# Meeting\n", "capture").unwrap();
        drop(library);
        assert_eq!(run(&root, "n1", &now()), Answer::Done { title: "Meeting".into(), line: None, transcript_chars: 0, summary: false });
        let done = progress_of(&root);
        assert_eq!((done.recorded_ms, done.error), (Some(2000), None));
        assert_eq!(Library::open_fs(&root.join("Library")).unwrap().get_note("n1").unwrap().unwrap().recording_ms, Some(2000));
    }

    #[test]
    fn an_error_is_counted_and_the_third_is_failed() {
        let _one = lock(&TEST_SERIAL);
        let (root, wav_path) = phone(1);
        finish(&root, "n1", "Meeting").unwrap();
        // A recording that is not one any more: every run fails on it.
        std::fs::write(&wav_path, b"RIFF\0\0\0\0WAVEjunk").unwrap();
        for tries in 1..MAX_TRIES {
            let Answer::Retry(sentence) = run(&root, "n1", &now()) else { panic!("counted, and retried") };
            assert!(!sentence.is_empty());
            let held = progress_of(&root);
            assert_eq!((held.phase, held.waiting_for.as_deref(), held.tries), (Phase::Waiting, Some("error"), tries));
        }
        let Answer::Error { again, .. } = run(&root, "n1", &now()) else { panic!("the third is failed") };
        assert!(!again);
        assert_eq!(progress_of(&root).phase, Phase::Failed);
        assert!(matches!(run(&root, "n1", &now()), Answer::Error { again: true, .. }));
    }

    #[test]
    fn the_battery_rule_holds_only_on_battery_below_half_when_set_to_wait_for_the_charger() {
        let _one = lock(&TEST_SERIAL);
        let (root, _) = phone(1);
        finish(&root, "n1", "Meeting").unwrap();
        let low = Options { charging: false, battery_percent: 30, ..Options::default() };
        let runs = |options: &Options| {
            queued_again(&root);
            run(&root, "n1", options)
        };
        assert_eq!(runs(&low), Answer::Retry("battery".into()));
        assert_eq!(runs(&Options { battery_percent: 49, ..low.clone() }), Answer::Retry("battery".into()), "just under half");
        assert_eq!(runs(&Options { battery_percent: 50, ..low.clone() }), done(None, 0, false), "half is enough");
        assert_eq!(runs(&Options { now: true, ..low.clone() }), done(None, 0, false), "Write up now");
        assert_eq!(runs(&Options { charging: true, ..low.clone() }), done(None, 0, false), "on the charger");
        configure(&root, |config| config.write_up = "now".into());
        assert_eq!(runs(&low), done(None, 0, false), "Straight away");
    }

    #[test]
    fn summaries_off_still_writes_the_transcript_and_says_so() {
        let _one = lock(&TEST_SERIAL);
        let (root, _) = phone(1);
        heard(&root, "We agreed.");
        assert_eq!(run(&root, "n1", &now()), done(None, 10, false), "not needsModel: no summary was asked for");
        let result: JobResult = crate::fsx::read_json(&jobs::result_path(&root.join("jobs"), "n1")).unwrap();
        assert_eq!((result.summary, result.transcript_chars), (None, 10));
    }

    #[test]
    fn a_meeting_a_kill_left_before_finish_is_measured_by_the_run_itself() {
        let _one = lock(&TEST_SERIAL);
        let (root, wav_path) = phone(2);
        // The service's header from before the first patch, and no progress file: `finish` never ran.
        let mut bytes = std::fs::read(&wav_path).unwrap();
        bytes[40..44].copy_from_slice(&0u32.to_le_bytes());
        std::fs::write(&wav_path, &bytes).unwrap();
        let recovered = Options { fresh: true, title: Some("Meeting, 26 Sep 14:05".into()), ..now() };
        assert_eq!(run(&root, "n1", &recovered), Answer::Done { title: "Meeting, 26 Sep 14:05".into(), line: None, transcript_chars: 0, summary: false });
        assert_eq!(std::fs::read(&wav_path).unwrap()[40..44], (16_000u32 * 2 * 2).to_le_bytes(), "the header put right");
        assert_eq!(progress_of(&root).recorded_ms, Some(2000));
        assert_eq!(Library::open_fs(&root.join("Library")).unwrap().get_note("n1").unwrap().unwrap().recording_ms, Some(2000));
    }

    #[test]
    fn a_cancel_made_after_a_fresh_request_wins_over_that_requests_retry() {
        let _one = lock(&TEST_SERIAL);
        let (root, _) = phone(1);
        let mut cancelled = Progress::queued("n1", "Meeting");
        cancelled.phase = Phase::Cancelled;
        cancelled.save(&jobs::progress_path(&root.join("jobs"), "n1"), false).unwrap();
        let at = progress_of(&root).updated_at;
        // Write up now, asked before the meeting went to the trash, retried by WorkManager after it.
        assert_eq!(run(&root, "n1", &Options { fresh: true, requested_at: Some(at - 1_000), ..now() }), Answer::Cancelled);
        assert_eq!(progress_of(&root).phase, Phase::Cancelled, "and the file stays cancelled");
        // Restored from the trash: a request made after the cancel.
        assert_eq!(run(&root, "n1", &Options { fresh: true, requested_at: Some(at + 1_000), ..now() }), done(None, 0, false));
    }

    #[test]
    fn a_cancel_leaves_a_finished_write_up_for_the_page_to_land() {
        let _one = lock(&TEST_SERIAL);
        let (root, _) = phone(1);
        finish(&root, "n1", "Meeting").unwrap();
        assert_eq!(run(&root, "n1", &now()), done(None, 0, false));
        assert!(!cancel(&root, "n1", "cancel"), "nothing running");
        assert_eq!(progress_of(&root).phase, Phase::Done, "the trash does not strand a result");
        assert!(jobs::result_path(&root.join("jobs"), "n1").exists());
        assert_eq!(run(&root, "n1", &Options { fresh: true, ..now() }), Answer::AlreadyDone, "restored: landed, never written up twice");
    }

    #[test]
    fn a_write_up_asked_again_keeps_the_transcript_the_note_already_has() {
        let _one = lock(&TEST_SERIAL);
        let (root, _) = phone(2);
        let corrected = "# Meeting\n\n## Transcript\n\nWe agreed, as I corrected it.\n\nThen a line I added.\n";
        let mut library = Library::open_fs(&root.join("Library")).unwrap();
        library.save_note("n1", corrected, "capture").unwrap();
        drop(library);
        // The page took the last result, so there is no progress file: Restore asks afresh.
        assert_eq!(run(&root, "n1", &Options { fresh: true, ..now() }), done(None, "We agreed, as I corrected it.\n\nThen a line I added.".chars().count(), false));
        assert_eq!(body_of(&root), corrected, "not listened to again, nor written over");
        assert_eq!(progress_of(&root).transcript.as_deref(), Some("We agreed, as I corrected it.\n\nThen a line I added."));
    }

    #[test]
    fn a_capture_that_is_still_loading_its_model_holds_a_write_up() {
        let _one = lock(&TEST_SERIAL);
        let (root, _) = phone(1);
        finish(&root, "n1", "Meeting").unwrap();
        let starting = guards::capture_starting();
        assert_eq!(run(&root, "n1", &now()), Answer::Retry("capturing".into()));
        drop(starting);
        assert_eq!(run(&root, "n1", &now()), done(None, 0, false));
    }

    #[test]
    fn a_short_transcript_is_summarised_in_one_pass_by_the_model_that_is_here() {
        let _one = lock(&TEST_SERIAL);
        let (root, _) = phone(1);
        configure(&root, |config| config.summaries = "meetings".into());
        // The config names the 4B (chosen before the download); only the 2B is on the phone.
        a_language_model(&root, &QWEN3_5_2B);
        let transcript = "We agreed to ship in March. I will book the venue.";
        heard(&root, transcript);
        let model = StandIn::answering(|_| Ok("# March\nA call that fixed the date.\n\n- [ ] Book the venue.".into()));
        assert_eq!(run(&root, "n1", &now()), done(Some("A call that fixed the date."), transcript.len(), true));
        let asked = model.asked();
        assert_eq!(asked.len(), 1, "{asked:?}");
        assert_eq!(asked[0].id, "write-up:n1:summary");
        assert_eq!((asked[0].system.as_str(), asked[0].context.as_deref(), asked[0].prompt.as_str()), (prompts::SUMMARY, None, transcript));
        let result: JobResult = crate::fsx::read_json(&jobs::result_path(&root.join("jobs"), "n1")).unwrap();
        assert_eq!(result.model, QWEN3_5_2B.id, "the model that wrote it, by the page's rule");
        assert_eq!(result.summary.as_deref(), Some("# March\nA call that fixed the date.\n\n- [ ] Book the venue."));
        // With the chosen one here too, it is the one used.
        a_language_model(&root, &QWEN3_5_4B);
        heard(&root, transcript);
        let _model = StandIn::answering(|_| Ok("# March\nA call.".into()));
        run(&root, "n1", &now());
        let result: JobResult = crate::fsx::read_json(&jobs::result_path(&root.join("jobs"), "n1")).unwrap();
        assert_eq!(result.model, QWEN3_5_4B.id);
    }

    #[test]
    fn a_long_transcript_goes_piece_by_piece_and_resumes_at_the_piece_it_stopped_on() {
        let _one = lock(&TEST_SERIAL);
        let (root, _) = phone(1);
        configure(&root, |config| {
            config.summaries = "meetings".into();
            config.one_pass_chars = 40;
            config.piece_chars = 60;
        });
        a_language_model(&root, &QWEN3_5_2B);
        let transcript = "We agreed to ship the launch in March.\n\nSam will send the press list on Friday.\n\nI will book the venue before the tenth.";
        let pieces = crate::transcript::pieces(transcript, 60);
        let m = pieces.len();
        assert!(m >= 3, "{pieces:?}");
        heard(&root, transcript);
        // The second piece fails the first time: counted, and the first piece's notes kept.
        let first = StandIn::answering(|request| if request.id.ends_with(":piece-2") { Err("the phone ran out of memory".into()) } else { Ok(format!("- Notes on {}", request.id)) });
        assert_eq!(run(&root, "n1", &now()), Answer::Retry("the phone ran out of memory".into()));
        assert_eq!(first.asked().len(), 2);
        drop(first);
        let held = progress_of(&root);
        assert_eq!((held.pieces.len(), held.tries, held.waiting_for.as_deref()), (1, 1, Some("error")));
        // The retry starts at the second piece.
        let model = StandIn::answering(|request| Ok(if request.id.ends_with(":summary") { "# Launch\nA call about the launch.".into() } else { format!("- Notes on {}", request.id) }));
        assert_eq!(run(&root, "n1", &now()), done(Some("A call about the launch."), transcript.len(), true));
        let asked = model.asked();
        assert_eq!(asked.len(), m, "pieces two to {m}, then the summary: {asked:?}");
        for (at, piece) in asked[..m - 1].iter().zip(2..) {
            assert_eq!(at.id, format!("write-up:n1:piece-{piece}"));
            assert_eq!((at.system.as_str(), at.context.as_deref()), (prompts::NOTES, None));
            let line = fill(prompts::PIECE, &[("n", &piece.to_string()), ("m", &m.to_string())]);
            assert_eq!(at.prompt, format!("{line}\n\n{}", pieces[piece - 1]), "the piece line in the prompt, where the page puts it");
        }
        let summary = &asked[m - 1];
        assert_eq!(summary.system, prompts::SUMMARY);
        let words = transcript.split_whitespace().count();
        assert_eq!(summary.context.as_deref(), Some(fill(prompts::PARTS, &[("words", &thousands(words))]).as_str()), "the parts line in the context");
        let notes: Vec<String> = (1..=m).map(|n| format!("- Notes on write-up:n1:piece-{n}")).collect();
        assert_eq!(summary.prompt, notes.join("\n\n"));
    }

    #[test]
    fn a_dictation_started_between_pieces_holds_the_rest() {
        let _one = lock(&TEST_SERIAL);
        let (root, _) = phone(1);
        configure(&root, |config| {
            config.summaries = "meetings".into();
            config.one_pass_chars = 40;
            config.piece_chars = 60;
        });
        a_language_model(&root, &QWEN3_5_2B);
        heard(&root, "We agreed to ship the launch in March.\n\nSam will send the press list on Friday.\n\nI will book the venue.");
        let _model = StandIn::answering(|_| {
            // The person picks the phone up and starts talking while the first piece is written.
            guards::set_capturing(true);
            Ok("- A note.".into())
        });
        let answer = run(&root, "n1", &now());
        guards::set_capturing(false);
        assert_eq!(answer, Answer::Retry("capturing".into()));
        let held = progress_of(&root);
        assert_eq!((held.pieces.len(), held.waiting_for.as_deref(), held.tries), (1, Some("capturing"), 0), "a hold, not a try");
    }

    /// `text` spoken by macOS's `say` as 16 kHz mono PCM16, or `None` off a Mac.
    fn spoken(text: &str) -> Option<Vec<i16>> {
        use std::process::Command;
        let stem = std::env::temp_dir().join(format!("glyph-write-up-{}", uuid::Uuid::new_v4()));
        let (aiff, wav_path) = (stem.with_extension("aiff"), stem.with_extension("wav"));
        let spoke = Command::new("say").arg("-o").arg(&aiff).arg(text).status();
        let converted = matches!(spoke, Ok(s) if s.success())
            && matches!(Command::new("afconvert").args(["-f", "WAVE", "-d", "LEI16@16000", "-c", "1"]).arg(&aiff).arg(&wav_path).status(), Ok(s) if s.success());
        let samples = converted.then(|| wav::read(&wav_path).ok()).flatten().map(|audio| audio.iter().map(|s| (s * 32_767.0).round() as i16).collect());
        let _ = std::fs::remove_file(&aiff);
        let _ = std::fs::remove_file(&wav_path);
        samples
    }

    /// The real listening: two sentences with three seconds of silence
    /// between them, transcribed with base.en span by span. Skipped without the
    /// model in `models/` or without `say`, as whisper's own tests are.
    #[test]
    fn listening_goes_span_by_span_and_each_phrase_keeps_its_place_on_the_tape() {
        let _one = lock(&TEST_SERIAL);
        let models = std::env::var_os("GLYPH_MODELS_DIR").map(PathBuf::from).unwrap_or_else(|| Path::new(env!("CARGO_MANIFEST_DIR")).join("..").join("models"));
        let status = crate::model_files::status(&models, &whisper_model::ACTIVE);
        if !status.present {
            eprintln!("SKIPPED: {} is not in models/", whisper_model::ACTIVE.file);
            return;
        }
        let (Some(first), Some(second)) = (spoken("We agreed to ship the launch in March."), spoken("Sam will send the press list on Friday.")) else {
            eprintln!("SKIPPED: no `say` and `afconvert` to speak the meeting with (macOS only)");
            return;
        };
        let (root, wav_path) = phone(1);
        let mut samples = first.clone();
        samples.extend(std::iter::repeat_n(0i16, 16_000 * 3));
        let second_at = samples_to_ms(samples.len());
        samples.extend(&second);
        samples.extend(std::iter::repeat_n(0i16, 16_000));
        wav::write_pcm16(&wav_path, &samples, false).unwrap();
        std::fs::create_dir_all(root.join("models")).unwrap();
        std::os::unix::fs::symlink(std::fs::canonicalize(&status.path).unwrap(), crate::model_files::path_in(&root.join("models"), &whisper_model::ACTIVE)).unwrap();
        finish(&root, "n1", "Meeting").unwrap();
        let Answer::Done { transcript_chars, summary: false, .. } = run(&root, "n1", &now()) else { panic!("written up") };
        assert!(transcript_chars > 0);
        let spans = progress_of(&root).spans.expect("the spans found");
        assert!(spans.len() >= 2, "one span a sentence at least: {spans:?}");
        assert!(spans.iter().any(|(from, _)| *from + 400 >= second_at), "a span begins at the second sentence: {spans:?}");
        let note = Library::open_fs(&root.join("Library")).unwrap().get_note("n1").unwrap().unwrap();
        let lower = note.body.to_lowercase();
        assert!(lower.contains("## transcript") && lower.contains("march") && lower.contains("friday"), "{}", note.body);
        let segments = note.segments.clone().expect("the phrases beside the note");
        let friday = segments.iter().find(|s| s.text.to_lowercase().contains("friday")).expect("a phrase with Friday");
        assert!(friday.start_ms + 400 >= second_at, "offset to its place on the tape, not the span's: {friday:?} vs {second_at}");
        assert!(segments.iter().any(|s| s.text.to_lowercase().contains("march") && s.end_ms <= second_at), "{segments:?}");

        // Stopped after the first span (a kill, the heat): the retry decodes only what is left.
        let mut resumed = Progress::queued("n1", "Meeting");
        resumed.phase = Phase::Waiting;
        resumed.recorded_ms = Some(samples_to_ms(samples.len()));
        resumed.spans = Some(spans.clone());
        resumed.spans_done = spans.iter().take_while(|(from, _)| *from + 400 < second_at).count();
        resumed.segments = vec![crate::note::RecordedSegment { text: "Planted words for the first span.".into(), start_ms: spans[0].0, end_ms: spans[0].1 }];
        resumed.save(&jobs::progress_path(&root.join("jobs"), "n1"), true).unwrap();
        assert!(matches!(run(&root, "n1", &now()), Answer::Done { .. }));
        let body = body_of(&root).to_lowercase();
        assert!(body.contains("planted words for the first span") && body.contains("friday") && !body.contains("march"), "the first span not decoded again: {body}");
    }

    /// Every key `WriteUp.options` puts is a field of `Options`, and every
    /// field is put: a key misspelt on either side would be read here as its
    /// default (100% battery, the app closed) without a word.
    #[test]
    fn the_kotlin_options_are_the_rust_fields() {
        let source = kotlin("recordings/WriteUp.kt");
        let from = source.find("fun options(").expect("WriteUp.options");
        let body = &source[from..from + source[from..].find(".toString()").expect("the options' end")];
        let put: BTreeSet<String> = body.match_indices(".put(\"").map(|(at, key)| body[at + key.len()..].split('"').next().unwrap_or_default().to_string()).collect();
        let fields: BTreeSet<String> = serde_json::to_value(Options::default()).unwrap().as_object().unwrap().keys().cloned().collect();
        assert_eq!(put, fields);
    }

    /// Kotlin reads `run`'s answer by the keys `to_json` writes, the thermal
    /// words by the ones `run` holds for, and leaves alone the phases Rust
    /// never takes up again without being asked.
    #[test]
    fn the_kotlin_reads_every_answer_by_its_key_and_every_word_by_its_name() {
        let source = kotlin("recordings/WriteUp.kt");
        let reader = &source[source.find("fun outcomeOf(").expect("WriteUp.outcomeOf")..];
        let answers = [
            ("done", done(Some("A line."), 10, true)),
            ("alreadyDone", Answer::AlreadyDone),
            ("retry", Answer::Retry("busy".into())),
            ("needsModel", Answer::NeedsModel { id: "qwen3.5-4b".into(), again: false }),
            ("error", Answer::Error { message: "no".into(), again: true }),
            ("cancelled", Answer::Cancelled),
            ("gone", Answer::Gone),
        ];
        for (tag, answer) in answers {
            let json: serde_json::Value = serde_json::from_str(&answer.to_json()).unwrap();
            for key in json.as_object().unwrap().keys() {
                assert!(reader.contains(&format!("\"{key}\"")), "outcomeOf never reads {key:?}, which {tag} carries");
            }
            assert!(json.get(tag).is_some(), "{tag} is the key {answer:?} is known by");
        }
        for word in HOT {
            assert!(source.contains(&format!("-> \"{word}\"")), "WriteUp.thermalWord no longer says {word}");
        }
        let terminal = source.lines().find(|line| line.contains("val TERMINAL_PHASES")).expect("WriteUp.TERMINAL_PHASES");
        for phase in [Phase::Done, Phase::NeedsModel, Phase::Failed, Phase::Cancelled] {
            let word = serde_json::to_value(phase).unwrap();
            assert!(terminal.contains(&format!("\"{}\"", word.as_str().unwrap())), "the sweep would retry a {phase:?} job");
        }
    }

    /// The Kotlin door (`recordings/RecordingJob.kt`) and the JNI symbols in
    /// `recording_jobs.rs` name each other: the package, the object and the
    /// three `external fun`s on one side, the three `Java_..._RecordingJob_*`
    /// functions on the other. A rename on either side fails here rather than
    /// as an `UnsatisfiedLinkError` on a phone with the app closed.
    #[test]
    fn the_kotlin_door_and_the_rust_symbols_name_each_other() {
        let door = include_str!("recording_jobs.rs");
        for symbol in ["run", "finish", "cancel"] {
            let function = format!("fn Java_com_mattssoftware_glyph_recordings_RecordingJob_{symbol}<");
            assert!(door.contains(&function), "recording_jobs.rs exports {function}");
        }
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("gen/android/app/src/main/java/com/mattssoftware/glyph/recordings/RecordingJob.kt");
        let kotlin = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
        for expected in ["package com.mattssoftware.glyph.recordings", "object RecordingJob", "external fun finish(", "external fun run(", "external fun cancel("] {
            assert!(kotlin.contains(expected), "RecordingJob.kt no longer says {expected}");
        }
        // The same three strings on both sides: a parameter added or dropped on one is an UnsatisfiedLinkError
        // or garbage on the phone, not a failure anywhere else.
        for (symbol, last) in [("finish", "title"), ("run", "options"), ("cancel", "reason")] {
            let signature = format!("external fun {symbol}(dataDir: String, noteId: String, {last}: String): String?");
            assert!(kotlin.contains(&signature), "RecordingJob.kt no longer says {signature}");
            let from = door.find(&format!("fn Java_com_mattssoftware_glyph_recordings_RecordingJob_{symbol}<")).unwrap();
            let parameters = &door[from..from + door[from..].find(") -> jstring").unwrap()];
            assert_eq!(parameters.matches("JString<'local>").count(), 3, "{symbol} takes three strings");
        }
    }

    /// The budgets, held to the page's by the fixture both sides read
    /// (src/app/ai/writeUpTwins.fixture.json).
    #[test]
    fn the_budgets_agree_with_the_pages_fixture() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../src/app/ai/writeUpTwins.fixture.json");
        let source = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
        let fixture: serde_json::Value = serde_json::from_str(&source).expect("the fixture is JSON");
        let budgets = fixture["budgets"].as_array().expect("the budgets");
        assert!(!budgets.is_empty());
        for case in budgets {
            let chars = case["chars"].as_u64().unwrap() as usize;
            assert_eq!(summary_budget(chars) as u64, case["summary"].as_u64().unwrap(), "the summary's for {chars}");
            assert_eq!(notes_budget(chars) as u64, case["notes"].as_u64().unwrap(), "a piece's notes' for {chars}");
        }
    }

    #[test]
    fn the_prompt_helpers_twin_the_pages() {
        assert_eq!(fill(prompts::PIECE, &[("n", "2"), ("m", "5")]), "Part 2 of 5 of one recording.");
        assert!(fill(prompts::PARTS, &[("words", &thousands(41_230))]).contains("about 41,230 words"));
        assert_eq!(thousands(0), "0");
        assert_eq!(thousands(999), "999");
        assert_eq!(thousands(1000), "1,000");
        assert_eq!(thousands(1_234_567), "1,234,567");
        assert_eq!(summary_budget(0), 200);
        assert_eq!(summary_budget(41_230), 1024.min(41_230_usize.div_ceil(4).div_ceil(6) as u32 + 96));
        assert_eq!(summary_budget(400_000), 1024);
        assert_eq!(notes_budget(0), 128);
        assert_eq!(notes_budget(4_000), 4_000_usize.div_ceil(4).div_ceil(4) as u32 + 64);
        assert_eq!(notes_budget(12_000), 512, "a whole piece is capped, as the page caps it");
        assert_eq!(notes_budget(100_000), 512);
        assert_eq!(summary_line("# Launch\nA call that fixed the date.\n\n- The site copy.").as_deref(), Some("A call that fixed the date."));
        assert_eq!(summary_line("- [ ] Book it.\n"), None);
        assert_eq!(summary_line(""), None);
        let options: Options = serde_json::from_str(r#"{"now":true,"charging":false,"batteryPercent":64,"thermal":"light","appInFront":true}"#).unwrap();
        assert_eq!((options.now, options.fresh, options.battery_percent, options.app_in_front), (true, false, 64, true));
        assert_eq!(serde_json::from_str::<Options>("{}").unwrap(), Options::default());
    }
}
