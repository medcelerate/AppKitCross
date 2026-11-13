# ADR-0036: Core depth — NSView, NSWindow, NSImage and the image reps

Date: 2026-11-12. Status: accepted.

## Context

The generated-stub burn-down (PRs 63–66) left the hand-written Core types with 1,085
`unimplemented()` members, and apps reach NSView, NSWindow and NSImage first. This round takes
those three and the image reps: NSView 102, NSWindow 142, NSImage 170, NSImageRep 20,
NSBitmapImageRep 28 (462 counted `unimplemented(` sites). Several members the brief listed as
priorities (`convert(_:to:)`, `frameRect(forContentRect:)`, `draw(in:from:operation:fraction:)`)
already existed but were shallow: NSView conversion ignored bounds scaling and rotation,
`convert(_:NSSize…)` returned its argument, NSImage drew its first representation whatever the
destination, ignored `capInsets`/`resizingMode` and the compositing operation, and
`tiffRepresentation` returned PNG bytes. Those are fixed here too.

Every behaviour with a measurable answer was probed on macOS first (scratch Swift scripts against
the real AppKit on the host) and the tests assert those numbers: conversion results across
flipped/scaled/turned views, bounds of turned views, `isMousePoint` edges, `previousKeyView`
after relinking, the window resize-time curve, the cascade step, frame descriptor format and
autosave key, `minFrameWidth`, `backingAlignedRect`, bitmap byte layouts after `setColor`.

## Decision

Each stub was classified **(a)** implementable with existing Core and seams, **(b)** needs a small
backend hook, **(c)** out of scope (Apple-only service, deprecated PostScript, or depends on a
type that is still a generated stub). (a) and (b) are implemented; (c) members keep
`unimplemented()` with the reason in the message. The appendix lists every member.

**NSView geometry.** A view maps bounds to its superview as AppKit does:
F = D·(R(θb)·p − o) into the frame's rectangle (D = frame size / bounds size, θb the bounds
rotation about the coordinate origin, o the bounds origin), flipped if the orientation differs from
the superview's, turned by `frameRotation` about the frame origin and moved to it. The same
mapping drives conversions, drawing (`_concatToSuperview`), hit testing (a turned view tests its
frame rectangle, not the bounding box) and `lockFocus`. Rect conversion is the bounding box of all
four corners; sizes convert as vectors and come back positive (macOS's answer across a flip).
A turned view's `bounds` is the bounding box of the frame in bounds coordinates; a scaled view
keeps its scale when the frame resizes; `scaleUnitSquare`, `rotate(byDegrees:)` and
`frameCenterRotation` follow. A layer-backed view's frame rotation becomes its layer's affine
transform (the anchor is the frame origin); bounds scaling and bounds rotation are not applied to
backing layers yet.

**NSView behaviour.** Tool tips are shown at last: `_NSToolTipManager` follows the window's mouse
moves and shows `toolTip` or an `addToolTip` rectangle (owner via `NSViewToolTipOwner`, else its
description) in a non-activating panel after `NSInitialToolTipDelay` (1 s), at once when moving
between tips, and hides on clicks, keys, scrolls and exits. `addTrackingRect` is an
`NSTrackingArea` whose events carry the tag as `trackingNumber` and the user data. The key view
chain is AppKit's (`nextKeyView` sets the other's `previousKeyView`, which survives relinking;
`next/previousValidKeyView` skip views that cannot become key); the window follows an explicit
chain before its default order, `recalculateKeyViewLoop` links top-to-bottom/left-to-right, and
`autorecalculatesKeyViewLoop` now defaults to false as on macOS. `lockFocus` inside a draw pass
of the view's window concatenates the view's transform onto the current context; outside one it
draws into an offscreen copy of the view that is shown over the view until it next draws (what
drawing into the backing store does on macOS) and that `NSBitmapImageRep(focusedViewRect:)`
reads. `enterFullScreenMode` moves the view into a borderless window over the screen and back.
`scroll(_:)`, `NSClipView.autoscroll` (scroll by the overshoot), `sortSubviews`, `getRectsBeingDrawn`
(one rect), `shadow` (on the backing layer), `willOpenMenu`/`didCloseMenu` (called around
contextual menus), `enclosingMenuItem` (set by `NSMenuItem.view`) and the stored flags are done;
`isHorizontal/VerticalContentSizeConstraintActive` reach the layout engine.

