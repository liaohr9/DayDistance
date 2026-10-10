#!/bin/zsh
set -eu
cd "${0:A:h}/.."
batch_build=$(mktemp -d "${TMPDIR:-/tmp/}daydistance-batch.XXXXXX")
trap 'rm -rf "$batch_build"' EXIT
xcrun swiftc -parse-as-library -target arm64-apple-macos14.0 Shared/Core/*.swift \
 Shared/Platform/SharedContainer.swift App/Services/EventHistoryUndoManager.swift App/Stores/EventStore.swift \
 Tests/Fixtures/BatchProbe.swift -o "$batch_build/probe"
"$batch_build/probe" "$batch_build"
