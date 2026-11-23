//! The C interface: seven functions (include/ghost_p2p.h), and on Android one more for Kotlin.
//!
//! A node is a number. Commands go in as bytes (`ghost_p2p_command`), events come out as bytes through the one
//! callback the node was made with, on the library's own threads; each event's buffer is the receiver's to give back
//! (`ghost_p2p_buffer_free`). src/wire.rs is the layout of both; README.md says it in tables.
//!
//! Whoever makes nodes says who it is by a number of its own choosing (its **owner**; the Dart side gives its
//! Flutter engine's), so that it can let go of what an earlier life of itself left behind (`ghost_p2p_drop_owned`: a
//! hot restart ends an isolate without a word) and of nothing that is someone else's.
//!
//! Nothing here waits on the network, and nothing here can take the app down: every entry catches a panic and
//! answers [`PANICKED`] (or nothing) instead.

use std::{
    collections::HashMap,
    panic::{AssertUnwindSafe, catch_unwind},
    sync::{
        Arc, Mutex, MutexGuard, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
};

use tokio::runtime::Runtime;

use crate::{node::Node, wire::Event};

/// What the Dart side must find, or it does not use the library: raised whenever a function, a command, an event or
/// what one of them means changes.
pub const ABI: u32 = 1;

/// What `ghost_p2p_command` answers.
pub const OK: i32 = 0;
/// There is no such node.
pub const NO_NODE: i32 = -1;
/// The command could not be read.
pub const MALFORMED: i32 = -2;
/// SEND: there is no such stream (it has closed).
pub const NO_STREAM: i32 = -3;
/// SEND: the stream's queue was full, and the stream is now closed.
pub const OVERFLOW: i32 = -4;
/// SEND: the frame is longer than a stream carries.
pub const TOO_LONG: i32 = -5;
/// A bug in the library was caught.
pub const PANICKED: i32 = -6;

/// Called with a node's events, one at a time and in order, from the library's threads. `event` is `len` bytes that
/// the receiver gives back with `ghost_p2p_buffer_free`.
pub type EventCallback = unsafe extern "C" fn(node: u64, event: *mut u8, len: usize);

struct Kept {
    node: Node,
    owner: u64,
    /// The callback, until the node is dropped: taken away under the same lock an event is handed over under, so
    /// that once `ghost_p2p_drop` has returned it is never called again.
    callback: Arc<Mutex<Option<EventCallback>>>,
}

static NODES: Mutex<Option<HashMap<u64, Arc<Kept>>>> = Mutex::new(None);
static NEXT: AtomicU64 = AtomicU64::new(1);
static RUNTIME: OnceLock<Option<Runtime>> = OnceLock::new();

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// The library's own threads: two, made when the first node is, and kept for the life of the process.
fn runtime() -> Option<&'static Runtime> {
    RUNTIME.get_or_init(|| tokio::runtime::Builder::new_multi_thread().worker_threads(2).thread_name("ghost-p2p").enable_all().build().ok()).as_ref()
}

fn kept(node: u64) -> Option<Arc<Kept>> {
    lock(&NODES).as_ref()?.get(&node).cloned()
}

/// Takes a node's callback away and lets the node go; it stops by itself, in the background.
fn let_go(kept: Arc<Kept>) {
    *lock(&kept.callback) = None;
}

/// The number the Dart side checks before it uses anything else.
#[unsafe(no_mangle)]
pub extern "C" fn ghost_p2p_abi() -> u32 {
    ABI
}

/// The node id a node key makes, with nothing started. `secret` is 32 bytes, `out` is room for 32. Answers 0, or
/// [`MALFORMED`] where either is null.
///
/// # Safety
/// `secret` must be readable and `out` writable for 32 bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ghost_p2p_node_id(secret: *const u8, out: *mut u8) -> i32 {
    if secret.is_null() || out.is_null() {
        return MALFORMED;
    }
    catch_unwind(AssertUnwindSafe(|| {
        let mut key = [0u8; 32];
        // SAFETY: the caller's word that 32 bytes are there to read, and 32 to write.
        unsafe { std::ptr::copy_nonoverlapping(secret, key.as_mut_ptr(), 32) };
        let id = crate::node::node_id(&key);
        key.fill(0);
        unsafe { std::ptr::copy_nonoverlapping(id.as_ptr(), out, 32) };
        OK
    }))
    .unwrap_or(PANICKED)
}

