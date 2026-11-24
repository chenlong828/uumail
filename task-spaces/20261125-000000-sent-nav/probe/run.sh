#!/bin/sh
# Rebuild and run the W-M3-19 UI probes. Binaries and the module cache are not committed.
set -e
cd "$(dirname "$0")"

compile() {
  name="$1"; shift
  xcrun swiftc -parse-as-library -module-cache-path .module-cache -o "$name" "$@" \
    -framework SwiftUI -framework AppKit
}

compile toolbar-probe ToolbarProbe.swift
echo "toolbar-probe built; run it, then screencapture -l <window> toolbar-nav.png"

compile two-column-probe TwoColumnProbe.swift
./two-column-probe | tee two-column.txt

rm -f toolbar-probe two-column-probe
rm -rf .module-cache
