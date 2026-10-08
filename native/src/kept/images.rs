//! The pictures a deleted note takes with it: the four items of `../glyph/src-tauri/src/images.rs` that
//! `delete_note` needs, word for word.
//!
//! images.rs cannot come in by `#[path]` as the library does: it also holds the `img` scheme and two Tauri
//! commands, so it names `tauri::` types. What is between the marks below is copied from it unchanged, and
//! `kept::tests` reads the original and fails when either side moves.

use std::path::Path;

// copied:begin
const EXTENSIONS: [&str; 4] = ["jpg", "jpeg", "png", "webp"];

/// Whether `name` is a picture name this module will turn into a path: a
/// plain id (`fsx::plain_id`) of at most 64 characters - a picture's stem is a
/// uuid, so it never needed the 128 a note id may have, and a name that was
/// refused before must stay refused - then one image extension.
pub fn valid_name(name: &str) -> bool {
    let Some((stem, extension)) = name.rsplit_once('.') else { return false };
    stem.len() <= 64 && crate::fsx::plain_id(stem) && EXTENSIONS.contains(&extension)
}

/// The picture names a note's body refers to, as `![alt](image/<name>)`, in
/// order, without repeats. Names that are not valid are skipped.
pub fn referenced(body: &str) -> Vec<String> {
    let mut names = Vec::new();
    let mut rest = body;
    while let Some(at) = rest.find("![") {
        rest = &rest[at + 2..];
        let Some(close) = rest.find("](image/") else { continue };
        // The alt text may not hold a `]`, the same as the page's pattern.
        if rest[..close].contains(']') {
            continue;
        }
        let after = &rest[close + "](image/".len()..];
        let Some(end) = after.find(')') else { continue };
        let name = &after[..end];
        if valid_name(name) && !names.iter().any(|n| n == name) {
            names.push(name.to_string());
        }
        rest = &after[end..];
    }
    names
}


/// Removes from `images` the pictures a deleted note referred to, unless
/// another note in `library` still does. Best effort: a picture that cannot be
/// removed, or whose use cannot be checked, is left, and the delete it follows
/// has already happened.
pub fn remove_unreferenced(images: &Path, library: &crate::library::Library, body: &str) {
    for name in referenced(body) {
        if library.image_in_use(&name).unwrap_or(true) {
            continue;
        }
        let _ = std::fs::remove_file(images.join(&name));
    }
}
// copied:end
