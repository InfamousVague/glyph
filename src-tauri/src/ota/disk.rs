//! What the OTA system keeps under `<app_data_dir>/ota/`, and the one way each
//! file is read and written: `state.json` (which bundle runs, which it
//! replaced, what has failed), `installed.json` (the newest frontend this
//! install can already run), and one directory per downloaded bundle, named by
//! its build.
//!
//! Every write is a whole file (`fsx::write_atomically`), so a process killed
//! mid-write leaves the old state or the new one, and every read of a missing
//! or garbled file is the state a first launch starts from. `sources.json` is
//! `sources`'s.

use std::path::Path;
use std::sync::Mutex;

use serde::{Deserialize, Serialize};

use super::manifest::{build_number, validate, Manifest, MANIFEST_FILE};
use crate::fsx;
use crate::lock::lock;

/// `state.json`: which bundle runs, which one it replaced, and what has failed.
#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub(super) struct Stored {
    pub(super) active: Option<String>,
    pub(super) previous: Option<String>,
    pub(super) pending: Option<String>,
    pub(super) strikes: u32,
    pub(super) quarantined: Vec<String>,
}

/// `state.json`, or the state a first launch starts from: no bundle, nothing
/// staked, nothing quarantined.
pub(super) fn read_stored(root: &Path) -> Stored {
    fsx::read_json_or(&root.join("state.json"), Stored::default())
}

/// Around every read-modify-write of `installed.json` and `sources.json`. Those
/// two are written from outside the command lock too: by the background update
/// check (update_alerts.rs), which WorkManager runs on its own thread in the
/// SAME process as an open app - so without this, the worker and the app's own
/// check can both read the old file and the older write can land last.
pub(super) static FILES: Mutex<()> = Mutex::new(());

/// A truncated state reads back as "no bundle, nothing quarantined", which is
/// why this goes through `fsx::write_atomically`: a process killed mid-write
/// leaves the previous file rather than a truncated one, and two writers at
/// once never share - and garble - one temporary file.
pub(super) fn write_stored(root: &Path, stored: &Stored) -> Result<(), String> {
    let bytes = serde_json::to_vec_pretty(stored).map_err(|e| e.to_string())?;
    fsx::write_atomically(&root.join("state.json"), &bytes).map_err(|e| format!("cannot write OTA state: {e}"))
}

/// A bundle directory's manifest, if the directory is complete.
pub(super) fn bundle_manifest(dir: &Path) -> Option<Manifest> {
    let manifest: Manifest = fsx::read_json(&dir.join(MANIFEST_FILE))?;
    validate(&manifest).ok()?;
    let complete = manifest.files.iter().all(|f| {
        std::fs::metadata(dir.join(&f.path))
            .map(|m| m.len() == f.bytes)
            .unwrap_or(false)
    });
    complete.then_some(manifest)
}

/// Removes a downloaded bundle's directory - only ever one named by a build id,
/// so a name from a manifest can never reach anything else under `root`.
pub(super) fn remove_bundle(root: &Path, build: &str) {
    if build_number(build).is_some() {
        let _ = std::fs::remove_dir_all(root.join(build));
    }
}

/// `installed.json`: the newest frontend build this install can already run,
/// embedded or downloaded. The background update check (update_alerts.rs) runs
/// with no Tauri in the process and so cannot read the embedded manifest; it
/// compares against this instead, so it never announces what is already here.
#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
struct Installed {
    build: Option<String>,
}

pub(super) fn record_installed(root: &Path, build: &str) {
    let _files = lock(&FILES);
    let had = read_installed(root).as_deref().and_then(build_number).unwrap_or(0);
    if build_number(build).unwrap_or(0) <= had {
        return;
    }
    if let Ok(bytes) = serde_json::to_vec(&Installed { build: Some(build.to_string()) }) {
        let _ = fsx::write_atomically(&root.join("installed.json"), &bytes);
    }
}

pub(super) fn read_installed(root: &Path) -> Option<String> {
    fsx::read_json_or(&root.join("installed.json"), Installed::default()).build
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ota::test_support::{bundle, manifest, temp};

    #[test]
    fn the_installed_record_only_moves_forward() {
        let dir = temp("installed");
        record_installed(&dir, "20260912230000");
        record_installed(&dir, "20260901000000");
        assert_eq!(read_installed(&dir).as_deref(), Some("20260912230000"));
        record_installed(&dir, "20260913000000");
        assert_eq!(read_installed(&dir).as_deref(), Some("20260913000000"));
    }

    #[test]
    fn a_bundle_is_offered_only_while_every_file_it_lists_is_whole() {
        let root = temp("complete");
        let dir = bundle(&root, &manifest("20260912221530"));
        assert!(bundle_manifest(&dir).is_some(), "every file at its listed length");
        // A file cut short on disk (a full phone, a killed install) is not a bundle to run.
        std::fs::write(dir.join("assets/index.css"), b"").unwrap();
        assert!(bundle_manifest(&dir).is_none());
        std::fs::remove_file(dir.join("assets/index.css")).unwrap();
        assert!(bundle_manifest(&dir).is_none(), "nor is one missing a file");
        assert!(bundle_manifest(&root.join("20260101000000")).is_none(), "nor a directory with no manifest");
    }

    #[test]
    fn only_a_directory_named_by_a_build_is_ever_removed() {
        let root = temp("remove");
        std::fs::create_dir_all(root.join("20260912221530")).unwrap();
        std::fs::create_dir_all(root.join("keep")).unwrap();
        remove_bundle(&root, "keep");
        remove_bundle(&root, "..");
        remove_bundle(&root, "20260912221530");
        assert!(root.join("keep").is_dir() && !root.join("20260912221530").exists());
    }

    #[test]
    fn a_state_file_that_is_missing_or_garbled_is_a_first_launch() {
        let root = temp("stored");
        assert_eq!(read_stored(&root).active, None);
        let stored = Stored { active: Some("20260912221530".into()), strikes: 1, ..Stored::default() };
        write_stored(&root, &stored).unwrap();
        let back = read_stored(&root);
        assert_eq!((back.active.as_deref(), back.strikes), (Some("20260912221530"), 1));
        std::fs::write(root.join("state.json"), b"{ half").unwrap();
        assert_eq!(read_stored(&root).active, None, "no bundle, nothing quarantined");
    }
}
