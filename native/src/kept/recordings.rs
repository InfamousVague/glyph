//! Where a note's kept recording lives, and how one that arrives by sync is kept: the two functions of
//! `tauri/src-tauri/src/recordings.rs` that `delete_note` and `sync_put_file` need, word for word. The rest of that file is the `rec` scheme, which is Tauri's.
//! `kept::tests` holds what is between the marks to the original.

use std::path::{Path, PathBuf};

// copied:begin
/// Where note `id`'s recording lives inside `recordings`, or `None` for an id
/// that is not a plain name. Ids reach this from the page, and one that is not
/// letters, digits, `-` and `_` - a `../`, a slash - must never become a path
/// to write or delete. The rule is `fsx::plain_id`, the same one a note's
/// sidecar and a picture's name obey.
pub fn recording_file(recordings: &Path, id: &str) -> Option<PathBuf> {
    crate::fsx::plain_id(id).then(|| recordings.join(format!("{id}.wav")))
}

/// Keeps a recording that arrived by sync under the note's id: base64 of a
/// WAV file, written whole or not at all into `recordings` (made if it is not
/// there). Refuses an id that may not name a file and bytes that are not a
/// RIFF file, before anything is written.
pub fn place(recordings: &Path, id: &str, base64: &str) -> Result<(), String> {
    use base64::Engine as _;
    let file = recording_file(recordings, id).ok_or_else(|| "That is not a note id.".to_string())?;
    let bytes = base64::engine::general_purpose::STANDARD.decode(base64.trim()).map_err(|_| "That recording could not be read.".to_string())?;
    if !bytes.starts_with(b"RIFF") {
        return Err("That is not a recording Glyph can keep.".to_string());
    }
    std::fs::create_dir_all(recordings).map_err(|e| e.to_string())?;
    crate::fsx::write_atomically(&file, &bytes).map_err(|e| format!("The recording could not be saved: {e}"))
}
// copied:end
