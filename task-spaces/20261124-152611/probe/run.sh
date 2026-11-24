#!/bin/sh
# Rebuild and run the W-M3-17 design probes. Outputs are kept in this directory as evidence;
# binaries and the Swift module cache are not committed.
set -e
cd "$(dirname "$0")"

run() {
  name="$1"; src="$2"; out="$3"
  echo "== $name"
  xcrun swiftc -parse-as-library -module-cache-path .module-cache -o "$name" "$src" \
    -framework SwiftUI -framework AppKit
  PROBE_OUT="$PWD/$out" "./$name"
  cat "$out"
}

run window-probe WindowCarrierProbe.swift window-carrier.txt
run content-sized-probe ContentSizedWindowProbe.swift content-sized.txt
run appkit-window-probe AppKitWindowProbe.swift appkit-window.txt
run click-catcher-probe ClickCatcherProbe.swift click-catcher.txt
