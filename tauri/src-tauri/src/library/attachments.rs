//! Where the notes' attachments are: the pictures, files, films and tapes a note links or plays
//! (docs/MARKDOWN_FIRST.md §5 gap 1, decision 1). Matt, 2026-10-31: "our value proposition is that we can be
//! hosted anywhere for super cheap since it's all simply markdown files; the whole backup can be done from git".
//! A repository of the Library folder alone had every `image/<name>` link dead, because the pictures sat BESIDE
//! the library under the app's data, in folders that did not even share the links' names (`images/`,
//! `images/files/`).
//!
//! So each kind has a folder UNDER THE LIBRARY, named as the notes' links already name it: `image/`, `file/`,
//! `video/`, and the tapes' own `recordings/`. The old folder beside the library is still read, and at every open
//! whatever is still in it is brought in (`Places::gather`): a rename, so a thousand pictures move in a moment,
//! idempotent and resumable because a file already in place is only removed where it was, and a file that cannot
//! move is left and said. Cheap when there is nothing to move (one `read_dir` per folder), so it runs at every
//! open rather than once behind a flag: the old folders are a device's own, never shared through a chosen folder,
//! so a second device joining the same folder later still has its own to bring in, which a mark in the shared
//! `library.json` would have told it not to.
//!
//! WHICH KINDS HAVE MOVED (`Kind::settled`): all four, in the Flutter app's core. Pictures first (2026-10-31, read
//! and written through the core alone: files.rs, images.rs), then files, films and tapes the same day, once every
//! reader outside the core looked in both places (readers before writers, the rule from the 2026-10-20 org-folders
//! incident): Dart's store of the files notes link follows the core's `attachment_places` answer
//! (lib/files/attachment_store.dart), the phone's players and the Mac's take the folders to look in from Dart with
//! each load (TapePlayer.kt, FilmPlayer.kt, TapeChannel.swift; lib/tapes/phone_player.dart,
//! lib/core/phone_films.dart), and the write-up and the Mac's capture ask this file (write_up.rs, capture.rs,
//! recording.rs). The one writer that does not ask is the phone's meeting service, which spools a meeting's WAV
//! straight into `<data>/recordings/` (MeetingService.kt): `write_up::finish` brings it under the library when the
//! recording ends (`Places::bring`), and a meeting a kill cut short is brought in at the next open with the rest.
//!
//! A FOLDER CHOSEN THROUGH ANDROID'S PICKER has no paths SQLite, a player or the sidecars could use, so for a tree
//! the attachments stay in the app's own storage, as `.glyph/` does (root.rs); the backup and the export still
//! name them `Library/<kind>/`, so what leaves the phone has the one layout.
//!
//! A NOTE ON THE FOLDERS' NAMES: `image/`, `file/` and `video/` hold no `.md`, so no build ever indexes them as
//! notes (vault.rs lists `.md` only), and an older build sharing a chosen folder sees them as any other folder it
//! has no notes in: nothing of the move is visible to it but the folders themselves.

use std::io;
use std::path::{Path, PathBuf};

/// The app's own library folder under its data directory, `paths::LIBRARY`: named here because the attachments'
/// places are worked out from a data directory alone, as root.rs's are.
const OWN_LIBRARY: &str = "Library";

/// The `.gitattributes` for a library folder under git (docs/MARKDOWN_FIRST.md §10, the 'Back up to git' plugin):
/// the notes, their versions and the canvases as LF text, so a Windows checkout and a Mac's commit the same bytes
/// and never a whole-file diff of line endings; the sidecars as text with the platform's endings; and every kind of
/// attachment under the library as binary, so git never tries a text merge or a CRLF conversion on a WAV. The
/// file itself is tauri/publish/templates/gitattributes, beside the Pages workflow the plugin also writes, so the
/// publisher and the plugin read one copy; a backup may carry it too.
pub const GIT_ATTRIBUTES: &str = include_str!("../../../publish/templates/gitattributes");

/// What a note can link or play besides its words.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Kind {
    /// `![](image/<uuid>.jpg)`, and the `.ocr.txt` of words read in one beside it.
    Image,
    /// `[Name](file/<uuid>.pdf "2.4 MB")`, and its `.ocr.txt`.
    File,
    /// `[![video 0:12](image/<poster>.jpg)](video/<uuid>.mp4)`.
    Video,
    /// A note's tape, `<note id>.wav`, linked to the note by its name alone.
    Recording,
}

