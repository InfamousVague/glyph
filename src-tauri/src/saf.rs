//! Rust's calls into Kotlin for a folder chosen on Android (docs/DESIGN.md
//! §185): the `Documents` library/tree.rs's `TreeVault` stands on, answered by
//! `files/LibraryTree.kt` through the Storage Access Framework.
//!
//! THE FIRST CALLS THIS WAY. Every JNI door before this one runs Kotlin to
//! Rust (update_alerts.rs, recording_jobs.rs). This one runs Rust to Kotlin,
//! from whatever thread a command or a write-up is on, and a thread Rust
//! started cannot find an app class by name: `FindClass` there asks the
//! system's class loader, which has never heard of `com.mattssoftware.glyph`.
//! So Kotlin introduces itself first. `LibraryTree.install(context)` calls
//! `attach()`, below, on a thread of its own, and that hands Rust the JVM and
//! a global reference to the class, kept for the life of the process. The
//! activity installs it before Tauri starts (so the launch can open a folder
//! chosen here), and the write-up's two doors before they call Rust.
//!
//! Every call is a static method taking strings and answering one JSON string:
//! `{"error": "..."}` for a failure, `{"missing": true}` for a file that is
//! not there, otherwise the answer. Kotlin catches everything it can; a Java
//! exception that still escapes is cleared here and answered as an error, so
//! none is left pending on a thread that goes on to call the JVM again.
//!
//! This module is compiled for Android only, so paths.rs's
//! `the_folder_bridge_has_every_method_rust_calls` reads LibraryTree.kt for the
//! names called here, on every machine the tests run on.
//!
//! An attached thread's local references live until it detaches, and a Tauri
//! worker thread never does, so each call runs in its own local frame.

use std::io;
use std::sync::OnceLock;

use jni::objects::{GlobalRef, JClass, JObject, JString, JValue};
use jni::{JNIEnv, JavaVM};
use serde_json::Value;

use crate::library::tree::Documents;
use crate::library::vault::Entry;

/// The JVM and `LibraryTree`'s class, from `attach`.
struct Bridge {
    vm: JavaVM,
    class: GlobalRef,
}

static BRIDGE: OnceLock<Bridge> = OnceLock::new();

/// `LibraryTree.attach()`: Kotlin handing Rust the JVM and its class, once per process. A second call is a no-op.
#[no_mangle]
pub extern "system" fn Java_com_mattssoftware_glyph_files_LibraryTree_attach<'local>(env: JNIEnv<'local>, class: JClass<'local>) {
    let _ = std::panic::catch_unwind(move || {
        if BRIDGE.get().is_some() {
            return;
        }
        let (Ok(vm), Ok(class)) = (env.get_java_vm(), env.new_global_ref(&class)) else { return };
        let _ = BRIDGE.set(Bridge { vm, class });
    });
}

fn failed(message: impl Into<String>) -> io::Error {
    io::Error::other(message.into())
}

/// `LibraryTree.<method>(args…): String`, its JSON parsed: an `error` is an error, `missing` is `NotFound`.
fn call(method: &str, args: &[&str]) -> io::Result<Value> {
    let bridge = BRIDGE.get().ok_or_else(|| failed("the phone's folder is not reachable yet: Ghost.md's Android side has not started"))?;
    let mut env = bridge.vm.attach_current_thread().map_err(|e| failed(format!("no JVM for this thread: {e}")))?;
    let answer: String = env
        .with_local_frame(8 + args.len() as i32, |env| -> jni::errors::Result<String> {
            let strings = args.iter().map(|arg| env.new_string(arg).map(JObject::from)).collect::<jni::errors::Result<Vec<JObject>>>()?;
            let values: Vec<JValue> = strings.iter().map(JValue::Object).collect();
            let signature = format!("({})Ljava/lang/String;", "Ljava/lang/String;".repeat(args.len()));
            let class: &JClass = bridge.class.as_obj().into();
            let said = env.call_static_method(class, method, &signature, &values).and_then(|value| value.l());
            let said = match said {
                Ok(said) => said,
                Err(e) => {
                    if env.exception_check().unwrap_or(false) {
                        let _ = env.exception_describe();
                        let _ = env.exception_clear();
                    }
                    return Err(e);
                }
            };
            if said.is_null() {
                return Ok(String::new());
            }
            Ok(env.get_string(&JString::from(said))?.into())
        })
        .map_err(|e| failed(format!("LibraryTree.{method}: {e}")))?;
    let value: Value = serde_json::from_str(&answer).map_err(|_| failed(format!("LibraryTree.{method} answered nothing readable")))?;
    if let Some(error) = value.get("error").and_then(Value::as_str) {
        return Err(failed(error));
    }
    if value.get("missing").and_then(Value::as_bool) == Some(true) {
        return Err(io::Error::new(io::ErrorKind::NotFound, format!("not in the folder ({method})")));
    }
    Ok(value)
}

