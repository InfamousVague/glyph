//! The files a meeting's write-up is kept in: `<app_data_dir>/jobs/`, and the
//! three shapes in it. Every target, and NOT ONE `tauri::` TYPE, because both
//! doors read them: the page's commands (`recording_commands.rs`, on every
//! target) and the write-up itself (`write_up.rs`, reached over JNI with no
//! Tauri in the process).
//!
//! - `config.json` is what the page knows and the job needs: the model it
//!   chose, the prompts, the piece rule, the temperature, and the two
//!   preferences (`ai_keep_job_config` writes it at launch and on change; a
//!   fresh install that never ran the page has none, and `write_up` fills the
//!   blanks from its compiled-in copy).
//! - `<id>.progress` is where a write-up is: its phase, what it has found and
//!   written so far (the speech spans, the phrases, the transcript, the notes on
//!   each piece), and how many tries it has had. The job resumes from it by span
//!   and by piece, the page draws its captions from it, and Kotlin reads its
//!   phase for the notification. Rust is its only writer.
//! - `<id>.json` is the result the page takes once, and lands through the same
//!   `withSummary` as every other summary.
//!
//! Every write to a `.progress` in this process goes through `Progress::save`,
//! under `guards::PROGRESS_FILE`, which reads the file's phase first and never
//! writes over `cancelled`: a cancel from the notification or the trash cannot
//! be undone by the watcher's next tick (DESIGN §127 section 4).

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::note::RecordedSegment;

/// The directory under `<app_data_dir>`; the name is `paths::JOBS`, which
/// Kotlin shares (it lists `*.progress` at launch and never writes there).
pub const DIR: &str = crate::paths::JOBS;

/// `<data_dir>/jobs`.
pub fn dir(data_dir: &Path) -> PathBuf {
    data_dir.join(DIR)
}

/// `jobs/<id>.progress`.
pub fn progress_path(dir: &Path, id: &str) -> PathBuf {
    dir.join(format!("{id}.progress"))
}

/// `jobs/<id>.json`.
pub fn result_path(dir: &Path, id: &str) -> PathBuf {
    dir.join(format!("{id}.json"))
}

/// `jobs/config.json`.
pub fn config_path(dir: &Path) -> PathBuf {
    dir.join("config.json")
}

/// Where a write-up is. The names are the page's (`recording_job_state`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum Phase {
    /// Recorded and waiting for its first run.
    #[default]
    Queued,
    /// Transcribing, span by span.
    Listening,
    /// The model over the transcript, piece by piece.
    Summarizing,
    /// Held: `waiting_for` says why (battery, thermal, capturing, busy, ...).
    Waiting,
    /// Terminal until a model arrives.
    NeedsModel,
    /// Terminal after `write_up::MAX_TRIES`.
    Failed,
    /// Terminal: the result is in `<id>.json` until the page takes it.
    Done,
    /// Terminal: cancelled by a person, until a removal or a fresh run.
    Cancelled,
}

/// `jobs/<id>.progress`: one write-up, as far as it has got.
///
/// Every field a fresh install's file may lack has a default, so a file written
/// by an older binary still reads.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Progress {
    pub id: String,
    /// The note's title as recorded ("Meeting, 26 Sep 14:05"), for the notification.
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub phase: Phase,
    /// With `Waiting`: the hold. `"battery"` is the one the shelf names.
    #[serde(default)]
    pub waiting_for: Option<String>,
    /// Within the phase: listening is speech transcribed over speech found,
    /// summarizing is pieces done over pieces plus the final pass.
    #[serde(default)]
    pub percent: u32,
    /// Counted failures; a hold is not one.
    #[serde(default)]
    pub tries: u32,
    #[serde(default)]
    pub error: Option<String>,
    /// Milliseconds since the epoch of the last save.
    #[serde(default)]
    pub updated_at: i64,
    /// The recording's length, once `finish` (or `run` repeating it) has measured it.
    #[serde(default)]
    pub recorded_ms: Option<u64>,
    /// The speech spans, `[from_ms, to_ms]`, once found; absent before.
    #[serde(default)]
    pub spans: Option<Vec<(u64, u64)>>,
    #[serde(default)]
    pub spans_done: usize,
    /// The phrases so far, kept until listening ends and then dropped for `transcript`.
    #[serde(default)]
    pub segments: Vec<RecordedSegment>,
    /// The paragraphs joined by blank lines, once listening has ended.
    #[serde(default)]
    pub transcript: Option<String>,
    #[serde(default)]
    pub transcript_chars: usize,
    /// The notes on each finished piece of a long transcript, in order.
    #[serde(default)]
    pub pieces: Vec<String>,
    /// The model the summary is being written with, by the page's id.
    #[serde(default)]
    pub model: Option<String>,
}