impl Kind {
    pub const ALL: [Kind; 4] = [Kind::Image, Kind::File, Kind::Video, Kind::Recording];

    /// Its folder under the library: the name the notes' links already use.
    pub fn folder(self) -> &'static str {
        match self {
            Kind::Image => "image",
            Kind::File => "file",
            Kind::Video => "video",
            Kind::Recording => "recordings",
        }
    }

    /// Its folder beside the library, under the app's data, where every build before 2.3.94 kept it
    /// (paths.rs `IMAGES`, `VIDEO`, `RECORDINGS`; attachment_store.dart `images/files`).
    pub fn legacy(self) -> &'static str {
        match self {
            Kind::Image => "images",
            Kind::File => "images/files",
            Kind::Video => "video",
            Kind::Recording => "recordings",
        }
    }

    /// Whether this build keeps the kind under the library (written there, and the old folder's files brought in
    /// at open), or still beside it because something reads it by the old path alone. Every kind, in the Flutter
    /// app's core, since 2026-10-31 (the module's header says how each reader came to look in both places). Only
    /// there: the Tauri app this file is shared with reads its pictures through its own `img` scheme (images.rs)
    /// and its tapes and films through `rec` and `vid`, which look beside the library alone, so there nothing has
    /// moved and a move of the library's folder gathers nothing. `CARGO_PKG_NAME` is the crate this file is
    /// compiled into.
    pub fn settled(self) -> bool {
        env!("CARGO_PKG_NAME") == "ghost_core"
    }

    /// The kind as a sentence names it.
    pub fn said(self) -> &'static str {
        match self {
            Kind::Image => "pictures",
            Kind::File => "files",
            Kind::Video => "films",
            Kind::Recording => "recordings",
        }
    }
}

/// Whether a name in an attachment folder is one of the folder's own files, not a write under way or a dot file
/// (`video/.orphans.json` is the sweep's memory, `.<id>.part` half a sync, `.<hex>.tmp` half a write).
fn is_kept_file(name: &str) -> bool {
    !name.starts_with('.') && !name.ends_with(".part") && !name.ends_with(".tmp")
}

/// Where one kind's files are: the folder they are written to first, then every folder they are still read from.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Places {
    dirs: Vec<PathBuf>,
}

impl Places {
    /// `dirs` in order, the first the one written to; a folder named twice counts once.
    pub fn new(dirs: Vec<PathBuf>) -> Places {
        let mut kept: Vec<PathBuf> = Vec::with_capacity(dirs.len());
        for dir in dirs {
            if !kept.contains(&dir) {
                kept.push(dir);
            }
        }
        Places { dirs: kept }
    }

    /// Where a new file is written.
    pub fn first(&self) -> &Path {
        &self.dirs[0]
    }

    /// Every folder read, the first first.
    pub fn dirs(&self) -> &[PathBuf] {
        &self.dirs
    }

    /// Where `name` is, from the first folder that has it; `None` where none does.
    pub fn find(&self, name: &str) -> Option<PathBuf> {
        self.dirs.iter().map(|dir| dir.join(name)).find(|path| path.is_file())
    }

    /// `name` where it is, or where it will be written: for what writes a file whole, or adds to one.
    pub fn place(&self, name: &str) -> PathBuf {
        self.find(name).unwrap_or_else(|| self.first().join(name))
    }

    /// `name` brought into the first folder from whichever other folder has it, and where it is now; `None` where
    /// no folder has it. For a file something outside the core wrote into an old folder after the open's gather (the
    /// phone's meeting service spooling a WAV into `<data>/recordings/`, MeetingService.kt), brought in when the core
    /// first touches it (`write_up::finish`). The rule is `gather`'s for one file: one already in the first folder
    /// at the same size is the same file, and the other copy goes; one there at another size is left where it is
    /// and the first folder's is answered, so nothing is written over.
    pub fn bring(&self, name: &str) -> io::Result<Option<PathBuf>> {
        let to = self.first().join(name);
        let from = self.dirs[1..].iter().map(|dir| dir.join(name)).find(|path| path.is_file());
        let Some(from) = from else { return Ok(to.is_file().then_some(to)) };
        if let Ok(there) = std::fs::metadata(&to) {
            if there.len() == std::fs::metadata(&from)?.len() {
                std::fs::remove_file(&from)?;
            }
            return Ok(Some(to));
        }
        std::fs::create_dir_all(self.first())?;
        move_file(&from, &to)?;
        Ok(Some(to))
    }

