#!/bin/sh
# The Mac build for the Mac App Store (docs/CUTOVER.md, section 9): tool/cutover-build-mac.sh's twin for the store,
# as tool/cutover-build-ios.sh is the iPhone's. The same app record (Ghost Markdown, 6818598896) and the same
# bundle id, com.mattssoftware.glyph, so one purchase covers both.
#
#   tool/cutover-build-mac-store.sh 2.0.5             # build/mac-store/Ghost.md-2.0.5-2000005.pkg, signed for the store
#   tool/cutover-build-mac-store.sh 2.0.5 --build 2   # the same version uploaded again: build 2000005.2
#   tool/cutover-build-mac-store.sh 2.0.5 --proof --api http://127.0.0.1:<port>/api
#                                                     # build/mac-store/proof/Ghost.md.app: the same release build
#                                                     # to RUN on this Mac, under the same sandbox (see below)
#   tool/cutover-build-mac-store.sh 2.0.5 --tour --api http://127.0.0.1:<port>/api
#                                                     # build/mac-store/tour/Ghost.md.app: a debug build of it, which
#                                                     # can be walked from inside (lib/shell/desktop/mac_tour.dart)
#
# IT UPLOADS NOTHING. The package it leaves is the last step here: sending it to App Store Connect is somebody's
# decision and somebody's command (docs/CUTOVER.md, section 9, "To publish").
#
# WHAT DIFFERS FROM THE BUILD ON THE WEBSITE (tool/cutover-build-mac.sh, which this does not change in any way: the
# Xcode project, its Info.plist and its entitlements are the same files, and everything below is done to a copy of
# what Xcode built):
#
# - It is SANDBOXED, which the store requires: signed with macos/Runner/Store.entitlements, which says what each
#   entitlement is for. Its files are then in its own container, ~/Library/Containers/com.mattssoftware.glyph/Data.
# - Dart is told `GHOST_MAC_STORE=true` (lib/core/mac_app.dart `macAppStore`) and NOT `GHOST_CUTOVER=true`: it
#   carries nothing from the app on the website (a sandboxed app cannot read that app's folder or its Keychain
#   items) and starts as a new install; About says its updates are the App Store's; Settings has no Backup page
#   and About offers no Guide book. Xcode is still told GHOST_CUTOVER=1, which is only the name and the id.
# - The Info.plist is given `ITSAppUsesNonExemptEncryption` false, for the reason beside the iPhone's
#   (ios/Runner/Info.plist; Matt, 2026-10-13: standard algorithms only, none proprietary, not sold in France), and
#   the app is given a privacy manifest (macos/Runner/PrivacyInfo.xcprivacy).
# - It is signed with the hardened runtime by the team's distribution certificate ("Apple Distribution"), and
#   packed by productbuild into a package signed by the team's installer certificate ("3rd Party Mac Developer
#   Installer"), which is how a Mac app is sent to the store. Not a Developer ID, not notarised: the store signs
#   what it sells.
#
# THE LOOK is the Mac's own, as the website's build has it: no GHOST_PLAIN. Matt chose the plain look for the
# iPhone for frame rates measured on a phone; a Mac draws its own strip and fade at a page's edges, not the phone's
# smoke, and nobody measured it wanting.
#
# THE VERSION AND THE BUILD NUMBER are the iPhone's scheme: 2.0.5 is build 2000005, and `--build 2` gives
# 2000005.2. A platform's builds are numbered apart from another's on the same record, and the Mac has none yet.
#
# --proof AND --tour make something that can be STARTED on this Mac, which the store's package cannot be (macOS
# will not run an app signed for the store that did not come from it). They are the same source and the same
# entitlements, and differ in exactly this, on purpose:
#   - the bundle id is com.mattssoftware.glyph.storeproof, so the container, the preferences and the Keychain
#     service are not the real app's (~/Library/Containers/com.mattssoftware.glyph.storeproof);
#   - `ghostmd:` is taken out of its Info.plist, so it can never be handed a link meant for the real app;
#   - it is signed ad hoc, with the same entitlements file (--tour adds cs.allow-jit and
#     cs.disable-library-validation, which a debug build's Dart needs and no release has);
#   - it is told a local service (tool/local-server.sh) with --api, where the store's build names none and is on
#     the real one by itself. Without --api it is given an address nothing listens on, so it can never sign in to
#     the real service by accident. It is told the same dead address for the speech and language models
#     (GHOST_MODELS), so it downloads none from the real mirrors.
set -eu
version="${1:?the version, three numbers: tool/cutover-build-mac-store.sh 2.0.5}"
shift
again=""
proof=""
tour=""
api=""
while [ $# -gt 0 ]; do
  case "$1" in
    --build) again="${2:?--build takes a number}"; shift 2 ;;
    --proof) proof=1; shift ;;
    --tour) tour=1; shift ;;
    --api) api="${2:?--api takes an address}"; shift 2 ;;
    *) break ;;
  esac
