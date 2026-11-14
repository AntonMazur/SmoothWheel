#!/bin/zsh
set -eu
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/smoothwheel-clang-cache"
swift build --disable-sandbox --build-system native --manifest-cache local -c release --scratch-path .build-release >&2
BIN_DIR=$(swift build --disable-sandbox --build-system native --manifest-cache local -c release --scratch-path .build-release --show-bin-path)
BENCH_DIR=$(mktemp -d "${TMPDIR:-/tmp}/smoothwheel-benchmark.XXXXXX")
trap 'rm -rf "$BENCH_DIR"' EXIT
swiftc -O -module-cache-path "$CLANG_MODULE_CACHE_PATH" -I "$BIN_DIR/Modules" scripts/benchmark-scroll.swift \
  "$BIN_DIR/ScrollCore.build/ScrollSmoother.swift.o" "$BIN_DIR/ScrollEvents.build/ScrollEventStream.swift.o" -o "$BENCH_DIR/benchmark"
"$BENCH_DIR/benchmark"