    /// Every file of the kind by its name, each from the first folder that has it: the folders' own files only
    /// (`is_kept_file`), none from a folder inside them (a picture folder's `files/` is another kind's). Sorted
    /// by name, so a backup and an export list the same way twice.
    pub fn files(&self) -> io::Result<Vec<(String, PathBuf)>> {
        let mut out: Vec<(String, PathBuf)> = Vec::new();
        for dir in &self.dirs {
            let entries = match std::fs::read_dir(dir) {
                Ok(entries) => entries,
                Err(e) if e.kind() == io::ErrorKind::NotFound => continue,
                Err(e) => return Err(e),
            };
            for entry in entries {
                let entry = entry?;
                let name = entry.file_name().to_string_lossy().into_owned();
                if !is_kept_file(&name) || !entry.file_type()?.is_file() || out.iter().any(|(had, _)| *had == name) {
                    continue;
                }
                out.push((name, entry.path()));
            }
        }
        out.sort();
        Ok(out)
    }

    /// `name` gone from every folder; one already gone is no error.
    pub fn remove(&self, name: &str) -> io::Result<()> {
        for dir in &self.dirs {
            match std::fs::remove_file(dir.join(name)) {
                Ok(()) => {}
                Err(e) if e.kind() == io::ErrorKind::NotFound => {}
                Err(e) => return Err(e),
            }
        }
        Ok(())
    }

    /// Everything in the other folders brought into the first, and the number that came. A rename where the two
    /// are on one disk; a copy through a hidden file and a delete where they are not. A file already in the first
    /// folder at the same size is the same file, and is only removed where it was; one there at another size is
    /// left where it was and said, so nothing is ever written over. Resumable: a move stopped half way leaves
    /// every file in one place or the other, and the next open finishes it.
    pub fn gather(&self, kind: Kind, mut say: impl FnMut(String)) -> io::Result<usize> {
        let first = self.first();
        let mut moved = 0;
        for dir in &self.dirs[1..] {
            let entries = match std::fs::read_dir(dir) {
                Ok(entries) => entries,
                Err(e) if e.kind() == io::ErrorKind::NotFound => continue,
                Err(e) => return Err(e),
            };
            for entry in entries {
                let entry = entry?;
                let name = entry.file_name().to_string_lossy().into_owned();
                if !is_kept_file(&name) || !entry.file_type()?.is_file() {
                    continue;
                }
                let from = entry.path();
                let to = first.join(&name);
                if let Ok(there) = std::fs::metadata(&to) {
                    if there.len() == entry.metadata()?.len() {
                        std::fs::remove_file(&from)?;
                    } else {
                        say(format!("{} is in both {} folders at different sizes: {} is left where it is", name, kind.said(), from.display()));
                    }
                    continue;
                }
                std::fs::create_dir_all(first)?;
                move_file(&from, &to)?;
                moved += 1;
            }
        }
        if moved > 0 {
            say(format!("moved {moved} {} into {}", kind.said(), first.display()));
        }
        Ok(moved)
    }

    /// Every file `other` has that this first folder has not, copied into it: for a library going to another
    /// folder with its notes, whose attachments go with them (relocate.rs). Into the first folder even where another
    /// of these folders has the file (the app's data, which both libraries read): the new folder is to hold them
    /// all. The source is never removed here: a folder of the person's keeps every file, and the app's own gives
    /// its up to `gather`, which follows.
    pub fn copy_from(&self, other: &Places) -> io::Result<usize> {
        let mut copied = 0;
        for (name, source) in other.files()? {
            if self.first().join(&name).is_file() {
                continue;
            }
            std::fs::create_dir_all(self.first())?;
            copy_file(&source, &self.first().join(&name))?;
            copied += 1;
        }
        Ok(copied)
    }
}

/// `from` moved to `to`: a rename, or across disks a copy and a delete.
fn move_file(from: &Path, to: &Path) -> io::Result<()> {
    if std::fs::rename(from, to).is_ok() {
        return Ok(());
    }
    copy_file(from, to)?;
    std::fs::remove_file(from)
}

