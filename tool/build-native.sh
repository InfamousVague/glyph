#!/bin/sh
# Builds the Rust core (native/, docs/STAGE3.md): its tests, the Mac's library that Dart's tests open, and the
# phone's libghost_core.so, copied to where Gradle packs it.
#
#   tool/build-native.sh            all three
#   tool/build-native.sh test       cargo test on the Mac
#   tool/build-native.sh host       native/target/debug/libghost_core.dylib, for `flutter test test/native`
#   tool/build-native.sh android    android/app/src/main/jniLibs/arm64-v8a/libghost_core.so (release)
#   tool/build-native.sh mac        macos/Core/libghost_core.dylib (release, Apple silicon and Intel in one file),
#                                   which Xcode's "Bundle the core" phase copies into the app's Frameworks and
#                                   signs; not part of `all`. GHOST_MAC_ARCHS="arm64" builds the one alone.
#
#   GHOST_VOICE=0 tool/build-native.sh ...    the notes-only core, without the engines: seconds, not minutes
#
# The crate includes its library from ../glyph/src-tauri/src by path and builds nothing there: cargo's target
# directory is native/target, whatever CARGO_TARGET_DIR says outside. A deploy of the Tauri app runs tests that
# fail when the Mac is busy, so this waits for one to end before it compiles.
#
# The engines (the crate's `voice` feature, docs/STAGES_5_6_8_9.md stage 8) are whisper.cpp and llama.cpp over
# ONE ggml, compiled by CMake the first time (about two minutes for the Mac, more for the phone) and kept in
# native/target after that. They are built with half the cores: other sessions share this Mac. What the build
# scripts read that is the same for every NDK is in native/.cargo/config.toml; what names the NDK is set here.
#
# The phone's .so: arm64 only (the Fold), API 24, the C++ runtime linked in (no libc++_shared.so to ship), and
# LOAD segments aligned to 16 KB, which Android 15 and later ask of every library on a 16 KB-page device.
# NDK 28.2, the one Flutter's own Gradle build names (flutter.ndkVersion) when there is one, else the newest:
# the Tauri app pins 26.3 because its Gradle does; one NDK must compile every C and C++ file in a library
# (SQLite, ring, ggml), and here that is Flutter's. ANDROID_NDK_HOME picks another.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
crate="$root/native"
export CARGO_TARGET_DIR="$crate/target"
what="${1:-all}"

# With the engines unless told otherwise.
voice="${GHOST_VOICE:-1}"
case "$voice" in 0|no|false|off) voice="" ;; *) voice="voice" ;; esac

# Half the cores, for cargo and for the two CMake builds inside it (llama-cpp-sys-2 reads
# CMAKE_BUILD_PARALLEL_LEVEL, and takes every core without it; whisper-rs-sys follows cargo's -j).
cores="$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
jobs=$((cores / 2))
[ "$jobs" -ge 1 ] || jobs=1
export CMAKE_BUILD_PARALLEL_LEVEL="$jobs"

# The included tests that cannot run from here, by name. Each reads a file of the Tauri app's by a path built
# from CARGO_MANIFEST_DIR, which in this crate is native/ and not ../glyph/src-tauri, and takes no directory
# from the environment: three hold write_up.rs to the Tauri app's Kotlin (gen/android/.../RecordingJob.kt and
# friends), one to a fixture of its page. They are the Tauri app's own agreements and run in its own suite.
# (The engine's model-bound tests in llm/tests.rs look for ../models/llm the same way; they find none and say
# SKIPPED rather than fail. smoke.rs runs a model through the boundary instead.)
skipped="
  write_up::tests::the_budgets_agree_with_the_pages_fixture
  write_up::tests::the_kotlin_door_and_the_rust_symbols_name_each_other
  write_up::tests::the_kotlin_options_are_the_rust_fields
  write_up::tests::the_kotlin_reads_every_answer_by_its_key_and_every_word_by_its_name
"

if [ ! -f "$root/../glyph/src-tauri/src/library/mod.rs" ]; then
  echo "build-native: ../glyph is not beside this repository; the core is built from its src-tauri/src." >&2
  exit 1
fi

wait_for_deploys() {
  while pgrep -fl "scripts/[d]eploy" >/dev/null 2>&1; do
    echo "build-native: a deploy of the Tauri app is running; waiting for it to end..."
    sleep 20
  done
}

run_tests() {
  wait_for_deploys
  if [ -n "$voice" ]; then
    skips=""
    for name in $skipped; do skips="$skips --skip $name"; done
    # Five at a time, like the build: the engines' tests each take four cores of their own.
    # shellcheck disable=SC2086
    (cd "$crate" && cargo test -j "$jobs" --features test-hooks,voice -- --test-threads "$jobs" $skips)
    (cd "$crate" && cargo test -j "$jobs" -p tauri)
  else
    (cd "$crate" && cargo test -j "$jobs" --features test-hooks)
  fi
}

