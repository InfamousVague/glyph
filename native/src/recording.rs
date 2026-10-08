//! The app's door to a meeting's write-up and its tapes (the `voice` feature): what
//! `../glyph/src-tauri/src/recording_commands.rs` is to the Tauri app, command for command. What the app gives
//! the write-up (its config), what it takes from it (the result, the state of every job), and two calls about
//! the audio itself (a digest for sync, a removal for the Tapes row). The files are `jobs.rs`'s shapes.
//!
//! - `ai_keep_job_config {config: {model, prompts: {summary, notes, piece, parts}, onePassChars, pieceChars,
//!   temperature, writeUp, summaries}}` -> `null`: writes `jobs/config.json`, whole or not at all. At launch and
//!   on change, so a write-up with the app closed uses what the app would have.
//! - `recording_result_take {id}` -> `{summary, model, transcriptChars, finishedAt} | null`, once: the result
//!   and the progress file go with it.
//! - `recording_job_state` -> `[{id, title, phase, waitingFor, percent, error, updatedAt}]`, every
//!   `jobs/*.progress`. `phase` is `queued`, `listening`, `summarizing`, `waiting`, `needsModel`, `failed`,
//!   `done` or `cancelled`.
//! - `recording_digest {id}` (job) -> `{sha256, bytes} | null`: the recording's SHA-256, hashed on the job's
//!   thread, so sync never reads an hour's audio to learn whether it changed.
//! - `recording_delete {ids}` -> `{removed, freedBytes}`: each recording's WAV and write-up files go; the note
//!   keeps its length and its phrases.
//!
//! STARTING AND STOPPING A WRITE-UP ON THE PHONE ARE KOTLIN'S, as in the Tauri app (`ghost_md/meeting`'s
//! `writeUp` and `cancelWriteUp`, android/…/MainActivity.kt): the one side that knows both WorkManager and the
//! JNI door (`recording_jobs.rs`, included as it is). The three commands below are this crate's own, the same
//! three functions of `write_up.rs` behind that door, for where there is no Kotlin (the Mac) and for tests:
//!
//! - `write_up_finish {id, title}` -> `{recordedMs}`: the recording closed, its header put right, its length on
//!   the note, a `queued` progress file.
//! - `write_up_run {id, options?}` (job) -> one of `write_up::Answer`'s shapes (`{done, title, line,
//!   transcriptChars, summary}`, `{alreadyDone}`, `{retry}`, `{needsModel, again}`, `{error, again}`,
//!   `{cancelled}`, `{gone}`). `options` is `write_up::Options` (`now`, `fresh`, `requestedAt`, `title`,
//!   `charging`, `batteryPercent`, `thermal`, `appInFront`); progress is the `.progress` file.
//! - `write_up_cancel {id, reason?}` (job) -> `{cancelled}`: a run for the note ended with `reason` ("cancel"
//!   by default, which also marks the file cancelled; "thermal", "timeout", "meeting").

use std::path::Path;
use std::sync::Arc;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::dispatch::{read, Core};
use crate::jobs::{self, JobConfig, JobResult, Phase, Progress};

const COMMANDS: &[&str] = &["ai_keep_job_config", "recording_result_take", "recording_job_state", "recording_digest", "recording_delete", "write_up_finish", "write_up_run", "write_up_cancel"];

pub fn has(command: &str) -> bool {
    COMMANDS.contains(&command)
}

fn keep_config(jobs: &Path, config: &JobConfig) -> Result<(), String> {
    crate::fsx::make_dir(jobs)?;
    let json = serde_json::to_vec(config).map_err(|e| format!("the job config could not be written: {e}"))?;
    crate::fsx::write_atomically(&jobs::config_path(jobs), &json).map_err(|e| format!("the job config could not be written: {e}"))
}

/// The result file read and removed with its progress, under the lock every writer of a progress file takes;
/// an id that may not name a file has none.
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

/// One write-up as the app draws it.
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
        JobState { id: progress.id, title: progress.title, phase: progress.phase, waiting_for: progress.waiting_for, percent: progress.percent, error: progress.error, updated_at: progress.updated_at }
    }
}

