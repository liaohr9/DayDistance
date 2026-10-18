#!/usr/bin/env python3
"""Exercise widget maintenance on disposable preferences; never register real widgets."""
import os, platform, subprocess, tempfile
from pathlib import Path
root = Path(__file__).resolve().parent.parent
env = dict(os.environ)
with tempfile.TemporaryDirectory(suffix=".noindex") as folder:
    binary = Path(folder) / "maintenance-probe"
    sources = list((root / "Shared/Core").glob("*.swift")) + [root / "App/Services/WidgetMaintenance.swift", root / "Tests/Fixtures/WidgetMaintenanceProbe.swift"]
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", f"{platform.machine()}-apple-macos14.0", *map(str, sources), "-o", str(binary)], env=env, check=True, timeout=90)
    subprocess.run([str(binary)], check=True, timeout=15)
