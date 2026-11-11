#!/bin/bash
# Reproduces the Pages tab interaction on the X11 backend under Xvfb: finds the pink
# page in a screen capture, clicks Next, Blue, presses Right/Left, and reports the page colour.
set -e
cd /src
swift build --scratch-path .build-linux --product HelloWindow 2>&1 | grep -E "error:" | head -3 || true
Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
export DISPLAY=:99
sleep 1
APPKITWIN_LINUX_BACKEND=x11 APPKITWIN_LAYOUT_TAB=pages APPKITWIN_TRACE=${TRACE:-} .build-linux/debug/HelloWindow --layout 2>/tmp/app.log &
APP=$!
sleep 4
shot() { xwd -root -silent | convert xwd:- /tmp/$1.png; convert /tmp/$1.png /tmp/$1.ppm; }
python3 - <<'PY' > /tmp/geom.txt
import struct
def read(name):
    with open(f"/tmp/{name}.ppm","rb") as f:
        assert f.readline().strip()==b"P6"
        line=f.readline()
        while line.startswith(b"#"): line=f.readline()
        w,h=map(int,line.split()); f.readline()
        return w,h,f.read()
PY
shot before
python3 - <<'PY'
def read(name):
    with open(f"/tmp/{name}.ppm","rb") as f:
        f.readline(); line=f.readline()
        while line.startswith(b"#"): line=f.readline()
        w,h=map(int,line.split()); f.readline()
        return w,h,f.read()
w,h,d=read("before")
xs=[];ys=[]
for y in range(0,h,2):
    row=d[y*w*3:(y+1)*w*3]
    for x in range(0,w,2):
        r,g,b=row[x*3],row[x*3+1],row[x*3+2]
        if abs(r-255)<6 and abs(g-217)<8 and abs(b-217)<8: xs.append(x); ys.append(y)
if not xs: print("NOPINK"); raise SystemExit
print(min(xs),min(ys),max(xs),max(ys))
PY
read X0 Y0 X1 Y1 < <(python3 - <<'PY'
def read(name):
    with open(f"/tmp/{name}.ppm","rb") as f:
        f.readline(); line=f.readline()
        while line.startswith(b"#"): line=f.readline()
        w,h=map(int,line.split()); f.readline()
        return w,h,f.read()
w,h,d=read("before")
xs=[];ys=[]
for y in range(0,h,2):
    row=d[y*w*3:(y+1)*w*3]
    for x in range(0,w,2):
        r,g,b=row[x*3],row[x*3+1],row[x*3+2]
        if abs(r-255)<6 and abs(g-217)<8 and abs(b-217)<8: xs.append(x); ys.append(y)
print(min(xs),min(ys),max(xs),max(ys))
PY
)
echo "pink page: $X0 $Y0 $X1 $Y1"
CX=$(( (X0+X1)/2 )); CY=$(( (Y0+Y1)/2 ))
pixel() { convert /tmp/$1.png -format "%[pixel:p{$CX,$CY}]" info:; echo; }
echo "page colour before: $(pixel before)"
python3 tools/linux/x11-click.py click $((X0+96)) $((Y0-20)); sleep 1.5; shot next
echo "after Next:   $(pixel next)"
python3 tools/linux/x11-click.py click $((X0+258)) $((Y0-20)); sleep 1.5; shot blue
echo "after Blue:   $(pixel blue)"
python3 tools/linux/x11-click.py click $CX $CY; python3 tools/linux/x11-click.py key Left; sleep 1.5; shot left
echo "after Left:   $(pixel left)"
python3 tools/linux/x11-click.py scroll $CX $CY -3; sleep 1.5; shot wheel
echo "after wheel:  $(pixel wheel)"
cp /tmp/next.png /src/docs/images/compare/x11-after-next.png
kill $APP 2>/dev/null || true; wait $APP 2>/dev/null || true
echo "== app log"; grep -v "^$" /tmp/app.log | tail -20
