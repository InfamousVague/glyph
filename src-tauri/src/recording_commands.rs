//! The webview's door to a meeting's write-up and its tapes: what the page
//! gives the write-up (its config), what it takes from it (the result, the
//! state of every job), and two calls about the audio itself (a digest for
//! sync, a removal for the Tapes row). Native generation 20. Every target: the
//! files are `jobs.rs`'s shapes, which need neither whisper nor llama, so iOS
//! builds this whole and answers honestly (no jobs, no tapes).
//!
//! THE CONTRACT WITH THE PAGE:
//!
//! - `ai_keep_job_config({ config })` writes `jobs/config.json`, the shape in
//!   jobs.rs: the model the page resolved, the prompts, the piece rule, the
//!   temperature, and the Write up and Summaries preferences. At launch and on
//!   change, so a write-up with the app closed uses what the page would have.
//! - `recording_result_take({ id }) -> { summary, model, transcriptChars,
//!   finishedAt } | null`, once: the result and the progress file go with it.
//! - `recording_job_state() -> [{ id, title, phase, waitingFor, percent, error,
//!   updatedAt }]`, every `jobs/*.progress`, for the shelf's captions.
//! - `recording_digest({ id }) -> { sha256, bytes } | null`, the recording's
//!   SHA-256 hashed off the async runtime, so sync never reads an hour's audio
//!   into the WebView to learn whether it changed.
//! - `recording_delete({ ids }) -> { removed, freedBytes }`: each recording's
//!   WAV and write-up files go; the note keeps its length and its phrases.
//!
//! Starting and stopping a write-up are not here: those are Kotlin's
//! (`GlyphHost.writeUp`, `cancelWriteUp`), the one side that knows both
//! WorkManager and the JNI cancel.

use std::path::Path;

use serde::Serialize;
use tauri::AppHandle;

use crate::jobs::{self, JobConfig, JobResult, Phase, Progress};
use crate::paths;

/// Writes what the write-up needs from the page, whole or not at all.
#[tauri::command]
pub fn ai_keep_job_config(app: AppHandle, config: JobConfig) -> Result<(), String> {
    let dir = paths::jobs_dir(&app)?;
    keep_config(&dir, &config)
}

fn keep_config(jobs: &Path, config: &JobConfig) -> Result<(), String> {
    crate::fsx::make_dir(jobs)?;
    let json = serde_json::to_vec(config).map_err(|e| format!("the job config could not be written: {e}"))?;
    crate::fsx::write_atomically(&jobs::config_path(jobs), &json).map_err(|e| format!("the job config could not be written: {e}"))
}

/// The result of note `id`'s write-up, once; `null` when there is none yet.
#[tauri::command]
pub fn recording_result_take(app: AppHandle, id: String) -> Result<Option<JobResult>, String> {
    let dir = paths::jobs_dir(&app)?;
    Ok(take_result(&dir, &id))
}

/// The result file read and removed with its progress, under the lock every
/// writer of a progress file takes; an id that may not name a file has none.
fn take_result(jobs: &Path, id: &str) -> Option<JobResult> {
    if !crate::fsx::plain_id(id) {
        return None;
    }
    let result: JobResult = crate::fsx::read_json(&jobs::result_path(jobs, id))?;
    let _one = crate::lock::lock(&crate::guards::PROGRESS_FILE);
    let _ = std::fs::remove_file(jobs::result_path(jobs, id));
    let _ = std::fs::remove_file(jobs::progress_path(jobs, id));
    Some(result)
}

/// One write-up as the page draws it.
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct JobState {
    pub id: String,
    pub title: String,
    pub phase: Phase,
    pub waiting_for: Option<String>,
    pub percent: u32,
    pub error: Option<String>,
    pub updated_at: i64,
}

impl From<Progress> for JobState {
    fn from(progress: Progress) -> JobState {
        JobState {
            id: progress.id,
            title: progress.title,
            phase: progress.phase,
            waiting_for: progress.waiting_for,
            percent: progress.percent,
            error: progress.error,
            updated_at: progress.updated_at,
        }
    }
}

