//! Where a note made in the page is kept in the library, as the phone's library would have named it: the one
//! decision the web store (lib/core/native/web_store.dart) asks of Rust, so a note synced from the page lands in
//! the file the Mac would have written.
//!
//! The rules are tauri/src-tauri/src/library/mod.rs's, copied word for word where that file keeps them private
//! (`named_for`, `folder_of`, `in_folder`, `INBOX`) and called where names.rs makes them public (`title_of`,
//! `file_stem`, `unique_name`). The page's library is the app's own folder, so a file always follows its title.

use serde::Deserialize;
use serde_json::{json, Value};

use crate::names::{file_stem, title_of, unique_name};

/// A new note's folder (library/mod.rs `INBOX`).
pub const INBOX: &str = "Inbox";

fn folder_of(path: &str) -> &str {
    path.rfind('/').map_or("", |at| &path[..at])
}

fn in_folder(folder: &str, name: &str) -> String {
    if folder.is_empty() { name.to_string() } else { format!("{folder}/{name}") }
}

/// Whether a file's name is already its title's: `Stem.md`, or `Stem 2.md` for a clash.
fn named_for(path: &str, stem: &str) -> bool {
    let name = path.rsplit('/').next().unwrap_or(path);
    let Some(bare) = name.strip_suffix(".md").or_else(|| name.strip_suffix(".MD")) else { return false };
    bare == stem || bare.strip_prefix(stem).and_then(|rest| rest.strip_prefix(' ')).is_some_and(|n| !n.is_empty() && n.chars().all(|c| c.is_ascii_digit()))
}

/// Whether a path from another device can be a note's here: relative, `.md`, no dot folders or `..`.
fn library_path(path: &str) -> bool {
    path.to_ascii_lowercase().ends_with(".md") && path.split('/').all(|part| !part.is_empty() && !part.starts_with('.'))
}

#[derive(Deserialize)]
struct Named {
    /// The note's words, front matter and all.
    body: String,
    /// Where its file is now; none for a note with no file yet.
    path: Option<String>,
    /// Where another device keeps it (`store_apply`): taken when it is free.
    wanted: Option<String>,
    /// Every path the library holds but this note's own.
    taken: Vec<String>,
}

/// `note_path`: where the note's file is to be after this write. The rules of `save_note` and `apply_note`:
///
/// - a note with no file gets `Inbox/<title>.md` (or the folder another device keeps it in, `wanted`), the
///   first of `Title.md`, `Title 2.md` … that is free;
/// - one whose title changed follows it, in the folder it is in;
/// - one another device keeps elsewhere moves there, while that path is free here.
fn note_path(args: Named) -> String {
    let Named { body, path, wanted, taken } = args;
    let stem = file_stem(&title_of(&body));
    let free = |folder: &str| in_folder(folder, &unique_name(&stem, |name| taken.iter().any(|t| *t == in_folder(folder, name))));
    let wanted = wanted.filter(|p| library_path(p));
    // apply_note's two steps: a note with no file is first given a free one named for its title (in the folder another
    // device keeps it in), and then, like a note that has one, moved to where that device keeps it while that is free,
    // or else renamed for its title where it is not named for it already.
    let mut path = path.unwrap_or_else(|| free(wanted.as_deref().map_or(INBOX, folder_of)));
    match wanted {
        Some(to) if to != path && !taken.contains(&to) => path = to,
        _ if !named_for(&path, &stem) => path = free(folder_of(&path)),
        _ => {}
    }
    path
}

pub fn has(command: &str) -> bool {
    command == "note_path"
}

pub fn call(command: &str, args: Value) -> Result<Value, String> {
    match command {
        "note_path" => {
            let named: Named = serde_json::from_value(args).map_err(|e| format!("invalid args for command `{command}`: {e}"))?;
            Ok(json!(note_path(named)))
        }
        _ => Err(format!("Ghost.md's core has no command named {command}.")),
    }
}
