//! "Connect Google Calendar" for Ghost.md: the half of Google's OAuth that
//! needs a secret, and nothing else. Notion's sign-in (`notion.rs`) is the
//! same shape, and this is its twin (docs/CALENDAR.md, section 2).
//!
//! A Google web client signs a person in with a code that has to be swapped
//! for tokens using the client's secret, and a secret cannot ship inside an
//! app. So the phone opens `start` in a browser; Google sends the browser back
//! to `callback` with the code; this service swaps it and holds the answer for
//! a few minutes; and the phone collects it from `claim`. The tokens never
//! travel in a URL: `claim` answers only to the phone that started the
//! sign-in, which proves it with a verifier whose SHA-256 it sent to `start`
//! (the PKCE shape: `challenge` is the unpadded base64url of SHA-256 of
//! `verifier`). Nothing is written to disk and nothing about the account is
//! logged. `refresh` swaps a refresh token the same way.
//!
//!   GET  /api/google/start?state&challenge  -> 302 to Google's consent screen
//!   GET  /api/google/callback?code&state     -> a page to go back to Ghost.md
//!   POST /api/google/claim  { state, verifier }  -> tokens | 202 pending | 404
//!   POST /api/google/refresh { refreshToken }    -> tokens
//!
//! Tokens answer as `{ accessToken, refreshToken?, expiresIn, scope }`: a
//! refresh comes back without a refresh token, and the phone keeps the one it
//! has.
//!
//! Configured by GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in the service's
//! root-owned environment file (GOOGLE_REDIRECT_URI too, left at its default
//! on the box); without them every route answers 503 `{ "error": "Google
//! sign-in is not set up yet." }`, and the rest of glyph-api is unaffected.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use axum::extract::{ConnectInfo, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Redirect, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::Deserialize;
use serde_json::{json, Value};
use std::net::SocketAddr;

use crate::guard;
use crate::notion::{challenge_of, page, well_formed};
use crate::wire::error;

const AUTHORIZE: &str = "https://accounts.google.com/o/oauth2/v2/auth";
const TOKEN: &str = "https://oauth2.googleapis.com/token";
const DEFAULT_REDIRECT: &str = "https://ghostmarkdown.com/api/google/callback";
/// Reading and writing events, and listing the account's calendars to choose from: nothing else of the account.
const SCOPES: &str = "https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.calendarlist.readonly";
/// What every route answers while the client ID and secret are missing. The app reads a 503 from `start` as "don't
/// offer it".
const NOT_SET_UP: &str = "Google sign-in is not set up yet.";

/// How long a sign-in can take from `start` to `claim`.
const PENDING_TTL: Duration = Duration::from_secs(10 * 60);
/// Sign-ins in flight at once: a person signs in once, so this only ever
/// matters to something hammering `start`.
const MAX_PENDING: usize = 256;
const REQUESTS_PER_MINUTE: u32 = 30;

pub struct Google {
    client_id: String,
    client_secret: String,
    redirect_uri: String,
    /// Where codes and refresh tokens are swapped: Google's `TOKEN`, or a stand-in in the tests.
    token_url: String,
    http: reqwest::Client,
    pending: Mutex<HashMap<String, Pending>>,
    limiter: guard::RateLimiter,
}

struct Pending {
    challenge: String,
    created: Instant,
    outcome: Option<Result<Value, String>>,
}

impl Google {
    pub fn new(client_id: String, client_secret: String, redirect_uri: String) -> Arc<Self> {
        Self::swapping_at(TOKEN, client_id, client_secret, redirect_uri)
    }

    /// `new`, with codes swapped at `token_url` rather than at Google.
    fn swapping_at(token_url: &str, client_id: String, client_secret: String, redirect_uri: String) -> Arc<Self> {
        Arc::new(Google {
            client_id,
            client_secret,
            redirect_uri,
            token_url: token_url.to_string(),
            http: reqwest::Client::builder().timeout(Duration::from_secs(20)).build().unwrap_or_default(),
            pending: Mutex::new(HashMap::new()),
            limiter: guard::RateLimiter::new(REQUESTS_PER_MINUTE, Instant::now()),
        })
    }

    /// From the environment. Missing client credentials leave sign-in off.
    pub fn from_env() -> Arc<Self> {
        let var = |name: &str| std::env::var(name).unwrap_or_default().trim().to_string();
        let redirect = std::env::var("GOOGLE_REDIRECT_URI").unwrap_or_else(|_| DEFAULT_REDIRECT.into());
        Google::new(var("GOOGLE_CLIENT_ID"), var("GOOGLE_CLIENT_SECRET"), redirect)
    }

