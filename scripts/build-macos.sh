#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
python3 scripts/generate-macos-project.py
xcodebuild -project Aidoku-macOS.xcodeproj -scheme Aidoku-macOS \
  -configuration Release -sdk macosx -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages \
  -skipPackagePluginValidation \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tee build/macos-build.log
app=build/DerivedData/Build/Products/Release/Aidoku.app
test -x "$app/Contents/MacOS/Aidoku"
codesign --force --sign - --timestamp=none --entitlements macOS/macOS.entitlements "$app"
codesign --verify --deep --strict --verbose=2 "$app"
xcrun vtool -show-build "$app/Contents/MacOS/Aidoku" | tee build/macho-platform.txt
grep -q 'platform MACOS' build/macho-platform.txt
test "$(lipo -archs "$app/Contents/MacOS/Aidoku")" = arm64
bash scripts/package-macos.sh "$app"
