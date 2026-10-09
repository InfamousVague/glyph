//! The files sync carries besides the notes (docs/STAGE7.md, "Sync"): a note's recording, the pictures notes
//! show, and a note's versions file. What `LocalFiles` in `../glyph/src/app/core/sync/notes.ts` asks of a device.
//!
//! The web page read a picture and a recording through its own schemes (`img`, `rec`) and wrote them through one
//! Tauri command. Flutter has no such schemes, so reading is a command too, and a large file need never cross at
//! all: `file_path` says where it lies, crypto.rs's `seal_file` seals it from there, and what arrives is opened to
//! a file (`open_file`) and adopted from it (`sync_put_file_path`).
//!
//! | command | takes | answers |
//! | --- | --- | --- |
//! | `sync_put_file` | `{kind, name, base64}` | `null`. The Tauri command of that name, with its rules and sentences |
//! | `sync_put_file_path` | `{kind, name, path}` | `null`. The same, from a file, which is moved in |
//! | `read_file` | `{kind, name}` | standard base64, or `null` where this device has none |
//! | `file_path` | `{kind, name}` | `{path, bytes}`, or `null` |
//! | `file_digest` | `{kind, name}` | the first sixteen bytes of its SHA-256 as hex, or `null` |
//! | `file_exists` | `{kind, name}` | whether this device has it |
//! | `save_video` | `{path, poster}` | `{video, poster}`. The Tauri command of that name: a film and its poster adopted from the cache's `picked/` |
//! | `discard_picked` | `{path}` | `null`. The Tauri command of that name: a picked file nobody will name, thrown away |
//!
//! `kind` is `recording` (by note id), `image` (by its own name) or, for the three that read, `versions` (by note
//! id): a versions file lies beside its note wherever the library is, a folder chosen through Android's picker
//! included, so it has no path to give and is read through the library, under its lock. Pictures and recordings
//! take no lock: they are the app's own files, written whole or not at all.
//!
//! A film is `video` (by its own name), and only where it lies and whether it is here are answered
//! (`file_path`, `file_exists`): it stays on the phone it was added on (kept/videos.rs), so sync never reads,
//! writes or fingerprints one, and those commands refuse the kind. The page asked whether a film was here with a
//! HEAD to its `vid` scheme and played it from there; the Flutter app asks `file_exists` and hands the phone's
//! player the file's name. `save_video` adopts from `<cache>/picked/` and nowhere else, all or nothing, and both
//! film commands sweep what has waited there for over an hour, as the Tauri commands do.
//!
//! A name is checked before it becomes a path, by the Tauri app's own rules (kept/images.rs `valid_name`,
//! kept/recordings.rs `recording_file`): one that is not a plain name answers `null` to a read and an `Err` to a
//! write, and never names a file.

use std::path::{Path, PathBuf};

use base64::Engine as _;
use serde::Deserialize;
use serde_json::{json, Value};

use crate::dispatch::NotesStore;
use crate::kept::recordings::recording_file;

const COMMANDS: [&str; 8] = ["sync_put_file", "sync_put_file_path", "read_file", "file_path", "file_digest", "file_exists", "save_video", "discard_picked"];

/// Whether `command` is one of this module's.
pub fn has(command: &str) -> bool {
    COMMANDS.contains(&command)
}

#[derive(Deserialize)]
struct Put {
    kind: String,
    name: String,
    base64: String,
}

#[derive(Deserialize)]
struct PutPath {
    kind: String,
    name: String,
    path: PathBuf,
}

#[derive(Deserialize)]
struct SaveVideo {
    path: PathBuf,
    poster: PathBuf,
}

#[derive(Deserialize)]
struct Discard {
    path: PathBuf,
}

#[derive(Deserialize)]
struct Named {
    kind: String,
    name: String,
}

fn read<T: serde::de::DeserializeOwned>(command: &str, args: Value) -> Result<T, String> {
    serde_json::from_value(args).map_err(|e| format!("invalid args for command `{command}`: {e}"))
}

/// Where a picture or a recording lies, whether or not it is there; `None` for a name that may not name a file.
fn kept_path(data: &Path, kind: &str, name: &str) -> Result<Option<PathBuf>, String> {
    match kind {
        "image" => Ok(crate::kept::images::valid_name(name).then(|| data.join(crate::paths::IMAGES).join(name))),
        "recording" => Ok(recording_file(&data.join(crate::paths::RECORDINGS), name)),
        _ => Err(format!("Nothing is kept as {kind}.")),
    }
}

