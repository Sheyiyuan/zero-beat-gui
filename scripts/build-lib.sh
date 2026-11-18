#!/bin/sh
# Build libzero.so / libzero.dylib from cmd/lib.
# Android 15+ 16 KB pages need the linker flag below. This script does not build an APK.
set -eu
cd "$(dirname "$0")/.."
out="${1:-build/libzero.so}"
mkdir -p "$(dirname "$out")"
export CGO_ENABLED=1
# -s -w belong to the Go linker. The page-size flag must reach the external linker.
extld="${ZERO_LIB_EXTLDFLAGS:--Wl,-z,max-page-size=16384}"
exec "${GO:-go}" build -buildmode=c-shared -ldflags "-s -w -extldflags=${extld}" -o "$out" ./cmd/lib
