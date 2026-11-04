#!/bin/bash
# Regenerates the checked-in wayland-scanner output under Sources/CWayland from the
# system's wayland-protocols (run inside the Linux container or on a Linux host with
# libwayland-bin and wayland-protocols installed). SwiftPM has no build step for it,
# so the files are committed; see Sources/CWayland/include/CWayland.h.
set -e
cd "$(dirname "$0")/../../Sources/CWayland"
P=${WAYLAND_PROTOCOLS_DIR:-$(pkg-config --variable=pkgdatadir wayland-protocols)}
for spec in stable/xdg-shell/xdg-shell.xml unstable/xdg-decoration/xdg-decoration-unstable-v1.xml unstable/pointer-gestures/pointer-gestures-unstable-v1.xml; do
    name=$(basename "$spec" .xml)
    wayland-scanner client-header "$P/$spec" "include/$name-client-protocol.h"
    wayland-scanner private-code "$P/$spec" "protocols/$name-protocol.c"
done
echo "generated from wayland-protocols $(pkg-config --modversion wayland-protocols)"
