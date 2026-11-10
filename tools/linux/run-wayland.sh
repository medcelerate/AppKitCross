#!/bin/bash
# Runs HelloWindow on the Wayland backend under a headless sway (wlroots headless backend,
# pixman renderer, no seat) and screenshots the output with grim. Must run unprivileged.
set -e
cd "$(dirname "$0")/../.."
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp/appkitwin-xdg-$(id -u)}
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
rm -f "$XDG_RUNTIME_DIR"/wayland-*
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 LIBSEAT_BACKEND=noop
export XCURSOR_THEME=DMZ-White XCURSOR_SIZE=24
unset DISPLAY
sway -c tools/linux/sway-headless.config >/tmp/sway.log 2>&1 &
SWAY=$!
for i in $(seq 1 50); do
    SOCKET=$(ls "$XDG_RUNTIME_DIR"/wayland-? 2>/dev/null | head -1)
    [ -n "$SOCKET" ] && break
    sleep 0.2
done
if [ -z "$SOCKET" ]; then echo "sway did not start:"; tail -20 /tmp/sway.log; exit 1; fi
export WAYLAND_DISPLAY=$(basename "$SOCKET")
sleep 1
./.build/debug/HelloWindow >/tmp/hellowindow-wayland.log 2>&1 &
APP=$!
sleep 3
if ! kill -0 $APP 2>/dev/null; then echo "HelloWindow exited:"; cat /tmp/hellowindow-wayland.log; kill $SWAY; exit 1; fi
grim /tmp/hellowindow-linux-wayland.png
echo "screenshot: /tmp/hellowindow-linux-wayland.png ($(stat -c %s /tmp/hellowindow-linux-wayland.png) bytes)"
kill $APP 2>/dev/null || true
wait $APP 2>/dev/null || true
# Client-side decorations (ADR-0015): sway grants server-side decorations, so the package's
# own frame is forced with APPKITWIN_WAYLAND_DECORATIONS=client (what every window gets
# under a compositor without xdg-decoration, such as Mutter). The band, buttons, shadow and
# rounded corners are in the screenshot; sway's tree must see the window geometry (the
# frame without the shadow margin) as the window's rectangle, and a resize through the
# compositor must land on the frame: the app's frame trace and sway's rectangle agree.
echo "== HelloWindow with client-side decorations under sway"
export SWAYSOCK=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -1)
APPKITWIN_WAYLAND_DECORATIONS=client APPKITWIN_TRACE=1 ./.build/debug/HelloWindow >/tmp/hellowindow-wayland-csd.log 2>&1 &
APP=$!
sleep 3
if ! kill -0 $APP 2>/dev/null; then echo "HelloWindow (CSD) exited:"; cat /tmp/hellowindow-wayland-csd.log; kill $SWAY; exit 1; fi
grim /tmp/hellowindow-linux-wayland-csd.png
echo "screenshot: /tmp/hellowindow-linux-wayland-csd.png ($(stat -c %s /tmp/hellowindow-linux-wayland-csd.png) bytes)"
rects() { swaymsg -t get_tree | jq -r '.. | select(.app_id? == "AppKitCross") | "rect \(.rect.width)x\(.rect.height) window_rect \(.window_rect.width)x\(.window_rect.height) geometry \(.geometry.x),\(.geometry.y) \(.geometry.width)x\(.geometry.height)"' | head -1; }
echo "sway sees: $(rects)"
swaymsg '[app_id="AppKitCross"] resize set width 500 px height 400 px' >/dev/null
sleep 2
echo "after resize set 500x400: $(rects)"
CSD_RECT=$(swaymsg -t get_tree | jq -r '.. | select(.app_id? == "AppKitCross") | "\(.rect.width)x\(.rect.height)"' | head -1)
FRAME_LINE=$(grep -E "frame '.*width: 500\\.0, height: 400\\.0" /tmp/hellowindow-wayland-csd.log | tail -1)
grim /tmp/hellowindow-linux-wayland-csd-resized.png
kill $APP 2>/dev/null || true
wait $APP 2>/dev/null || true
echo "frame trace: ${FRAME_LINE:-<no 500x400 frame line>}"
if [ "$CSD_RECT" != "500x400" ] || [ -z "$FRAME_LINE" ]; then
    echo "FAIL: the window geometry does not match the compositor's rectangle"; grep -E "frame|unimplemented|Fatal" /tmp/hellowindow-wayland-csd.log | tail -5; kill $SWAY; exit 1
