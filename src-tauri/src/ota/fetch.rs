//! Everything the OTA system takes from the network, and the one rule it all
//! passes first: a manifest or an APK description is parsed only once a
//! trusted key has signed exactly its bytes (the module header's "TRUST IS A
//! KEY, NOT A DOMAIN"). Not built for iOS, which has no reqwest.

use tauri::http::header;

use super::manifest::{list, validate, Manifest, MANIFEST_FILE};
use super::TRUSTED_KEYS;

/// Signature contexts, so a signature over one kind of file cannot be replayed
/// as another. They must match scripts/ota-sign.mjs byte for byte.
pub(super) const CONTEXT_MANIFEST: &[u8] = b"glyph-ota\0";
pub(super) const CONTEXT_APK: &[u8] = b"glyph-apk\0";

/// The client every OTA request goes through.
pub(super) fn client() -> Result<reqwest::Client, String> {
    // Connect and read timeouts, never a total one: a 43 MB APK over a slow
    // connection is legitimately minutes (the same reasoning as model_files.rs).
    reqwest::Client::builder()
        .connect_timeout(std::time::Duration::from_secs(15))
        .read_timeout(std::time::Duration::from_secs(30))
        .build()
        .map_err(|e| format!("cannot start an HTTP client: {e}"))
}

async fn fetch_bytes(client: &reqwest::Client, url: &str) -> Result<Vec<u8>, String> {
    let response = client
        .get(url)
        .header(header::CACHE_CONTROL.as_str(), "no-cache")
        .send()
        .await
        .and_then(reqwest::Response::error_for_status)
        .map_err(|e| format!("{url}: {e}"))?;
    response.bytes().await.map(|b| b.to_vec()).map_err(|e| format!("{url}: {e}"))
}

/// Whether any of `keys` (raw 32-byte Ed25519 keys, base64) signed context + bytes.
fn verify_with<'a>(keys: impl IntoIterator<Item = &'a str>, context: &[u8], bytes: &[u8], signature: &str) -> bool {
    use base64::Engine;
    use ring::signature::{UnparsedPublicKey, ED25519};
    let engine = base64::engine::general_purpose::STANDARD;
    let Ok(signature) = engine.decode(signature.trim()) else {
        return false;
    };
    let mut message = Vec::with_capacity(context.len() + bytes.len());
    message.extend_from_slice(context);
    message.extend_from_slice(bytes);
    keys.into_iter().any(|key| {
        engine
            .decode(key)
            .is_ok_and(|raw| raw.len() == 32 && UnparsedPublicKey::new(&ED25519, raw).verify(&message, &signature).is_ok())
    })
}

/// Fetch `url` and `url.sig`, and parse the file only if a trusted key signed
/// exactly those bytes. Parsing comes AFTER verifying on purpose: a JSON parser
/// never sees a byte an attacker chose.
pub(super) async fn fetch_signed<T: serde::de::DeserializeOwned>(client: &reqwest::Client, url: &str, context: &[u8]) -> Result<T, String> {
    let body = fetch_bytes(client, url).await?;
    let signature = fetch_bytes(client, &format!("{url}.sig")).await?;
    let signature = String::from_utf8_lossy(&signature);
    if !verify_with(list(TRUSTED_KEYS), context, &body, &signature) {
        return Err(format!("{url}: the signature did not verify against any trusted key"));
    }
    serde_json::from_slice::<T>(&body).map_err(|e| format!("{url}: {e}"))
}

/// The first source, in order, that serves a verified, valid manifest.
pub(super) async fn find_manifest(client: &reqwest::Client, sources: &[String]) -> Result<(String, Manifest), String> {
    let mut failures = Vec::new();
    for source in sources {
        match fetch_signed::<Manifest>(client, &format!("{source}/{MANIFEST_FILE}"), CONTEXT_MANIFEST)
            .await
            .and_then(|m| validate(&m).map(|()| m))
        {
            Ok(manifest) => return Ok((source.clone(), manifest)),
            Err(error) => failures.push(error),
        }
    }
    Err(if failures.is_empty() { "no update sources".to_string() } else { failures.join("; ") })
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ota::manifest::valid_url;
    use crate::ota::COMPILED_SOURCES;

    /// A vector signed by Node's crypto with a throwaway key, exactly as
    /// scripts/ota-sign.mjs signs: the two halves must agree on every byte.
    #[test]
    fn signatures_from_the_deploy_script_verify_and_nothing_else_does() {
        let key = "EnYQkB2cQwgpjgjkuGdCa0yccOhrQMURHVwZUI2t1yU=";
        let body = br#"{"schema":1}"#;
        let sig = "0X3peDVYhcHRgB0Pzj4tWKv8ZjaZrAFNLQC2VdcO9qHz0xVbfNZEJ1vom+dUzSFdatqpsR3sHnNBSb7Ewt03Aw==";
        assert!(verify_with([key], CONTEXT_MANIFEST, body, sig));
        assert!(!verify_with([key], CONTEXT_APK, body, sig), "a manifest signature must not pass as an APK one");
        assert!(!verify_with([key], CONTEXT_MANIFEST, br#"{"schema":2}"#, sig), "tampered bytes");
        assert!(!verify_with(["+lGP9TU8jcvUCrDjPwD5W33HsJn/Bhxm3gH4TK5CvkM="], CONTEXT_MANIFEST, body, sig), "another key");
        assert!(!verify_with([key], CONTEXT_MANIFEST, body, "not base64!"));
    }

    #[test]
    fn the_app_trusts_at_least_one_key_and_one_source() {
        assert!(list(TRUSTED_KEYS).count() >= 1);
        assert!(list(COMPILED_SOURCES).all(valid_url));
        assert!(list(COMPILED_SOURCES).count() >= 1);
    }

    #[test]
    fn a_digest_is_written_the_way_the_manifests_write_it() {
        assert_eq!(sha256_hex(b""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
        assert_eq!(sha256_hex(b"glyph").len(), 64);
    }
}
