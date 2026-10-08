//! The C functions Dart calls (lib/core/native/ghost_worker.dart): what Tauri's IPC was to the web page.
//!
//! ```c
//! uint8_t *ghost_alloc(size_t len);
//! uint8_t *ghost_invoke(const uint8_t *cmd, size_t cmd_len, const uint8_t *args_json, size_t args_len, size_t *out_len);
//! void     ghost_free(uint8_t *ptr, size_t len);
//! void     ghost_set_listener(void (*listener)(const uint8_t *json, size_t len));
//! ```
//!
//! - **`ghost_invoke`** takes a command's name and its arguments as UTF-8 JSON (no bytes at all for none), and
//!   answers UTF-8 JSON of its own: `{"ok": <value>}` or `{"err": "<sentence>"}`, `*out_len` bytes of it, never
//!   null. The caller hands the answer back to `ghost_free` with that length.
//! - **A panic never crosses.** Unwinding into Dart is undefined behaviour, so the whole call runs under
//!   `catch_unwind` and a panic is an `err` like any other. The library's lock recovers from one (`lock.rs`),
//!   so the next command is answered.
//! - **`ghost_alloc`** is how Dart gets memory for what it sends, so the app needs no `package:ffi` and no
//!   `malloc` looked up by name: every buffer on either side of the boundary is this crate's, 8-aligned, and
//!   goes back through `ghost_free`.
//! - **`ghost_set_listener`** keeps a function for events from Rust to the app. Nothing calls it yet: the
//!   library emits none (docs/STAGE3.md), and the first to will be a meeting's write-up.
//!
//! Every function may be called from any thread; the Dart side calls from one worker isolate.

use std::alloc::Layout;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::Mutex;

use serde_json::{json, Value};

/// How every buffer that crosses is aligned: enough for the `size_t` Dart reads the answer's length from.
const ALIGN: usize = 8;

fn layout(len: usize) -> Option<Layout> {
    Layout::from_size_align(len.max(1), ALIGN).ok()
}

/// `len` bytes for the caller to fill, or null when there is no memory. Freed with `ghost_free(ptr, len)`.
#[no_mangle]
pub extern "C" fn ghost_alloc(len: usize) -> *mut u8 {
    match layout(len) {
        // SAFETY: the layout's size is never zero.
        Some(layout) => unsafe { std::alloc::alloc(layout) },
        None => std::ptr::null_mut(),
    }
}

/// Gives back what `ghost_alloc` or `ghost_invoke` handed out. `len` is the length it was handed out with.
///
/// # Safety
/// `ptr` must be null, or have come from `ghost_alloc(len)` or from `ghost_invoke` with `*out_len == len`, and
/// not have been freed since.
#[no_mangle]
pub unsafe extern "C" fn ghost_free(ptr: *mut u8, len: usize) {
    if ptr.is_null() {
        return;
    }
    if let Some(layout) = layout(len) {
        std::alloc::dealloc(ptr, layout);
    }
}

/// `bytes` in a buffer of this crate's, its length written to `out_len`.
unsafe fn hand_over(bytes: &[u8], out_len: *mut usize) -> *mut u8 {
    let ptr = ghost_alloc(bytes.len());
    if ptr.is_null() {
        std::alloc::handle_alloc_error(layout(bytes.len()).unwrap_or(Layout::new::<u64>()));
    }
    std::ptr::copy_nonoverlapping(bytes.as_ptr(), ptr, bytes.len());
    if !out_len.is_null() {
        *out_len = bytes.len();
    }
    ptr
}

/// What a panic said, for the `err` it becomes.
fn panic_said(payload: Box<dyn std::any::Any + Send>) -> String {
    let said = payload.downcast_ref::<&str>().map(|s| s.to_string()).or_else(|| payload.downcast_ref::<String>().cloned());
    match said {
        Some(said) => format!("Ghost.md's core stopped in the middle of that: {said}"),
        None => "Ghost.md's core stopped in the middle of that.".to_string(),
    }
}

