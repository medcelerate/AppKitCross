# ADR-0039: Core depth, round 3 — the remaining Core stubs

Date: 2026-11-16. Status: accepted.

## Context

After ADR-0038 (with PR #78 merged) `grep unimplemented( Sources/AppKit/Core` counted 483, but
173 of those were the two header comment lines every seeded file carries. The real count was
**310 call sites, 269 of them without a reason** (the brief's per-type estimate predated
ADR-0036/0038 work on NSFont descriptors and friends). This round classifies every one of
them with the ADR-0036 method: values that have a measurable answer were printed by the real
AppKit on this Mac (macOS 15, Objective-C probes that catch AppKit's exceptions) and the tests
assert them.

Two silent defects turned up that were not counted as stubs and are fixed here because
their members could not work without it: `NSButtonCell.drawImage` was an empty body, so no
push button ever drew its image; `NSColor.encode(with:)` was empty, so every archived colour
came back black. `NSControl.init?(coder:)` made no cell either (a decoded control had none).

## Decision

Each stub is **(a)** implemented with existing Core, **(b)** implemented over a new backend
hook, or **(c)** left as `unimplemented("…reason…")`. Core: **310 sites → 103, every one now
carrying its reason** (269 unreasoned → 0).

**(b) Hooks.**

- `PlatformDisplay.refreshRate` / `bitsPerSample` (defaults 60 Hz / 8): Win32 reads
  `EnumDisplaySettingsW` for the monitor's current mode (10 bits a sample with HDR on);
  Wayland the `wl_output` current mode's refresh; X11 keeps the defaults (no RandR yet).
- `PlatformWorkspace.removableVolumePaths()`, `ejectVolume(at:)`, `fileSystemInfo(forPath:)`,
  `showSearchResults(forQuery:)` (protocol requirements with defaults): Win32 uses
  `GetLogicalDrives`/`GetDriveTypeW`, lock-dismount-eject through `DeviceIoControl`,
  `GetVolumePathNameW`/`GetVolumeInformationW`, and `search-ms:` for Windows Search; Linux
  reads `/proc/mounts` (udisks mounts under /media and /run/media are removable), ejects with
  `gio mount --eject`, and answers false for search (no desktop-neutral entry point); the host
  backend has test hooks.
- `CARuntime.lastTickTime` (QuartzCore): the frame clock's last tick, for
  `NSScreen.lastDisplayUpdateTimestamp`.

**Notable behaviour (probed).** `NSBezierPath.close()` appends the close *and* an implicit
move to the subpath start (an M L Z path has four elements), consecutive moves merge, the
shape builders close without the move; `reversed` keeps subpath order and starts a closed
subpath from its first point; archives use AppKit's `NSSegments` (a type byte and big-endian
Float32 x, y per point) and attribute keys. `appendGlyph` needs a current point (AppKit
raises "No current point for line") and leaves a move one advance on. A bitmap
`NSGraphicsContext` draws in the rep's size in points (CTM scaled to pixels),
relative-colorimetric, y up, and the rep takes the pixels when the context stops being
current. `NSScroller.isCompatibleWithOverlayScrollers` is true for NSScroller only (even an
empty subclass answers false). NSButton compression applies hide-text only when an image
remains and hide-images only when a title remains, in priority order. `NSFont.vertical`,
`printer` and `screen` are the font itself (macOS answers so for Helvetica);
`NSFontIdentityMatrix` is a null sentinel on macOS, and the port's `identityMatrix` points at
the identity, which `init(name:matrix:)` reads the same way (a 1-point font).

**Deviations, stated.** Palette menu items get a swatch image (macOS draws swatches in a
private view and leaves `image` nil; the port's menus draw item images). `flattened` sizes its
subdivision from `flatness` (Wang's bound); macOS 15 uses eight lines a quarter circle whatever
the flatness. NSLayoutManager's manual-layout setters change the queries until the next layout
pass; drawing still follows the CoreText lines. `NSCollectionViewItem.copy` makes a new item of
the same class and nib (macOS archives the view; the port has no view archiving). View
`init?(coder:)` decodes nothing (the port loads no nibs) and gives what `init(frame: .zero)`
gives.

## Inventory

(a) existing Core; (b) new hook; (c) left, reason in the message.

### NSFont (18)

| Members | Class | Notes |
|---|---|---|
| advancement/boundingRect(forGlyph:), getAdvancements (glyphs, packed), getBoundingRects, glyph(withName:), numberOfGlyphs, coveredCharacterSet | a | port CoreText (`CTFontGetAdvancesForGlyphs`, …); zero for glyphs past the face; packed = big-endian 16-bit |
| init(name:matrix:), matrix, identityMatrix | a | size from the matrix; `[size 0 0 size 0 0]` |
| preferredFont(forTextStyle:options:) | a | macOS 15 sizes/weights (26/22/17/15, headline bold 13, caption2 medium 10) |
| printer, screen, screenFont(with:), vertical | a | the font itself |
| setUser, setUserFixedPitch | a | `NSFont`/`NSFontSize`, `NSFixedPitchFont`/`NSFixedPitchFontSize`; user fonts read them (12 / 11 pt defaults) |

### NSResponder (14)

| Members | Class | Notes |
|---|---|---|
| interpretKeyEvents | a | the standard key-binding table (shared with NSTextView): commands to the first text input client or up the chain, text to the first client, else beep |
| presentError(_:modalFor:delegate:didPresent:contextInfo:) | a | willPresentError, up the chain, sheet at the end; callback via the registry (NO) |
| makeTouchBar, touchBar | a | nil; stored, made lazily |
| allowedClasses, restorableStateKeyPaths, encodeRestorableState(…backgroundQueue:) | a | [], [], forwards |
| validRequestor, wantsForwardedScrollEvents, wantsScrollEventsForSwipeTracking, shouldBeTreatedAsInkEvent | a | next responder's / false |
| newWindowForTab | a | NSResponder does not implement it (macOS raises unrecognized selector) |
| showWritingTools | c | Writing Tools is an Apple Intelligence service |

### NSButton, NSButtonCell, NSUserInterfaceCompressionOptions (19 + new type)

| Members | Class | Notes |
|---|---|---|
| image drawing (drawImage, cellSize, drawInterior) | a | positions incl. leading/trailing, scaling, template tint (pixel tint, no blend modes on every backend), alternate image, dimming |
| activeCompressionOptions, compress, minimumSize(withPrioritizedCompressionOptions:) | a | over `NSUserInterfaceCompressionOptions`, moved to Core (config `handwritten`) |
| attributedAlternateTitle (button, cell) | a | font, control text colour, centred tail-truncating style |
| isSpringLoaded, maxAcceleratorLevel, borderShape, tintProminence, contentTintColor, imageHugsTitle, hasDestructiveAction, symbolConfiguration | a | stored (maxAcceleratorLevel 1…5, others refused with macOS's warning) |
| gradientType, keyEquivalentFont, setKeyEquivalentFont | a | stored; system 13 pt default |

### NSMenu, NSMenuItem (14)

| Members | Class | Notes |
|---|---|---|
| selectionMode, selectedItems, presentationStyle, palette(colors:…) | a | selection applied when an item is chosen; selectOne keeps the last |
| menuChangedMessagesEnabled, automaticallyInsertsWritingToolsItems | a | stored (false / true) |
| helpRequested(with:) | a | nothing: NSHelpManager registers no help |
| sectionHeader ×2, setTitleWithMnemonic, userKeyEquivalent | a | macOS 15 behaviour; `NSUserKeyEquivalents` default |
| writingToolsItems | a | none (no Writing Tools) |

### NSScreen (13)

| Members | Class | Notes |
|---|---|---|
| maximumFramesPerSecond, minimum/maximumRefreshInterval, displayUpdateGranularity, depth | b | `refreshRate`, `bitsPerSample` |
| lastDisplayUpdateTimestamp | b | `CARuntime.lastTickTime` |
| deviceDescription | a | macOS 15 keys incl. `NSScreenNumber` |
| auxiliaryTopLeft/RightArea, cgDirectDisplayID, screensHaveSeparateSpaces | a | nil / nil / false |
| supportedWindowDepths | c | a zero-terminated list cannot be made of the port's Swift enum |

### NSWorkspace (14)

| Members | Class | Notes |
|---|---|---|
| mountedRemovableMedia, unmountAndEjectDevice ×2, getFileSystemInfo, showSearchResults | b | volume/search hooks; eject errors are NSOSStatusErrorDomain −36 (macOS) |
| desktopImageOptions, fileLabels, fileLabelColors, extendPowerOff | a | options last set (else empty); macOS 15 labels/colours; 0 |
| setIcon, requestAuthorization ×2 | c | no custom file icons; FileManager(authorization:) is macOS-only |

### NSTextField, NSControl (22)

| Members | Class | Notes |
|---|---|---|
| edit/select/endEditing, selectCell, sizeThatFits, take*ValueFrom | a | through the cell |
| placeholderStrings, placeholderAttributedStrings | a | first that fits the width (cell draws attributed placeholders now) |
| allowsWritingTools(+Affordance), resolvesNaturalAlignmentWithBaseWritingDirection | a | stored (true / false / false, the last unverified: no macOS 26) |

### NSGraphicsContext (10), NSBezierPath (10)

| Members | Class | Notes |
|---|---|---|
| init(bitmapImageRep:), init(attributes:), init(graphicsPort:flipped:), graphicsPort, colorRenderingIntent | a | offscreen surface synced into the rep |
| init(window:) | c | windows draw only in their views' display pass |
| setGraphicsState | c | gstate numbers are no longer handed out |
| appendArc(from:to:radius:), appendGlyph(s), appendPackedGlyphs, drawPackedGlyphs, flattened, reversed, supportsSecureCoding, coding | a | probed element sequences and archive |

### NSLayoutManager (19)

| Members | Class | Notes |
|---|---|---|
| setLineFragmentRect, setExtraLineFragmentRect, setTextContainer, setLocation(s), setNotShownAttribute, setDrawsOutsideLineFragment, setIntAttribute, intAttribute | a | until the next layout pass |
| rulerAccessoryView | a | alignment strip (macOS also has spacing and list pop-ups) |
| insertGlyph(s), deleteGlyphs, replaceGlyph, setCharacterIndex | c | one glyph per character; no glyph storage |
| typesetter, glyphGenerator (get/set) | c | CoreText typesetting; NSTypesetter belongs to the TextKit 2 round |

### NSCoding (≈40 across 30 types)

| Members | Class | Notes |
|---|---|---|
| view `init?(coder:)` (NSBox, NSComboBox, NSGridView, NSOutlineView, NSRulerView, NSScrubber, NSSegmentedControl, NSTable{,CellView,HeaderView,RowView}, NSCollectionView, NSDrawer) | a | as `init(frame: .zero)` |
| NSColor, NSGradient, NSAnimation, NSViewAnimation, NSTableColumn, NSTrackingArea, NSGrid{Cell,Column,Row}, collection layouts, scrubber layouts and styles, NSRulerMarker, NSSound, NSController, NSObjectController, NSUserDefaultsController | a | AppKit's keys where probed (NSRGB/NSWhite strings, NSGrid_…, NSAnimation…, NSItemSize, …) |
| private helpers (drawer slide, rule editor rows, tree child array) | c | never archived |

### Tail

| Members | Class | Notes |
|---|---|---|
| NSText RTF/RTFD (read, replace, rtf(d)(from:), writeRTFD, movementUserInfoKey) | a | the port's RTF reader/writer |
| NSCollectionView frameForItem(at:withNumberOfItems:), newItem, legacy content path, drag images; NSCollectionViewItem components/copy; NSTableView, NSBrowser drag images | a | snapshots via `cacheDisplay` |
| NSAccessibility unignored helpers, ErrorCodeExceptionInfo, raiseBadArgumentException, setMayContainProtectedContent | a | the port's elements (controls, not cells) |
| NSAlert legacy beginSheetModal, NSController commitEditing callback, valueClassForBinding, isCompatibleWithOverlayScrollers, NSSliderCell.prefersTrackingUntilMouseUp, NSTabViewController toolbar items, NSSpellChecker.menu(for:), NSPasteboardItem reading, NSWindowController preview items, terminateAutomaticallyTerminableApplications | a | registry callbacks; probed answers |
| NSPasteboard/Item detected* (6) | c | NSDataDetector is not in corelibs |
| NSPrintInfo PM* (5), takeSettings(from:), NSPrintOperation eps* (3), pdfPanel | c | Core Printing is macOS-only; NSPDFInfo/NSPDFPanel are generated stubs; no PostScript writer |
| NSDocument browseVersions, restoreWindow (×2), standardShareMenuItem, NSObjectController.fetch/newObject, binding value transformers, NSGestureRecognizer.pressureConfiguration, NSTitlebarAccessoryViewController.preferredScrollEdgeEffectStyle, NSSpellChecker indicators/predictions, NSMatrix custom sort | c | macOS services, Core Data, missing corelibs types, generated stubs |

## Consequences

Core has no unexplained stub left; the 103 remaining are listed above with reasons. Image
buttons draw their images on every backend for the first time. The PC checklist covers the
visible members: glyph metrics, image buttons, the palette menu popped up from code, the path
hit test and the pasteboard round trip (HelloWindow `coredepth`, top strip).