**NSWindow.** Frame autosave writes `frameDescriptor` ("x y w h sx sy sw sh ", window then screen
frame) to the user defaults under `NSWindow Frame <name>`; `setFrameAutosaveName` refuses a name
another live window holds, restores a saved frame, and the frame is saved whenever it changes;
`setFrame(from:)`/`setFrameUsingName` move the frame by the saved screen's offset, keep a
non-resizable window's size (top-left placed as saved) and constrain to the screen.
`cascadeTopLeft` steps (29, −29) and restarts at the visible frame's corner when the window would
leave it. `setFrame(_:display:animate:)` animates over `animationResizeTime` — macOS's curve,
k·ln(1 + d/100) for the farthest edge's travel d — and returns on arrival (nested loop, as macOS
blocks). `zoom` uses the delegate's `windowWillUseStandardFrame`: the default frame maximises on
the platform as before, a custom one frames the window there and back; `setIsZoomed`/
`setIsMiniaturized` toggle. The default button cell is the button with Return; disabling it
clears and restores that key equivalent. `toggleFullScreen` is a core emulation (`.fullScreen` in
the style mask, the screen's frame, status-bar level, the will/did notifications and delegate
calls); platform full-screen states are not entered, so a native title bar stays where the
platform draws one. `NSApplication.orderedWindows` is now front to back (the windows record the
order they were last ordered in), which `orderedIndex`, `windowNumber(at:belowWindowWithWindowNumber:)`
and `windowNumbers(options:)` use. Tabbing is not modelled: `addTabbedWindow` orders the window as
a separate window, the tab actions do nothing, `tabbedWindows`/`tabGroup` are nil.

**(b) Resize constraints.** `PlatformWindow.setResizeConstraints(_:)` hands `aspectRatio`,
`contentAspectRatio`, `resizeIncrements` and `contentResizeIncrements` to the platform for the
user's live resizes (programmatic frames are not constrained, as on macOS); the arithmetic is the
portable `PlatformResizeConstraints.constrain`. Host: stored, and `HostWindow._userResize` drives
it in tests. X11: `PAspect`/`PResizeInc` size hints (the client window is the content). Win32:
`WM_SIZING` adjusts the dragged edges (`Win32ResizeConstraints.swift`; one `case` in the window
proc). Wayland: the default no-op — xdg-shell has no aspect or increment hints.

**NSImage.** The 138 image-name constants carry macOS's raw values ("NS" + name, checked against
the SDK). 60 of them, and 40 SF Symbols names (`plus`, `xmark`, `chevron.left`, `gearshape`,
`trash`, `folder`, …), resolve to template artwork drawn with NSBezierPath
(`NSImage+SystemImages.swift`); other names give nil as an unknown name does on macOS.
`bestRepresentation` follows AppKit's rule (the smallest rep covering the needed pixels at the
context's scale, else the largest; `matchesOnMultipleResolution`, `matchesOnlyOnBestFittingAxis`),
and drawing uses it. A whole-image draw with `capInsets` (or `.tile`) draws nine slices — corners
as they are, edges and centre stretched or tiled, insets shrinking in proportion when the
destination is smaller; flipped contexts with `respectFlipped` keep the picture upright. The
compositing operation is honoured; `delegate.imageDidNotDraw` supplies a stand-in; `hitTest`
tests the alpha of the pixels under the rect; `tiffRepresentation` is a real TIFF; coding archives
the size, template flag and a TIFF; pasteboard, item-provider and literal initialisers work.

**NSImageRep.** A registry (`registeredClasses`, register/unregister with the notification) starts
with `NSBitmapImageRep` only — the PDF, EPS, PICT and Core Image reps are generated stubs that
cannot draw. Type lists come from the registered classes (the base class lists none, as macOS),
`class(for:)`/`class(forType:)`/`class(forFileType:)`/`class(forPasteboardType:)` search them,
`NSBitmapImageRep.canInit(with:)` checks file signatures, and a plain `NSImageRep` made from a file
or pasteboard draws the decoded rep it stands for. `draw(in:from:operation:fraction:respectFlipped:hints:)`
and `cgImage(forProposedRect:…)` render reps that have no bitmap.