    fn configured(&self) -> bool {
        !self.client_id.is_empty() && !self.client_secret.is_empty()
    }

    fn allowed(&self, peer: SocketAddr, headers: &HeaderMap) -> bool {
        self.limiter.take(guard::client_ip_of(peer.ip(), headers), Instant::now())
    }

    fn prune(pending: &mut HashMap<String, Pending>, now: Instant) {
        pending.retain(|_, p| now.duration_since(p.created) < PENDING_TTL);
    }

    /// One swap at the token endpoint. Google takes the client's credentials in the form body
    /// (`client_secret_post`), beside `fields`.
    async fn exchange(&self, fields: &[(&str, &str)]) -> Result<Value, String> {
        let mut form = vec![("client_id", self.client_id.as_str()), ("client_secret", self.client_secret.as_str())];
        form.extend_from_slice(fields);
        let response = self
            .http
            .post(&self.token_url)
            .form(&form)
            .send()
            .await
            .map_err(|_| "Google could not be reached.".to_string())?;
        let status = response.status();
        let answer: Value = response.json().await.map_err(|_| "Google answered with something unreadable.".to_string())?;
        if !status.is_success() {
            let reason = answer.get("error_description").or_else(|| answer.get("error")).and_then(Value::as_str).unwrap_or("refused");
            return Err(format!("Google said no: {reason}"));
        }
        tokens(&answer).ok_or_else(|| "Google answered without a token.".to_string())
    }
}

/// What the phone keeps from Google's answer: the tokens, how long the access token lasts, and what it was granted.
/// The refresh token only when Google sent one, which a refresh does not.
fn tokens(answer: &Value) -> Option<Value> {
    let access = answer.get("access_token").filter(|t| t.as_str().is_some_and(|t| !t.is_empty()))?;
    let mut kept = json!({
        "accessToken": access,
        "expiresIn": answer.get("expires_in"),
        "scope": answer.get("scope"),
    });
    if let Some(refresh) = answer.get("refresh_token").filter(|t| t.is_string()) {
        kept["refreshToken"] = refresh.clone();
    }
    Some(kept)
}

#[derive(Deserialize)]
struct StartQuery {
    state: String,
    challenge: String,
}

async fn start(State(google): State<Arc<Google>>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap, Query(query): Query<StartQuery>) -> Response {
    if !google.allowed(peer, &headers) {
        return page(StatusCode::TOO_MANY_REQUESTS, "Slow down", "Too many sign-ins in a minute. Try again shortly.");
    }
    if !google.configured() {
        return error(StatusCode::SERVICE_UNAVAILABLE, NOT_SET_UP);
    }
    if !well_formed(&query.state) || !well_formed(&query.challenge) {
        return page(StatusCode::BAD_REQUEST, "That link is broken", "Start the sign-in again from Ghost.md.");
    }
    let now = Instant::now();
    {
        let Ok(mut pending) = google.pending.lock() else {
            return page(StatusCode::INTERNAL_SERVER_ERROR, "Something went wrong", "Start the sign-in again from Ghost.md.");
        };
        Google::prune(&mut pending, now);
        if pending.len() >= MAX_PENDING && !pending.contains_key(&query.state) {
            return page(StatusCode::TOO_MANY_REQUESTS, "Busy", "Too many sign-ins at once. Try again in a few minutes.");
        }
        pending.insert(query.state.clone(), Pending { challenge: query.challenge, created: now, outcome: None });
    }
    // `access_type=offline` and `prompt=consent` so a refresh token comes back every time, not only the first.
    let mut url = reqwest::Url::parse(AUTHORIZE).expect("a fixed URL parses");
    url.query_pairs_mut()
        .append_pair("client_id", &google.client_id)
        .append_pair("redirect_uri", &google.redirect_uri)
        .append_pair("response_type", "code")
        .append_pair("scope", SCOPES)
        .append_pair("access_type", "offline")
        .append_pair("prompt", "consent")
        .append_pair("include_granted_scopes", "true")
        .append_pair("state", &query.state);
    Redirect::to(url.as_str()).into_response()
}

#[derive(Deserialize)]
struct CallbackQuery {
    code: Option<String>,
    state: Option<String>,
    error: Option<String>,
}

