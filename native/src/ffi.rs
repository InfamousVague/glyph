//! The C functions Dart calls (lib/core/native/ghost_worker.dart): what Tauri's IPC was to the web page.
//!
//! ```c
//! uint8_t *ghost_alloc(size_t len);
//! uint8_t *ghost_invoke(const uint8_t *cmd, size_t cmd_len, const uint8_t *args_json, size_t args_len, size_t *out_len);
//! void     ghost_free(uint8_t *ptr, size_t len);
//! void     ghost_set_listener(void (*listener)(uint8_t *json, size_t len));
//! void     ghost_forget_listener(void (*listener)(uint8_t *json, size_t len));
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
//! - **`ghost_set_listener`** keeps a function for events from Rust to the app (events.rs's `emit`, from any
//!   thread). Each event is UTF-8 JSON, `{"event": "<name>", "payload": <value>}`, in a buffer of this crate's
//!   that the LISTENER OWNS: it gives it back with `ghost_free(json, len)`. Owned and not borrowed because the
//!   app's listener is a `NativeCallable.listener`, which only posts the call to its isolate and returns: the
//!   bytes are read later, on the worker isolate's own turn. `ghost_forget_listener` forgets a listener only if
//!   it is still the one kept, so a worker that closes cannot silence the worker opened after it; once either
//!   returns, the old listener is never called again (the call is made under the same lock).
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
pub(crate) fn panic_said(payload: Box<dyn std::any::Any + Send>) -> String {
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

/// A function of the app's for events from Rust: UTF-8 JSON in a buffer the listener gives back with
/// `ghost_free(json, len)`.
pub type Listener = extern "C" fn(json: *mut u8, len: usize);

static LISTENER: Mutex<Option<Listener>> = Mutex::new(None);

/// Keeps `listener` in place of any other (null forgets it).
#[no_mangle]
pub extern "C" fn ghost_set_listener(listener: Option<Listener>) {
    *crate::lock::lock(&LISTENER) = listener;
}

/// Forgets `listener` if it is the one kept, and leaves another alone.
#[no_mangle]
pub extern "C" fn ghost_forget_listener(listener: Option<Listener>) {
    let mut kept = crate::lock::lock(&LISTENER);
    if listener.is_some() && kept.map(|l| l as usize) == listener.map(|l| l as usize) {
        *kept = None;
    }
}

/// The listener kept, if there is one.
pub fn listener() -> Option<Listener> {
    *crate::lock::lock(&LISTENER)
}

/// Hands `bytes` to the listener in a buffer it will free; `false` when nobody listens (nothing is allocated).
/// The lock is held across the call, which is why forgetting a listener is final: the listener only posts to
/// its isolate, so the wait is a message's.
pub(crate) fn send(bytes: &[u8]) -> bool {
    let kept = crate::lock::lock(&LISTENER);
    let Some(listener) = *kept else { return false };
    let ptr = ghost_alloc(bytes.len());
    if ptr.is_null() {
        return false;
    }
    // SAFETY: `ptr` is `bytes.len()` writable bytes (at least one), fresh from the allocator.
    unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), ptr, bytes.len()) };
    listener(ptr, bytes.len());
    true
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

    /// The listener is one slot for the process: the tests that fill it take turns.
    pub(crate) static LISTENING: Mutex<()> = Mutex::new(());
    static HEARD: Mutex<Vec<String>> = Mutex::new(Vec::new());

    extern "C" fn hears(json: *mut u8, len: usize) {
        let said = unsafe { String::from_utf8_lossy(std::slice::from_raw_parts(json, len)).into_owned() };
        unsafe { ghost_free(json, len) };
        HEARD.lock().unwrap().push(said);
    }

    extern "C" fn other(json: *mut u8, len: usize) {
        unsafe { ghost_free(json, len) };
    }

    #[test]
    fn a_listener_is_kept_called_from_any_thread_and_forgotten() {
        let _turn = crate::lock::lock(&LISTENING);
        ghost_set_listener(None);
        assert!(!send(b"{}"), "nobody listens, nothing is sent");
        ghost_set_listener(Some(hears));
        assert!(listener().is_some());
        let threads: Vec<_> = (0..8).map(|n| std::thread::spawn(move || crate::events::emit("test://from-a-thread", &json!({ "n": n })))).collect();
        for thread in threads {
            thread.join().unwrap();
        }
        crate::events::emit_json("test://raw", "");
        let heard = std::mem::take(&mut *HEARD.lock().unwrap());
        let mine: Vec<Value> = heard.iter().map(|said| serde_json::from_str(said).unwrap()).collect();
        let mut seen: Vec<u64> = mine.iter().filter(|e| e["event"] == "test://from-a-thread").map(|e| e["payload"]["n"].as_u64().unwrap()).collect();
        seen.sort();
        assert_eq!(seen, (0..8).collect::<Vec<u64>>());
        assert!(mine.iter().any(|e| e["event"] == "test://raw" && e["payload"].is_null()), "no payload is null");

        // Forgetting another listener leaves this one; forgetting this one is final.
        ghost_forget_listener(Some(other));
        assert!(listener().is_some());
        ghost_forget_listener(None);
        assert!(listener().is_some());
        ghost_forget_listener(Some(hears));
        assert!(listener().is_none());
        assert!(!send(b"{}"));
    }
}
