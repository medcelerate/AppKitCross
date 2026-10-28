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
echo "== HelloWindow under Xvfb (X11 backend)"
Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
export DISPLAY=:99
sleep 1
APPKITWIN_LINUX_BACKEND=x11 ./.build/debug/HelloWindow &
APP=$!
sleep 3
xwd -root -silent | convert xwd:- /tmp/hellowindow-linux.png
echo "screenshot: /tmp/hellowindow-linux.png ($(stat -c %s /tmp/hellowindow-linux.png) bytes)"
kill $APP 2>/dev/null || true
wait $APP 2>/dev/null || true
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
