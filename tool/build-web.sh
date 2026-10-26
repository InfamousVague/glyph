#!/bin/sh
# Builds Ghost.md for the web (docs/WEB.md): the browser's core (tool/build-web-core.sh), then the app compiled to
# WebAssembly into build/web, under the address it is served at. Matt, 2026-10-26: "update the web version of the app
# it's very behind".
#
#   tool/build-web.sh                          the release, on the real service, for scripts/deploy-flutter-web.mjs
#   GHOST_WEB_API=http://127.0.0.1:9/api tool/build-web.sh
#                                              one that signs in nowhere (a dead address), for the browser pane
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

# What the deploy reads to say which build it is shipping.
printf '{"built":"%s","commit":"%s","base":"%s","api":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(git rev-parse --short HEAD)" "$base" "${GHOST_WEB_API:-https://ghostmarkdown.com/api}" > "$root/build/web/ghost-build.json"
du -sh "$root/build/web"
