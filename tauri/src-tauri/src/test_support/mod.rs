//! What the crate's tests share: a directory of a test's own that goes when
//! the test does (`temp.rs`), and a header read off a custom scheme's answer.
//! Built for tests only.
//!
//! `temp.rs` is a file of its own because tools/host-tests compiles it by path
//! with no Tauri in that crate; what names Tauri's types stays here.

mod temp;

pub use temp::TempDir;

use tauri::http::{header::HeaderName, Response};

/// `name`'s value on `response`, when it is set and is text: how the `img`,
/// `rec` and `ota` scheme tests read what their answers say.
pub fn header_of(response: &Response<Vec<u8>>, name: HeaderName) -> Option<&str> {
    response.headers().get(name).and_then(|value| value.to_str().ok())
}
