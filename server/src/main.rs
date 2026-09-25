//! glyph-api: Ghost.md's service on attack.fm - accounts, end-to-end encrypted sync, shared links, live typing's relay,
//! Notion sign-in and the door to Claude's hosted MCP server - and the voice-note formatting route it began as.
//!
//!   /glyph/api/v1/*          accounts and end-to-end encrypted sync, see `accounts.rs`, `sync.rs`
//!   /glyph/api/v1/shares/*   notes and books shared by their links, see `shares.rs`
//!   /glyph/api/v1/live       live sync's relay, a WebSocket passing sealed edits, see `live.rs`
//!   /glyph/api/notion/*      Notion sign-in, see `notion.rs`
//!   /glyph/api/mcp/*         Claude's hosted MCP server, running beside this one, see `mcp_proxy.rs`
//!   GET  /glyph/api/health   the service is up, and whether the format route's model is, see `health` below
//!   POST /glyph/api/format   annotations for a transcript, which nothing in the app asks for any more, see `format.rs`
//!
//! This file owns startup and the wiring every route shares: the environment, the router the routes are merged into,
//! the CORS layer around all of them and the origins it lets in, and the JSON answer for a route or a method that is
//! not there. `wire.rs` owns the error shape and the base64url check every route uses, `guard.rs` client addresses and
//! rate limits, `identity.rs` the session tokens, and `store.rs` the one SQLite file everything is kept in.
//!
//! THE ENVIRONMENT, every variable the binary reads: GLYPH_API_BIND (where to listen, loopback); GLYPH_API_DATA (where
//! accounts are kept - unset, the service runs without accounts, sync, shares or the relay); GLYPH_API_TOKEN,
//! GLYPH_API_MODEL and OLLAMA_URL (the format route's token and model, `format.rs`); GLYPH_MCP_UPSTREAM
//! (`mcp_proxy.rs`); and NOTION_CLIENT_ID, NOTION_CLIENT_SECRET and NOTION_REDIRECT_URI (`notion.rs`). On the box,
//! glyph-api.service sets GLYPH_API_BIND, OLLAMA_URL and GLYPH_API_DATA, and its env file the token and Notion's client
//! id and secret; GLYPH_API_MODEL, GLYPH_MCP_UPSTREAM and NOTION_REDIRECT_URI are left at their defaults.
//!
//! Caddy routes `/glyph/api/*` here; the prefix is not stripped, so the routes carry it.

mod accounts;
mod format;
mod guard;
mod identity;
mod notion;
mod store;
mod live;
mod mcp_proxy;
mod shares;
mod sync;
mod wire;
#[cfg(test)]
mod test_support;
#[cfg(test)]
mod sync_tests;
#[cfg(test)]
mod shares_tests;
#[cfg(test)]
mod live_tests;

use axum::extract::State;
use axum::http::{header, HeaderValue, Method, StatusCode};
use axum::response::Response;
use axum::routing::get;
use axum::{Json, Router};
use serde_json::json;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tower_http::cors::{AllowOrigin, CorsLayer};
use wire::error;

/// Loopback only. Caddy is the one door; a port open to the internet would be
/// a second one with no TLS and no access log.
const DEFAULT_BIND: &str = "127.0.0.1:8796";

/// The webview origins Glyph actually runs under.
///
/// Verified in tauri-2.11.5 `src/manager/mod.rs` (`tauri_protocol_url`):
/// Android and Windows serve the app from `http://tauri.localhost`, or
/// `https://tauri.localhost` when a window sets `useHttpsScheme` - Glyph's
/// `tauri.conf.json` does not, so the phone is the http one today, and the
/// https one is here so flipping that flag does not silently cut the app off.
/// iOS and macOS use `tauri://localhost`. The web build at attack.fm/glyph/ is
/// same-origin and needs no entry. ghostmarkdown.com is the one website: the reader page for shared notes is served
/// there (scripts/deploy-landing.mjs), and reads a share from this service by its id. The Vite dev server
/// (`vite.config.ts`, port 5250) is not listed: `allowed_origin` lets in a dev server at any local port.
const ORIGINS: &[&str] = &["http://tauri.localhost", "https://tauri.localhost", "tauri://localhost", "https://ghostmarkdown.com"];

/// Whether a page may call this service from the browser: one of `ORIGINS`,
/// or a dev server on this machine at any port (`http://localhost:5255`,
/// `http://127.0.0.1:5251`), since several run side by side and each takes the
/// next free port. A dev page is the person's own; the token it would need
/// lives in its own storage, not in the origin. The CORS layer below asks this
/// for every request, and live.rs asks it for every socket, which CORS does not cover.
fn allowed_origin(origin: &[u8]) -> bool {
    let Ok(origin) = std::str::from_utf8(origin) else { return false };
    if ORIGINS.contains(&origin) {
        return true;
    }
    ["http://localhost:", "http://127.0.0.1:"].iter().any(|host| {
        origin.strip_prefix(host).is_some_and(|port| (1..=5).contains(&port.len()) && port.bytes().all(|b| b.is_ascii_digit()))
    })
}

