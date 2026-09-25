//! Stand-ins for AttackFM's Ollama, for the format route's tests: one that answers what a test tells it to, and one
//! that admits a chat and never finishes it.
//!
//! Test-only: format.rs declares it under `#[cfg(test)]`. The route's tests, the conversation's (`model.rs`) and the
//! benchmark's (`bench.rs`) all speak to one of these rather than to a model, so none of them needs Ollama on the
//! machine, and each one's copy of a fake no longer drifts from the others'.

use axum::routing::post;
use axum::Router;
use serde_json::{json, Value};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

/// A stand-in Ollama on an ephemeral port: `/api/show` reports whether the
/// model thinks, and `/api/chat` answers after `delay` with `reply` lines.
/// Every chat body it receives is kept, so a test can read what was sent.
pub async fn fake_ollama(thinking: bool, delay: Duration, reply: String) -> (String, Arc<Mutex<Vec<Value>>>) {
    let seen = Arc::new(Mutex::new(Vec::new()));
    let log = seen.clone();
    let app = Router::new()
        .route(
            "/api/show",
            post(move || async move {
                axum::Json(json!({ "capabilities": if thinking { json!(["completion", "thinking"]) } else { json!(["completion"]) } }))
            }),
        )
        .route(
            "/api/chat",
            post(move |axum::Json(body): axum::Json<Value>| {
                let reply = reply.clone();
                let log = log.clone();
                async move {
                    log.lock().unwrap().push(body);
                    tokio::time::sleep(delay).await;
                    reply
                }
            }),
        );
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    (format!("http://{address}"), seen)
}

/// An NDJSON stream the way Ollama writes one: content in pieces, then a
/// final line carrying the counts.
pub fn stream_of(content: &str, done_reason: &str) -> String {
    let (head, tail) = content.split_at(content.len() / 2);
    [
        json!({ "message": { "content": head }, "done": false }),
        json!({ "message": { "content": tail }, "done": false }),
        json!({ "message": { "content": "" }, "done": true, "done_reason": done_reason,
                "prompt_eval_count": 640, "prompt_eval_duration": 2_000_000_000u64,
                "eval_count": 90, "eval_duration": 22_000_000_000u64, "load_duration": 1_000_000u64 }),
    ]
    .iter()
    .map(|line| format!("{line}\n"))
    .collect()
}

/// An Ollama that ADMITS a chat - headers and a first line straight away -
/// and then never finishes it, which is what a CPU generating four tokens
/// a second looks like from inside a 45-second budget. Speaks raw HTTP/1.1
/// because the point is a stream that stalls mid-body. Counts chats.
pub async fn admits_then_stalls() -> (String, Arc<AtomicUsize>) {
    let chats = Arc::new(AtomicUsize::new(0));
    let counter = chats.clone();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    tokio::spawn(async move {
        loop {
            let Ok((mut socket, _)) = listener.accept().await else { return };
            let counter = counter.clone();
            tokio::spawn(async move {
                let mut pending = Vec::new();
                loop {
                    let mut buf = [0u8; 4096];
                    let Ok(n) = socket.read(&mut buf).await else { return };
                    if n == 0 {
                        return;
                    }
                    pending.extend_from_slice(&buf[..n]);
                    let Some(end) = pending.windows(4).position(|w| w == b"\r\n\r\n") else { continue };
                    let head = String::from_utf8_lossy(&pending[..end]).to_string();
                    let length: usize = head
                        .lines()
                        .find_map(|l| l.to_ascii_lowercase().strip_prefix("content-length:").map(|v| v.trim().parse().unwrap_or(0)))
                        .unwrap_or(0);
                    if pending.len() < end + 4 + length {
                        continue;
                    }
                    pending.drain(..end + 4 + length);
                    if head.starts_with("POST /api/show") {
                        let body = r#"{"capabilities":["completion"]}"#;
                        let reply = format!("HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\n\r\n{body}", body.len());
                        let _ = socket.write_all(reply.as_bytes()).await;
                    } else {
                        counter.fetch_add(1, Ordering::SeqCst);
                        let line = "{\"message\":{\"content\":\"{\"},\"done\":false}\n";
                        let reply = format!(
                            "HTTP/1.1 200 OK\r\ncontent-type: application/x-ndjson\r\ntransfer-encoding: chunked\r\n\r\n{:x}\r\n{line}\r\n",
                            line.len()
                        );
                        let _ = socket.write_all(reply.as_bytes()).await;
                        tokio::time::sleep(Duration::from_secs(60)).await;
                        return;
                    }
                }
            });
        }
    });
    (format!("http://{address}"), chats)
}