impl Progress {
    /// A queued write-up for `id`, titled: what `finish` writes.
    pub fn queued(id: &str, title: &str) -> Progress {
        Progress { id: id.to_string(), title: title.to_string(), phase: Phase::Queued, updated_at: crate::note::now_ms(), ..Progress::default() }
    }

    /// The file at `path`, or `None` when it is missing or not this shape.
    pub fn load(path: &Path) -> Option<Progress> {
        crate::fsx::read_json(path)
    }

    /// Writes this progress whole, under `guards::PROGRESS_FILE`, stamping
    /// `updated_at`. Answers whether it was written: a file that says
    /// `cancelled` is never written over, except by a `queued` progress whose
    /// caller said `fresh` (a new recording under the id, or Try again). A
    /// `cancelled` progress itself is always written.
    pub fn save(&self, path: &Path, fresh: bool) -> Result<bool, String> {
        let _one = crate::lock::lock(&crate::guards::PROGRESS_FILE);
        let cancelled_on_disk = Progress::load(path).is_some_and(|on_disk| on_disk.phase == Phase::Cancelled);
        let allowed = self.phase == Phase::Cancelled || !cancelled_on_disk || (fresh && self.phase == Phase::Queued);
        if !allowed {
            return Ok(false);
        }
        let mut stamped = self.clone();
        stamped.updated_at = crate::note::now_ms();
        if let Some(parent) = path.parent() {
            crate::fsx::make_dir(parent)?;
        }
        let json = serde_json::to_vec(&stamped).map_err(|e| format!("the progress could not be written: {e}"))?;
        crate::fsx::write_atomically(path, &json).map_err(|e| format!("the progress could not be written: {e}"))?;
        Ok(true)
    }
}

/// `jobs/<id>.json`: what a finished write-up leaves for the page.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct JobResult {
    /// The model's answer, raw, or `None` with summaries off.
    pub summary: Option<String>,
    pub model: String,
    pub transcript_chars: usize,
    pub finished_at: i64,
}

/// The prompts the page sends (`format/prompt.ts`); a blank one means the
/// compiled-in copy (`write_up::prompts`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct Prompts {
    #[serde(default)]
    pub summary: String,
    #[serde(default)]
    pub notes: String,
    #[serde(default)]
    pub piece: String,
    #[serde(default)]
    pub parts: String,
}

/// `jobs/config.json`, as `ai_keep_job_config` writes it. Every field has a
/// default so a file from an older page still reads; a blank or zero is filled
/// by `write_up` with what the page would have sent.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct JobConfig {
    /// The model's id, as the page resolved it (`modelFor`).
    #[serde(default)]
    pub model: String,
    #[serde(default)]
    pub prompts: Prompts,
    /// A transcript up to this many characters goes to the model in one pass.
    #[serde(default)]
    pub one_pass_chars: usize,
    /// About how many characters a piece of a longer transcript holds.
    #[serde(default)]
    pub piece_chars: usize,
    #[serde(default)]
    pub temperature: f32,
    /// `"charging"` or `"now"`: Settings › Recording › Meetings › Write up.
    #[serde(default)]
    pub write_up: String,
    /// `"meetings"`, `"long"` or `"off"`: Settings › Recording › Summaries.
    #[serde(default)]
    pub summaries: String,
}