async fn callback(State(google): State<Arc<Google>>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap, Query(query): Query<CallbackQuery>) -> Response {
    if !google.allowed(peer, &headers) {
        return page(StatusCode::TOO_MANY_REQUESTS, "Slow down", "Too many sign-ins in a minute. Try again shortly.");
    }
    if !google.configured() {
        return error(StatusCode::SERVICE_UNAVAILABLE, NOT_SET_UP);
    }
    let Some(state) = query.state.filter(|s| well_formed(s)) else {
        return page(StatusCode::BAD_REQUEST, "That link is broken", "Start the sign-in again from Ghost.md.");
    };
    // Decided and the lock let go before the network call below: a guard held
    // across an await would make this handler unsendable.
    let known = google
        .pending
        .lock()
        .map(|mut p| {
            Google::prune(&mut p, Instant::now());
            p.get(&state).is_some_and(|p| p.outcome.is_none())
        })
        .unwrap_or(false);
    if !known {
        return page(StatusCode::GONE, "This sign-in has expired", "Start it again from Ghost.md.");
    }

    let outcome = match (query.error, query.code) {
        (Some(_), _) => Err("You cancelled the sign-in.".to_string()),
        (None, Some(code)) if !code.is_empty() => {
            google
                .exchange(&[("grant_type", "authorization_code"), ("code", &code), ("redirect_uri", &google.redirect_uri)])
                .await
        }
        _ => Err("Google didn't send a sign-in code.".to_string()),
    };
    let succeeded = outcome.is_ok();
    let reason = outcome.as_ref().err().cloned();
    if let Ok(mut pending) = google.pending.lock() {
        if let Some(entry) = pending.get_mut(&state) {
            entry.outcome = Some(outcome);
        }
    }
    eprintln!("google callback {}", if succeeded { "ok" } else { "failed" });
    if succeeded {
        page(StatusCode::OK, "Connected", "Ghost.md can use your Google Calendar now. Go back to Ghost.md to choose your calendars.")
    } else {
        page(StatusCode::OK, "Not connected", &reason.unwrap_or_else(|| "Sign-in didn't finish.".into()))
    }
}

#[derive(Deserialize)]
struct ClaimRequest {
    state: String,
    verifier: String,
}