/// Where a film lies, whether or not it is there; `None` for a name that may not name one.
fn film_path(data: &Path, name: &str) -> Option<PathBuf> {
    crate::kept::videos::valid_name(name).then(|| data.join(crate::paths::VIDEO).join(name))
}

/// The file that is there, with its length.
fn present(path: Option<PathBuf>) -> Option<(PathBuf, u64)> {
    let path = path?;
    let meta = std::fs::metadata(&path).ok()?;
    meta.is_file().then(|| (path, meta.len()))
}

/// Keeps a file that arrived by sync: commands.rs `sync_put_file`.
fn put(data: &Path, kind: &str, name: &str, base64: &str) -> Result<(), String> {
    match kind {
        "image" => crate::kept::images::place(&data.join(crate::paths::IMAGES), name, base64),
        "recording" => crate::kept::recordings::place(&data.join(crate::paths::RECORDINGS), name, base64),
        _ => Err(format!("Nothing is kept as {kind}.")),
    }
}

/// `from` moved to `to`: a rename where it can be, and across mounts (the cache and the data directory can be on
/// different ones) a copy through a hidden file and a delete, as images.rs `adopt` has it.
fn move_in(from: &Path, to: &Path) -> std::io::Result<()> {
    if std::fs::rename(from, to).is_ok() {
        return Ok(());
    }
    let part = to.with_file_name(format!(".{}.part", crate::note::new_id()));
    let copied = std::fs::copy(from, &part).and_then(|_| std::fs::rename(&part, to));
    if copied.is_err() {
        let _ = std::fs::remove_file(&part);
    }
    copied?;
    let _ = std::fs::remove_file(from);
    Ok(())
}

/// Keeps a file that arrived by sync and was opened to `path` (crypto.rs `open_file`), under the same rules as
/// `sync_put_file`. A picture is small, and goes through the Tauri app's own `place`. A recording can be an hour
/// long: its id and its first four bytes are checked as recordings.rs `place` checks them, and the file is moved
/// into place rather than read. Either way `path` is gone afterwards when it was kept.
fn put_path(data: &Path, kind: &str, name: &str, path: &Path) -> Result<(), String> {
    match kind {
        "image" => {
            let bytes = std::fs::read(path).map_err(|_| "That picture could not be added.".to_string())?;
            put(data, kind, name, &base64::engine::general_purpose::STANDARD.encode(bytes))?;
            let _ = std::fs::remove_file(path);
            Ok(())
        }
        "recording" => {
            use std::io::Read as _;
            let recordings = data.join(crate::paths::RECORDINGS);
            let file = recording_file(&recordings, name).ok_or_else(|| "That is not a note id.".to_string())?;
            let mut start = [0u8; 4];
            let riff = std::fs::File::open(path).and_then(|mut source| source.read_exact(&mut start)).is_ok() && &start == b"RIFF";
            if !riff {
                return Err("That is not a recording Glyph can keep.".to_string());
            }
            std::fs::create_dir_all(&recordings).map_err(|e| e.to_string())?;
            move_in(path, &file).map_err(|e| format!("The recording could not be saved: {e}"))
        }
        _ => Err(format!("Nothing is kept as {kind}.")),
    }
}

/// A note's versions file as the library has it, or `None`.
fn versions(notes: &NotesStore, id: &str) -> Result<Option<String>, String> {
    notes.lock().read_versions(id).map_err(|e| e.to_string())
}

