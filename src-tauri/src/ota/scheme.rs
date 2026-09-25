//! The `ota` URI scheme: the claimed bundle's files, served by their real
//! relative paths so a bundle is simply `dist/` (the module header says why
//! that matters), from whichever directory the last claim chose.

use tauri::http::{header, Response, StatusCode};
use tauri::{AppHandle, Manager, Runtime};

use super::manifest::safe_relative;
use super::OtaState;
use crate::lock::lock;

/// The URI scheme the claimed bundle is served under.
pub const SCHEME: &str = "ota";

/// The scheme's URL prefix on this platform. Android and Windows route custom
/// schemes through `http://<scheme>.localhost`; everything else uses the scheme.
pub(super) fn scheme_base() -> String {
    if cfg!(any(target_os = "android", target_os = "windows")) {
        format!("http://{SCHEME}.localhost/")
    } else {
        format!("{SCHEME}://localhost/")
    }
}

fn mime_for(path: &str) -> &'static str {
    match path.rsplit('.').next().unwrap_or("") {
        "js" | "mjs" => "text/javascript",
        "css" => "text/css",
        "woff2" => "font/woff2",
        "woff" => "font/woff",
        "ttf" => "font/ttf",
        "json" => "application/json",
        "svg" => "image/svg+xml",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "webp" => "image/webp",
        "wasm" => "application/wasm",
        "html" => "text/html",
        _ => "application/octet-stream",
    }
}

/// Serves the claimed bundle. Every response carries `Access-Control-Allow-Origin`
/// because the page's origin is the app's, not this scheme's, and module
/// scripts and fonts are fetched in CORS mode: without the header the entry
/// script is refused and the page stays blank. `no-store` because a WebView
/// cache keyed on a path that now holds a different build is a stale frontend.
pub fn serve<R: Runtime>(app: &AppHandle<R>, request: &tauri::http::Request<Vec<u8>>) -> Response<Vec<u8>> {
    answer(request.uri().path(), app.try_state::<OtaState>().as_deref())
}

/// The answer to a request for `path`, given the OTA state (or none, before
/// setup has managed it).
fn answer(path: &str, state: Option<&OtaState>) -> Response<Vec<u8>> {
    let respond = |status: StatusCode, mime: &str, body: Vec<u8>| {
        Response::builder()
            .status(status)
            .header(header::CONTENT_TYPE, mime)
            .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .header(header::CACHE_CONTROL, "no-store")
            .body(body)
            .unwrap_or_else(|_| Response::new(Vec::new()))
    };
    let path = path.trim_start_matches('/');
    let Some(path) = safe_relative(path) else {
        return respond(StatusCode::BAD_REQUEST, "text/plain", b"bad path".to_vec());
    };
    let Some(state) = state else {
        return respond(StatusCode::SERVICE_UNAVAILABLE, "text/plain", Vec::new());
    };
    let Some((_, dir)) = lock(&state.serving).clone() else {
        return respond(StatusCode::NOT_FOUND, "text/plain", b"no bundle claimed".to_vec());
    };
    match std::fs::read(dir.join(path)) {
        Ok(bytes) => respond(StatusCode::OK, mime_for(path), bytes),
        Err(_) => respond(StatusCode::NOT_FOUND, "text/plain", b"not in this bundle".to_vec()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ota::test_support::{bundle, manifest, temp};
    use crate::test_support::header_of;

    #[test]
    fn a_claimed_bundle_is_served_by_its_real_paths_to_a_page_of_another_origin() {
        let root = temp("scheme");
        let dir = bundle(&root, &manifest("20260912221530"));
        let state = OtaState::new();
        *lock(&state.serving) = Some(("20260912221530".into(), dir));
        let served = answer("/assets/index.js", Some(&state));
        assert_eq!(served.status(), StatusCode::OK);
        assert_eq!(served.body(), b"x");
        assert_eq!(header_of(&served, header::CONTENT_TYPE), Some("text/javascript"), "a module script must say it is one");
        assert_eq!(header_of(&served, header::ACCESS_CONTROL_ALLOW_ORIGIN), Some("*"), "or the page's CORS fetch refuses it");
        assert_eq!(header_of(&served, header::CACHE_CONTROL), Some("no-store"));
        assert_eq!(header_of(&answer("/assets/index.css", Some(&state)), header::CONTENT_TYPE), Some("text/css"));
        let missing = answer("/assets/other.js", Some(&state));
        assert_eq!((missing.status(), missing.body().as_slice()), (StatusCode::NOT_FOUND, &b"not in this bundle"[..]));
    }

    #[test]
    fn nothing_is_served_outside_a_claimed_bundle() {
        let state = OtaState::new();
        let unclaimed = answer("/assets/index.js", Some(&state));
        assert_eq!((unclaimed.status(), unclaimed.body().as_slice()), (StatusCode::NOT_FOUND, &b"no bundle claimed"[..]));
        for path in ["/../state.json", "/assets/../../x", "/", "/a%2e%2e/x"] {
            assert_eq!(answer(path, Some(&state)).status(), StatusCode::BAD_REQUEST, "{path}");
        }
        assert_eq!(answer("/assets/index.js", None).status(), StatusCode::SERVICE_UNAVAILABLE, "before setup has run");
    }

    #[test]
    fn the_prefix_is_the_platforms_rule_for_a_custom_scheme() {
        let base = scheme_base();
        assert!(base == "http://ota.localhost/" || base == "ota://localhost/", "{base}");
        assert_eq!(base == "http://ota.localhost/", cfg!(any(target_os = "android", target_os = "windows")));
    }
}
