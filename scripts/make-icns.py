"""Compile every standard and Retina icon representation with Apple's iconutil."""
from pathlib import Path
import subprocess
import sys
import tempfile

source, destination = (Path(arg).resolve() for arg in sys.argv[1:])
expected = {
    f"icon_{size}x{size}{scale}.png"
    for size in (16, 32, 128, 256, 512)
    for scale in ("", "@2x")
}
missing = expected - {path.name for path in source.glob("*.png")}
if missing:
    raise SystemExit(f"Missing icon representations: {sorted(missing)}")
subprocess.run(["/usr/bin/iconutil", "-c", "icns", str(source), "-o", str(destination)], check=True)
# Verify what macOS decodes, rather than trusting the container header alone.
with tempfile.TemporaryDirectory(prefix="smoothwheel-icon-check-") as temporary:
    decoded = Path(temporary) / "AppIcon.iconset"
    subprocess.run(["/usr/bin/iconutil", "-c", "iconset", str(destination), "-o", str(decoded)], check=True)
    missing = expected - {path.name for path in decoded.glob("*.png")}
    if missing:
        raise SystemExit(f"Compiled icon lost representations: {sorted(missing)}")
print("App icon verified: all ten standard and Retina representations.")
