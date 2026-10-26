//! The C functions the page's worker calls (web/core/ghost_core_worker.js): native/src/ffi.rs's three, by the same
//! names and the same contract, so the worker is ghost_worker.dart over WebAssembly's memory instead of `dart:ffi`.
//!
//! ```c
//! uint8_t *ghost_alloc(size_t len);
//! uint8_t *ghost_invoke(const uint8_t *cmd, size_t cmd_len, const uint8_t *args_json, size_t args_len, size_t *out_len);
//! void     ghost_free(uint8_t *ptr, size_t len);
//! ```
//!
//! No listener: nothing here emits an event or runs a job. And no unwinding (lib.rs says why), so a panic is the
//! worker's to see, as a trap.

use std::alloc::Layout;

use serde_json::{json, Value};

const ALIGN: usize = 8;

fn layout(len: usize) -> Option<Layout> {
    Layout::from_size_align(len.max(1), ALIGN).ok()
}

/// `len` bytes for the caller to fill, or null when there is no memory.
#[no_mangle]
pub extern "C" fn ghost_alloc(len: usize) -> *mut u8 {
    match layout(len) {
        // SAFETY: the layout's size is never zero.
        Some(layout) => unsafe { std::alloc::alloc(layout) },
        None => std::ptr::null_mut(),
    }
}

/// Gives back what `ghost_alloc` or `ghost_invoke` handed out, with the length it was handed out with.
///
/// # Safety
/// As native/src/ffi.rs's.
#[no_mangle]
pub unsafe extern "C" fn ghost_free(ptr: *mut u8, len: usize) {
    if ptr.is_null() {
        return;
    }
    if let Some(layout) = layout(len) {
        std::alloc::dealloc(ptr, layout);
    }
}

/// One command, by name: what dispatch.rs's `invoke` hands to these files, and nothing else.
fn invoke(command: &str, args: Value) -> Result<Value, String> {
    let args = if args.is_null() { json!({}) } else { args };
    match command {
        "new_id" => Ok(Value::String(crate::note::new_id())),
        command if crate::crypto::has(command) => crate::crypto::call(command, args),
        command if crate::crdt::has(command) => crate::crdt::call(command, args),
        command if crate::paths::has(command) => crate::paths::call(command, args),
        _ => Err(format!("Ghost.md's core in the browser has no command named {command}.")),
    }
}

/// One command, answered as the JSON text that crosses.
pub fn answer(command: &[u8], args: &[u8]) -> String {
    let result = (|| -> Result<Value, String> {
        let command = std::str::from_utf8(command).map_err(|_| "a command's name must be UTF-8".to_string())?;
        let args: Value = if args.is_empty() {
            Value::Null
        } else {
            serde_json::from_slice(args).map_err(|e| format!("the arguments of {command} are not JSON: {e}"))?
        };
        invoke(command, args)
    })();
    let said = match result {
        Ok(value) => json!({ "ok": value }),
        Err(sentence) => json!({ "err": sentence }),
    };
    said.to_string()
}

/// Runs one command.
///
/// # Safety
/// As native/src/ffi.rs's.
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
    let bytes = said.as_bytes();
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
