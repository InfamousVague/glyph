#!/bin/sh
# Xcode's "Find the core" phase (ios/Runner.xcodeproj): the Rust core an iPhone build links is
# ios/Core/GhostCore.xcframework, tool/build-native.sh ios's (not in git, as the phone's jniLibs and the Mac's
# macos/Core are not). A build with none there, or with none for what is being built (a phone's without the
# simulator's, or the other way), stops here and says so, rather than failing later on five missing symbols.
set -eu

core="$SRCROOT/Core/GhostCore.xcframework"
case "${PLATFORM_NAME:-}" in
  iphonesimulator) slice="ios-arm64-simulator" ;;
  *) slice="ios-arm64" ;;
esac
if [ ! -f "$core/$slice/libghost_core.a" ]; then
  echo "error: no ios/Core/GhostCore.xcframework/$slice: run tool/build-native.sh ios first." >&2
  exit 1
fi