/// `from` copied to `to` whole or not at all, through a hidden file beside it (which `is_kept_file` skips) and a
/// rename.
fn copy_file(from: &Path, to: &Path) -> io::Result<()> {
    let name = to.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let part = to.with_file_name(format!(".{name}.part"));
    let copied = std::fs::copy(from, &part).and_then(|_| std::fs::rename(&part, to));
    if copied.is_err() {
        let _ = std::fs::remove_file(&part);
    }
    copied
}

/// The four kinds' places for one library.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Attachments {
    places: Vec<(Kind, Places)>,
}

impl Attachments {
    /// The places for a library whose folder is `folder` (none through Android's picker), the app's own folder or
    /// not (`own`), with the app's data at `data`:
    ///
    /// - a settled kind is written under the library's folder, read from the old folder beside the app's data,
    ///   and read from the app's own library when the library is a chosen folder (a launch while that folder was
    ///   away opened the app's own, and may have gathered into it);
    /// - a kind not yet settled is written to the old folder, and read from the others;
    /// - with no folder to write under (a tree), the old folder is written, and the app's own library read.
    pub fn new(folder: Option<&Path>, own: bool, data: &Path) -> Attachments {
        let own_library = data.join(OWN_LIBRARY);
        let places = Kind::ALL
            .into_iter()
            .map(|kind| {
                let legacy = data.join(kind.legacy());
                let mut dirs = match (folder, kind.settled()) {
                    (Some(folder), true) => vec![folder.join(kind.folder()), legacy],
                    (Some(folder), false) => vec![legacy, folder.join(kind.folder())],
                    (None, _) => vec![legacy],
                };
                if !own {
                    dirs.push(own_library.join(kind.folder()));
                }
                (kind, Places::new(dirs))
            })
            .collect();
        Attachments { places }
    }

    /// One kind's places.
    pub fn of(&self, kind: Kind) -> &Places {
        &self.places.iter().find(|(k, _)| *k == kind).expect("every kind has its places").1
    }

    /// Every kind gathered into its first folder (`Places::gather`): the move at open. A kind that cannot be
    /// gathered is said and the rest go on; the answer is how many files moved.
    pub fn gather(&self, mut say: impl FnMut(String)) -> usize {
        let mut moved = 0;
        for (kind, places) in &self.places {
            match places.gather(*kind, &mut say) {
                Ok(n) => moved += n,
                Err(e) => say(format!("the {} could not all be moved into {}: {e}", kind.said(), places.first().display())),
            }
        }
        moved
    }

    /// Every kind's files that `other` has and this has not, copied in (`Places::copy_from`).
    pub fn copy_from(&self, other: &Attachments) -> io::Result<usize> {
        let mut copied = 0;
        for (kind, places) in &self.places {
            copied += places.copy_from(other.of(*kind))?;
        }
        Ok(copied)
    }

    /// Every file of every kind, as `(kind, name, path)`, each from the first folder that has it: what a backup
    /// and an export carry, with nothing twice.
    pub fn files(&self) -> io::Result<Vec<(Kind, String, PathBuf)>> {
        let mut out = Vec::new();
        for (kind, places) in &self.places {
            out.extend(places.files()?.into_iter().map(|(name, path)| (*kind, name, path)));
        }
        Ok(out)
    }
}

impl super::Library {
    /// Where this library's attachments are, with the app's data at `data` (`Attachments::new`).
    pub fn attachments(&self, data: &Path) -> Attachments {
        Attachments::new(self.folder().as_deref(), self.in_own_folder(), data)
    }

    /// The attachment folders under the library (`Kind::folder`), for a clear of the app's own folder, where
    /// every file is the app's to remove (`clear`). Nothing in a folder of the person's.
    pub(super) fn remove_own_attachments(&self) -> io::Result<()> {
        let Some(folder) = self.folder() else { return Ok(()) };
        if !self.in_own_folder() {
            return Ok(());
        }
        for kind in Kind::ALL {
            crate::fsx::remove_dir_if_present(&folder.join(kind.folder()))?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::TempDir;

    fn put(path: &Path, bytes: &[u8]) {
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, bytes).unwrap();
    }

    fn names(dir: &Path) -> Vec<String> {
        let mut names: Vec<String> = match std::fs::read_dir(dir) {
            Ok(entries) => entries.map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).collect(),
            Err(_) => Vec::new(),
        };
        names.sort();
        names
    }

