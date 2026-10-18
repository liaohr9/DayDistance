#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
case "$MODE" in run|--verify|--debug|--logs|--telemetry|--build-only|--install-only) ;; *) echo 'usage: build_and_run.sh [--build-only|--install-only|--verify|--debug|--logs|--telemetry]' >&2; exit 2;; esac
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
if [[ ! -d "$DEVELOPER_DIR" ]]; then echo "Xcode not found: $DEVELOPER_DIR" >&2; exit 1; fi
CONFIGURATION="${CONFIGURATION:-DebugLocal}"
BUILD_DIR="$ROOT_DIR/build.noindex"
CANDIDATE="$BUILD_DIR/Build/Products/$CONFIGURATION/DayDistance.app"
APP_BUNDLE="/Applications/日距.app"
mkdir -p "$BUILD_DIR"
cleanup_registration() {
 python3 "$ROOT_DIR/script/install_app.py" "$CANDIDATE" --destination "$APP_BUNDLE" --cleanup-registration
}
cleanup_on_exit() {
 local result=$?
 trap - EXIT
 if ! cleanup_registration; then result=1; fi
 exit "$result"
}
trap cleanup_on_exit EXIT
if [[ "$MODE" != --install-only ]]; then
 python3 "$ROOT_DIR/script/test_install.py" > "$BUILD_DIR/install-tests.log" 2>&1 || { cat "$BUILD_DIR/install-tests.log"; exit 1; }
 python3 "$ROOT_DIR/script/test_lifecycle_ui_probe.py" > "$BUILD_DIR/lifecycle-tests.log" 2>&1 || { cat "$BUILD_DIR/lifecycle-tests.log"; exit 1; }
 python3 "$ROOT_DIR/script/test_ui_probe_control.py" > "$BUILD_DIR/ui-probe-control-tests.log" 2>&1 || { cat "$BUILD_DIR/ui-probe-control-tests.log"; exit 1; }
 python3 "$ROOT_DIR/script/test_disk_ui_probe.py" > "$BUILD_DIR/disk-probe-tests.log" 2>&1 || { cat "$BUILD_DIR/disk-probe-tests.log"; exit 1; }
 python3 "$ROOT_DIR/script/test_release.py" > "$BUILD_DIR/release-tests.log" 2>&1 || { cat "$BUILD_DIR/release-tests.log"; exit 1; }
 python3 "$ROOT_DIR/script/test_storage.py" > "$BUILD_DIR/storage-tests.log" 2>&1 || { cat "$BUILD_DIR/storage-tests.log"; exit 1; }
 python3 "$ROOT_DIR/script/test_widget_intent.py" > "$BUILD_DIR/widget-intent-tests.log" 2>&1 || { cat "$BUILD_DIR/widget-intent-tests.log"; exit 1; }
 python3 "$ROOT_DIR/script/test_widget_smart_lists.py" > "$BUILD_DIR/widget-smart-tests.log" 2>&1 || { cat "$BUILD_DIR/widget-smart-tests.log"; exit 1; }
 python3 "$ROOT_DIR/script/test_smart_list_store.py" > "$BUILD_DIR/smart-store-tests.log" 2>&1 || { cat "$BUILD_DIR/smart-store-tests.log"; exit 1; }
 python3 "$ROOT_DIR/script/test_undo.py" > "$BUILD_DIR/undo-tests.log" 2>&1 || { cat "$BUILD_DIR/undo-tests.log"; exit 1; }
 zsh "$ROOT_DIR/script/test_background_reminders.sh" > "$BUILD_DIR/background-reminder-tests.log" 2>&1 || { cat "$BUILD_DIR/background-reminder-tests.log"; exit 1; }
 python3 "$ROOT_DIR/script/test_release_notes.py" > "$BUILD_DIR/release-notes-tests.log" 2>&1 || { cat "$BUILD_DIR/release-notes-tests.log"; exit 1; }
 python3 "$ROOT_DIR/script/test_widget_maintenance.py" > "$BUILD_DIR/widget-maintenance-tests.log" 2>&1 || { cat "$BUILD_DIR/widget-maintenance-tests.log"; exit 1; }
 python3 "$ROOT_DIR/script/test_updates.py" > "$BUILD_DIR/update-tests.log" 2>&1 || { cat "$BUILD_DIR/update-tests.log"; exit 1; }
 python3 "$ROOT_DIR/script/test_settings.py" > "$BUILD_DIR/settings-tests.log" 2>&1 || { cat "$BUILD_DIR/settings-tests.log"; exit 1; }
 zsh "$ROOT_DIR/script/test_batch.sh" > "$BUILD_DIR/batch-tests.log" 2>&1 || { cat "$BUILD_DIR/batch-tests.log"; exit 1; }
 zsh "$ROOT_DIR/script/test_dock_icon.sh" > "$BUILD_DIR/dock-icon-tests.log" 2>&1 || { cat "$BUILD_DIR/dock-icon-tests.log"; exit 1; }
 zsh "$ROOT_DIR/script/test_diagnostics.sh" > "$BUILD_DIR/diagnostics-tests.log" 2>&1 || { cat "$BUILD_DIR/diagnostics-tests.log"; exit 1; }
 zsh "$ROOT_DIR/Tests/Fixtures/Reminders/test.sh" > "$BUILD_DIR/reminder-tests.log" 2>&1 || { tail -60 "$BUILD_DIR/reminder-tests.log"; exit 1; }
 zsh "$ROOT_DIR/Tests/Fixtures/Shortcuts/test.sh" > "$BUILD_DIR/shortcut-tests.log" 2>&1 || { tail -60 "$BUILD_DIR/shortcut-tests.log"; exit 1; }
 xcodebuild -project "$ROOT_DIR/DayDistance.xcodeproj" -scheme DayDistance -configuration "$CONFIGURATION" -destination 'platform=macOS' -derivedDataPath "$BUILD_DIR" build > "$BUILD_DIR/build.log" 2>&1 || { tail -80 "$BUILD_DIR/build.log"; exit 1; }
 cleanup_registration
 python3 "$ROOT_DIR/script/test_widget_summary.py" "$CANDIDATE" > "$BUILD_DIR/widget-summary-tests.log" 2>&1 || { cat "$BUILD_DIR/widget-summary-tests.log"; exit 1; }
 (cd "$ROOT_DIR" && swift test --scratch-path "$BUILD_DIR/CoreTests") > "$BUILD_DIR/core-tests.log" 2>&1 || { tail -80 "$BUILD_DIR/core-tests.log"; exit 1; }
 /usr/bin/codesign --verify --deep --strict "$CANDIDATE"
 printf 'Build and core tests succeeded: %s\n' "$CANDIDATE"
