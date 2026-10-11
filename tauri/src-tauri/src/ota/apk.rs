//! The APK: what the sources publish about the newest native build
//! (`apk.json`), and its download into the cache directory the FileProvider
//! exposes, verified against the signed SHA-256 as it streams. A store build
//! (`STORE`) neither offers nor fetches one. Not built for iOS, which has no APK.

use std::io::Write as _;

use serde::Serialize;
use tauri::{AppHandle, Emitter, Runtime};

use super::fetch::{client, fetch_signed, hex, sha256_hex, CONTEXT_APK};
use super::manifest::{safe_relative, valid_url, ApkInfo};
use super::sources::{effective_sources, read_known};
use super::{OtaState, STORE};
use crate::fsx;

/// A store as a person reads it.
fn store_name(store: &str) -> &'static str {
    match store {
        "appstore" => "App Store",
        _ => "Play Store",
    }
}

/// The APK description, unless this is a store build.
pub(super) async fn offered_apk(client: &reqwest::Client, source: &str) -> Option<ApkInfo> {
    if STORE.is_some() {
        return None;
    }
    fetch_signed::<ApkInfo>(client, &format!("{source}/apk.json"), CONTEXT_APK).await.ok()
}

/// `ota://apk-progress`, as the page reads it.
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct ApkProgress {
    received: u64,
    total: u64,
}

/// Downloads the published APK, verified, and answers with its path: the body
/// of `ota_fetch_apk`, which says why Rust does this rather than the page.
pub(super) async fn fetch<R: Runtime>(app: &AppHandle<R>, state: &OtaState) -> Result<String, String> {
    if let Some(store) = STORE {
        return Err(format!("This copy of Ghost.md came from the {}, and updates through it.", store_name(store)));
    }
    let _one_install = state.installing.lock().await;
    let client = client()?;
    let root = super::root(app)?;
    let mut failures = Vec::new();
    let mut found = None;
    for source in effective_sources(&read_known(&root)) {
        match fetch_signed::<ApkInfo>(&client, &format!("{source}/apk.json"), CONTEXT_APK).await {
            Ok(info) => {
                found = Some((source, info));
                break;
            }
            Err(error) => failures.push(error),
        }
    }
    let (base, info) = found.ok_or_else(|| failures.join("; "))?;
    // A relative name is served beside apk.json; an absolute https URL (a
    // release asset on another host) is allowed too. Either way the signed
    // SHA-256 decides, and Android refuses an APK signed by another key.
    let download = if valid_url(&info.url) {
        info.url.clone()
    } else {
        let file = safe_relative(&info.url).filter(|f| !f.contains('/')).ok_or("bad APK name")?;
        format!("{base}/{file}")
    };
    let dir = crate::paths::updates_dir(app)?;
    fsx::make_dir(&dir)?;
    let target = dir.join(format!("glyph-{}.apk", info.version_code));

    if std::fs::read(&target).map(|b| sha256_hex(&b) == info.sha256.to_ascii_lowercase()).unwrap_or(false) {
        // Already here from an earlier tap (the one that stopped for the
        // install permission, usually). Say so, or the page sits on "0 of 44 MB".
        let _ = app.emit("ota://apk-progress", ApkProgress { received: info.bytes, total: info.bytes });
        return Ok(target.to_string_lossy().into_owned());
    }
    // Old downloads are 40 MB each; only the one being fetched stays.
    if let Ok(entries) = std::fs::read_dir(&dir) {
        for entry in entries.flatten() {
            let _ = std::fs::remove_file(entry.path());
        }
    }

    let mut response = client
        .get(&download)
        .send()
        .await
        .and_then(reqwest::Response::error_for_status)
        .map_err(|e| format!("APK download: {e}"))?;
    let part = dir.join("download.part");
    let mut out = std::fs::File::create(&part).map_err(|e| format!("cannot write the APK: {e}"))?;
    let mut hasher = <sha2::Sha256 as sha2::Digest>::new();
    let mut received = 0u64;
    let mut next_report = 0u64;
    while let Some(chunk) = response.chunk().await.map_err(|e| format!("APK download: {e}"))? {
        received += chunk.len() as u64;
        if received > info.bytes {
            let _ = std::fs::remove_file(&part);
            return Err("the server sent more than the published APK size".to_string());
        }
        sha2::Digest::update(&mut hasher, &chunk);
        out.write_all(&chunk).map_err(|e| format!("cannot write the APK: {e}"))?;
        if received >= next_report {
            let _ = app.emit("ota://apk-progress", ApkProgress { received, total: info.bytes });
            next_report = received + 512 * 1024;
        }
    }
    drop(out);
    let digest = hex(&sha2::Digest::finalize(hasher));
    if received != info.bytes || digest != info.sha256.to_ascii_lowercase() {
        let _ = std::fs::remove_file(&part);
        return Err("the APK did not match its published checksum".to_string());
    }
    std::fs::rename(&part, &target).map_err(|e| format!("cannot place the APK: {e}"))?;
    let _ = app.emit("ota://apk-progress", ApkProgress { received, total: info.bytes });
    Ok(target.to_string_lossy().into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_store_is_named_the_way_a_person_knows_it() {
        assert_eq!(store_name("appstore"), "App Store");
        assert_eq!(store_name("play"), "Play Store");
    }
}
