#!/bin/sh
# The Mac's own updates tried end to end on this Mac, with nothing published and nothing of the real app's touched
# (lib/core/updates.dart `UpdateKind.mac`, macos/Runner/UpdatesChannel.swift; docs/CUTOVER.md, section 7).
#
#   tool/mac-update-proof.sh build <dir>     two builds, 9.9.1 and 9.9.2, the newer one's update files, a test key
#   tool/mac-update-proof.sh serve <dir>     the update files on http://127.0.0.1:8765, in the background (its PID in
#                                            <dir>/server.pid), and 9.9.1 put in <dir>/Applications to be opened
#   tool/mac-update-proof.sh stop <dir>      the server, by its PID
#
# WHAT THE BUILDS ARE, and why each differs from a release:
# - DEBUG builds, since only a debug build reads `GHOST_UPDATES_TEST`: it lets the address be http (this Mac's own
#   server) and trusts a key made for the run (`GHOST_UPDATES_TEST_KEY`) beside the app's own. A release reads
#   neither, whatever it is told. What is tried is the same Dart and the same Swift a release runs.
# - The bundle id is com.mattssoftware.glyph.updateproof, set in each copy before it is ever opened: its folder
#   (~/Library/Application Support/com.mattssoftware.glyph.updateproof), its preferences and its Keychain service are
#   its own, never the real app's or a development build's. `ghostmd:` is taken out of its Info.plist, so it is never
#   handed a link meant for the real app. It is told no service (a debug build has no account then) and no models.
# - It presses its own buttons (`GHOST_UPDATES_TEST_WALK`, read beside GHOST_UPDATES_TEST by a debug build alone):
#   Install eight seconds after the update is found, Restart to update eight seconds after it is in place, so the
#   walk needs no hand on this Mac's screen, and the card can be photographed in each state on the way.
# - Signed with the team's Developer ID where the Keychain has it (no hardened runtime, not notarised: nothing
#   leaves this Mac), so the update's signature is checked as a release checks it, against this app's team; with
#   GHOST_PROOF_ADHOC=1, ad hoc, which a debug build takes as any whole signature.
# - Kept under <dir>, never /Applications: the app updates itself where it is, so <dir>/Applications/Ghost
#   Flutter.app is what is replaced.
#
# The build takes /tmp/ghost-flutter-build.lock (mkdir, its PID inside) and gives it back however it ends; a lock
# another holds is waited for, never taken.
set -eu
what="${1:?build, serve or stop}"
dir="${2:?a scratch folder}"
root="$(cd "$(dirname "$0")/.." && pwd)"
port="${GHOST_PROOF_PORT:-8765}"
id="com.mattssoftware.glyph.updateproof"
identity="Developer ID Application: Matt Wisniewski (F6ZAL7ANAD)"
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"
case "$dir" in /Applications | /Applications/*) echo "error: not under /Applications." >&2; exit 2 ;; esac

code_of() {
  major="${1%%.*}"; rest="${1#*.}"; minor="${rest%%.*}"; patch="${rest#*.}"
  echo $((major * 1000000 + minor * 1000 + patch))
}

build_one() {
  version="$1"
  key="$2"
  (cd "$root" && flutter build macos --debug --no-pub \
    --build-name="$version" \
    --build-number="$(code_of "$version")" \
    --dart-define=GHOST_VERSION="$version" \
    --dart-define=GHOST_BUILD="$(date -u +%Y%m%d%H%M%S)" \
    --dart-define=GHOST_UPDATES="http://127.0.0.1:$port" \
    --dart-define=GHOST_UPDATES_TEST=true \
    --dart-define=GHOST_UPDATES_TEST_WALK=true \
    --dart-define=GHOST_UPDATES_TEST_KEY="$key")
  built="$root/build/macos/Build/Products/Debug/Ghost Flutter.app"
  [ -d "$built" ] || { echo "error: the build left no $built." >&2; exit 1; }
  app="$dir/$version/Ghost Flutter.app"
  rm -rf "$dir/$version"
  mkdir -p "$dir/$version"
  ditto "$built" "$app"
  plist="$app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $id" "$plist"
  /usr/libexec/PlistBuddy -c 'Delete :CFBundleURLTypes' "$plist" 2>/dev/null || true
  # Signed again, inside out, now that the plist is changed.
  sign="-"
  if [ "${GHOST_PROOF_ADHOC:-}" != 1 ] && security find-identity -v -p codesigning | grep -qF "\"$identity\""; then sign="$identity"; fi
  find "$app/Contents/Frameworks" -depth \( -name '*.dylib' -o -name '*.framework' \) -print | while read -r inner; do
    codesign --force --sign "$sign" "$inner" >/dev/null 2>&1 || { echo "error: could not sign $inner." >&2; exit 1; }
  done
  codesign --force --sign "$sign" --entitlements "$root/macos/Runner/DebugProfile.entitlements" "$app" >/dev/null 2>&1 || { echo "error: could not sign the app." >&2; exit 1; }
  codesign --verify --deep --strict "$app"
  echo "$app: $version ($(code_of "$version")), $id, signed by ${sign#-}$( [ "$sign" = - ] && echo 'nobody (ad hoc)')"
}

case "$what" in
  build)
    lock=/tmp/ghost-flutter-build.lock
    until mkdir "$lock" 2>/dev/null; do
      echo "waiting for the build lock ($(cat "$lock/pid" 2>/dev/null || echo '?') holds it)..."
      sleep 15
    done
    echo $$ >"$lock/pid"
    trap 'rm -f "$lock/pid"; rmdir "$lock" 2>/dev/null' EXIT INT TERM
    # A key for the run, its private half in <dir> and nowhere else; kept for a second call that builds one version.
    # Node's, since the Mac's own openssl (LibreSSL) makes no Ed25519 key.
    [ -f "$dir/test-key.pem" ] || node -e "const { generateKeyPairSync } = require('node:crypto'); require('node:fs').writeFileSync(process.argv[1], generateKeyPairSync('ed25519').privateKey.export({ type: 'pkcs8', format: 'pem' }), { mode: 0o600 });" "$dir/test-key.pem"
    public="$(node -e "const c = require('node:crypto'); process.stdout.write(c.createPublicKey(c.createPrivateKey(require('node:fs').readFileSync(process.argv[1]))).export({ type: 'spki', format: 'der' }).subarray(-32).toString('base64'));" "$dir/test-key.pem")"
    [ -n "$public" ] || { echo "error: no key for the run." >&2; exit 1; }
    shift 2
    # Both, or the versions named (`build <dir> 9.9.1`): a build can take longer than a caller's patience.
    for version in ${*:-9.9.1 9.9.2}; do build_one "$version" "$public"; done
    [ ! -d "$dir/9.9.2" ] || node "$root/scripts/deploy-flutter-mac.mjs" --test-feed "$dir/9.9.2/Ghost Flutter.app" --key "$dir/test-key.pem" --out "$dir/feed"
    ;;
  serve)
    [ -f "$dir/feed/mac.json" ] || { echo "error: no $dir/feed: run build first." >&2; exit 1; }
    rm -rf "$dir/Applications"
    mkdir -p "$dir/Applications"
    ditto "$dir/9.9.1/Ghost Flutter.app" "$dir/Applications/Ghost Flutter.app"
    python3 -m http.server "$port" --bind 127.0.0.1 --directory "$dir/feed" >"$dir/server.log" 2>&1 &
    echo $! >"$dir/server.pid"
    echo "serving $dir/feed on http://127.0.0.1:$port (PID $(cat "$dir/server.pid")); open \"$dir/Applications/Ghost Flutter.app\""
    ;;
  stop)
    [ -f "$dir/server.pid" ] && kill "$(cat "$dir/server.pid")" 2>/dev/null || true
    rm -f "$dir/server.pid"
    ;;
  *) echo "build, serve or stop" >&2; exit 2 ;;
esac
