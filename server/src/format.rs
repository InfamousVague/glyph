//! `POST /glyph/api/format`: the service's first job, the server half of voice-note formatting - which the app no
//! longer asks for.
//!
//! Matt holds the side key, talks, and Whisper on the phone transcribes him
//! live while cheap local rules turn the words into markdown. When he paused,
//! the phone sent the plain transcript here, and this answered with
//! ANNOTATIONS - a title, phrases to bold, action items, enumerations, section
//! breaks - each one an exact piece of what he said. The phone applied them.
//! Nothing here returns prose, and nothing here can change a word of the note.
//!
//!   POST /glyph/api/format   { "text" }  ->  annotations, model, elapsedMs
//!   GET  /glyph/api/health                ->  { ok, model, ollama }
//!
//! Since 0.6.0 the phone formats with its spoken cues and its own rules only, and nothing in the app calls the route
//! (docs/DESIGN.md §13). It still runs, behind its token, and the deploy still checks it answers
//! (scripts/deploy-server.mjs), so it is kept whole: this file and the folder beside it, which nothing else in the
//! service depends on. `model.rs` owns the Ollama call, `prompt.rs` what the model is asked, `shape.rs` the verbatim
//! rule, `chunks.rs` how a long note is cut, `breaker.rs` the rest after an overrun, and `bench.rs` measures the same
//! pipeline from a shell on the box. Taking the route out is this module, its line in main.rs's router, the token
//! gate in `main`, and the deploy's two checks.
//!
//! A GUEST ON SOMEBODY ELSE'S BOX. The Ollama this calls is AttackFM's, and
//! AttackFM's enrichment, DJ and discovery loops use it all day - through a
//! runner with ONE slot (see `model.rs`). Everything below that looks
//! conservative - one model call at a time, a short queue, a rate limit, an
//! admission gate, a hard 45-second budget - is there so that a phone can
//! never hold that slot for long, and never at all while AttackFM is using
//! it.
//!
//! THE TOKEN IS A SPEED BUMP, NOT A SECRET. It shipped inside the public APK,
//! where `unzip` and `strings` find it in a minute; the public builds are made
//! without it now (scripts/deploy-ota.mjs empties `VITE_GLYPH_API_TOKEN`). It
//! keeps out a crawler that finds the path and nobody who wants in. The real
//! protection is the shape of the service itself: a per-address rate limit
//! (`guard.rs`) and the breaker, a body cap and ONE concurrent model call here,
//! the admission gate in `model.rs`, and a bind to loopback so Caddy is the
//! only door.

pub mod bench;
mod breaker;
mod chunks;
#[cfg(test)]
mod fake_ollama;
pub mod model;
mod prompt;
mod shape;

