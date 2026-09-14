use std::path::{Path, PathBuf};

fn main() {
    stage_android_cxx_runtime();
    tauri_build::build()
}

/// Put the C++ runtime whisper.cpp links against next to the app's own library
/// in the Android project, on every Android build.
///
/// whisper.cpp is C++, and on Android it is built against `c++_shared`, so
/// `libglyph_lib.so` carries a NEEDED entry for `libc++_shared.so` (checked with
/// `llvm-readelf -d`). Gradle only packages that runtime for native code IT
/// builds, and cargo-mobile2 only symlinks the Rust library into `jniLibs/`, so
/// nothing else puts it there. Missing, the app installs fine and dies the
/// moment Java loads the library: `dlopen failed: library "libc++_shared.so"
/// not found`.
///
/// It was first copied in by hand, which works until a fresh clone: Tauri's
/// generated `gen/android/app/.gitignore` ignores every `.so` under `jniLibs/`,
/// so the copy was never in git. Copying it here makes the build produce what
/// the build needs.
///
/// The NDK is found the same way the CMake toolchain wrapper finds it - from
/// the target C compiler cargo was given, falling back to `NDK_HOME` - so the
/// runtime always comes from the same NDK that compiled the code linking it.
/// Mismatched runtimes are an ABI hazard, not a style issue.
fn stage_android_cxx_runtime() {
    println!("cargo:rerun-if-env-changed=CC_aarch64_linux_android");
    println!("cargo:rerun-if-env-changed=NDK_HOME");

    if std::env::var("TARGET").as_deref() != Ok("aarch64-linux-android") {
        return;
    }

    let ndk = std::env::var_os("CC_aarch64_linux_android")
        .map(PathBuf::from)
        // .../ndk/<ver>/toolchains/llvm/prebuilt/<host>/bin/<clang>
        .and_then(|cc| cc.ancestors().nth(6).map(Path::to_path_buf))
        .or_else(|| std::env::var_os("NDK_HOME").map(PathBuf::from));

    let Some(ndk) = ndk else {
        println!("cargo:warning=no NDK found (CC_aarch64_linux_android and NDK_HOME unset); libc++_shared.so not staged");
        return;
    };

    let prebuilt = ndk.join("toolchains/llvm/prebuilt");
    let Some(runtime) = std::fs::read_dir(&prebuilt)
        .into_iter()
        .flatten()
        .flatten()
        .map(|host| host.path().join("sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"))
        .find(|path| path.exists())
    else {
        println!("cargo:warning=libc++_shared.so not found under {}", prebuilt.display());
        return;
    };

    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("cargo sets CARGO_MANIFEST_DIR"));
    let dest_dir = manifest.join("gen/android/app/src/main/jniLibs/arm64-v8a");
    let dest = dest_dir.join("libc++_shared.so");

    // Skipped when already identical, so an unchanged runtime does not touch the
    // file and invalidate Gradle's up-to-date check on every build.
    let same = std::fs::metadata(&dest).ok().map(|m| m.len()) == std::fs::metadata(&runtime).ok().map(|m| m.len());
    if same {
        return;
    }
    if let Err(error) = std::fs::create_dir_all(&dest_dir).and_then(|()| std::fs::copy(&runtime, &dest).map(|_| ())) {
        println!("cargo:warning=could not stage libc++_shared.so into {}: {error}", dest_dir.display());
    }
}
