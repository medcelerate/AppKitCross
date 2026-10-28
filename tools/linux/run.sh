#!/bin/bash
# Runs the test suite on the host backend, then HelloWindow under Xvfb for a screenshot.
set -e
cd "$(dirname "$0")/../.."
echo "== tests (host backend)"
APPKITWIN_HOST_BACKEND=1 swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -5
echo "== HelloWindow under Xvfb"
Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
export DISPLAY=:99
sleep 1
./.build/debug/HelloWindow &
APP=$!
sleep 3
xwd -root -silent | convert xwd:- /tmp/hellowindow-linux.png
echo "screenshot: /tmp/hellowindow-linux.png ($(stat -c %s /tmp/hellowindow-linux.png) bytes)"
kill $APP 2>/dev/null || true
wait $APP 2>/dev/null || true
echo "done"