/// One of this module's commands, given the app's data and cache directories and its library.
pub fn call(data: &Path, cache: &Path, notes: &NotesStore, command: &str, args: Value) -> Result<Value, String> {
    match command {
        "save_video" => {
            let SaveVideo { path, poster } = read(command, args)?;
            let picked = cache.join(crate::paths::PICKED);
            let saved = crate::kept::videos::save_video(&picked, &data.join(crate::paths::VIDEO), &data.join(crate::paths::IMAGES), &path, &poster)?;
            serde_json::to_value(saved).map_err(|e| e.to_string())
        }
        "discard_picked" => {
            let Discard { path } = read(command, args)?;
            crate::kept::videos::discard_picked(&cache.join(crate::paths::PICKED), &path).map(|()| Value::Null)
        }
        "sync_put_file" => {
            let Put { kind, name, base64 } = read(command, args)?;
            put(data, &kind, &name, &base64).map(|()| Value::Null)
        }
        "sync_put_file_path" => {
            let PutPath { kind, name, path } = read(command, args)?;
            put_path(data, &kind, &name, &path).map(|()| Value::Null)
        }
        "read_file" => {
            let Named { kind, name } = read(command, args)?;
            let bytes = if kind == "versions" {
                versions(notes, &name)?.map(String::into_bytes)
            } else {
                present(kept_path(data, &kind, &name)?).and_then(|(path, _)| std::fs::read(path).ok())
            };
            Ok(json!(bytes.map(|bytes| base64::engine::general_purpose::STANDARD.encode(bytes))))
        }
        "file_path" => {
            let Named { kind, name } = read(command, args)?;
            if kind == "versions" {
                return Err("A versions file is read, never sealed where it lies: it may be in a folder that has no path.".to_string());
            }
            if kind == "video" {
                return Ok(json!(present(film_path(data, &name)).map(|(path, bytes)| json!({ "path": path.display().to_string(), "bytes": bytes }))));
            }
            Ok(json!(present(kept_path(data, &kind, &name)?).map(|(path, bytes)| json!({ "path": path.display().to_string(), "bytes": bytes }))))
        }
        "file_digest" => {
            let Named { kind, name } = read(command, args)?;
            if kind == "versions" {
                return Ok(json!(versions(notes, &name)?.map(|text| crate::crypto::sha256_16(text.as_bytes()))));
            }
            Ok(json!(present(kept_path(data, &kind, &name)?).and_then(|(path, _)| crate::crypto::digest_file(&path))))
        }
        "file_exists" => {
            let Named { kind, name } = read(command, args)?;
            if kind == "versions" {
                return Ok(json!(versions(notes, &name)?.is_some()));
            }
            if kind == "video" {
                return Ok(json!(present(film_path(data, &name)).is_some()));
            }
            Ok(json!(present(kept_path(data, &kind, &name)?).is_some()))
        }
        _ => Err(format!("Ghost.md's core has no command named {command}.")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::Library;
    use crate::test_support::TempDir;
    use std::sync::Mutex;

    fn b64(bytes: &[u8]) -> String {
        base64::engine::general_purpose::STANDARD.encode(bytes)
    }

    struct Phone {
        notes: NotesStore,
        root: TempDir,
    }

    impl Phone {
        fn new() -> Phone {
            let root = TempDir::new("files");
            let notes = NotesStore(Mutex::new(Library::open_fs(&root.join("Library")).unwrap()));
            Phone { notes, root }
        }

        fn ask(&self, command: &str, args: Value) -> Result<Value, String> {
            call(&self.root, &self.root.join("cache"), &self.notes, command, args)
        }
    }

    const JPEG: [u8; 6] = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2];

    #[test]
    fn a_synced_picture_is_kept_under_its_name_only_if_it_is_what_the_name_says() {
        let phone = Phone::new();
        assert_eq!(phone.ask("file_exists", json!({"kind": "image", "name": "abc.jpg"})), Ok(json!(false)));
        assert_eq!(phone.ask("read_file", json!({"kind": "image", "name": "abc.jpg"})), Ok(Value::Null));
        assert_eq!(phone.ask("sync_put_file", json!({"kind": "image", "name": "abc.jpg", "base64": b64(&JPEG)})), Ok(Value::Null));
        assert_eq!(std::fs::read(phone.root.join("images/abc.jpg")).unwrap(), JPEG);
        assert_eq!(phone.ask("read_file", json!({"kind": "image", "name": "abc.jpg"})), Ok(json!(b64(&JPEG))));
        assert_eq!(phone.ask("file_exists", json!({"kind": "image", "name": "abc.jpg"})), Ok(json!(true)));
        assert_eq!(phone.ask("file_digest", json!({"kind": "image", "name": "abc.jpg"})), Ok(json!(crate::crypto::sha256_16(&JPEG))));
        let at = phone.ask("file_path", json!({"kind": "image", "name": "abc.jpg"})).unwrap();
        assert_eq!((at["path"].as_str(), at["bytes"].as_u64()), (Some(phone.root.join("images/abc.jpg").to_str().unwrap()), Some(6)));

        // The Tauri command's own refusals, in its own words.
        let put = |name: &str, bytes: &[u8]| phone.ask("sync_put_file", json!({"kind": "image", "name": name, "base64": b64(bytes)})).unwrap_err();
        assert_eq!(put("abc.png", &JPEG), "That picture is not what its name says.");
        assert_eq!(put("../abc.jpg", &JPEG), "That is not a picture name.");
        assert_eq!(put("t.jpg", b"hello"), "That is not a picture Glyph can add.");
        assert_eq!(phone.ask("sync_put_file", json!({"kind": "film", "name": "a.mp4", "base64": ""})), Err("Nothing is kept as film.".into()));
        // A name that may not name a file reads as nothing, and reaches nothing.
        std::fs::write(phone.root.join("secret.jpg"), JPEG).unwrap();
        for command in ["read_file", "file_path", "file_digest"] {
            assert_eq!(phone.ask(command, json!({"kind": "image", "name": "../secret.jpg"})), Ok(Value::Null), "{command}");
        }
        assert_eq!(phone.ask("read_file", json!({"kind": "film", "name": "a.mp4"})), Err("Nothing is kept as film.".into()));
    }

    #[test]
    fn a_synced_recording_is_kept_under_its_note_s_id_only_if_it_is_a_riff_file() {
        let phone = Phone::new();
        let wav = b"RIFF\x24\0\0\0WAVEfmt and the sound".to_vec();
        assert_eq!(phone.ask("sync_put_file", json!({"kind": "recording", "name": "n1", "base64": b64(&wav)})), Ok(Value::Null));
        assert_eq!(std::fs::read(phone.root.join("recordings/n1.wav")).unwrap(), wav);
        assert_eq!(phone.ask("read_file", json!({"kind": "recording", "name": "n1"})), Ok(json!(b64(&wav))));
        assert_eq!(phone.ask("file_digest", json!({"kind": "recording", "name": "n1"})), Ok(json!(crate::crypto::sha256_16(&wav))));
        assert_eq!(phone.ask("file_digest", json!({"kind": "recording", "name": "n2"})), Ok(Value::Null));
        let put = |name: &str, bytes: &[u8]| phone.ask("sync_put_file", json!({"kind": "recording", "name": name, "base64": b64(bytes)})).unwrap_err();
        assert_eq!(put("../n1", &wav), "That is not a note id.");
        assert_eq!(put("n3", b"ID3 not a wav"), "That is not a recording Glyph can keep.");
        assert_eq!(phone.ask("sync_put_file", json!({"kind": "recording", "name": "n3", "base64": "not base64!"})), Err("That recording could not be read.".into()));
        assert!(!phone.root.join("recordings/n3.wav").exists());
    }

    #[test]
    fn a_file_opened_beside_is_adopted_by_the_same_rules_and_moved_in() {
        let phone = Phone::new();
        let arrived = phone.root.join("cache");
        std::fs::create_dir_all(&arrived).unwrap();
        let wav = b"RIFF and an hour of sound".to_vec();
        std::fs::write(arrived.join("r.opened"), &wav).unwrap();
        assert_eq!(phone.ask("sync_put_file_path", json!({"kind": "recording", "name": "n1", "path": arrived.join("r.opened")})), Ok(Value::Null));
        assert_eq!(std::fs::read(phone.root.join("recordings/n1.wav")).unwrap(), wav);
        assert!(!arrived.join("r.opened").exists(), "moved, not copied");

        std::fs::write(arrived.join("bad"), b"ID3").unwrap();
        assert_eq!(phone.ask("sync_put_file_path", json!({"kind": "recording", "name": "n2", "path": arrived.join("bad")})), Err("That is not a recording Glyph can keep.".into()));
        assert_eq!(phone.ask("sync_put_file_path", json!({"kind": "recording", "name": "a/b", "path": arrived.join("bad")})), Err("That is not a note id.".into()));
        assert!(arrived.join("bad").exists() && !phone.root.join("recordings/n2.wav").exists());

        std::fs::write(arrived.join("p.opened"), JPEG).unwrap();
        assert_eq!(phone.ask("sync_put_file_path", json!({"kind": "image", "name": "pic.jpeg", "path": arrived.join("p.opened")})), Ok(Value::Null));
        assert_eq!(std::fs::read(phone.root.join("images/pic.jpeg")).unwrap(), JPEG);
        assert!(!arrived.join("p.opened").exists());
        std::fs::write(arrived.join("p2.opened"), JPEG).unwrap();
        assert_eq!(phone.ask("sync_put_file_path", json!({"kind": "image", "name": "pic.webp", "path": arrived.join("p2.opened")})), Err("That picture is not what its name says.".into()));
        assert!(arrived.join("p2.opened").exists(), "a file that was refused is left for whoever opened it");
    }

    #[test]
    fn a_versions_file_is_read_through_the_library_and_has_no_path() {
        let phone = Phone::new();
        phone.notes.lock().save_note("n1", "# Plan\n", "editor").unwrap();
        assert_eq!(phone.ask("read_file", json!({"kind": "versions", "name": "n1"})), Ok(Value::Null));
        assert_eq!(phone.ask("file_exists", json!({"kind": "versions", "name": "n1"})), Ok(json!(false)));
        let text = "{\"v\":1,\"versions\":[\"día\"]}";
        assert!(phone.notes.lock().write_versions("n1", text).unwrap());
        assert_eq!(phone.ask("read_file", json!({"kind": "versions", "name": "n1"})), Ok(json!(b64(text.as_bytes()))));
        assert_eq!(phone.ask("file_digest", json!({"kind": "versions", "name": "n1"})), Ok(json!(crate::crypto::sha256_16(text.as_bytes()))));
        assert_eq!(phone.ask("file_exists", json!({"kind": "versions", "name": "n1"})), Ok(json!(true)));
        assert_eq!(phone.ask("read_file", json!({"kind": "versions", "name": "nobody"})), Ok(Value::Null));
        assert!(phone.ask("file_path", json!({"kind": "versions", "name": "n1"})).unwrap_err().starts_with("A versions file is read"));
        assert!(has("sync_put_file") && has("file_digest") && !has("seal_file"));
    }

    const MP4: &[u8] = b"\0\0\0\x18ftypmp42\0\0\0\0 and the rest of a film";

    #[test]
    fn a_picked_film_and_its_poster_are_kept_and_only_from_the_picked_folder() {
        let phone = Phone::new();
        let picked = phone.root.join("cache/picked");
        std::fs::create_dir_all(&picked).unwrap();
        std::fs::write(picked.join("p.mp4"), MP4).unwrap();
        std::fs::write(picked.join("p.jpg"), JPEG).unwrap();
        let saved = phone.ask("save_video", json!({"path": picked.join("p.mp4"), "poster": picked.join("p.jpg")})).unwrap();
        let (video, poster) = (saved["video"].as_str().unwrap(), saved["poster"].as_str().unwrap());
        assert!(crate::kept::videos::valid_name(video) && video.ends_with(".mp4"), "{saved}");
        assert!(crate::kept::images::valid_name(poster) && poster.ends_with(".jpg"), "{saved}");
        assert_eq!(std::fs::read(phone.root.join("video").join(video)).unwrap(), MP4);
        assert_eq!(std::fs::read(phone.root.join("images").join(poster)).unwrap(), JPEG);
        assert!(!picked.join("p.mp4").exists() && !picked.join("p.jpg").exists(), "moved, not copied");

        // Where it lies and whether it is here, and nothing sync would ask of it.
        assert_eq!(phone.ask("file_exists", json!({"kind": "video", "name": video})), Ok(json!(true)));
        let at = phone.ask("file_path", json!({"kind": "video", "name": video})).unwrap();
        assert_eq!((at["path"].as_str(), at["bytes"].as_u64()), (Some(phone.root.join("video").join(video).to_str().unwrap()), Some(MP4.len() as u64)));
        assert_eq!(phone.ask("file_exists", json!({"kind": "video", "name": "nobody.mp4"})), Ok(json!(false)));
        assert_eq!(phone.ask("file_exists", json!({"kind": "video", "name": "../video/x.mp4"})), Ok(json!(false)));
        for command in ["read_file", "file_digest"] {
            assert_eq!(phone.ask(command, json!({"kind": "video", "name": video})), Err("Nothing is kept as video.".into()), "{command}");
        }
        assert_eq!(phone.ask("sync_put_file", json!({"kind": "video", "name": video, "base64": ""})), Err("Nothing is kept as video.".into()));

        // A film that is not one takes its poster with it; a file elsewhere is neither adopted nor thrown away.
        std::fs::write(picked.join("q.mp4"), b"not a film").unwrap();
        std::fs::write(picked.join("q.jpg"), JPEG).unwrap();
        assert_eq!(phone.ask("save_video", json!({"path": picked.join("q.mp4"), "poster": picked.join("q.jpg")})), Err("The video couldn’t be kept.".into()));
        assert!(!picked.join("q.mp4").exists() && !picked.join("q.jpg").exists());
        assert_eq!(std::fs::read_dir(phone.root.join("images")).unwrap().count(), 1);
        std::fs::write(phone.root.join("elsewhere.mp4"), MP4).unwrap();
        assert_eq!(phone.ask("discard_picked", json!({"path": phone.root.join("elsewhere.mp4")})), Err("That is not a picked file.".into()));
        assert!(phone.root.join("elsewhere.mp4").exists());
        std::fs::write(picked.join("r.mp4"), MP4).unwrap();
        assert_eq!(phone.ask("discard_picked", json!({"path": picked.join("r.mp4")})), Ok(Value::Null));
        assert!(!picked.join("r.mp4").exists());
        assert_eq!(phone.ask("discard_picked", json!({"path": picked.join("gone.mp4")})), Ok(Value::Null));
    }
}
