use std::path::PathBuf;

fn main() {
    android_native_rules();
    tauri_build::build()
}

/// Two rules for the Android library, both from Google Play (docs/store/PLAY_STORE.md).
///
/// **16 KB pages.** Play takes only apps whose native libraries load on phones with 16 KB memory pages, which means
/// every LOAD segment of every `.so` aligned to 16 KB. NDK r26's linker lays them out at 4 KB unless told otherwise,
/// so `libglyph_lib.so` is linked with `-z max-page-size=16384`. Here rather than in `.cargo/config.toml`'s rustflags
/// because Tauri's Android build sets rustflags of its own, which replace the config's rather than adding to them; a
/// build script's link arguments always reach the link.
///
/// **No libc++_shared.so.** whisper.cpp and llama.cpp are C++, and were built against the shared C++ runtime, which
/// this script used to copy out of the NDK into `jniLibs/` (Gradle packages it only for native code it builds itself).
/// NDK r26's copy is 4 KB-aligned, so it would fail the rule above on its own. Both are now linked against the static
/// runtime inside `libglyph_lib.so` (Cargo.toml `android-static-stdcxx`, vendor/whisper-rs-sys/build.rs, the CMake
/// toolchain file), so there is nothing to ship - and a copy left in `jniLibs/` from an older build would still be
/// packaged and still be refused, so it is removed.
fn android_native_rules() {
    if std::env::var("TARGET").as_deref() != Ok("aarch64-linux-android") {
        return;
    }
    println!("cargo:rustc-link-arg=-Wl,-z,max-page-size=16384");
    println!("cargo:rustc-link-arg=-Wl,-z,common-page-size=16384");

    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("cargo sets CARGO_MANIFEST_DIR"));
    let stale = manifest.join("gen/android/app/src/main/jniLibs/arm64-v8a/libc++_shared.so");
    if std::fs::symlink_metadata(&stale).is_ok() {
        if let Err(error) = std::fs::remove_file(&stale) {
            println!("cargo:warning=could not remove the old {}: {error}", stale.display());
        }
    }
}