**NSBitmapImageRep.** A rep keeps its drawable image (premultiplied BGRA on the port's
CoreGraphics) and, once samples are read or written, an 8-bit sample buffer in AppKit's layout:
meshed or planar, alpha first or last, premultiplied unless `.alphaNonpremultiplied`, rows padded
to 32 bytes when unspecified. Reps made from planes, or whose `bitmapData` was handed out, rebuild
the image from the bytes whenever it is asked for (AppKit reads planes each time it draws; this
costs a copy per draw for such reps). Decoded images unpack to straight-alpha RGBA, as macOS's
PNG reps do. `colorAt`/`setColor`/`getPixel`/`setPixel`/`colorize` work on gray and RGB reps.
TIFF and BMP are written by the port itself on every platform (`NSBitmapImageRep+Codecs.swift`:
baseline big-endian TIFF, none or PackBits, one page per rep; 32-bit V4 BMP), and a TIFF the
platform decoder cannot read (Linux) goes through the port's reader. PNG and JPEG go through the
platform codec; GIF and JPEG 2000 only on the host (ImageIO) — the Win32 encoder now refuses
formats it does not write instead of returning PNG bytes, and Linux has no JPEG encoder, so those
answer nil. `incrementalLoad` asks for all the data, then decodes.

**(c) Out of scope**, still `unimplemented()`: EPS output (no PostScript writer; PDF works),
`showDefinition` (dictionary service), `NSView.LayoutRegion` members (a generated macOS 26 type),
`inputContext` for text-input clients (`NSTextInputContext` is generated), deprecated promise
drags, Carbon `windowRef`, window sharing, `NSWindow.tab`, `visualizeConstraints`, custom symbol
assets, the default `symbolConfiguration`, and everything taking an `NSColorSpace`
(`colorSpace`, `converting`, `retagging`) since `NSColorSpace` is still generated. `NSScreen.colorSpace`
and `canRepresent` remain stubs, so `NSWindow.colorSpace` (unset) and `canRepresent(.p3)` reach them.

## Consequences

Core's `grep -c unimplemented(` total goes from 1,085 to 657. Members still stubbed: NSView 9,
NSWindow 8, NSImage 3, NSImageRep 0, NSBitmapImageRep 4 (plus one depth check inside the planes
initialiser).
`CoreDepthTests` (34) cover each group on the host backend; pixel checks skip elsewhere.
Behaviour changes for existing code: view conversions now apply bounds scale and rotation;
`autorecalculatesKeyViewLoop` defaults to false; `NSApplication.orderedWindows` is front to back;
`NSImage.tiffRepresentation` returns TIFF; the Win32 image encoder returns nil for GIF/JPEG 2000;
`NSImageRep.canInit(with:)` on the base class asks the registered classes instead of answering
true for any non-empty data.

Follow-ups: NSColorSpace and NSScreen colour members (unblocks the colour-space trio),
`NSTextInputContext`, native full-screen states per platform, bounds scale/rotation on backing
layers, window tabs.

The Layout Demo gains a `coredepth` tab (`Examples/HelloWindow/CoreDepthDemo.swift`): a nine-slice
image stretched and tiled, a turned label, PNG/TIFF/BMP export of the panel through a save panel,
and a window with a frame autosave name and a 4:3 content aspect ratio.

## Appendix: inventory

(a) implemented with existing Core and seams; (b) new backend hook; (c) out of scope, still
`unimplemented()` with the reason shown.

### NSView (85 stubs before, 9 left)