done
major="${version%%.*}"
rest="${version#*.}"
minor="${rest%%.*}"
patch="${rest#*.}"
case "$major$minor$patch$again" in
  *[!0-9]* | "") echo "error: the version is three numbers (2.0.5), not $version." >&2; exit 2 ;;
esac
[ "$version" = "$major.$minor.$patch" ] || { echo "error: the version is three numbers (2.0.5), not $version." >&2; exit 2; }
code=$((major * 1000000 + minor * 1000 + patch))
[ "$code" -gt 1015000 ] || { echo "error: $version is not above the Tauri app's 1.15.0." >&2; exit 2; }
build="$code${again:+.$again}"
[ -z "$proof" ] || [ -z "$tour" ] || { echo "error: --proof or --tour, not both." >&2; exit 2; }
local_run="$proof$tour"
if [ -n "$local_run" ]; then
  case "$api" in
    http://127.0.0.1:*/api | http://localhost:*/api) ;;
    # Nothing listens on port 9 of this Mac: a build told nothing must still never reach the real service.
    "") api="http://127.0.0.1:9/api" ;;
    *) echo "error: a build to run here is given a local service (http://127.0.0.1:<port>/api) or none, not $api." >&2; exit 2 ;;
  esac
else
  [ -z "$api" ] || { echo "error: the store's build is on the real service by itself; --api is --proof's and --tour's." >&2; exit 2; }
fi

cd "$(dirname "$0")/.."
root="$PWD"
stamp="$(date -u +%Y%m%d%H%M%S)"
commit="$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- . 2>/dev/null || echo +)"
out="$root/build/mac-store"
mkdir -p "$out"
entitlements="$root/macos/Runner/Store.entitlements"
manifest="$root/macos/Runner/PrivacyInfo.xcprivacy"
[ -f "$entitlements" ] && [ -f "$manifest" ] || { echo "error: macos/Runner/Store.entitlements or PrivacyInfo.xcprivacy is missing." >&2; exit 1; }

# The core, for both kinds of Mac in one file (macos/Core/libghost_core.dylib, which Xcode's "Bundle the core"
# phase copies into the app).
tool/build-native.sh mac

mode="--release"
config="Release"
[ -z "$tour" ] || { mode="--debug"; config="Debug"; }
GHOST_CUTOVER=1 flutter build macos $mode --no-pub \
  --build-name="$version" \
  --build-number="$build" \
  --dart-define=GHOST_MAC_STORE=true \
  --dart-define=GHOST_VERSION="$version" \
  --dart-define=GHOST_BUILD="$stamp" \
  --dart-define=GHOST_COMMIT="$commit" \
  ${api:+--dart-define=GHOST_API="$api"} \
  ${local_run:+--dart-define=GHOST_MODELS=http://127.0.0.1:9} \
  "$@"

built="build/macos/Build/Products/$config/Ghost.md.app"
[ -d "$built" ] || { echo "error: the build left no $built." >&2; exit 1; }
if [ -n "$proof" ]; then dir="$out/proof"; elif [ -n "$tour" ]; then dir="$out/tour"; else dir="$out"; fi
app="$dir/Ghost.md.app"
rm -rf "$app"
mkdir -p "$dir"
ditto "$built" "$app"
plist="$app/Contents/Info.plist"
buddy() { /usr/libexec/PlistBuddy -c "$1" "$plist"; }
value() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || true; }

