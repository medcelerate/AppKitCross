# ADR-0044: Apple-only API — counted apart from the stubs still to do

Date: 2026-11-17. Status: accepted.

## Context

Every member the port has not written yet calls `unimplemented()`, and the stub count is how
the project measures what is left. Part of that count can never shrink: classes that drive Apple
hardware (the Touch Bar), Apple services (Writing Tools, Sharing extensions, Help Viewer, iCloud)
or engines that exist only on macOS (CGL OpenGL, the macOS speech engine, ColorSync, Core
Printing, Carbon). Leaving them under `unimplemented()` overstates the work left and gives a
caller a misleading "not implemented yet" message.

The declarations themselves must stay: the inventory in `api-inventory/` is the source of truth
and code that names an Apple-only class (an app with an `#if` around its Touch Bar, a library that
adopts `NSTouchBarDelegate`) has to compile. `@available(*, unavailable)` would change the API
surface and break that code, so it is not an option.

## Decision

1. **A third stub function.** `appleOnlyUnavailable()` in `Sources/AppKit/Support/Unimplemented.swift`,
   beside `unimplemented()` and `unimplementedOptionalRequirement()`, with the same signature.
   It stops with "`X` exists only on macOS (Apple hardware, service or engine); it is not
   available on this platform".

2. **A generator classification.** `tools/apigen/config.json` gains `appleOnly` (dotted symbol
   paths: whole types, nested types of generated types, or single members of generated types)
   and `appleOnlyReasons` (exactly one one-line reason per entry). For an entry, or anything
   nested in it, `apigen.py` emits the declaration unchanged and swaps every `unimplemented()`
   and `unimplementedOptionalRequirement()` body for `appleOnlyUnavailable()`. Optional
   requirements with harmless defaults (`nil`, `false`, `{ }`) keep them. The generator refuses
   to run when an entry is not in the symbol-graph inventory, has no reason, has a stray
   reason, is a duplicate, or is owned elsewhere (`skipTypes`, `pending`, `skipMembers`, a
   `handwritten` type or a nested type Core declares). Hand-written Core types mark their own
   Apple-only members by calling `appleOnlyUnavailable("…reason…")` directly.

3. **Coverage.** `docs/API-COVERAGE.md` gets a "Stub call sites" table (Generated and Core,
   still to do vs Apple-only, counted on non-comment lines, the same rule as ADR-0039), a
   `Types apple-only` status and an "Apple-only" column in the type table, and an
   "Apple-only (ADR-0044)" section listing each entry with its site count and reason.

4. **Tests.** `AppleOnlyGeneratorTests`: every entry has one reason, is not handwritten,
   skipped or pending, and has its generated file (the generator emits one per inventory type,
   so that stands in for the git-ignored inventory) with the Apple-only declaration in it;
   Apple-only type files contain no `unimplemented()`; no other generated file calls
   `appleOnlyUnavailable`; and the coverage table matches a recount of the tree.

### What counts as Apple-only

The feature depends on Apple hardware, an Apple service, or a macOS engine whose identifiers,
formats or data have no counterpart on Windows or Linux, and the port has no plan to build it.
Anything a Windows or Linux app could plausibly need stays `unimplemented()`.

| Family | Entries | Why |
| --- | --- | --- |
| Touch Bar | `NSTouchBar`, `NSTouchBarItem`, `NSTouchBarDelegate`, `NSTouchBarProvider`, `NSButtonTouchBarItem`, `NSCandidateListTouchBarItem` (+ delegate), `NSColorPickerTouchBarItem`, `NSCustomTouchBarItem`, `NSGroupTouchBarItem`, `NSPickerTouchBarItem`, `NSPopoverTouchBarItem`, `NSSharingServicePickerTouchBarItem` (+ delegate), `NSSliderTouchBarItem`, `NSStepperTouchBarItem` | Touch Bar hardware exists only on some MacBook Pros. Nested types (`NSTouchBar.CustomizationIdentifier`, `NSTouchBarItem.Identifier`, priorities) come with their parents. |
| Writing Tools | `NSWritingToolsCoordinator` and its nested types | Apple Intelligence service. `NSWritingToolsBehavior`/`ResultOptions` and writing-tools members on other types stay as they are. |
| Speech | `NSSpeechSynthesizer`, `NSSpeechRecognizer` and their delegates | The macOS speech engine and Speakable Items (both deprecated since macOS 14); voices, phonemes and dictionaries are that engine's formats. |
| Sharing | `NSSharingService`, `NSSharingServicePicker`, `NSSharingServicePickerToolbarItem` and their delegates, `NSCloudSharingServiceDelegate`, `NSCloudSharingValidation` | Services are macOS Sharing extensions (AirDrop, Mail, Messages, Notes, iCloud collaboration) found through Launch Services. |
| OpenGL | `NSOpenGLView`, `NSOpenGLContext`, `NSOpenGLPixelFormat`, `NSOpenGLLayer` | CGL, deprecated since macOS 10.14; the port's GPU path is Metal (MTKView over D3D12 and Vulkan). `NSOpenGLPixelBuffer` is not in the Swift inventory; the `NSOpenGLPFA*` constants keep their probed values. |
| Help | `NSHelpManager.registerBooks(in:)`, `openHelpAnchor(_:inBook:)`, `find(_:inBook:)` | Apple Help Books and the Help Viewer. Context help (`setContextHelp`, `showContextHelp`, …) stays `unimplemented()`. |

