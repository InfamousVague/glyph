//! What the service's tests build on: a folder that cleans up after itself, the values a device sends when it signs
//! up, and the service itself, wired as main.rs wires it but with nothing real behind the model.
//!
//! These were written out again in each test file that needed them - a `TempDir` in store.rs, sync_tests.rs and
//! live_tests.rs, the login and recovery-sheet fixtures in all three `*_tests.rs` files, the same `app_with(...)` and
//! `MockConnectInfo` in main.rs and two more. A fixture that drifts between copies is a test that passes for a reason
//! the next one does not share, so they live here, once, and a test file says only what is particular to it.
//!
//! Test-only: main.rs declares it under `#[cfg(test)]`, and nothing here is compiled into the service.

use crate::accounts::{Accounts, RECOVERY_CODES};
use crate::store::Store;
use crate::{app_with, model, router};
use axum::body::{to_bytes, Body};
use axum::extract::connect_info::MockConnectInfo;
use axum::http::{header, HeaderMap, Method, Request, StatusCode};
use axum::Router;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use ed25519_dalek::SigningKey;
use serde_json::{json, Value};
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tower::ServiceExt;

/// The format route's bearer token in a test: 64 hex characters, as the deploy writes one.
pub const TOKEN: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

/// A folder under the system temp directory, removed when the test lets go of it.
pub struct TempDir(PathBuf);

impl TempDir {
    /// A fresh folder, named for the test file that asked (`glyph-<label>-<pid>-<random>`), so a leftover from a run
    /// that was killed says whose it was.
    pub fn new(label: &str) -> Self {
        let path = std::env::temp_dir().join(format!("glyph-{label}-{}-{}", std::process::id(), rand::random::<u64>()));
        std::fs::create_dir_all(&path).unwrap();
        Self(path)
    }

    pub fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        // A folder the system cannot remove is left in the temp directory, which is the system's to sweep; failing
        // a test over its cleanup would hide whatever the test itself found.
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

// --- what a device sends -------------------------------------------------------

/// A login half, as a device derives one: 64 hex characters.
pub fn login(seed: u8) -> String {
    format!("{seed:02x}").repeat(32)
}

/// A wrapped key, as a device writes one: base64url.
pub fn wrapped(label: &str) -> String {
    URL_SAFE_NO_PAD.encode(format!("wrapped:{label}"))
}

/// A whole recovery sheet: eight codes, each a login half and a key wrapped under it.
pub fn sheet() -> Vec<Value> {
    (0..RECOVERY_CODES).map(|i| json!({ "login": login(100 + i as u8), "wrapped": wrapped(&format!("code{i}")) })).collect()
}

/// A device's own signing key, fresh.
pub fn device() -> SigningKey {
    SigningKey::generate(&mut rand::rngs::OsRng)
}

/// `POST v1/signup`'s body for a new account with the password `login(1)` and a recovery sheet, and with `device`'s
/// key when it has one.
pub fn signup_body(handle: &str, device: Option<&SigningKey>) -> Value {
    let mut body = json!({ "handle": handle, "loginSecret": login(1), "wrapped": wrapped("password"), "recovery": sheet() });
    if let Some(device) = device {
        body["devicePublicKey"] = json!(URL_SAFE_NO_PAD.encode(device.verifying_key().to_bytes()));
        body["deviceLabel"] = json!("phone");
    }
    body
}

// --- the service -----------------------------------------------------------------

/// The accounts service over a database in memory, its recordings in `dir`.
pub fn accounts_in(dir: &Path) -> Arc<Accounts> {
    Accounts::new(Arc::new(Store::in_memory(dir.join("recordings"))))
}

/// Every route, as main.rs wires them, with `accounts` or without. The model is an Ollama at a port nothing listens on,
/// so a test that reaches it gets a refused connection in microseconds instead of a real call.
pub fn routes(accounts: Option<Arc<Accounts>>) -> Router {
    router(app_with(TOKEN.into(), model::Ollama::new("http://127.0.0.1:9", "test-model")), accounts)
}

/// `routes` for the in-memory tests, which never open a socket: every request arrives from Caddy's address, as it does
/// on the box.
pub fn service(accounts: Option<Arc<Accounts>>) -> Router {
    routes(accounts).layer(MockConnectInfo(SocketAddr::from(([127, 0, 0, 1], 40000))))
}

/// A request as a device makes one: a bearer token when it has one, and a JSON body when there is one.
pub fn request(method: Method, path: &str, token: Option<&str>, body: Option<Value>) -> Request<Body> {
    let mut request = Request::builder().method(method).uri(path);
    if let Some(token) = token {
        request = request.header(header::AUTHORIZATION, format!("Bearer {token}"));
    }
    match body {
        Some(body) => request.header(header::CONTENT_TYPE, "application/json").body(Body::from(body.to_string())),
        None => request.body(Body::empty()),
    }
    .unwrap()
}

/// The service with accounts, driven in memory, and the folder its recordings go to.
pub struct Harness {
    pub service: Router,
    pub dir: TempDir,
}

impl Harness {
    pub fn new(label: &str) -> Self {
        let dir = TempDir::new(label);
        Harness { service: service(Some(accounts_in(dir.path()))), dir }
    }

    /// One request, answered: its status, its headers and its body's bytes.
    pub async fn send(&self, request: Request<Body>) -> (StatusCode, HeaderMap, Vec<u8>) {
        let response = self.service.clone().oneshot(request).await.unwrap();
        let (status, headers) = (response.status(), response.headers().clone());
        (status, headers, to_bytes(response.into_body(), usize::MAX).await.unwrap().to_vec())
    }

    /// A JSON call, answered with its status and its body as JSON (`null` for a body that is not).
    pub async fn call(&self, method: Method, path: &str, token: Option<&str>, body: Option<Value>) -> (StatusCode, Value) {
        let (status, _, bytes) = self.send(request(method, path, token, body)).await;
        (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
    }

    /// A new account with a password, `device`'s key and a recovery sheet; its token.
    pub async fn signup(&self, handle: &str, device: &SigningKey) -> String {
        let (status, body) = self.call(Method::POST, "/glyph/api/v1/signup", None, Some(signup_body(handle, Some(device)))).await;
        assert_eq!(status, StatusCode::OK, "{body}");
        body["token"].as_str().unwrap().to_string()
    }
}
