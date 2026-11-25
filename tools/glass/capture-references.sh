#!/bin/bash
# Liquid Glass reference captures (ADR-0052 stage 2).
#
#   bash tools/glass/capture-references.sh            # on a macOS 26 Mac: capture + port + compare
#   bash tools/glass/capture-references.sh --port     # any Mac: port captures + compare only
#
# On macOS 26 it builds tools/glass/reference against Apple's AppKit (outside the package, so
# the port's AppKit does not shadow it) with the shared scene files
# (Examples/Glass/ReferenceScene.swift, ReferenceSceneGlass.swift), and captures every scene
# (light, dark, over-dark, interactive) in every state (rest; hover and press for interactive)
# with real NSGlassEffectViews and SwiftUI glass, at the display's scale and at 1x, into
# docs/images/glass/macos26-<scene>-<state>@<n>x.png with docs/images/glass/macos26-manifest.json.
# Grant the terminal Screen Recording (System Settings > Privacy & Security) when asked, and
# Accessibility for the press captures (without it they are skipped and the manifest says so).
# Keep the Mac awake and unlocked, the pointer still, and the terminal from covering the top
# left of the main display while it runs (about a minute).
#
# Then, on any Mac, it draws the same scenes through the port at 2x and 1x
# (docs/images/glass/port-<scene>-<state>@<n>x.png, port-manifest.json) and prints the
# per-surface comparison for every pair it has.
set -e
cd "$(dirname "$0")/../.."
OUT=docs/images/glass
TOOL=.build/glass-reference
mkdir -p "$OUT" .build
PORT_ONLY=0
[ "$1" = "--port" ] && PORT_ONLY=1

xcrun swiftc -O -o "$TOOL" tools/glass/reference/main.swift Examples/Glass/ReferenceScene.swift
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "$PORT_ONLY" = 0 ]; then
  if [ "$MAJOR" -ge 26 ]; then
    ARCH=$(uname -m)
    xcrun swiftc -O -D GLASS_CAPTURE -target "$ARCH-apple-macos26.0" -o "$TOOL-capture" \
      tools/glass/reference/main.swift Examples/Glass/ReferenceScene.swift Examples/Glass/ReferenceSceneGlass.swift
    "$TOOL-capture" capture "$OUT"
  else
    echo "macOS $(sw_vers -productVersion): no NSGlassEffectView here; comparing against the committed macos26-*.png"
  fi
fi

swift build -c release --product Glass >/dev/null
BIN=$(swift build -c release --show-bin-path)
SCENES="light:rest dark:rest over-dark:rest interactive:rest interactive:hover interactive:press"
{
  echo '{'
  echo '  "generator": "tools/glass/capture-references.sh",'
  echo "  \"commit\": \"$(git rev-parse --short HEAD)\","
  echo '  "renderer": "Examples/Glass --reference on the host backend, APPKITWIN_LIQUID_GLASS=1, the GPU program",'
  echo '  "captures": ['
  first=1
  for scale in 2 1; do
    for pair in $SCENES; do
      scene=${pair%%:*}; state=${pair##*:}
      file="port-$scene-$state@${scale}x.png"
      APPKITWIN_HOST_BACKEND=1 APPKITWIN_LIQUID_GLASS=1 APPKITWIN_HOST_SCALE=$scale "$BIN/Glass" --reference "$scene" "$state" "$OUT/$file" >&2
      [ $first = 1 ] || echo ','
      first=0
      printf '    {"file": "%s", "scene": "%s", "state": "%s", "scale": %s}' "$file" "$scene" "$state" "$scale"
    done
  done
  echo
  echo '  ]'
  echo '}'
} > "$OUT/port-manifest.json"

for scale in 2 1; do
  for pair in $SCENES; do
    scene=${pair%%:*}; state=${pair##*:}
    mac="$OUT/macos26-$scene-$state@${scale}x.png"
    if [ -f "$mac" ]; then
      echo "== $scene $state @${scale}x"
      "$TOOL" compare "$scene" "$mac" "$OUT/port-$scene-$state@${scale}x.png"
    fi
  done
done
