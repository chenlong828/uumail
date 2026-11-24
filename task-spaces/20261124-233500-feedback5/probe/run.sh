#!/bin/sh
# Rebuild and run the W-M3-18 probes. Outputs are kept here as evidence; binaries and the
# Swift module cache are not committed.
set -e
cd "$(dirname "$0")"

compile() {
  name="$1"; shift
  xcrun swiftc -parse-as-library -module-cache-path .module-cache -o "$name" "$@" \
    -framework SwiftUI -framework AppKit
}

run() {
  name="$1"; out="$2"
  PROBE_OUT="$PWD/$out" "./$name"
}

compile message-row-click-probe MessageRowClickProbe.swift \
  ../../../Sources/uumail/CalendarSelection.swift \
  ../../../Sources/uumail/MessageRowClick.swift
run message-row-click-probe message-row-click.txt

compile mailbox-column-width-probe MailboxColumnWidthProbe.swift
run mailbox-column-width-probe column-width.txt

# Visual preview (manual): renders the production hour grid; screenshot is committed.
compile hour-grid-preview HourGridPreview.swift ../../../Sources/uumail/CalendarHourGrid.swift
echo "hour-grid-preview built; run it and screencapture -l <window> hour-grid.png"

rm -f message-row-click-probe mailbox-column-width-probe hour-grid-preview
rm -rf .module-cache
