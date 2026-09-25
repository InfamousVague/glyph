//! Where updates come from, and how that moves: the sources compiled into this
//! APK, the newer list a verified manifest may announce (`sources.json`), and
//! the other service endpoints that move with it.
//!
//! The compiled list is never dropped, and an older signed manifest can never
//! roll the remembered one back - see the module header's "WHERE UPDATES COME
//! FROM" for why both halves of that matter.

use std::path::Path;

use serde::{Deserialize, Serialize};
#[cfg(not(target_os = "ios"))]
use tauri::{AppHandle, Runtime};

use super::manifest::{list, valid_url, Services};
use super::{COMPILED_SOURCES, TEST_SOURCE};
use crate::fsx;

#[cfg(not(target_os = "ios"))]
use super::manifest::{build_number, Manifest};
#[cfg(not(target_os = "ios"))]
use super::disk::FILES;
#[cfg(not(target_os = "ios"))]
use crate::lock::lock;

/// `sources.json`: the newest signed word on where updates and services live.
#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub(super) struct Known {
    pub(super) sources: Vec<String>,
    pub(super) services: Services,
    /// The build whose manifest set these, so an older signed manifest - a
    /// stale mirror, or one replayed on purpose - can never roll them back.
    pub(super) build: Option<String>,
}

/// The sources compiled into this APK, most preferred first - or only the one
/// test server a `GLYPH_OTA_BASE` build names instead.
pub(super) fn compiled_sources() -> Vec<String> {
    match TEST_SOURCE {
        Some(test) => vec![test.trim_end_matches('/').to_string()],
        None => list(COMPILED_SOURCES).map(str::to_string).collect(),
    }
}

/// `sources.json`, or nothing remembered yet.
pub(super) fn read_known(root: &Path) -> Known {
    fsx::read_json_or(&root.join("sources.json"), Known::default())
}

/// The remembered sources first, then the compiled ones, without repeats. The
/// compiled list is never dropped: if every new domain dies, the one the APK
/// was built with is still tried.
pub(super) fn effective_sources(known: &Known) -> Vec<String> {
    let mut all: Vec<String> = Vec::new();
    for source in known.sources.iter().cloned().chain(compiled_sources()) {
        if valid_url(&source) && !all.contains(&source) {
            all.push(source);
        }
    }
    all
}

/// The service endpoints the newest verified manifest announced. For other
/// modules: each falls back to its own default for anything absent. Only the
/// model downloads ask today, and iOS downloads no models.
#[cfg(not(target_os = "ios"))]
pub fn services<R: Runtime>(app: &AppHandle<R>) -> Services {
    super::root(app).map(|r| read_known(&r).services).unwrap_or_default()
}

/// Remember a verified manifest's sources and services, unless a newer build already set them.
#[cfg(not(target_os = "ios"))]
pub(super) fn remember(root: &Path, manifest: &Manifest) {
    if manifest.sources.is_empty() {
        return;
    }
    let _files = lock(&FILES);
    let known = read_known(root);
    let newer = known
        .build
        .as_deref()
        .and_then(build_number)
        .is_none_or(|had| build_number(&manifest.build).unwrap_or(0) >= had);
    if !newer || (known.sources == manifest.sources && known.services == manifest.services) {
        return;
    }
    let next = Known { sources: manifest.sources.clone(), services: manifest.services.clone(), build: Some(manifest.build.clone()) };
    if let Ok(bytes) = serde_json::to_vec_pretty(&next) {
        let _ = fsx::write_atomically(&root.join("sources.json"), &bytes);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn remembered_sources_come_first_and_the_compiled_ones_stay() {
        let known = Known { sources: vec!["https://new.example/glyph".into()], ..Known::default() };
        let all = effective_sources(&known);
        assert_eq!(all.first().map(String::as_str), Some("https://new.example/glyph"));
        assert!(all.iter().any(|s| compiled_sources().contains(s)));
    }

    #[cfg(not(target_os = "ios"))]
    #[test]
    fn an_older_manifest_cannot_roll_the_sources_back() {
        let dir = crate::ota::test_support::temp("sources");
        let mut newer = crate::ota::test_support::manifest("20260920000000");
        newer.sources = vec!["https://new.example/glyph".into()];
        remember(&dir, &newer);
        let mut older = crate::ota::test_support::manifest("20260912000000");
        older.sources = vec!["https://old.example/glyph".into()];
        remember(&dir, &older);
        assert_eq!(read_known(&dir).sources, vec!["https://new.example/glyph".to_string()]);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
