#!/bin/sh
# The build that replaces Ghost.md's Tauri app (docs/CUTOVER.md): the two halves of the one switch, which have to be
# given together. Gradle's (GHOST_CUTOVER=1: the id com.mattssoftware.glyph, the name, the version code, the
# Tauri activity's name; android/app/build.gradle.kts) and Dart's (GHOST_CUTOVER=true: updates looked for where the
# Tauri app's installs look; lib/core/updates.dart). A release build is on the real service by itself.
#
#   tool/cutover-build.sh 2.0.0            # a release APK, signed from ~/.config/glyph/android-signing.properties
#   tool/cutover-build.sh 2.0.0 --debug    # a debug one, for an emulator: no account, no updates
#   tool/cutover-build.sh 2.4.25 --play    # Google Play's: a release App Bundle at build/play/ghost-md-2.4.25.aab
#
# GOOGLE PLAY'S BUILD (--play; docs/store/play/README.md) is this release build as an App Bundle, signed with the same
# key (Play App Signing's upload key), with a third half to the switch: GHOST_STORE=play for Gradle (the manifest of
# android/app/src/play/ over the release one: no REQUEST_INSTALL_PACKAGES, no installer FileProvider) and
# --dart-define=GHOST_STORE=play for Dart (lib/core/updates.dart `playStoreBuild`: no update check, no update
# anywhere on screen; About says Google Play updates the app). No watch app: the watch is a Play release of its own.
# Signed with Play's upload key (~/.config/glyph/play-signing.properties), not the sideload APK's.
# Without --play nothing of this is given, and the APK is exactly as it was.
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
play=0
[ "${1:-}" = "--play" ] && [ "$mode" = "--release" ] && play=1 && shift
cd "$(dirname "$0")/.."
# The What's new card after an update says this version's changes (lib/changelog): no entry, no release. A debug
# build for an emulator is no release, and is built whatever its version.
if [ "$mode" = "--release" ]; then tool/changelog_check.sh "$version"; fi
# The anonymous usage stats' project key and host (tool/posthog-defines.sh), for a release only: a debug build sends
# nothing.
posthog=""
if [ "$mode" = "--release" ]; then . tool/posthog-defines.sh; fi
artifact="apk"
store=""
if [ "$play" = "1" ]; then
  artifact="appbundle"
  store="--dart-define=GHOST_STORE=play"
  export GHOST_STORE=play GHOST_WEAR=0
  # Signed with Play's UPLOAD key, registered with Play App Signing on 2026-10-05, not the sideload key (whose
  # certificate reads CN=Android Debug, which Play refuses as a debug build). GLYPH_ANDROID_SIGNING names another.
  export GLYPH_ANDROID_SIGNING="${GLYPH_ANDROID_SIGNING:-$HOME/.config/glyph/play-signing.properties}"
  [ -f "$GLYPH_ANDROID_SIGNING" ] || { echo "No Play upload key's signing file at $GLYPH_ANDROID_SIGNING." >&2; exit 1; }
fi
# arm64 alone in both: the core (libghost_core.so, tool/build-native.sh android) is built for nothing else, so Play
# offers the bundle to arm64 phones only.
GHOST_CUTOVER=1 GHOST_WEAR="${GHOST_WEAR:-1}" flutter build "$artifact" "$mode" --no-pub --target-platform android-arm64 \
  --build-name="$version" \
  --dart-define=GHOST_CUTOVER=true \
  $store \
  --dart-define=GHOST_VERSION="$version" \
  --dart-define=GHOST_BUILD="$(date -u +%Y%m%d%H%M%S)" \
  --dart-define=GHOST_COMMIT="$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- . 2>/dev/null || echo +)" \
  $posthog \
  "$@"
if [ "$play" = "1" ]; then
  mkdir -p build/play
  cp build/app/outputs/bundle/release/app-release.aab "build/play/ghost-md-$version.aab"
  echo "Google Play's bundle: build/play/ghost-md-$version.aab"
  exit 0
fi
kind="${mode#--}"
wear="build/wear/outputs/apk/$kind/wear-$kind.apk"
if [ "${GHOST_WEAR:-1}" = "1" ] && [ -f "$wear" ]; then echo "The watch app: $wear"; fi
