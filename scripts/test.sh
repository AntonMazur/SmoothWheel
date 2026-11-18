#!/bin/zsh
set -eu
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/smoothwheel-clang-cache"
mkdir -p artifacts/tests artifacts/coverage/profiles
if [[ -z "${SMOOTHWHEEL_UI_SNAPSHOTS:-}" ]]; then
    if [[ "$(sw_vers -productVersion)" == 26.* ]]; then
        export SMOOTHWHEEL_UI_SNAPSHOTS=1
    else
        export SMOOTHWHEEL_UI_SNAPSHOTS=0
        print 'UI goldens require macOS 26; run CI for the complete snapshot check.'
    fi
fi
# Remove old evidence so filtered/failed runs cannot borrow earlier coverage.
python3 - <<'PY'
from pathlib import Path
for root in [Path('.build-coverage'), Path('artifacts/coverage/profiles')]:
    for path in root.rglob('*.profraw'):
        path.unlink()
for name in ['llvm.json', 'summary.json', 'summary.md']:
    Path('artifacts/coverage', name).unlink(missing_ok=True)
PY
result=0
# UI rendering and display-clock integration must run in separate processes:
# synchronous AppKit drawing would otherwise starve parallel clock tests.
SMOOTHWHEEL_UI_SNAPSHOTS=0 swift test --disable-sandbox --build-system native --manifest-cache local --scratch-path .build-coverage --enable-code-coverage --xunit-output artifacts/tests/functional.xml "$@" || result=$?
python3 scripts/export-coverage.py --collect || result=1
if [[ "$SMOOTHWHEEL_UI_SNAPSHOTS" == 1 ]]; then
    swift test --disable-sandbox --build-system native --manifest-cache local --scratch-path .build-coverage --enable-code-coverage --skip-build --filter actualSettingsWindowSnapshots --xunit-output artifacts/tests/ui.xml || result=$?
    python3 scripts/export-coverage.py --collect || result=1
fi
if python3 scripts/export-coverage.py; then
    python3 scripts/coverage-report.py artifacts/coverage/llvm.json || result=1
else
    result=1
fi
python3 scripts/check-design.py || result=1
exit "$result"
