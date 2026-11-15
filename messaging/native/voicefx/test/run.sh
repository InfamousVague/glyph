#!/bin/sh
# Builds voicefx with RNNoise for this computer and runs its test.
set -e
here=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/voicefx_test
cc -O2 -std=c11 -I"$here/include" -I"$here/rnnoise/include" -I"$here/rnnoise/src" "$here/voicefx.c" "$here"/rnnoise/src/*.c "$here/test/voicefx_test.c" -lm -o "$out"
"$out"
