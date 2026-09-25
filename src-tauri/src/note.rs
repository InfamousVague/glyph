//! A note, as every part of the crate and the page agree on it, and NOT ONE
//! `tauri::` TYPE IN THIS FILE.
//!
//! `library/` keeps the notes as Markdown files, `store.rs` reads the database
//! they lived in before 1.3.0, `commands.rs` hands them to the page, and
//! `src/app/core/store.ts` is the page's idea of one. This module is the
//! vocabulary all of them share: the `Note` that crosses the IPC seam, a
//! recording's phrases and the limits a recording keeps, a guarded command
//! mutation and its answers, and the clock and the ids a note is stamped with.
//!
//! THE RULE, and why the obvious tidy-up breaks it. This module, `store`,
//! `library/`, `fsx`, `lock`, `whisper/` and `llm/` hold no Tauri type, so a
//! process with no Tauri in it can link them. DESIGN section 6.1 planned for
//! the side-key capture to run in a separate process with no webview and no
//! `tauri::Builder`, writing its transcript over JNI. That is not how capture
//! shipped - it runs in the app's own page (section 13) - but keeping these
//! modules free of Tauri keeps that door open, and the update-alert worker
//! (update_alerts.rs) now walks through the same kind of door for `ota`. A
//! `tauri::AppHandle` parameter anywhere in them would mean such a process
//! cannot link the one function it exists to call - and the tempting one is
//! the convenience: an `open` that took a handle and found the app data
//! directory by itself. So the CALLER supplies every path instead. The command
//! layer resolves them (`paths`), a process with no Tauri resolves its own,
//! and neither has to agree with the other about how a directory is found -
//! only about which file it holds.

use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

/// One note, in the shape the page already expects.
///
/// The `camelCase` rename is the reason this is a struct and not a row. The
/// index spells a column `created_at`, TypeScript reads `createdAt`, and the
/// translation happens once here instead of in the command layer, the page's
/// `store.ts`, and again in the localStorage fallback that has to produce the
/// identical shape for `npm run dev` in a browser (DESIGN section 5). Three
/// copies of a naming convention is three chances for one of them to drift.
///
/// `Deserialize` because one note does come back whole: `store_apply` takes a
/// note exactly as another device has it (docs/SYNC.md). A field the page may
/// leave out of an older shape is `#[serde(default)]` for that reason.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Note {
    pub id: String,
    pub body: String,
    /// Milliseconds since the epoch. Set once, when the note is first written.
    pub created_at: i64,
    /// Milliseconds since the epoch. Moved by every save.
    pub updated_at: i64,
    /// Where the note came from - "editor", "capture", and whatever the side
    /// key learns to say about itself. A birth fact: see `create_note`.
    pub source: String,
    /// Pinned to the top of the list.
    pub starred: bool,
    /// Milliseconds since the epoch when archived; `None` for a note in the list.
    pub archived_at: Option<i64>,
    /// The length of the note's kept recording; `None` when it has none.
    pub recording_ms: Option<i64>,
    /// The recording's phrases and their timing. Only `get_note` fills this;
    /// in `list_notes` it is always `None`, the list being fetched on every
    /// return to the app and the tapes needing only the length.
    pub segments: Option<Vec<RecordedSegment>>,
    /// The on-device model's version of the body. Only `get_note` fills this;
    /// the list carries `formatted_for` and `formatted_model` and not the text.
    pub formatted: Option<String>,
    /// The page's hash of the body `formatted` was written from.
    pub formatted_for: Option<i64>,
    /// The model that wrote it, by the page's id.
    pub formatted_model: Option<String>,
    /// Where the note's file is in the library (library/), relative to it: `Inbox/AttackFM.md`.
    /// None for a note read from the old database.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    /// Monotonic body version. Command mutations compare this before writing,
    /// so a preview can never overwrite an edit made after it was shown.
    #[serde(default = "default_revision")]
    pub revision: i64,
}

fn default_revision() -> i64 {
    1
}

impl Note {
    /// A note with no words yet, born `at` from `source`: what a new note is
    /// until its first save (a draft, `library/`).
    pub fn blank(id: &str, source: &str, at: i64) -> Note {
        Note {
            id: id.to_string(),
            body: String::new(),
            created_at: at,
            updated_at: at,
            source: source.to_string(),
            starred: false,
            archived_at: None,
            recording_ms: None,
            segments: None,
            formatted: None,
            formatted_for: None,
            formatted_model: None,
            path: None,
            revision: 1,
        }
    }
}

/// One atomic command write. `before_revision = None` creates a note; a
/// number updates exactly that version. The caller supplies final Markdown,
/// but only deterministic application code is allowed to construct it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandMutation {
    pub id: String,
    pub note_id: String,
    pub kind: String,
    pub before_revision: Option<i64>,
    pub before_body: Option<String>,
    pub after_body: String,
    pub source: String,
}

/// What `apply_command_mutation` answers: the note as the command left it, or
/// the note as it is now when the command's base had moved on.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "status", rename_all = "kebab-case", rename_all_fields = "camelCase")]
pub enum CommandMutationResult {
    Applied { mutation_id: String, note: Note },
    Conflict { current: Option<Note> },
}

/// What `undo_command_mutation` answers. `Conflict` when the note has changed
/// since the command, which an undo never overwrites.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "status", rename_all = "kebab-case", rename_all_fields = "camelCase")]
pub enum CommandUndoResult {
    Undone { mutation_id: String, note: Option<Note> },
    Conflict { current: Option<Note> },
    AlreadyUndone,
    NotFound,
}

