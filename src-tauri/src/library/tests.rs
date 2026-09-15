use super::*;
use crate::store::{RecordedSegment, Recording, Store};

fn temp(label: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("glyph-library-{label}-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn read(root: &Path, path: &str) -> String {
    std::fs::read_to_string(root.join(path)).unwrap()
}

#[test]
fn a_new_note_is_a_markdown_file_in_the_inbox_with_its_id() {
    let root = temp("new");
    let mut library = Library::open_fs(&root).unwrap();
    let note = library.save_note("n1", "# Weekend trip\n\nBook the cabin.\n", "capture").unwrap();
    assert_eq!(note.path.as_deref(), Some("Inbox/Weekend trip.md"));
    let text = read(&root, "Inbox/Weekend trip.md");
    assert!(text.starts_with("---\nsource: capture\nid: n1\ncreated: "), "{text}");
    assert!(text.ends_with("---\n# Weekend trip\n\nBook the cabin.\n"));
    assert_eq!(note.body, "# Weekend trip\n\nBook the cabin.\n", "the page sees the body, not the front matter");
    assert!(root.join(".glyph/index.sqlite").exists() && root.join(".glyph/library.json").exists());
}

#[test]
fn a_changed_title_renames_the_file_and_a_clash_gets_a_number() {
    let root = temp("rename");
    let mut library = Library::open_fs(&root).unwrap();
    library.save_note("a", "# Plans\n", "editor").unwrap();
    library.save_note("b", "# Ideas\n", "editor").unwrap();
    let moved = library.save_note("b", "# Plans\n\nmore\n", "editor").unwrap();
    assert_eq!(moved.path.as_deref(), Some("Inbox/Plans 2.md"));
    assert!(!root.join("Inbox/Ideas.md").exists());
    // Editing the body under the same title leaves the numbered name alone.
    assert_eq!(library.save_note("b", "# Plans\n\neven more\n", "editor").unwrap().path.as_deref(), Some("Inbox/Plans 2.md"));
    assert_eq!(library.list_notes().unwrap().len(), 2);
}

#[test]
fn pinning_and_archiving_write_front_matter_and_keep_the_modified_time() {
    let root = temp("pin");
    let mut library = Library::open_fs(&root).unwrap();
    let saved = library.save_note("p", "# Pin me\n", "editor").unwrap();
    std::thread::sleep(std::time::Duration::from_millis(20));
    let pinned = library.set_starred("p", true).unwrap().unwrap();
    assert!(pinned.starred);
    assert_eq!(pinned.updated_at, saved.updated_at, "a pin doesn't move the note up the list");
    assert!(read(&root, "Inbox/Pin me.md").contains("pinned: true\n"));
    let archived = library.set_archived("p", true).unwrap().unwrap();
    assert!(archived.archived_at.is_some());
    library.set_starred("p", false).unwrap();
    let text = read(&root, "Inbox/Pin me.md");
    assert!(!text.contains("pinned") && text.contains("archived: 20"));
}

#[test]
fn files_written_by_other_apps_are_indexed_and_edits_are_picked_up() {
    let root = temp("external");
    let mut library = Library::open_fs(&root).unwrap();
    std::fs::create_dir_all(root.join("Work")).unwrap();
    std::fs::write(root.join("Work/HelloTrade.md"), "---\ntags: [trade]\npinned: true\n---\n# HelloTrade\n\n- [ ] Ship it\n").unwrap();
    std::fs::create_dir_all(root.join(".obsidian")).unwrap();
    std::fs::write(root.join(".obsidian/workspace.md"), "not a note").unwrap();
    let notes = library.list_notes().unwrap();
    assert_eq!(notes.len(), 1, "dot folders aren't notes");
    let note = &notes[0];
    assert_eq!(note.path.as_deref(), Some("Work/HelloTrade.md"));
    assert!(note.starred);
    let id = note.id.clone();

    std::thread::sleep(std::time::Duration::from_millis(20));
    std::fs::write(root.join("Work/HelloTrade.md"), "---\ntags: [trade]\npinned: true\n---\n# HelloTrade\n\n- [x] Ship it\n").unwrap();
    let fresh = library.get_note(&id).unwrap().unwrap();
    assert!(fresh.body.contains("- [x] Ship it"), "an edit made elsewhere is read again");
    assert_eq!(fresh.id, id, "the same file keeps its id until Glyph writes one in");

    library.save_note(&id, "# HelloTrade\n\n- [x] Ship it\n- [ ] Tell Sam\n", "editor").unwrap();
    let text = read(&root, "Work/HelloTrade.md");
    assert!(text.starts_with("---\ntags: [trade]\npinned: true\nid: "), "Glyph adds its keys after the person's: {text}");

    std::fs::remove_file(root.join("Work/HelloTrade.md")).unwrap();
    assert!(library.list_notes().unwrap().is_empty(), "a file deleted elsewhere leaves the list");
}

#[test]
fn a_copied_file_with_the_same_id_becomes_its_own_note() {
    let root = temp("copy");
    let mut library = Library::open_fs(&root).unwrap();
    library.save_note("same", "# Original\n", "editor").unwrap();
    std::fs::copy(root.join("Inbox/Original.md"), root.join("Inbox/Copy.md")).unwrap();
    let notes = library.list_notes().unwrap();
    assert_eq!(notes.len(), 2);
    let ids: HashSet<_> = notes.iter().map(|n| n.id.clone()).collect();
    assert_eq!(ids.len(), 2, "two files, two notes");
    assert!(ids.contains("same"));
}

#[test]
fn recordings_and_formatted_versions_live_beside_not_in_the_markdown() {
    let root = temp("sidecar");
    let mut library = Library::open_fs(&root).unwrap();
    library.save_note("r", "# Said\n", "capture").unwrap();
    let recording = Recording::new(1900, vec![RecordedSegment { text: "Said.".into(), start_ms: 0, end_ms: 1900 }]).unwrap();
    library.set_recording("r", Some(&recording)).unwrap();
    library.set_formatted("r", Some("# Said\n\nTidy."), Some(42), Some("qwen3.5-4b")).unwrap();
    let note = library.get_note("r").unwrap().unwrap();
    assert_eq!(note.recording_ms, Some(1900));
    assert_eq!(note.segments.unwrap()[0].text, "Said.");
    assert_eq!(note.formatted.as_deref(), Some("# Said\n\nTidy."));
    assert!(!read(&root, "Inbox/Said.md").contains("Tidy"), "the .md holds only the note");
    assert!(root.join(".glyph/notes/r.json").exists());
    let listed = library.list_notes().unwrap();
    assert_eq!(listed[0].formatted, None, "the list doesn't carry the formatted text");
    assert!(library.delete_note("r").unwrap());
    assert!(!root.join("Inbox/Said.md").exists() && !root.join(".glyph/notes/r.json").exists());
}

#[test]
fn the_index_is_only_a_cache() {
    let root = temp("rebuild");
    {
        let mut library = Library::open_fs(&root).unwrap();
        library.save_note("k", "# Kept\n![](image/abc.jpg)\n", "editor").unwrap();
        library.set_starred("k", true).unwrap();
    }
    std::fs::remove_file(root.join(".glyph/index.sqlite")).unwrap();
    let mut library = Library::open_fs(&root).unwrap();
    let note = library.get_note("k").unwrap().unwrap();
    assert!(note.starred && note.body.starts_with("# Kept"));
    assert!(library.image_in_use("abc.jpg").unwrap());
    assert!(!library.image_in_use("other.jpg").unwrap());
}

#[test]
fn moving_in_writes_every_old_note_out_and_is_safe_to_repeat() {
    let root = temp("move");
    let db = root.join("glyph.sqlite");
    let old = Store::open(&db).unwrap();
    old.save_note("m1", "# Old pinned\n\nwords", "editor").unwrap();
    old.set_starred("m1", true).unwrap();
    old.save_note("m2", "Spoken, untitled heading", "capture").unwrap();
    old.set_archived("m2", true).unwrap();
    let recording = Recording::new(500, vec![RecordedSegment { text: "Spoken".into(), start_ms: 0, end_ms: 500 }]).unwrap();
    old.set_recording("m2", Some(&recording)).unwrap();
    old.set_formatted("m1", Some("# Old pinned\n\nWords."), Some(7), Some("qwen3.5-2b")).unwrap();
    let before = old.get_note("m1").unwrap().unwrap();
    old.save_note("m3", "", "editor").unwrap();

    let mut library = Library::open_fs(&root.join("Library")).unwrap();
    assert!(!library.moved_in());
    assert_eq!(library.move_in(&old).unwrap(), 2);
    library.mark_moved_in("glyph.sqlite", 2).unwrap();
    assert!(library.moved_in());
    assert_eq!(library.move_in(&old).unwrap(), 2, "a second move finds them there and writes nothing new");

    let notes = library.list_notes().unwrap();
    assert_eq!(notes.len(), 2, "the note opened and left empty stays behind");
    assert!(!root.join("Library/Inbox/Untitled.md").exists());
    let m1 = library.get_note("m1").unwrap().unwrap();
    assert!(m1.starred);
    assert_eq!(m1.created_at, before.created_at);
    assert_eq!(m1.updated_at, before.updated_at, "the list keeps its order");
    assert_eq!(m1.formatted.as_deref(), Some("# Old pinned\n\nWords."));
    let m2 = library.get_note("m2").unwrap().unwrap();
    assert!(m2.archived_at.is_some());
    assert_eq!(m2.source, "capture");
    assert_eq!(m2.recording_ms, Some(500));
    assert_eq!(m2.path.as_deref(), Some("Inbox/Spoken, untitled heading.md"));
}

#[test]
fn dates_go_to_front_matter_and_come_back() {
    let at = 1_789_381_930_123;
    let text = iso(at);
    assert_eq!(text, "2026-09-14T10:32:10.123Z");
    assert_eq!(parse_iso(&text), Some(at));
    assert_eq!(parse_iso("2026-09-14"), Some(1_789_344_000_000));
    assert_eq!(parse_iso("2026-09-14T12:32:10.123+02:00"), Some(at));
    assert_eq!(parse_iso("not a date"), None);
}

#[test]
fn a_path_never_leaves_the_library() {
    let root = temp("escape");
    let vault = FsVault::new(&root).unwrap();
    assert!(vault.read("../secret.md").is_err());
    assert!(vault.write("/etc/x.md", "x").is_err());
}

#[test]
fn a_new_note_left_empty_never_becomes_a_file() {
    let root = temp("draft");
    let mut library = Library::open_fs(&root).unwrap();
    let draft = library.save_note("d", "", "editor").unwrap();
    assert_eq!(draft.path, None);
    assert!(library.vault.markdown().unwrap().is_empty(), "no Untitled.md");
    assert!(library.list_notes().unwrap().is_empty(), "the list leaves a draft out");
    assert_eq!(library.get_note("d").unwrap().map(|n| n.body), Some(String::new()), "but the open note still finds it");

    // The first words write the file, with the draft's own created time.
    let written = library.save_note("d", "Call Sam\n", "editor").unwrap();
    assert_eq!(written.path.as_deref(), Some("Inbox/Call Sam.md"));
    assert_eq!(written.created_at, draft.created_at);

    // Taking every word out again, with nothing else set, puts it back to a draft.
    assert_eq!(library.save_note("d", "", "editor").unwrap().path, None);
    assert!(library.vault.markdown().unwrap().is_empty());

    // A pin is something set: the draft becomes a file even without words, and stays one.
    library.set_starred("d", true).unwrap();
    assert_eq!(library.list_notes().unwrap().len(), 1);
    library.save_note("d", "words", "editor").unwrap();
    library.save_note("d", "", "editor").unwrap();
    assert_eq!(library.list_notes().unwrap().len(), 1, "a pinned note emptied is kept");

    // A file that was never a draft here (someone's own empty note) is never removed for being empty.
    std::fs::write(root.join("Empty.md"), "").unwrap();
    library.list_notes().unwrap();
    let theirs = library.list_notes().unwrap().into_iter().find(|n| n.path.as_deref() == Some("Empty.md")).unwrap();
    library.save_note(&theirs.id, "", "editor").unwrap();
    assert!(root.join("Empty.md").exists() || root.join("Untitled.md").exists());

    library.save_note("gone", "", "editor").unwrap();
    assert!(library.delete_note("gone").unwrap());
    assert_eq!(library.get_note("gone").unwrap(), None);
}
