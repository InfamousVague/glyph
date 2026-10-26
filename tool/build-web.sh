#!/bin/sh
# Builds Ghost.md for the web (docs/WEB.md): the browser's core (tool/build-web-core.sh), then the app compiled to
# WebAssembly into build/web, under the address it is served at. Matt, 2026-10-26: "update the web version of the app
# it's very behind".
#
#   tool/build-web.sh                          the release, on the real service, for scripts/deploy-flutter-web.mjs
#   GHOST_WEB_VERSION=2.3.36 tool/build-web.sh
#                                              the version About says (pubspec's 0.1.0 when not told), as the Mac's and
#                                              the iPhone's builds are told theirs; the deploy refuses a build without
#   GHOST_WEB_API=http://127.0.0.1:9999/api tool/build-web.sh
#                                              one that signs in nowhere (a dead address), for the browser pane; the
#                                              deploy refuses it (scripts/deploy-flutter-web.mjs)
#   GHOST_WEB_BASE=/ tool/build-web.sh         served at a site's root instead of /glyph/
#   GHOST_WEB_NAMES=1 tool/build-web.sh        Dart's names kept in the WebAssembly (-O1, not stripped), so an error
#                                              in the console names the function it came from
#
# What it is built as, and why:
#
# - **WebAssembly, with a JavaScript copy beside it** (`--wasm`). The app's hashes are 64-bit FNV-1a, which only a
#   64-bit `int` keeps, so the WebAssembly is the app and the JavaScript copy opens only lib/web/too_old.dart.
# - **Flutter's renderer from the site itself** (`--no-web-resources-cdn`): nothing is fetched from Google's CDN to
#   draw a note, and the page works where that is blocked.
# - **No service worker** (web/flutter_bootstrap.js): every file is served no-cache and revalidated instead.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

free="$(df -g / | awk 'NR==2 {print $4}')"
if [ "${free:-0}" -lt 20 ]; then
  echo "Only ${free} GB free on /: not building." >&2
  exit 1
fi

"$root/tool/build-web-core.sh"

base="${GHOST_WEB_BASE:-/glyph/}"
set -- --wasm --release --no-pub --base-href "$base" --no-web-resources-cdn --no-wasm-dry-run
if [ -n "${GHOST_WEB_API:-}" ]; then
  set -- "$@" "--dart-define=GHOST_API=$GHOST_WEB_API"
fi
if [ -n "${GHOST_WEB_VERSION:-}" ]; then
  set -- "$@" "--dart-define=GHOST_VERSION=$GHOST_WEB_VERSION"
fi
if [ "${GHOST_WEB_NAMES:-}" = "1" ]; then
  set -- "$@" -O1 --no-strip-wasm
fi
flutter build web "$@"

# What the deploy reads to know which build it is shipping, and to refuse one built from other code than the tree's,
# against another service, or with no version.
printf '{"built":"%s","commit":"%s","base":"%s","api":"%s","version":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(git rev-parse HEAD)" "$base" "${GHOST_WEB_API:-https://ghostmarkdown.com/api}" "${GHOST_WEB_VERSION:-}" > "$root/build/web/ghost-build.json"
du -sh "$root/build/web"
