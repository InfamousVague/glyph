#!/bin/sh
# The real account and sync service (server, Rust), on this Mac and nowhere else: what test/e2e runs
# against (docs/STAGE7.md: "a local copy of server/"). Nothing here, and nothing it starts, talks to
# ghostmarkdown.com or attack.fm: the service binds 127.0.0.1 on a port the system picks, with a token made for the
# run and a data folder made for the run, both thrown away when it stops.
#
#   tool/local-server.sh build     copies server and builds it (once; again only when its source changed)
#   tool/local-server.sh start     builds if need be, starts it, and prints  GHOST_E2E_API=http://127.0.0.1:<port>/api
#   tool/local-server.sh stop      stops the one `start` started, by its PID, and removes its data
#   tool/local-server.sh status    whether one is running, and where
#   tool/local-server.sh test      start, `flutter test --no-pub test/e2e` against it (more arguments are passed on), stop
#
# server/ (the service, at this repository's root) is only READ. It is copied (without target/) to
# build/local-server/server, under the git-ignored build/, and cargo builds there with its own target directory, so
# nothing is written in server/ and none of its 5 GB of build output is touched. `flutter clean` removes the copy and the
# build; the next `build` makes them again (a few minutes).
#
# A deploy of the Tauri app runs tests that fail when the Mac is busy (as tool/build-native.sh says), so a build
# waits for one to end.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
source="$root/server"
work="$root/build/local-server"
copy="$work/server"
target="$work/target"
binary="$target/debug/glyph-api"
run="$work/run.env"
what="${1:-start}"
[ $# -gt 0 ] && shift

wait_for_deploys() {
  while pgrep -fl "scripts/[d]eploy" >/dev/null 2>&1; do
    echo "local-server: a deploy of the Tauri app is running; waiting for it to end..." >&2
    sleep 20
  done
}

build() {
  if [ ! -f "$source/Cargo.toml" ]; then
    echo "local-server: there is no server/ in this checkout." >&2
    exit 1
  fi
  mkdir -p "$copy"
  # The source as it is now; target/ never. --delete, so a file removed there is removed here.
  rsync -a --delete --exclude target/ "$source/" "$copy/"
  wait_for_deploys
  (cd "$copy" && CARGO_TARGET_DIR="$target" cargo build --locked >&2)
  echo "local-server: $binary" >&2
}

running() {
  [ -f "$run" ] || return 1
  # shellcheck disable=SC1090
  . "$run"
  kill -0 "$GHOST_E2E_PID" 2>/dev/null
}

free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

start() {
  if running; then
    echo "local-server: already running (pid $GHOST_E2E_PID)" >&2
    echo "GHOST_E2E_API=$GHOST_E2E_API"
    return 0
  fi
  build
  port="$(free_port)"
  data="$(mktemp -d "${TMPDIR:-/tmp}/ghost-e2e-data.XXXXXX")"
  token="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
  log="$work/server.log"
  # OLLAMA_URL names a closed port: the format route has no model to reach, and nothing else is asked of one.
  GLYPH_API_TOKEN="$token" GLYPH_API_DATA="$data" GLYPH_API_BIND="127.0.0.1:$port" OLLAMA_URL="http://127.0.0.1:9" \
    nohup "$binary" >"$log" 2>&1 &
  pid=$!
  api="http://127.0.0.1:$port/api"
  {
    echo "GHOST_E2E_PID=$pid"
    echo "GHOST_E2E_API=$api"
    echo "GHOST_E2E_DATA=$data"
  } >"$run"
  tries=0
  until curl -fsS -o /dev/null "$api/health" 2>/dev/null; do
    tries=$((tries + 1))
    if ! kill -0 "$pid" 2>/dev/null || [ "$tries" -gt 100 ]; then
      echo "local-server: the service did not come up; see $log" >&2
      stop
      exit 1
    fi
    sleep 0.1
  done
  echo "local-server: pid $pid, data $data, log $log" >&2
  echo "GHOST_E2E_API=$api"
}

stop() {
  if [ ! -f "$run" ]; then
    echo "local-server: none was started here." >&2
    return 0
  fi
  # shellcheck disable=SC1090
  . "$run"
  # Only the process this script started, and only while it is still that binary.
  if kill -0 "$GHOST_E2E_PID" 2>/dev/null && ps -p "$GHOST_E2E_PID" -o command= | grep -q "glyph-api"; then
    kill "$GHOST_E2E_PID"
    tries=0
    while kill -0 "$GHOST_E2E_PID" 2>/dev/null && [ "$tries" -lt 50 ]; do
      tries=$((tries + 1))
      sleep 0.1
    done
  fi
  case "$GHOST_E2E_DATA" in
    */ghost-e2e-data.*) rm -rf "$GHOST_E2E_DATA" ;;
  esac
  rm -f "$run"
  echo "local-server: stopped." >&2
}

case "$what" in
  build) build ;;
  start) start ;;
  stop) stop ;;
  status)
    if running; then echo "GHOST_E2E_API=$GHOST_E2E_API"; else echo "local-server: not running." >&2; exit 1; fi
    ;;
  test)
    start >/dev/null
    # shellcheck disable=SC1090
    . "$run"
    status=0
    (cd "$root" && GHOST_E2E_API="$GHOST_E2E_API" flutter test --no-pub test/e2e "$@") || status=$?
    stop
    exit "$status"
    ;;
  *) echo "usage: tool/local-server.sh [build|start|stop|status|test]" >&2; exit 2 ;;
esac
