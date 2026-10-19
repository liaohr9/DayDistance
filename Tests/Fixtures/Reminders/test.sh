#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/../../.."
if [[ -z "${DEVELOPER_DIR:-}" && -d '/Volumes/haoran 1/Applications/Xcode.app/Contents/Developer' ]]; then
  export DEVELOPER_DIR='/Volumes/haoran 1/Applications/Xcode.app/Contents/Developer'
fi
reminderScratch=$(mktemp -d /tmp/daydistance-reminders.XXXXXX)
trap 'rm -rf "$reminderScratch"' EXIT
swift test --scratch-path "$reminderScratch/core" --filter ReminderPolicyTests
xcrun swiftc -parse-as-library Shared/Core/L10n.swift Shared/Core/Event.swift Shared/Core/EventDates.swift Shared/Core/DayCounter.swift Shared/Core/EventRepository.swift Shared/Core/AutomationProtocol.swift Shared/Core/ExportDestinationPolicy.swift Shared/Core/ReminderSchedulingLock.swift Shared/Core/ReminderPolicy.swift \
  App/Services/EventReminderService.swift Tests/Fixtures/Reminders/ReminderServiceProbe.swift -o "$reminderScratch/service-probe"
"$reminderScratch/service-probe"