# What the store's copy says of itself that the website's does not: the export answer, and the privacy manifest.
buddy 'Delete :ITSAppUsesNonExemptEncryption' >/dev/null 2>&1 || true
buddy 'Add :ITSAppUsesNonExemptEncryption bool false'
cp "$manifest" "$app/Contents/Resources/PrivacyInfo.xcprivacy"

wanted_id="com.mattssoftware.glyph"
if [ -n "$local_run" ]; then
  wanted_id="com.mattssoftware.glyph.storeproof"
  buddy "Set :CFBundleIdentifier $wanted_id"
  buddy 'Delete :CFBundleURLTypes'
fi

# Every binary in the bundle, innermost first, then the app around them with the sandbox's entitlements.
if [ -n "$local_run" ]; then
  identity="-"
  signed_with="$entitlements"
  if [ -n "$tour" ]; then
    signed_with="$dir/TourStore.entitlements"
    cp "$entitlements" "$signed_with"
    /usr/libexec/PlistBuddy -c 'Add :com.apple.security.cs.allow-jit bool true' -c 'Add :com.apple.security.cs.disable-library-validation bool true' "$signed_with"
  fi
  sign() { codesign --force --sign - "$@"; }
else
  identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Distribution: .*(F6ZAL7ANAD)\)".*/\1/p' | head -1)"
  installer="$(security find-identity -v | sed -n 's/.*"\(3rd Party Mac Developer Installer: .*(F6ZAL7ANAD)\)".*/\1/p' | head -1)"
  [ -n "$identity" ] || { echo "error: no \"Apple Distribution\" certificate of the team's in the Keychain." >&2; exit 1; }
  [ -n "$installer" ] || { echo "error: no \"3rd Party Mac Developer Installer\" certificate of the team's in the Keychain." >&2; exit 1; }
  signed_with="$entitlements"
  sign() { codesign --force --sign "$identity" --options runtime --timestamp "$@"; }
