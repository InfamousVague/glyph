#!/bin/sh
# The iPhone build that replaces Ghost.md's Tauri iPhone app in the App Store (docs/CUTOVER.md, section 8):
# tool/cutover-build.sh's and tool/cutover-build-mac.sh's twin. The two halves of the one switch, given together.
# Xcode's (GHOST_CUTOVER=1 in the build's environment: the name Ghost.md and the id com.mattssoftware.glyph;
# ios/Flutter/AppInfo.xcconfig) and Dart's (GHOST_CUTOVER=true: on its first launch the app copies what the Tauri
# app kept in the same container into a folder of its own; lib/carry/iphone_carry.dart). A release build is on the
# real service by itself, as the phone's and the Mac's are.
#
#   tool/cutover-build-ios.sh 2.0.5              # build/ios-store/Ghost.md-2.0.5-2000005.ipa, signed for the App Store
#   tool/cutover-build-ios.sh 2.0.5 --build 2    # the same version uploaded again: build 2000005.2
#   tool/cutover-build-ios.sh 2.0.5 --simulator --api http://127.0.0.1:<port>/api
#                                                # build/ios-store/simulator/Runner.app: a debug build for a
#                                                # simulator, with a local service (tool/local-server.sh). A
#                                                # simulator build is never a release, so it never names the real one.
#
# IT UPLOADS NOTHING. The IPA it leaves is signed with the team's distribution certificate and a store profile
# Xcode makes or fetches itself, and that is the last step here: sending it to App Store Connect is somebody's
# decision and somebody's command (docs/CUTOVER.md, section 8, "To publish").
#
# THE VERSION AND THE BUILD NUMBER. The store's record (Ghost Markdown, 6818598896) holds version 1.10.0 with the
# build "1.10.0". CFBundleVersion is one to three whole numbers with dots, compared number by number, and a new
# upload must be above every earlier one. This build's is made as the phone's version code and the Mac's build
# are: 2.0.5 is 2000005, one number, above 1.10.0 at its first number whatever follows. A second upload of the
# same version takes a second number after it (--build 2 gives 2000005.2), which is above 2000005 and below the
# next version's.
#
# SIGNING is automatic, by the team (F6ZAL7ANAD, the project's DEVELOPMENT_TEAM), with the suite's App Store
# Connect key handed to xcodebuild as -allowProvisioningUpdates and the three -authenticationKey flags: the way
# the Tauri build was signed (tauri/docs/store/APP_STORE.md). The key is named by ~/.config/mattssoftware/signing/
# asc-api.env (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH); nothing of it is printed. `flutter build ipa` cannot be
# handed a key, so Flutter writes the build's settings (`--config-only`) and xcodebuild archives and exports.
#
# THE LOOK. Matt chose this look for iPhone on 2026-10-13: the plain one with the slight blur behind the header
# (lib/app/plain.dart: GHOST_PLAIN=true and GHOST_BAR_BLUR=true; no smoke at a page's edges, no halo round the
# dock, each pane of glass its tint alone, and one small backdrop filter under the header). Both builds here are
# given it, so what a simulator shows is what the store's build draws; About's "This build" says "plain: no smoke
# or blur" on its Kind line (lib/core/build_facts.dart, which names the first define). `--full-look` leaves the
# two defines out.
set -eu
version="${1:?the version, three numbers above 1.10.0: tool/cutover-build-ios.sh 2.0.5}"
shift
again=""
simulator=""
api=""
look="--dart-define=GHOST_PLAIN=true --dart-define=GHOST_BAR_BLUR=true"
while [ $# -gt 0 ]; do
  case "$1" in
    --build) again="${2:?--build takes a number}"; shift 2 ;;
    --simulator) simulator=1; shift ;;
    --api) api="${2:?--api takes an address}"; shift 2 ;;
    --full-look) look=""; shift ;;
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
# The Tauri iPhone app's last is 1.10.0, as a number made the same way: 1010000.
code=$((major * 1000000 + minor * 1000 + patch))
[ "$code" -gt 1010000 ] || { echo "error: $version is not above the Tauri app's 1.10.0." >&2; exit 2; }
build="$code${again:+.$again}"

