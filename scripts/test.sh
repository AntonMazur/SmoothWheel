#!/bin/zsh
set -eu
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/smoothwheel-clang-cache"
swift test --disable-sandbox --build-system native --manifest-cache local --scratch-path .build-tests
python3 scripts/check-design.py
