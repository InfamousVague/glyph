//! A canvas note's derived `<Title>.canvas` beside its `.md` (docs/MARKDOWN_FIRST.md
//! §5 gap 14, §11 decision 7; Matt, 2026-10-31): the same JSON Canvas 1.0 the
//! note's body holds, as a file of its own, so Obsidian opens it (it opens only
//! `*.canvas`) and the publisher draws it (tauri/publish). The `.md` stays the
//! stored form for now; this file follows it as `<Title>.versions` does
//! (versions.rs): written with it, renamed, moved and trashed with it, deleted
//! with it. Not a note: `FsVault::walk` lists `.md` files only.
//!
//! The way back: a canvas edited in Obsidian is a `.canvas` newer than its
//! `.md`. Opening the note (`get_note`) reads it back into the note's body,
//! which writes the `.md` and brings the two level again. The app's own writes
//! set the `.canvas` to the `.md`'s time, so "newer" means another app's hand.
//! A `.canvas` holding what the body already holds is never read back, whatever
//! its time (a pin keeps the `.md`'s old time, which would otherwise look like an
//! edit).
//!
//! What a canvas body is here (lib/canvas/json_canvas.dart `isCanvasBody`): the
//! page's own front matter block, then a JSON object with a `nodes` or `edges`
//! array and nothing else.

use super::names::front_matter_end;
use super::{Library, Result};

/// The canvas file of the note at `path`: `Work/Roadmap.md` → `Work/Roadmap.canvas`.
pub(super) fn canvas_path(path: &str) -> String {
    let bare = path.strip_suffix(".md").or_else(|| path.strip_suffix(".MD")).unwrap_or(path);
    format!("{bare}.canvas")
}

/// Where the page's own front matter block ends in `body`, as a byte offset: 0 where it has none.
fn page_front_len(body: &str) -> usize {
    let lines: Vec<&str> = body.split('\n').collect();
    let end = front_matter_end(&lines);
    if end == 0 {
        return 0;
    }
    // The lines through the closing fence, each with its newline.
    lines[..end].iter().map(|line| line.len() + 1).sum::<usize>().min(body.len())
}

/// Whether `text` is JSON Canvas enough to be one: an object with a `nodes` or `edges` array.
fn is_canvas_json(text: &str) -> bool {
    let trimmed = text.trim();
    if !trimmed.starts_with('{') {
        return false;
    }
    match serde_json::from_str::<serde_json::Value>(trimmed) {
        Ok(serde_json::Value::Object(map)) => map.get("nodes").is_some_and(|v| v.is_array()) || map.get("edges").is_some_and(|v| v.is_array()),
        _ => false,
    }
}

/// The JSON Canvas `body` holds, where the body is a canvas: everything after the page's front matter, trimmed.
pub(super) fn canvas_json(body: &str) -> Option<&str> {
    let json = body[page_front_len(body)..].trim();
    is_canvas_json(json).then_some(json)
}

/// `body` with its canvas replaced by `json`, its front matter kept character for character (lib/canvas/json_canvas.dart
/// `withCanvas`).
fn with_canvas(body: &str, json: &str) -> String {
    format!("{}{}", &body[..page_front_len(body)], json.trim())
}

impl Library {
    /// The `.canvas` beside the note at `path` brought level with `body`: written where the body is a canvas and the
    /// file does not already hold its JSON, and set to the note's time (`modified_ms`) so an edit by another app
    /// reads as newer. A note that is words leaves any `.canvas` beside it alone: it is not this note's to remove.
    pub(super) fn keep_canvas(&self, path: &str, body: &str, modified_ms: i64) {
        let Some(json) = canvas_json(body) else { return };
        let file = canvas_path(path);
        let wanted = format!("{json}\n");
        let same = self.vault.read(&file).is_ok_and(|held| held.trim() == json);
        if !same && self.vault.write(&file, &wanted).is_err() {
            return;
        }
        let _ = self.vault.keep_modified(&file, modified_ms);
    }