/// Where every write-up is, from `jobs/*.progress`.
#[tauri::command]
pub fn recording_job_state(app: AppHandle) -> Result<Vec<JobState>, String> {
    let dir = paths::jobs_dir(&app)?;
    Ok(jobs::list(&dir).into_iter().map(JobState::from).collect())
}

/// A recording's SHA-256 and size, for sync's "has it changed?".
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Digest {
    /// Hex, lower case.
    pub sha256: String,
    pub bytes: u64,
}

/// The digest of note `id`'s recording, or `null` when it has none here.
#[tauri::command]
pub async fn recording_digest(app: AppHandle, id: String) -> Result<Option<Digest>, String> {
    let dir = paths::recordings_dir(&app)?;
    let Some(file) = crate::recordings::recording_file(&dir, &id) else { return Ok(None) };
    // Hashing 115 MB belongs on the blocking pool, not the async runtime.
    tauri::async_runtime::spawn_blocking(move || digest_of(&file))
        .await
        .map_err(|e| format!("the digest did not finish: {e}"))
}

/// The file's SHA-256, streamed, or `None` when there is no such file.
#[cfg(not(target_os = "ios"))]
fn digest_of(file: &Path) -> Option<Digest> {
    use sha2::Digest as _;
    use std::io::Read as _;
    let mut source = std::fs::File::open(file).ok()?;
    let mut hasher = sha2::Sha256::new();
    let mut buffer = vec![0u8; 256 * 1024];
    let mut bytes = 0u64;
    loop {
        let read = source.read(&mut buffer).ok()?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
        bytes += read as u64;
    }
    let hash = hasher.finalize();
    Some(Digest { sha256: hash.iter().map(|b| format!("{b:02x}")).collect(), bytes })
}

/// iOS has no recorder and builds no sha2 (Cargo.toml's target table), so
/// nothing there has a digest: sync then reads the bytes only for an upload,
/// as it does below generation 20.
#[cfg(target_os = "ios")]
fn digest_of(_file: &Path) -> Option<Digest> {
    None
}

/// What `recording_delete` removed.
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Deleted {
    /// The ids whose recording was there and went.
    pub removed: Vec<String>,
    pub freed_bytes: u64,
}

/// Removes the recordings of `ids` and their write-up files. The notes keep
/// their length and their phrases: the words stay, the audio goes.
#[tauri::command]
pub async fn recording_delete(app: AppHandle, ids: Vec<String>) -> Result<Deleted, String> {
    let recordings = paths::recordings_dir(&app)?;
    let jobs = paths::jobs_dir(&app)?;
    tauri::async_runtime::spawn_blocking(move || delete_recordings(&recordings, &jobs, &ids))
        .await
        .map_err(|e| format!("the removal did not finish: {e}"))
}

