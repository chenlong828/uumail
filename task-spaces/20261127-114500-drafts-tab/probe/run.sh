#!/bin/sh
# Rebuild the W-M3-23 draft probes and re-capture the two screenshots. Binaries and the
# Swift module cache are not committed; the MailStore object list filters the stale
# MailStore+Meetings.swift.o that SwiftPM leaves behind from an earlier refactor.
set -e
cd "$(dirname "$0")"
ROOT=../../..
MODULES="$ROOT/.build/debug/Modules"
GRDBMAP="$ROOT/.build/checkouts/GRDB.swift/Sources/GRDBSQLite"
OBJ="$ROOT/.build/debug"
PKG="$OBJ/Presentation.build/*.o $OBJ/MailDomain.build/*.o $OBJ/Outbox.build/*.o"
LIBS="$OBJ/Presentation.build/*.o $OBJ/MailDomain.build/*.o $OBJ/Scenes.build/*.o $OBJ/SyncEngine.build/*.o $OBJ/Outbox.build/*.o $OBJ/SyncContract.build/*.o $OBJ/HTMLSupport.build/*.o $OBJ/MeetingDomain.build/*.o $OBJ/GRDB.build/*.o"

xcrun swiftc -parse-as-library -module-cache-path .module-cache -I "$MODULES" -I "$GRDBMAP" \
  -o draft-list-probe DraftListProbe.swift \
  "$ROOT/Sources/uumail/DraftListView.swift" \
  "$ROOT/Sources/uumail/EmptyState.swift" \
  "$ROOT/Sources/uumail/FontSizeStyle.swift" \
  $PKG $(ls "$OBJ"/MailStore.build/*.o | grep -v 'MailStore+Meetings') \
  -framework SwiftUI -framework AppKit -lsqlite3

xcrun swiftc -parse-as-library -module-cache-path .module-cache -I "$MODULES" -I "$GRDBMAP" \
  -o embedded-compose-probe EmbeddedComposeProbe.swift \
  "$ROOT/Sources/uumail/ComposeView.swift" \
  "$ROOT/Sources/uumail/ComposeEditor.swift" \
  "$ROOT/Sources/uumail/ComposeFormatBar.swift" \
  "$ROOT/Sources/uumail/RecipientForm.swift" \
  "$ROOT/Sources/uumail/RecipientTextField.swift" \
  "$ROOT/Sources/uumail/RecipientTextField+AppKit.swift" \
  "$ROOT/Sources/uumail/FontSizeStyle.swift" \
  $LIBS $(ls "$OBJ"/MailStore.build/*.o | grep -v 'MailStore+Meetings') \
  -framework SwiftUI -framework AppKit -framework WebKit -lsqlite3

capture() {
  name="$1"; out="$2"; log="$3"
  rm -f "$log"
  "./$name" > "$log" 2>&1 &
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.4
    [ -s "$log" ] && break
  done
  number=$(grep -o 'number=[0-9]*' "$log" | head -1 | cut -d= -f2)
  sleep 1.2
  screencapture -x -o -l "$number" "$out"
  sleep 2
  echo "captured $out (window=$number)"
}

capture draft-list-probe draft-list.png draft-list.txt
capture embedded-compose-probe embedded-compose.png embedded-compose.txt

rm -f draft-list-probe embedded-compose-probe
rm -rf .module-cache