/// Makes a node, not started, for `owner`, whose events go to `callback`. Answers its number, or 0 where it could not
/// be made.
#[unsafe(no_mangle)]
pub extern "C" fn ghost_p2p_new(owner: u64, callback: Option<EventCallback>) -> u64 {
    let Some(callback) = callback else { return 0 };
    catch_unwind(|| {
        let Some(runtime) = runtime() else { return 0 };
        let number = NEXT.fetch_add(1, Ordering::Relaxed);
        let callback = Arc::new(Mutex::new(Some(callback)));
        let node = Node::new(runtime.handle(), {
            let callback = callback.clone();
            move |event: Event| {
                let bytes = event.encode().into_boxed_slice();
                let held = lock(&callback);
                if let Some(call) = *held {
                    let len = bytes.len();
                    let event = Box::into_raw(bytes) as *mut u8;
                    // SAFETY: the buffer is whole and is the receiver's from here; it comes back through
                    // ghost_p2p_buffer_free with the same length.
                    unsafe { call(number, event, len) };
                }
            }
        });
        lock(&NODES).get_or_insert_with(HashMap::new).insert(number, Arc::new(Kept { node, owner, callback }));
        number
    })
    .unwrap_or(0)
}

/// Gives a node a command (README.md, "Commands"). Never waits: what a command comes to is said in events.
///
/// # Safety
/// `command` must be readable for `len` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ghost_p2p_command(node: u64, command: *const u8, len: usize) -> i32 {
    if command.is_null() || len == 0 {
        return MALFORMED;
    }
    catch_unwind(AssertUnwindSafe(|| {
        let Some(kept) = kept(node) else { return NO_NODE };
        // SAFETY: the caller's word that `len` bytes are there; they are read, never kept.
        let bytes = unsafe { std::slice::from_raw_parts(command, len) };
        kept.node.command(bytes)
    }))
    .unwrap_or(PANICKED)
}

/// Gives back a buffer the callback was handed, with the length it was handed with.
///
/// # Safety
/// `buffer` and `len` must be exactly what one call of the callback was given, given back once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ghost_p2p_buffer_free(buffer: *mut u8, len: usize) {
    if buffer.is_null() {
        return;
    }
    // SAFETY: made by Box::into_raw of a boxed slice of this length, in ghost_p2p_new's sink.
    drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(buffer, len)) });
}

/// Stops a node and forgets it. Once this has returned its callback is not called again; the node's links and
/// sockets close in the background, within a few seconds.
#[unsafe(no_mangle)]
pub extern "C" fn ghost_p2p_drop(node: u64) {
    let _ = catch_unwind(|| {
        let kept = lock(&NODES).as_mut().and_then(|nodes| nodes.remove(&node));
        if let Some(kept) = kept {
            let_go(kept);
        }
    });
}

/// The same for every node `owner` made: what the Dart side calls as it first opens the library, so that nodes left
/// by an isolate that is gone (a hot restart) do not stay up with nobody to hear them, calling a callback that is no
/// longer there. Another owner's nodes (another Flutter engine's in the same process) are left alone.
#[unsafe(no_mangle)]
pub extern "C" fn ghost_p2p_drop_owned(owner: u64) {
    let _ = catch_unwind(|| {
        let owned: Vec<Arc<Kept>> = {
            let mut nodes = lock(&NODES);
            let Some(nodes) = nodes.as_mut() else { return };
            let numbers: Vec<u64> = nodes.iter().filter(|(_, kept)| kept.owner == owner).map(|(number, _)| *number).collect();
            numbers.iter().filter_map(|number| nodes.remove(number)).collect()
        };
        for kept in owned {
            let_go(kept);
        }
    });
}

