#!/bin/bash
set -euo pipefail
app="$1"
test -f "$app/Contents/Info.plist"
test -x "$app/Contents/MacOS/Aidoku"
codesign --verify --deep --strict "$app"
mkdir -p build
stage="$(mktemp -d /tmp/aidoku-dmg.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Aidoku.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname 'Aidoku macOS' -srcfolder "$stage" -ov -format UDZO build/Aidoku-macOS-arm64.dmg
hdiutil verify build/Aidoku-macOS-arm64.dmg
shasum -a 256 build/Aidoku-macOS-arm64.dmg > build/Aidoku-macOS-arm64.dmg.sha256
