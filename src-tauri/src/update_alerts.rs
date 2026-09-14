//! The Rust half of update alerts: one JNI entry point a WorkManager job calls
//! with the app closed, answering "what is published?" as JSON.
//!
//! This is the first code in Glyph reached with NO Tauri in the process. The
//! Kotlin worker (`updates/UpdateCheck.kt`) loads `glyph_lib` itself and calls
//! `run` on its own thread, so nothing here may assume an `AppHandle`, a
//! webview, or an async runtime that setup started. `ota::peek` is written for
//! exactly that: it takes the `ota` directory as a path, builds the global
//! runtime lazily with `block_on`, and uses the webpki-roots TLS stack that needs
//! no JVM hook (see the reqwest comment in Cargo.toml).
//!
//! Verification is the whole reason the check is in Rust rather than a Kotlin
//! HTTP call: the answer comes from `ota::peek`, which accepts only manifests a
//! trusted key signed and tries the remembered sources first - so an alert can
//! never be conjured by a hijacked domain, and alerts follow Glyph to a new one.
//!
//! A panic must not unwind into the JVM (undefined behaviour across `extern
//! "system"`), so the body runs under `catch_unwind` and a panic becomes an
//! `error` field like any other failure.

use std::path::PathBuf;

use jni::objects::{JClass, JString};
use jni::sys::jstring;
use jni::JNIEnv;

/// `UpdateCheck.run(otaDir: String): String?` - the published update as JSON
/// (`ota::Peek`), or `{"error": "..."}`. Null only if the JVM could not be
/// handed a string at all.
#[no_mangle]
pub extern "system" fn Java_com_mattssoftware_glyph_updates_UpdateCheck_run<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    ota_dir: JString<'local>,
) -> jstring {
    let dir: Option<String> = env.get_string(&ota_dir).ok().map(Into::into);
    let answer = std::panic::catch_unwind(move || {
        let Some(dir) = dir else {
            return serde_json::json!({ "error": "no directory" }).to_string();
        };
        match crate::ota::peek(&PathBuf::from(dir)) {
            Ok(peek) => serde_json::to_string(&peek).unwrap_or_else(|e| serde_json::json!({ "error": e.to_string() }).to_string()),
            Err(error) => serde_json::json!({ "error": error }).to_string(),
        }
    })
    .unwrap_or_else(|_| serde_json::json!({ "error": "the update check panicked" }).to_string());

    env.new_string(answer).map(|s| s.into_raw()).unwrap_or(std::ptr::null_mut())
}