build_host() {
  wait_for_deploys
  # With the test hooks: `test_panic`, `test_emit` and `test_long_job` for test/native. The phone's has none.
  (cd "$crate" && cargo build -j "$jobs" --features "test-hooks${voice:+,voice}")
  echo "build-native: $CARGO_TARGET_DIR/debug/libghost_core.dylib${voice:+ (with the engines)}"
}

build_android() {
  sdk="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
  ndk="${ANDROID_NDK_HOME:-}"
  if [ -z "$ndk" ]; then
    ndk="$(ls -d "$sdk"/ndk/28.* 2>/dev/null | sort -V | tail -1)"
    [ -n "$ndk" ] || ndk="$(ls -d "$sdk"/ndk/* 2>/dev/null | sort -V | tail -1)"
  fi
  if [ -z "$ndk" ] || [ ! -d "$ndk" ]; then
    echo "build-native: no NDK under $sdk/ndk (sdkmanager 'ndk;28.2.13676358')." >&2
    exit 1
  fi
  bin="$(ls -d "$ndk"/toolchains/llvm/prebuilt/*/bin | head -1)"
  api=24
  target=aarch64-linux-android
  if ! rustup target list --installed | grep -qx "$target"; then
    echo "build-native: rustup target add $target" >&2
    exit 1
  fi
  wait_for_deploys
  export CC_aarch64_linux_android="$bin/${target}${api}-clang"
  export AR_aarch64_linux_android="$bin/llvm-ar"
  export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$bin/${target}${api}-clang"
  export CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS="-C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-Wl,-z,common-page-size=16384"
  if [ -n "$voice" ]; then
    # What ../glyph/.cargo/config.toml sets for its NDK, for this one. The C++ compiler by name (the cmake crate
    # asks cc for it); the sysroot bindgen parses whisper.h and llama.h against; and the NDK and API level
    # llama-cpp-sys-2 finds by its own rules (left alone: the newest NDK installed, API 28). The CMake toolchain
    # file for whisper.cpp, and GGML_CPU_ARM_ARCH, are in native/.cargo/config.toml.
    export CXX_aarch64_linux_android="$bin/${target}${api}-clang++"
    export BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android="--sysroot=$(dirname "$bin")/sysroot --target=${target}${api}"
    export ANDROID_NDK="$ndk"
    export ANDROID_API_LEVEL="$api"
    # CMake honours a toolchain file only the first time it configures a build directory, so engines first
    # configured for another NDK would stay that NDK's for ever, silently. Their build directories go when
    # the NDK changes.
    stamp="$CARGO_TARGET_DIR/$target/.ghost-ndk"
    if [ "$(cat "$stamp" 2>/dev/null || true)" != "$ndk" ]; then
      rm -rf "$CARGO_TARGET_DIR/$target"/release/build/whisper-rs-sys-* "$CARGO_TARGET_DIR/$target"/release/build/llama-cpp-sys-2-*
      mkdir -p "$CARGO_TARGET_DIR/$target"
      printf '%s' "$ndk" > "$stamp"
    fi
  fi
  (cd "$crate" && cargo build -j "$jobs" --release --target "$target" ${voice:+--features voice})
  built="$CARGO_TARGET_DIR/$target/release/libghost_core.so"
  out="$root/android/app/src/main/jniLibs/arm64-v8a"
  echo "build-native: NDK $(basename "$ndk"), API $api${voice:+, with the engines}"
  # Everything is checked on the built file: one that fails is never put where Gradle packs it.
  "$bin/llvm-readelf" -lW "$built" | awk '$1 == "LOAD" { print "build-native: LOAD align " $NF; if ($NF != "0x4000") bad = 1 } END { exit bad }' || {
    echo "build-native: a LOAD segment is not 16 KB aligned." >&2
    exit 1
  }
  symbols="ghost_alloc ghost_invoke ghost_free ghost_set_listener ghost_forget_listener"
  # The door a chosen folder's Kotlin hands itself to Rust through (saf.rs; android/.../glyph/files/LibraryTree.kt).
  symbols="$symbols Java_com_mattssoftware_glyph_files_LibraryTree_attach"
  # The JNI door a meeting's service and its job call (recording_jobs.rs), and the audio door the dictation
  # microphone pushes through (capture.rs; android/.../glyph/capture/DictationMic.kt): Kotlin finds these by name.
  [ -z "$voice" ] || symbols="$symbols Java_com_mattssoftware_glyph_recordings_RecordingJob_finish Java_com_mattssoftware_glyph_recordings_RecordingJob_run Java_com_mattssoftware_glyph_recordings_RecordingJob_cancel ghost_capture_push Java_com_mattssoftware_glyph_capture_DictationMic_push"
  "$bin/llvm-readelf" --dyn-syms -W "$built" > "$CARGO_TARGET_DIR/$target/.ghost-symbols"
  for symbol in $symbols; do
    grep -qw "$symbol" "$CARGO_TARGET_DIR/$target/.ghost-symbols" || { echo "build-native: $symbol is not exported." >&2; exit 1; }
  done
  # The C++ runtime is inside (c++_static): a library that asks for libc++_shared.so would not load, since
  # nothing ships one.
  if "$bin/llvm-readelf" -dW "$built" | grep -q 'libc++_shared'; then
    echo "build-native: the library needs libc++_shared.so, which the app does not carry." >&2
    exit 1
  fi
  "$bin/llvm-readelf" -dW "$built" | awk '/NEEDED/ { printf "build-native: needs %s\n", $NF }'
  mkdir -p "$out"
  # Copied beside under a name Gradle does not pack, then moved: a build of the app meanwhile packs the old
  # library or the new one, never half of one.
  cp "$built" "$out/libghost_core.so.part"
  mv -f "$out/libghost_core.so.part" "$out/libghost_core.so"
  echo "build-native: $out/libghost_core.so ($(wc -c < "$out/libghost_core.so" | tr -d ' ') bytes)"
}

