//! Looking for a newer web bundle and installing it: `ota_check`'s work, and
//! `peek`, the same look without the install for the background alert. Not
//! built for iOS, which has no reqwest.
//!
//! An install never runs the bundle. It stages every file, verifies each
//! against the signed manifest, renames the whole directory into place and
//! makes it `active`; the next page load claims it (`boot::claim`). The
//! `serving` slot is left alone here on purpose - see `OtaState`.

use std::path::Path;

use serde::Serialize;
use tauri::{AppHandle, Runtime};

use super::apk::offered_apk;
use super::boot::embedded_manifest;
use super::disk::{bundle_manifest, read_installed, read_stored, record_installed, remove_bundle, write_stored};
use super::fetch::{client, find_manifest, sha256_hex};
use super::manifest::{build_number, Manifest, MANIFEST_FILE};
use super::sources::{effective_sources, read_known, remember};
use super::{CheckResult, OtaState, NATIVE_GENERATION, STAGING};
use crate::fsx;
use crate::lock::lock;

/// Asks the sources for a newer web bundle and installs it, reporting the
/// published APK alongside. The body of `ota_check`; see it for what the page
/// does with the answer.
pub(super) async fn check<R: Runtime>(app: &AppHandle<R>, state: &OtaState) -> Result<CheckResult, String> {
    if STAGING {
        return Ok(CheckResult { web: "current", web_build: None, web_version: None, apk: None, error: None, source: None });
    }
    let client = client()?;
    let root = super::root(app)?;
    let sources = effective_sources(&read_known(&root));
    let (source, manifest) = match find_manifest(&client, &sources).await {
        Ok(found) => found,
        Err(error) => {
            return Ok(CheckResult { web: "offline", web_build: None, web_version: None, apk: None, error: Some(error), source: None });
        }
    };
    remember(&root, &manifest);
    // The APK description is advisory, and comes from the same source as
    // the manifest; its absence or a bad signature is not a failed check.
    let apk = offered_apk(&client, &source).await;
    let result = |web: &'static str| CheckResult {
        web,
        web_build: Some(manifest.build.clone()),
        web_version: Some(manifest.version.clone()),
        apk: apk.clone(),
        error: None,
        source: Some(source.clone()),
    };

    let _one_install = state.installing.lock().await;
    let embedded = embedded_manifest(app, state);
    let stored = {
        let _guard = lock(&state.lock);
        read_stored(&root)
    };
    let offered = build_number(&manifest.build).unwrap_or(0);
    let have = stored
        .active
        .as_deref()
        .and_then(build_number)
        .into_iter()
        .chain(embedded.as_ref().and_then(|m| build_number(&m.build)))
        .max()
        .unwrap_or(0);
    if offered <= have {
        return Ok(result("current"));
    }
    if stored.quarantined.contains(&manifest.build) {
        return Ok(result("quarantined"));
    }
    if manifest.native > NATIVE_GENERATION {
        return Ok(result("needs-native"));
    }

    install_bundle(app, &client, &root, &manifest, stored.active.as_deref(), &source).await?;

    let _guard = lock(&state.lock);
    let mut stored = read_stored(&root);
    if stored.quarantined.contains(&manifest.build) {
        // Quarantined while it downloaded (a same-launch failure report).
        remove_bundle(&root, &manifest.build);
        return Ok(result("quarantined"));
    }
    if stored.active.as_deref() != Some(manifest.build.as_str()) {
        stored.previous = stored.active.take();
    }
    stored.active = Some(manifest.build.clone());
    stored.strikes = 0;
    // Everything but the new bundle, its predecessor, and whatever this
    // process is serving right now goes.
    let serving = lock(&state.serving).as_ref().map(|(b, _)| b.clone());
    let keep: Vec<&str> = [stored.active.as_deref(), stored.previous.as_deref(), serving.as_deref()]
        .into_iter()
        .flatten()
        .collect();
    prune(&root, &keep);
    write_stored(&root, &stored)?;
    record_installed(&root, &manifest.build);
    Ok(result("installed"))
}

/// What the published update looks like, for the background alert check.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Peek {
    pub web_build: String,
    pub web_version: String,
    pub notes: Option<String>,
    pub installed_build: Option<String>,
    pub apk_version: Option<String>,
    pub apk_version_code: Option<u64>,
    pub apk_native: Option<u32>,
}

/// Look at what is published, verified exactly as `ota_check` does - same
/// signatures, same remembered sources - without installing anything. Blocking,
/// and free of `AppHandle`, because its caller is a WorkManager job in a
/// process where Tauri may never have started. `root` is `<app_data_dir>/ota`.
#[cfg_attr(not(target_os = "android"), allow(dead_code))]
pub fn peek(root: &Path) -> Result<Peek, String> {
    fsx::make_dir(root)?;
    tauri::async_runtime::block_on(async {
        let client = client()?;
        let (source, manifest) = find_manifest(&client, &effective_sources(&read_known(root))).await?;
        remember(root, &manifest);
        let apk = offered_apk(&client, &source).await;
        Ok(Peek {
            web_build: manifest.build,
            web_version: manifest.version,
            notes: manifest.notes,
            installed_build: read_installed(root),
            apk_version: apk.as_ref().map(|a| a.version.clone()),
            apk_version_code: apk.as_ref().map(|a| a.version_code),
            apk_native: apk.as_ref().map(|a| a.native),
        })
    })
}

