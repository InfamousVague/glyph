//! The shapes every route puts on the wire, written once: the one error body, the one check a device's base64url has
//! to pass, and the clock tokens and rows are stamped with.
//!
//! These lived in the modules that first needed them - `error` and `now_secs` in accounts.rs, where sync.rs, shares.rs
//! and live.rs borrowed them, and three more copies of `error` in main.rs, notion.rs and mcp_proxy.rs - and the
//! base64url rule was written out eight times with a different length each time. None of it is about accounts, or
//! about any one route, so it lives here, where a route that is not an account's can use it without importing the
//! accounts service to get at a function that returns some JSON.
//!
//! What stays with each route is its LIMIT. A note may be 1.4 MB, a share id 22 to 64 characters, a Notion state 32 to
//! 128: those are each route's own contract with the app, kept as a constant beside the route that enforces it, and
//! passed in here as a range. This module owns the charset and nothing else about a length.

use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde_json::json;
use std::ops::RangeInclusive;

/// A refusal, as every route words one: `{ "error": message }` under `status`.
///
/// The app reads the words - some of them it matches on, most it shows as they are - so a route's message is part of
/// its contract, and this is only the envelope. The test below pins the shape, and each route's tests its words.
pub fn error(status: StatusCode, message: &str) -> Response {
    (status, Json(json!({ "error": message }))).into_response()
}

/// Whether `s` is base64url as a device writes it - letters, digits, `-` and `_`, no padding - and its length in bytes
/// is inside `len`.
///
/// Every id, blob and nonce a device sends is checked with this before it goes anywhere near a path, a query or the
/// database, which is why the charset is the whole alphabet and not "anything printable": a string that passes cannot
/// hold a `/`, a `.`, a `%` or a quote. The service never decodes what it checks here; the bytes are the device's
/// ciphertext or the device's random id, and the shape is all it can know about them.
pub fn base64url(s: &str, len: RangeInclusive<usize>) -> bool {
    len.contains(&s.len()) && s.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

/// Now, in unix seconds: what tokens are issued and checked against, and what rows are stamped with. A clock before
/// 1970 reads as 0 rather than failing a request over it.
pub fn now_secs() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::to_bytes;

    #[tokio::test]
    async fn an_error_is_one_field_of_json_under_its_status() {
        let response = error(StatusCode::CONFLICT, "That handle is taken.");
        assert_eq!(response.status(), StatusCode::CONFLICT);
        assert_eq!(response.headers()["content-type"], "application/json");
        let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        assert_eq!(&bytes[..], br#"{"error":"That handle is taken."}"#);
    }

    #[test]
    fn base64url_is_the_alphabet_and_the_length_together() {
        assert!(base64url("AbC-_09z", 1..=64));
        assert!(base64url("a", 1..=1), "both ends of the range are in it");
        assert!(!base64url("", 1..=64), "empty is never a value");
        assert!(!base64url("ab", 1..=1), "one over");
        assert!(!base64url(&"a".repeat(21), 22..=64), "one under a floor above one");
        for bad in ["a/b", "a.b", "a+b", "a=b", "a b", "a%2F", "é", "../x"] {
            assert!(!base64url(bad, 1..=64), "{bad}");
        }
    }
}
