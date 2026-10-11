//! What an update of the app itself must pass before the phone's installer sees it (stage 9I): the signature over
//! `apk.json`, the shape of what it says, and the SHA-256 and size of the file it names. From three files of
//! `../glyph/src-tauri/src/ota` that name `tauri::`, `reqwest` and `ring` and so cannot be included whole:
//! `manifest.rs`, `fetch.rs` and `apk.rs`.
//!
//! THE RULE IS THE TAURI APP'S: TRUST IS A KEY, NOT A DOMAIN. An APK description is parsed only once a trusted
//! key has signed exactly its bytes, and the file it names is handed on only if it is the size and the hash that
//! signed description gives. Whatever served either, over whatever connection, changes nothing.
//!
//! - **`update_read {body, signature, keys, http}`** is `fetch::fetch_signed` after its two requests: `body` is
//!   `apk.json` as it arrived (standard base64 of its bytes, so not one is changed on the way here), `signature`
//!   the text of `apk.json.sig`, `keys` the raw 32-byte Ed25519 keys this build trusts (base64). Answers the
//!   description, or the Tauri app's sentence ("the signature did not verify against any trusted key"). `http`
//!   lets the description name an `http://` address, which only a test build asks (`TEST_SOURCE` there).
//! - **`update_verify {path, sha256, bytes}`** is the end of `apk::fetch`: the file at `path` read through, and
//!   refused ("the APK did not match its published checksum") unless it is `bytes` long and hashes to `sha256`.
//!
//! What differs from the Tauri app:
//!
//! - **The requests are Dart's** (lib/core/updates.dart, over `HttpClient`): this crate has `reqwest` only with
//!   the engines, and an update check must not need them. So the hash is taken of the finished file, where
//!   apk.rs hashed each chunk as it came; the same bytes are hashed either way, and the same two numbers decide.
//! - **Ed25519 by `ed25519-dalek`**, which crypto.rs already has, where fetch.rs used `ring`. The Tauri app's own
//!   vector (a signature made by Node as scripts/ota-sign.mjs makes them) is among the tests below.
//! - **The context is this app's own**, `ghost-flutter-apk\0`, where the Tauri app signs `glyph-apk\0` + bytes: a
//!   description signed for Ghost.md can never be replayed to this app, nor this app's to it, even if one key
//!   came to sign both. tool/release.md says how a release signs it.
//! - **The keys are an argument.** The Tauri app compiles `ota-trusted-keys.txt` in; here the list is the app's
//!   (lib/core/update_keys.dart), which is compiled into the same signed APK.
//! - **`native` is not required** of a description: there is no page here for a native generation to gate.
//!
//! The lines between the marks are manifest.rs's, word for word (kept/mod.rs holds them to it); `sha256_hex` and
//! `hex` are fetch.rs's, held by the test at the foot.

use std::io::Read as _;
use std::path::Path;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::dispatch::read;

/// The signature context of this app's `apk.json`. tool/release.md has it byte for byte.
pub const CONTEXT_APK: &[u8] = b"ghost-flutter-apk\0";

const COMMANDS: &[&str] = &["update_read", "update_verify"];

/// Whether `command` is one of this module's.
pub fn has(command: &str) -> bool {
    COMMANDS.contains(&command)
}

/// The APK a release offers (`ApkInfo`, manifest.rs), with `native` optional: see the header.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ApkInfo {
    pub version: String,
    pub version_code: u64,
    #[serde(default)]
    pub native: u32,
    pub sha256: String,
    pub bytes: u64,
    /// Relative to the APK description's own URL.
    pub url: String,
}

// copied:begin
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
// copied:end

/// `valid_url` of manifest.rs, with the test build's `http://` asked for by the caller where that file read a
/// compile-time variable: https, no whitespace or fragments, no trailing slash, and short.
fn valid_url(url: &str, http: bool) -> bool {
    let secure = url.starts_with("https://") || (http && url.starts_with("http://"));
    secure
        && url.len() <= 512
        && !url.ends_with('/')
        && !url.bytes().any(|b| b.is_ascii_whitespace() || b.is_ascii_control() || matches!(b, b'#' | b'"' | b'\\'))
        && url.split("://").nth(1).is_some_and(|rest| !rest.is_empty())
}

