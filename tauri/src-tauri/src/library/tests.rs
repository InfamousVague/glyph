//! The library against real folders in the temp directory: what a save, a pin,
//! a sync, a move-in and another app's edit each leave on disk, and what the
//! page is answered with.

use super::dates::parse_iso;
use super::*;
use crate::note::{CommandMutation, CommandMutationResult, CommandUndoResult, RecordedSegment, Recording};
use crate::store::Store;
use crate::test_support::TempDir;

fn read(root: &Path, path: &str) -> String {
    std::fs::read_to_string(root.join(path)).unwrap()
}

#[test]
fn a_new_note_is_a_markdown_file_in_the_inbox_with_its_id() {
    let root = TempDir::new("library-new");
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
    let root = TempDir::new("library-rename");
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
    let root = TempDir::new("library-pin");
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
    let root = TempDir::new("library-external");
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
    // The person's `tags:` is the page's key, read out of the one block at the top of the body; `pinned:` is the library's.
    assert_eq!(fresh.body, "---\ntags: [trade]\n---\n# HelloTrade\n\n- [x] Ship it\n");

    library.save_note(&id, "---\ntags: [trade]\n---\n# HelloTrade\n\n- [x] Ship it\n- [ ] Tell Sam\n", "editor").unwrap();
    let text = read(&root, "Work/HelloTrade.md");
    assert!(text.starts_with("---\ntags: [trade]\npinned: true\nid: "), "Glyph adds its keys after the person's: {text}");
    assert_eq!(text.matches("---\n").count(), 2, "and in the one block the file had: {text}");

    std::fs::remove_file(root.join("Work/HelloTrade.md")).unwrap();
    assert!(library.list_notes().unwrap().is_empty(), "a file deleted elsewhere leaves the list");
}

/// A ticket's properties are the page's own front matter (docs/DESIGN.md §157), a block of its own after the library's:
/// its `id: GHO-12` is never taken for the note's id, and a save, a pin and a synced edit leave every line of it as the
/// page wrote it.
#[test]
fn a_tickets_front_matter_is_the_pages_and_is_kept_whole() {
    let root = TempDir::new("library-ticket");
    let mut library = Library::open_fs(&root).unwrap();
    let ticket = "---\ntype: ticket\nid: GHO-12\nstatus: In progress\nassignee: Sam\nblocked-by: \"[[GHO-9]]\"\nlabels: [bug, ui]\n---\n# Fix the login loop\n\nIt loops.\n";
    let saved = library.save_note("t1", ticket, "editor").unwrap();
    assert_eq!(saved.id, "t1", "the library's id, not the ticket's key");
    assert_eq!(saved.body, ticket, "the page sees its own block as it wrote it");
    assert_eq!(saved.path.as_deref(), Some("Inbox/Fix the login loop.md"));
    let text = read(&root, "Inbox/Fix the login loop.md");
    assert!(text.starts_with("---\nid: t1\ncreated: "), "the library's own block first: {text}");
    assert!(text.ends_with(ticket), "{text}");

    library.set_starred("t1", true).unwrap();
    let changed = ticket.replace("status: In progress", "status: Done");
    library.save_note("t1", &changed, "editor").unwrap();
    let again = library.get_note("t1").unwrap().unwrap();
    assert_eq!(again.body, changed);
    assert!(again.starred);
    library.apply_note(&Note { body: ticket.to_string(), ..remote("t1", ticket) }).unwrap();
    assert_eq!(library.get_note("t1").unwrap().unwrap().body, ticket, "a synced edit lands whole");
    assert_eq!(library.list_notes().unwrap().len(), 1);
}

