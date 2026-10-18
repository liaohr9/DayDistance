#!/bin/zsh
set -eu
cd "${0:A:h}/.."
diagnostic_build=$(mktemp -d "${TMPDIR:-/tmp/}daydistance-diagnostics.XXXXXX")
trap 'rm -rf "$diagnostic_build"' EXIT
sdk=$(xcrun --sdk macosx --show-sdk-path)
xcrun swiftc -parse-as-library -target arm64-apple-macos14.0 -sdk "$sdk" \
  Shared/Core/*.swift Shared/Platform/SharedContainer.swift \
  App/Services/WidgetMaintenance.swift App/Services/WidgetDiagnostics.swift Tests/Fixtures/WidgetDiagnosticsProbe.swift \
  -o "$diagnostic_build/probe"
"$diagnostic_build/probe"
