#!/bin/sh
# The Mac build that replaces Ghost.md's Tauri Mac app (docs/CUTOVER.md, section 7): tool/cutover-build.sh's twin.
# The two halves of the one switch, given together. Xcode's (GHOST_CUTOVER=1 in the build's environment: the name
# Ghost.md and the id com.mattssoftware.glyph; macos/Runner/Configs/AppInfo.xcconfig) and Dart's
# (GHOST_CUTOVER=true: on its first launch the app copies what the Tauri app kept into its own folder;
# lib/carry/mac_carry.dart). A release build is on the real service by itself, as the phone's is.
#
#   tool/cutover-build-mac.sh 2.0.3      # build/release-mac/Ghost.md.app, universal (Apple silicon and Intel)
#
# The app it leaves is signed ad hoc, as every local build is: it is NOT signed with a Developer ID, not
# notarised, and nothing is published. scripts/deploy-flutter-mac.mjs --prepare does those, for whoever publishes.
#
# UPDATES (since 2026-10-24): the app updates itself, as the phone's does (lib/core/updates.dart `UpdateKind.mac`,
# macos/Runner/UpdatesChannel.swift). Told nothing, GHOST_CUTOVER=true makes it look where the phone looks
# (https://attack.fm/glyph, the box's release folder, which ghostmarkdown.com also serves), for `mac.json`, and
# scripts/deploy-flutter-mac.mjs --prepare writes that with the zip it names. A version reaching a Mac with no
# updater yet (2.3.15 and before) is still a download, installed by hand once.
#
# THE BUILD NUMBER is how the updater, like macOS, tells a newer build: CFBundleVersion is made as the phone's
# version code is, 2.3.16 is 2003016, so it rises with every version, and this refuses an app that says another.
#
# The Rust core is built first (tool/build-native.sh mac, both kinds of Mac): Xcode copies whatever
# macos/Core/libghost_core.dylib is there, and a stale one would be shipped as found (the core reads the update's
# description, `update_read`; one from before 2.3.16 cannot read the Mac's). GHOST_KEEP_CORE=1 skips it, for a
# build made a moment after one.
set -eu
version="${1:?the version, three numbers above 1.15.0: tool/cutover-build-mac.sh 2.0.3}"
shift
major="${version%%.*}"
rest="${version#*.}"
minor="${rest%%.*}"
patch="${rest#*.}"
case "$major$minor$patch" in
  *[!0-9]* | "") echo "error: the version is three numbers (2.0.3), not $version." >&2; exit 2 ;;
esac
[ "$version" = "$major.$minor.$patch" ] || { echo "error: the version is three numbers (2.0.3), not $version." >&2; exit 2; }
# The number macOS compares builds by, made as the phone's version code is: 2.0.3 is 2000003. The Tauri Mac app's
# last (1.15.0) is below anything that begins with 2.
code=$((major * 1000000 + minor * 1000 + patch))
[ "$code" -gt 1015000 ] || { echo "error: $version is not above the Tauri app's 1.15.0." >&2; exit 2; }

cd "$(dirname "$0")/.."
[ "${GHOST_KEEP_CORE:-}" = 1 ] || tool/build-native.sh mac
GHOST_CUTOVER=1 flutter build macos --release --no-pub \
  --build-name="$version" \
  --build-number="$code" \
  --dart-define=GHOST_CUTOVER=true \
  --dart-define=GHOST_VERSION="$version" \
  --dart-define=GHOST_BUILD="$(date -u +%Y%m%d%H%M%S)" \
  --dart-define=GHOST_COMMIT="$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- . 2>/dev/null || echo +)" \
  "$@"

built="build/macos/Build/Products/Release/Ghost.md.app"
[ -d "$built" ] || { echo "error: the build left no $built." >&2; exit 1; }
out="build/release-mac"
rm -rf "$out/Ghost.md.app"
mkdir -p "$out"
ditto "$built" "$out/Ghost.md.app"
app="$out/Ghost.md.app"

# What was built is what was asked for, or this stops: the id, the version, and both kinds of Mac in every binary
# of the bundle, the Rust core included (a universal app with an Apple silicon core alone opens on an Intel Mac and
# finds no library).
plist="$app/Contents/Info.plist"
id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
said="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
[ "$id" = "com.mattssoftware.glyph" ] || { echo "error: the app's id is $id." >&2; exit 1; }
[ "$said" = "$version" ] || { echo "error: the app says version $said." >&2; exit 1; }
[ "$build" = "$code" ] || { echo "error: the app says build $build, not $code: the updater would not take it for $version." >&2; exit 1; }
failed=0
for binary in "$app/Contents/MacOS/Ghost.md" "$app/Contents/Frameworks/libghost_core.dylib" "$app"/Contents/Frameworks/*.framework/Versions/A/*; do
  [ -f "$binary" ] || continue
  file -b "$binary" | grep -q "Mach-O" || continue
  archs="$(lipo -archs "$binary")"
  case " $archs " in
    *" arm64 "*) ;;
    *) echo "error: ${binary#"$app"/} is built for $archs: no arm64." >&2; failed=1 ;;
  esac
  case " $archs " in
    *" x86_64 "*) ;;
    *) echo "error: ${binary#"$app"/} is built for $archs: no x86_64." >&2; failed=1 ;;
  esac
  echo "  ${binary#"$app"/}: $archs"
done
[ "$failed" = 0 ] || exit 1
[ -f "$app/Contents/Frameworks/libghost_core.dylib" ] || { echo "error: the app has no Rust core in it." >&2; exit 1; }
echo "$app: Ghost.md $version ($code), $id, universal. Signed ad hoc; not notarised; nothing published."
