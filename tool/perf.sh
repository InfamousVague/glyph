#!/bin/sh
# Measures the app: builds it to be measured, has it walk itself (lib/perf/perf_run.dart), and prints what every
# stretch of the walk cost in frames and, for the Mac's profile build, which Dart functions the time went to
# (tool/perf_cpu.dart).
#
#   tool/perf.sh mac                      the whole standard walk on the Mac, with the CPU's samples
#   tool/perf.sh mac note+settings        only those parts of it (home, note, board, canvas, notebook, settings)
#   tool/perf.sh mac 'wait:2000;mark:x;taptext:Bench long;wait:2000;mark:end'     a walk of your own
#   PERF_TOP=50 PERF_ONLY=note-type tool/perf.sh mac note      more of the profile, for one stretch
#   PERF_BUILD=0 tool/perf.sh mac note    walk the build that is there, without building again
#   PERF_DEVICE=<adb serial> tool/perf.sh android [note+settings]
#                                         the same walk on a phone or an emulator: frames by stretch, where the
#                                         raster half is the phone's own GPU. The device is always named, never
#                                         guessed: the walk takes its screen for as long as it lasts. It is an app
#                                         of its own there (Ghost Perf, com.mattssoftware.glyph.flutter.perf), with
#                                         its own made-up library, put on for the walk and taken off after
#                                         (PERF_KEEP=1 leaves it). No CPU samples from a phone yet.
#
# The Mac's window opens for as long as the walk takes (the whole of it is about four minutes) and nothing is
# clicked or typed outside it: the app is given its touches from inside. Its library is 350 made-up notes in
# build/perf/mac (lib/perf/perf_seed.dart), never a person's.
#
# One build and one walk at a time on this machine: the build lock other builds take is held from the build to the
# walk's end, since a walk measured while something else compiles says nothing.
#
# Output: build/perf/mac/last.txt (frames by stretch, then the profile by stretch) and the same on the terminal's
# first lines; the report and the samples stay in build/perf/mac/cache/perf for `dart run tool/perf_cpu.dart
# build/perf/mac/cache/perf --saved --only <stretch> --top 60`.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
what="${1:-mac}"
walk="${2:-bench}"
case "$walk" in
  bench|*';'*|*':'*) ;;
  *) walk="bench:$walk" ;;
esac

if [ "$what" != "mac" ] && [ "$what" != "android" ]; then
  echo "perf: tool/perf.sh mac [parts] or PERF_DEVICE=<adb serial> tool/perf.sh android [parts]" >&2
  exit 64
fi

# The lock says who holds it, so one left by a walk that was ended is taken over and not waited on for ever (a lock
# made by a plain mkdir elsewhere names no one, and is waited for).
lock=/tmp/ghost-flutter-build.lock
held=0
drop_lock() {
  [ "$held" = 1 ] || return 0
  held=0
  rm -f "$lock/pid"
  rmdir "$lock" 2>/dev/null || true
}
trap drop_lock EXIT
trap 'exit 130' INT TERM HUP
until mkdir "$lock" 2>/dev/null; do
  holder="$(cat "$lock/pid" 2>/dev/null || true)"
  if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
    rm -f "$lock/pid"
    rmdir "$lock" 2>/dev/null || true
    continue
  fi
  # Looked for every second: others look every half second or three, and a walk that looked every ten waited
  # forty-five minutes behind them.
  sleep 1
done
held=1
echo $$ > "$lock/pid"