fi
# A sheet under sway (ADR-0019): the alert is a wl_subsurface of the window, so sway's tree
# holds one AppKitCross toplevel, not two, and the screenshot shows the alert over the window.
echo "== Sheets --alert under sway (the sheet is a subsurface of its window)"
APPKITWIN_TRACE=1 ./.build/debug/Sheets --alert >/tmp/sheets-wayland.log 2>&1 &
APP=$!
sleep 3
if ! kill -0 $APP 2>/dev/null; then echo "Sheets exited:"; cat /tmp/sheets-wayland.log; kill $SWAY; exit 1; fi
grim /tmp/sheets-linux-wayland.png
TOPLEVELS=$(swaymsg -t get_tree | jq -r '[.. | select(.app_id? == "AppKitCross")] | length')
kill $APP 2>/dev/null || true
wait $APP 2>/dev/null || true
echo "screenshot: /tmp/sheets-linux-wayland.png ($(stat -c %s /tmp/sheets-linux-wayland.png) bytes); AppKitCross toplevels in sway's tree: $TOPLEVELS"
grep -E "wayland sheet|unimplemented|Fatal" /tmp/sheets-wayland.log | head -3
if [ "$TOPLEVELS" != "1" ] || ! grep -q "wayland sheet .* subsurface of" /tmp/sheets-wayland.log; then
    echo "FAIL: the sheet is not a subsurface of its window"; kill $SWAY; exit 1
fi
# The Metal tab on the Vulkan device (ADR-0012), presented through a VkSwapchainKHR on a
# subsurface of the Wayland window; the log lines are as in run.sh (device, then corner and
# centre pixels every 30 frames and the presentation path), and the screenshot must show
# the static clear colour (#3399E6) where the subsurface is.
timeout 6 ./.build/debug/HelloWindow --metal --metal-log --metal-static >/tmp/hellowindow-wayland-metal.log 2>&1 &
APP=$!
sleep 4
grim /tmp/hellowindow-linux-wayland-metal.png
wait $APP 2>/dev/null || true
grep -E "^device|Vulkan|pipeline failed|^frame" /tmp/hellowindow-wayland-metal.log | head -5
echo "screenshot: /tmp/hellowindow-linux-wayland-metal.png ($(stat -c %s /tmp/hellowindow-linux-wayland-metal.png) bytes)"
count_pixels() { convert "$1" -depth 8 -format %c histogram:info:- 2>/dev/null | grep -i "$2" | awk -F: '{s+=$1} END {print s+0}'; }
METAL_PIXELS=$(count_pixels /tmp/hellowindow-linux-wayland-metal.png "#3399E6")
echo "presented clear-colour pixels on screen: $METAL_PIXELS"
if grep -q "presentation=swap chain" /tmp/hellowindow-wayland-metal.log && [ "$METAL_PIXELS" -lt 10000 ]; then
    echo "FAIL: the swap chain presented but the screenshot does not show the clear colour"; kill $SWAY; exit 1
