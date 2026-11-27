#!/bin/sh
# Real-gateway draft smoke for REQ-0044 (creates and deletes a throwaway draft in the
# account's server Drafts folder; credentials come from ~/.uumail.env). The compiled probe
# intentionally lives outside the app and uses a TEMPORARY MailStore, so the user's real
# local database is never touched.
#
#   ./run.sh build   # compile the probes against .build/debug
#   ./run.sh smoke   # upload -> verify server body -> delete -> verify gone
#   ./run.sh keys    # diagnose which SyncKey is usable after a draft write
#
# Evidence from the 2026-11-27 run: smoke3.txt (PASS) and keyprobe.txt (the write
# response's SyncKey is rejected; a fresh SyncKey=0 bootstrap is valid).
set -e
cd "$(dirname "$0")"
ROOT=../../..
MODULES="$ROOT/.build/debug/Modules"
OBJ="$ROOT/.build/debug"
BASE="$OBJ/EASClient.build/*.o $OBJ/EASAdapter.build/*.o $OBJ/MailDomain.build/*.o $OBJ/MeetingDomain.build/*.o $OBJ/SyncContract.build/*.o"

case "${1:-smoke}" in
  build)
    xcrun swiftc -parse-as-library -module-cache-path .module-cache -I "$MODULES" -o key-probe \
      KeyProbe.swift $BASE -framework Foundation -framework Security
    xcrun swiftc -parse-as-library -module-cache-path .module-cache -I "$MODULES" \
      -I "$ROOT/.build/checkouts/GRDB.swift/Sources/GRDBSQLite" -o draft-smoke DraftSmoke.swift \
      $BASE $OBJ/SyncEngine.build/*.o "$OBJ/GRDB.build/"*.o \
      $(ls "$OBJ"/MailStore.build/*.o | grep -v 'MailStore+Meetings') \
      -framework Foundation -framework Security
    ;;
  smoke)
    ./draft-smoke
    ;;
  keys)
    ./key-probe
    ;;
esac
