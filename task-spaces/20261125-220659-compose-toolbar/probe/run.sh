#!/bin/sh
# Rebuild the W-M3-21 compose-toolbar probe and re-capture the three layouts.
# Evidence stays in this directory; the binary and the Swift module cache are not committed.
#
# Linking note: SwiftPM leaves stale objects for files merged away by earlier refactors
# (MailStore+Meetings.swift.o), so the MailStore objects are filtered below.
set -e
cd "$(dirname "$0")"
ROOT=../../..
MODULES="$ROOT/.build/debug/Modules"
GRDBMAP="$ROOT/.build/checkouts/GRDB.swift/Sources/GRDBSQLite"
OBJ="$ROOT/.build/debug"

xcrun swiftc -parse-as-library -module-cache-path .module-cache \
  -I "$MODULES" -I "$GRDBMAP" \
  -o compose-toolbar-probe ComposeToolbarProbe.swift \
  "$ROOT/Sources/uumail/ComposeView.swift" \
  "$ROOT/Sources/uumail/ComposeEditor.swift" \
  "$ROOT/Sources/uumail/ComposeFormatBar.swift" \
  "$ROOT/Sources/uumail/RecipientForm.swift" \
  "$ROOT/Sources/uumail/RecipientTextField.swift" \
  "$ROOT/Sources/uumail/RecipientTextField+AppKit.swift" \
  "$ROOT/Sources/uumail/FontSizeStyle.swift" \
  "$OBJ"/Presentation.build/*.o \
  "$OBJ"/Scenes.build/*.o \
  "$OBJ"/SyncEngine.build/*.o \
  $(ls "$OBJ"/MailStore.build/*.o | grep -v 'MailStore+Meetings') \
  "$OBJ"/Outbox.build/*.o \
  "$OBJ"/MailDomain.build/*.o \
  "$OBJ"/SyncContract.build/*.o \
  "$OBJ"/HTMLSupport.build/*.o \
  "$OBJ"/MeetingDomain.build/*.o \
  "$OBJ"/GRDB.build/*.o \
  -framework SwiftUI -framework AppKit -framework WebKit -lsqlite3

capture() {
  font="$1"; width="$2"; height="$3"; out="$4"
  rm -f "$out.txt"
  PROBE_OUT="$PWD/$out.txt" PROBE_FONT="$font" PROBE_WIDTH="$width" PROBE_HEIGHT="$height" \
    ./compose-toolbar-probe >/dev/null 2>&1 &
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    sleep 0.4
    [ -s "$out.txt" ] && break
  done
  number=$(grep -o 'window=[0-9]*' "$out.txt" | head -1 | cut -d= -f2)
  sleep 2
  screencapture -x -o -l "$number" "$out"
  sleep 3
  echo "captured $out (font=$font width=$width height=$height window=$number)"
}

capture 100 900 760 compose-900.png
capture 100 480 760 compose-480.png
capture 225 480 760 compose-225-480.png

rm -f compose-toolbar-probe
rm -rf .module-cache
