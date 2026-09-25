//! A directory of a test's own, removed when the test ends however it ends.
//!
//! A test that cleans up with `remove_dir_all` as its last line leaves its
//! directory behind whenever an assertion above that line fails; a `TempDir`
//! goes when it is dropped, which a failing assertion's unwinding does too.
//! Each is named by a uuid, so two runs (or what a crashed run left) never
//! share one.
//!
//! Free of Tauri types on purpose: tools/host-tests compiles this file by path
//! as its own `test_support`, for the library's and fsx's tests there.

use std::path::{Path, PathBuf};

/// `<temp dir>/glyph-<label>-<uuid>`, made empty, and removed on drop. It
/// derefs to its `Path`, so `dir.join(..)` and `&dir` work where a path does.
pub struct TempDir(PathBuf);

impl TempDir {
    pub fn new(label: &str) -> TempDir {
        let dir = std::env::temp_dir().join(format!("glyph-{label}-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        TempDir(dir)
    }
}

impl std::ops::Deref for TempDir {
    type Target = Path;

    fn deref(&self) -> &Path {
        &self.0
    }
}

impl AsRef<Path> for TempDir {
    fn as_ref(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        // Gone already, or nothing a test could do about it.
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