/// A command still undoable after a restart, for `latest_command_mutation`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PendingCommandUndo {
    pub mutation_id: String,
    pub note_id: String,
    pub kind: String,
    pub created_at: i64,
}

/// One committed phrase of a recording, as the page's `Segment` has it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RecordedSegment {
    pub text: String,
    pub start_ms: u64,
    pub end_ms: u64,
}

/// A recording's length and phrases, checked. Only [`Recording::new`] makes
/// one, so no note is ever kept with a recording that is not.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Recording {
    ms: i64,
    segments: Vec<RecordedSegment>,
}

/// A day of audio. A capture is minutes; this only refuses nonsense.
const MAX_RECORDING_MS: i64 = 24 * 60 * 60 * 1000;
/// Ten hours at the engine's phrase rate, far past any note.
const MAX_SEGMENTS: usize = 20_000;
const MAX_SEGMENT_CHARS: usize = 10_000;

impl Recording {
    pub fn new(ms: i64, segments: Vec<RecordedSegment>) -> std::result::Result<Recording, String> {
        if !(0..=MAX_RECORDING_MS).contains(&ms) {
            return Err(format!("a recording of {ms} ms is not a length"));
        }
        if segments.len() > MAX_SEGMENTS {
            return Err(format!("{} segments is more than a recording can have", segments.len()));
        }
        for (index, segment) in segments.iter().enumerate() {
            if segment.start_ms > segment.end_ms {
                return Err(format!("segment {index} ends before it starts"));
            }
            if segment.text.chars().count() > MAX_SEGMENT_CHARS {
                return Err(format!("segment {index} is too long to be one phrase"));
            }
        }
        Ok(Recording { ms, segments })
    }

    /// The recording's length in milliseconds.
    pub fn ms(&self) -> i64 {
        self.ms
    }

    /// Its phrases, in order.
    pub fn segments(&self) -> &[RecordedSegment] {
        &self.segments
    }
}

/// The wall clock in milliseconds, which is what a phone's list of notes
/// actually sorts by.
///
/// Milliseconds rather than seconds because two saves a second apart are
/// common and two saves in the same second are not rare - a debounced editor
/// save landing next to a capture is exactly that. Milliseconds are not fine
/// enough to separate two writes inside one tick either, which is why the list
/// carries a tiebreak and why tests space their writes deliberately.
pub fn now_ms() -> i64 {
    ms_since_epoch(SystemTime::now())
}

/// A moment as milliseconds since the epoch - a file's modified time, or now.
///
/// A moment before 1970 answers 0 rather than panicking. That is a phone with
/// no battery-backed clock at first boot, and the honest outcome is a note
/// that sorts to the bottom until it is next edited, not a save that dies.
pub fn ms_since_epoch(at: SystemTime) -> i64 {
    at.duration_since(UNIX_EPOCH).map(|since| since.as_millis() as i64).unwrap_or(0)
}

/// A fresh note id: a UUIDv4, in the hyphenated form the page compares as a
/// string.
///
/// Random, not sequential and not time-based, because the capture process
/// mints ids without ever asking the app what the last one was - there is no
/// shared counter to ask. Nothing may read meaning out of an id; the order is
/// `updated_at`'s job.
pub fn new_id() -> String {
    uuid::Uuid::new_v4().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn segment(text: &str, start_ms: u64, end_ms: u64) -> RecordedSegment {
        RecordedSegment { text: text.into(), start_ms, end_ms }
    }

    #[test]
    fn a_recording_that_is_not_one_is_refused() {
        assert!(Recording::new(-1, vec![]).is_err());
        assert!(Recording::new(MAX_RECORDING_MS + 1, vec![]).is_err());
        assert!(Recording::new(1000, vec![segment("backwards", 900, 100)]).is_err());
        assert!(Recording::new(1000, vec![segment(&"x".repeat(MAX_SEGMENT_CHARS + 1), 0, 1)]).is_err());
        assert!(Recording::new(0, vec![]).is_ok(), "a key held and nothing said is still a recording");
    }

    #[test]
    fn a_clock_before_1970_is_the_start_of_the_list_not_a_panic() {
        assert_eq!(ms_since_epoch(UNIX_EPOCH - std::time::Duration::from_secs(60)), 0);
        assert_eq!(ms_since_epoch(UNIX_EPOCH + std::time::Duration::from_millis(1_789_381_930_123)), 1_789_381_930_123);
        assert!(now_ms() > 1_789_381_930_123, "the clock is after this was written");
    }

    #[test]
    fn a_new_id_is_a_random_uuid_the_page_compares_as_text() {
        let (one, two) = (new_id(), new_id());
        assert_ne!(one, two);
        assert_eq!(uuid::Uuid::parse_str(&one).unwrap().get_version_num(), 4);
        assert_eq!(one.len(), 36, "hyphenated");
    }

    #[test]
    fn a_note_from_an_older_page_without_a_path_or_revision_still_reads() {
        let sent = r#"{"id":"n1","body":"hi","createdAt":1,"updatedAt":2,"source":"editor","starred":false,"archivedAt":null,"recordingMs":null,"segments":null,"formatted":null,"formattedFor":null,"formattedModel":null}"#;
        let note: Note = serde_json::from_str(sent).unwrap();
        assert_eq!((note.path, note.revision), (None, 1));
        let blank = Note::blank("n2", "capture", 7);
        let json = serde_json::to_value(&blank).unwrap();
        assert_eq!(json["createdAt"], 7);
        assert!(json.get("path").is_none(), "a note with no file says nothing about one");
        assert_eq!(serde_json::from_value::<Note>(json).unwrap(), blank);
    }
}
