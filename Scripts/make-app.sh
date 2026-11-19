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

cp "Resources/Info.plist" "$APP/Contents/Info.plist"

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc signing failed"

{
  echo "commit: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo "built:  $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "config: release"
} > dist/build-info.txt

echo "published: $APP"