async fn claim(State(google): State<Arc<Google>>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap, Json(request): Json<ClaimRequest>) -> Response {
    // No bearer token, as Notion's claim: only the phone that started this
    // sign-in has the verifier that answers its challenge.
    if !google.allowed(peer, &headers) {
        return error(StatusCode::TOO_MANY_REQUESTS, "rate limited");
    }
    if !google.configured() {
        return error(StatusCode::SERVICE_UNAVAILABLE, NOT_SET_UP);
    }
    let Ok(mut pending) = google.pending.lock() else {
        return error(StatusCode::INTERNAL_SERVER_ERROR, "try again");
    };
    Google::prune(&mut pending, Instant::now());
    let Some(entry) = pending.get(&request.state) else {
        return error(StatusCode::NOT_FOUND, "no sign-in with that state, or it expired");
    };
    // The proof is checked before anything about the sign-in is revealed,
    // even whether it has finished.
    if challenge_of(&request.verifier) != entry.challenge {
        return error(StatusCode::FORBIDDEN, "the verifier does not match");
    }
    match &entry.outcome {
        None => (StatusCode::ACCEPTED, Json(json!({ "pending": true }))).into_response(),
        Some(_) => match pending.remove(&request.state).and_then(|p| p.outcome) {
            Some(Ok(tokens)) => Json(tokens).into_response(),
            Some(Err(reason)) => error(StatusCode::BAD_REQUEST, &reason),
            None => error(StatusCode::INTERNAL_SERVER_ERROR, "try again"),
        },
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RefreshRequest {
    refresh_token: String,
}

async fn refresh(State(google): State<Arc<Google>>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap, Json(request): Json<RefreshRequest>) -> Response {
    // No bearer token, for the same reason as `claim`: a refresh token is itself
    // the secret, and Google refuses one it did not issue to this client.
    if !google.allowed(peer, &headers) {
        return error(StatusCode::TOO_MANY_REQUESTS, "rate limited");
    }
    if !google.configured() {
        return error(StatusCode::SERVICE_UNAVAILABLE, NOT_SET_UP);
    }
    match google.exchange(&[("grant_type", "refresh_token"), ("refresh_token", &request.refresh_token)]).await {
        Ok(tokens) => Json(tokens).into_response(),
        Err(reason) => error(StatusCode::BAD_GATEWAY, &reason),
    }
}

/// The four routes, with their own state; merged into glyph-api's router.
pub fn router(google: Arc<Google>) -> Router {
    Router::new()
        .route("/api/google/start", get(start))
        .route("/api/google/callback", get(callback))
        .route("/api/google/claim", post(claim))
        .route("/api/google/refresh", post(refresh))
        .with_state(google)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::behind_caddy;
    use axum::body::{to_bytes, Body};
    use axum::http::{header, Request};
    use axum::Form;
    use tower::ServiceExt;
    const STATE: &str = "state-0123456789abcdefghijklmnopqrstuv";
    const VERIFIER: &str = "verifier-0123456789abcdefghijklmnopqrstuvwxyz";

    fn service(google: Arc<Google>) -> Router {
        behind_caddy(router(google))
    }

    fn configured() -> Arc<Google> {
        Google::new("client-id.apps.googleusercontent.com".into(), "client-secret".into(), DEFAULT_REDIRECT.into())
    }

    fn unconfigured() -> Arc<Google> {
        Google::new(String::new(), String::new(), DEFAULT_REDIRECT.into())
    }

    fn post_json(uri: &str, body: Value) -> Request<Body> {
        Request::post(uri).header(header::CONTENT_TYPE, "application/json").body(Body::from(body.to_string())).unwrap()
    }

    fn claim_request(verifier: &str) -> Request<Body> {
        post_json("/api/google/claim", json!({ "state": STATE, "verifier": verifier }))
    }

    fn refresh_request(token: &str) -> Request<Body> {
        post_json("/api/google/refresh", json!({ "refreshToken": token }))
    }

    fn get(uri: String) -> Request<Body> {
        Request::get(uri).body(Body::empty()).unwrap()
    }

    fn start_uri(state: &str) -> String {
        format!("/api/google/start?state={state}&challenge={}", challenge_of(VERIFIER))
    }

    async fn body_of(response: Response) -> (StatusCode, String) {
        let status = response.status();
        (status, String::from_utf8(to_bytes(response.into_body(), usize::MAX).await.unwrap().to_vec()).unwrap())
    }

    /// What a stand-in for Google was sent: the form fields of each swap.
    type Swaps = Arc<Mutex<Vec<HashMap<String, String>>>>;

    /// A stand-in for Google's token endpoint on a loopback port: every swap is answered with `status` and `answer`,
    /// and kept, so a test can read what the service sent.
    async fn google_answering(status: StatusCode, answer: Value) -> (String, Swaps) {
        let swaps: Swaps = Arc::new(Mutex::new(Vec::new()));
        let kept = swaps.clone();
        let app = Router::new().route(
            "/token",
            post(move |Form(fields): Form<HashMap<String, String>>| {
                let (kept, answer) = (kept.clone(), answer.clone());
                async move {
                    kept.lock().unwrap().push(fields);
                    (status, Json(answer))
                }
            }),
        );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        (format!("http://{address}/token"), swaps)
    }

    fn swapping_at(token_url: &str) -> Arc<Google> {
        Google::swapping_at(token_url, "client-id.apps.googleusercontent.com".into(), "client-secret".into(), DEFAULT_REDIRECT.into())
    }

    fn fields(pairs: &[(&str, &str)]) -> HashMap<String, String> {
        pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect()
    }

    #[tokio::test]
    async fn every_route_says_so_when_sign_in_is_not_set_up() {
        let not_set_up = (StatusCode::SERVICE_UNAVAILABLE, r#"{"error":"Google sign-in is not set up yet."}"#.to_string());
        let google = unconfigured();
        assert_eq!(body_of(service(google.clone()).oneshot(get(start_uri(STATE))).await.unwrap()).await, not_set_up, "start");
        let callback = get(format!("/api/google/callback?code=abc&state={STATE}"));
        assert_eq!(body_of(service(google.clone()).oneshot(callback).await.unwrap()).await, not_set_up, "callback");
        assert_eq!(body_of(service(google.clone()).oneshot(claim_request(VERIFIER)).await.unwrap()).await, not_set_up, "claim");
        assert_eq!(body_of(service(google.clone()).oneshot(refresh_request("r1")).await.unwrap()).await, not_set_up, "refresh");
        assert!(google.pending.lock().unwrap().is_empty(), "nothing held");

        // One of the two is not enough.
        let half = Google::new("client-id".into(), String::new(), DEFAULT_REDIRECT.into());
        assert_eq!(service(half).oneshot(get(start_uri(STATE))).await.unwrap().status(), StatusCode::SERVICE_UNAVAILABLE);
    }

    #[tokio::test]
    async fn start_sends_the_browser_to_google_s_consent_screen_with_the_state() {
        let response = service(configured()).oneshot(get(start_uri(STATE))).await.unwrap();
        assert!(response.status().is_redirection());
        let location = response.headers().get(header::LOCATION).unwrap().to_str().unwrap();
        assert!(location.starts_with(&format!("{AUTHORIZE}?")), "{location}");
        let url = reqwest::Url::parse(location).unwrap();
        let params: HashMap<String, String> = url.query_pairs().into_owned().collect();
        assert_eq!(
            params,
            fields(&[
                ("client_id", "client-id.apps.googleusercontent.com"),
                ("redirect_uri", "https://ghostmarkdown.com/api/google/callback"),
                ("response_type", "code"),
                ("scope", "https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.calendarlist.readonly"),
                ("access_type", "offline"),
                ("prompt", "consent"),
                ("include_granted_scopes", "true"),
                ("state", STATE),
            ]),
            "every parameter, and nothing else: no challenge, no secret"
        );
        assert!(!location.contains("client-secret"));
    }

    #[tokio::test]
    async fn start_refuses_a_state_or_a_challenge_too_short_to_be_unguessable() {
        let short = service(configured()).oneshot(get(format!("/api/google/start?state=short&challenge={}", challenge_of(VERIFIER)))).await.unwrap();
        assert_eq!(short.status(), StatusCode::BAD_REQUEST);
        let odd = service(configured()).oneshot(get(format!("/api/google/start?state={STATE}&challenge=not%2Fbase64url-0123456789abcdefghijklmnop"))).await.unwrap();
        assert_eq!(odd.status(), StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn claim_waits_for_the_callback_and_answers_only_the_right_verifier() {
        let google = configured();
        service(google.clone()).oneshot(get(start_uri(STATE))).await.unwrap();

        let wrong = service(google.clone()).oneshot(claim_request("someone-else-0123456789abcdefghijklmnop")).await.unwrap();
        assert_eq!(wrong.status(), StatusCode::FORBIDDEN);

        let (status, body) = body_of(service(google.clone()).oneshot(claim_request(VERIFIER)).await.unwrap()).await;
        assert_eq!((status, body), (StatusCode::ACCEPTED, r#"{"pending":true}"#.to_string()));

        // What the callback leaves behind once Google has answered.
        google.pending.lock().unwrap().get_mut(STATE).unwrap().outcome = Some(Ok(json!({ "accessToken": "secret-token", "expiresIn": 3599 })));
        let wrong = service(google.clone()).oneshot(claim_request("someone-else-0123456789abcdefghijklmnop")).await.unwrap();
        assert_eq!(wrong.status(), StatusCode::FORBIDDEN, "a finished sign-in is no easier to take");
        let (status, body) = body_of(service(google.clone()).oneshot(claim_request(VERIFIER)).await.unwrap()).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(serde_json::from_str::<Value>(&body).unwrap()["accessToken"], "secret-token");

        // Once only.
        let again = service(google).oneshot(claim_request(VERIFIER)).await.unwrap();
        assert_eq!(again.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn a_callback_for_an_unknown_sign_in_is_told_it_expired() {
        let response = service(configured()).oneshot(get(format!("/api/google/callback?code=abc&state={STATE}"))).await.unwrap();
        assert_eq!(response.status(), StatusCode::GONE);
    }

    #[tokio::test]
    async fn a_sign_in_is_held_ten_minutes_and_no_longer() {
        let google = configured();
        service(google.clone()).oneshot(get(start_uri(STATE))).await.unwrap();
        let aged = |google: &Arc<Google>, by: Duration| {
            google.pending.lock().unwrap().get_mut(STATE).unwrap().created = Instant::now().checked_sub(by).unwrap();
        };
        aged(&google, PENDING_TTL - Duration::from_secs(5));
        assert_eq!(service(google.clone()).oneshot(claim_request(VERIFIER)).await.unwrap().status(), StatusCode::ACCEPTED, "still waiting at 9:55");

        aged(&google, PENDING_TTL + Duration::from_secs(1));
        let late = service(google.clone()).oneshot(get(format!("/api/google/callback?code=abc&state={STATE}"))).await.unwrap();
        assert_eq!(late.status(), StatusCode::GONE, "a callback after ten minutes is an old link");
        let (status, body) = body_of(service(google.clone()).oneshot(claim_request(VERIFIER)).await.unwrap()).await;
        assert_eq!((status, body), (StatusCode::NOT_FOUND, r#"{"error":"no sign-in with that state, or it expired"}"#.to_string()));
        assert!(google.pending.lock().unwrap().is_empty(), "and it is let go");
    }

    #[tokio::test]
    async fn a_callback_swaps_the_code_and_the_phone_claims_the_tokens_once() {
        let answer = json!({ "access_token": "secret-token", "refresh_token": "r1", "expires_in": 3599, "token_type": "Bearer",
                             "scope": SCOPES, "id_token": "not-kept" });
        let (url, swaps) = google_answering(StatusCode::OK, answer).await;
        let google = swapping_at(&url);
        service(google.clone()).oneshot(get(start_uri(STATE))).await.unwrap();

        let callback = get(format!("/api/google/callback?state={STATE}&code=4%2F0the-code&scope=whatever"));
        let (status, html) = body_of(service(google.clone()).oneshot(callback).await.unwrap()).await;
        assert_eq!(status, StatusCode::OK);
        assert!(html.contains("<h1>Connected</h1>") && html.contains("Ghost.md can use your Google Calendar now."), "{html}");

        let sent = swaps.lock().unwrap().clone();
        assert_eq!(
            sent,
            vec![fields(&[
                ("client_id", "client-id.apps.googleusercontent.com"),
                ("client_secret", "client-secret"),
                ("grant_type", "authorization_code"),
                ("code", "4/0the-code"),
                ("redirect_uri", DEFAULT_REDIRECT),
            ])]
        );

        let (status, tokens) = body_of(service(google.clone()).oneshot(claim_request(VERIFIER)).await.unwrap()).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(
            serde_json::from_str::<Value>(&tokens).unwrap(),
            json!({ "accessToken": "secret-token", "refreshToken": "r1", "expiresIn": 3599, "scope": SCOPES }),
            "the tokens, their life and their scope, and nothing else of Google's answer"
        );
        let again = service(google).oneshot(claim_request(VERIFIER)).await.unwrap();
        assert_eq!(again.status(), StatusCode::NOT_FOUND, "claimed once");
    }

    #[tokio::test]
    async fn a_refused_code_is_told_to_the_page_and_to_the_phone() {
        let (url, _) = google_answering(StatusCode::BAD_REQUEST, json!({ "error": "invalid_grant", "error_description": "Malformed auth code." })).await;
        let google = swapping_at(&url);
        service(google.clone()).oneshot(get(start_uri(STATE))).await.unwrap();
        let (status, html) = body_of(service(google.clone()).oneshot(get(format!("/api/google/callback?code=bad&state={STATE}"))).await.unwrap()).await;
        assert_eq!(status, StatusCode::OK);
        assert!(html.contains("<h1>Not connected</h1>") && html.contains("Google said no: Malformed auth code."), "{html}");
        let (status, body) = body_of(service(google).oneshot(claim_request(VERIFIER)).await.unwrap()).await;
        assert_eq!((status, body), (StatusCode::BAD_REQUEST, r#"{"error":"Google said no: Malformed auth code."}"#.to_string()));
    }

    #[tokio::test]
    async fn a_cancelled_sign_in_is_told_to_the_page_and_to_the_phone() {
        let (url, swaps) = google_answering(StatusCode::OK, json!({})).await;
        let google = swapping_at(&url);
        service(google.clone()).oneshot(get(start_uri(STATE))).await.unwrap();
        let page = service(google.clone()).oneshot(get(format!("/api/google/callback?error=access_denied&state={STATE}"))).await.unwrap();
        let (status, html) = body_of(page).await;
        assert_eq!(status, StatusCode::OK);
        assert!(html.contains("<h1>Not connected</h1>") && html.contains("You cancelled the sign-in."), "{html}");
        assert!(swaps.lock().unwrap().is_empty(), "nothing to swap");
        // A second callback for a sign-in that has its answer is an old link.
        let late = service(google.clone()).oneshot(get(format!("/api/google/callback?code=abc&state={STATE}"))).await.unwrap();
        assert_eq!(late.status(), StatusCode::GONE);
        let (status, body) = body_of(service(google).oneshot(claim_request(VERIFIER)).await.unwrap()).await;
        assert_eq!((status, body), (StatusCode::BAD_REQUEST, r#"{"error":"You cancelled the sign-in."}"#.to_string()));
    }

    #[tokio::test]
    async fn refresh_swaps_a_refresh_token_and_passes_google_s_refusal_on_in_its_own_words() {
        let (url, swaps) = google_answering(StatusCode::OK, json!({ "access_token": "fresh", "expires_in": 3599, "scope": SCOPES, "token_type": "Bearer" })).await;
        let (status, body) = body_of(service(swapping_at(&url)).oneshot(refresh_request("r1")).await.unwrap()).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(
            serde_json::from_str::<Value>(&body).unwrap(),
            json!({ "accessToken": "fresh", "expiresIn": 3599, "scope": SCOPES }),
            "no refresh token in Google's answer, none in ours: the phone keeps the one it has"
        );
        assert_eq!(
            swaps.lock().unwrap()[0],
            fields(&[("client_id", "client-id.apps.googleusercontent.com"), ("client_secret", "client-secret"), ("grant_type", "refresh_token"), ("refresh_token", "r1")])
        );

        let (url, _) = google_answering(StatusCode::BAD_REQUEST, json!({ "error": "invalid_grant", "error_description": "Token has been expired or revoked." })).await;
        let (status, body) = body_of(service(swapping_at(&url)).oneshot(refresh_request("r1")).await.unwrap()).await;
        assert_eq!((status, body), (StatusCode::BAD_GATEWAY, r#"{"error":"Google said no: Token has been expired or revoked."}"#.to_string()));

        let (url, _) = google_answering(StatusCode::OK, json!({ "token_type": "Bearer" })).await;
        let (status, body) = body_of(service(swapping_at(&url)).oneshot(refresh_request("r1")).await.unwrap()).await;
        assert_eq!((status, body), (StatusCode::BAD_GATEWAY, r#"{"error":"Google answered without a token."}"#.to_string()));

        let (status, body) = body_of(service(swapping_at("http://127.0.0.1:9/token")).oneshot(refresh_request("r1")).await.unwrap()).await;
        assert_eq!((status, body), (StatusCode::BAD_GATEWAY, r#"{"error":"Google could not be reached."}"#.to_string()));
    }

    #[tokio::test]
    async fn sign_ins_in_flight_are_capped_and_one_already_started_may_start_again() {
        let google = configured();
        let from = |i: usize, state: &str| {
            let mut start = get(start_uri(state));
            start.headers_mut().insert("x-forwarded-for", format!("10.0.{}.{}", i / 250, i % 250).parse().unwrap());
            start
        };
        let state = |i: usize| format!("state-{i:04}-0123456789abcdefghijklmnopqrstuv");
        for i in 0..MAX_PENDING {
            let response = service(google.clone()).oneshot(from(i, &state(i))).await.unwrap();
            assert!(response.status().is_redirection(), "sign-in {i}");
        }
        let (status, html) = body_of(service(google.clone()).oneshot(from(MAX_PENDING, &state(MAX_PENDING))).await.unwrap()).await;
        assert_eq!(status, StatusCode::TOO_MANY_REQUESTS);
        assert!(html.contains("Too many sign-ins at once."), "{html}");
        let again = service(google).oneshot(from(MAX_PENDING + 1, &state(0))).await.unwrap();
        assert!(again.status().is_redirection(), "the same sign-in, started again, takes no new place");
    }

    #[tokio::test]
    async fn one_address_starting_sign_ins_is_slowed_down() {
        let google = configured();
        let mut refused = None;
        for i in 0..REQUESTS_PER_MINUTE as usize + 20 {
            let response = service(google.clone()).oneshot(get(start_uri(&format!("state-{i:04}-0123456789abcdefghijklmnopqrstuv")))).await.unwrap();
            if response.status() == StatusCode::TOO_MANY_REQUESTS {
                refused = Some((i, body_of(response).await.1));
                break;
            }
        }
        let (at, html) = refused.expect("a burst from one address meets the limit");
        assert!(at >= REQUESTS_PER_MINUTE as usize, "the first {REQUESTS_PER_MINUTE} are let through, refused at {at}");
        assert!(html.contains("<h1>Slow down</h1>"), "{html}");
    }
}