/// The other shape (docs/MARKDOWN_FIRST.md §11, Matt, 2026-10-31: "one block, phased"): a ticket written by another app
/// as ONE block, the library's keys and the page's together in any order. The index reads its id, pin and creation from
/// it, the page sees the page's keys as a block of its own, and every write - a pin, a save, a synced edit - keeps the
/// file one block with every key the person wrote.
#[test]
fn a_one_block_file_reads_as_the_pages_and_stays_one_block() {
    let root = TempDir::new("library-one-block");
    let mut library = Library::open_fs(&root).unwrap();
    let file = "---\nstatus: In progress\nid: t2\ndue: 2026-11-01\ncreated: 2026-10-01T08:00:00.000Z\ntype: ticket\npinned: true\nissue: GHO-14\n---\n# Fix the fold\n\nIt folds.\n";
    std::fs::create_dir_all(root.join("Inbox")).unwrap();
    std::fs::write(root.join("Inbox/Fix the fold.md"), file).unwrap();
    assert_eq!(library.list_notes().unwrap().len(), 1);
    let note = library.get_note("t2").unwrap().expect("indexed by the id in the one block");
    assert!(note.starred);
    assert_eq!(note.created_at, parse_iso("2026-10-01T08:00:00.000Z").unwrap());
    assert_eq!(note.body, "---\nstatus: In progress\ndue: 2026-11-01\ntype: ticket\nissue: GHO-14\n---\n# Fix the fold\n\nIt folds.\n", "the page's keys, in their order, as a block of their own");

    // A managed key written: the one block keeps every page key and gains no second block.
    library.set_starred("t2", false).unwrap();
    let text = read(&root, "Inbox/Fix the fold.md");
    assert_eq!(text, file.replace("pinned: true\n", ""), "{text}");

    // The page's own words saved back unchanged: byte for byte.
    let before = read(&root, "Inbox/Fix the fold.md");
    library.save_note("t2", &note.body, "editor").unwrap();
    assert_eq!(read(&root, "Inbox/Fix the fold.md"), before, "an unchanged round trip rewrites nothing");

    // A page key changed: still one block, the library's lines first (`updated:` among them, the save's), the page's after.
    library.save_note("t2", &note.body.replace("status: In progress", "status: Done"), "editor").unwrap();
    let text = read(&root, "Inbox/Fix the fold.md");
    assert!(text.contains("\nupdated: 20"), "{text}");
    let without_updated: String = text.lines().filter(|line| !line.starts_with("updated: ")).map(|line| format!("{line}\n")).collect();
    assert_eq!(without_updated, "---\nid: t2\ncreated: 2026-10-01T08:00:00.000Z\nstatus: Done\ndue: 2026-11-01\ntype: ticket\nissue: GHO-14\n---\n# Fix the fold\n\nIt folds.\n");

    // A synced edit lands in the one block too, with the library's keys stamped from the note.
    let synced = Note { path: Some("Inbox/Fix the fold.md".into()), ..remote("t2", "---\nstatus: Done\ntype: ticket\nissue: GHO-14\n---\n# Fix the fold\n\nIt folds, fixed.\n") };
    library.apply_note(&synced).unwrap();
    let text = read(&root, "Inbox/Fix the fold.md");
    assert_eq!(text.matches("---\n").count(), 2, "{text}");
    assert!(text.contains("pinned: true\n") && text.contains("source: capture\n") && text.contains("issue: GHO-14\n"), "{text}");
    assert_eq!(library.get_note("t2").unwrap().unwrap().body, synced.body);
    assert_eq!(library.list_notes().unwrap().len(), 1);
}

/// A one-block ticket from another app with Ghost.md's own old key, `id: GHO-12`, and no library id: the index gives
/// the note an id of its own rather than taking the ticket's, the page reads the ticket's key, and the first write moves
/// it to `issue:` so the library's `id:` can take the line.
#[test]
fn a_one_block_tickets_own_id_is_never_the_notes() {
    let root = TempDir::new("library-one-block-id");
    let mut library = Library::open_fs(&root).unwrap();
    std::fs::create_dir_all(root.join("Inbox")).unwrap();
    std::fs::write(root.join("Inbox/Loop.md"), "---\ntype: ticket\nid: GHO-12\nstatus: To do\n---\n# Loop\n").unwrap();
    let notes = library.list_notes().unwrap();
    assert_eq!(notes.len(), 1);
    assert_ne!(notes[0].id, "GHO-12", "a ticket's key is not a note's id");
    assert_eq!(notes[0].body, "---\ntype: ticket\nid: GHO-12\nstatus: To do\n---\n# Loop\n", "the page sees the ticket's key as it was written");
    library.set_starred(&notes[0].id, true).unwrap();
    let text = read(&root, "Inbox/Loop.md");
    assert_eq!(text, "---\ntype: ticket\nid: GHO-12\nstatus: To do\npinned: true\n---\n# Loop\n", "a pin alone leaves the ticket's id where it is: {text}");
    library.save_note(&notes[0].id, "---\ntype: ticket\nid: GHO-12\nstatus: Done\n---\n# Loop\n", "editor").unwrap();
    let text = read(&root, "Inbox/Loop.md");
    assert!(text.contains("issue: GHO-12\n") && text.contains(&format!("id: {}\n", notes[0].id)), "{text}");
    assert_eq!(text.matches("---\n").count(), 2, "{text}");
    assert_eq!(library.get_note(&notes[0].id).unwrap().unwrap().body, "---\ntype: ticket\nissue: GHO-12\nstatus: Done\n---\n# Loop\n");
}

