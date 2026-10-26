//! Ghost.md's core in a browser: the halves of native/ whose bytes every device must agree on, behind the same C
//! functions as native/src/ffi.rs, built for `wasm32-wasip1` and run in a worker of the page
//! (web/core/ghost_core_worker.js; lib/core/native/web_core.dart is its Dart end, docs/WEB.md).
//!
//! Matt, 2026-10-26: "update the web version of the app it's very behind". The web build is the Flutter app
//! compiled to WebAssembly, and what it cannot be is the phone's library of Markdown files over SQLite: a page has
//! no folder and no file to open an index in. So the notes are kept by the page itself, in IndexedDB
//! (lib/core/native/web_store.dart), answering the same commands, and only these come from Rust:
//!
//! - `crypto`: the account's keys and the sealed wire, native/src/crypto.rs itself. A password derived here is the
//!   phone's 64 bytes, a note sealed here opens on the Mac, and an organization's key unwrapped here is the key the
//!   Mac unwrapped: the same lines made them.
//! - `crdt`, `crdt_wire`: team notes and live typing, native/src/crdt.rs itself, over the same `yrs`.
//! - `names`: a note's file name from its title (tauri/src-tauri/src/library/names.rs), so a note made in the page
//!   has the path the phone would have given it, and keeps it when it syncs there.
//! - `note`, `lock`: what those include.
//!
//! What a browser does not have, and how each included file is kept from needing it:
//!
//! - **Threads.** WASI preview 1 has none: crypto.rs derives a secret's two halves one after the other here
//!   (`derive_bytes`), and a recovery sheet's eight codes too. The worker is the thread the phone's lane was.
//! - **Unwinding.** A wasm32 panic aborts, so `catch_unwind` below catches nothing: a panic traps the instance,
//!   and the worker says so and starts a fresh one (its keys and documents gone with it, as a crashed isolate's).
//! - **A file system.** No command of these needs one; the file-sealing commands (`seal_file`, `open_file`,
//!   `digest_file`) answer the system's refusal, and the page seals bytes instead.
//!
//! ```sh
//! tool/build-web-core.sh
//! ```

#[path = "../../../tauri/src-tauri/src/lock.rs"]
pub mod lock;

#[path = "../../../tauri/src-tauri/src/note.rs"]
pub mod note;

#[path = "../../../tauri/src-tauri/src/library/names.rs"]
pub mod names;

#[path = "../../src/crypto.rs"]
pub mod crypto;

#[path = "../../src/crdt.rs"]
pub mod crdt;

#[path = "../../src/crdt_wire.rs"]
pub mod crdt_wire;

pub mod ffi;
pub mod paths;