if [ "$what" = "android" ]; then
  device="${PERF_DEVICE:?perf: name the device (PERF_DEVICE=<adb serial>); the walk takes its screen}"
  case "$walk" in
    *';'*|*','*) echo "perf: a phone walks the standard parts only (bench, or note+settings)" >&2; exit 64 ;;
  esac
  id=com.mattssoftware.glyph.flutter.perf
  dir="$root/build/perf/android"
  mkdir -p "$dir"
  export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
  export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
  if [ "${PERF_BUILD:-1}" != "0" ]; then
    # The walk is compiled in: a phone's app has no environment to read it from.
    GHOST_PERF_ID=1 flutter build apk --profile --no-pub --target-platform android-arm64 \
      --dart-define=GHOST_PERF=true --dart-define=GHOST_PERF_SEED=350 "--dart-define=GHOST_PERF_TOUR=$walk" 2>&1 | tail -2
    cp "$root/build/app/outputs/flutter-apk/app-profile.apk" "$dir/perf.apk"
  fi
  # The lock is let go once the build is done: what the walk measures is the phone, not this Mac.
  drop_lock
  adb -s "$device" install -r "$dir/perf.apk" > "$dir/install.log" 2>&1 || { cat "$dir/install.log" >&2; exit 1; }
  adb -s "$device" logcat -c
  # The app's words are kept as they are said: the phone's own log keeps only its last few hundred lines.
  adb -s "$device" logcat -s flutter > "$dir/run.log" 2>&1 &
  logging=$!
  adb -s "$device" shell am start -n "$id/com.mattssoftware.ghost_md.MainActivity" > /dev/null
  waited=0
  until grep -q '\[perf\] report end' "$dir/run.log" 2>/dev/null; do
    sleep 5
    waited=$((waited + 5))
    if [ "$waited" -ge "${PERF_WAIT:-600}" ]; then echo "perf: the walk did not end in ${PERF_WAIT:-600} s" >&2; break; fi
    if [ $((waited % 30)) -eq 0 ] && ! adb -s "$device" shell pidof "$id" > /dev/null 2>&1; then echo "perf: the app is gone (it ended or was ended)" >&2; break; fi
  done
  kill "$logging" 2>/dev/null || true
  adb -s "$device" logcat -d -b crash > "$dir/crash.log" 2>&1 || true
  adb -s "$device" shell am force-stop "$id" || true
  [ "${PERF_KEEP:-0}" = "1" ] || adb -s "$device" uninstall "$id" > /dev/null 2>&1 || true
  {
    echo "# $(git rev-parse --short HEAD)$(git diff --quiet HEAD -- lib packages shaders 2>/dev/null || echo ' + uncommitted changes'), walked $(date '+%H:%M'), load $(sysctl -n vm.loadavg | tr -d '{}' | awk '{print $1}')"
    echo "# $(adb -s "$device" shell getprop ro.product.model 2>/dev/null | tr -d '\r'), frames by stretch (build and raster in ms: p50/p90/p99/max)"
    grep '\[perf\]' "$dir/run.log" | grep -v 'report' | sed 's/^.*\[perf\] //'
    grep -E 'FAILED|ERROR|NOT FOUND|NOTHING HOLDS' "$dir/run.log" | sed 's/^.*flutter *: //' || true
    grep -c 'FATAL\|SIGSEGV' "$dir/crash.log" | sed 's/^/crash lines: /' || true
  } > "$dir/last.txt"
  cat "$dir/last.txt"
  exit 0
fi

dir="$root/build/perf/mac"
mkdir -p "$dir"
if [ "${PERF_BUILD:-1}" != "0" ]; then
  flutter build macos --profile --no-pub --dart-define=GHOST_PERF=true --dart-define=GHOST_PERF_SEED=350 2>&1 | tail -2
fi
app="$root/build/macos/Build/Products/Profile/Ghost Flutter.app/Contents/MacOS/Ghost Flutter"
rm -f "$dir/cache/perf/report.json" "$dir/cache/perf/vm.txt" "$dir/cache/perf/done" "$dir/cache/perf/samples.json"
GHOST_PERF_TOUR="$walk" GHOST_PERF_HOLD=1 GHOST_PERF_DIR="$dir" "$app" > "$dir/run.log" 2>&1 &
set +e
dart run tool/perf_cpu.dart "$dir/cache/perf" --top "${PERF_TOP:-30}" ${PERF_ONLY:+--only "$PERF_ONLY"} > "$dir/cpu.txt" 2> "$dir/cpu.err"
status=$?
set -e
{
  echo "# $(git rev-parse --short HEAD)$(git diff --quiet HEAD -- lib packages shaders 2>/dev/null || echo ' + uncommitted changes'), walked $(date '+%H:%M'), load $(sysctl -n vm.loadavg | tr -d '{}' | awk '{print $1}')"
  echo "# frames by stretch (build and raster in ms: p50/p90/p99/max)"
  grep '\[perf\]' "$dir/run.log" | grep -v 'report' | sed 's/^flutter: \[perf\] //'
  grep -E 'FAILED|ERROR|NOT FOUND|NOTHING HOLDS' "$dir/run.log" | sed 's/^flutter: //' || true
  echo
  echo "# the profile by stretch"
  cat "$dir/cpu.txt"
} > "$dir/last.txt"
grep -c '' "$dir/last.txt" >/dev/null
sed -n '1,40p' "$dir/last.txt"
echo "perf: the rest is in build/perf/mac/last.txt"
[ "$status" -eq 0 ] || { tail -5 "$dir/cpu.err" >&2; exit "$status"; }
