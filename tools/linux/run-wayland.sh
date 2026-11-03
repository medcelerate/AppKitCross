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
# The Metal tab on the Vulkan device (ADR-0012), presented through the Wayland window.
timeout 6 ./.build/debug/HelloWindow --metal --metal-log >/tmp/hellowindow-wayland-metal.log 2>&1 &
APP=$!
sleep 4
grim /tmp/hellowindow-linux-wayland-metal.png
wait $APP 2>/dev/null || true
grep -E "^device|Vulkan|^frame" /tmp/hellowindow-wayland-metal.log | head -4
echo "screenshot: /tmp/hellowindow-linux-wayland-metal.png ($(stat -c %s /tmp/hellowindow-linux-wayland-metal.png) bytes)"
kill $SWAY 2>/dev/null || true
wait $SWAY 2>/dev/null || true
