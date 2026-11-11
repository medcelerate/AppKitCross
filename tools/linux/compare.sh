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
# The Layout Demo's collection, grid and box tabs (ADR-0020).
APPKITWIN_LINUX_BACKEND=x11 APPKITWIN_LAYOUT_TAB=collection APPKITWIN_COLLECTION_SELECT=1 "${BIN:-./.build/debug/HelloWindow}" --layout --screenshot "$OUT"
APPKITWIN_LINUX_BACKEND=x11 APPKITWIN_LAYOUT_TAB=grid "${BIN:-./.build/debug/HelloWindow}" --layout --screenshot "$OUT"
APPKITWIN_LINUX_BACKEND=x11 APPKITWIN_LAYOUT_TAB=box "${BIN:-./.build/debug/HelloWindow}" --layout --screenshot "$OUT"
# The Layout Demo's Diffable tab after a shuffle, an insert, a delete and a reload (ADR-0029).
APPKITWIN_LINUX_BACKEND=x11 APPKITWIN_LAYOUT_TAB=diffable APPKITWIN_DIFFABLE_STEPS=shuffle,insert,delete,reload "${BIN:-./.build/debug/HelloWindow}" --layout --screenshot "$OUT"
# The Layout Demo's Combo, Outline and Pages tabs, and the Outline tab mirrored right to left.
for tab in combo outline pages; do
    APPKITWIN_LINUX_BACKEND=x11 APPKITWIN_LAYOUT_TAB=$tab "${BIN:-./.build/debug/HelloWindow}" --layout --screenshot "$OUT"
done
mkdir -p "$OUT/rtl"
APPKITWIN_LINUX_BACKEND=x11 APPKITWIN_LAYOUT_TAB=outline APPKITWIN_LAYOUT_DIRECTION=rtl "${BIN:-./.build/debug/HelloWindow}" --layout --screenshot "$OUT/rtl"
mv "$OUT/rtl/layout-outline-linux.png" "$OUT/layout-outline-rtl-linux.png"
rm -rf "$OUT/rtl"
# The combo box's list open (its own window): a capture of the X screen.
APPKITWIN_LINUX_BACKEND=x11 APPKITWIN_LAYOUT_TAB=combo APPKITWIN_COMBO_POPUP=1 "${BIN:-./.build/debug/HelloWindow}" --layout &
APP=$!
sleep 3
xwd -root -silent | convert xwd:- -trim "$OUT/layout-combo-open-linux.png"
kill $APP 2>/dev/null || true
wait $APP 2>/dev/null || true
