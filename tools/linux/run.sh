#!/bin/bash
# Runs the test suite on the host backend, then HelloWindow under Xvfb for a screenshot.
# With --wayland it also runs HelloWindow under a headless sway and screenshots it with
# grim (see run-wayland.sh). Screenshots land in /tmp, and in $APPKITWIN_OUT when set.
set -e
cd "$(dirname "$0")/../.."
WAYLAND=0
for arg in "$@"; do case "$arg" in --wayland) WAYLAND=1 ;; esac; done
echo "== tests (host backend)"
APPKITWIN_HOST_BACKEND=1 swift test 2>&1 | grep -E "Fatal error|error: -\[|Executed .* tests|Test Suite .* (failed|passed)|^error:" | tail -12
Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
export DISPLAY=:99
sleep 1
# An accessibility bus (ADR-0013): a session bus for org.a11y.Bus, then the launcher starts
# the registry (at-spi2-registryd) and publishes the bus address.
if command -v dbus-daemon >/dev/null && [ -x /usr/libexec/at-spi-bus-launcher ]; then
    export DBUS_SESSION_BUS_ADDRESS
    DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address)
    /usr/libexec/at-spi-bus-launcher --launch-immediately >/dev/null 2>&1 &
    sleep 1
    export AT_SPI_BUS_ADDRESS
    AT_SPI_BUS_ADDRESS=$(dbus-send --session --print-reply=literal --dest=org.a11y.Bus /org/a11y/bus org.a11y.Bus.GetAddress 2>/dev/null | tr -d ' \n')
    echo "accessibility bus: ${AT_SPI_BUS_ADDRESS:-none}"
fi
echo "== tests on the X11 backend under Xvfb (XDND, CLIPBOARD, the event pump, AT-SPI)"
swift test --filter "X11DragDropTests|X11ClipboardTests|MainQueueTests|AtspiTests" 2>&1 | grep -E "Fatal error|error: -\[|Executed .* tests|Test Suite .* (failed|passed)|^error:" | tail -6
echo "== HelloWindow under Xvfb (X11 backend)"
APPKITWIN_LINUX_BACKEND=x11 ./.build/debug/HelloWindow &
APP=$!
sleep 3
xwd -root -silent | convert xwd:- /tmp/hellowindow-linux.png
echo "screenshot: /tmp/hellowindow-linux.png ($(stat -c %s /tmp/hellowindow-linux.png) bytes)"
if [ -n "$AT_SPI_BUS_ADDRESS" ]; then
    echo "== AT-SPI2 tree of HelloWindow (tools/linux/atspi-probe.py)"
    python3 tools/linux/atspi-probe.py --expect-hello
fi
kill $APP 2>/dev/null || true
wait $APP 2>/dev/null || true
echo "== HelloWindow Metal tab under Xvfb (Vulkan device, ADR-0012)"
# The Metal tab names its device, then logs the drawable's corner and centre pixels every
# 30 frames after that frame's command buffer completes. The corner follows the clear
# colour; the centre is the triangle (a blend of its vertex colours, around BGRA
# [111, 118, 135]) on lavapipe, and the clear colour again on the reference device,
# which does not rasterize. A "Vulkan device unavailable" line says why it fell back.
APPKITWIN_LINUX_BACKEND=x11 timeout 6 ./.build/debug/HelloWindow --metal --metal-log >/tmp/hellowindow-linux-metal.log 2>&1 &
APP=$!
sleep 4
xwd -root -silent | convert xwd:- /tmp/hellowindow-linux-metal.png
wait $APP 2>/dev/null || true
grep -E "^device|Vulkan|pipeline failed|^frame" /tmp/hellowindow-linux-metal.log | head -5
echo "screenshot: /tmp/hellowindow-linux-metal.png ($(stat -c %s /tmp/hellowindow-linux-metal.png) bytes)"
if [ "$WAYLAND" = 1 ]; then
    echo "== HelloWindow under headless sway (Wayland backend)"
    # sway refuses to run as root; the image has an unprivileged user for it.
    if [ "$(id -u)" = 0 ]; then
        runuser -u appkitwin -- bash tools/linux/run-wayland.sh
    else
        bash tools/linux/run-wayland.sh
    fi
fi
if [ -n "$APPKITWIN_OUT" ] && [ -d "$APPKITWIN_OUT" ]; then
    cp /tmp/hellowindow-linux*.png "$APPKITWIN_OUT"/
fi
echo "done"
