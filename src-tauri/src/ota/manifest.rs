//! What an update says about itself, and what makes one acceptable: the shape
//! of `ota.json` and `apk.json`, and the rules every build id, path and URL in
//! them must keep before anything in `ota/` turns one into a directory, a file
//! or a request.
//!
//! Nothing here reads a file or touches the network. A manifest passes the
//! same `validate` wherever it came from: a server, after its signature
//! (`fetch`); a bundle directory on disk (`disk::bundle_manifest`); or the
//! frontend compiled into this binary (`boot::embedded_manifest`).

use serde::{Deserialize, Serialize};

use super::TEST_SOURCE;

/// No manifest may name more than this many sources or mirrors.
const MAX_URLS: usize = 8;

/// The manifest's own name, in `dist/`, on the server, and inside every bundle directory.
pub(super) const MANIFEST_FILE: &str = "ota.json";

/// `ota.json`, as the build writes it.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Manifest {
    pub schema: u32,
    /// UTC `YYYYMMDDHHMMSS`. Digits only, so it is also a safe directory name
    /// and compares as a number.
    pub build: String,
    pub version: String,
    /// The native generation this bundle needs.
    pub native: u32,
    /// The module script, relative to the bundle root.
    pub entry: String,
    pub styles: Vec<String>,
    pub files: Vec<ManifestFile>,
    /// Where to look for updates from now on, most preferred first. Optional,
    /// so manifests from before signing still parse; remembered only from a
    /// manifest whose signature verified.
    #[serde(default)]
    pub sources: Vec<String>,
    /// Other services the app reaches, so they can move with the domain too.
    #[serde(default)]
    pub services: Services,
    /// What changed, in a sentence or two - the text of an update alert.
    #[serde(default)]
    pub notes: Option<String>,
}

/// Service endpoints a signed manifest can move. Every field is optional; a
/// consumer uses what is here and falls back to its own compiled-in default.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Services {
    /// The formatting endpoint. Nothing reads it since the page's annotation
    /// pass went (it was src/app/capture/annotate.ts); it is still accepted,
    /// validated and reported, so a manifest that names one stays valid.
    pub format: Option<String>,
    /// Base URLs the Whisper model files are served under, most preferred first
    /// (src-tauri/src/whisper/model.rs). Hashes stay pinned in the binary.
    pub model_mirrors: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ManifestFile {
    pub path: String,
    pub sha256: String,
    pub bytes: u64,
}

/// The APK the server offers, as `deploy:ota --apk` describes it.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ApkInfo {
    pub version: String,
    pub version_code: u64,
    pub native: u32,
    pub sha256: String,
    pub bytes: u64,
    /// Relative to the APK description's own URL.
    pub url: String,
}

/// A build id is 14 digits and nothing else: it becomes a directory name.
pub(super) fn build_number(build: &str) -> Option<u64> {
    (build.len() == 14 && build.bytes().all(|b| b.is_ascii_digit()))
        .then(|| build.parse().ok())
        .flatten()
}

/// A path inside a bundle: relative, no `..`, and only the characters Vite
/// names files with. Anything else is refused rather than escaped - there is
/// no legitimate file a bundle could need that fails this.
pub(super) fn safe_relative(path: &str) -> Option<&str> {
    let ok = !path.is_empty()
        && !path.starts_with('/')
        && path
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-' | b'/'))
        && path.split('/').all(|part| !part.is_empty() && part != "." && part != "..");
    ok.then_some(path)
}

/// A base URL a manifest may point the app at: https (http only in a test
/// build), no whitespace or fragments, no trailing slash, and short.
pub(super) fn valid_url(url: &str) -> bool {
    let secure = url.starts_with("https://") || (TEST_SOURCE.is_some() && url.starts_with("http://"));
    secure
        && url.len() <= 512
        && !url.ends_with('/')
        && !url.bytes().any(|b| b.is_ascii_whitespace() || b.is_ascii_control() || matches!(b, b'#' | b'"' | b'\\'))
        && url.split("://").nth(1).is_some_and(|rest| !rest.is_empty())
}

/// The non-comment lines of a compiled-in list file (the same parse as ota-sign.mjs).
pub(super) fn list(text: &str) -> impl Iterator<Item = &str> {
    text.lines().map(|line| line.split('#').next().unwrap_or("").trim()).filter(|line| !line.is_empty())
}

pub(super) fn validate(manifest: &Manifest) -> Result<(), String> {
    if manifest.notes.as_ref().is_some_and(|n| n.len() > 2000) {
        return Err("notes longer than 2000 bytes".to_string());
    }
    if manifest.sources.len() > MAX_URLS || manifest.services.model_mirrors.len() > MAX_URLS {
        return Err("too many sources or mirrors".to_string());
    }
    let urls = manifest.sources.iter().chain(&manifest.services.model_mirrors).chain(&manifest.services.format);
    if let Some(bad) = urls.into_iter().find(|u| !valid_url(u)) {
        return Err(format!("unacceptable URL {bad:?}"));
    }
    if manifest.schema != 1 {
        return Err(format!("unknown manifest schema {}", manifest.schema));
    }
    build_number(&manifest.build).ok_or_else(|| format!("bad build id {:?}", manifest.build))?;
    let listed: std::collections::HashSet<&str> = manifest.files.iter().map(|f| f.path.as_str()).collect();
    for file in &manifest.files {
        safe_relative(&file.path).ok_or_else(|| format!("unsafe path {:?}", file.path))?;
        if file.sha256.len() != 64 || !file.sha256.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err(format!("{}: bad sha256", file.path));
        }
    }
    // The loader asks for these by name; a bundle without them boots blank.
    for needed in std::iter::once(&manifest.entry).chain(&manifest.styles) {
        if !listed.contains(needed.as_str()) {
            return Err(format!("the manifest names {needed} but does not ship it"));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ota::test_support::manifest;

    #[test]
    fn a_manifest_can_only_point_at_https() {
        if TEST_SOURCE.is_some() {
            return;
        }
        assert!(valid_url("https://attack.fm/glyph"));
        assert!(!valid_url("http://attack.fm/glyph"));
        assert!(!valid_url("https://attack.fm/glyph/"));
        assert!(!valid_url("https://"));
        assert!(!valid_url("file:///etc"));
        assert!(!valid_url("https://a.b/c d"));
    }

    #[test]
    fn build_ids_are_fourteen_digits() {
        assert_eq!(build_number("20260912221530"), Some(20_260_912_221_530));
        assert_eq!(build_number("2026091222153"), None);
        assert_eq!(build_number("20260912../530"), None);
    }

    #[test]
    fn bundle_paths_cannot_escape() {
        assert!(safe_relative("assets/index-abc.js").is_some());
        assert!(safe_relative("../state.json").is_none());
        assert!(safe_relative("assets/../../x").is_none());
        assert!(safe_relative("/etc/passwd").is_none());
        assert!(safe_relative("assets//x.js").is_none());
        assert!(safe_relative("assets/x%2e.js").is_none());
    }

    #[test]
    fn a_manifest_must_ship_what_the_loader_asks_for() {
        assert!(validate(&manifest("20260912221530")).is_ok());
        let mut missing = manifest("20260912221530");
        missing.files.pop();
        assert!(validate(&missing).is_err());
        let mut escaping = manifest("20260912221530");
        escaping.files[0].path = "../../evil.js".into();
        assert!(validate(&escaping).is_err());
    }
}