/// With the writer switched on (frontmatter.rs `ONE_BLOCK`, off until every device reads both shapes), a two-block file
/// becomes one block at its next write, with nothing lost, and a new note's page keys are written into the library's
/// block. Off, the two-block file is left as it is.
#[test]
fn with_one_block_on_a_two_block_file_is_merged_at_the_next_write() {
    let root = TempDir::new("library-one-block-on");
    let two = "---\nid: t3\ncreated: 2026-10-01T08:00:00.000Z\n---\n---\ntype: ticket\nid: GHO-3\nstatus: To do\n---\n# Two\n";
    std::fs::create_dir_all(root.join("Inbox")).unwrap();
    std::fs::write(root.join("Inbox/Two.md"), two).unwrap();
    {
        let mut library = Library::open_fs(&root).unwrap();
        let note = library.get_note("t3").unwrap().unwrap();
        assert_eq!(note.body, "---\ntype: ticket\nid: GHO-3\nstatus: To do\n---\n# Two\n");
        library.save_note("t3", &note.body, "editor").unwrap();
        assert_eq!(read(&root, "Inbox/Two.md"), two, "off: an unchanged round trip rewrites nothing");
        library.set_starred("t3", true).unwrap();
        assert_eq!(read(&root, "Inbox/Two.md"), two.replacen("---\n---", "pinned: true\n---\n---", 1), "off: a pin keeps the two blocks");
        library.set_starred("t3", false).unwrap();
    }
    frontmatter::one_block_for_test(true);
    let mut library = Library::open_fs(&root).unwrap();
    library.set_starred("t3", true).unwrap();
    let text = read(&root, "Inbox/Two.md");
    assert_eq!(text, "---\nid: t3\ncreated: 2026-10-01T08:00:00.000Z\npinned: true\ntype: ticket\nissue: GHO-3\nstatus: To do\n---\n# Two\n", "on: a pin merges the blocks into one, the ticket's key as issue:");
    let note = library.get_note("t3").unwrap().unwrap();
    assert_eq!(note.body, "---\ntype: ticket\nissue: GHO-3\nstatus: To do\n---\n# Two\n", "the page reads the ticket's key under issue:");
    library.save_note("t3", &note.body.replace("To do", "Done"), "editor").unwrap();
    let text = read(&root, "Inbox/Two.md");
    let without_updated: String = text.lines().filter(|line| !line.starts_with("updated: ")).map(|line| format!("{line}\n")).collect();
    assert_eq!(without_updated, "---\nid: t3\ncreated: 2026-10-01T08:00:00.000Z\npinned: true\ntype: ticket\nissue: GHO-3\nstatus: Done\n---\n# Two\n", "{text}");
    let fresh = library.save_note("t4", "---\ntype: ticket\nstatus: To do\n---\n# Fresh\n", "editor").unwrap();
    let text = read(&root, "Inbox/Fresh.md");
    assert_eq!(text.matches("---\n").count(), 2, "on: a new note is one block: {text}");
    assert!(text.starts_with("---\nid: t4\ncreated: ") && text.ends_with("type: ticket\nstatus: To do\n---\n# Fresh\n"), "{text}");
    assert_eq!(fresh.body, "---\ntype: ticket\nstatus: To do\n---\n# Fresh\n");
    frontmatter::one_block_for_test(false);
}