fn delete_recordings(recordings: &Path, jobs: &Path, ids: &[String]) -> Deleted {
    let mut deleted = Deleted { removed: Vec::new(), freed_bytes: 0 };
    for id in ids {
        let Some(file) = crate::recordings::recording_file(recordings, id) else { continue };
        let bytes = std::fs::metadata(&file).map(|meta| meta.len()).unwrap_or(0);
        if std::fs::remove_file(&file).is_ok() {
            deleted.removed.push(id.clone());
            deleted.freed_bytes += bytes;
        }
        let _one = crate::lock::lock(&crate::guards::PROGRESS_FILE);
        let _ = std::fs::remove_file(jobs::progress_path(jobs, id));
        let _ = std::fs::remove_file(jobs::result_path(jobs, id));
    }
    deleted
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TempDir;

    #[test]
    fn the_config_is_written_where_the_write_up_reads_it() {
        let root = TempDir::new("recording-commands");
        let jobs = root.join("jobs");
        let config = JobConfig { model: "qwen3.5-4b".into(), one_pass_chars: 20_000, summaries: "off".into(), ..JobConfig::default() };
        keep_config(&jobs, &config).unwrap();
        let back: JobConfig = crate::fsx::read_json(&jobs::config_path(&jobs)).unwrap();
        assert_eq!(back, config);
    }

    #[test]
    fn a_result_is_taken_once_and_its_progress_goes_with_it() {
        let root = TempDir::new("recording-take");
        let jobs = root.join("jobs");
        let mut progress = Progress::queued("n1", "Meeting, 26 Sep 14:05");
        progress.phase = Phase::Done;
        progress.save(&jobs::progress_path(&jobs, "n1"), false).unwrap();
        let result = JobResult { summary: Some("# Launch\nSettled.".into()), model: "qwen3.5-4b".into(), transcript_chars: 41_230, finished_at: 5 };
        std::fs::write(jobs::result_path(&jobs, "n1"), serde_json::to_vec(&result).unwrap()).unwrap();
        let states = jobs::list(&jobs).into_iter().map(JobState::from).collect::<Vec<_>>();
        assert_eq!((states[0].id.as_str(), states[0].phase, states[0].title.as_str()), ("n1", Phase::Done, "Meeting, 26 Sep 14:05"));
        assert_eq!(serde_json::to_value(&states[0]).unwrap()["waitingFor"], serde_json::Value::Null);
        assert_eq!(take_result(&jobs, "n1"), Some(result.clone()));
        assert_eq!(take_result(&jobs, "n1"), None, "once");
        assert!(!jobs::progress_path(&jobs, "n1").exists(), "the progress goes with the result");
        // An id that climbs out of the folder names files there that must survive the take.
        std::fs::write(root.join("n1.json"), serde_json::to_vec(&result).unwrap()).unwrap();
        std::fs::write(root.join("n1.progress"), b"{}").unwrap();
        assert_eq!(take_result(&jobs, "../n1"), None);
        assert!(root.join("n1.json").exists() && root.join("n1.progress").exists(), "nothing outside jobs/ is read or removed");
    }

    #[test]
    fn removing_recordings_takes_the_audio_and_the_write_up_and_counts_the_bytes() {
        let root = TempDir::new("recording-delete");
        let recordings = root.join("recordings");
        let jobs = root.join("jobs");
        std::fs::create_dir_all(&recordings).unwrap();
        std::fs::create_dir_all(&jobs).unwrap();
        std::fs::write(recordings.join("n1.wav"), vec![0u8; 1000]).unwrap();
        std::fs::write(recordings.join("n2.wav"), vec![0u8; 500]).unwrap();
        std::fs::write(jobs::progress_path(&jobs, "n1"), b"{}").unwrap();
        std::fs::write(root.join("escape.wav"), b"x").unwrap();
        std::fs::write(root.join("escape.progress"), b"{}").unwrap();
        std::fs::write(root.join("escape.json"), b"{}").unwrap();
        let deleted = delete_recordings(&recordings, &jobs, &["n1".into(), "gone".into(), "../escape".into()]);
        assert_eq!(deleted, Deleted { removed: vec!["n1".into()], freed_bytes: 1000 });
        assert!(!recordings.join("n1.wav").exists() && !jobs::progress_path(&jobs, "n1").exists());
        assert!(recordings.join("n2.wav").exists() && root.join("escape.wav").exists());
        assert!(root.join("escape.progress").exists() && root.join("escape.json").exists(), "an escaping id takes no job files either");
        assert_eq!(serde_json::to_value(&deleted).unwrap()["freedBytes"], 1000);
    }

    #[cfg(not(target_os = "ios"))]
    #[test]
    fn a_digest_is_the_files_sha256_in_hex() {
        let root = TempDir::new("recording-digest");
        let file = root.join("n1.wav");
        std::fs::write(&file, b"abc").unwrap();
        let digest = digest_of(&file).unwrap();
        assert_eq!(digest.sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
        assert_eq!(digest.bytes, 3);
        assert_eq!(digest_of(&root.join("none.wav")), None);
    }
}
