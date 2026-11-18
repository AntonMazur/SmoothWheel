#!/usr/bin/env python3
"""Export release metrics using an allowlist; exclude app names, PIDs and local paths."""
import argparse
from datetime import datetime
import json
import platform
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
RUNTIME_FIELDS = [
    'acceptedDiscreteEvents', 'bypassedContinuousEvents', 'postedFrames',
    'frameIntervalsRecorded', 'clockMode', 'inputCallbackP95Ms', 'inputCallbackMaximumMs',
    'frameIntervalP95Ms', 'frameIntervalMaximumMs', 'maximumPointerMismatchPixels',
    'annotatedDestinationEvents', 'unknownDestinationEvents', 'fallbackDestinationEvents',
]


def test_count(name):
    root = ET.parse(ROOT / f'artifacts/tests/{name}-swift-testing.xml').getroot()
    suites = root.findall('testsuite')
    if not suites or any(int(s.get('errors', '0')) or int(s.get('failures', '0')) for s in suites):
        raise SystemExit(f'No passing {name} test report')
    return sum(int(s.get('tests', '0')) for s in suites)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--runtime-report', required=True, type=Path)
    args = parser.parse_args()
    raw = json.loads(args.runtime_report.read_text())
    coverage = json.loads((ROOT / 'artifacts/coverage/summary.json').read_text())
    timings = json.loads((ROOT / 'artifacts/performance/callbacks.json').read_text())
    report = {
        'schemaVersion': 1,
        'version': args.version,
        'recordedAt': datetime.now(ZoneInfo('Europe/Bratislava')).isoformat(timespec='seconds'),
        'environment': {
            'architecture': platform.machine(), 'macOS': platform.mac_ver()[0],
            'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip().splitlines()[0],
        },
        'physicalWheelSession': {
            **{key: raw[key] for key in RUNTIME_FIELDS},
            'routedWheelEvents': sum(raw['wheelRouting'].values()),
            'scope': 'One physical Razer-wheel development session; not a controlled comparison or external-app presentation measurement.',
            'pointerMetricScope': 'Distance between event position and a cursor read immediately before posting; includes cursor movement between reads.',
        },
        'releaseMicrobenchmark': {
            'paths': timings,
            'scope': 'Optimized local coordinator with cached identities and captured output; excludes global event posting, physical input, and external-app rendering.',
            'p95BudgetMs': 2,
        },
        'validation': {
            'functionalTestsPassed': test_count('functional'), 'uiTestsPassed': test_count('ui'),
            'uiSnapshotStates': len(list((ROOT / 'Tests/SmoothWheelAppCoreTests/Snapshots').glob('settings-*.png'))),
            'productionModuleLineCoverage': coverage['modules'],
            'coordinatorLineCoverage': coverage['files']['Sources/SmoothWheelAppCore/ScrollEngine.swift'],
            'scope': 'Coverage is line execution, not branch completeness; permission, tap installation and external-app rendering require live validation. Unlinked sources are counted as uncovered source lines.',
        },
    }
    destination = ROOT / 'docs/metrics' / f'v{args.version}.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print(f'Exported aggregate public metrics: {destination.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