/// One command, answered as the JSON text that crosses. Safe Rust: the pointers are `ghost_invoke`'s business.
pub fn answer(command: &[u8], args: &[u8]) -> String {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<Value, String> {
        let command = std::str::from_utf8(command).map_err(|_| "a command's name must be UTF-8".to_string())?;
        let args: Value = if args.is_empty() {
            Value::Null
        } else {
            serde_json::from_slice(args).map_err(|e| format!("the arguments of {command} are not JSON: {e}"))?
        };
        crate::dispatch::invoke(command, args)
    }));
    let said = match result {
        Ok(Ok(value)) => json!({ "ok": value }),
        Ok(Err(sentence)) => json!({ "err": sentence }),
        Err(payload) => json!({ "err": panic_said(payload) }),
    };
    said.to_string()
}

/// Runs one command. See the module's header.
///
/// # Safety
/// `cmd` must point at `cmd_len` readable bytes and `args_json` at `args_len` (either may be null when its
/// length is 0), and `out_len` must be null or point at a writable `size_t`.
#[no_mangle]
pub unsafe extern "C" fn ghost_invoke(cmd: *const u8, cmd_len: usize, args_json: *const u8, args_len: usize, out_len: *mut usize) -> *mut u8 {
    let slice = |ptr: *const u8, len: usize| -> &[u8] {
        if ptr.is_null() || len == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(ptr, len)
        }
    };
    let said = answer(slice(cmd, cmd_len), slice(args_json, args_len));
    hand_over(said.as_bytes(), out_len)
}

/// A function of the app's for events from Rust: UTF-8 JSON, borrowed for the call.
pub type Listener = extern "C" fn(json: *const u8, len: usize);

static LISTENER: Mutex<Option<Listener>> = Mutex::new(None);

/// Keeps `listener` (null forgets it). Stored, and not yet called by anything.
#[no_mangle]
pub extern "C" fn ghost_set_listener(listener: Option<Listener>) {
    *crate::lock::lock(&LISTENER) = listener;
}

/// The listener kept, for the first thing that has an event to send.
pub fn listener() -> Option<Listener> {
    *crate::lock::lock(&LISTENER)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A command through the C functions themselves, its answer parsed and its buffers given back.
    fn through_c(command: &str, args: &str) -> Value {
        unsafe {
            let cmd = ghost_alloc(command.len());
            std::ptr::copy_nonoverlapping(command.as_ptr(), cmd, command.len());
            let sent = ghost_alloc(args.len());
            std::ptr::copy_nonoverlapping(args.as_ptr(), sent, args.len());
            let mut len = 0usize;
            let out = ghost_invoke(cmd, command.len(), sent, args.len(), &mut len);
            assert!(!out.is_null() && out as usize % ALIGN == 0);
            let said = serde_json::from_slice(std::slice::from_raw_parts(out, len)).unwrap();
            ghost_free(out, len);
            ghost_free(cmd, command.len());
            ghost_free(sent, args.len());
            said
        }
    }

    #[test]
    fn an_answer_is_ok_or_err_and_never_a_panic() {
        let id = through_c("new_id", "");
        assert!(id["ok"].as_str().is_some_and(|id| id.len() == 36), "{id}");
        assert_eq!(through_c("new_id", "{not json")["err"].as_str().map(|e| e.starts_with("the arguments of new_id are not JSON:")), Some(true));
        assert_eq!(through_c("nothing_of_the_kind", "{}")["err"].as_str().map(|e| e.contains("nothing_of_the_kind")), Some(true));
        assert_eq!(answer(&[0xff, 0xfe], b""), r#"{"err":"a command's name must be UTF-8"}"#);
        // Null pointers with no length are no bytes, not a crash.
        let mut len = 0usize;
        let out = unsafe { ghost_invoke(std::ptr::null(), 0, std::ptr::null(), 0, &mut len) };
        assert!(len > 0);
        unsafe { ghost_free(out, len) };
        unsafe { ghost_free(std::ptr::null_mut(), 0) };
    }

    #[test]
    fn a_panic_is_an_err_with_what_it_said() {
        let caught = catch_unwind(|| panic!("the index is gone")).unwrap_err();
        assert_eq!(panic_said(caught), "Ghost.md's core stopped in the middle of that: the index is gone");
        let caught = catch_unwind(|| std::panic::panic_any(7)).unwrap_err();
        assert_eq!(panic_said(caught), "Ghost.md's core stopped in the middle of that.");
    }

    #[test]
    fn a_listener_is_kept_and_forgotten() {
        extern "C" fn hears(_json: *const u8, _len: usize) {}
        ghost_set_listener(Some(hears));
        assert!(listener().is_some());
        ghost_set_listener(None);
        assert!(listener().is_none());
    }
}