    /// Whether this crate is the Flutter app's core, where every kind lives under the library; in the Tauri app
    /// nothing has moved, and the same tests read the other way round.
    fn core() -> bool {
        Kind::Image.settled()
    }

    #[test]
    fn the_folders_are_named_as_the_links_are_and_every_kind_has_moved_in_the_core() {
        assert_eq!(Kind::ALL.map(Kind::folder), ["image", "file", "video", "recordings"]);
        assert_eq!(Kind::ALL.map(Kind::legacy), ["images", "images/files", "video", "recordings"]);
        assert_eq!(Kind::ALL.map(Kind::settled), [core(); 4], "all four together since 2026-10-31, in the core alone");
        let data = Path::new("/data");
        let own = Attachments::new(Some(&data.join("Library")), true, data);
        let chosen = Attachments::new(Some(Path::new("/Users/matt/Notes")), false, data);
        if core() {
            assert_eq!(own.of(Kind::Image).dirs(), [data.join("Library/image"), data.join("images")]);
            assert_eq!(own.of(Kind::Recording).dirs(), [data.join("Library/recordings"), data.join("recordings")], "written under, read beside");
            assert_eq!(own.of(Kind::File).dirs(), [data.join("Library/file"), data.join("images/files")]);
            assert_eq!(chosen.of(Kind::Image).dirs(), [PathBuf::from("/Users/matt/Notes/image"), data.join("images"), data.join("Library/image")]);
            assert_eq!(chosen.of(Kind::File).dirs(), [PathBuf::from("/Users/matt/Notes/file"), data.join("images/files"), data.join("Library/file")]);
            assert_eq!(chosen.of(Kind::Video).first(), Path::new("/Users/matt/Notes/video"));
        } else {
            assert_eq!(own.of(Kind::Image).dirs(), [data.join("images"), data.join("Library/image")], "the Tauri app writes beside the library still");
            assert_eq!(own.of(Kind::Recording).dirs(), [data.join("recordings"), data.join("Library/recordings")]);
            assert_eq!(chosen.of(Kind::File).dirs(), [data.join("images/files"), PathBuf::from("/Users/matt/Notes/file"), data.join("Library/file")]);
        }
        let tree = Attachments::new(None, false, data);
        assert_eq!(tree.of(Kind::Image).dirs(), [data.join("images"), data.join("Library/image")], "a tree keeps them in the app's storage");
        assert_eq!(tree.of(Kind::Video).first(), data.join("video"));
        assert_eq!(tree.of(Kind::Recording).first(), data.join("recordings"));
    }

    #[test]
    fn the_git_attributes_name_the_notes_as_lf_text_and_every_attachment_as_binary() {
        let rules: Vec<&str> = GIT_ATTRIBUTES.lines().filter(|line| !line.starts_with('#') && !line.trim().is_empty()).collect();
        assert_eq!(rules, ["*.md text eol=lf", "*.versions text eol=lf", "*.canvas text eol=lf", "*.json text", "*.wav binary", "*.jpg binary", "*.png binary", "*.mp4 binary", "*.pdf binary"]);
    }

