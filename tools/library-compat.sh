#!/bin/bash
# Builds Examples/LibraryCompat, the third-party SwiftUI library compatibility example
# (docs/compatibility/swiftui-libraries.md), on any platform.
#
# The third-party packages do not depend on AppKitWin, so AppKitWin's SwiftUI module has
# to be in the build's Modules directory before they compile: step 1 builds it, step 2
# builds the libraries and the example. With --probe, each library target is built on its
# own first and its error count and first error are printed, which is how the report's
# "builds" column is filled in; a library that fails to build is left out of the example
# by Examples/LibraryCompat/Package.swift and the probe is the way to re-check it.
#
#     tools/library-compat.sh            # build the example
#     tools/library-compat.sh --probe    # per-library build results, then the example
#     tools/library-compat.sh --run      # build, then run it (on macOS: headless screenshot)
set -e
cd "$(dirname "$0")/../Examples/LibraryCompat"
PROBE=0; RUN=0
for arg in "$@"; do case "$arg" in --probe) PROBE=1 ;; --run) RUN=1 ;; esac; done
# On macOS the host build's modules declare macOS 14 while the libraries declare 10.15-12,
# which the compiler refuses to mix; raising every target's deployment target to 14 is the
# only way to type-check them against AppKitWin's SwiftUI there (Windows and Linux have no
# deployment targets).
FLAGS=()
if [ "$(uname)" = Darwin ]; then FLAGS=(-Xswiftc -target -Xswiftc "$(uname -m)-apple-macosx14.0"); fi
# AppKitWin's modules import the C shims (CCairo, CD2D, ...) and a client of a module needs
# every clang module it imports; SwiftPM only passes those maps to targets that declare the
# dependency, so they are passed to every compile here.
for m in ../../Sources/C*/module.modulemap .build/debug/C*.build/module.modulemap; do
    [ -f "$m" ] && FLAGS+=(-Xcc -fmodule-map-file="$(cd "$(dirname "$m")" && pwd)/$(basename "$m")")
done
# ... and the system headers those maps include (Cairo, Pango, X11, D-Bus on Linux).
if [ "$(uname)" = Linux ] && command -v pkg-config >/dev/null; then
    for flag in $(pkg-config --cflags-only-I pangocairo x11 dbus-1 2>/dev/null); do FLAGS+=(-Xcc "$flag"); done
fi

echo "== step 1: AppKitWin's SwiftUI (and AppKit) into the Modules directory"
swift build --target SwiftUI "${FLAGS[@]}" 2>&1 | grep -E ": error:|Build complete|Compiling" | tail -3
if [ "$(uname)" != Darwin ]; then
    # Apple's AppKit re-exports these; the libraries import them by name.
    swift build --target ImageIO "${FLAGS[@]}" 2>&1 | grep -E ": error:|Build complete" | tail -2
fi

if [ "$PROBE" = 1 ]; then
    echo "== probe: each library on its own"
    for target in MarkdownUI SwiftUIIntrospect ConfettiSwiftUI Shimmer WrappingHStack SwiftUICharts Defaults Nuke NukeUI; do
        log=$(mktemp)
        if swift build --target "$target" "${FLAGS[@]}" >"$log" 2>&1; then
            echo "$target: builds"
        else
            errors=$(grep -c ": error: " "$log" || true)
            first=$(grep -m1 ": error: " "$log" | sed -E 's|^.*/checkouts/||')
            echo "$target: FAILS ($errors errors); first: $first"
        fi
        rm -f "$log"
    done
fi

echo "== step 2: the libraries and the example"
swift build "${FLAGS[@]}" 2>&1 | grep -E ": error:|Build complete|Compiling" | tail -5
if [ "$RUN" = 1 ]; then
    .build/debug/LibraryCompat "${APPKITWIN_LIBRARY_COMPAT_ARGS[@]}"
fi
