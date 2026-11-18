# ADR-0033: Globals and AppKit's Foundation extensions

Date: 2026-11-12. Status: accepted, awaiting verification on the Windows PC.

## Context

Three generated files held the largest stub counts outside classes: `_Globals.swift` (251
`unimplemented()` members: free functions and global variables), `Foundation+AppKit.swift`
(133: AppKit's extensions on Foundation types) and `NSWorkspace+Types.swift` (98: the nested
types of the hand-written `NSWorkspace`).

Most of the 251 globals were not code at all. They are C macros and enum constants imported as
`var`s (`NSUpArrowFunctionKey`, `NSOKButton`, `NSFontPanelAllModesMask`, the
`NSOpenGLPFA…` attributes, error-code ranges, `NSAccessibilitySearch…Key` strings). The
generator already emitted a global constant with its value when the probe (`probe.sh`, which
compiles a program against the real SDK and prints raw values) had recorded one, but the probe
only recorded enum cases and typed static constants, so every plain global fell through to
`unimplemented()`. The same gap stubbed AppKit's static additions to Foundation types whose
type is a Swift struct or an `NS_OPTIONS` (`CocoaError.Code.serviceMiscellaneous`,
`NSString.DrawingOptions.usesLineFragmentOrigin`).

The 98 in `NSWorkspace+Types.swift` were not generator drift: they are the twenty typed
notification messages macOS 26 added (`NSWorkspace.DidLaunchApplicationMessage` and so on),
nested in a hand-written class, so the generator emits them beside it. The other nested types
in that file (`LaunchOptions`, `FileOperationName`, `DesktopImageOptionKey`, …) were already
complete.

The functions the brief named as examples are not AppKit globals in Swift: `NSBeep()` is
`NSSound.beep()` (already hand-written), `NSRectFill` and `NSFrameRect` are `CGRect.fill(using:)`
and `CGRect.frame(withWidth:using:)`, `NSEventMaskFromType` is `NSEvent.EventTypeMask(type:)`,
and `NSInsetRect`/`NSStringFromRect` belong to Foundation. The `CGRect` methods were not emitted
at all (their owner is listed in the symbol graph under CoreFoundation), so they are added here
by hand.

## Decision

### Constants come from the probe

`collect_probe_entries` now also records global `var`s typed `Int`, `Int32`, `UInt32`, `UInt`,
`Double` or `String`, and every type property on a Foundation type AppKit extends (the probe
program gains `rv` overloads for those types; anything else still records `"?"`). Running
`probe.sh` on macOS 15.8 against the macOS 26.2 SDK added 306 values to
`api-inventory/AppKit.values.json`; existing keys were kept as they were (six static
`Double` class properties such as `NSEvent.doubleClickInterval` now probe to a value but are
user settings, not constants, so they stay unrecorded). The generated files then carry the SDK's
values, so nothing is hand-copied. Constants introduced in macOS 26 cannot be probed on the
15.8 host and stay stubs (below).

### Code goes in Core, listed in config

