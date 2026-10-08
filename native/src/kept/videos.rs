//! The films a deleted note takes with it: the four items of `../glyph/src-tauri/src/videos.rs` that
//! `delete_note` needs, word for word. The rest of that file (adopting a picked film, the weekly sweep, the
//! `vid` scheme) names Tauri and waits for its stage. `kept::tests` holds what is between the marks to the
//! original.

use std::path::Path;

// copied:begin
/// The kinds of film kept. KOTLIN TWIN: media/VideoPick.kt's `EXTENSIONS`,
/// which names a picked film by its type; a test here reads it.
pub const EXTENSIONS: [&str; 4] = ["mp4", "m4v", "mov", "webm"];

/// Whether `name` is a film name this module will turn into a path: a plain id
/// of at most 64 characters (a uuid), then one film extension.
pub fn valid_name(name: &str) -> bool {
    let Some((stem, extension)) = name.rsplit_once('.') else { return false };
    stem.len() <= 64 && crate::fsx::plain_id(stem) && EXTENSIONS.contains(&extension)
}

/// The films a note's body names as `(video/<name>)`, in order, without
/// repeats. Names that are not valid are skipped.
pub fn referenced(body: &str) -> Vec<String> {
    let mut names = Vec::new();
    let mut rest = body;
    while let Some(at) = rest.find("](video/") {
        let after = &rest[at + "](video/".len()..];
        let Some(end) = after.find(')') else { break };
        let name = &after[..end];
        if valid_name(name) && !names.iter().any(|n| n == name) {
            names.push(name.to_string());
        }
        rest = &after[end..];
    }
    names
}

/// Removes from `videos` the films a deleted note named, unless another note
/// in `library` still does. Best effort, as the pictures' is.
pub fn remove_unreferenced(videos: &Path, library: &crate::library::Library, body: &str) {
    for name in referenced(body) {
        if library.video_in_use(&name).unwrap_or(true) {
            continue;
        }
        let _ = std::fs::remove_file(videos.join(&name));
    }
}
// copied:end
