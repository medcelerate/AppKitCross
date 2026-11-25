#!/bin/bash
# Liquid Glass reference captures (ADR-0052 stage 2). On a macOS 26 Mac:
#   bash tools/glass/capture-references.sh
# builds tools/glass/reference against Apple's AppKit (outside the package, so the port's
# AppKit does not shadow it) with the shared scene file, captures each scene with real
# NSGlassEffectViews into docs/images/glass/macos26-<scene>@2x.png (grant Screen Recording
# to the terminal when asked), draws the same scenes through the port
# (docs/images/glass/port-<scene>@2x.png) and prints the per-surface comparison for each.
# On an older macOS it skips the capture and compares whatever references are committed.
set -e
cd "$(dirname "$0")/../.."
OUT=docs/images/glass
TOOL=.build/glass-reference
mkdir -p "$OUT" .build
xcrun swiftc -O -o "$TOOL" tools/glass/reference/main.swift Examples/Glass/ReferenceScene.swift
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MAJOR" -ge 26 ]; then
  ARCH=$(uname -m)
  xcrun swiftc -O -D GLASS_CAPTURE -target "$ARCH-apple-macos26.0" -o "$TOOL-capture" \
    tools/glass/reference/main.swift Examples/Glass/ReferenceScene.swift Examples/Glass/ReferenceSceneGlass.swift
  "$TOOL-capture" capture "$OUT"
else
  echo "macOS $(sw_vers -productVersion): no NSGlassEffectView here, using the committed macos26-*.png"
fi
swift build -c release --product Glass >/dev/null
BIN=$(swift build -c release --show-bin-path)
for scene in light dark over-dark; do
  APPKITWIN_HOST_BACKEND=1 APPKITWIN_LIQUID_GLASS=1 "$BIN/Glass" --reference "$scene" "$OUT/port-$scene@2x.png"
  if [ -f "$OUT/macos26-$scene@2x.png" ]; then
    echo "== $scene"
    "$TOOL" compare "$OUT/macos26-$scene@2x.png" "$OUT/port-$scene@2x.png"
  fi
done