    #[test]
    fn the_move_at_open_brings_the_old_folder_in_once_and_can_be_stopped_and_run_again() {
        let data = TempDir::new("attachments-gather");
        put(&data.join("images/a.jpg"), b"aaa");
        put(&data.join("images/a.jpg.ocr.txt"), b"words in a");
        put(&data.join("images/b.png"), b"bb");
        put(&data.join("images/.c.part"), b"half a sync");
        put(&data.join("images/files/doc.pdf"), b"a file, another kind's");
        // Half moved already: the same picture in both places, and one that differs.
        put(&data.join("Library/image/b.png"), b"bb");
        put(&data.join("images/d.webp"), b"old d");
        put(&data.join("Library/image/d.webp"), b"new d, longer");
        if !core() {
            // The Tauri app keeps everything beside the library: the move is the core's alone.
            let places = Attachments::new(Some(&data.join("Library")), true, &data);
            assert_eq!(places.gather(|_| {}), 0);
            assert_eq!(places.of(Kind::Image).find("a.jpg"), Some(data.join("images/a.jpg")));
            return;
        }
        let places = Attachments::new(Some(&data.join("Library")), true, &data);
        let mut said = Vec::new();
        assert_eq!(places.gather(|line| said.push(line)), 3, "a and its words came; b was there already; d stayed; the file came too");
        assert_eq!(names(&data.join("Library/image")), ["a.jpg", "a.jpg.ocr.txt", "b.png", "d.webp"]);
        assert_eq!(names(&data.join("images")), [".c.part", "d.webp", "files"], "b went, d is left, a write under way is not touched");
        assert_eq!(names(&data.join("Library/file")), ["doc.pdf"], "the files are their own kind, under the library now");
        assert_eq!(names(&data.join("images/files")), Vec::<String>::new());
        assert_eq!(std::fs::read(data.join("Library/image/d.webp")).unwrap(), b"new d, longer", "nothing is written over");
        assert!(said.iter().any(|line| line.contains("d.webp") && line.contains("different sizes")), "{said:?}");
        assert!(said.iter().any(|line| line.contains("moved 2 pictures")), "{said:?}");
        assert!(said.iter().any(|line| line.contains("moved 1 files")), "{said:?}");
        // Again: nothing to do, and nothing said.
        let mut again = Vec::new();
        assert_eq!(places.gather(|line| again.push(line)), 0);
        assert_eq!(again, vec![format!("d.webp is in both pictures folders at different sizes: {} is left where it is", data.join("images/d.webp").display())]);
        // Every kind is read in both places and written under the library.
        assert_eq!(places.of(Kind::File).find("doc.pdf"), Some(data.join("Library/file/doc.pdf")));
        assert_eq!(places.of(Kind::File).place("new.pdf"), data.join("Library/file/new.pdf"));
        assert_eq!(places.of(Kind::Image).place("new.jpg"), data.join("Library/image/new.jpg"));
        assert_eq!(places.of(Kind::Image).find("d.webp"), Some(data.join("Library/image/d.webp")), "the library's copy is the one read");
        assert_eq!(places.of(Kind::Recording).place("n1.wav"), data.join("Library/recordings/n1.wav"));
    }

    #[test]
    fn films_and_recordings_move_at_open_too_and_are_read_from_either_folder_meanwhile() {
        if !core() {
            return;
        }
        let data = TempDir::new("attachments-kinds");
        put(&data.join("video/f.mp4"), b"a film");
        put(&data.join("video/.orphans.json"), b"{}");
        put(&data.join("recordings/n1.wav"), b"RIFF n1");
        put(&data.join("recordings/.n2.wav.part"), b"half a sync");
        put(&data.join("Library/recordings/n3.wav"), b"RIFF n3, already under");
        let places = Attachments::new(Some(&data.join("Library")), true, &data);
        // Read-both before the move: what the players and the write-up see between a Kotlin write and the open.
        assert_eq!(places.of(Kind::Video).find("f.mp4"), Some(data.join("video/f.mp4")));
        assert_eq!(places.of(Kind::Recording).find("n1.wav"), Some(data.join("recordings/n1.wav")));
        assert_eq!(places.of(Kind::Recording).find("n3.wav"), Some(data.join("Library/recordings/n3.wav")));
        assert_eq!(places.of(Kind::Recording).files().unwrap().iter().map(|(name, _)| name.as_str()).collect::<Vec<_>>(), ["n1.wav", "n3.wav"], "each once, no half a sync");
        let mut said = Vec::new();
        assert_eq!(places.gather(|line| said.push(line)), 2);
        assert_eq!(names(&data.join("Library/video")), ["f.mp4"]);
        assert_eq!(names(&data.join("video")), [".orphans.json"], "the sweep's memory is the app's own and stays");
        assert_eq!(names(&data.join("Library/recordings")), ["n1.wav", "n3.wav"]);
        assert_eq!(names(&data.join("recordings")), [".n2.wav.part"]);
        assert_eq!(places.gather(|_| panic!("nothing to say twice")), 0, "idempotent");
        assert_eq!(places.of(Kind::Video).find("f.mp4"), Some(data.join("Library/video/f.mp4")));
    }

