#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
work='development/.build'
app='AniOnMac.app'
mkdir -p "$work" "$app/Contents/MacOS" "$app/Contents/Resources"
for arch in arm64 x86_64; do
  xcrun clang -arch "$arch" -mmacosx-version-min=14.0 -fobjc-arc -Wall -Wextra -framework AppKit development/native/cursorctl.m -o "$work/cursorctl-$arch"
  xcrun clang -arch "$arch" -mmacosx-version-min=14.0 -fobjc-arc -c development/native/CursorRefresh.m -o "$work/refresh-$arch.o"
  xcrun swiftc -parse-as-library -swift-version 5 -target "$arch-apple-macosx14.0" -module-cache-path "$work/swift-cache" development/native/ANIConverter.swift development/native/CursorOutline.swift -o "$work/anicore-$arch"
  xcrun swiftc -O -parse-as-library -swift-version 5 -target "$arch-apple-macosx14.0" -module-cache-path "$work/swift-cache" development/app/Studio.swift development/app/Views.swift development/native/CursorOutline.swift "$work/refresh-$arch.o" -o "$work/app-$arch"
done
lipo -create "$work/app-arm64" "$work/app-x86_64" -output "$app/Contents/MacOS/AniOnMac"
for tool in anicore cursorctl; do
  lipo -create "$work/$tool-arm64" "$work/$tool-x86_64" -output "$app/Contents/Resources/$tool"
  codesign --force --sign - "$app/Contents/Resources/$tool"
done
cp development/resources/*.json "$app/Contents/Resources/"
cp development/resources/AppIcon.icns "$app/Contents/Resources/"
python3 - <<'PY'
import plistlib
from pathlib import Path
p=Path('AniOnMac.app/Contents/Info.plist')
p.write_bytes(plistlib.dumps(dict(CFBundleExecutable='AniOnMac',CFBundleIdentifier='io.anionmac.app',CFBundleName='AniOnMac',CFBundleDisplayName='AniOnMac',CFBundleIconFile='AppIcon',CFBundlePackageType='APPL',CFBundleShortVersionString='0.2.0',CFBundleVersion='6',LSMinimumSystemVersion='14.0',NSHighResolutionCapable=True)))
PY
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
echo "Built $app (Universal: arm64 + x86_64)"
