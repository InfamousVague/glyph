#!/bin/sh
# Builds Ghost.md's core for the browser (native/web, docs/WEB.md): crypto.rs, crdt.rs and the library's note names,
# compiled for wasm32-wasip1 and copied to web/core/ghost_core_web.wasm, where `flutter build web` takes it into
# build/web/core/. The file is ignored, as the phone's libghost_core.so is: built from the tree, never kept.
#
#   tool/build-web-core.sh          the release build, copied
#   tool/build-web-core.sh check    node tool/web_core_vectors.mjs after it: the browser's core opens what the web
#                                   app sealed, at the real rounds, and names notes as the phone's library does
#
# Needs the target once: `rustup target add wasm32-wasip1`. Seconds, not minutes: none of the engines, no SQLite.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
crate="$root/native/web"
export CARGO_TARGET_DIR="$crate/target"

cores="$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
jobs=$((cores / 2))
[ "$jobs" -ge 1 ] || jobs=1

(cd "$crate" && cargo build --release --target wasm32-wasip1 -j "${GHOST_JOBS:-$jobs}")
mkdir -p "$root/web/core"
cp "$crate/target/wasm32-wasip1/release/ghost_core_web.wasm" "$root/web/core/ghost_core_web.wasm"
echo "web/core/ghost_core_web.wasm: $(wc -c < "$root/web/core/ghost_core_web.wasm" | tr -d ' ') bytes"

if [ "${1:-}" = "check" ]; then
  node "$root/tool/web_core_vectors.mjs"
fi
