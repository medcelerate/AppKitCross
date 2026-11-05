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
# pipefail: the greps that trim the build output must not hide a failed build (CI).
set -eo pipefail
cd "$(dirname "$0")/../Examples/LibraryCompat"
PROBE=0; RUN=0
for arg in "$@"; do case "$arg" in --probe) PROBE=1 ;; --run) RUN=1 ;; esac; done
# On macOS the host build's modules declare macOS 14 while the libraries declare 10.15-12,
# which the compiler refuses to mix; raising every target's deployment target to 14 is the
# only way to type-check them against AppKitWin's SwiftUI there (Windows and Linux have no
# deployment targets).
# Plain diagnostics: swiftc colours them on Windows, which would hide "error:" from the greps.
FLAGS=(-Xswiftc -no-color-diagnostics)
if [ "$(uname)" = Darwin ]; then FLAGS+=(-Xswiftc -target -Xswiftc "$(uname -m)-apple-macosx14.0"); fi
# AppKitWin's modules import the C shims (CCairo, CD2D, ...) and a client of a module needs
# every clang module it imports; SwiftPM only passes those maps to targets that declare the
# dependency, so they are passed to every compile here: the hand-written maps in Sources
# and the ones SwiftPM synthesises for the other C targets in the build directory (after
# step 1), plus the shims' include directories since the Windows shim headers include each
# other (cdirectwrite.h includes cd2d.h).
# An absolute path clang accepts: on Windows (Git Bash) `pwd -W` gives C:/..., not /c/....
abs() { (cd "$1" && (pwd -W 2>/dev/null || pwd)); }
seen=""
add_maps() {
    local m name
    for m in "$@"; do
        [ -f "$m" ] || continue
        name=$(basename "$(dirname "$m")"); [ "$name" = include ] && name=$(basename "$(dirname "$(dirname "$m")")")
        case " $seen " in *" $name "*) continue ;; esac
        seen="$seen $name"
        FLAGS+=(-Xcc -fmodule-map-file="$(abs "$(dirname "$m")")/$(basename "$m")")
    done
}
add_maps ../../Sources/C*/module.modulemap ../../Sources/C*/include/module.modulemap
for d in ../../Sources/C*/include ../../Sources/C*; do
    [ -d "$d" ] && FLAGS+=(-Xcc -I"$(abs "$d")")
done
# ... and the system headers those maps include (Cairo, Pango, X11, D-Bus on Linux).
if [ "$(uname)" = Linux ] && command -v pkg-config >/dev/null; then
    for flag in $(pkg-config --cflags-only-I pangocairo x11 dbus-1 2>/dev/null); do FLAGS+=(-Xcc "$flag"); done
fi

echo "== step 1: AppKitWin's SwiftUI (and AppKit) into the Modules directory"
# A second full build of the package lands here; say how much room it has (CI runners).
df -h . 2>/dev/null | tail -1 || true
# Runs a build, printing its last lines on success and the whole log on failure.
build() {
    local out
    if out=$(swift build "$@" "${FLAGS[@]}" 2>&1); then
        echo "$out" | grep -E "error:|Build complete|Compiling" | tail -3 || true
    else
        # The diagnostics first (the tail alone can be all warnings): lines of the form
        # path:line:col: error:, <unknown>:0: error: or a bare error:, not the source
        # snippets the compiler prints under them (which may contain "error:" as text).
        # `|| true`: under `set -eo pipefail` a grep with no match would end the script
        # before the log is shown.
        echo "$out" | grep -E "error:|undefined symbol|lld-link" | grep -vE "willPresentError|^\s*[0-9]+ \||^\s*\||warning:" | head -30 || true
        echo "$out" | grep -vE "^\[[0-9]+/[0-9]+\]|warning:|note:|^\s*[0-9]+ \||^\s*\|" | tail -40 || true
        return 1
    fi
}
build --target SwiftUI
if [ "$(uname)" != Darwin ]; then
    # Apple's AppKit re-exports these; the libraries import them by name.
    build --target ImageIO
fi
# Step 1 synthesised the module maps of the C targets without a hand-written one.
add_maps .build/debug/C*.build/module.modulemap .build/*/debug/C*.build/module.modulemap
echo "module maps: $seen"

if [ "$PROBE" = 1 ]; then
    echo "== probe: each library on its own"
    for target in MarkdownUI SwiftUIIntrospect ConfettiSwiftUI Shimmer WrappingHStack SwiftUICharts Defaults Nuke NukeUI; do
        log=$(mktemp)
        if swift build --target "$target" "${FLAGS[@]}" >"$log" 2>&1; then
            echo "$target: builds"
        else
            # Diagnostic lines start with a path; the source excerpts under them do not.
            errors=$(grep -cE "^[^ |].*error: " "$log" || true)
            first=$(grep -m1 -E "^[^ |].*:[0-9]+:[0-9]+: error: " "$log" || grep -m1 "error: " "$log" || true)
            first=$(echo "$first" | sed -E 's|^.*/checkouts/||')
            echo "$target: FAILS ($errors errors); first: $first"
        fi
        rm -f "$log"
    done
fi

echo "== step 2: the libraries and the example"
build
if [ "$RUN" = 1 ]; then
    .build/debug/LibraryCompat "${APPKITWIN_LIBRARY_COMPAT_ARGS[@]}"
fi