    /// The body as a `.canvas` edited since the note was written would have it, or `None` where there is no such
    /// file, it is no newer than the note, it is not a canvas, or it holds what the body holds already.
    pub(super) fn canvas_edited(&self, path: &str, body: &str) -> Option<String> {
        let held = canvas_json(body)?;
        let file = canvas_path(path);
        if !self.vault.exists(&file) {
            return None;
        }
        let (note, canvas) = (self.vault.stat(path).ok()?, self.vault.stat(&file).ok()?);
        if canvas.modified_ms <= note.modified_ms {
            return None;
        }
        let text = self.vault.read(&file).ok()?;
        let json = text.trim();
        if json == held || !is_canvas_json(json) {
            return None;
        }
        Some(with_canvas(body, json))
    }

    /// A note's canvas file renamed with it, when it has one: as versions.rs does, a file in the way keeps it where
    /// it was.
    pub(super) fn rename_canvas(&self, from: &str, to: &str) -> Result<()> {
        let (was, now) = (canvas_path(from), canvas_path(to));
        if self.vault.exists(&was) && !self.vault.exists(&now) {
            self.vault.rename(&was, &now)?;
        }
        Ok(())
    }

    /// A note's canvas file gone, with the note.
    pub(super) fn remove_canvas(&self, path: &str) {
        let _ = self.vault.remove(&canvas_path(path));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TempDir;

    const CANVAS: &str = "---\ntitle: \"Roadmap\"\n---\n{\n\t\"nodes\":[\n\t\t{\"id\":\"a\",\"type\":\"text\",\"x\":0,\"y\":0,\"width\":200,\"height\":80,\"text\":\"Beta\"}\n\t],\n\t\"edges\":[]\n}";

    fn read(root: &std::path::Path, path: &str) -> String {
        std::fs::read_to_string(root.join(path)).unwrap()
    }

    #[test]
    fn a_canvas_file_is_named_for_its_markdown_file() {
        assert_eq!(canvas_path("Work/Roadmap.md"), "Work/Roadmap.canvas");
        assert_eq!(canvas_path("Deep/Old.MD"), "Deep/Old.canvas");
    }

    #[test]
    fn a_canvas_body_is_the_pages_front_matter_then_json_canvas_and_nothing_else() {
        assert_eq!(page_front_len(CANVAS), 25);
        assert_eq!(canvas_json(CANVAS), Some(&CANVAS[25..]));
        assert_eq!(canvas_json("{\"nodes\":[],\"edges\":[]}"), Some("{\"nodes\":[],\"edges\":[]}"), "no front matter is fine");
        assert_eq!(canvas_json("---\ntitle: A\n---\n# Words\n\n{\"nodes\":[]}"), None, "words before the JSON");
        assert_eq!(canvas_json("---\ntitle: A\n---\n{\"title\":\"not a canvas\"}"), None, "an object with no nodes or edges");
        assert_eq!(canvas_json("# Plan\n\nwords"), None);
        assert_eq!(canvas_json("---\ntitle: A\n---\n"), None);
        assert_eq!(with_canvas(CANVAS, "{\"nodes\":[],\"edges\":[]}\n"), "---\ntitle: \"Roadmap\"\n---\n{\"nodes\":[],\"edges\":[]}");
    }

    #[test]
    fn the_canvas_file_holds_the_notes_json_and_goes_where_the_note_goes() {
        let root = TempDir::new("canvas");
        let mut library = Library::open_fs(&root).unwrap();
        library.save_note("w", "# Plan\nwords", "editor").unwrap();
        assert!(!root.join("Inbox/Plan.canvas").exists(), "a note of words has no canvas file");

        let saved = library.save_note("c", CANVAS, "editor").unwrap();
        assert_eq!(saved.path.as_deref(), Some("Inbox/Roadmap.md"));
        assert_eq!(read(&root, "Inbox/Roadmap.canvas"), format!("{}\n", &CANVAS[25..]), "the JSON alone, as Obsidian wants it");
        assert_eq!(library.list_notes().unwrap().len(), 2, "not a note");
        // Level with the note: its time is the note's (to the millisecond the vault keeps), so nothing reads as an edit.
        let note = library.vault.stat("Inbox/Roadmap.md").unwrap().modified_ms;
        let canvas = library.vault.stat("Inbox/Roadmap.canvas").unwrap().modified_ms;
        assert_eq!(canvas, note);
        assert_eq!(library.get_note("c").unwrap().unwrap().body, CANVAS, "nothing read back");

        // Renamed with its title.
        let renamed = CANVAS.replace("Roadmap", "Launch map");
        library.save_note("c", &renamed, "editor").unwrap();
        assert!(!root.join("Inbox/Roadmap.canvas").exists());
        assert!(root.join("Inbox/Launch map.canvas").exists());

        // The canvas changed: the file follows.
        let moved = renamed.replace("\"x\":0", "\"x\":40");
        library.save_note("c", &moved, "editor").unwrap();
        assert!(read(&root, "Inbox/Launch map.canvas").contains("\"x\":40"));

        // Filed elsewhere, from another device.
        let mut note = library.get_note("c").unwrap().unwrap();
        note.path = Some("workspaces/Work/Launch map.md".into());
        library.apply_note(&note).unwrap();
        assert!(root.join("workspaces/Work/Launch map.canvas").exists() && !root.join("Inbox/Launch map.canvas").exists());

        // A pin keeps the note's old time: the canvas file, no newer in what it holds, is left as it is.
        std::thread::sleep(std::time::Duration::from_millis(20));
        library.set_starred("c", true).unwrap();
        assert_eq!(library.get_note("c").unwrap().unwrap().body, moved);

        // Deleted with it.
        assert!(library.delete_note("c").unwrap());
        assert!(!root.join("workspaces/Work/Launch map.canvas").exists());
    }

    #[test]
    fn a_canvas_edited_in_another_app_is_read_back_into_the_note_when_it_is_opened() {
        let root = TempDir::new("canvas-back");
        let mut library = Library::open_fs(&root).unwrap();
        library.save_note("c", CANVAS, "editor").unwrap();
        // Obsidian writes the file later, its own way (tabs, a trailing newline).
        std::thread::sleep(std::time::Duration::from_millis(20));
        let edited = "{\n\t\"nodes\":[\n\t\t{\"id\":\"a\",\"type\":\"text\",\"x\":0,\"y\":0,\"width\":200,\"height\":80,\"text\":\"Beta\"},\n\t\t{\"id\":\"b\",\"type\":\"text\",\"x\":300,\"y\":0,\"width\":200,\"height\":80,\"text\":\"GA\"}\n\t],\n\t\"edges\":[{\"id\":\"e\",\"fromNode\":\"a\",\"toNode\":\"b\"}]\n}\n";
        std::fs::write(root.join("Inbox/Roadmap.canvas"), edited).unwrap();
        let later = std::time::SystemTime::now() + std::time::Duration::from_secs(5);
        std::fs::File::options().write(true).open(root.join("Inbox/Roadmap.canvas")).unwrap().set_modified(later).unwrap();

        let opened = library.get_note("c").unwrap().unwrap();
        assert_eq!(opened.body, format!("---\ntitle: \"Roadmap\"\n---\n{}", edited.trim_end()), "the page's block kept, the JSON the other app's");
        assert!(read(&root, "Inbox/Roadmap.md").ends_with(edited.trim_end()), "the .md is the stored form still");
        assert_eq!(read(&root, "Inbox/Roadmap.canvas"), edited, "the file is left as the other app wrote it");
        // Level again: opened once more, nothing changes.
        let again = library.get_note("c").unwrap().unwrap();
        assert_eq!((&again.body, again.revision), (&opened.body, opened.revision));

        // A file that is newer but not a canvas, or that holds what the note holds, reads back nothing.
        std::fs::write(root.join("Inbox/Roadmap.canvas"), "not json").unwrap();
        std::fs::File::options().write(true).open(root.join("Inbox/Roadmap.canvas")).unwrap().set_modified(later + std::time::Duration::from_secs(5)).unwrap();
        assert_eq!(library.get_note("c").unwrap().unwrap().body, opened.body);
        // And a note's words never read a `.canvas` back, whatever sits beside them.
        library.save_note("w", "# Notes\nwords", "editor").unwrap();
        std::fs::write(root.join("Inbox/Notes.canvas"), edited).unwrap();
        std::fs::File::options().write(true).open(root.join("Inbox/Notes.canvas")).unwrap().set_modified(later).unwrap();
        assert_eq!(library.get_note("w").unwrap().unwrap().body, "# Notes\nwords");
    }
}
