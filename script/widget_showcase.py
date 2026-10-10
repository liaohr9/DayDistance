#!/usr/bin/env python3
"""Render real widget views in a disposable, unindexed app; no event storage."""
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile


def main():
    project = Path(__file__).resolve().parent.parent
    env = os.environ.copy()
    env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    sources = [project / "Shared/Core/L10n.swift", project / "Shared/Core/Event.swift", project / "Shared/Core/EventDates.swift", project / "Shared/Core/DayCounter.swift",
               project / "Shared/Core/WidgetPolicy.swift", project / "Tests/Fixtures/WidgetShowcase.swift"]
    sources += [project / "Shared/Core/EventDisplayFormatter.swift", project / "Shared/Core/WidgetManualSelection.swift"]
    sources += sorted((project / "Shared/Presentation").glob("*.swift"))
    with tempfile.TemporaryDirectory(prefix="daydistance-widget-ui-", suffix=".noindex") as temporary:
        app = Path(temporary) / "WidgetShowcase.app"
        macos = app / "Contents/MacOS"
        macos.mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "local.daydistance.widgetshowcase.qa", "CFBundleName": "WidgetShowcase",
            "CFBundleExecutable": "WidgetShowcase", "CFBundlePackageType": "APPL",
            "CFBundleDevelopmentRegion": "zh-Hans", "NSPrincipalClass": "NSApplication"}))
        binary = macos / "WidgetShowcase"
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", "arm64-apple-macos14.0",
                        *map(str, sources), "-o", str(binary)], env=env, check=True, timeout=90)
        print(f"Temporary widget UI: {app}", flush=True)
        process = subprocess.Popen([str(binary)])
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
