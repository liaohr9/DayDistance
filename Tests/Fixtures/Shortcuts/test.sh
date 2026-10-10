#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/../../.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
shortcutScratch=$(mktemp -d /tmp/daydistance-shortcuts.XXXXXX)
trap 'rm -rf "$shortcutScratch"' EXIT
swift test --scratch-path "$shortcutScratch/core.noindex" --filter ShortcutRepositoryTests
xcrun swiftc -parse-as-library -target arm64-apple-macosx14.0 Shared/Core/*.swift Shared/Platform/SharedContainer.swift \
  App/Services/EventHistoryUndoManager.swift App/Stores/EventStore.swift App/Services/ShortcutEventService.swift \
  App/Intents/*.swift Tests/Fixtures/Shortcuts/ShortcutIntentProbe.swift -o "$shortcutScratch/shortcut-probe"
"$shortcutScratch/shortcut-probe"