Core (hand-written, 30 sites switched; every other Core stub untouched): ColorSync
(`NSColorSpace(colorSyncProfile:)`, `colorSyncProfile`); Quartz/Carbon events
(`NSEvent(cgEvent:)`, `NSEvent(eventRef:)`); Core Printing (`NSPrintInfo.pmPageFormat`,
`pmPrintSession`, `pmPrintSettings`, `updateFromPMPageFormat`, `updateFromPMPrintSettings`);
Writing Tools (`NSResponder.showWritingTools`); the window server (`NSGraphicsContext(window:)`,
`setGraphicsState(_:)`, `NSScreen.supportedWindowDepths`); Carbon windows
(`NSWindow(windowRef:)`, `windowRef`); window sharing (`requestSharingOfWindow` ×2,
`transferWindowSharing`); NSWorkspace (`setIcon(_:forFile:options:)`, `requestAuthorization` ×2);
Versions (`NSDocument.browseVersions`); Sharing (`NSDocumentController.standardShareMenuItem`,
`NSTextView.orderFrontSharingServicePicker`); speech (`NSTextView.startSpeaking`/`stopSpeaking`);
Quick Look (`NSTextView.toggleQuickLookPreviewPanel`); the Dictionary service
(`NSView.showDefinition` ×2); inline predictions (`NSSpellChecker.showInlinePrediction`).

### Left as `unimplemented()` on purpose

- **NSScrubber family**: hand-written in Core and working (a scrubber is an ordinary view).
- **`NSColorSampler`**: a screen eyedropper is buildable (xdg-desktop-portal `PickColor`,
  Windows screen capture).
- **`NSPreviewRepresentingActivityItem`**: a plain value holder (item, title, image, icon).
- **`NSWorkspace.OpenConfiguration.isForPrinting`**: maps to the Windows `print` shell verb.
- **Core**: `orderFrontCharacterPalette` (Windows has an emoji panel), pasteboard data
  detection (needs NSDataDetector, not Apple-only), `showCorrectionIndicator` (the port could
  draw the bubble), swipe tracking, nib loading, EPS, window restoration.
- Text input context, text checking, predicate editor, diffable `Reference` classes, PDF info,
  accessibility types and NSImage nested types.

Speech and OpenGL are the judgment calls: SAPI/speech-dispatcher and WGL/EGL exist, so a basic
port is conceivable. Both APIs are deprecated by Apple with replacements outside AppKit
(AVSpeechSynthesizer) or already provided by the port (Metal), so they are classified Apple-only.
Moving an entry back is one config line and a regeneration.

## Numbers

Measured on non-comment lines, at the PR 81 head (49021ed) before and after this change:

| | Before | After |
| --- | ---: | ---: |
| Generated `unimplemented()` | 1,307 | 966 |
| Generated `appleOnlyUnavailable()` | 0 | 341 |
| Core `unimplemented(` | 103 | 73 |
| Core `appleOnlyUnavailable(` | 0 | 30 |
| **Still to do (total)** | **1,410** | **1,039** |

Generated Apple-only sites per family: Touch Bar 184, Sharing 44, OpenGL 39, Speech 37,
Writing Tools 34, Help 3 (33 types, 3 members). Core: 30 sites over 13 types. (The brief's
"about 1,740 Generated" included the header comment every generated file carries.)

## Consequences

- The coverage report's still-to-do number now excludes work the port will never do, and a
  caller that reaches an Apple-only member learns it is a platform limit, not a gap.
- A new Apple-only generated type or member is one `appleOnly` entry plus a reason; the
  generator and the tests reject an entry that drifts from the inventory or the config.
- Any later change to a Core stub or the generated tree must regenerate `docs/API-COVERAGE.md`
  (`python3 tools/apigen/apigen.py`), or `testCoverageReportCountsMatchTheTree` fails.