| Member | Class | Notes |
|---|---|---|
| `acceptsTouchEvents` | (a) |  |
| `addToolTip(_:owner:userData:)` | (a) | shown by the new tool tip manager |
| `addTrackingRect(_:owner:userData:assumeInside:)` | (a) | NSTrackingArea carrying tag and userData |
| `additionalSafeAreaInsets` | (a) |  |
| `adjustScroll(_:)` | (a) |  |
| `allocateGState()` | (a) | deprecated no-op (as macOS) |
| `allowedTouchTypes` | (a) |  |
| `autoscroll(with:)` | (a) |  |
| `canDrawConcurrently` | (a) |  |
| `candidateListTouchBarItem` | (a) |  |
| `convertFromLayer(_:)` | (a) | identity (layer bounds are the view bounds; macOS answers the same) |
| `convertFromLayer(_:)` | (a) | identity (layer bounds are the view bounds; macOS answers the same) |
| `convertFromLayer(_:)` | (a) | identity (layer bounds are the view bounds; macOS answers the same) |
| `convertToLayer(_:)` | (a) | identity, as macOS |
| `convertToLayer(_:)` | (a) | identity, as macOS |
| `convertToLayer(_:)` | (a) | identity, as macOS |
| `dataWithEPS(inside:)` | (c) | no PostScript writer; use dataWithPDF(inside:) |
| `defaultMenu` | (a) |  |
| `didCloseMenu(_:with:)` | (a) |  |
| `displayIfNeededIgnoringOpacity()` | (a) |  |
| `displayIfNeededIgnoringOpacity(_:)` | (a) |  |
| `dragFile(_:from:slideBack:event:)` | (a) |  |
| `dragPromisedFiles(ofTypes:from:source:slideBack:event:)` | (c) | deprecated; use NSFilePromiseProvider |
| `drawFocusRingMask()` | (a) |  |
| `drawSheetBorder(with:)` | (a) |  |
| `edgeInsets(for:)` | (c) | NSView.LayoutRegion is not modelled |
| `enclosingMenuItem` | (a) |  |
| `enterFullScreenMode(_:withOptions:)` | (a) | borderless window over the screen |
| `exitFullScreenMode(options:)` | (a) |  |
| `focusRingMaskBounds` | (a) |  |
| `focusView` | (a) |  |
| `gState()` | (a) | 0, as macOS |
| `getRectsBeingDrawn(_:count:)` | (a) |  |
| `getRectsExposedDuringLiveResize(_:count:)` | (a) |  |
| `inputContext` | (c) | NSTextInputContext is a generated stub |
| `isCompatibleWithResponsiveScrolling` | (a) |  |
| `isDrawingFindIndicator` | (a) |  |
| `isHorizontalContentSizeConstraintActive` | (a) |  |
| `isInFullScreenMode` | (a) |  |
| `isMousePoint(_:in:)` | (a) |  |
| `isVerticalContentSizeConstraintActive` | (a) |  |
| `layerUsesCoreImageFilters` | (a) |  |
| `layoutGuide(for:)` | (c) | NSView.LayoutRegion is not modelled |
| `lockFocus()` | (a) | inline in a draw pass, else an offscreen copy shown over the view until it next draws |
| `lockFocusIfCanDraw()` | (a) | inline in a draw pass, else an offscreen copy shown over the view until it next draws |
| `lockFocusIfCanDraw(in:)` | (a) | inline in a draw pass, else an offscreen copy shown over the view until it next draws |
| `nextKeyView` | (a) | with previousKeyView back link |
| `nextValidKeyView` | (a) |  |
| `noteFocusRingMaskChanged()` | (a) |  |
| `prefersCompactControlSizeMetrics` | (a) |  |
| `prepareContent(in:)` | (a) |  |
| `preservesContentDuringLiveResize` | (a) |  |
| `pressureConfiguration` | (a) |  |
| `previousKeyView` | (a) |  |
| `previousValidKeyView` | (a) |  |
| `rect(for:)` | (c) | NSView.LayoutRegion is not modelled |
| `rectForSmartMagnification(at:in:)` | (a) |  |
| `rectPreservedDuringLiveResize` | (a) |  |
| `reflectScrolledClipView(_:)` | (a) |  |
| `releaseGState()` | (a) |  |
| `removeAllToolTips()` | (a) |  |
| `removeToolTip(_:)` | (a) |  |
| `removeTrackingRect(_:)` | (a) |  |
| `renewGState()` | (a) |  |
| `rotate(byDegrees:)` | (a) | adds to boundsRotation (conversions, drawing, hit testing honour it) |
| `safeAreaRect` | (a) |  |
| `scaleUnitSquare(to:)` | (a) | bounds scale applied to conversions and drawing |
| `scroll(_:)` | (a) |  |
| `scroll(_:by:)` | (a) |  |
| `scroll(_:to:)` | (a) |  |
| `setKeyboardFocusRingNeedsDisplay(_:)` | (a) |  |
| `setUpGState()` | (a) |  |
| `shadow` | (a) |  |
| `shouldDrawColor()` | (a) |  |
| `showDefinition(for:at:)` | (c) | no dictionary service on this platform |
| `showDefinition(for:range:options:baselineOriginProvider:)` | (c) | no dictionary service on this platform |
| `sortSubviews(_:)` | (a) |  |
| `translateRectsNeedingDisplay(in:by:)` | (a) |  |
| `unlockFocus()` | (a) |  |
| `wantsBestResolutionOpenGLSurface` | (a) |  |
| `wantsExtendedDynamicRangeOpenGLSurface` | (a) |  |
| `wantsRestingTouches` | (a) |  |
| `willOpenMenu(_:with:)` | (a) |  |
| `writeEPS(inside:to:)` | (c) | no PostScript writer; use writePDF(inside:to:) |
| `writingToolsCoordinator` | (a) |  |