fi
if [[ "$MODE" == --build-only ]]; then exit 0; fi
python3 "$ROOT_DIR/script/install_app.py" "$CANDIDATE" --destination "$APP_BUNDLE" --backups "$BUILD_DIR/backups"
cleanup_registration
# Candidate is a verified, project-owned build product; the installed app and ZIP remain.
python3 - "$CANDIDATE" <<'PY'
import plistlib, shutil, sys
from pathlib import Path
app = Path(sys.argv[1])
assert app.name == "DayDistance.app" and "build.noindex" in app.parts
assert plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleIdentifier"] == "local.daydistance.mac"
shutil.rmtree(app)
PY
if [[ "$MODE" == --install-only ]]; then exit 0; fi
# Finish LaunchServices cleanup before launching: another -f registration after
# cold-start recovery can invalidate the background task's new BTM identifier.
trap - EXIT
case "$MODE" in
 --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/DayDistance";;
 --logs) open "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "DayDistance"';;
 --telemetry) open "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "local.daydistance.mac"';;
 --verify) open "$APP_BUNDLE"; for attempt in {1..20}; do if /bin/ps -axo comm= | /usr/bin/grep -Fx "$APP_BUNDLE/Contents/MacOS/DayDistance" >/dev/null; then echo 'Launch verified: installed DayDistance process running'; exit 0; fi; sleep 0.25; done; echo 'Installed app process did not start' >&2; exit 1;;
 run) open "$APP_BUNDLE";;
esac
