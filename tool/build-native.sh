#!/bin/sh
# Builds the Rust core (native/, docs/STAGE3.md): its tests, the Mac's library that Dart's tests open, and the
# phone's libghost_core.so, copied to where Gradle packs it.
#
#   tool/build-native.sh            all three
#   tool/build-native.sh test       cargo test on the Mac
#   tool/build-native.sh host       native/target/debug/libghost_core.dylib, for `flutter test test/native`
#   tool/build-native.sh android    android/app/src/main/jniLibs/arm64-v8a/libghost_core.so (release)
#
# The crate includes its library from ../glyph/src-tauri/src by path and builds nothing there: cargo's target
# directory is native/target, whatever CARGO_TARGET_DIR says outside. A deploy of the Tauri app runs tests that
# fail when the Mac is busy, so this waits for one to end before it compiles.
#
# The phone's .so: arm64 only (the Fold), API 24, and LOAD segments aligned to 16 KB, which Android 15 and
# later ask of every library on a 16 KB-page device. NDK 28.x when there is one, else the newest.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
crate="$root/native"
export CARGO_TARGET_DIR="$crate/target"
what="${1:-all}"

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
  (cd "$crate" && cargo test --features test-hooks)
}

build_host() {
  wait_for_deploys
  # With the test hooks: a `test_panic` command for test/native. The phone's library has none.
  (cd "$crate" && cargo build --features test-hooks)
  echo "build-native: $CARGO_TARGET_DIR/debug/libghost_core.dylib"
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
  export CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS="-C link-arg=-Wl,-z,max-page-size=16384"
  (cd "$crate" && cargo build --release --target "$target")
  built="$CARGO_TARGET_DIR/$target/release/libghost_core.so"
  out="$root/android/app/src/main/jniLibs/arm64-v8a"
  mkdir -p "$out"
  cp "$built" "$out/libghost_core.so"
  echo "build-native: NDK $(basename "$ndk"), API $api"
  "$bin/llvm-readelf" -lW "$out/libghost_core.so" | awk '$1 == "LOAD" { print "build-native: LOAD align " $NF; if ($NF != "0x4000") bad = 1 } END { exit bad }' || {
    echo "build-native: a LOAD segment is not 16 KB aligned." >&2
    exit 1
  }
  for symbol in ghost_alloc ghost_invoke ghost_free ghost_set_listener; do
    "$bin/llvm-readelf" --dyn-syms -W "$out/libghost_core.so" | grep -qw "$symbol" || { echo "build-native: $symbol is not exported." >&2; exit 1; }
  done
  echo "build-native: $out/libghost_core.so ($(wc -c < "$out/libghost_core.so" | tr -d ' ') bytes)"
}

case "$what" in
  test) run_tests ;;
  host) build_host ;;
  android) build_android ;;
  all) run_tests; build_host; build_android ;;
  *) echo "usage: tool/build-native.sh [test|host|android|all]" >&2; exit 2 ;;
esac

cat <<'SAID'

To run it:
  flutter test --no-pub test/native                             # Dart over the Mac's library (needs: host)
  flutter build apk --debug --target-platform android-arm64     # packs jniLibs/arm64-v8a/libghost_core.so (needs: android)
SAID