### NSWindow (117 stubs before, 8 left)

| Member | Class | Notes |
|---|---|---|
| `init(windowRef:)` | (c) | Carbon WindowRef is macOS-only |
| `addTabbedWindow(_:ordered:)` | (a) | tabs not modelled: ordered as a separate window |
| `allowsAutomaticWindowTabbing` | (a) |  |
| `allowsConcurrentViewDrawing` | (a) |  |
| `anchorAttribute(for:)` | (a) |  |
| `animationResizeTime(_:)` | (a) | macOS's k·ln(1+d/100) curve |
| `appearanceSource` | (a) |  |
| `autorecalculatesContentBorderThickness(for:)` | (a) |  |
| `backingAlignedRect(_:options:)` | (a) |  |
| `backingLocation` | (a) |  |
| `backingType` | (a) |  |
| `beginDraggingSession(items:event:source:)` | (a) |  |
| `cacheImage(in:)` | (a) |  |
| `canBecomeVisibleWithoutLogin` | (a) |  |
| `canRepresent(_:)` | (a) |  |
| `canStoreColor()` | (a) |  |
| `cascadeTopLeft(from:)` | (a) | (29,-29) step, wraps to visible frame |
| `cascadingReferenceFrame` | (a) |  |
| `colorSpace` | (a) |  |
| `contentAspectRatio` | (b) | new PlatformWindow.setResizeConstraints: host, X11 hints, Win32 WM_SIZING; Wayland no-op |
| `contentBorderThickness(for:)` | (a) |  |
| `contentLayoutGuide` | (a) |  |
| `contentResizeIncrements` | (b) | same hook as contentAspectRatio |
| `convertPointFromBacking(_:)` | (a) |  |
| `convertPointToBacking(_:)` | (a) |  |
| `dataWithEPS(inside:)` | (c) | no PostScript writer; use dataWithPDF(inside:) |
| `dataWithPDF(inside:)` | (a) |  |
| `deepestScreen` | (a) |  |
| `defaultButtonCell` | (a) |  |
| `depthLimit` | (a) |  |
| `deviceDescription` | (a) |  |
| `disableFlushing()` | (a) |  |
| `disableKeyEquivalentForDefaultButtonCell()` | (a) |  |
| `disableSnapshotRestoration()` | (a) |  |
| `discardCachedImage()` | (a) |  |
| `discardEvents(matching:before:)` | (a) |  |
| `drag(_:at:offset:event:pasteboard:source:slideBack:)` | (a) |  |
| `drawers` | (a) |  |
| `enableFlushing()` | (a) |  |
| `enableKeyEquivalentForDefaultButtonCell()` | (a) |  |
| `enableSnapshotRestoration()` | (a) |  |
| `flush()` | (a) |  |
| `flushIfNeeded()` | (a) |  |
| `frameDescriptor` | (a) |  |
| `gState()` | (a) |  |
| `graphicsContext` | (a) |  |
| `hasActiveWindowSharingSession` | (a) |  |
| `hasCloseBox` | (a) |  |
| `hasDynamicDepthLimit` | (a) |  |
| `hasTitleBar` | (a) |  |
| `isFloatingPanel` | (a) |  |
| `isFlushWindowDisabled` | (a) |  |
| `isMiniaturizable` | (a) |  |
| `isModalPanel` | (a) |  |
| `isOnActiveSpace` | (a) | true while visible (no spaces) |
| `isOneShot` | (a) |  |
| `isResizable` | (a) |  |
| `isZoomable` | (a) |  |
| `keyViewSelectionDirection` | (a) |  |
| `maxFullScreenContentSize` | (a) |  |
| `menuChanged(_:)` | (a) |  |
| `mergeAllWindows(_:)` | (a) |  |
| `minFrameWidth(withTitle:styleMask:)` | (a) |  |
| `minFullScreenContentSize` | (a) |  |
| `miniwindowImage` | (a) |  |
| `miniwindowTitle` | (a) |  |
| `mouseLocationOutsideOfEventStream` | (a) |  |
| `moveTabToNewWindow(_:)` | (a) |  |
| `nextEvent(matching:until:inMode:dequeue:)` | (a) |  |
| `occlusionState` | (a) | visible while ordered in and not minimised |
| `oldColorSpaceUserInfoKey` | (a) |  |
| `oldScaleFactorUserInfoKey` | (a) |  |
| `orderedIndex` | (a) |  |
| `performDrag(with:)` | (a) | moves the window via trackEvents |
| `preferredBackingLocation` | (a) |  |
| `preventsApplicationTerminationWhenModal` | (a) |  |
| `recalculateKeyViewLoop()` | (a) |  |
| `registerForDraggedTypes(_:)` | (a) |  |
| `removeFrame(usingName:)` | (a) |  |
| `requestSharingOfWindow(_:)` | (c) | window sharing is a macOS service |
| `requestSharingOfWindow(usingPreview:title:)` | (c) | window sharing is a macOS service |
| `resizeFlags` | (a) |  |
| `restorationClass` | (a) |  |
| `restoreCachedImage()` | (a) |  |
| `saveFrame(usingName:)` | (a) | user defaults "NSWindow Frame <name>" |
| `selectNextTab(_:)` | (a) |  |
| `selectPreviousTab(_:)` | (a) |  |
| `setAnchorAttribute(_:for:)` | (a) |  |
| `setAutorecalculatesContentBorderThickness(_:for:)` | (a) |  |
| `setContentBorderThickness(_:for:)` | (a) |  |
| `setDynamicDepthLimit(_:)` | (a) |  |
| `setFrame(from:)` | (a) |  |
| `setFrameUsingName(_:)` | (a) | descriptor parse, screen offset, constrain |
| `setFrameUsingName(_:force:)` | (a) | descriptor parse, screen offset, constrain |
| `setIsMiniaturized(_:)` | (a) |  |
| `setIsZoomed(_:)` | (a) |  |
| `sharingType` | (a) |  |
| `showsResizeIndicator` | (a) |  |
| `tab` | (c) | window tabs are not modelled |
| `tabGroup` | (a) |  |
| `tabbedWindows` | (a) |  |
| `tabbingIdentifier` | (a) |  |
| `titlebarSeparatorStyle` | (a) |  |
| `toggleFullScreen(_:)` | (a) | core emulation: .fullScreen style + screen frame (no native full-screen state) |
| `toggleTabBar(_:)` | (a) |  |
| `toggleTabOverview(_:)` | (a) |  |
| `trackEvents(matching:timeout:mode:handler:)` | (a) | loop over NSApp.nextEvent |
| `transferWindowSharing(to:)` | (c) | window sharing is a macOS service |
| `unregisterDraggedTypes()` | (a) |  |
| `updateConstraintsIfNeeded()` | (a) |  |
| `useOptimizedDrawing(_:)` | (a) |  |
| `validRequestor(forSendType:returnType:)` | (a) |  |
| `visualizeConstraints(_:)` | (c) | constraint debugging overlay not available |
| `windowNumber(at:belowWindowWithWindowNumber:)` | (a) |  |
| `windowNumbers(options:)` | (a) |  |
| `windowRef` | (c) | Carbon WindowRef is macOS-only |
| `worksWhenModal` | (a) |  |

