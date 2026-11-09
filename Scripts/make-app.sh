#!/usr/bin/env bash
# Builds uumail.app from the SwiftPM executable (no Xcode project needed).
set -euo pipefail
cd "$(dirname "$0")/.."
./Scripts/swiftw build -c release --product uumail
APP=".build/uumail.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/uumail" "$APP/Contents/MacOS/uumail"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>uumail</string>
    <key>CFBundleDisplayName</key><string>uumail</string>
    <key>CFBundleIdentifier</key><string>com.uumail.app</string>
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
echo "$APP"
