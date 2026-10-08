//! The library's folder, moved and gone back from: the items of `../glyph/src-tauri/src/library_commands.rs`
//! that need no Tauri, word for word between the marks. That file's commands take Tauri's `AppHandle` and
//! `State` and open the Mac's folder panel, so it cannot be included whole; `kept::tests` holds what is here to
//! it. The commands themselves are folder.rs's.

use std::path::{Path, PathBuf};

// copied:begin
/// The folders a reset forgets: every chosen folder's index and an Android folder's `.glyph/`, all in the app's
/// storage (library/root.rs). Nothing in a chosen folder is among them.
pub fn bookkeeping(data: &Path) -> [PathBuf; 2] {
    [data.join(crate::library::root::INDEXES), data.join(crate::library::root::TREES)]
}
// copied:end