/// Every `*.progress` in `dir`, by id, unreadable ones skipped. Empty when the
/// directory is not there.
pub fn list(dir: &Path) -> Vec<Progress> {
    let Ok(entries) = std::fs::read_dir(dir) else { return Vec::new() };
    let mut found: Vec<Progress> = entries
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "progress"))
        .filter_map(|path| Progress::load(&path))
        .collect();
    found.sort_by(|a, b| a.id.cmp(&b.id));
    found
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TempDir;

    #[test]
    fn the_paths_are_where_kotlin_and_the_page_look() {
        let data = Path::new("/data/glyph");
        let jobs = dir(data);
        assert_eq!(jobs, PathBuf::from("/data/glyph/jobs"));
        assert_eq!(progress_path(&jobs, "n1"), PathBuf::from("/data/glyph/jobs/n1.progress"));
        assert_eq!(result_path(&jobs, "n1"), PathBuf::from("/data/glyph/jobs/n1.json"));
        assert_eq!(config_path(&jobs), PathBuf::from("/data/glyph/jobs/config.json"));
    }

    #[test]
    fn a_progress_is_written_and_read_in_the_pages_names() {
        let root = TempDir::new("jobs");
        let jobs = dir(&root);
        let mut progress = Progress::queued("n1", "Meeting, 26 Sep 14:05");
        progress.spans = Some(vec![(0, 27_400), (28_100, 55_000)]);
        progress.segments = vec![RecordedSegment { text: "Hello.".into(), start_ms: 0, end_ms: 900 }];
        assert!(progress.save(&progress_path(&jobs, "n1"), false).unwrap(), "the directory is made on the way");
        let json: serde_json::Value = serde_json::from_slice(&std::fs::read(progress_path(&jobs, "n1")).unwrap()).unwrap();
        assert_eq!(json["phase"], "queued");
        assert_eq!(json["spansDone"], 0);
        assert_eq!(json["segments"][0]["startMs"], 0);
        assert!(json["updatedAt"].as_i64().unwrap() > 0, "stamped on save");
        assert_eq!(json["waitingFor"], serde_json::Value::Null);
        let back = Progress::load(&progress_path(&jobs, "n1")).unwrap();
        assert_eq!(back.spans, progress.spans);
        assert_eq!(back.title, "Meeting, 26 Sep 14:05");
        // A file from an older binary that lacks most fields still reads.
        std::fs::write(progress_path(&jobs, "n2"), br#"{"id":"n2","phase":"needsModel"}"#).unwrap();
        let older = Progress::load(&progress_path(&jobs, "n2")).unwrap();
        assert_eq!((older.phase, older.tries, older.spans), (Phase::NeedsModel, 0, None));
        assert_eq!(list(&jobs).iter().map(|p| p.id.as_str()).collect::<Vec<_>>(), ["n1", "n2"]);
        assert!(list(&root.join("nowhere")).is_empty());
    }

    #[test]
    fn a_cancelled_file_is_only_written_over_by_a_fresh_queued_one() {
        let root = TempDir::new("jobs-cancel");
        let path = progress_path(&dir(&root), "n1");
        let mut progress = Progress::queued("n1", "Meeting");
        progress.phase = Phase::Listening;
        assert!(progress.save(&path, false).unwrap());
        let mut cancelled = progress.clone();
        cancelled.phase = Phase::Cancelled;
        assert!(cancelled.save(&path, false).unwrap(), "a cancel always lands");
        // The watcher's next tick: refused, and the file still says cancelled.
        progress.percent = 40;
        assert!(!progress.save(&path, false).unwrap());
        assert_eq!(Progress::load(&path).unwrap().phase, Phase::Cancelled);
        let mut waiting = progress.clone();
        waiting.phase = Phase::Waiting;
        assert!(!waiting.save(&path, false).unwrap(), "nor the run's final mark");
        // Try again, or a new recording under the id: queued and fresh.
        let again = Progress::queued("n1", "Meeting");
        assert!(!again.save(&path, false).unwrap(), "queued alone is not enough");
        assert!(again.save(&path, true).unwrap());
        assert_eq!(Progress::load(&path).unwrap().phase, Phase::Queued);
    }

    #[test]
    fn a_config_from_the_page_reads_and_a_missing_field_is_blank() {
        let json = r#"{"model":"qwen3.5-4b","prompts":{"summary":"S","notes":"N","piece":"P {n} {m}","parts":"W {words}"},"onePassChars":20000,"pieceChars":12000,"temperature":0.3,"writeUp":"charging","summaries":"meetings"}"#;
        let config: JobConfig = serde_json::from_str(json).unwrap();
        assert_eq!((config.model.as_str(), config.one_pass_chars, config.piece_chars), ("qwen3.5-4b", 20_000, 12_000));
        assert_eq!(config.prompts.piece, "P {n} {m}");
        let older: JobConfig = serde_json::from_str(r#"{"model":"qwen3.5-2b"}"#).unwrap();
        assert_eq!((older.prompts.summary.as_str(), older.one_pass_chars, older.write_up.as_str()), ("", 0, ""));
        let result = JobResult { summary: None, model: "qwen3.5-4b".into(), transcript_chars: 41_230, finished_at: 1 };
        let json = serde_json::to_value(&result).unwrap();
        assert_eq!(json["transcriptChars"], 41_230);
        assert_eq!(json["summary"], serde_json::Value::Null);
    }
}
