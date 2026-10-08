//! A folder chosen through Android's picker, which this app cannot reach yet: the stand-in for
//! `../glyph/src-tauri/src/saf.rs`.
//!
//! The original calls into the Tauri app's Kotlin (`files/LibraryTree.kt`) over JNI. The Flutter app has no
//! such class, and stage 3 offers no way to choose a folder, so `TreeDocuments::new` answers Err. What follows
//! from that is `library_root::open`'s own rule for a folder that cannot be reached: the app's own folder is
//! opened for this run, and the choice is kept.
//!
//! `library_root.rs` names `crate::saf` only when compiled for Android; this is compiled everywhere so the Mac's
//! tests hold it to the `Documents` trait.

use std::io;

use crate::library::tree::Documents;
use crate::library::vault::Entry;

const NOT_YET: &str = "a folder chosen on the phone cannot be opened by this version of Ghost.md";

/// A tree URI's documents. Never made: `new` always answers Err.
pub struct TreeDocuments(());

impl TreeDocuments {
    pub fn new(_uri: &str) -> Result<TreeDocuments, String> {
        Err(NOT_YET.into())
    }
}

fn not_yet<T>() -> io::Result<T> {
    Err(io::Error::other(NOT_YET))
}

impl Documents for TreeDocuments {
    fn list(&self) -> io::Result<Vec<Entry>> {
        not_yet()
    }

    fn read(&self, _path: &str) -> io::Result<String> {
        not_yet()
    }

    fn write(&self, _path: &str, _text: &str) -> io::Result<Entry> {
        not_yet()
    }

    fn rename(&self, _from: &str, _to: &str) -> io::Result<()> {
        not_yet()
    }

    fn remove(&self, _path: &str) -> io::Result<()> {
        not_yet()
    }

    fn stat(&self, _path: &str) -> io::Result<Option<Entry>> {
        not_yet()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_chosen_folder_is_refused_with_a_sentence() {
        assert_eq!(TreeDocuments::new("content://x/tree/y").err().as_deref(), Some(NOT_YET));
    }
}
