#!/usr/bin/env python3
"""Summarize LLVM coverage for every production source; gate tested engine modules."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Floors are reviewed with the report, not silently lowered when a test fails.
FLOORS = {"ScrollCore": 90, "ScrollEvents": 85, "ScrollTiming": 75, "ScrollEngine.swift": 60}


def report(source, output):
    coverage = json.loads(Path(source).read_text())
    files = {}
    for unit in coverage["data"]:
        for item in unit["files"]:
            filename = Path(item["filename"])
            try:
                relative = filename.relative_to(ROOT)
            except ValueError:
                continue
            if relative.parts[0] != "Sources":
                continue
            lines = item["summary"]["lines"]
            files[str(relative)] = {"covered": lines["covered"], "count": lines["count"]}
    if not files:
        raise SystemExit("No production coverage found")
    # Include source files absent from the export as uncovered, rather than hiding them.
    for path in (ROOT / "Sources").rglob("*.swift"):
        relative = str(path.relative_to(ROOT))
        if relative not in files:
            files[relative] = {"covered": 0, "count": len(path.read_text().splitlines())}
    groups = {}
    for filename, lines in files.items():
        module = Path(filename).parts[1]
        group = groups.setdefault(module, {"covered": 0, "count": 0})
        for key in group:
            group[key] += lines[key]
    for values in [*files.values(), *groups.values()]:
        values["percent"] = round(100 * values["covered"] / max(values["count"], 1), 2)
    results = {"modules": groups, "files": files, "lineCoverageFloors": FLOORS}
    destination = Path(output)
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "summary.json").write_text(json.dumps(results, indent=2) + "\n")
    rows = ["# Production line coverage", "", "| Module | Covered / executable lines | Coverage |", "|---|---:|---:|"]
    for name, values in sorted(groups.items()):
        rows.append(f'| {name} | {values["covered"]} / {values["count"]} | {values["percent"]:.2f}% |')
    rows += ["", "The entry point, permission prompts, live AX discovery and global event posting require live validation.",
             "Coverage measures executed lines; replay snapshots check routing and emitted packets. Neither proves external-app rendering quality.", ""]
    (destination / "summary.md").write_text("\n".join(rows))
    failures = []
    for key, floor in FLOORS.items():
        values = groups.get(key) or next((v for p, v in files.items() if Path(p).name == key), None)
        if values is None or values["percent"] < floor:
            failures.append(f"{key}: {values and values['percent']}% < {floor}%")
    print("\n".join(rows))
    if failures:
        raise SystemExit("Coverage gate failed: " + "; ".join(failures))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("coverage_json")
    parser.add_argument("--output", default=str(ROOT / "artifacts/coverage"))
    args = parser.parse_args()
    report(args.coverage_json, args.output)