/// Whether any of `keys` (raw 32-byte Ed25519 keys, base64) signed context + bytes: `verify_with` of fetch.rs.
fn verify_with<'a>(keys: impl IntoIterator<Item = &'a str>, context: &[u8], bytes: &[u8], signature: &str) -> bool {
    use base64::Engine;
    use ed25519_dalek::Verifier as _;
    let engine = base64::engine::general_purpose::STANDARD;
    let Ok(signature) = engine.decode(signature.trim()) else {
        return false;
    };
    let Ok(signature) = ed25519_dalek::Signature::from_slice(&signature) else {
        return false;
    };
    let mut message = Vec::with_capacity(context.len() + bytes.len());
    message.extend_from_slice(context);
    message.extend_from_slice(bytes);
    keys.into_iter().any(|key| {
        engine
            .decode(key.trim())
            .ok()
            .and_then(|raw| <[u8; 32]>::try_from(raw).ok())
            .and_then(|raw| ed25519_dalek::VerifyingKey::from_bytes(&raw).ok())
            .is_some_and(|key| key.verify(&message, &signature).is_ok())
    })
}

/// SHA-256 as the manifests write it: lowercase hex.
pub(super) fn sha256_hex(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    hex(&Sha256::digest(bytes))
}

/// A digest as the manifests write it, for one hashed as it streamed in.
pub(super) fn hex(digest: &[u8]) -> String {
    digest.iter().map(|b| format!("{b:02x}")).collect()
}

/// The description in `body`, if one of `keys` signed exactly those bytes and what it says can be acted on.
/// Parsing comes AFTER verifying on purpose (fetch.rs): a JSON parser never sees a byte an attacker chose.
pub fn read_signed(body: &[u8], signature: &str, keys: &[String], http: bool) -> Result<ApkInfo, String> {
    if !verify_with(keys.iter().map(String::as_str), CONTEXT_APK, body, signature) {
        return Err("the signature did not verify against any trusted key".to_string());
    }
    let info = serde_json::from_slice::<ApkInfo>(body).map_err(|e| e.to_string())?;
    if info.sha256.len() != 64 || !info.sha256.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err("bad sha256".to_string());
    }
    // A relative name is served beside apk.json; an absolute https URL (a release asset on another host) is
    // allowed too (apk.rs). Either way the signed SHA-256 decides.
    if !valid_url(&info.url, http) && safe_relative(&info.url).filter(|f| !f.contains('/')).is_none() {
        return Err("bad APK name".to_string());
    }
    Ok(info)
}

/// Whether the file at `path` is the one a signed description names: its size, then its SHA-256.
pub fn verify_file(path: &Path, sha256: &str, bytes: u64) -> Result<(), String> {
    let refused = || "the APK did not match its published checksum".to_string();
    let mut file = std::fs::File::open(path).map_err(|e| format!("cannot read the APK: {e}"))?;
    if file.metadata().map_err(|e| format!("cannot read the APK: {e}"))?.len() != bytes {
        return Err(refused());
    }
    let mut hasher = <sha2::Sha256 as sha2::Digest>::new();
    let mut chunk = vec![0u8; 256 * 1024];
    let mut received = 0u64;
    loop {
        let n = file.read(&mut chunk).map_err(|e| format!("cannot read the APK: {e}"))?;
        if n == 0 {
            break;
        }
        received += n as u64;
        sha2::Digest::update(&mut hasher, &chunk[..n]);
    }
    let digest = hex(&sha2::Digest::finalize(hasher));
    if received != bytes || digest != sha256.to_ascii_lowercase() {
        return Err(refused());
    }
    Ok(())
}

#[derive(Deserialize)]
struct ReadArgs {
    body: String,
    signature: String,
    keys: Vec<String>,
    #[serde(default)]
    http: bool,
}

#[derive(Deserialize)]
struct VerifyArgs {
    path: String,
    sha256: String,
    bytes: u64,
}

