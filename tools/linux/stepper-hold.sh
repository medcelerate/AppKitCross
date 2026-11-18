#!/bin/bash
# Holds the mouse on the Layout Demo's stepper under Xvfb and checks that the value
# autorepeats (ADR-0021): the stepper's text field goes from 3 to well past 4.
# Run inside the container: bash tools/linux/stepper-hold.sh
set -e
cd "$(dirname "$0")/../.."
Xvfb :98 -screen 0 1000x700x24 >/dev/null 2>&1 &
XVFB=$!
export DISPLAY=:98
sleep 1
APPKITWIN_LINUX_BACKEND=x11 APPKITWIN_LAYOUT_TAB=controls APPKITWIN_STEPPER_PROBE=1 "${BIN:-./.build/debug/HelloWindow}" --layout > /tmp/stepper-hold.log 2>&1 &
APP=$!
sleep 3
# The probe prints the stepper's screen position once the window is up.
read -r SX SY < <(grep "stepper at" /tmp/stepper-hold.log | tail -1 | awk '{print $3, $4}')
echo "stepper at $SX $SY"
python3 - "$SX" "$SY" <<'PY'
import ctypes, sys, time
x11 = ctypes.CDLL("libX11.so.6"); xtst = ctypes.CDLL("libXtst.so.6")
x11.XOpenDisplay.restype = ctypes.c_void_p; x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
x11.XFlush.argtypes = [ctypes.c_void_p]
xtst.XTestFakeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeButtonEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
d = x11.XOpenDisplay(None)
x, y = int(sys.argv[1]), int(sys.argv[2])
xtst.XTestFakeMotionEvent(d, -1, x, y, 0); x11.XFlush(d); time.sleep(0.2)
xtst.XTestFakeButtonEvent(d, 1, 1, 0); x11.XFlush(d)
time.sleep(1.5)
xtst.XTestFakeButtonEvent(d, 1, 0, 0); x11.XFlush(d)
time.sleep(0.3)
PY
sleep 0.5
kill $APP 2>/dev/null || true; wait $APP 2>/dev/null || true
kill $XVFB 2>/dev/null || true
grep "stepper value" /tmp/stepper-hold.log | tail -3   # "stepper value N +0.512s": offset since the first step of the hold
LAST=$(grep "stepper value" /tmp/stepper-hold.log | tail -1 | awk '{print $3}')
if [ -n "$LAST" ] && [ "$LAST" -ge 8 ]; then echo "autorepeat OK (3 -> $LAST after a 1.5 s hold)"; else echo "autorepeat FAILED (last value: ${LAST:-none})"; exit 1; fi
