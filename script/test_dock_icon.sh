#!/bin/zsh
set -eu
cd "${0:A:h}/.."
icon_build=$(mktemp -d "${TMPDIR:-/tmp/}daydistance-icon.XXXXXX")
trap 'rm -rf "$icon_build"' EXIT
xcrun swiftc -parse-as-library -target arm64-apple-macos14.0 \
  Shared/Core/*.swift App/Services/DockIconController.swift Tests/Fixtures/DockIconProbe.swift \
  -o "$icon_build/probe"
"$icon_build/probe" "$PWD/Resources/DockIcons"