#[test]
fn a_copied_file_with_the_same_id_becomes_its_own_note() {
    let root = TempDir::new("library-copy");
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
    let root = TempDir::new("library-sidecar");
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
fn a_sidecar_is_kept_only_under_an_id_that_may_become_a_file_name() {
    let root = TempDir::new("library-sidecar-ids");
    let mut library = Library::open_fs(&root).unwrap();
    let longest = "x".repeat(crate::fsx::PLAIN_ID_MAX);
    assert!(library.sidecar_path(&longest).is_some());
    // The cap a recording's file always had: before `fsx::plain_id` a sidecar had none.
    assert!(library.sidecar_path(&format!("{longest}x")).is_none());
    assert!(library.sidecar_path("../escape").is_none() && library.sidecar_path("").is_none());
    library.save_note("s", "# Said\n", "capture").unwrap();
    library.set_formatted("s", Some("# Said\n\nTidy."), Some(1), Some("qwen3.5-4b")).unwrap();
    let kept: Vec<_> = std::fs::read_dir(root.join(".glyph/notes")).unwrap().map(|e| e.unwrap().file_name()).collect();
    assert_eq!(kept, ["s.json"], "written whole, with nothing left beside it");
}

#[test]
fn the_index_is_only_a_cache() {
    let root = TempDir::new("library-rebuild");
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
fn a_film_is_in_use_while_a_note_names_it_and_only_as_a_film() {
    let root = TempDir::new("library-films");
    let mut library = Library::open_fs(&root).unwrap();
    library.save_note("v", "# Harbour\n\n[![video 0:12](image/p1.jpg)](video/f1.mp4)\n", "editor").unwrap();
    assert!(library.video_in_use("f1.mp4").unwrap());
    assert!(library.image_in_use("p1.jpg").unwrap(), "the poster is an ordinary picture");
    assert!(!library.video_in_use("p1.jpg").unwrap(), "a picture's name is not a film's");
    assert!(!library.video_in_use("f2.mp4").unwrap());
    // `_` and `%` are wildcards to LIKE, and nothing to instr.
    assert!(!library.video_in_use("f_.mp4").unwrap());
}

/// Two handles are opened in one process now: the app's, and a meeting's
/// write-up on its own thread. After a version bump both find the old number
/// at once; `index::open` takes a process-wide lock round the rebuild so the
/// second cannot drop what the first has just filled.
#[test]
fn two_handles_opened_at_once_on_an_older_index_both_open() {
    let root = TempDir::new("library-two-handles");
    {
        let mut library = Library::open_fs(&root).unwrap();
        library.save_note("k", "# Kept\n", "editor").unwrap();
    }
    // Many rounds, each pair released together: one round in thirty lost the race without the lock.
    for round in 0..40 {
        let index = rusqlite::Connection::open(root.join(".glyph/index.sqlite")).unwrap();
        index.execute_batch("PRAGMA user_version = 1;").unwrap();
        drop(index);
        let together = std::sync::Arc::new(std::sync::Barrier::new(2));
        let openers: Vec<_> = (0..2)
            .map(|_| {
                let root = root.to_path_buf();
                let together = std::sync::Arc::clone(&together);
                std::thread::spawn(move || {
                    together.wait();
                    let mut library = Library::open_fs(&root).unwrap();
                    library.list_notes().unwrap().len()
                })
            })
            .collect();
        for opener in openers {
            assert_eq!(opener.join().unwrap(), 1, "round {round}: each handle sees the note");
        }
        let index = rusqlite::Connection::open(root.join(".glyph/index.sqlite")).unwrap();
        let version: i64 = index.query_row("PRAGMA user_version", [], |row| row.get(0)).unwrap();
        assert_eq!(version, 3);
        let rows: i64 = index.query_row("SELECT count(*) FROM notes", [], |row| row.get(0)).unwrap();
        assert_eq!(rows, 1, "round {round}: the rows the first rebuild filled are still there");
    }
}

/// The app's handle and a meeting's write-up both write the same note in one
/// process. Each update names the revision it read; two at the same revision,
/// released together from two handles, must never both win, or the later file
/// write overwrites the earlier with no conflict seen (`WRITING`).
#[test]
fn two_handles_writing_one_revision_at_once_never_both_win() {
    let root = TempDir::new("library-two-writers");
    Library::open_fs(&root).unwrap().save_note("n1", "# Meeting\n", "capture").unwrap();
    for round in 0..20 {
        let revision = Library::open_fs(&root).unwrap().get_note("n1").unwrap().unwrap().revision;
        let together = std::sync::Arc::new(std::sync::Barrier::new(2));
        let writers: Vec<_> = ["editor", "write-up"]
            .into_iter()
            .map(|who| {
                let root = root.to_path_buf();
                let together = std::sync::Arc::clone(&together);
                std::thread::spawn(move || {
                    let mut library = Library::open_fs(&root).unwrap();
                    together.wait();
                    library.update_note("n1", &format!("# Meeting\n\n{who} {round}\n"), revision).unwrap().map(|note| note.body)
                })
            })
            .collect();
        let won: Vec<String> = writers.into_iter().filter_map(|writer| writer.join().unwrap()).collect();
        assert_eq!(won.len(), 1, "round {round}: exactly one write at revision {revision}");
        let note = Library::open_fs(&root).unwrap().get_note("n1").unwrap().unwrap();
        assert_eq!((note.revision, note.body.as_str()), (revision + 1, won[0].as_str()), "round {round}: the winner's words, one revision on");
    }
}

#[test]
fn moving_in_writes_every_old_note_out_and_is_safe_to_repeat() {
    let root = TempDir::new("library-move");
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
fn a_path_never_leaves_the_library() {
    let root = TempDir::new("library-escape");
    let vault = FsVault::new(&root).unwrap();
    assert!(vault.read("../secret.md").is_err());
    assert!(vault.write("/etc/x.md", "x").is_err());
}

#[test]
fn a_new_note_left_empty_never_becomes_a_file() {
    let root = TempDir::new("library-draft");
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

fn remote(id: &str, body: &str) -> Note {
    Note {
        id: id.to_string(),
        body: body.to_string(),
        created_at: parse_iso("2026-01-02T03:04:05.000Z").unwrap(),
        updated_at: parse_iso("2026-03-04T05:06:07.000Z").unwrap(),
        source: "capture".to_string(),
        starred: true,
        archived_at: None,
        recording_ms: Some(1500),
        segments: Some(vec![RecordedSegment { text: "hello".into(), start_ms: 0, end_ms: 900 }]),
        formatted: Some("# Hello".into()),
        formatted_for: Some(42),
        formatted_model: Some("m".into()),
        path: Some("Work/Trips/Hello.md".into()),
        revision: 7,
    }
}

#[test]
fn a_synced_note_keeps_its_own_times_folder_and_what_isnt_text() {
    let root = TempDir::new("library-apply-new");
    let mut library = Library::open_fs(&root).unwrap();
    let applied = library.apply_note(&remote("s1", "# Hello\n\nfrom the phone\n")).unwrap();
    let wanted = remote("s1", "# Hello\n\nfrom the phone\n");
    assert_eq!(applied, wanted, "the note reads back exactly as it was sent");
    let text = read(&root, "Work/Trips/Hello.md");
    assert!(text.contains("pinned: true\n") && text.contains("created: 2026-01-02T03:04:05.000Z\n"), "{text}");
    // It sorts by when it was written there, not when it arrived here.
    library.save_note("local", "# Newer\n", "editor").unwrap();
    let list = library.list_notes().unwrap();
    assert_eq!(list.iter().map(|n| n.id.as_str()).collect::<Vec<_>>(), ["local", "s1"]);
}

#[test]
fn a_synced_edit_updates_the_file_in_place_and_keeps_local_front_matter() {
    let root = TempDir::new("library-apply-edit");
    let mut library = Library::open_fs(&root).unwrap();
    library.apply_note(&remote("s2", "# Hello\n")).unwrap();
    let path = root.join("Work/Trips/Hello.md");
    let text = std::fs::read_to_string(&path).unwrap().replacen("---\n", "---\ntags: [trip]\n", 1);
    std::fs::write(&path, text).unwrap();
    library.scan().unwrap();

    // The device's `tags: [trip]` is the page's key now, in the body every device syncs: the edit comes back with it.
    assert_eq!(library.get_note("s2").unwrap().unwrap().body, "---\ntags: [trip]\n---\n# Hello\n");
    let mut edit = remote("s2", "---\ntags: [trip]\n---\n# Goodbye\n\nchanged\n");
    edit.starred = false;
    edit.archived_at = Some(parse_iso("2026-03-05T00:00:00.000Z").unwrap());
    edit.recording_ms = None;
    edit.segments = None;
    edit.formatted = None;
    edit.formatted_for = None;
    edit.formatted_model = None;
    let applied = library.apply_note(&edit).unwrap();
    assert_eq!(applied.path.as_deref(), Some("Work/Trips/Goodbye.md"), "a new title elsewhere is a new name here");
    assert!(!path.exists());
    let text = read(&root, "Work/Trips/Goodbye.md");
    assert!(text.contains("tags: [trip]") && !text.contains("pinned") && text.contains("archived: 2026-03-05"), "{text}");
    assert_eq!(text.matches("---\n").count(), 2, "still the one block: {text}");
    assert_eq!(applied.recording_ms, None);
    assert!(!root.join(".glyph/notes/s2.json").exists(), "nothing left beside it");
    assert_eq!(library.list_notes().unwrap().len(), 1);
}

#[test]
fn a_synced_note_whose_folder_is_taken_or_unsafe_lands_in_the_inbox_or_beside_it() {
    let root = TempDir::new("library-apply-safe");
    let mut library = Library::open_fs(&root).unwrap();
    let mut escape = remote("s3", "# Sneaky\n");
    escape.path = Some("../outside.md".into());
    assert_eq!(library.apply_note(&escape).unwrap().path.as_deref(), Some("Inbox/Sneaky.md"));
    let mut hidden = remote("s4", "# Hidden\n");
    hidden.path = Some(".glyph/x.md".into());
    assert_eq!(library.apply_note(&hidden).unwrap().path.as_deref(), Some("Inbox/Hidden.md"));
    library.save_note("mine", "# Hello\n", "editor").unwrap();
    let mut clash = remote("s5", "# Hello\n");
    clash.path = Some("Inbox/Hello.md".into());
    assert_eq!(library.apply_note(&clash).unwrap().path.as_deref(), Some("Inbox/Hello 2.md"));
    assert_eq!(library.get_note("mine").unwrap().unwrap().body, "# Hello\n", "the note already there is untouched");
}

#[test]
fn a_synced_note_replaces_a_draft_of_the_same_id() {
    let root = TempDir::new("library-apply-draft");
    let mut library = Library::open_fs(&root).unwrap();
    library.save_note("d", "", "editor").unwrap();
    library.apply_note(&remote("d", "# Hello\n")).unwrap();
    assert_eq!(library.get_note("d").unwrap().unwrap().body, "# Hello\n");
    library.save_note("d", "", "editor").unwrap();
    assert!(library.get_note("d").unwrap().is_some(), "a synced note is not a draft to be dropped");
}

#[test]
fn a_stale_writer_cannot_resurrect_a_deleted_library_note() {
    let root = TempDir::new("library-deleted-cas");
    let mut library = Library::open_fs(&root).unwrap();
    let original = library.create_note("gone", "# Gone\n", "capture").unwrap().unwrap();
    assert!(library.delete_note(&original.id).unwrap());
    assert_eq!(library.update_note(&original.id, "# Returned\n", original.revision).unwrap(), None);
    assert_eq!(library.get_note(&original.id).unwrap(), None);
}

#[test]
fn command_mutation_is_cas_guarded_and_undo_survives_reopen() {
    let root = TempDir::new("library-command-cas");
    let mut library = Library::open_fs(&root).unwrap();
    let before = library.create_note("todo", "To-Do\n", "editor").unwrap().unwrap();
    let mutation = CommandMutation {
        id: "m1".into(),
        note_id: before.id.clone(),
        kind: "append".into(),
        before_revision: Some(before.revision),
        before_body: Some(before.body.clone()),
        after_body: "To-Do\n\n- [ ] Wash dishes\n".into(),
        source: "capture".into(),
    };
    let applied = library.apply_command(&mutation).unwrap();
    assert!(matches!(applied, CommandMutationResult::Applied { .. }));
    drop(library);

    let mut reopened = Library::open_fs(&root).unwrap();
    let undone = reopened.undo_command("m1").unwrap();
    assert!(matches!(undone, CommandUndoResult::Undone { .. }));
    assert_eq!(reopened.get_note("todo").unwrap().unwrap().body, "To-Do\n");
    assert_eq!(reopened.undo_command("m1").unwrap(), CommandUndoResult::AlreadyUndone);
}

#[test]
fn stale_command_preview_never_overwrites_a_later_library_edit() {
    let root = TempDir::new("library-command-conflict");
    let mut library = Library::open_fs(&root).unwrap();
    let shown = library.create_note("todo", "To-Do\n", "editor").unwrap().unwrap();
    let edited = library.update_note("todo", "To-Do\n\nTyped later.\n", shown.revision).unwrap().unwrap();
    let result = library.apply_command(&CommandMutation {
        id: "stale".into(),
        note_id: shown.id,
        kind: "append".into(),
        before_revision: Some(shown.revision),
        before_body: Some(shown.body),
        after_body: "To-Do\n\n- [ ] Voice\n".into(),
        source: "capture".into(),
    }).unwrap();
    assert_eq!(result, CommandMutationResult::Conflict { current: Some(edited) });
}

fn command(id: &str, note: &Note, after: &str) -> CommandMutation {
    CommandMutation {
        id: id.into(),
        note_id: note.id.clone(),
        kind: "append".into(),
        before_revision: Some(note.revision),
        before_body: Some(note.body.clone()),
        after_body: after.into(),
        source: note.source.clone(),
    }
}

#[test]
fn a_recent_command_still_standing_is_offered_again_after_an_interruption() {
    let root = TempDir::new("library-command-recover");
    let mut library = Library::open_fs(&root).unwrap();
    let before = library.create_note("todo", "To-Do\n", "editor").unwrap().unwrap();
    library.apply_command(&command("recover", &before, "To-Do\n\n- [ ] Voice\n")).unwrap();
    drop(library);
    let mut reopened = Library::open_fs(&root).unwrap();
    assert_eq!(reopened.latest_command_undo(60_000).unwrap().map(|pending| pending.mutation_id).as_deref(), Some("recover"));
    // Typed over since: the command's result no longer stands, so there is nothing to undo.
    let now = reopened.get_note("todo").unwrap().unwrap();
    reopened.update_note("todo", "To-Do\n\n- [ ] Voice\n- [ ] Typed\n", now.revision).unwrap();
    assert_eq!(reopened.latest_command_undo(60_000).unwrap(), None);
}

#[test]
fn undoing_a_created_note_removes_it_but_never_a_note_edited_since() {
    let root = TempDir::new("library-command-create");
    let mut library = Library::open_fs(&root).unwrap();
    let create = CommandMutation {
        id: "c1".into(),
        note_id: "new".into(),
        kind: "create".into(),
        before_revision: None,
        before_body: None,
        after_body: "Apartment stuff\n".into(),
        source: "capture".into(),
    };
    assert!(matches!(library.apply_command(&create).unwrap(), CommandMutationResult::Applied { .. }));
    assert!(matches!(library.undo_command("c1").unwrap(), CommandUndoResult::Undone { note: None, .. }));
    assert_eq!(library.get_note("new").unwrap(), None, "the note the command made is gone again");
    assert_eq!(library.undo_command("never").unwrap(), CommandUndoResult::NotFound);

    let again = CommandMutation { id: "c2".into(), ..create };
    library.apply_command(&again).unwrap();
    let made = library.get_note("new").unwrap().unwrap();
    let later = library.update_note("new", "Apartment stuff\n\nand more\n", made.revision).unwrap().unwrap();
    assert_eq!(library.undo_command("c2").unwrap(), CommandUndoResult::Conflict { current: Some(later) });
    assert!(library.get_note("new").unwrap().is_some(), "an undo never throws away a later edit");
}

#[test]
fn a_note_moved_by_another_app_is_found_where_it_went() {
    let root = TempDir::new("library-moved");
    let mut library = Library::open_fs(&root).unwrap();
    library.save_note("n", "# Moved\n", "editor").unwrap();
    std::fs::create_dir_all(root.join("Work")).unwrap();
    std::fs::rename(root.join("Inbox/Moved.md"), root.join("Work/Moved.md")).unwrap();
    let found = library.get_note("n").unwrap().unwrap();
    assert_eq!(found.path.as_deref(), Some("Work/Moved.md"), "the id in its front matter follows it");
    std::fs::remove_file(root.join("Work/Moved.md")).unwrap();
    assert_eq!(library.get_note("n").unwrap(), None, "and a file removed elsewhere is a note gone");
}

#[test]
fn clearing_empties_the_library_and_it_carries_on() {
    let root = TempDir::new("library-clear");
    let mut library = Library::open_fs(&root).unwrap();
    library.save_note("a", "# One\n", "editor").unwrap();
    library.save_note("b", "# Two\n", "capture").unwrap();
    library.set_formatted("b", Some("# Two\n\nTidy."), Some(1), Some("m")).unwrap();
    library.save_note("draft", "", "editor").unwrap();
    library.clear().unwrap();
    assert!(library.list_notes().unwrap().is_empty());
    assert_eq!(library.get_note("draft").unwrap(), None, "drafts go too");
    assert!(!root.join("Inbox/One.md").exists() && !root.join(".glyph/notes/b.json").exists());
    assert!(root.join(".glyph/notes").is_dir(), "the folder a sidecar is written into is still there");
    let again = library.save_note("c", "# Three\n", "editor").unwrap();
    assert_eq!(library.list_notes().unwrap(), vec![again]);
}

/// Decision 20 of docs/MARKDOWN_FIRST.md: a file from another app has its id in the index only, so a pin on it
/// used to leave a note that would be another note on a fresh device. The pin's rewrite now carries the id in.
#[test]
fn a_pin_writes_the_id_into_a_file_from_another_app_and_nothing_into_one_it_leaves_alone() {
    let root = TempDir::new("library-pin-id");
    let mut library = Library::open_fs(&root).unwrap();
    std::fs::write(root.join("Theirs.md"), "---\ntags: [trip]\n---\n# Theirs\n").unwrap();
    std::fs::write(root.join("Bare.md"), "# Bare\n").unwrap();
    let notes = library.list_notes().unwrap();
    let theirs = notes.iter().find(|n| n.path.as_deref() == Some("Theirs.md")).unwrap().clone();
    let bare = notes.iter().find(|n| n.path.as_deref() == Some("Bare.md")).unwrap().clone();
    // Pinned: the person's keys first, then the pin and the id, and the file's time as it was.
    let pinned = library.set_starred(&theirs.id, true).unwrap().unwrap();
    assert_eq!(read(&root, "Theirs.md"), format!("---\ntags: [trip]\npinned: true\nid: {}\n---\n# Theirs\n", theirs.id));
    assert_eq!(pinned.updated_at, theirs.updated_at);
    // Unpinned, nothing changes, nothing is written: a file without an id stays as it was.
    library.set_starred(&bare.id, false).unwrap();
    assert_eq!(read(&root, "Bare.md"), "# Bare\n");
    // Archived: the id goes in with the archive, and the note is the same note on a fresh index.
    library.set_archived(&bare.id, true).unwrap();
    let archived = read(&root, "Bare.md");
    assert!(archived.starts_with("---\narchived: 20") && archived.contains(&format!("\nid: {}\n", bare.id)), "{archived}");
    drop(library);
    std::fs::remove_file(root.join(".glyph/index.sqlite")).unwrap();
    let mut fresh = Library::open_fs(&root).unwrap();
    assert!(fresh.get_note(&theirs.id).unwrap().unwrap().starred && fresh.get_note(&bare.id).unwrap().unwrap().archived_at.is_some());
}

/// The critic's first finding (docs/MARKDOWN_FIRST.md §12): a second file carrying a live id was given a fresh id
/// in the index only, and on a fresh clone the walk reached `Plan (conflict from Mac).md` before `Plan.md` and gave
/// the copy the real id. Now the copy's fresh id is written into it, and the file named for its title keeps the id.
#[test]
fn a_conflict_copy_is_given_a_fresh_id_in_its_file_and_the_note_named_for_its_title_keeps_its_own() {
    let root = TempDir::new("library-conflict");
    let plan = "---\nid: plan\ncreated: 2026-10-01T10:00:00.000Z\n---\n# Plan\n\nours\n";
    std::fs::create_dir_all(root.join("Inbox")).unwrap();
    std::fs::write(root.join("Inbox/Plan.md"), plan).unwrap();
    std::fs::write(root.join("Inbox/Plan (conflict from Mac).md"), plan.replace("ours", "theirs")).unwrap();
    // A fresh clone: no index. The copy sorts first in the walk.
    let mut library = Library::open_fs(&root).unwrap();
    let notes = library.list_notes().unwrap();
    assert_eq!(notes.len(), 2);
    let real = library.get_note("plan").unwrap().unwrap();
    assert_eq!(real.path.as_deref(), Some("Inbox/Plan.md"), "the file named for its title is the note");
    let copy = notes.iter().find(|n| n.id != "plan").unwrap().clone();
    assert_eq!(copy.path.as_deref(), Some("Inbox/Plan (conflict from Mac).md"));
    let text = read(&root, "Inbox/Plan (conflict from Mac).md");
    assert!(text.starts_with(&format!("---\nid: {}\ncreated: 2026-10-01T10:00:00.000Z\n---\n", copy.id)), "the fresh id is in the file: {text}");
    assert_eq!(read(&root, "Inbox/Plan.md"), plan, "the note's file is untouched");
    assert!(!root.join(".glyph/notes").join(format!("{}.json", copy.id)).exists(), "no sidecar comes with a fresh id");
    // A second fresh clone of the folder as it now is gives the same ids: nothing is left to the walk's order.
    drop(library);
    std::fs::remove_file(root.join(".glyph/index.sqlite")).unwrap();
    let mut again = Library::open_fs(&root).unwrap();
    assert_eq!(again.get_note("plan").unwrap().unwrap().path.as_deref(), Some("Inbox/Plan.md"));
    assert_eq!(again.get_note(&copy.id).unwrap().unwrap().body, "# Plan\n\ntheirs\n");

    // The other way round: a copy of a note already indexed is the copy whatever it is called, and its file says so.
    again.save_note("same", "# Original\n", "editor").unwrap();
    std::fs::copy(root.join("Inbox/Original.md"), root.join("Inbox/Copy.md")).unwrap();
    let notes = again.list_notes().unwrap();
    let copied = notes.iter().find(|n| n.path.as_deref() == Some("Inbox/Copy.md")).unwrap();
    assert_ne!(copied.id, "same");
    let copy_text = read(&root, "Inbox/Copy.md");
    assert!(copy_text.contains(&format!("\nid: {}\n", copied.id)), "{copy_text}");
    assert_eq!(again.get_note("same").unwrap().unwrap().path.as_deref(), Some("Inbox/Original.md"));
}

/// Decision 5 of docs/MARKDOWN_FIRST.md, the alternative the critic showed is the only one SAF allows: `updated:` is
/// written on a save that changed the words, and the note's time is the later of the key and the file's own.
#[test]
fn a_save_writes_when_the_words_changed_and_the_note_shows_the_later_of_the_key_and_the_file() {
    let root = TempDir::new("library-updated");
    let mut library = Library::open_fs(&root).unwrap();
    let saved = library.save_note("u", "# Plan\n", "editor").unwrap();
    let text = read(&root, "Inbox/Plan.md");
    let key = text.lines().find_map(|line| line.strip_prefix("updated: ")).expect("an updated key").to_string();
    let key_ms = parse_iso(&key).unwrap();
    assert!((saved.updated_at - key_ms).abs() < 2_000, "{saved:?} {key}");
    // The same words again: not an edit, the file is not written, the key stands.
    std::thread::sleep(std::time::Duration::from_millis(20));
    library.save_note("u", "# Plan\n", "editor").unwrap();
    assert_eq!(read(&root, "Inbox/Plan.md"), text);
    // A pin keeps it too.
    library.set_starred("u", true).unwrap();
    assert!(read(&root, "Inbox/Plan.md").contains(&format!("updated: {key}\n")));
    // A clone whose files git has stamped with an older time (or any folder copied with its times lost): the key wins.
    library.vault.keep_modified("Inbox/Plan.md", key_ms - 86_400_000).unwrap();
    drop(library);
    std::fs::remove_file(root.join(".glyph/index.sqlite")).unwrap();
    let mut fresh = Library::open_fs(&root).unwrap();
    assert_eq!(fresh.get_note("u").unwrap().unwrap().updated_at, key_ms, "the key is later than the file");
    // An edit in another app moves the file's time and not the key: the file wins, and the note is at the top.
    std::thread::sleep(std::time::Duration::from_millis(20));
    let edited = read(&root, "Inbox/Plan.md").replace("# Plan\n", "# Plan\n\nedited in Obsidian\n");
    std::fs::write(root.join("Inbox/Plan.md"), edited).unwrap();
    let note = fresh.get_note("u").unwrap().unwrap();
    assert!(note.updated_at > key_ms, "{} > {key_ms}", note.updated_at);
    assert!(note.body.contains("edited in Obsidian"));
    // A note that arrives by sync carries its own time as the key.
    let applied = fresh.apply_note(&remote("s", "# Synced\n")).unwrap();
    assert!(read(&root, "Work/Trips/Hello.md").contains("updated: 2026-03-04T05:06:07.000Z\n"), "{}", read(&root, "Work/Trips/Hello.md"));
    assert_eq!(applied.updated_at, parse_iso("2026-03-04T05:06:07.000Z").unwrap());
    assert_eq!(MANAGED_KEYS, ["id", "created", "updated", "source", "pinned", "archived"]);
    assert!(MANAGED_KEYS.iter().all(|key| frontmatter::LIBRARY_KEYS.contains(key)), "every managed key is one the one-block reader takes as the library's");
}

/// The critic's case/normalization finding: a tree written on Android, whose own storage tells `Plan.md` from
/// `plan.md`, must not hold both, since a Mac or an iPhone checking it out would merge them, one over the other.
#[test]
fn two_names_that_differ_only_in_case_or_composition_are_one_name() {
    let root = TempDir::new("library-case");
    let mut library = Library::open_fs(&root).unwrap();
    assert_eq!(library.save_note("a", "# Plan\n", "editor").unwrap().path.as_deref(), Some("Inbox/Plan.md"));
    assert_eq!(library.save_note("b", "# plan\n", "editor").unwrap().path.as_deref(), Some("Inbox/plan 2.md"));
    assert_eq!(library.save_note("c", "# PLAN\n", "editor").unwrap().path.as_deref(), Some("Inbox/PLAN 3.md"));
    // `Café` typed composed, then decomposed as a Mac's file system or a pasted name may spell it.
    assert_eq!(library.save_note("d", "# Caf\u{e9}\n", "editor").unwrap().path.as_deref(), Some("Inbox/Caf\u{e9}.md"));
    assert_eq!(library.save_note("e", "# Cafe\u{301}\n", "editor").unwrap().path.as_deref(), Some("Inbox/Caf\u{e9} 2.md"), "composed before it is written, and one name with the first");
    // A file another app wrote decomposed is named for its title: a save keeps its name rather than numbering it.
    std::fs::write(root.join("Inbox/Cre\u{300}me.md"), "# Cr\u{e8}me\n").unwrap();
    let theirs = library.list_notes().unwrap().into_iter().find(|n| n.path.as_deref() == Some("Inbox/Cre\u{300}me.md")).unwrap();
    assert_eq!(library.save_note(&theirs.id, "# Cr\u{e8}me\n\nbr\u{fb}l\u{e9}e\n", "editor").unwrap().path.as_deref(), Some("Inbox/Cre\u{300}me.md"));
    assert_eq!(library.list_notes().unwrap().len(), 6);
}

/// A reset of the app's own folder takes the pictures under it with the notes that showed them; a person's folder
/// (library/relocate.rs tests) keeps every file.
#[test]
fn clearing_the_apps_own_folder_takes_its_pictures_too() {
    let root = TempDir::new("library-clear-pictures");
    let mut library = Library::open_fs(&root).unwrap();
    library.save_note("a", "# One\n\n![](image/a.jpg)\n", "editor").unwrap();
    std::fs::create_dir_all(root.join("image")).unwrap();
    std::fs::write(root.join("image/a.jpg"), b"jpeg").unwrap();
    std::fs::write(root.join("image/a.jpg.ocr.txt"), b"words").unwrap();
    library.clear().unwrap();
    assert!(!root.join("image").exists() && !root.join("Inbox/One.md").exists());
    assert!(root.join(".glyph/library.json").exists());
}
