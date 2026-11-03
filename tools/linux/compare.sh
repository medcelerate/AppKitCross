#!/bin/bash
# Renders the comparison screenshots (docs/comparisons.md) for the Linux column under Xvfb.
set -e
cd "$(dirname "$0")/../.."
OUT=${1:-docs/images/compare}
Xvfb :97 -screen 0 1600x1000x24 >/dev/null 2>&1 &
export DISPLAY=:97
sleep 1
APPKITWIN_LINUX_BACKEND=x11 "${BIN:-./.build/debug/HelloWindow}" --swiftui --layout --screenshot "$OUT"
