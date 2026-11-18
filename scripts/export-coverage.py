#!/usr/bin/env python3
"""Merge all Swift Testing bundle profiles (SwiftPM may export only one bundle)."""
import shutil
import sys
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
output = root / "artifacts/coverage"
output.mkdir(parents=True, exist_ok=True)
profile_store = output / "profiles"
profile_store.mkdir(parents=True, exist_ok=True)
if "--collect" in sys.argv:
    profiles = sorted((root / ".build-coverage").rglob("*.profraw"))
    if not profiles:
        raise SystemExit("No fresh instrumented profiles found")
    for profile in profiles:
        shutil.copy2(profile, profile_store / profile.name)
    raise SystemExit(0)
profiles = sorted(profile_store.glob("*.profraw"))
binaries = sorted(p for p in (root / ".build-coverage").rglob("*.xctest/Contents/MacOS/*") if p.is_file() and p.suffix != ".dSYM")
if not profiles or not binaries:
    raise SystemExit("Missing instrumented test profiles or test binaries")
subprocess.run(["xcrun", "llvm-profdata", "merge", "-sparse", *map(str, profiles), "-o", str(output / "merged.profdata")], check=True)
command = ["xcrun", "llvm-cov", "export", "-instr-profile=" + str(output / "merged.profdata"), str(binaries[0])]
for binary in binaries[1:]:
    command += ["-object", str(binary)]
with (output / "llvm.json").open("w") as stream:
    subprocess.run(command, stdout=stream, check=True)