/// Download (or reuse) every file into a staging directory, verify, then rename into place.
///
/// A file is REUSED when the running bundle or the embedded frontend already
/// has those exact bytes. Vite names files by content hash, so a release that
/// only touched the page's code downloads its JS and CSS and nothing else -
/// the fonts are most of `dist/` by size and almost never change.
async fn install_bundle<R: Runtime>(
    app: &AppHandle<R>,
    client: &reqwest::Client,
    root: &Path,
    manifest: &Manifest,
    active: Option<&str>,
    base: &str,
) -> Result<(), String> {
    let staging = root.join(format!(".staging-{}", manifest.build));
    let _ = std::fs::remove_dir_all(&staging);
    let cleanup = scopeguard(&staging);
    let active_dir = active.map(|a| root.join(a));

    for file in &manifest.files {
        let target = staging.join(&file.path);
        if let Some(parent) = target.parent() {
            std::fs::create_dir_all(parent).map_err(|e| format!("cannot stage {}: {e}", file.path))?;
        }
        let local = active_dir
            .as_ref()
            .and_then(|dir| std::fs::read(dir.join(&file.path)).ok())
            .filter(|bytes| sha256_hex(bytes) == file.sha256.to_ascii_lowercase())
            .or_else(|| {
                app.asset_resolver()
                    .get(file.path.clone())
                    .map(|asset| asset.bytes)
                    .filter(|bytes| sha256_hex(bytes) == file.sha256.to_ascii_lowercase())
            });
        let bytes = match local {
            Some(bytes) => bytes,
            None => {
                let url = format!("{base}/{}", file.path);
                let body = client
                    .get(&url)
                    .send()
                    .await
                    .and_then(reqwest::Response::error_for_status)
                    .map_err(|e| format!("{}: {e}", file.path))?
                    .bytes()
                    .await
                    .map_err(|e| format!("{}: {e}", file.path))?;
                if body.len() as u64 != file.bytes || sha256_hex(&body) != file.sha256.to_ascii_lowercase() {
                    return Err(format!("{}: the download did not match the manifest", file.path));
                }
                body.to_vec()
            }
        };
        std::fs::write(&target, bytes).map_err(|e| format!("cannot write {}: {e}", file.path))?;
    }
    let json = serde_json::to_vec_pretty(manifest).map_err(|e| e.to_string())?;
    std::fs::write(staging.join(MANIFEST_FILE), json).map_err(|e| format!("cannot write the manifest: {e}"))?;
    bundle_manifest(&staging).ok_or("the staged bundle is incomplete")?;

    let target = root.join(&manifest.build);
    let _ = std::fs::remove_dir_all(&target);
    std::fs::rename(&staging, &target).map_err(|e| format!("cannot place the bundle: {e}"))?;
    cleanup.disarm();
    Ok(())
}

/// Removes a staging directory on every exit that is not the final rename.
struct StagingGuard<'a> {
    dir: &'a Path,
    armed: std::cell::Cell<bool>,
}

fn scopeguard(dir: &Path) -> StagingGuard<'_> {
    StagingGuard { dir, armed: std::cell::Cell::new(true) }
}

impl StagingGuard<'_> {
    fn disarm(&self) {
        self.armed.set(false);
    }
}

impl Drop for StagingGuard<'_> {
    fn drop(&mut self) {
        if self.armed.get() {
            let _ = std::fs::remove_dir_all(self.dir);
        }
    }
}

/// Removes every downloaded bundle but those in `keep`, and any staging
/// directory an interrupted install left behind.
fn prune(root: &Path, keep: &[&str]) {
    let Ok(entries) = std::fs::read_dir(root) else { return };
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        let stale_build = build_number(&name).is_some() && !keep.contains(&name.as_str());
        if stale_build || name.starts_with(".staging-") {
            let _ = std::fs::remove_dir_all(entry.path());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ota::test_support::temp;

    #[test]
    fn a_prune_keeps_what_it_is_told_to_and_whatever_is_not_a_bundle() {
        let root = temp("prune");
        for name in ["20260910000000", "20260911000000", "20260912000000", ".staging-20260913000000", "not-a-build"] {
            std::fs::create_dir_all(root.join(name)).unwrap();
        }
        std::fs::write(root.join("state.json"), b"{}").unwrap();
        prune(&root, &["20260912000000", "20260911000000"]);
        let mut left: Vec<String> = std::fs::read_dir(&root).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).collect();
        left.sort();
        assert_eq!(left, ["20260911000000", "20260912000000", "not-a-build", "state.json"]);
    }

    #[test]
    fn a_staging_directory_goes_unless_the_install_reached_its_rename() {
        let root = temp("staging");
        let dir = root.join(".staging-20260912000000");
        std::fs::create_dir_all(&dir).unwrap();
        drop(scopeguard(&dir));
        assert!(!dir.exists(), "an install that stopped early leaves nothing staged");
        std::fs::create_dir_all(&dir).unwrap();
        let placed = scopeguard(&dir);
        placed.disarm();
        drop(placed);
        assert!(dir.exists(), "a disarmed guard leaves the directory it no longer owns");
    }
}