Two new keys in `tools/apigen/config.json`: `handwrittenGlobals` (free functions and variables)
and `handwrittenMembers` (members of AppKit's extensions on Foundation types). The generator
skips both like `skipMembers` and reports them in a new "Globals and Foundation extensions"
table in `docs/API-COVERAGE.md`. The implementations live in
`Core/AppKitGlobals.swift`, `Core/Foundation+AppKitExtensions.swift`,
`Core/NSWorkspace+Messages.swift` (the twenty message structs, listed under `skipMembers` as
nested types) and `Core/NSDirectionalEdgeInsets.swift` (now a hand-written type, so
`NSDirectionalEdgeInsetsZero` has a value; its fields are stored and settable as Apple's C
struct is).

### No new backend hooks

Every implemented member works through what Core already has: the current
`NSGraphicsContext`'s `CGContext`, the layout manager, the RTF/RTFD reader, the pasteboard and
`NSFontManager`. `NSReadPixel` reads back through `CGContext.makeImage()`, which every backend
answers for bitmap contexts; on a Win32 window target (no readable backing) it returns nil.
`NSBeep` needs no hook because Swift spells it `NSSound.beep()`, which already reaches each
platform. `NSShowAnimationEffect` is not in the Swift SDK (deprecated, not imported).

## Inventory

Numbers are `unimplemented()` members before → after.

| File | Before | After |
| --- | ---: | ---: |
| `_Globals.swift` | 251 | 8 |
| `Foundation+AppKit.swift` | 133 | 19 |
| `NSWorkspace+Types.swift` | 98 | 0 |

### (a) Implemented

| Group | Members | How |
| --- | --- | --- |
| Constants (probe) | 219 globals: function keys and characters, panel/alert/run return codes, text movements, font traits/classes/panel masks, glyph attributes, `NSOpenGLPFA…`, pasteboard/window-sharing/workspace error codes, accessibility search keys, type identifiers, `NS_USER_ACTIVITY_SUPPORTED`, … ; 64 Foundation statics: `CocoaError` / `CocoaError.Code` service, sharing, font and text error codes, `NSString.DrawingOptions` | Generated with the SDK's values |
| Rect drawing | `CGRect.fill(using:)`, `frame(withWidth:using:)`, `clip()`, `NSEraseRect`, `NSDottedFrameRect`, `NSDrawWindowBackground`, `NSDrawTiledRects`, `NSDrawColorTiledRects` | Current context, compositing operation honoured |
| Bevels | `NSDrawButton`, `NSDrawGrayBezel`, `NSDrawWhiteBezel`, `NSDrawDarkBezel`, `NSDrawLightBezel`, `NSDrawGroove` | Classic grey strips through the tiled-rect routine, top/bottom swapped in flipped contexts |
| Images | `NSDrawBitmap` (8-bit, grey/RGB, meshed or planar), `NSDrawThreePartImage`, `NSDrawNinePartImage`, `NSReadPixel` | `CGImage` from converted pixels; caps and corners at natural size; read back via `makeImage()` |
| Misc globals | `NSDirectionalEdgeInsetsZero`, `NSConvertGlyphsToPackedGlyphs`, `NSDisableScreenUpdates`/`NSEnableScreenUpdates` (count only: every backend presents a window's frame whole), `NSReleaseAlertPanel`, `NSMultipleValuesMarker`, `NSNoSelectionMarker`, `NSNotApplicableMarker`, `NSIsControllerMarker` | |
| String drawing | `NSAttributedString.boundingRect(with:options:context:)`, `draw(with:options:context:)`, `NSString.boundingRect(with:options:attributes:context:)`, `draw(with:options:attributes:context:)`, `NSString.DrawingOptions.optionsResolvesNaturalAlignmentWithBaseWritingDirection` (1 << 9, from the header) | An `NSLayoutManager` with zero line fragment padding; one line without `.usesLineFragmentOrigin`. `NSStringDrawingContext` is not updated (its scale factors are not modelled) |
| Documents | `NSAttributedString.init?(RTF:)`, `init?(URL:)`, `init(URL:options:)`, `init?(path:)`, `fileWrapper(from:documentAttributes:)`, `textTypes`, `textUnfilteredTypes`; `NSMutableAttributedString.read(from:…)` (four overloads) | The RTF/RTFD/plain reader of ADR-0017/0030; HTML and Word throw `textReadInapplicableDocumentType` |
| Attributes and editing | `fontAttributes(in:)`, `rulerAttributes(in:)`, `lineBreak(before:within:)` (whitespace and hyphens), `url(at:effectiveRange:)`, `init(adaptiveImageGlyph:attributes:)`, `applyFontTraits`, `fixParagraphStyleAttribute`, `setAlignment`, `setBaseWritingDirection`, `superscriptRange`, `subscriptRange`, `unscriptRange`, `updateAttachments(fromPath:)` | |
| Foundation helpers | `CocoaError.isFontError`/`isServiceError`/`isSharingServiceError`/`isTextReadWriteError`; `Bundle.urlForImageResource`, `pathForImageResource`, `image(forResource:)`, `path(forSoundResource:)`; `NSAffineTransform.concat()`, `set()`, `transform(_:)`; `NSIndexPath(forItem:inSection:)`, `item`, `section`; `NSSet(collectionViewIndexPath(s):)`, `enumerateIndexPaths`; `NSURL(fromPasteboard:)`, `write(to:)`; `NSString(pasteboardPropertyList:ofType:)`; `FileWrapper.icon` (a weak side table) | |
| Workspace messages | The 20 `NSWorkspace.*Message` structs: stored properties, `name`, `makeMessage(_:)` from the userInfo keys NSWorkspace posts, `makeNotification(_:)` | Without the `NotificationCenter.MainActorMessage` conformance, which corelibs Foundation lacks |

### (b) Hooked

None needed (see above).

### (c) Out of scope: still `unimplemented()`

| Member | Why |
| --- | --- |
| `NSPerformService`, `NSRegisterServicesProvider`, `NSUnregisterServicesProvider`, `NSSetShowsServicesMenuItem`, `NSShowsServicesMenuItem`, `NSUpdateDynamicServices` | The Services menu is a macOS system facility (pbs and other applications' `NSServices`); Windows and Linux have nothing to register with or invoke |
| `NSCopyBits` | Takes a PostScript graphics-state number; there are no gstates |
| `NSGetWindowServerMemory` | There is no window server to ask |
| `Bundle.loadNibNamed(_:owner:topLevelObjects:)` | Nib loading is not supported (CLAUDE.md, `NSApplicationMain`) |
| `Bundle.contextHelp(forKey:)` | Help books and `NSHelpManager` are not ported |
| `FileManager(authorization:)` | Privileged file operations (`NSWorkspace.Authorization`) need the macOS authorization services |
| `NSAttributedString.init?(HTML:…)` (3), `docFormat(from:)`, `init?(docFormat:)` | No HTML (WebKit) or Word importer/exporter in the port |
| `lineBreakByHyphenating(before:within:)` | No hyphenation dictionaries |
| `fixFontAttribute(in:)`, `fixAttributes(in:)` | Font substitution needs per-font character coverage (`NSFont.coveredCharacterSet` is itself a stub); `fixAttributes` includes it |
| `URLResourceValues.customIcon`, `effectiveIcon`, `labelColor`, `thumbnail` | Corelibs `URLResourceValues` has no storage for AppKit's resource keys and `URL.resourceValues(forKeys:)` never fetches them |
| `NSAttributedString.Key.accessibilityFontBoldAttribute`, `accessibilityFontItalicAttribute`, `NSNotification.Name.NSApplicationShould{Begin,End}SuppressingHighDynamicRangeContent` | macOS 26 string constants: their values exist only in the macOS 26 AppKit binary, which the 15.8 probe host cannot load; re-run `probe.sh` on macOS 26 to fill them |

## Consequences

- Re-running `probe.sh` regenerates every value; a newer host fills the macOS 26 constants.
- Members of AppKit's extensions on Foundation types are ambiguous from the macOS test target
  (XCTest brings in Apple's AppKit declarations); the tests use typed locals, raw values and the
  internal helpers (`_NSStringDrawingLayout`, `_NSAttributedStringDocuments`).
- `GlobalsFoundationTests` (14): SDK values, notification names, error ranges, geometry and
  index paths, tiled rects, fill/erase/frame/`NSReadPixel`/`NSAffineTransform` pixels in a bitmap
  context, `NSDrawBitmap` and `NSDrawButton`, a host window filled through `CGRect.fill()`
  (skipped off the host backend), measurement against a hand-built layout manager, drawing with
  options in flipped and unflipped contexts, reading by URL, paragraph and script edits,
  pasteboard hooks and the workspace messages (skipped on macOS hosts older than 26).
