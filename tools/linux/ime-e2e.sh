#!/bin/bash
# End-to-end input method check on X11 (ADR-0047): ibus with ENGINE (default libpinyin;
# mozc-jp also installs) composing into TextEdit under Xvfb through XIM. Run in the Linux image:
#   docker run --rm -v "$PWD":/src -w /src appkitwin-linux bash tools/linux/ime-e2e.sh
# Prints the app's [textinput] trace; screenshots go to .build-linux/ime-*.png.
set -u
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq --no-install-recommends ibus ibus-libpinyin ibus-mozc xdotool imagemagick fonts-noto-cjk dbus-x11 x11-utils >/dev/null 2>&1 || { echo "apt failed"; exit 1; }
cd /src
swift build --scratch-path .build-linux --product TextEdit 2>&1 | grep -E "error|Compiling TextEdit|Build complete" | tail -3
Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
export DISPLAY=:99
sleep 1
eval "$(dbus-launch --sh-syntax)"
export LANG=C.UTF-8 LC_ALL=C.UTF-8
ibus-daemon -drx --xim >/tmp/ibus.log 2>&1
sleep 4
ibus engine "${ENGINE:-libpinyin}"; echo "ibus engine: $(ibus engine)"; ibus list-engine 2>/dev/null | grep -iE "pinyin|mozc" | head -3
export XMODIFIERS=@im=ibus GTK_IM_MODULE=ibus
APPKITWIN_LINUX_BACKEND=x11 APPKITWIN_TRACE_TEXTINPUT=1 ./.build-linux/debug/TextEdit >/tmp/app.log 2>&1 &
APP=$!
sleep 6
WID=$(xdotool search --onlyvisible --name "Untitled" | head -1)
echo "window $WID"
xdotool windowfocus --sync "$WID" 2>/dev/null; xdotool windowactivate "$WID" 2>/dev/null
sleep 1
xdotool type --delay 150 "nihao"
sleep 1
import -window root /src/.build-linux/ime-composing.png 2>/dev/null || xwd -root -silent | convert xwd:- /src/.build-linux/ime-composing.png
xdotool key --delay 200 space
sleep 1
import -window root /src/.build-linux/ime-converted.png 2>/dev/null || true
xdotool key --delay 200 Return
sleep 1
xdotool type --delay 150 "zhong"
sleep 0.5
sleep 1
echo "--- before escape"; tail -3 /tmp/app.log
xdotool key --delay 200 Escape
sleep 3
echo "--- after escape"; tail -6 /tmp/app.log
xdotool type --delay 150 "ma"
sleep 1
xdotool key --delay 200 BackSpace BackSpace
sleep 2
echo "--- after backspaces"; tail -6 /tmp/app.log
import -window root /src/.build-linux/ime-final.png 2>/dev/null || true
kill $APP 2>/dev/null; sleep 1
echo "--- app trace"; grep -E "textinput|error|Fatal" /tmp/app.log | head -60
echo "--- ibus log"; tail -5 /tmp/ibus.log
