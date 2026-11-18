#!/usr/bin/env python3
"""Gate optimized local callback measurements, not external application FPS."""
import json
import math
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text())
for name in ["nativeCallback", "smoothCallback", "backgroundRendererCallback", "frameEmission"]:
    result = report[name]
    if result["samples"] < 1000:
        raise SystemExit(f"Insufficient samples: {name}")
    p95 = result["p95Ms"]
    if not math.isfinite(p95) or not 0 <= p95 <= 2:
        raise SystemExit(f"{name}: p95 {p95}ms exceeds 2ms budget or is invalid")
    print(f"{name}: p95 {p95:.4f}ms; max {result['maximumMs']:.4f}ms")