cd "$(dirname "$0")/.."
root="$PWD"
stamp="$(date -u +%Y%m%d%H%M%S)"
commit="$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- . 2>/dev/null || echo +)"
out="$root/build/ios-store"
mkdir -p "$out"

if [ -n "$simulator" ]; then
  case "$api" in
    http://127.0.0.1:*/api | http://localhost:*/api | "") ;;
    *) echo "error: a simulator build is given a local service (http://127.0.0.1:<port>/api) or none, not $api." >&2; exit 2 ;;
  esac
  tool/build-native.sh ios
  GHOST_CUTOVER=1 flutter build ios --simulator --debug --no-pub \
    --build-name="$version" --build-number="$build" \
    --dart-define=GHOST_CUTOVER=true \
    --dart-define=GHOST_VERSION="$version" \
    --dart-define=GHOST_BUILD="$stamp" \
    --dart-define=GHOST_COMMIT="$commit" \
    $look \
    ${api:+--dart-define=GHOST_API="$api"} \
    "$@"
  built="build/ios/iphonesimulator/Runner.app"
  [ -d "$built" ] || { echo "error: the build left no $built." >&2; exit 1; }
  rm -rf "$out/simulator"
  mkdir -p "$out/simulator"
  ditto "$built" "$out/simulator/Runner.app"
  id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$out/simulator/Runner.app/Info.plist")"
  [ "$id" = "com.mattssoftware.glyph" ] || { echo "error: the app's id is $id." >&2; exit 1; }
  echo "$out/simulator/Runner.app: Ghost.md $version ($build), $id, a debug build for a simulator${api:+, on $api}."
  exit 0
fi

[ -z "$api" ] || { echo "error: the store's build is on the real service by itself; --api is the simulator's." >&2; exit 2; }
keys="${GHOST_ASC_ENV:-$HOME/.config/mattssoftware/signing/asc-api.env}"
[ -f "$keys" ] || { echo "error: no $keys: the App Store Connect key that signs the build is named there." >&2; exit 1; }
# shellcheck disable=SC1090
. "$keys"
: "${ASC_KEY_ID:?$keys names no ASC_KEY_ID}" "${ASC_ISSUER_ID:?$keys names no ASC_ISSUER_ID}" "${ASC_KEY_PATH:?$keys names no ASC_KEY_PATH}"
[ -f "$ASC_KEY_PATH" ] || { echo "error: the key file $keys names is not there." >&2; exit 1; }

# The core, for a phone and for the simulator both (static, without the engines, as the Tauri iPhone app is:
# tool/build-native.sh), so one xcframework serves either build.
tool/build-native.sh ios

# Flutter writes what the build is (ios/Flutter/Generated.xcconfig: the version, the build, the defines) and
# builds nothing; Xcode's own "Run Script" phase then builds the Dart in release, with --no-load_cse
# (ios/Flutter/Release.xcconfig).
GHOST_CUTOVER=1 flutter build ios --release --no-codesign --config-only --no-pub \
  --build-name="$version" --build-number="$build" \
  --dart-define=GHOST_CUTOVER=true \
  --dart-define=GHOST_VERSION="$version" \
  --dart-define=GHOST_BUILD="$stamp" \
  --dart-define=GHOST_COMMIT="$commit" \
  $look \
  "$@"

archive="$out/Ghost.md.xcarchive"
rm -rf "$archive" "$out/export"
# /usr/bin first: Homebrew's rsync broke the Tauri build's export (APP_STORE.md).
PATH="/usr/bin:$PATH" GHOST_CUTOVER=1 xcodebuild archive \
  -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  GHOST_CUTOVER=1 >"$out/archive.log" 2>&1 || { tail -40 "$out/archive.log" >&2; echo "error: the archive failed; the whole of it is in $out/archive.log" >&2; exit 1; }