use crate::guard;
use crate::wire::error;
use axum::body::{to_bytes, Body};
use axum::extract::{ConnectInfo, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use breaker::Breaker;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::sync::Semaphore;

/// AttackFM's Ollama on the box: `OLLAMA_URL` unless set.
pub const DEFAULT_OLLAMA: &str = "http://127.0.0.1:11434";

/// The contract's ceiling on the transcript itself, in UTF-8 bytes.
const TEXT_LIMIT: usize = 16 * 1024;

/// The ceiling on the raw request body, which is deliberately NOT the same
/// number. A 16 KB transcript is legal, and JSON-encoding it adds a
/// backslash to every newline and quote - so a body cap of exactly 16 KB
/// would answer 413 to a note the contract says is fine. Twice the text plus a
/// kilobyte is the worst a transcript can encode to (every character a newline
/// or a quote); the TEXT is still held to 16 KB after parsing, and 33 KB is
/// still nothing to buffer.
const BODY_LIMIT: usize = 2 * TEXT_LIMIT + 1024;

/// Per client address. A phone pausing every few seconds while dictating
/// sends well under this; a loop or a scraper hits it inside a minute.
const REQUESTS_PER_MINUTE: u32 = 20;

/// How long a request waits for the single model slot before giving up.
///
/// Short, because the phone re-sent at the next pause anyway, and a request
/// that waited half a minute would be annotating a transcript that has
/// already grown past it.
const QUEUE_WAIT: Duration = Duration::from_secs(8);

/// The whole budget for one request, counted from when it ARRIVED - queue
/// wait and every chunk together. The phone gave up at 45 seconds too, and a
/// server whose clock started after the queue could still be working on an
/// answer nobody is waiting for. `bench.rs` holds a run to the same number.
pub const UPSTREAM_TIMEOUT: Duration = Duration::from_secs(45);

/// How long the endpoint stops asking the model after a call that was
/// admitted and still could not finish. See `Breaker` for the numbers.
const BREAKER_COOLDOWN: Duration = Duration::from_secs(600);

/// The route's state: the token, the model, and every limit that keeps a phone off AttackFM's one slot.
pub struct App {
    token: String,
    ollama: model::Ollama,
    limiter: guard::RateLimiter,
    breaker: Mutex<Breaker>,
    /// `UPSTREAM_TIMEOUT` and `model::ADMISSION_WAIT` in production; fields
    /// only so a test can hold the service to milliseconds instead of minutes.
    budget: Duration,
    admission: Duration,
    /// ONE permit, so this service never has two requests in Ollama's queue at
    /// once. Two would take AttackFM's single slot twice in a row.
    slot: Semaphore,
}

/// The route's state with the production budget and admission gate.
pub fn app_with(token: String, ollama: model::Ollama) -> Arc<App> {
    app_bounded(token, ollama, UPSTREAM_TIMEOUT, model::ADMISSION_WAIT)
}

fn app_bounded(token: String, ollama: model::Ollama, budget: Duration, admission: Duration) -> Arc<App> {
    Arc::new(App {
        token,
        ollama,
        limiter: guard::RateLimiter::new(REQUESTS_PER_MINUTE, Instant::now()),
        breaker: Mutex::new(Breaker::new(BREAKER_COOLDOWN)),
        budget,
        admission,
        slot: Semaphore::new(1),
    })
}

/// The route and the service's health, with their state; merged into glyph-api's router.
pub fn router(app: Arc<App>) -> Router {
    Router::new().route("/glyph/api/health", get(health)).route("/glyph/api/format", post(format)).with_state(app)
}

/// Whether an `Authorization` header carries exactly this bearer token.
///
/// Compared in constant time. With the token once in a public APK that is not
/// protecting much, but a comparison that returns at the first wrong byte is
/// a timing oracle for whatever token replaces it, and doing it properly
/// costs nothing.
fn bearer_matches(header: Option<&str>, token: &str) -> bool {
    let Some(presented) = header.and_then(|h| h.strip_prefix("Bearer ")) else {
        return false;
    };
    constant_time_eq(presented.trim().as_bytes(), token.as_bytes())
}

fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

#[derive(Deserialize)]
struct FormatRequest {
    text: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Formatted {
    #[serde(flatten)]
    annotations: shape::Annotations,
    model: String,
    elapsed_ms: u64,
}

/// `GET /glyph/api/health`, with no token: the service is up, and whether its model is. The deploy reads it from
/// outside after every ship.
async fn health(State(app): State<Arc<App>>) -> Json<serde_json::Value> {
    Json(json!({ "ok": true, "model": app.ollama.model(), "ollama": app.ollama.reachable().await }))
}

/// The one route that costs anything.
///
/// The guards run cheapest first, and the rate limit runs BEFORE the token
/// check on purpose: a client guessing tokens is a client making requests,
/// and should run out of them at the same rate as anyone else.
///
/// If the phone gives up - it sends a newer transcript, or Matt locks the
/// screen - Caddy drops the upstream connection, axum drops this future, and
/// with it the in-flight request to Ollama, which stops generating when its
/// client goes away. Dropping IS the cancellation; nothing needs to be told.
async fn format(
    State(app): State<Arc<App>>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    body: Body,
) -> Response {
    let started = Instant::now();
    if !app.limiter.take(guard::client_ip_of(peer.ip(), &headers), started) {
        eprintln!("format 429 rate limited");
        return error(StatusCode::TOO_MANY_REQUESTS, "rate limited: at most 20 requests a minute");
    }

    let authorization = headers.get(header::AUTHORIZATION).and_then(|v| v.to_str().ok());
    if !bearer_matches(authorization, &app.token) {
        eprintln!("format 401");
        return error(StatusCode::UNAUTHORIZED, "missing or wrong bearer token");
    }

    // Any failure to buffer is reported as too large. The other way to fail
    // here is a client that hung up mid-body, and nobody reads that response.
    let Ok(bytes) = to_bytes(body, BODY_LIMIT).await else {
        eprintln!("format 413 body over {BODY_LIMIT} bytes");
        return error(StatusCode::PAYLOAD_TOO_LARGE, "request body is too large");
    };
    let Ok(request) = serde_json::from_slice::<FormatRequest>(&bytes) else {
        eprintln!("format 400 malformed");
        return error(StatusCode::BAD_REQUEST, "expected a JSON body of the form { \"text\": string }");
    };
    if request.text.len() > TEXT_LIMIT {
        eprintln!("format 413 text {} bytes", request.text.len());
        return error(StatusCode::PAYLOAD_TOO_LARGE, "text is over 16 KB");
    }

    let respond = |annotations| {
        let elapsed_ms = started.elapsed().as_millis() as u64;
        Json(Formatted { annotations, model: app.ollama.model().to_string(), elapsed_ms }).into_response()
    };

    // Silence is a legal transcript (the key was held and nothing was said),
    // and it does not need a model to know there is nothing in it.
    if request.text.trim().is_empty() {
        return respond(shape::Annotations::default());
    }

    let resting = app.breaker.lock().map(|b| b.is_open(Instant::now()).then(|| b.remaining(Instant::now()))).unwrap_or(None);
    if let Some(left) = resting {
        eprintln!("format 503 breaker open for another {}s", left.as_secs());
        return error(
            StatusCode::SERVICE_UNAVAILABLE,
            &format!("the model could not finish inside the budget recently; not asking again for {}s", left.as_secs()),
        );
    }

    let Ok(Ok(_permit)) = tokio::time::timeout(QUEUE_WAIT, app.slot.acquire()).await else {
        eprintln!("format 503 busy after {}ms in the queue", QUEUE_WAIT.as_millis());
        return error(StatusCode::SERVICE_UNAVAILABLE, "busy: another note is being formatted");
    };

    match model::annotate(&app.ollama, &request.text, started + app.budget, app.admission).await {
        Ok(outcome) => {
            // Counts and timings only. The transcript is somebody's voice
            // note, and the journal is not the place for it.
            eprintln!(
                "format 200 {}ms bytes={} chunks={}/{} proposed={} dropped={} lists_dropped={} prompt_tokens={} eval_tokens={}{}",
                started.elapsed().as_millis(),
                request.text.len(),
                outcome.completed,
                outcome.chunks,
                outcome.tally.proposed,
                outcome.tally.dropped,
                outcome.tally.lists_dropped,
                outcome.timing.prompt_tokens,
                outcome.timing.eval_tokens,
                if outcome.completed < outcome.chunks { " PARTIAL" } else { "" },
            );
            respond(outcome.annotations)
        }
        Err(failure) => {
            if matches!(failure, model::Failure::TimedOut) {
                if let Ok(mut breaker) = app.breaker.lock() {
                    breaker.overran(Instant::now());
                }
            }
            eprintln!("format 503 {}ms {failure}", started.elapsed().as_millis());
            error(StatusCode::SERVICE_UNAVAILABLE, &failure.to_string())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{self, TOKEN};
    use axum::http::Request;
    use std::sync::atomic::Ordering;
    use tower::ServiceExt;

    /// The service without accounts, its Ollama at a port nothing listens on (test_support.rs says why).
    fn service() -> Router {
        test_support::service(None)
    }

    fn post(body: impl Into<Body>, token: Option<&str>) -> Request<Body> {
        let mut request = Request::post("/glyph/api/format").header(header::CONTENT_TYPE, "application/json");
        if let Some(token) = token {
            request = request.header(header::AUTHORIZATION, format!("Bearer {token}"));
        }
        request.body(body.into()).unwrap()
    }

    async fn json_of(response: Response) -> serde_json::Value {
        let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        serde_json::from_slice(&bytes).unwrap()
    }

    #[test]
    fn only_the_exact_bearer_token_passes() {
        assert!(bearer_matches(Some(&format!("Bearer {TOKEN}")), TOKEN));
        assert!(!bearer_matches(None, TOKEN), "no header");
        assert!(!bearer_matches(Some(TOKEN), TOKEN), "no scheme");
        assert!(!bearer_matches(Some(&format!("Basic {TOKEN}")), TOKEN), "wrong scheme");
        assert!(!bearer_matches(Some(&format!("Bearer {}", &TOKEN[1..])), TOKEN), "one short");
        assert!(!bearer_matches(Some(&format!("Bearer {TOKEN}0")), TOKEN), "one long");
        assert!(!bearer_matches(Some("Bearer "), TOKEN), "empty");
    }

    #[tokio::test]
    async fn refuses_a_missing_or_wrong_token_with_401() {
        let response = service().oneshot(post(r#"{"text":"hi"}"#, None)).await.unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
        assert!(json_of(response).await["error"].is_string(), "errors are {{ error: string }}");

        let response = service().oneshot(post(r#"{"text":"hi"}"#, Some("wrong"))).await.unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn refuses_an_oversized_body_and_an_oversized_text_with_413() {
        let huge = format!(r#"{{"text":"{}"}}"#, "a".repeat(BODY_LIMIT));
        let response = service().oneshot(post(huge, Some(TOKEN))).await.unwrap();
        assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE);

        let over = format!(r#"{{"text":"{}"}}"#, "a".repeat(TEXT_LIMIT + 1));
        let response = service().oneshot(post(over, Some(TOKEN))).await.unwrap();
        assert_eq!(response.status(), StatusCode::PAYLOAD_TOO_LARGE, "the text cap holds inside the envelope room");
    }

    #[tokio::test]
    async fn a_legal_16kb_transcript_full_of_newlines_is_not_a_413() {
        // Every newline and quote doubles in JSON. This is the worst legal note,
        // and the reason the body cap is not the text cap.
        let text = "\"\n".repeat(TEXT_LIMIT / 2);
        let body = serde_json::to_string(&json!({ "text": text })).unwrap();
        assert!(body.len() > 2 * TEXT_LIMIT, "the fixture really does double once encoded");
        let response = service().oneshot(post(body, Some(TOKEN))).await.unwrap();
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE, "it reached the (absent) model");
    }

    #[tokio::test]
    async fn malformed_json_is_400() {
        for body in ["not json", r#"{"words":"hi"}"#, r#"{"text":42}"#] {
            let response = service().oneshot(post(body, Some(TOKEN))).await.unwrap();
            assert_eq!(response.status(), StatusCode::BAD_REQUEST, "{body}");
        }
    }

    #[tokio::test]
    async fn an_unreachable_ollama_is_503() {
        let response = service().oneshot(post(r#"{"text":"call the plumber"}"#, Some(TOKEN))).await.unwrap();
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert!(json_of(response).await["error"].as_str().unwrap().contains("unavailable"));
    }

    #[tokio::test]
    async fn an_admitted_call_that_overruns_rests_the_model_instead_of_retrying_it() {
        let (base, chats) = fake_ollama::admits_then_stalls().await;
        let app = app_bounded(TOKEN.into(), model::Ollama::new(&base, "test-model"), Duration::from_millis(800), Duration::from_millis(400));
        let service = test_support::behind_caddy(router(app));

        let response = service.clone().oneshot(post(r#"{"text":"call the plumber"}"#, Some(TOKEN))).await.unwrap();
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert!(json_of(response).await["error"].as_str().unwrap().contains("timed out"));

        // The breaker's own words, and a chat count that did not move, are what show the second request was answered
        // without Ollama: a stalled slot would have made it wait out QUEUE_WAIT and answer "busy" instead.
        let response = service.clone().oneshot(post(r#"{"text":"call the plumber"}"#, Some(TOKEN))).await.unwrap();
        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        assert!(json_of(response).await["error"].as_str().unwrap().contains("not asking again"));
        assert_eq!(chats.load(Ordering::SeqCst), 1, "the second request never reached the model");
    }

    #[tokio::test]
    async fn silence_is_answered_without_a_model() {
        let response = service().oneshot(post(r#"{"text":"  \n\n "}"#, Some(TOKEN))).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let body = json_of(response).await;
        assert_eq!(body["title"], serde_json::Value::Null);
        assert_eq!(body["emphasis"], json!([]));
        assert_eq!(body["model"], "test-model");
        assert!(body["elapsedMs"].is_u64(), "camelCase on the wire: {body}");
    }

    #[tokio::test]
    async fn the_twenty_first_request_in_a_minute_is_429() {
        let service = service();
        for i in 0..REQUESTS_PER_MINUTE {
            let response = service.clone().oneshot(post(r#"{"text":""}"#, Some(TOKEN))).await.unwrap();
            assert_eq!(response.status(), StatusCode::OK, "request {i}");
        }
        let response = service.clone().oneshot(post(r#"{"text":""}"#, Some(TOKEN))).await.unwrap();
        assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
    }

    #[tokio::test]
    async fn health_needs_no_token_and_reports_ollama_honestly() {
        let response = service().oneshot(Request::get("/glyph/api/health").body(Body::empty()).unwrap()).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(json_of(response).await, json!({ "ok": true, "model": "test-model", "ollama": false }));
    }
}
