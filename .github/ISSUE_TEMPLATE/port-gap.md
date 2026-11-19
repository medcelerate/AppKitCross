---
name: Port gap
about: An Apple API that does not compile, traps or behaves differently on AppKitCross
title: "Gap: <Type.member> on <platform>"
labels: port-gap
---

**API**: the exact Apple symbol and module (for example `NSImage.init(systemSymbolName:accessibilityDescription:)`, AppKit)

**Platform**: Windows / Linux X11 / Linux Wayland / macOS host build

**Toolchain and commit**: `swift --version`; the AppKitCross revision from `Package.resolved`

**Kind**: compile error / trap / wrong behaviour

**Message**: the full compiler error, or the whole `AppKitCross: ...` trap line with its file and line

**Expected**: what Apple's documentation (or the app on macOS) does

**Minimal repro**: the smallest code that shows it, ideally a host-backend XCTest (AGENTS.md, section 4)

**App context**: the app that hit it (link if open source) and the workaround used, if any
