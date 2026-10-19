#!/usr/bin/env python3
"""Compile the real AppIntent and verify its selection boundary on in-memory fixtures."""
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    project = Path(__file__).resolve().parent.parent
    environment = os.environ.copy()
    sources = ["Shared/Core/L10n.swift", "Shared/Core/LocalBackupRepository.swift", "App/Services/EventHistoryUndoManager.swift", "Shared/Core/Event.swift", "Shared/Core/DayCounter.swift", "Shared/Core/ExportDestinationPolicy.swift", "Shared/Core/EventDisplayFormatter.swift", "Shared/Core/EventDates.swift", "Shared/Core/EventRepository.swift", "Shared/Core/AutomationProtocol.swift", "Shared/Core/WidgetPolicy.swift", "Shared/Core/WidgetManualSelection.swift",
               "Shared/Platform/SharedContainer.swift", "Shared/Presentation/DayEntry.swift", "Shared/Presentation/EventTheme.swift", "Shared/Presentation/WidgetViews.swift", "Widget/EventIntent.swift", "Tests/Fixtures/WidgetIntentProbe.swift"]
    sources = ["Shared/Core/SmartList.swift", "Shared/Core/SmartListRepository.swift"] + sources
    provider_sources = sources[:-1] + ["Widget/DayDistanceWidget.swift"]
    subprocess.run(["/usr/bin/xcrun", "swiftc", "-parse-as-library", "-typecheck",
                    *[str(project / s) for s in provider_sources]], env=environment, check=True, timeout=90)
    with tempfile.TemporaryDirectory(suffix=".noindex") as temporary:
        binary = str(Path(temporary) / "widget-intent-probe")
        subprocess.run(["/usr/bin/xcrun", "swiftc", "-parse-as-library", *[str(project / s) for s in sources],
                        "-o", binary], env=environment, check=True, timeout=90)
        subprocess.run([binary], check=True, timeout=10)


if __name__ == "__main__": main()
