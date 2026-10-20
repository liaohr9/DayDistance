#!/usr/bin/env python3
"""Host real views on disposable events in a temporary, unindexed QA bundle."""
import argparse
import os
import shutil
from pathlib import Path
import plistlib
import subprocess
from disk_ui_probe import probe_folder
from lifecycle_ui_probe import lifecycle_source


def restore_data_permissions(root):
    data = Path(root) / "data"
    if not data.is_symlink() and data.is_dir() and data.resolve().parent == Path(root).resolve():
        data.chmod(0o700)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("list", "faults", "read-corrupt", "read-newer", "disk-full", "lifecycle", "expiration"), default="list")
    parser.add_argument("--sdk", type=Path, help="Explicit local SDK for QA compilation when full Xcode is unavailable")
    parser.add_argument("--language", choices=("zh-Hans", "en"))
    args = parser.parse_args()
    sdk_flags = ["-sdk", str(args.sdk)] if args.sdk else []
    project = Path(__file__).resolve().parent.parent
    env = os.environ.copy()
    if args.language: env["DAYDISTANCE_UI_LANGUAGE"] = args.language
    sources = sorted((project / "Shared/Core").glob("*.swift"))
    sources += sorted((project / "Shared/Presentation").glob("*.swift"))
    sources += [project / "Shared/Platform/SharedContainer.swift"] + sorted((project / "App/Stores").glob("*.swift"))
    sources += sorted((project / "App/Views").glob("*.swift"))
    sources += sorted((project / "App/Services").glob("*.swift"))
    if args.mode != "lifecycle":
        sources += [project / "Tests/Fixtures/ListUIProbe.swift"]
    with probe_folder(disk=args.mode == "disk-full") as temporary:
        if args.mode == "lifecycle":
            host = Path(temporary) / "LifecycleApp.swift"
            host.write_text(lifecycle_source((project / "App/DayDistanceApp.swift").read_text()))
            sources += [project / "Tests/Fixtures/LifecycleUIProbe.swift", host]
        app = Path(temporary) / "日距列表验证.app"
        contents = app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        binary = str(contents / "MacOS/DayDistanceUIProbe")
        subprocess.run(["/usr/bin/xcrun", "swiftc", "-parse-as-library", "-target", "arm64-apple-macos14.0", *sdk_flags,
                        *map(str, sources), "-o", binary], env=env, check=True, timeout=120)
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "local.daydistance.uiprobe", "CFBundleExecutable": "DayDistanceUIProbe",
            "CFBundleName": "日距列表验证", "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "14.0",
            "CFBundleDevelopmentRegion": "zh-Hans",
        }))
        shutil.copytree(project / "Shared/Core/Resources", contents / "Resources")
        if args.mode not in ("list", "expiration"):
            subprocess.run(["/usr/bin/xcrun", "swiftc", "-parse-as-library", *sdk_flags,
                            str(project / "Shared/Core/L10n.swift"), str(project / "Shared/Core/Event.swift"), str(project / "Shared/Core/EventDates.swift"), str(project / "Shared/Core/EventRepository.swift"), str(project / "Shared/Core/AutomationProtocol.swift"), str(project / "Shared/Core/ExportDestinationPolicy.swift"),
                            str(project / "Tests/Fixtures/UIWriterProbe.swift"), "-o", str(Path(temporary) / "writer")],
                           env=env, check=True, timeout=90)
        print(f"Temporary UI probe: {app}", flush=True)
        print(f"{60 if args.mode == 'list' else 3} disposable events; press Command-Q to exit and remove the QA bundle and data.", flush=True)
        process = subprocess.Popen([binary, temporary, args.mode], env=env)
        try:
            code = process.wait()
            if code:
                raise subprocess.CalledProcessError(code, [binary, temporary, args.mode])
        finally:
            # Interrupted test runners must not leave a child using deleted data.
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            # Don't leave a QA registration after the disposable host exits.
            subprocess.run(["/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                            "-u", str(app)], check=False)
            # Fault tests may deliberately make only their data directory read-only.
            restore_data_permissions(temporary)


if __name__ == "__main__":
    main()