fi
for inner in "$app"/Contents/Frameworks/*.dylib "$app"/Contents/Frameworks/*.framework; do
  [ -e "$inner" ] || continue
  sign "$inner" 2>/dev/null || { echo "error: could not sign ${inner#"$app"/}." >&2; exit 1; }
done
sign --entitlements "$signed_with" "$app" 2>/dev/null || { echo "error: could not sign the app." >&2; exit 1; }
codesign --verify --deep --strict "$app" || { echo "error: the signed app does not verify." >&2; exit 1; }

# What was built is what was asked for, or this stops.
failed=0
check() { [ "$2" = "$3" ] || { echo "error: $1 is \"$2\", not \"$3\"." >&2; failed=1; }; }
check "the id" "$(value CFBundleIdentifier)" "$wanted_id"
check "the name" "$(value CFBundleDisplayName)" "Ghost.md"
check "the version" "$(value CFBundleShortVersionString)" "$version"
check "the build" "$(value CFBundleVersion)" "$build"
check "the category" "$(value LSApplicationCategoryType)" "public.app-category.productivity"
check "the export-compliance answer" "$(value ITSAppUsesNonExemptEncryption)" "false"
[ -n "$(value LSMinimumSystemVersion)" ] || { echo "error: no minimum macOS." >&2; failed=1; }
[ -n "$(value NSMicrophoneUsageDescription)" ] || { echo "error: no microphone sentence in an app that records." >&2; failed=1; }
[ -f "$app/Contents/Resources/PrivacyInfo.xcprivacy" ] || { echo "error: no privacy manifest in the app." >&2; failed=1; }
[ -f "$app/Contents/Frameworks/libghost_core.dylib" ] || { echo "error: the app has no Rust core in it." >&2; failed=1; }
if [ -z "$local_run" ]; then check "the link scheme" "$(value CFBundleURLTypes:0:CFBundleURLSchemes:0)" "ghostmd"; fi
has="$(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -convert json -o - - 2>/dev/null || echo '{}')"
for key in com.apple.security.app-sandbox com.apple.security.network.client com.apple.security.device.audio-input com.apple.security.files.user-selected.read-write com.apple.security.files.bookmarks.app-scope; do
  case "$has" in *"\"$key\":true"*) ;; *) echo "error: the app is not signed with $key." >&2; failed=1 ;; esac
done
if [ -z "$tour" ]; then
  # A release has exactly those five, and nothing that loosens the hardened runtime.
  count="$(printf '%s' "$has" | tr ',' '\n' | grep -c 'com\.apple\.' || true)"
  check "the number of entitlements" "$count" "5"
  # Both kinds of Mac in every binary of the bundle, the core included.
  for binary in "$app/Contents/MacOS/Ghost.md" "$app/Contents/Frameworks/libghost_core.dylib" "$app"/Contents/Frameworks/*.framework/Versions/A/*; do
    [ -f "$binary" ] || continue
    file -b "$binary" | grep -q "Mach-O" || continue
    archs="$(lipo -archs "$binary")"
    case " $archs " in *" arm64 "*) ;; *) echo "error: ${binary#"$app"/} is built for $archs: no arm64." >&2; failed=1 ;; esac
    case " $archs " in *" x86_64 "*) ;; *) echo "error: ${binary#"$app"/} is built for $archs: no x86_64." >&2; failed=1 ;; esac
    echo "  ${binary#"$app"/}: $archs"
  done
  # The store's build says it is one, and names no service: the compiled Dart holds the store's sentence and, in
  # the package for the store, no local address.
  strings -a "$app/Contents/Frameworks/App.framework/Versions/A/App" | grep -q "Ghost.md updates through the App Store." || { echo "error: the compiled app does not hold the App Store's sentence." >&2; failed=1; }
fi
[ "$failed" = 0 ] || exit 1

if [ -n "$local_run" ]; then
  echo "$app"
  echo "  Ghost.md $version ($build), $wanted_id, a $config build to run here under the store's sandbox, on $api"
  echo "  signed ad hoc with $(basename "$signed_with"); ghostmd: not claimed. Not for the store."
  exit 0
fi

signed="$(codesign -dvv "$app" 2>&1 || true)"
authority="$(printf '%s\n' "$signed" | sed -n 's/^Authority=//p' | head -1)"
case "$authority" in
  "Apple Distribution: "*"(F6ZAL7ANAD)") ;;
  *) echo "error: signed by \"$authority\", not the team's distribution certificate." >&2; exit 1 ;;
esac
printf '%s\n' "$signed" | grep -q 'flags=.*runtime' || { echo "error: the app is not signed with the hardened runtime." >&2; exit 1; }
if strings -a "$app/Contents/Frameworks/App.framework/Versions/A/App" | grep -qE 'http://(127\.0\.0\.1|localhost):[0-9]+/api'; then
  echo "error: the store's build names a local service." >&2; exit 1
fi

pkg="$out/Ghost.md-$version-$build.pkg"
rm -f "$pkg"
productbuild --component "$app" /Applications --sign "$installer" --timestamp "$pkg" >"$out/productbuild.log" 2>&1 || { tail -20 "$out/productbuild.log" >&2; echo "error: productbuild failed." >&2; exit 1; }
pkgutil --check-signature "$pkg" >"$out/pkg-signature.txt" 2>&1 || { cat "$out/pkg-signature.txt" >&2; echo "error: the package's signature does not check." >&2; exit 1; }
grep -q "3rd Party Mac Developer Installer: .*(F6ZAL7ANAD)" "$out/pkg-signature.txt" || { echo "error: the package is not signed by the team's installer certificate." >&2; exit 1; }
size="$(wc -c <"$pkg" | tr -d ' ')"
echo "$pkg"
echo "  Ghost.md $version ($build), com.mattssoftware.glyph, universal, macOS $(value LSMinimumSystemVersion) and later, $size bytes"
echo "  the app signed by $authority, sandboxed, hardened runtime; the package by $installer"
echo "  built $stamp from $commit. Not uploaded: nothing here sends it anywhere."
