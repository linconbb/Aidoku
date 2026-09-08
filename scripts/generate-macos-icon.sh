#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_icon="Aidoku/App/Resources/Assets.xcassets/AppIcon.appiconset/Icon.png"
test -f "$source_icon"
mkdir -p build/AppIcon.iconset macOS/Resources
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$source_icon" --out "build/AppIcon.iconset/icon_$size""x$size.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$source_icon" --out "build/AppIcon.iconset/icon_$size""x$size@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o macOS/Resources/AppIcon.icns
test -s macOS/Resources/AppIcon.icns
