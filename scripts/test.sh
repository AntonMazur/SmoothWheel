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
Path('artifacts/tests/saved-presets-results.json').unlink(missing_ok=True)
for path in Path('artifacts/tests/transition-frames').glob('*.png'):
    path.unlink()
PY
result=0
# Native drawing and sheet actions run separately so AppKit cannot delay
# the functional suite's clock, resolver, or diagnostics tests.
SMOOTHWHEEL_UI_SNAPSHOTS=0 swift test --disable-sandbox --build-system native --manifest-cache local --scratch-path .build-coverage --enable-code-coverage --xunit-output artifacts/tests/functional.xml "$@" || result=$?
python3 scripts/export-coverage.py --collect || result=1
if [[ "$SMOOTHWHEEL_UI_SNAPSHOTS" == 1 ]]; then
    swift test --disable-sandbox --build-system native --manifest-cache local --scratch-path .build-coverage --enable-code-coverage --skip-build --filter 'actualSettingsWindowSnapshots|nativeLibraryActionsAndKeyboardUseTheProductionCoordinator' --xunit-output artifacts/tests/ui.xml || result=$?
    python3 scripts/export-coverage.py --collect || result=1
    # Keep each run-loop motion fixture independent of snapshot rendering and window teardown.
    for motion_test in rapidReplacementAndReducedMotionPreserveFocus switchRetargetingAndFailedEnableUseCommittedState saveRevealAndListEditsPreserveStateAndGeometry samplesLiveSettingsTransitionFrames; do
        swift test --disable-sandbox --build-system native --manifest-cache local --scratch-path .build-coverage --enable-code-coverage --skip-build --filter "$motion_test" --xunit-output "artifacts/tests/$motion_test.xml" || result=$?
        python3 scripts/export-coverage.py --collect || result=1
    done
    python3 - <<'PY' || result=1
import json
from pathlib import Path

report = Path('artifacts/tests/saved-presets-results.json')
results = json.loads(report.read_text()) if report.exists() else {}
if not all(f'transition-frames-{mode}' in results for mode in ('light', 'dark')):
    raise SystemExit('Missing native transition-frame results. Check the AppKit test log.')
PY
fi
if python3 scripts/export-coverage.py; then
    python3 scripts/coverage-report.py artifacts/coverage/llvm.json || result=1
else
    result=1
fi
python3 scripts/check-design.py || result=1
exit "$result"
