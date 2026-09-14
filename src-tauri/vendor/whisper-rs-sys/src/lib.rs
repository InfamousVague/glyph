#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]

// Glyph: whisper.cpp is compiled against llama-cpp-sys-2's ggml (build.rs,
// `shared_ggml`), and ggml's libraries are linked by that crate. Nothing in
// Rust here uses it, and rustc does not link the native libraries of a crate
// nobody references - so without this line whisper's ggml symbols are
// undefined wherever the app does not call llama itself.
extern crate llama_cpp_sys_2;

include!(concat!(env!("OUT_DIR"), "/bindings.rs"));
