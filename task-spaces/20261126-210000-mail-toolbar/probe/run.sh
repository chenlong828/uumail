#!/bin/sh
# Rebuild and run the W-M3-22 toolbar probes. Evidence stays here; binaries and the
# Swift module cache are not committed.
set -e
cd "$(dirname "$0")"
ROOT=../../..

compile() {
  name="$1"; shift
  xcrun swiftc -parse-as-library -module-cache-path .module-cache -o "$name" "$@" \
    "$ROOT/Sources/uumail/MailboxToolbar.swift" \
    "$ROOT/Sources/uumail/ToolbarTooltips.swift" \
    -framework SwiftUI -framework AppKit
}

run() {
  name="$1"; out="$2"
  "./$name" > "$out"
  cat "$out"
}

compile final-layout-probe FinalLayoutProbe.swift
run final-layout-probe final-layout.txt

compile stability-probe StabilityProbe.swift
run stability-probe stability.txt

rm -f final-layout-probe stability-probe
rm -rf .module-cache
