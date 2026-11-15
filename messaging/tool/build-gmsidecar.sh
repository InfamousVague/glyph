#!/bin/sh
# Builds the Google Messages sidecar (sidecar/gmessages, AGPL-3.0) for the desktop apps:
#   build/gmsidecar/mac/gmsidecar        one file for Apple silicon and Intel
#   build/gmsidecar/windows/gmsidecar.exe
# Pure Go (no C), so a Mac builds both. Usage: tool/build-gmsidecar.sh [mac|windows|all]
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
src="$root/sidecar/gmessages"
out="$root/build/gmsidecar"
want=${1:-all}
cd "$src"
export CGO_ENABLED=0
flags="-trimpath -ldflags=-s"
if [ "$want" = mac ] || [ "$want" = all ]; then
  mkdir -p "$out/mac"
  GOOS=darwin GOARCH=arm64 go build $flags -o "$out/mac/gmsidecar-arm64" .
  GOOS=darwin GOARCH=amd64 go build $flags -o "$out/mac/gmsidecar-amd64" .
  lipo -create -output "$out/mac/gmsidecar" "$out/mac/gmsidecar-arm64" "$out/mac/gmsidecar-amd64"
  rm "$out/mac/gmsidecar-arm64" "$out/mac/gmsidecar-amd64"
  echo "ok $out/mac/gmsidecar"
fi
if [ "$want" = windows ] || [ "$want" = all ]; then
  mkdir -p "$out/windows"
  GOOS=windows GOARCH=amd64 go build $flags -o "$out/windows/gmsidecar.exe" .
  echo "ok $out/windows/gmsidecar.exe"
fi
