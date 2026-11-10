#!/bin/bash
# Renders the comparison screenshots (docs/comparisons.md) for the Linux column under Xvfb.
set -e
cd "$(dirname "$0")/../.."
OUT=${1:-docs/images/compare}
Xvfb :97 -screen 0 1600x1000x24 >/dev/null 2>&1 &
export DISPLAY=:97
sleep 1
APPKITWIN_LINUX_BACKEND=x11 "${BIN:-./.build/debug/HelloWindow}" --swiftui --layout --screenshot "$OUT"
# The SwiftUI demo's Data tab (Table) as a second capture.
APPKITWIN_LINUX_BACKEND=x11 APPKITWIN_DEMO_TAB=data "${BIN:-./.build/debug/HelloWindow}" --swiftui --screenshot "$OUT"
# The Layout Demo's collection, grid and box tabs (ADR-0019).
APPKITWIN_LINUX_BACKEND=x11 APPKITWIN_LAYOUT_TAB=collection APPKITWIN_COLLECTION_SELECT=1 "${BIN:-./.build/debug/HelloWindow}" --layout --screenshot "$OUT"
APPKITWIN_LINUX_BACKEND=x11 APPKITWIN_LAYOUT_TAB=grid "${BIN:-./.build/debug/HelloWindow}" --layout --screenshot "$OUT"
APPKITWIN_LINUX_BACKEND=x11 APPKITWIN_LAYOUT_TAB=box "${BIN:-./.build/debug/HelloWindow}" --layout --screenshot "$OUT"