/// `[path, modifiedMs, size]`, as Kotlin writes an entry.
fn entry_of(value: &Value) -> io::Result<Entry> {
    let unread = || failed("an entry from the phone's folder could not be read");
    let parts = value.as_array().ok_or_else(unread)?;
    Ok(Entry {
        path: parts.first().and_then(Value::as_str).ok_or_else(unread)?.to_string(),
        modified_ms: parts.get(1).and_then(Value::as_i64).unwrap_or(0),
        size: parts.get(2).and_then(Value::as_u64).unwrap_or(0),
        evicted: false,
    })
}

/// What the picker's folder holds, for the page to say before it is taken: its name, how many notes, whether
/// Obsidian keeps it.
pub struct Inspected {
    pub name: String,
    pub markdown: usize,
    pub obsidian: bool,
}

/// The folder at `uri`, looked into and nothing written there.
pub fn inspect(uri: &str) -> io::Result<Inspected> {
    let value = call("inspect", &[uri])?;
    Ok(Inspected {
        name: value.get("name").and_then(Value::as_str).unwrap_or("").to_string(),
        markdown: value.get("markdown").and_then(Value::as_u64).unwrap_or(0) as usize,
        obsidian: value.get("obsidian").and_then(Value::as_bool).unwrap_or(false),
    })
}

/// The folder the picker granted, by its tree URI.
pub struct TreeDocuments {
    uri: String,
}

impl TreeDocuments {
    /// The folder at `uri`, while Ghost.md still holds its grant to read and write it.
    pub fn new(uri: &str) -> Result<TreeDocuments, String> {
        call("granted", &[uri]).map_err(|e| e.to_string())?;
        Ok(TreeDocuments { uri: uri.to_string() })
    }
}

impl Documents for TreeDocuments {
    fn list(&self) -> io::Result<Vec<Entry>> {
        let value = call("list", &[&self.uri])?;
        value.get("entries").and_then(Value::as_array).ok_or_else(|| failed("the phone's folder could not be listed"))?.iter().map(entry_of).collect()
    }

    fn read(&self, path: &str) -> io::Result<String> {
        let value = call("read", &[&self.uri, path])?;
        value.get("text").and_then(Value::as_str).map(str::to_string).ok_or_else(|| failed(format!("{path} could not be read")))
    }

    fn write(&self, path: &str, text: &str) -> io::Result<Entry> {
        let value = call("write", &[&self.uri, path, text])?;
        entry_of(value.get("entry").unwrap_or(&Value::Null))
    }

    fn rename(&self, from: &str, to: &str) -> io::Result<()> {
        call("rename", &[&self.uri, from, to]).map(drop)
    }

    fn remove(&self, path: &str) -> io::Result<()> {
        match call("remove", &[&self.uri, path]) {
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(()),
            other => other.map(drop),
        }
    }

    fn stat(&self, path: &str) -> io::Result<Option<Entry>> {
        match call("stat", &[&self.uri, path]) {
            Ok(value) => entry_of(value.get("entry").unwrap_or(&Value::Null)).map(Some),
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(e),
        }
    }
}
