#!/bin/zsh
set -eu
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/smoothwheel-clang-cache"
SMOOTHWHEEL_MEASURE=1 swift test --disable-sandbox --build-system native --manifest-cache local --scratch-path .build-measurements -c release --disable-code-coverage --filter productionCallbackMeasurements
python3 scripts/check-performance.py artifacts/performance/callbacks.json
