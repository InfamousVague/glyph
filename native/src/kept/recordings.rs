//! Where a note's kept recording lives: the one function of `../glyph/src-tauri/src/recordings.rs` that
//! `delete_note` needs, word for word. The rest of that file is the `rec` scheme, which is Tauri's.
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
// copied:end
