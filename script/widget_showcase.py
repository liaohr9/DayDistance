#!/usr/bin/env python3
"""Render real widget views in a disposable, unindexed app; no event storage."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--language', choices=['zh-Hans', 'en'], default='zh-Hans')
    args = parser.parse_args()
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
        resources = app / "Contents/Resources"
        shutil.copytree(project / "Shared/Core/Resources", resources)
        if args.language == 'en':
            fixture = project / "Tests/Fixtures/WidgetShowcase.swift"
            source = fixture.read_text()
            for chinese, english in {
                '日距 · 小组件': 'DayDistance · Widgets',
                '小组件，让时间一眼可见。': 'Time at a glance.',
                '日距': 'DayDistance',
                '小号 · 一个重要日子': 'Small · One important day',
                '中号 · 最多三个事件': 'Medium · Up to three events',
                '深色外观': 'Dark appearance',
                '选择事件、调整顺序，自定义图标与日期显示。': 'Choose events, reorder them, and customize icons and dates.',
                '京都之旅': 'Kyoto Trip',
                '第一场马拉松': 'My First Marathon',
                '开始学习钢琴': 'Learning Piano',
            }.items():
                source = source.replace(f'"{chinese}"', f'"{english}"')
            english_fixture = Path(temporary) / 'WidgetShowcase.swift'
            english_fixture.write_text(source)
            sources = [english_fixture if path == fixture else path for path in sources]
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "local.daydistance.widgetshowcase.qa." + Path(temporary).name.replace('.noindex', ''), "CFBundleName": "WidgetShowcase",
            "CFBundleExecutable": "WidgetShowcase", "CFBundlePackageType": "APPL",
            "CFBundleDevelopmentRegion": "zh-Hans", "CFBundleLocalizations": ["en", "zh-Hans"], "NSPrincipalClass": "NSApplication"}))
        binary = macos / "WidgetShowcase"
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", "arm64-apple-macos14.0",
                        *map(str, sources), "-o", str(binary)], env=env, check=True, timeout=90)
        print(f"Temporary widget UI: {app}", flush=True)
        process = subprocess.Popen([str(binary), '-AppleLanguages', f'({args.language})',
                                    '-AppleLocale', 'en_US' if args.language == 'en' else 'zh_CN'])
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
