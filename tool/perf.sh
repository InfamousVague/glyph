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

if [ "$what" != "mac" ]; then
  echo "perf: only the Mac is walked from here so far (tool/perf.sh mac)" >&2
  exit 64
fi

lock=/tmp/ghost-flutter-build.lock
until mkdir "$lock" 2>/dev/null; do sleep 10; done
trap 'rmdir "$lock" 2>/dev/null || true' EXIT

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
