#!/usr/bin/env bash
# Builds uumail.app and publishes it into dist/.
# Every completed development milestone should end with a run of this script.
set -euo pipefail
cd "$(dirname "$0")/.."

./Scripts/swiftw build -c release --product uumail

APP="dist/uumail.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/uumail" "$APP/Contents/MacOS/uumail"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>uumail</string>
    <key>CFBundleDisplayName</key><string>uumail</string>
    <key>CFBundleIdentifier</key><string>com.uumail.app</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleExecutable</key><string>uumail</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc signing failed"

{
  echo "commit: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo "built:  $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "config: release"
} > dist/build-info.txt

echo "published: $APP"
