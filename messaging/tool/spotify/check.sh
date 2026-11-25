#!/bin/sh
# Checks the music link without a sound (tool/spotify/check.swift says how). Needs the WebRTC framework a macOS build
# has fetched: WEBRTC=<folder holding WebRTC.framework>, or it is looked for under build/macos.
set -e
here=$(cd "$(dirname "$0")/../.." && pwd)
fw=${WEBRTC:-$(find "$here/build/macos/SourcePackages/artifacts" -type d -path '*macos-arm64_x86_64' 2>/dev/null | head -1)}
[ -d "$fw/WebRTC.framework" ] || fw="$here/build/spotify/webrtc"
[ -d "$fw/WebRTC.framework" ] || { echo "no WebRTC.framework: set WEBRTC to the folder it is in"; exit 2; }
out="$here/build/spotify"
mkdir -p "$out/check"
cp "$here/tool/spotify/check.swift" "$out/check/main.swift"
swiftc -swift-version 5 -O -target arm64-apple-macos12.0 -F "$fw" -framework WebRTC -Xlinker -rpath -Xlinker "$fw" "$here/macos/Runner/MusicLink.swift" "$out/check/main.swift" -o "$out/music-check"
if [ -n "$1" ]; then exec "$out/music-check" "$1"; fi
echo "--- as it is (must pass)"; "$out/music-check" right
echo "--- swapped (must fail)"; if "$out/music-check" swapped; then echo "the check did not notice the sides were swapped"; exit 1; fi
echo "--- cut (must fail)"; if "$out/music-check" cut; then echo "the check did not notice there was no music"; exit 1; fi
echo "all three did as they should"
