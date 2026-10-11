//! A folder chosen through Android's picker, where there is no Android: the stand-in for
//! `../glyph/src-tauri/src/saf.rs` on the Mac.
//!
//! On a phone the original itself is compiled (lib.rs includes it for Android only, as the Tauri app does): it
//! calls into Kotlin (`files/LibraryTree.kt`) over JNI. Anywhere else there is no such class to call and no such
//! folder to reach, so `TreeDocuments::new` answers Err, and what follows from that is `library_root::open`'s own
//! rule for a folder that cannot be reached: the app's own folder is opened for this run, and the choice is kept.
//!
//! `library_root.rs` names `crate::saf` only when compiled for Android; this is compiled everywhere else so the
//! Mac's tests hold it to the `Documents` trait, and hold this app's Kotlin to the names the original calls.

use std::io;

use crate::library::tree::Documents;
use crate::library::vault::Entry;

const NOT_YET: &str = "a folder chosen on an Android phone cannot be opened here";

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

    /// What `../glyph/src-tauri/src/paths.rs` holds its own Kotlin to, for this app's port of it: the class Rust
    /// is handed is `com.mattssoftware.glyph.files.LibraryTree`, each call the original saf.rs makes is a
    /// `@JvmStatic` method of strings answering a string, and `attach` is the native method saf.rs exports. A
    /// rename on either side fails here rather than as a library that will not open on a phone.
    #[test]
    fn the_folder_bridge_has_every_method_rust_calls() {
        let manifest = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        let kotlin = manifest.join("../android/app/src/main/kotlin/com/mattssoftware/glyph/files/LibraryTree.kt");
        let source = std::fs::read_to_string(&kotlin).unwrap_or_else(|e| panic!("{}: {e}", kotlin.display()));
        assert!(source.starts_with("package com.mattssoftware.glyph.files\n"), "saf.rs exports Java_com_mattssoftware_glyph_files_LibraryTree_attach");
        assert!(source.contains("object LibraryTree {") && source.contains("@JvmStatic private external fun attach()"));
        assert!(source.contains("System.loadLibrary(\"ghost_core\")"), "the library that exports `attach` is this crate's");
        let rust = manifest.join("../../glyph/src-tauri/src/saf.rs");
        let rust = std::fs::read_to_string(&rust).unwrap_or_else(|e| panic!("{}: {e}", rust.display()));
        assert!(rust.contains("pub extern \"system\" fn Java_com_mattssoftware_glyph_files_LibraryTree_attach"));
        // Every `call("<method>", &[…])` in the original, by its name and how many strings it passes.
        let mut called = std::collections::BTreeMap::new();
        for (at, _) in rust.match_indices("call(\"") {
            let rest = &rust[at + 6..];
            let name = &rest[..rest.find('"').unwrap()];
            let args = &rest[rest.find("&[").unwrap() + 2..rest.find(']').unwrap()];
            called.insert(name.to_string(), args.split(',').filter(|arg| !arg.trim().is_empty()).count());
        }
        assert_eq!(called.keys().map(String::as_str).collect::<Vec<_>>(), ["copyIn", "granted", "inspect", "list", "read", "remove", "rename", "stat", "write"]);
        for (name, args) in called {
            let signature = format!("fun {name}(");
            let at = source.find(&signature).unwrap_or_else(|| panic!("LibraryTree.kt has no {signature}"));
            assert!(source[..at].trim_end().ends_with("@JvmStatic"), "{signature} must be @JvmStatic for JNI's static call");
            let declared = &source[at + signature.len()..];
            let declared = &declared[..declared.find(')').unwrap()];
            assert_eq!(declared.matches(": String").count(), args, "{name} takes {args} strings");
            assert!(source[at..].lines().next().unwrap().contains("): String"), "{name} answers a string");
        }
    }
}