/// Android: hands iroh's DNS the app's context, which it reads the phone's DNS servers through (P2pCore.kt calls it
/// once, before Dart can start a node). Without it no link helper's name can be looked up: this library asks no
/// public DNS server in the system's place. Answers whether the context is in place.
///
/// # Safety
/// Called by the JVM as the native method `P2pCore.nativeInstall(Context)`.
#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
pub unsafe extern "system" fn Java_com_infamousvague_ghostmessaging_P2pCore_nativeInstall(
    env: *mut jni_sys::JNIEnv,
    _this: jni_sys::jobject,
    context: jni_sys::jobject,
) -> jni_sys::jboolean {
    static INSTALLED: Mutex<bool> = Mutex::new(false);
    if env.is_null() || context.is_null() {
        return false;
    }
    catch_unwind(AssertUnwindSafe(|| {
        let mut installed = lock(&INSTALLED);
        if *installed {
            return true;
        }
        // SAFETY: `env` is the JNI environment of the calling thread, and `context` a live reference, for the length
        // of this call. The context is made a global reference, which lives (as the virtual machine does) until the
        // process ends: what iroh asks of both.
        unsafe {
            let mut vm: *mut jni_sys::JavaVM = std::ptr::null_mut();
            if ((**env).GetJavaVM)(env, &mut vm) != jni_sys::JNI_OK || vm.is_null() {
                return false;
            }
            let global = ((**env).NewGlobalRef)(env, context);
            if global.is_null() {
                return false;
            }
            iroh::dns::install_android_jni_context(vm.cast(), global.cast());
        }
        *installed = true;
        true
    }))
    .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wire::{cmd, ev};
    use std::sync::mpsc;

    /// An event as the callback was handed it: the node, and the bytes.
    type Heard = (u64, Vec<u8>);
    static HEARD: Mutex<Option<mpsc::Sender<Heard>>> = Mutex::new(None);

    unsafe extern "C" fn hear(node: u64, event: *mut u8, len: usize) {
        let bytes = unsafe { std::slice::from_raw_parts(event, len) }.to_vec();
        unsafe { ghost_p2p_buffer_free(event, len) };
        if let Some(heard) = lock(&HEARD).as_ref() {
            let _ = heard.send((node, bytes));
        }
    }

    fn command(node: u64, bytes: &[u8]) -> i32 {
        unsafe { ghost_p2p_command(node, bytes.as_ptr(), bytes.len()) }
    }

    /// The whole interface, as the Dart side uses it: a node is made, started, heard from, stopped and dropped, and
    /// what is wrong is answered, not obeyed.
    #[test]
    fn the_c_interface_end_to_end() {
        let (tx, rx) = mpsc::channel();
        *lock(&HEARD) = Some(tx);
        let next = |want: u8| loop {
            let (node, bytes) = rx.recv_timeout(std::time::Duration::from_secs(20)).expect("an event");
            if bytes[0] == want {
                return (node, bytes);
            }
        };
        assert_eq!(ghost_p2p_abi(), ABI);
        assert_eq!(ghost_p2p_new(1, None), 0);

        let secret = [9u8; 32];
        let mut id = [0u8; 32];
        assert_eq!(unsafe { ghost_p2p_node_id(secret.as_ptr(), id.as_mut_ptr()) }, OK);
        assert_eq!(id, crate::node::node_id(&secret));
        assert_eq!(unsafe { ghost_p2p_node_id(std::ptr::null(), id.as_mut_ptr()) }, MALFORMED);

        let node = ghost_p2p_new(1, Some(hear));
        assert_ne!(node, 0);
        assert_eq!(command(node + 1000, &[cmd::STOP]), NO_NODE);
        assert_eq!(command(node, &[0x7f]), MALFORMED);
        assert_eq!(command(node, &[cmd::START, 0]), MALFORMED);
        assert_eq!(unsafe { ghost_p2p_command(node, std::ptr::null(), 4) }, MALFORMED);
        let mut send = vec![cmd::SEND];
        send.extend_from_slice(&77u64.to_be_bytes());
        send.extend_from_slice(b"to nobody");
        assert_eq!(command(node, &send), NO_STREAM);
        send.resize(crate::wire::FRAME_AT + crate::wire::MAX_FRAME + 1, 0);
        assert_eq!(command(node, &send), TOO_LONG);

        let mut start = vec![cmd::START, 0];
        start.extend_from_slice(&secret);
        start.push(0);
        assert_eq!(command(node, &start), OK);
        let (from, up) = next(ev::UP);
        assert_eq!(from, node);
        assert_eq!(&up[1..], &id);

        // An open to a node nothing is known of fails at once, and says which request failed.
        let mut open = vec![cmd::OPEN];
        open.extend_from_slice(&5u32.to_be_bytes());
        open.extend_from_slice(&crate::node::node_id(&[8u8; 32]));
        open.push(0);
        open.extend_from_slice(&2000u32.to_be_bytes());
        open.extend_from_slice(&[0, 0, 0]);
        assert_eq!(command(node, &open), OK);
        let (_, failed) = next(ev::OPEN_FAILED);
        assert_eq!(&failed[1..6], &[0, 0, 0, 5, crate::wire::OpenError::Unreachable as u8]);

        assert_eq!(command(node, &[cmd::STOP]), OK);
        next(ev::OFF);

        // Two more beside it, one of them another owner's. An owner lets go of its own, and of nobody else's.
        let mine = ghost_p2p_new(1, Some(hear));
        let theirs = ghost_p2p_new(2, Some(hear));
        assert!(mine != 0 && theirs != 0 && mine != node && theirs != mine);
        ghost_p2p_drop_owned(1);
        assert_eq!(command(node, &[cmd::STOP]), NO_NODE);
        assert_eq!(command(mine, &[cmd::STOP]), NO_NODE);
        assert_eq!(command(theirs, &[cmd::STOP]), OK);
        ghost_p2p_drop(theirs);
        assert_eq!(command(theirs, &[cmd::STOP]), NO_NODE);
        ghost_p2p_drop(node);
    }
}