### NSImage (166 stubs before, 3 left)

| Member | Class | Notes |
|---|---|---|
| 138 image name constants (`actionTemplateName` … `userName`, `touchBar…TemplateName`) | (a) | raw values from macOS ("NS" + name); 60 resolve to drawn artwork |
| `init(coder:)` | (a) |  |
| `init(imageLiteralResourceName:)` | (a) |  |
| `init(pasteboard:)` | (a) |  |
| `init(pasteboardPropertyList:ofType:)` | (a) |  |
| `init(symbolName:bundle:variableValue:)` | (c) | custom symbol assets are not rendered |
| `init(symbolName:variableValue:)` | (c) | custom symbol assets are not rendered |
| `init(systemSymbolName:accessibilityDescription:)` | (a) |  |
| `init(systemSymbolName:variableValue:accessibilityDescription:)` | (a) |  |
| `canInit(with:)` | (a) |  |
| `delegate` | (a) |  |
| `imageFileTypes()` | (a) |  |
| `imagePasteboardTypes()` | (a) |  |
| `imageTypes` | (a) |  |
| `imageUnfilteredFileTypes()` | (a) |  |
| `imageUnfilteredPasteboardTypes()` | (a) |  |
| `imageUnfilteredTypes` | (a) |  |
| `layerContents(forContentsScale:)` | (a) |  |
| `locale` | (a) |  |
| `matchesOnlyOnBestFittingAxis` | (a) |  |
| `recommendedLayerContentsScale(_:)` | (a) |  |
| `symbolConfiguration` | (c) | NSImage.SymbolConfiguration is not modelled |
| `withLocale(_:)` | (a) |  |
| `withSymbolConfiguration(_:)` | (a) |  |
| `supportsSecureCoding` | (a) |  |
| `readableTypeIdentifiersForItemProvider` | (a) |  |
| `object(withItemProviderData:typeIdentifier:)` | (a) |  |
| `writableTypeIdentifiersForItemProvider` | (a) |  |
| `loadData(withTypeIdentifier:forItemProviderCompletionHandler:)` | (a) |  |

