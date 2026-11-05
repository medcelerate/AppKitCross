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
# Windows (Swift 6.4.1): the frontend's debug-type round-trip check asserts on some of
# SwiftUICharts' shape files; skipping the check gives the library's own verdict.
case "$(uname)" in MINGW*|MSYS*|CYGWIN*) FLAGS+=(-Xswiftc -Xfrontend -Xswiftc -disable-round-trip-debug-types) ;; esac
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
        # A synthesised map (.build/debug/<Name>.build) is skipped when the shim has a
        # hand-written one, which would otherwise be a redefinition of the module.
        name=${name%.build}
        case " $seen " in *" $name "*) continue ;; esac
        # The CoreGraphics submodule map stands in for Apple's framework; on macOS the SDK has it.
        if [ "$(uname)" = Darwin ] && [ "$name" = CCoreGraphicsModules ]; then continue; fi
        seen="$seen $name"
        FLAGS+=(-Xcc -fmodule-map-file="$(abs "$(dirname "$m")")/$(basename "$m")")
    done
}
add_maps ../../Sources/C*/module.modulemap ../../Sources/C*/include/module.modulemap
for d in ../../Sources/C*/include ../../Sources/C*; do
    # (clang also finds a module.modulemap in an include directory on its own.)
    if [ "$(uname)" = Darwin ] && [ "$(basename "$d")" = CCoreGraphicsModules ]; then continue; fi
    [ -d "$d" ] && FLAGS+=(-Xcc -I"$(abs "$d")")
done
# ... and the system headers those maps include (Cairo, Pango, X11, D-Bus on Linux).
if [ "$(uname)" = Linux ] && command -v pkg-config >/dev/null; then
    for flag in $(pkg-config --cflags-only-I pangocairo x11 dbus-1 2>/dev/null); do FLAGS+=(-Xcc "$flag"); done
fi

echo "== step 1: AppKitWin's SwiftUI (and AppKit) into the Modules directory"
# Runs a build, printing its last lines on success and the whole log on failure.
build() {
    local out
    if out=$(swift build "$@" "${FLAGS[@]}" 2>&1); then
        echo "$out" | grep -E "error:|Build complete|Compiling" | tail -3 || true
    else
        # The error lines first (the tail alone can be all warnings), then the tail.
        echo "$out" | grep -E "error:" | grep -vE "warning:|note:" | head -20
        echo "$out" | grep -vE "^\[[0-9]+/[0-9]+\]|warning:|note:|^\s+[0-9]+ \||^\s+\|" | tail -40
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
            # Diagnostic lines name a source file and position; the source excerpts under
            # them and the SwiftCompile summaries do not. The log is read as text with its
            # carriage returns stripped (Windows), so grep never treats it as binary.
            tr -d '\r' < "$log" > "$log.txt"
            errors=$(grep -acE "swift:[0-9]+:[0-9]+: +error" "$log.txt" || true)
            first=$(grep -am1 -E "swift:[0-9]+:[0-9]+: +error" "$log.txt" || grep -am1 "error: " "$log.txt" || true)
            first=$(echo "$first" | sed -E 's|^.*/checkouts/||')
            echo "$target: FAILS ($errors errors); first: $first"
        fi
        rm -f "$log" "$log.txt"
    done
fi

echo "== step 2: the libraries and the example"
build
if [ "$RUN" = 1 ]; then
    .build/debug/LibraryCompat "${APPKITWIN_LIBRARY_COMPAT_ARGS[@]}"
fi