fi
# The presentation tests on the Wayland backend (the test binary swift test built; this
# user cannot write to .build): the swap chain on a subsurface, resize, the format fallback.
echo "== Metal presentation tests on the Wayland backend"
XCTEST=$(ls .build/debug/*PackageTests.xctest 2>/dev/null | head -1)
if [ -x "$XCTEST" ]; then
    "$XCTEST" AppKitTests.MetalVulkanPresentationTests 2>&1 | grep -E "Fatal error|error: -\[|Executed .* tests|Test Suite .* (failed|passed)|MetalVulkanPresentationTests:" | tail -6
else
    echo "skipped: no test binary (run swift test first)"
fi
# Monitor DPI change: a second headless output at scale 2 is added and HelloWindow is moved
# onto it. The compositor sends wl_surface.leave/enter, WaylandWindow.outputsDidChange picks
# the new scale, and NSWindow logs "backing scale '...' 2.0" (APPKITWIN_TRACE). The window's
# logical size in sway's tree (points) must not change; the 2x screenshot shows it crisp.
echo "== monitor scale change: HelloWindow moved to a 2x output"
swaymsg create_output >/dev/null
swaymsg output HEADLESS-2 resolution 1280x800 position 1280 0 scale 2 background '#6e3c91' solid_color >/dev/null
APPKITWIN_TRACE=1 ./.build/debug/HelloWindow >/tmp/hellowindow-wayland-dpi.log 2>&1 &
APP=$!
sleep 3
logical() { swaymsg -t get_tree | jq -r '.. | select(.app_id? == "AppKitCross") | "\(.rect.width)x\(.rect.height)"' | head -1; }
BEFORE=$(logical)
swaymsg '[app_id="AppKitCross"] move window to output HEADLESS-2' >/dev/null
sleep 2
AFTER=$(logical)
grim -o HEADLESS-2 /tmp/hellowindow-linux-wayland-2x.png
kill $APP 2>/dev/null || true
wait $APP 2>/dev/null || true
SCALE_LINE=$(grep -E "backing scale .* 2\.0" /tmp/hellowindow-wayland-dpi.log | head -1)
echo "logical size before: $BEFORE after: $AFTER; trace: ${SCALE_LINE:-<no backing scale line>}"
echo "screenshot: /tmp/hellowindow-linux-wayland-2x.png ($(stat -c %s /tmp/hellowindow-linux-wayland-2x.png) bytes)"
if [ -z "$SCALE_LINE" ] || [ "$BEFORE" != "$AFTER" ] || [ -z "$BEFORE" ]; then
    echo "FAIL: the window did not keep its logical size or did not change scale"; cat /tmp/hellowindow-wayland-dpi.log | grep -E "backing|frame" | head; kill $SWAY; exit 1
fi
# The Metal tab on the 2x output: the swap chain is re-created at twice the pixels (the
# subsurface keeps the view's points through its buffer scale) and keeps presenting.
echo "== Metal tab moved to the 2x output: the swap chain follows the backing scale"
timeout 8 ./.build/debug/HelloWindow --metal --metal-log --metal-static >/tmp/hellowindow-wayland-metal-2x.log 2>&1 &
APP=$!
sleep 2
swaymsg '[app_id="AppKitCross"] move window to output HEADLESS-2' >/dev/null
sleep 3
grim -o HEADLESS-2 /tmp/hellowindow-linux-wayland-metal-2x.png
wait $APP 2>/dev/null || true
grep -E "^frame" /tmp/hellowindow-wayland-metal-2x.log | awk '!seen[$0 ~ /876x548/]++' | head -3
METAL_2X=$(grep -c "size 876x548 presentation=swap chain" /tmp/hellowindow-wayland-metal-2x.log)
METAL_2X_PIXELS=$(count_pixels /tmp/hellowindow-linux-wayland-metal-2x.png "#3399E6")
echo "frames at 2x through the swap chain: $METAL_2X; presented clear-colour pixels on the 2x output: $METAL_2X_PIXELS"
echo "screenshot: /tmp/hellowindow-linux-wayland-metal-2x.png ($(stat -c %s /tmp/hellowindow-linux-wayland-metal-2x.png) bytes)"
if [ "$METAL_2X" -lt 1 ] || [ "$METAL_2X_PIXELS" -lt 40000 ]; then
    echo "FAIL: the Metal tab did not present at 2x on the second output"; grep -E "^frame|Vulkan" /tmp/hellowindow-wayland-metal-2x.log | tail -5; kill $SWAY; exit 1
fi
kill $SWAY 2>/dev/null || true
wait $SWAY 2>/dev/null || true
