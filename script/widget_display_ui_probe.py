#!/usr/bin/env python3
"""Render real widget views in a disposable, unindexed app; no event storage."""
import argparse
import os
import shutil
from pathlib import Path
import plistlib
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--english", action="store_true")
    args = parser.parse_args()
    project = Path(__file__).resolve().parent.parent
    env = os.environ.copy()
    env.setdefault("DEVELOPER_DIR", subprocess.check_output(["xcode-select", "-p"], text=True).strip())
    if args.english: env["DAYDISTANCE_WIDGET_PROBE_LANGUAGE"] = "en"
    sources = sorted((project / "Shared/Core").glob("*.swift"))
    sources += [project / "Tests/Fixtures/WidgetDisplayUIProbe.swift", project / "Shared/Platform/SharedContainer.swift"]
    sources += sorted((project / "Shared/Presentation").glob("*.swift"))
    with tempfile.TemporaryDirectory(prefix="daydistance-widget-ui-", suffix=".noindex") as temporary:
        app = Path(temporary) / "WidgetDisplayQA.app"
        macos = app / "Contents/MacOS"
        macos.mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "local.daydistance.widgetdisplay.qa", "CFBundleName": "WidgetDisplayQA",
            "CFBundleExecutable": "WidgetDisplayQA", "CFBundlePackageType": "APPL",
            "CFBundleDevelopmentRegion": "zh-Hans", "NSPrincipalClass": "NSApplication"}))
        shutil.copytree(project / "Shared/Core/Resources", app / "Contents/Resources")
        binary = macos / "WidgetDisplayQA"
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", "arm64-apple-macos14.0",
                        *map(str, sources), "-o", str(binary)], env=env, check=True, timeout=90)
        print(f"Temporary widget UI: {app}", flush=True)
        process = subprocess.Popen([str(binary)], env=env)
        try:
            process.wait()
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
            subprocess.run(["/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                            "-u", str(app)], check=False)


if __name__ == "__main__":
    main()
