#!/bin/sh
# The build that replaces Ghost.md's Tauri app (docs/CUTOVER.md): the two halves of the one switch, which have to be
# given together. Gradle's (GHOST_CUTOVER=1: the id com.mattssoftware.glyph, the name, the version code, the
# Tauri activity's name; android/app/build.gradle.kts) and Dart's (GHOST_CUTOVER=true: updates looked for where the
# Tauri app's installs look; lib/core/updates.dart). A release build is on the real service by itself.
#
#   tool/cutover-build.sh 2.0.0            # a release APK, signed from ~/.config/glyph/android-signing.properties
#   tool/cutover-build.sh 2.0.0 --debug    # a debug one, for an emulator: no account, no updates
#
# It builds and publishes nothing else. tool/release_apk.mjs writes what is uploaded. It stops before building where
# assets/changelog.json has no entry for the version (tool/changelog_check.sh), which the What's new card reads.
#
# THE WATCH APP comes out of the same Gradle run (android/wear; docs/WATCH.md): build/wear/outputs/apk/release/
# wear-release.apk, with the phone's id and signed with the phone's key, which the Data Layer needs to pair the two.
# It is installed on the watch by hand (docs/WATCH.md, "Installing it") and is not uploaded. GHOST_WEAR=0 leaves it out.
set -eu
version="${1:?the version, three numbers above 1.15.0: tool/cutover-build.sh 2.0.0}"
shift
mode="--release"
[ "${1:-}" = "--debug" ] && mode="--debug" && shift
cd "$(dirname "$0")/.."
# The What's new card after an update says this version's changes (lib/changelog): no entry, no release. A debug
# build for an emulator is no release, and is built whatever its version.
if [ "$mode" = "--release" ]; then tool/changelog_check.sh "$version"; fi
GHOST_CUTOVER=1 GHOST_WEAR="${GHOST_WEAR:-1}" flutter build apk "$mode" --no-pub --target-platform android-arm64 \
  --build-name="$version" \
  --dart-define=GHOST_CUTOVER=true \
  --dart-define=GHOST_VERSION="$version" \
  --dart-define=GHOST_BUILD="$(date -u +%Y%m%d%H%M%S)" \
  --dart-define=GHOST_COMMIT="$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- . 2>/dev/null || echo +)" \
  "$@"
kind="${mode#--}"
wear="build/wear/outputs/apk/$kind/wear-$kind.apk"
if [ "${GHOST_WEAR:-1}" = "1" ] && [ -f "$wear" ]; then echo "The watch app: $wear"; fi
