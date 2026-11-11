#!/usr/bin/env python3
"""Synthesizes pointer and key input on the X server through the XTest extension
(ctypes, no xdotool needed). Used by scripted checks under Xvfb.

  x11-click.py move X Y          warp the pointer to screen coordinates
  x11-click.py click X Y         move there and click button 1
  x11-click.py key KEYSYM        press and release a key (e.g. Right, Left)
  x11-click.py scroll X Y N      N notches of horizontal scroll (buttons 6/7) at X Y
"""
import ctypes, sys, time

x11 = ctypes.CDLL("libX11.so.6")
xtst = ctypes.CDLL("libXtst.so.6")
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
x11.XFlush.argtypes = [ctypes.c_void_p]
x11.XStringToKeysym.argtypes = [ctypes.c_char_p]
x11.XStringToKeysym.restype = ctypes.c_ulong
x11.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
x11.XKeysymToKeycode.restype = ctypes.c_ubyte
xtst.XTestFakeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeButtonEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]

d = x11.XOpenDisplay(None)
if not d:
    sys.exit("no display")

def move(x, y):
    xtst.XTestFakeMotionEvent(d, -1, x, y, 0)
    x11.XFlush(d)

def button(b, down):
    xtst.XTestFakeButtonEvent(d, b, 1 if down else 0, 0)
    x11.XFlush(d)

cmd = sys.argv[1]
if cmd == "move":
    move(int(sys.argv[2]), int(sys.argv[3]))
elif cmd == "click":
    move(int(sys.argv[2]), int(sys.argv[3])); time.sleep(0.05)
    button(1, True); time.sleep(0.05); button(1, False)
elif cmd == "key":
    code = x11.XKeysymToKeycode(d, x11.XStringToKeysym(sys.argv[2].encode()))
    xtst.XTestFakeKeyEvent(d, code, 1, 0); x11.XFlush(d); time.sleep(0.05)
    xtst.XTestFakeKeyEvent(d, code, 0, 0); x11.XFlush(d)
elif cmd == "scroll":
    move(int(sys.argv[2]), int(sys.argv[3])); time.sleep(0.05)
    n = int(sys.argv[4])
    b = 7 if n > 0 else 6
    for _ in range(abs(n)):
        button(b, True); button(b, False); time.sleep(0.03)
x11.XFlush(d)
time.sleep(0.1)