/// `GET /glyph/api/health`, with no token: the service is up, and whether the format route's model is. The deploy polls
/// it on loopback before it keeps a new binary, and reads it from outside after every ship, so it is the service's
/// answer rather than the format route's, and outlives that route; only the model's two fields are the route's.
async fn health(State(app): State<Arc<format::App>>) -> Json<serde_json::Value> {
    Json(json!({ "ok": true, "model": app.ollama().model(), "ollama": app.ollama().reachable().await }))
}

async fn not_found() -> Response {
    error(StatusCode::NOT_FOUND, "no such route")
}

async fn method_not_allowed() -> Response {
    error(StatusCode::METHOD_NOT_ALLOWED, "method not allowed")
}

/// Every route, merged: health and the format route, Notion, then - when the service has somewhere to keep them -
/// accounts, sync, shares and the relay, then the MCP proxy, all inside one CORS layer.
fn router(app: Arc<format::App>, accounts: Option<Arc<accounts::Accounts>>) -> Router {
    // The layer wraps every route, so a preflight is answered before method
    // routing sees it (an OPTIONS to a POST-only route would otherwise be a
    // 405), and the 401s and 429s carry CORS headers too - without them the
    // webview hides the status and the phone cannot tell "wrong token" from
    // "network down".
    let cors = CorsLayer::new()
        .allow_origin(AllowOrigin::predicate(|origin: &HeaderValue, _| allowed_origin(origin.as_bytes())))
        .allow_methods([Method::GET, Method::POST, Method::PUT, Method::DELETE])
        .allow_headers([header::AUTHORIZATION, header::CONTENT_TYPE])
        // A recording's revision rides in a header, and a page cannot read one it was not told it may.
        .expose_headers([header::HeaderName::from_static("x-glyph-rev")])
        .max_age(Duration::from_secs(600));
    let notion = notion::Notion::from_env();
    let mut routes = Router::new()
        .route("/glyph/api/health", get(health))
        .with_state(app.clone())
        .merge(format::router(app))
        .merge(notion::router(notion));
    // Accounts and sync, when the service has somewhere to keep them.
    if let Some(accounts) = accounts {
        routes = routes
            .merge(accounts::router(accounts.clone()))
            .merge(sync::router(accounts.clone()))
            // Notes and books shared by their links (docs/SHARING.md): the same accounts own them.
            .merge(shares::router(accounts.clone()))
            // Live sync's relay (docs/LIVE.md): the same accounts, a socket instead of requests.
            .merge(live::router(accounts));
    }
    // Claude's hosted MCP server (mcp/hosted.ts, docs/MCP.md), running beside this service, reached through it.
    routes = routes.merge(mcp_proxy::router(mcp_proxy::Upstream::from_env()));
    routes
        .fallback(not_found)
        .method_not_allowed_fallback(method_not_allowed)
        .layer(cors)
}

async fn shutdown() {
    let interrupt = async {
        // A process that cannot hear ctrl-c still hears SIGTERM below.
        let _ = tokio::signal::ctrl_c().await;
    };
    let terminate = async {
        match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            Ok(mut signal) => {
                signal.recv().await;
            }
            Err(_) => std::future::pending::<()>().await,
        }
    };
    tokio::select! {
        () = interrupt => {}
        () = terminate => {}
    }
}

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some("bench") {
        std::process::exit(format::bench::run(&args[2..]).await);
    }

    let token = std::env::var("GLYPH_API_TOKEN").unwrap_or_default();
    // Refuse to start rather than serve with a token anyone could guess. The
    // deploy writes 64 hex characters; 32 is the floor for a hand-set one.
    if token.len() < 32 {
        eprintln!("GLYPH_API_TOKEN is missing or shorter than 32 characters; refusing to start");
        std::process::exit(2);
    }
    let bind = std::env::var("GLYPH_API_BIND").unwrap_or_else(|_| DEFAULT_BIND.into());
    let model = std::env::var("GLYPH_API_MODEL").unwrap_or_else(|_| format::model::MODEL.into());
    let base = std::env::var("OLLAMA_URL").unwrap_or_else(|_| format::DEFAULT_OLLAMA.into());

    let app = format::app_with(token, format::model::Ollama::new(&base, &model));
    // Where accounts and synced notes are kept (docs/SYNC.md). Unset, the service runs as it did, without them.
    let accounts = match std::env::var("GLYPH_API_DATA").ok().filter(|d| !d.is_empty()) {
        Some(dir) => match store::Store::open(std::path::Path::new(&dir)) {
            Ok(store) => {
                eprintln!("glyph-api accounts in {dir}");
                Some(accounts::Accounts::new(Arc::new(store)))
            }
            Err(e) => {
                eprintln!("cannot open the accounts database in {dir}: {e}");
                std::process::exit(1);
            }
        },
        None => None,
    };
    let listener = match tokio::net::TcpListener::bind(&bind).await {
        Ok(listener) => listener,
        Err(e) => {
            eprintln!("cannot bind {bind}: {e}");
            std::process::exit(1);
        }
    };
    eprintln!("glyph-api listening on {bind}, model {model} via {base}");
    let served = axum::serve(listener, router(app, accounts).into_make_service_with_connect_info::<SocketAddr>())
        .with_graceful_shutdown(shutdown())
        .await;
    if let Err(e) = served {
        eprintln!("server error: {e}");
        std::process::exit(1);
    }
}