    #[test]
    fn a_file_written_into_an_old_folder_after_the_open_is_brought_in_when_the_core_touches_it() {
        if !core() {
            return;
        }
        let data = TempDir::new("attachments-bring");
        let places = Attachments::new(Some(&data.join("Library")), true, &data);
        let tapes = places.of(Kind::Recording);
        assert_eq!(tapes.bring("none.wav").unwrap(), None, "nowhere is nowhere");
        // The meeting service spooled a WAV beside the library while the app ran.
        put(&data.join("recordings/m1.wav"), b"RIFF a meeting");
        assert_eq!(tapes.bring("m1.wav").unwrap(), Some(data.join("Library/recordings/m1.wav")));
        assert_eq!(std::fs::read(data.join("Library/recordings/m1.wav")).unwrap(), b"RIFF a meeting");
        assert!(!data.join("recordings/m1.wav").exists());
        assert_eq!(tapes.bring("m1.wav").unwrap(), Some(data.join("Library/recordings/m1.wav")), "brought already: where it is");
        // The same file in both at the same size: the old copy goes. At another size: both stay, the library's is read.
        put(&data.join("recordings/m1.wav"), b"RIFF a meeting");
        assert_eq!(tapes.bring("m1.wav").unwrap(), Some(data.join("Library/recordings/m1.wav")));
        assert!(!data.join("recordings/m1.wav").exists());
        put(&data.join("recordings/m1.wav"), b"RIFF a meeting, longer");
        assert_eq!(tapes.bring("m1.wav").unwrap(), Some(data.join("Library/recordings/m1.wav")));
        assert!(data.join("recordings/m1.wav").exists(), "nothing is written over");
    }

    #[test]
    fn a_picture_is_read_from_either_folder_and_removed_from_both() {
        let data = TempDir::new("attachments-both");
        put(&data.join("images/old.jpg"), b"old");
        put(&data.join("Library/image/new.jpg"), b"new");
        put(&data.join("images/twice.jpg"), b"old twice");
        put(&data.join("Library/image/twice.jpg"), b"new twice");
        let places = Attachments::new(Some(&data.join("Library")), true, &data);
        let pictures = places.of(Kind::Image);
        assert_eq!(pictures.find("old.jpg"), Some(data.join("images/old.jpg")));
        assert_eq!(pictures.find("new.jpg"), Some(data.join("Library/image/new.jpg")));
        assert_eq!(pictures.find("nowhere.jpg"), None);
        let listed: Vec<(String, PathBuf)> = pictures.files().unwrap();
        assert_eq!(listed, [("new.jpg".to_string(), data.join("Library/image/new.jpg")), ("old.jpg".to_string(), data.join("images/old.jpg")), ("twice.jpg".to_string(), data.join("Library/image/twice.jpg"))], "each once, from the first folder that has it");
        pictures.remove("twice.jpg").unwrap();
        assert!(!data.join("images/twice.jpg").exists() && !data.join("Library/image/twice.jpg").exists());
        pictures.remove("twice.jpg").unwrap();
        let all = places.files().unwrap();
        assert_eq!(all.iter().map(|(kind, name, _)| (*kind, name.as_str())).collect::<Vec<_>>(), [(Kind::Image, "new.jpg"), (Kind::Image, "old.jpg")]);
    }

    #[test]
    fn a_library_going_to_another_folder_takes_copies_of_its_attachments_and_leaves_the_persons() {
        if !core() {
            return;
        }
        let data = TempDir::new("attachments-copy");
        let home = TempDir::new("attachments-copy-home");
        let vault = home.join("Vault");
        put(&data.join("Library/image/mine.jpg"), b"mine");
        put(&data.join("images/older.jpg"), b"older");
        put(&vault.join("image/theirs.jpg"), b"theirs");
        let own = Attachments::new(Some(&data.join("Library")), true, &data);
        let chosen = Attachments::new(Some(&vault), false, &data);
        assert_eq!(chosen.copy_from(&own).unwrap(), 2);
        assert_eq!(names(&vault.join("image")), ["mine.jpg", "older.jpg", "theirs.jpg"]);
        assert!(data.join("Library/image/mine.jpg").exists(), "copied, not moved: the next open's gather takes the app's own");
        assert_eq!(chosen.gather(|_| {}), 0, "the copies are there at the same size, so the app's own are only removed");
        assert!(!data.join("Library/image/mine.jpg").exists() && !data.join("images/older.jpg").exists());
        // Home again: copies come back, the person's folder keeps every file.
        assert_eq!(own.copy_from(&chosen).unwrap(), 3);
        assert_eq!(names(&data.join("Library/image")), ["mine.jpg", "older.jpg", "theirs.jpg"]);
        assert_eq!(names(&vault.join("image")), ["mine.jpg", "older.jpg", "theirs.jpg"]);
        assert_eq!(own.copy_from(&chosen).unwrap(), 0, "and nothing twice");
    }
}