options="$out/ExportOptions.plist"
cat >"$options" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<!-- An IPA on this Mac, and nothing sent anywhere. -->
	<key>destination</key>
	<string>export</string>
	<key>teamID</key>
	<string>F6ZAL7ANAD</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<!-- The version and the build are this script's, never Xcode's next free number. -->
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
PLIST
PATH="/usr/bin:$PATH" xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out/export" -exportOptionsPlist "$options" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  >"$out/export.log" 2>&1 || { tail -40 "$out/export.log" >&2; echo "error: the export failed; the whole of it is in $out/export.log" >&2; exit 1; }

made="$(ls "$out/export"/*.ipa 2>/dev/null | head -1)"
[ -n "$made" ] || { echo "error: the export left no IPA in $out/export." >&2; exit 1; }
ipa="$out/Ghost.md-$version-$build.ipa"
mv "$made" "$ipa"

# What was built is what was asked for, or this stops (the checks the Tauri build was held to, APP_STORE.md, and
# this app's own).
look="$out/look"
rm -rf "$look"
mkdir -p "$look"
unzip -q "$ipa" -d "$look"
app="$(ls -d "$look"/Payload/*.app | head -1)"
plist="$app/Info.plist"
value() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || true; }
failed=0
check() { [ "$2" = "$3" ] || { echo "error: $1 is \"$2\", not \"$3\"." >&2; failed=1; }; }
check "the id" "$(value CFBundleIdentifier)" "com.mattssoftware.glyph"
check "the version" "$(value CFBundleShortVersionString)" "$version"
check "the build" "$(value CFBundleVersion)" "$build"
check "the name" "$(value CFBundleDisplayName)" "Ghost.md"
check "the devices" "$(value UIDeviceFamily | tr -d ' \n')" "Array{1}"
check "the link scheme" "$(value CFBundleURLTypes:0:CFBundleURLSchemes:0)" "ghostmd"
[ -n "$(value NSCameraUsageDescription)" ] || { echo "error: no camera sentence." >&2; failed=1; }
[ -z "$(value NSMicrophoneUsageDescription)" ] || { echo "error: a microphone sentence in an app that records nothing." >&2; failed=1; }
[ -n "$(value ITSAppUsesNonExemptEncryption)" ] || { echo "error: the export-compliance answer is not in the Info.plist." >&2; failed=1; }
[ -f "$app/PrivacyInfo.xcprivacy" ] || { echo "error: no privacy manifest in the app." >&2; failed=1; }
binary="$app/$(value CFBundleExecutable)"
check "the app's architectures" "$(lipo -archs "$binary")" "arm64"
for symbol in ghost_alloc ghost_invoke ghost_free ghost_set_listener ghost_forget_listener; do
  nm -gU "$binary" 2>/dev/null | grep -q " _$symbol\$" || { echo "error: the core's $symbol is not in the app." >&2; failed=1; }
done
signed="$(codesign -dvv "$app" 2>&1 || true)"
authority="$(printf '%s\n' "$signed" | sed -n 's/^Authority=//p' | head -1)"
case "$authority" in
  "Apple Distribution: "*"(F6ZAL7ANAD)") ;;
  *) echo "error: signed by \"$authority\", not the team's distribution certificate." >&2; failed=1 ;;
esac
profile="$(security cms -D -i "$app/embedded.mobileprovision" 2>/dev/null | plutil -extract Name raw - 2>/dev/null || true)"
group="$(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -extract application-identifier raw - 2>/dev/null || true)"
# The Keychain's access group is the team and the id: what lets this app read the key WebKit kept for the Tauri app.
check "the application identifier" "$group" "F6ZAL7ANAD.com.mattssoftware.glyph"
[ "$failed" = 0 ] || exit 1
size="$(wc -c <"$ipa" | tr -d ' ')"
rm -rf "$look"
echo "$ipa"
echo "  Ghost.md $version ($build), com.mattssoftware.glyph, iPhone only, arm64, $size bytes"
echo "  signed by $authority, profile \"$profile\", built $stamp from $commit"
echo "  Not uploaded: nothing here sends it anywhere."
