//! What the OTA tests build their worlds from: a manifest that validates, a
//! bundle directory on disk that `disk::bundle_manifest` accepts, and a
//! directory of their own to put it in.

use std::path::{Path, PathBuf};

use super::manifest::{Manifest, ManifestFile, Services};
use crate::test_support::TempDir;

/// A fresh directory for one OTA test, removed when it is dropped.
pub fn temp(label: &str) -> TempDir {
    TempDir::new(&format!("ota-{label}"))
}

/// A valid manifest for `build`: an entry script and a stylesheet of one byte each.
pub fn manifest(build: &str) -> Manifest {
    Manifest {
        schema: 1,
        build: build.into(),
        version: "0.2.0".into(),
        native: 1,
        entry: "assets/index.js".into(),
        styles: vec!["assets/index.css".into()],
        files: vec![
            ManifestFile { path: "assets/index.js".into(), sha256: "a".repeat(64), bytes: 1 },
            ManifestFile { path: "assets/index.css".into(), sha256: "b".repeat(64), bytes: 1 },
        ],
        sources: vec![],
        services: Services::default(),
        notes: None,
    }
}

/// `manifest` installed as a complete bundle directory under `root`, the way
/// an install leaves one: every listed file at its listed length, and the
/// manifest beside them. Answers the directory.
pub fn bundle(root: &Path, manifest: &Manifest) -> PathBuf {
    let dir = root.join(&manifest.build);
    for file in &manifest.files {
        let path = dir.join(&file.path);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, vec![b'x'; file.bytes as usize]).unwrap();
    }
    std::fs::write(dir.join(super::manifest::MANIFEST_FILE), serde_json::to_vec(manifest).unwrap()).unwrap();
    dir
}
