#!/bin/bash
# Extracts Swift symbol graphs for the frameworks the port mirrors.
# macOS only (needs Xcode). Output: api-inventory/raw/*.symbols.json (git-ignored).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/api-inventory/raw"
SDK="$(xcrun --show-sdk-path)"
TARGET="${TARGET:-arm64-apple-macosx15.0}"
mkdir -p "$OUT"
for m in AppKit Foundation CoreGraphics QuartzCore CoreText; do
  echo "extracting $m"
  xcrun swift-symbolgraph-extract -module-name "$m" -sdk "$SDK" -target "$TARGET" \
    -output-dir "$OUT" -minimum-access-level public -pretty-print 2>/dev/null || true
done
sw_vers > "$OUT/../SDK-VERSION.txt"
xcrun swift --version 2>&1 | head -1 >> "$OUT/../SDK-VERSION.txt"
echo "sdk: $SDK" >> "$OUT/../SDK-VERSION.txt"
echo "done"