### NSImageRep (18 stubs before, 0 left)

| Member | Class | Notes |
|---|---|---|
| `init(pasteboard:)` | (a) |  |
| `canInit(with:)` | (a) |  |
| `cgImage(forProposedRect:context:hints:)` | (a) |  |
| ```(for:)` | (a) |  |
| ```(forFileType:)` | (a) |  |
| ```(forPasteboardType:)` | (a) |  |
| ```(forType:)` | (a) |  |
| `draw(in:from:operation:fraction:respectFlipped:hints:)` | (a) |  |
| `imageFileTypes()` | (a) |  |
| `imagePasteboardTypes()` | (a) |  |
| `imageReps(with:)` | (a) |  |
| `imageTypes` | (a) |  |
| `imageUnfilteredFileTypes()` | (a) |  |
| `imageUnfilteredPasteboardTypes()` | (a) |  |
| `imageUnfilteredTypes` | (a) |  |
| `registerClass(_:)` | (a) | registry starts with NSBitmapImageRep only (generated reps cannot draw) |
| `registeredClasses` | (a) |  |
| `unregisterClass(_:)` | (a) |  |

### NSBitmapImageRep (26 stubs before, 4 left)

| Member | Class | Notes |
|---|---|---|
| `init(bitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bitmapFormat:bytesPerRow:bitsPerPixel:)` | (a) | 8-bit gray/RGB, meshed or planar; 16-bit and float samples stop with `unimplemented()` (c) |
| `init(bitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:)` | (a) |  |
| `init(focusedViewRect:)` | (a) |  |
| `init(forIncrementalLoad:)` | (a) |  |
| `bitmapData` | (a) | 8-bit sample buffer; redrawn whenever the image is asked for |
| `canBeCompressed(using:)` | (a) |  |
| `colorSpace` | (c) | NSColorSpace is not modelled |
| `colorize(byMappingGray:to:blackMapping:whiteMapping:)` | (a) |  |
| `converting(to:renderingIntent:)` | (c) | NSColorSpace is not modelled |
| `getBitmapDataPlanes(_:)` | (a) |  |
| `getCompression(_:factor:)` | (a) |  |
| `getPixel(_:atX:y:)` | (a) |  |
| `getTIFFCompressionTypes(_:count:)` | (a) |  |
| `incrementalLoad(from:complete:)` | (a) |  |
| `localizedName(forTIFFCompressionType:)` | (a) |  |
| `retagging(with:)` | (c) | NSColorSpace is not modelled |
| `setColor(_:atX:y:)` | (a) |  |
| `setCompression(_:factor:)` | (a) |  |
| `setPixel(_:atX:y:)` | (a) |  |
| `setProperty(_:withValue:)` | (a) |  |
| `tiffRepresentation` | (a) | port-own baseline TIFF writer (none/PackBits) |
| `tiffRepresentation(using:factor:)` | (a) | port-own baseline TIFF writer (none/PackBits) |
| `tiffRepresentationOfImageReps(in:)` | (a) | port-own baseline TIFF writer (none/PackBits) |
| `tiffRepresentationOfImageReps(in:using:factor:)` | (a) | port-own baseline TIFF writer (none/PackBits) |
| `value(forProperty:)` | (a) |  |
| `supportsSecureCoding` | (a) |  |
