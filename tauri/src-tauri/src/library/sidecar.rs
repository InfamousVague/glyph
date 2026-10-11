//! What a note has that isn't text: `.glyph/notes/<id>.json`, beside the
//! library rather than in the Markdown, so a person's file holds only their
//! note. A recording's length and phrases and the formatted version live here;
//! a note with none of them has no sidecar at all.

use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use super::{Library, Result};
use crate::note::{Note, RecordedSegment};

/// `.glyph/notes/<id>.json`: what a note has that isn't text.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Sidecar {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) recording_ms: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) segments: Option<Vec<RecordedSegment>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) formatted: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) formatted_for: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) formatted_model: Option<String>,
}

impl Sidecar {
    pub(super) fn is_empty(&self) -> bool {
        *self == Sidecar::default()
    }
}

/// What `note` keeps beside its file: a note that arrived whole, by sync or
/// from the old database, brings all of it.
impl From<&Note> for Sidecar {
    fn from(note: &Note) -> Sidecar {
        Sidecar {
            recording_ms: note.recording_ms,
            segments: note.segments.clone(),
            formatted: note.formatted.clone(),
            formatted_for: note.formatted_for,
            formatted_model: note.formatted_model.clone(),
        }
    }
}

impl Library {
    /// `.glyph/notes/<id>.json`, for an id that may become a file name (`fsx::plain_id`).
    pub(super) fn sidecar_path(&self, id: &str) -> Option<PathBuf> {
        crate::fsx::plain_id(id).then(|| self.vault.glyph_dir().join("notes").join(format!("{id}.json")))
    }

    /// Note `id`'s sidecar, or an empty one when it has none (or it cannot be read).
    pub(super) fn sidecar(&self, id: &str) -> Sidecar {
        self.sidecar_path(id).and_then(|path| crate::fsx::read_json(&path)).unwrap_or_default()
    }

    /// Keeps `sidecar` for note `id`, whole or not at all - or removes it when
    /// there is nothing left in it. An id that may not name a file keeps none.
    pub(super) fn write_sidecar(&self, id: &str, sidecar: &Sidecar) -> Result<()> {
        let Some(path) = self.sidecar_path(id) else { return Ok(()) };
        if sidecar.is_empty() {
            let _ = std::fs::remove_file(path);
            return Ok(());
        }
        crate::fsx::write_atomically(&path, serde_json::to_string(sidecar).unwrap_or_default().as_bytes())?;
        Ok(())
    }
}
