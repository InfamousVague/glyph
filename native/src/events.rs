//! Events from Rust to the app: what `AppHandle::emit` was to the Tauri app's page.
//!
//! ```rust,ignore
//! crate::events::emit("capture://partial", &partial);          // anything `Serialize`
//! crate::events::emit_json("ai://progress", &already_json);    // JSON text as it stands
//! ```
//!
//! Callable from ANY thread, and it never blocks on the app: the listener (ffi.rs `ghost_set_listener`) is a
//! Dart `NativeCallable.listener`, which posts the call to the worker isolate and returns. What crosses is
//! `{"event": "<name>", "payload": <value>}` as UTF-8, in a buffer allocated here and freed by Dart through
//! `ghost_free` (lib/core/native/ghost_worker.dart), which decodes it and passes it to `GhostCore.events`.
//!
//! - **Names are the web app's** (`capture://partial`, `ai://progress` …), so a screen ported from the page
//!   listens for the name it listened for. `job://end` is this crate's own (work.rs).
//! - **Order**: events from one thread arrive in the order emitted. Across threads there is no order.
//! - **An event with nobody listening is dropped**, as Tauri's was with no page: before the worker registers,
//!   and after it closes. A job's result is therefore never ONLY an event when losing it would lose work; the
//!   write-up keeps its `.progress` file for that.
//! - **An event waits for the command in hand.** The worker isolate is serial (ghost_worker.dart): while it is
//!   inside `ghost_invoke` it reads no events, which is one more reason a long job returns its id at once.

use serde::Serialize;

/// `payload` as JSON under `event`. A payload that cannot be written as JSON is sent as `null`.
pub fn emit(event: &str, payload: &impl Serialize) {
    let payload = serde_json::to_string(payload).unwrap_or_default();
    emit_json(event, &payload);
}

/// `payload_json` (JSON text, trusted to be so; none at all is `null`) under `event`.
pub fn emit_json(event: &str, payload_json: &str) {
    let name = serde_json::to_string(event).unwrap_or_else(|_| "\"\"".to_string());
    let payload = if payload_json.trim().is_empty() { "null" } else { payload_json };
    let said = format!("{{\"event\":{name},\"payload\":{payload}}}");
    #[cfg(test)]
    tests::HEARD.lock().unwrap_or_else(|e| e.into_inner()).push(said.clone());
    crate::ffi::send(said.as_bytes());
}

#[cfg(test)]
pub(crate) mod tests {
    use std::sync::Mutex;
    use std::time::{Duration, Instant};

    use serde_json::Value;

    /// Every event this test process emitted, listener or none: what a Rust test reads, since the listener is
    /// one slot and tests run side by side. Each test looks for its own job's id.
    pub(crate) static HEARD: Mutex<Vec<String>> = Mutex::new(Vec::new());

    /// The events so far whose payload satisfies `mine`, in the order emitted.
    pub(crate) fn heard(mine: impl Fn(&str, &Value) -> bool) -> Vec<(String, Value)> {
        let all = HEARD.lock().unwrap_or_else(|e| e.into_inner()).clone();
        all.iter()
            .map(|said| serde_json::from_str::<Value>(said).expect("an event is JSON"))
            .filter_map(|e| Some((e["event"].as_str()?.to_string(), e["payload"].clone())))
            .filter(|(event, payload)| mine(event, payload))
            .collect()
    }

    /// Waits up to `limit` for an event satisfying `wanted`, and answers its payload.
    pub(crate) fn wait_for(limit: Duration, wanted: impl Fn(&str, &Value) -> bool) -> Option<Value> {
        let until = Instant::now() + limit;
        loop {
            if let Some((_, payload)) = heard(&wanted).into_iter().next() {
                return Some(payload);
            }
            if Instant::now() >= until {
                return None;
            }
            std::thread::sleep(Duration::from_millis(5));
        }
    }

    #[test]
    fn an_event_is_its_name_and_its_payload() {
        super::emit("test://shape", &serde_json::json!({ "mine": "shape-1", "text": "a \"quoted\" line\n" }));
        super::emit_json("test://shape", r#"{"mine":"shape-2","n":[1,2]}"#);
        let mine = heard(|event, payload| event == "test://shape" && payload["mine"].as_str().is_some_and(|m| m.starts_with("shape-")));
        assert_eq!(mine.len(), 2);
        assert_eq!(mine[0].1["text"], "a \"quoted\" line\n");
        assert_eq!(mine[1].1["n"][1], 2);
    }
}