/// One of this module's commands. The header says what each takes and answers.
pub fn call(command: &str, args: Value) -> Result<Value, String> {
    match command {
        "update_read" => {
            use base64::Engine;
            let ReadArgs { body, signature, keys, http } = read(command, args)?;
            let body = base64::engine::general_purpose::STANDARD.decode(body.trim()).map_err(|_| "the description was not base64".to_string())?;
            let info = read_signed(&body, &signature, &keys, http)?;
            serde_json::to_value(info).map_err(|e| e.to_string())
        }
        "update_verify" => {
            let VerifyArgs { path, sha256, bytes } = read(command, args)?;
            verify_file(Path::new(&path), &sha256, bytes)?;
            Ok(Value::Null)
        }
        _ => Err(format!("unknown command {command}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::Engine;
    use ed25519_dalek::Signer as _;
    use serde_json::json;

    /// The Tauri app's own contexts (fetch.rs), for its vector below.
    const GLYPH_MANIFEST: &[u8] = b"glyph-ota\0";
    const GLYPH_APK: &[u8] = b"glyph-apk\0";

    fn b64(bytes: &[u8]) -> String {
        base64::engine::general_purpose::STANDARD.encode(bytes)
    }

    /// A key that is nobody's, its public half as the app lists one, and `body` signed as a release signs it.
    fn signed(seed: u8, body: &[u8]) -> (String, String) {
        let key = ed25519_dalek::SigningKey::from_bytes(&[seed; 32]);
        let mut message = CONTEXT_APK.to_vec();
        message.extend_from_slice(body);
        (b64(key.verifying_key().as_bytes()), b64(&key.sign(&message).to_bytes()))
    }

    fn description(url: &str) -> Vec<u8> {
        json!({"version": "0.2.0", "versionCode": 2000, "sha256": sha256_hex(b"an apk"), "bytes": 6, "url": url}).to_string().into_bytes()
    }

    /// fetch.rs's test, with its vector: signed by Node's crypto with a throwaway key, exactly as
    /// scripts/ota-sign.mjs signs. What `ring` accepted there, this accepts, and nothing else.
    #[test]
    fn signatures_from_the_deploy_script_verify_and_nothing_else_does() {
        let key = "EnYQkB2cQwgpjgjkuGdCa0yccOhrQMURHVwZUI2t1yU=";
        let body = br#"{"schema":1}"#;
        let sig = "0X3peDVYhcHRgB0Pzj4tWKv8ZjaZrAFNLQC2VdcO9qHz0xVbfNZEJ1vom+dUzSFdatqpsR3sHnNBSb7Ewt03Aw==";
        assert!(verify_with([key], GLYPH_MANIFEST, body, sig));
        assert!(!verify_with([key], GLYPH_APK, body, sig), "a manifest signature must not pass as an APK one");
        assert!(!verify_with([key], GLYPH_MANIFEST, br#"{"schema":2}"#, sig), "tampered bytes");
        assert!(!verify_with(["+lGP9TU8jcvUCrDjPwD5W33HsJn/Bhxm3gH4TK5CvkM="], GLYPH_MANIFEST, body, sig), "another key");
        assert!(!verify_with([key], GLYPH_MANIFEST, body, "not base64!"));
        assert!(!verify_with([key], CONTEXT_APK, body, sig), "nor does anything signed for Ghost.md pass as this app's");
    }

    /// A vector made outside this crate, by Node as tool/release.md signs: the two halves agree on every byte.
    #[test]
    fn a_release_signed_as_the_document_says_is_read() {
        let body = include_bytes!("../../tests/fixtures/update/apk.json");
        let signature = include_str!("../../tests/fixtures/update/apk.json.sig");
        let trusted = include_str!("../../tests/fixtures/update/public-key.txt").trim().to_string();
        let info = read_signed(body, signature, &[trusted.clone()], false).unwrap();
        assert_eq!((info.version.as_str(), info.version_code, info.bytes, info.url.as_str()), ("0.2.0", 2000, 6, "ghost-flutter.apk"));
        let mut tampered = body.to_vec();
        *tampered.iter_mut().find(|b| **b == b'6').unwrap() = b'7';
        assert!(read_signed(&tampered, signature, &[trusted], false).is_err());
    }

    #[test]
    fn a_description_is_read_only_when_a_trusted_key_signed_exactly_its_bytes() {
        let body = description("ghost-flutter.apk");
        let (key, signature) = signed(7, &body);
        let (other, _) = signed(8, &body);
        let info = read_signed(&body, &signature, &[other.clone(), key.clone()], false).unwrap();
        assert_eq!(info.version, "0.2.0");
        assert_eq!(info.native, 0, "no native generation is asked of a description");
        let refused = "the signature did not verify against any trusted key";
        assert_eq!(read_signed(&body, &signature, &[other], false).unwrap_err(), refused);
        assert_eq!(read_signed(&body, &signature, &[], false).unwrap_err(), refused, "a build that trusts no key reads nothing");
        let mut changed = body.clone();
        changed.push(b' ');
        assert_eq!(read_signed(&changed, &signature, &[key.clone()], false).unwrap_err(), refused, "one byte more");
        // Signed, and not JSON: the parser's own words, never a panic.
        let (key, signature) = signed(7, b"not json");
        assert!(read_signed(b"not json", &signature, &[key], false).is_err());
    }

    #[test]
    fn a_description_names_a_file_beside_it_or_an_https_address_and_a_real_hash() {
        let read = |body: Vec<u8>, http: bool| {
            let (key, signature) = signed(7, &body);
            read_signed(&body, &signature, &[key], http)
        };
        assert!(read(description("ghost-flutter-2000.apk"), false).is_ok());
        assert!(read(description("https://example.com/releases/ghost.apk"), false).is_ok());
        for bad in ["../ghost.apk", "a/ghost.apk", "/ghost.apk", "", "http://example.com/ghost.apk", "file:///sdcard/x.apk", "https://example.com/a b"] {
            assert_eq!(read(description(bad), false).unwrap_err(), "bad APK name", "{bad:?}");
        }
        assert!(read(description("http://10.0.2.2:8000/ghost.apk"), true).is_ok(), "a test build may be served over http");
        let short = json!({"version": "0.2.0", "versionCode": 2000, "sha256": "abc", "bytes": 6, "url": "ghost.apk"}).to_string().into_bytes();
        assert_eq!(read(short, false).unwrap_err(), "bad sha256");
    }

    #[test]
    fn a_file_is_the_update_only_at_its_published_size_and_hash() {
        let dir = std::env::temp_dir().join(format!("ghost-update-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("ghost.apk");
        std::fs::write(&path, b"an apk").unwrap();
        let hash = sha256_hex(b"an apk");
        let refused = "the APK did not match its published checksum";
        assert_eq!(verify_file(&path, &hash, 6), Ok(()));
        assert_eq!(verify_file(&path, &hash.to_ascii_uppercase(), 6), Ok(()), "a hash is a hash in either case");
        assert_eq!(verify_file(&path, &hash, 7).unwrap_err(), refused);
        assert_eq!(verify_file(&path, &sha256_hex(b"an apq"), 6).unwrap_err(), refused);
        std::fs::write(&path, b"an apq").unwrap();
        assert_eq!(verify_file(&path, &hash, 6).unwrap_err(), refused, "one byte changed, the size the same");
        assert!(verify_file(&dir.join("none.apk"), &hash, 6).unwrap_err().starts_with("cannot read the APK"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_commands_take_what_the_app_sends() {
        let body = description("ghost-flutter.apk");
        let (key, signature) = signed(7, &body);
        assert!(has("update_read") && has("update_verify") && !has("update"));
        let info = call("update_read", json!({"body": b64(&body), "signature": signature, "keys": [key]})).unwrap();
        assert_eq!(info["versionCode"], 2000);
        assert_eq!(info["url"], "ghost-flutter.apk");
        assert!(call("update_read", json!({"body": b64(&body), "signature": signature, "keys": []})).is_err());
        assert!(call("update_read", json!({})).unwrap_err().starts_with("invalid args for command `update_read`"));
        assert!(call("update_verify", json!({"path": "/nowhere/ghost.apk", "sha256": "", "bytes": 0})).is_err());
    }

    /// fetch.rs's own, and that the two functions here are still its lines.
    #[test]
    fn a_digest_is_written_the_way_the_manifests_write_it() {
        assert_eq!(sha256_hex(b""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
        assert_eq!(sha256_hex(b"glyph").len(), 64);
        let fetch = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../glyph/src-tauri/src/ota/fetch.rs");
        let fetch = std::fs::read_to_string(&fetch).unwrap();
        for line in ["hex(&Sha256::digest(bytes))", "digest.iter().map(|b| format!(\"{b:02x}\")).collect()"] {
            assert!(fetch.contains(line), "fetch.rs no longer has {line}");
        }
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
    fn a_description_can_only_point_at_https() {
        assert!(valid_url("https://attack.fm/glyph", false));
        assert!(!valid_url("http://attack.fm/glyph", false));
        assert!(!valid_url("https://attack.fm/glyph/", false));
        assert!(!valid_url("https://", false));
        assert!(!valid_url("file:///etc", false));
        assert!(!valid_url("https://a.b/c d", false));
    }
}