/// The wiring every route shares, tried through the whole router: CORS, origins, and the JSON fallbacks. The format
/// route stands in for "a route with a token", as it needs no account to reach.
#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{self, request};
    use axum::body::{to_bytes, Body};
    use axum::http::Request;
    use serde_json::json;
    use tower::ServiceExt;

    /// The service without accounts, its Ollama at a port nothing listens on (test_support.rs says why).
    fn service() -> Router {
        test_support::service(None)
    }

    #[tokio::test]
    async fn answers_the_preflight_the_authorization_header_triggers() {
        let preflight = Request::builder()
            .method(Method::OPTIONS)
            .uri("/glyph/api/format")
            .header(header::ORIGIN, "http://tauri.localhost")
            .header(header::ACCESS_CONTROL_REQUEST_METHOD, "POST")
            .header(header::ACCESS_CONTROL_REQUEST_HEADERS, "authorization,content-type")
            .body(Body::empty())
            .unwrap();
        let response = service().oneshot(preflight).await.unwrap();
        assert!(response.status().is_success(), "{}", response.status());
        let headers = response.headers();
        assert_eq!(headers[header::ACCESS_CONTROL_ALLOW_ORIGIN], "http://tauri.localhost");
        let allowed = headers[header::ACCESS_CONTROL_ALLOW_HEADERS].to_str().unwrap().to_ascii_lowercase();
        assert!(allowed.contains("authorization") && allowed.contains("content-type"), "{allowed}");
    }

    #[tokio::test]
    async fn a_foreign_origin_gets_no_cors_grant_and_errors_carry_one_for_ours() {
        let foreign = Request::get("/glyph/api/health").header(header::ORIGIN, "https://evil.example").body(Body::empty()).unwrap();
        let response = service().oneshot(foreign).await.unwrap();
        assert!(response.headers().get(header::ACCESS_CONTROL_ALLOW_ORIGIN).is_none());

        let mut ours = request(Method::POST, "/glyph/api/format", None, Some(json!({ "text": "hi" })));
        ours.headers_mut().insert(header::ORIGIN, HeaderValue::from_static("tauri://localhost"));
        let response = service().oneshot(ours).await.unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
        assert_eq!(response.headers()[header::ACCESS_CONTROL_ALLOW_ORIGIN], "tauri://localhost", "so the phone can READ the 401");
    }

    #[test]
    fn any_local_dev_port_is_an_origin_and_nothing_that_only_looks_like_one() {
        for ok in ["tauri://localhost", "http://tauri.localhost", "https://ghostmarkdown.com", "http://localhost:5250", "http://localhost:5255", "http://127.0.0.1:5251"] {
            assert!(allowed_origin(ok.as_bytes()), "{ok}");
        }
        for no in ["https://evil.example", "http://ghostmarkdown.com", "https://ghostmarkdown.com.evil.example", "http://localhost", "http://localhost:", "http://localhost:5250.evil.example", "http://localhost:123456", "http://localhost.evil.example:5250", "https://localhost:5250", "null"] {
            assert!(!allowed_origin(no.as_bytes()), "{no}");
        }
    }

    #[tokio::test]
    async fn a_dev_server_on_another_port_is_granted_too() {
        let mut request = request(Method::POST, "/glyph/api/format", None, Some(json!({ "text": "hi" })));
        request.headers_mut().insert(header::ORIGIN, HeaderValue::from_static("http://localhost:5255"));
        let response = service().oneshot(request).await.unwrap();
        assert_eq!(response.headers()[header::ACCESS_CONTROL_ALLOW_ORIGIN], "http://localhost:5255");
    }

    #[tokio::test]
    async fn health_needs_no_token_and_reports_ollama_honestly() {
        let response = service().oneshot(Request::get("/glyph/api/health").body(Body::empty()).unwrap()).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        assert_eq!(serde_json::from_slice::<serde_json::Value>(&bytes).unwrap(), json!({ "ok": true, "model": "test-model", "ollama": false }));
    }

    #[tokio::test]
    async fn unknown_routes_and_methods_answer_in_json() {
        let response = service().oneshot(Request::get("/glyph/api/nope").body(Body::empty()).unwrap()).await.unwrap();
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
        let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        assert_eq!(serde_json::from_slice::<serde_json::Value>(&bytes).unwrap(), json!({ "error": "no such route" }));
        let response = service().oneshot(Request::get("/glyph/api/format").body(Body::empty()).unwrap()).await.unwrap();
        assert_eq!(response.status(), StatusCode::METHOD_NOT_ALLOWED);
        let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        assert!(serde_json::from_slice::<serde_json::Value>(&bytes).unwrap()["error"].is_string());
    }
}
