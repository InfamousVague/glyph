#!/bin/sh
# The build that replaces Ghost.md's Tauri app (docs/CUTOVER.md): the two halves of the one switch, which have to be
# given together. Gradle's (GHOST_CUTOVER=1: the id com.mattssoftware.glyph, the name, the version code, the
# Tauri activity's name; android/app/build.gradle.kts) and Dart's (GHOST_CUTOVER=true: updates looked for where the
# Tauri app's installs look; lib/core/updates.dart). A release build is on the real service by itself.
#
#   tool/cutover-build.sh 2.0.0            # a release APK, signed from ~/.config/glyph/android-signing.properties
#   tool/cutover-build.sh 2.0.0 --debug    # a debug one, for an emulator: no account, no updates
#
# It builds and publishes nothing else. tool/release_apk.mjs writes what is uploaded.
set -eu
version="${1:?the version, three numbers above 1.15.0: tool/cutover-build.sh 2.0.0}"
shift
mode="--release"
[ "${1:-}" = "--debug" ] && mode="--debug" && shift
cd "$(dirname "$0")/.."
GHOST_CUTOVER=1 exec flutter build apk "$mode" --no-pub --target-platform android-arm64 \
  --build-name="$version" \
  --dart-define=GHOST_CUTOVER=true \
  --dart-define=GHOST_BUILD="$(date -u +%Y%m%d%H%M%S)" \
  "$@"