/// A recording's SHA-256 and size, for sync's "has it changed?".
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Digest {
    /// Hex, lower case.
    pub sha256: String,
    pub bytes: u64,
}

/// The file's SHA-256, streamed, or `None` when there is no such file.
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

/// What `recording_delete` removed.
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Deleted {
    /// The ids whose recording was there and went.
    pub removed: Vec<String>,
    pub freed_bytes: u64,
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

#[derive(Deserialize)]
struct Keep {
    config: JobConfig,
}

#[derive(Deserialize)]
struct ById {
    id: String,
}

#[derive(Deserialize)]
struct ByIds {
    ids: Vec<String>,
}

#[derive(Deserialize)]
struct Finish {
    id: String,
    #[serde(default)]
    title: String,
}

#[derive(Deserialize)]
struct Run {
    id: String,
    #[serde(default)]
    options: crate::write_up::Options,
}

#[derive(Deserialize)]
struct Cancel {
    id: String,
    #[serde(default)]
    reason: Option<String>,
}

fn said<T: Serialize>(value: T) -> Result<Value, String> {
    serde_json::to_value(value).map_err(|e| format!("the answer could not be written: {e}"))
}

pub fn call(core: &Arc<Core>, command: &str, args: Value) -> Result<Value, String> {
    let data = core.data_dir().to_path_buf();
    let recordings = data.join(crate::paths::RECORDINGS);
    let jobs_dir = jobs::dir(&data);
    match command {
        "ai_keep_job_config" => {
            let Keep { config } = read(command, args)?;
            keep_config(&jobs_dir, &config)?;
            Ok(Value::Null)
        }
        "recording_result_take" => {
            let ById { id } = read(command, args)?;
            said(take_result(&jobs_dir, &id))
        }
        "recording_job_state" => said(jobs::list(&jobs_dir).into_iter().map(JobState::from).collect::<Vec<_>>()),
        "recording_digest" => {
            let ById { id } = read(command, args)?;
            let Some(file) = crate::recordings::recording_file(&recordings, &id) else { return Ok(json!({ "id": crate::work::start("digest", |_| Ok(Value::Null))? })) };
            Ok(json!({ "id": crate::work::start("digest", move |_| said(digest_of(&file)))? }))
        }
        "recording_delete" => {
            let ByIds { ids } = read(command, args)?;
            said(delete_recordings(&recordings, &jobs_dir, &ids))
        }
        "write_up_finish" => {
            let Finish { id, title } = read(command, args)?;
            Ok(json!({ "recordedMs": crate::write_up::finish(&data, &id, &title)? }))
        }
        "write_up_run" => {
            let Run { id, options } = read(command, args)?;
            Ok(json!({ "id": crate::work::start("write-up", move |_| serde_json::from_str(&crate::write_up::run(&data, &id, &options).to_json()).map_err(|e| e.to_string()))? }))
        }
        "write_up_cancel" => {
            let Cancel { id, reason } = read(command, args)?;
            let reason = reason.unwrap_or_else(|| "cancel".to_string());
            Ok(json!({ "id": crate::work::start("write-up-cancel", move |_| Ok(json!({ "cancelled": crate::write_up::cancel(&data, &id, &reason) })))? }))
        }
        _ => Err(format!("Ghost.md's core has no command named {command}.")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::capture::tests::{asked, core, job, models};
    use crate::test_support::TempDir;
    use std::time::Duration;

    #[test]
    fn the_copied_functions_are_the_tauri_apps_own_lines() {
        let source = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../glyph/src-tauri/src/recording_commands.rs");
        let source = std::fs::read_to_string(&source).unwrap_or_else(|e| panic!("{}: {e}", source.display()));
        let squeezed = |text: &str| text.split_whitespace().collect::<Vec<_>>().join(" ");
        let (theirs, mine) = (squeezed(&source), squeezed(include_str!("recording.rs")));
        // The bodies that decide what is read and removed, compared without their line breaks.
        for body in [
            "let result: JobResult = crate::fsx::read_json(&jobs::result_path(jobs, id))?; let _one = crate::lock::lock(&crate::guards::PROGRESS_FILE); let _ = std::fs::remove_file(jobs::result_path(jobs, id)); let _ = std::fs::remove_file(jobs::progress_path(jobs, id)); Some(result)",
            "let Some(file) = crate::recordings::recording_file(recordings, id) else { continue }; let bytes = std::fs::metadata(&file).map(|meta| meta.len()).unwrap_or(0); if std::fs::remove_file(&file).is_ok() { deleted.removed.push(id.clone()); deleted.freed_bytes += bytes; }",
            "crate::fsx::write_atomically(&jobs::config_path(jobs), &json)",
            "Some(Digest { sha256: hash.iter().map(|b| format!(\"{b:02x}\")).collect(), bytes })",
        ] {
            assert!(theirs.contains(body), "recording_commands.rs no longer says: {body}");
            assert!(mine.contains(body), "recording.rs no longer says: {body}");
        }
    }

    #[test]
    fn the_config_is_written_where_the_write_up_reads_it() {
        let root = TempDir::new("recording-commands");
        let core = Arc::new(Core::open(&root.join("data"), &root.join("cache")).unwrap());
        let config = json!({ "model": "qwen3.5-4b", "prompts": { "summary": "S", "notes": "", "piece": "", "parts": "" }, "onePassChars": 20000, "pieceChars": 12000, "temperature": 0.3, "writeUp": "now", "summaries": "off" });
        assert_eq!(call(&core, "ai_keep_job_config", json!({ "config": config })), Ok(Value::Null));
        let back: JobConfig = crate::fsx::read_json(&jobs::config_path(&root.join("data/jobs"))).unwrap();
        assert_eq!((back.model.as_str(), back.one_pass_chars, back.summaries.as_str(), back.prompts.summary.as_str(), back.write_up.as_str()), ("qwen3.5-4b", 20_000, "off", "S", "now"));
        assert!(call(&core, "ai_keep_job_config", json!({})).unwrap_err().starts_with("invalid args for command `ai_keep_job_config`"));
    }

    #[test]
    fn a_result_is_taken_once_and_tapes_are_removed_and_digested() {
        let root = TempDir::new("recording-take");
        let core = Arc::new(Core::open(&root.join("data"), &root.join("cache")).unwrap());
        let (jobs, recordings) = (root.join("data/jobs"), root.join("data/recordings"));
        std::fs::create_dir_all(&recordings).unwrap();
        let mut progress = Progress::queued("n1", "Meeting, 26 Sep 14:05");
        progress.phase = Phase::Done;
        progress.save(&jobs::progress_path(&jobs, "n1"), false).unwrap();
        let result = JobResult { summary: Some("# Launch\nSettled.".into()), model: "qwen3.5-4b".into(), transcript_chars: 41_230, finished_at: 5 };
        std::fs::write(jobs::result_path(&jobs, "n1"), serde_json::to_vec(&result).unwrap()).unwrap();
        let states = call(&core, "recording_job_state", json!({})).unwrap();
        assert_eq!(states[0]["id"], "n1");
        assert_eq!(states[0]["phase"], "done");
        assert_eq!(states[0]["title"], "Meeting, 26 Sep 14:05");
        assert_eq!(states[0]["waitingFor"], Value::Null);
        assert!(states[0]["updatedAt"].as_i64().unwrap() > 0 && states[0]["percent"] == 0 && states[0]["error"].is_null());
        assert_eq!(call(&core, "recording_result_take", json!({ "id": "n1" })), Ok(json!({ "summary": "# Launch\nSettled.", "model": "qwen3.5-4b", "transcriptChars": 41_230, "finishedAt": 5 })));
        assert_eq!(call(&core, "recording_result_take", json!({ "id": "n1" })), Ok(Value::Null), "once");
        assert!(!jobs::progress_path(&jobs, "n1").exists(), "the progress goes with the result");
        assert_eq!(call(&core, "recording_result_take", json!({ "id": "../n1" })), Ok(Value::Null));

        std::fs::write(recordings.join("n1.wav"), b"abc").unwrap();
        std::fs::write(recordings.join("n2.wav"), vec![0u8; 500]).unwrap();
        std::fs::write(jobs::progress_path(&jobs, "n1"), b"{}").unwrap();
        std::fs::write(root.join("data/escape.wav"), b"x").unwrap();
        // The digest is a job; this test owns no listener, so it reads the events of its own process.
        let begun = call(&core, "recording_digest", json!({ "id": "n1" })).unwrap();
        let id = begun["id"].as_str().unwrap().to_string();
        let end = crate::events::tests::wait_for(Duration::from_secs(20), move |event, payload| event == crate::work::END && payload["id"] == id.as_str()).unwrap();
        assert_eq!(end["ok"], json!({ "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "bytes": 3 }));
        assert_eq!(digest_of(&recordings.join("none.wav")), None);
        let deleted = call(&core, "recording_delete", json!({ "ids": ["n1", "gone", "../escape"] })).unwrap();
        assert_eq!(deleted, json!({ "removed": ["n1"], "freedBytes": 3 }));
        assert!(!recordings.join("n1.wav").exists() && !jobs::progress_path(&jobs, "n1").exists());
        assert!(recordings.join("n2.wav").exists() && root.join("data/escape.wav").exists());
    }

    /// A meeting's tape through the three doors with summaries off (the speech model alone): closed, written up,
    /// its state said, its result taken, and the note holding its transcript.
    #[test]
    fn a_tape_is_closed_and_written_up_and_its_result_taken() {
        let _one = crate::lock::lock(&crate::guards::TEST_SERIAL);
        let Some((_, data, _)) = core() else { return eprintln!("SKIPPED: GLYPH_MODELS_DIR is not a folder") };
        let id = "meeting-1";
        assert!(asked("create_note", json!({ "id": id, "body": "# Meeting, 8 Oct 10:00\n", "source": "editor" }))["ok"].is_object());
        std::fs::create_dir_all(data.join("recordings")).unwrap();
        // The tape as the recorder writes one (the fixture's own header is another program's).
        let heard: Vec<i16> = crate::whisper::wav::read(&models().unwrap().join("fixture.wav")).unwrap().iter().map(|s| (s * 32767.0) as i16).collect();
        crate::whisper::wav::write_pcm16(&data.join("recordings/meeting-1.wav"), &heard, false).unwrap();
        assert_eq!(asked("ai_keep_job_config", json!({ "config": { "model": "qwen3.5-2b", "summaries": "off", "writeUp": "now" } })), json!({ "ok": null }));
        let finished = asked("write_up_finish", json!({ "id": id, "title": "Meeting, 8 Oct 10:00" }));
        let recorded = finished["ok"]["recordedMs"].as_u64().unwrap_or_else(|| panic!("{finished}"));
        assert!(recorded > 1_000);
        let queued = asked("recording_job_state", json!({}));
        assert!(queued["ok"].as_array().unwrap().iter().any(|job| job["id"] == id && job["phase"] == "queued"), "{queued}");
        let began = std::time::Instant::now();
        let answer = job("write_up_run", json!({ "id": id, "options": { "now": true, "charging": true } }), Duration::from_secs(600)).unwrap();
        eprintln!("write-up of {recorded} ms with summaries off: {} ms: {answer}", began.elapsed().as_millis());
        assert_eq!(answer["done"], true, "{answer}");
        assert!(answer["transcriptChars"].as_u64().unwrap() > 20 && answer["summary"] == false);
        let taken = asked("recording_result_take", json!({ "id": id }));
        assert_eq!(taken["ok"]["summary"], Value::Null);
        assert!(taken["ok"]["transcriptChars"].as_u64().unwrap() > 20 && taken["ok"]["finishedAt"].as_i64().unwrap() > 0);
        let note = asked("get_note", json!({ "id": id }));
        assert!(note["ok"]["body"].as_str().unwrap().contains("## Transcript"), "{note}");
        assert_eq!(note["ok"]["recordingMs"].as_u64(), Some(recorded));
        assert_eq!(job("write_up_cancel", json!({ "id": id }), Duration::from_secs(20)), Ok(json!({ "cancelled": false })), "nothing is running to cancel");
        assert_eq!(job("write_up_run", json!({ "id": "no-such-tape" }), Duration::from_secs(20)), Ok(json!({ "gone": true })));
        assert_eq!(asked("write_up_finish", json!({ "id": "../x" }))["err"], "not a note id");
    }
}
