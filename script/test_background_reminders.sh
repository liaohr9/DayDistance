#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
backgroundScratch=$(mktemp -d /tmp/daydistance-background.XXXXXX)
trap 'rm -rf "$backgroundScratch"' EXIT
xcrun swiftc -parse-as-library Shared/Core/L10n.swift App/Services/BackgroundReminderController.swift Tests/Fixtures/BackgroundReminders/BackgroundReminderProbe.swift -o "$backgroundScratch/probe"
"$backgroundScratch/probe"