# The Mac app's library: release, without the test hooks, one slice per architecture joined by lipo, as the Tauri
# Mac app is universal (../glyph scripts/deploy-ota.mjs MAC_TARGET). Its install name is @rpath's, so the copy in
# the app's Frameworks is what it says it is. Left unsigned: Xcode's phase signs the copy with the app's identity.
# The Intel slice compiles the engines for x86_64 from here (no -march=native: cmake is told the processor).
build_mac() {
  wait_for_deploys
  archs="${GHOST_MAC_ARCHS:-arm64 x86_64}"
  # The lowest macOS the app opens on (macos/Runner.xcodeproj MACOSX_DEPLOYMENT_TARGET, the Tauri app's 13.1): a
  # library built for the build machine's own macOS would be refused by an older one.
  export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.1}"
  slices=""
  for arch in $archs; do
    case "$arch" in
      arm64) target=aarch64-apple-darwin ;;
      x86_64) target=x86_64-apple-darwin ;;
      *) echo "build-native: no Mac architecture named $arch" >&2; exit 2 ;;
    esac
    if ! rustup target list --installed | grep -qx "$target"; then
      echo "build-native: rustup target add $target" >&2
      exit 1
    fi
    # Not stripped by cargo here (the release profile's `strip = true`): with a deployment target set, the proc
    # macros it builds for this Mac are stripped too, and macOS 27's loader refuses what Xcode 27's strip leaves
    # of them ("mis-aligned LINKEDIT string pool"), so every crate with a derive fails as "can't find crate".
    # The joined library is stripped below instead, and only if it still opens.
    (cd "$crate" && cargo build -j "$jobs" --release --target "$target" --config 'profile.release.strip=false' ${voice:+--features voice})
    slices="$slices $CARGO_TARGET_DIR/$target/release/libghost_core.dylib"
  done
  out="$root/macos/Core"
  mkdir -p "$out"
  # shellcheck disable=SC2086
  lipo -create $slices -output "$out/libghost_core.dylib.part"
  install_name_tool -id "@rpath/libghost_core.dylib" "$out/libghost_core.dylib.part" 2>/dev/null
  # Its local symbols taken off, kept only if the loader still takes the result.
  cp "$out/libghost_core.dylib.part" "$out/libghost_core.dylib.stripped"
  if strip -x "$out/libghost_core.dylib.stripped" 2>/dev/null && python3 -c 'import ctypes, sys; ctypes.CDLL(sys.argv[1]).ghost_invoke' "$out/libghost_core.dylib.stripped" 2>/dev/null; then
    mv -f "$out/libghost_core.dylib.stripped" "$out/libghost_core.dylib.part"
  else
    rm -f "$out/libghost_core.dylib.stripped"
    echo "build-native: left unstripped (the stripped library would not open)"
  fi
  for symbol in ghost_alloc ghost_invoke ghost_free ghost_set_listener ghost_forget_listener ${voice:+ghost_capture_push}; do
    nm -gU "$out/libghost_core.dylib.part" 2>/dev/null | grep -qw "_$symbol" || { echo "build-native: $symbol is not exported." >&2; exit 1; }
  done
  mv -f "$out/libghost_core.dylib.part" "$out/libghost_core.dylib"
  echo "build-native: $out/libghost_core.dylib ($(lipo -archs "$out/libghost_core.dylib"), $(wc -c < "$out/libghost_core.dylib" | tr -d ' ') bytes${voice:+, with the engines})"
}

case "$what" in
  test) run_tests ;;
  mac) build_mac ;;
  host) build_host ;;
  android) build_android ;;
  all) run_tests; build_host; build_android ;;
  *) echo "usage: tool/build-native.sh [test|host|android|mac|all]" >&2; exit 2 ;;
esac

cat <<'SAID'

To run it:
  flutter test --no-pub test/native test/capture_native test/ai_native   # Dart over the Mac's library (needs: host)
  flutter build apk --debug --target-platform android-arm64     # packs jniLibs/arm64-v8a/libghost_core.so (needs: android)
  flutter build macos --debug                                   # bundles macos/Core/libghost_core.dylib (needs: mac)
SAID
