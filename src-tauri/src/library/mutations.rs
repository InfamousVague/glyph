//! Voice commands' writes: a note changed (or created) by a command the
//! person confirmed from a preview, recorded in the index so it can be undone
//! even after the app restarts (docs/instruction-voice-commands.md).
//!
//! Every one is guarded by the note's revision and body. A command applies only
//! while the note is exactly what the preview was made from, and an undo
//! applies only while the note is exactly what the command left - so a later
//! edit, typed or synced, is never overwritten by either; it is answered as a
//! conflict instead.

use rusqlite::OptionalExtension;

use super::{Library, LibraryError, Result};
use crate::note::{now_ms, CommandMutation, CommandMutationResult, CommandUndoResult, PendingCommandUndo};

impl Library {
    /// Applies a confirmed preview only while its exact base is current, then
    /// records enough for guarded undo.
    pub fn apply_command(&mut self, change: &CommandMutation) -> Result<CommandMutationResult> {
        let current = self.get_note(&change.note_id)?;
        let matches = match (&current, change.before_revision) {
            (None, None) => true,
            (Some(note), Some(revision)) => note.revision == revision && change.before_body.as_deref() == Some(note.body.as_str()),
            _ => false,
        };
        if !matches {
            return Ok(CommandMutationResult::Conflict { current });
        }
        let note = match change.before_revision {
            Some(revision) => self
                .update_note(&change.note_id, &change.after_body, revision)?
                .ok_or_else(|| LibraryError::Store("the note changed during the command".into()))?,
            None => self
                .create_note(&change.note_id, &change.after_body, &change.source)?
                .ok_or_else(|| LibraryError::Store("the note id already exists".into()))?,
        };
        self.index.execute(
            "INSERT INTO command_mutations
             (id, note_id, kind, before_body, after_body, before_revision, after_revision, created_at, undone_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, NULL)",
            rusqlite::params![change.id, change.note_id, change.kind, change.before_body, change.after_body, change.before_revision, note.revision, now_ms()],
        )?;
        Ok(CommandMutationResult::Applied { mutation_id: change.id.clone(), note })
    }

    /// Reverses a command only while its exact result is still current.
    pub fn undo_command(&mut self, mutation_id: &str) -> Result<CommandUndoResult> {
        let record = self.index.query_row(
            "SELECT note_id, before_body, after_body, before_revision, after_revision, undone_at
             FROM command_mutations WHERE id = ?1",
            [mutation_id],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, Option<String>>(1)?, row.get::<_, String>(2)?, row.get::<_, Option<i64>>(3)?, row.get::<_, i64>(4)?, row.get::<_, Option<i64>>(5)?)),
        ).optional()?;
        let Some((note_id, before_body, after_body, before_revision, after_revision, undone_at)) = record else {
            return Ok(CommandUndoResult::NotFound);
        };
        if undone_at.is_some() {
            return Ok(CommandUndoResult::AlreadyUndone);
        }
        let current = self.get_note(&note_id)?;
        if !current.as_ref().is_some_and(|note| note.revision == after_revision && note.body == after_body) {
            return Ok(CommandUndoResult::Conflict { current });
        }
        let note = if let (Some(body), Some(_)) = (before_body, before_revision) {
            self.update_note(&note_id, &body, after_revision)?
        } else {
            self.delete_note(&note_id)?;
            None
        };
        self.index.execute(
            "UPDATE command_mutations SET undone_at = ?2 WHERE id = ?1",
            rusqlite::params![mutation_id, now_ms()],
        )?;
        Ok(CommandUndoResult::Undone { mutation_id: mutation_id.to_string(), note })
    }

    /// The newest command, from the last `max_age_ms`, whose result is still
    /// the note as it stands: what the page offers to undo again after the app
    /// was stopped mid-undo.
    pub fn latest_command_undo(&mut self, max_age_ms: i64) -> Result<Option<PendingCommandUndo>> {
        let cutoff = now_ms().saturating_sub(max_age_ms.max(0));
        let rows: Vec<(String, String, String, i64, String, i64)> = {
            let mut stmt = self.index.prepare(
                "SELECT id, note_id, kind, created_at, after_body, after_revision
                 FROM command_mutations WHERE undone_at IS NULL AND created_at >= ?1
                 ORDER BY created_at DESC, id DESC",
            )?;
            let mapped = stmt.query_map([cutoff], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?, row.get(4)?, row.get(5)?)))?;
            mapped.collect::<rusqlite::Result<_>>()?
        };
        for (mutation_id, note_id, kind, created_at, after_body, after_revision) in rows {
            if self.get_note(&note_id)?.is_some_and(|note| note.revision == after_revision && note.body == after_body) {
                return Ok(Some(PendingCommandUndo { mutation_id, note_id, kind, created_at }));
            }
        }
        Ok(None)
    }
}
