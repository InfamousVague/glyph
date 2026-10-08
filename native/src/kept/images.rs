//! The pictures a deleted note takes with it, and a picture that arrives by sync: the items of
//! `../glyph/src-tauri/src/images.rs` that `delete_note` and `sync_put_file` need, word for word.
//!
//! images.rs cannot come in by `#[path]` as the library does: it also holds the `img` scheme and two Tauri
//! commands, so it names `tauri::` types. What is between the marks below is copied from it unchanged, and
//! `kept::tests` reads the original and fails when either side moves.

use std::path::Path;

// copied:begin
/// The largest picture adopted. The shell writes JPEGs of at most 1600 px at
/// quality 85, well under a megabyte; this only refuses something that is not
/// one of those.
const MAX_BYTES: u64 = 25 * 1024 * 1024;

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

/// The extension a picture's first bytes say it is: JPEG, PNG or WebP, and
/// nothing else. The bytes, not what the page says they are.
fn kind(bytes: &[u8]) -> Option<&'static str> {
    if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        Some("jpg")
    } else if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        Some("png")
    } else if bytes.len() >= 12 && bytes.starts_with(b"RIFF") && &bytes[8..12] == b"WEBP" {
        Some("webp")
    } else {
        None
    }
}

/// Base64 from the page, as plain base64 or a whole `data:` URL. Refused
/// before decoding when it could only decode to more than `MAX_BYTES`.
fn decode(text: &str) -> Result<Vec<u8>, String> {
    use base64::Engine as _;
    let text = text.split_once(";base64,").map_or(text, |(_, data)| data).trim();
    if text.len() as u64 > MAX_BYTES / 3 * 4 + 4 {
        return Err("That picture is too big to add.".to_string());
    }
    base64::engine::general_purpose::STANDARD
        .decode(text)
        .map_err(|_| "That picture could not be added.".to_string())
}

/// Keeps a picture that arrived by sync under the name it already has on the
/// device it came from, which is the name its notes refer to it by. The bytes
/// still have to be a picture, and of the kind the name says.
pub fn place(images: &Path, name: &str, base64: &str) -> Result<(), String> {
    if !valid_name(name) {
        return Err("That is not a picture name.".to_string());
    }
    let bytes = decode(base64)?;
    if bytes.len() as u64 > MAX_BYTES {
        return Err("That picture is too big to add.".to_string());
    }
    let extension = name.rsplit_once('.').map(|(_, e)| e.to_ascii_lowercase()).unwrap_or_default();
    let said = kind(&bytes).ok_or_else(|| "That is not a picture Glyph can add.".to_string())?;
    if said != extension && !(said == "jpg" && extension == "jpeg") {
        return Err("That picture is not what its name says.".to_string());
    }
    std::fs::create_dir_all(images).map_err(|e| format!("There is no room to keep pictures: {e}"))?;
    crate::fsx::write_atomically(&images.join(name), &bytes).map_err(|e| format!("The picture could not be saved: {e}"))
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
