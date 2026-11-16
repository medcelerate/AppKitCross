# ADR-0038: Core depth, round 2 — NSEvent, NSApplication, NSColor, NSCell, NSTextView

Date: 2026-11-16. Status: accepted.

## Context

After ADR-0036 (NSView, NSWindow, NSImage) Core still had 657 `unimplemented()` sites. The next
five types by count were NSTextView, NSCell, NSEvent, NSColor and NSApplication: 184 real stubs
(the file headers mention `unimplemented()` twice each, which the raw count of 194 included).
Two generated defects sat underneath them and are fixed here because these types could not work
without it: `NSEvent.EventTypeMask.init(type:)` was a generated stub, so
`NSApplication.nextEvent(matching:…)` and `discardEvents(matching:before:)` trapped; and the
generated `NSTextViewDelegate` defaults answered `false` to `textView(_:shouldChangeTextIn:…)`,
so any delegate that did not implement it stopped all typing (macOS lets the change happen).

Method, as ADR-0036: every behaviour with a measurable answer was printed by the real AppKit on
this Mac (macOS 15, throwaway Swift and Objective-C probes; the Objective-C ones catch the
`NSInternalInconsistencyException`s AppKit raises for members read from the wrong event type)
and the tests assert those values.

## Decision

Each stub is **(a)** implementable with existing Core and seams, **(b)** needs a small backend
hook, or **(c)** out of scope with the reason (kept as `unimplemented("…reason…")`). (a) and (b)
are implemented. Core stubs: 657 → 491.

**Events.** Local monitors run at the top of `NSApplication.sendEvent(_:)` — where macOS 15 runs
them (probed: a posted event reaches them when it is sent, not when `nextEvent` dequeues it) — in
the order they were added, each seeing the previous one's result; nil drops the event, and a
monitor removed by an earlier one in the same pass is skipped. Global monitors go to a new hook
(below). Members AppKit raises for on the wrong event type (tablet fields on a key event, `stage`
on a non-pressure event, touches on a non-gesture event, `characters(byApplyingModifiers:)` on a
mouse event) stop with AppKit's "Invalid message sent to event" message. Tablet fields are stored
and zero (macOS's values for a mouse event no tablet reported); touch queries return empty sets
because no backend delivers per-finger touches. Periodic events post `.periodic` events from a
run-loop timer.

**(b) Two backend hooks** on `PlatformBackend`:

- `characters(forKeyCode:modifierFlags:)` — the layout's translation of the backend's own key
  code with Shift/Option/Control/Caps Lock. Host: Apple's US layout, the table printed by macOS
  (`HostKeyboardLayout.swift`). Windows: `ToUnicode` on a synthesized key state (Option as AltGr,
  Control as Ctrl so it gives control characters as macOS does; flag 4 keeps the dead-key state).
  X11: `XLookupString` on the keysym's keycode with Mod5 for Option. Wayland: a scratch
  `xkb_state` over the current keymap. Core returns function and control keys' own characters
  without asking the backend.
- `setGlobalEventMonitoring(mask:handler:)` — other applications' input. Windows installs
  `WH_MOUSE_LL`/`WH_KEYBOARD_LL` hooks while a global monitor wants their types and skips input
  going to this process's windows; the host backend exposes the handler as a test hook; X11 and
  Wayland keep the default (the monitor exists and is never called — Wayland forbids it, and X11
  would need XInput2 raw events on the root window, left for later).

**Application.** `beginSheet(_:modalFor:modalDelegate:didEnd:contextInfo:)` drives the ADR-0025
sheet seam; its three-argument callback cannot be sent without the runtime, so — as NSDocument's
callbacks already do — the delegate gets the selector through the target/action registry with the
return code as an NSNumber sender. `searchString` is macOS's Help-menu rule (case-insensitive
prefix of a word, the whole word returned), `target(forAction:to:from:)` returns an explicit target
as is and searches the responder chain for nil, `makeWindowsPerform` treats "a handler performed it"
as YES, `orderedDocuments` follows the window order, remote-notification registration fails through
the delegate, Touch Bar and Services members are stored and inert, the run-loop orderings and launch
keys are Apple's constants, `showHelp` says there is no help as macOS does without a help book.

**Colour.** CMYK is a storage case (device formulas; macOS goes through ColorSync, so the tests
assert the port's numbers, not macOS's), with component accessors that stop for non-CMYK colours as
AppKit raises. `usingColorSpaceName` converts between RGB, white and CMYK (it returned `self`
before). Catalog colours: `catalogNameComponent` "System", localized "Developer" (macOS 15),
`init(catalogName:colorName:)` for the system colours and the colour lists. Dynamic colours
(`init(name:dynamicProvider:)`) resolve under the current drawing appearance. `NSColor(named:)`
reads uncompiled asset catalogs (`*.xcassets/<name>.colorset/Contents.json` among the bundle's
resources, with a dark-appearance variant), since SwiftPM copies them as resources off macOS.
Pattern colours store their image and tile it in `drawSwatch`; filling with one needs CGPattern,
which the port's CoreGraphics lacks, so `cgColor`/`set()` of a pattern colour stop with that reason
(a new, explicit trap where the init trapped before). The macOS 26 HDR members store an exposure
over the SDR components. The new system fills and `controlAlternatingRowBackgroundColors` carry
macOS 15's light and dark values.

**Cells.** The field-editor lifecycle is AppKit's (probed): `edit`/`select(withFrame:…)` set the
editor up (`setUpFieldEditorAttributes`, now also called by NSTextFieldCell's override), give it the
cell's text and font, place it over the rect in the control view, set the delegate and make it first
responder with the insertion point at the start; `endEditing` clears the delegate, gives first
responder back to the window, removes and empties the editor, and leaves the cell's value alone.
macOS puts the editor in a private clip view; the port adds it to the control view directly.
`NSCell()` is a null cell; the stored flags have macOS's defaults; focus-ring bounds and expansion
frames are zero for a plain cell; dragging components are icon (+ label for text cells) images that
draw the cell lazily.

**Text view undo.** NSTextView registered no undo at all. Now, with `allowsUndo`, every change
approved in `shouldChangeText(in:replacementString:)` registers a step with the view's undo manager
(the delegate's `undoManager(for:)`, else the window's). Typing and the delete keys coalesce into one
open "Typing" record that grows while edits stay next to it; `breakUndoCoalescing()`, moving the
insertion point away, other changes and undo/redo close it (`isCoalescingUndo`). NSWindow answers `undo:`/`redo:`, so
Edit > Undo reaches the manager. Format actions: `changeAttributes:` through
`NSFontManager.convertAttributes`, `underline:` (NSText's was a no-op), `outline:` (stroke width 3),
`highlight:` (macOS 15's `.textHighlightStyle`/`.textHighlightColorScheme` default values, drawn as a
rounded accent fill under the glyphs — macOS also tints the text), traditional character shape,
document background colour (only with `allowsDocumentBackgroundColorChange`, as macOS), a link
panel (an alert with a URL field), `dragImageForSelection`/`dragSelection`, `fieldEditor()` with
macOS 15's settings. The Writing Tools, inline prediction and math completion settings are stored and
inert.

**Examples.** TextEdit gains Edit > Undo/Redo and Format > Style (Underline, Outline, Highlight,
Add Link…) and lets the document's undo manager count its changes instead of counting every
`didChange` (undoing back to the saved text is clean again). HelloWindow's `coredepth` tab gets an
event monitor button (each event it sees is traced to stderr as `coredepth2 monitor local|global …`,
keys with their Shift and Option characters) and a sheet begun with the legacy call.

**Undo grouping.** A manager that groups by event (the default) opens the event's group on
registration, so the text view opens a group of its own only for a manager that does not; with
both, NSDocument saw two group closes per keystroke and stayed edited after an undo.

## Inventory

(a) implemented with existing Core; (b) new backend hook; (c) left, with the reason in the message.

### NSEvent (38)

| Members | Class | Notes |
|---|---|---|
| addLocalMonitorForEvents, removeMonitor | a | in `sendEvent`, ordered, replace/drop |
| addGlobalMonitorForEvents | b | `setGlobalEventMonitoring`: host, Win32 LL hooks; X11/Wayland never called |
| characters(byApplyingModifiers:) | b | `characters(forKeyCode:modifierFlags:)` on all four backends |
| absoluteX/Y/Z, buttonMask, capabilityMask, deviceID, isEnteringProximity, pointingDeviceID, pointingDeviceSerialNumber, pointingDeviceType, systemTabletID, tabletID, tangentialPressure, tilt, uniqueID, vendorDefined, vendorID, vendorPointingDeviceType | a | stored, zero unless set (`_setTabletFields`); raise off mouse/tablet events |
| associatedEventsMask | a | the button's down/up/dragged (70 for left) |
| allTouches, touches(for:), touches(matching:in:), coalescedTouches(for:) | a | empty on gesture events; raise otherwise |
| stage, stageTransition, pressureBehavior | a | pressure events only |
| foreverDuration, isMouseCoalescingEnabled (get/set) | a | `.greatestFiniteMagnitude`; stored, false (macOS 15) |
| startPeriodicEvents, stopPeriodicEvents | a | run-loop timer posting `.periodic` |
| init(cgEvent:), init(eventRef:) | c | Quartz event services / Carbon are macOS-only |
| trackSwipeEvent | c | the port reports `isSwipeTrackingFromScrollEventsEnabled = false` |

Plus `EventTypeMask.init(type:)` (generated stub → Core, config `handwrittenMembers`).

### NSApplication (32)

| Members | Class | Notes |
|---|---|---|
| beginSheet(_:modalFor:modalDelegate:didEnd:contextInfo:) | a | ADR-0025 seam; didEnd via the registry |
| target(forAction:), target(forAction:to:from:), makeWindowsPerform, validRequestor | a | responder chain |
| searchString(_:inUserInterfaceItemString:range:found:) | a | macOS's word-prefix rule |
| orderedDocuments | a | by window order |
| register/unregisterUserInterfaceItemSearchHandler, registerServicesMenuSendTypes | a | stored, never queried (no Help search field, no Services) |
| registerForRemoteNotifications ×2, unregisterForRemoteNotifications, enabledRemoteNotificationTypes | a | registration fails through the delegate; types empty |
| isAutomaticCustomizeTouchBarMenuItemEnabled (get/set), toggleTouchBarCustomizationPalette | a | stored / no Touch Bar |
| launchIsDefaultUserInfoKey, launchUserNotificationUserInfoKey, display/resetCursorRects/updateWindowsRunLoopOrdering | a | Apple's constants |
| context, applicationShouldSuppressHighDynamicRangeContent, activateContextHelpMode, reply(toOpenOrPrint:), showHelp, yieldActivation(toApplicationWithBundleIdentifier:) | a | nil / false / no-op (NSHelpManager is a stub) / ack / "no help" alert / NSRunningApplication |
| detachDrawingThread | c | a selector on another thread needs the runtime |
| loadApplication | c | no nib/storyboard loader |
| orderFrontCharacterPalette | c | no public character viewer on Windows/X11/Wayland |
| restoreWindow(withIdentifier:state:completionHandler:) | c | the port writes no restoration archives |

### NSColor (35)

| Members | Class | Notes |
|---|---|---|
| init(deviceCyan:…), cyan/magenta/yellow/blackComponent, getCyan | a | CMYK storage; raise for other spaces |
| init(catalogName:colorName:), catalogNameComponent, colorNameComponent, localizedCatalogNameComponent, localizedColorNameComponent, init(for: NSControlTint) | a | System catalog and colour lists |
| init(name:dynamicProvider:), init(named:), init(named:bundle:) | a | dynamic colours; asset-catalog colour sets |
| init(patternImage:), patternImage | a | pattern drawing stops: no CGPattern |
| controlAlternatingRowBackgroundColors, systemFill, secondary/tertiary/quaternary/quinarySystemFill, quinaryLabel | a | macOS 15 light/dark values |
| init(red:…exposure:), init(red:…linearExposure:), linearExposure, applyingContentHeadroom, standardDynamicRange | a | stored exposure |
| ignoresAlpha (get/set), supportsSecureCoding | a | stored false; true |
| colorSpace, init(colorSpace:components:count:), init(colorSpace:hue:saturation:brightness:alpha:) | c | NSColorSpace is a generated stub here; PR #78 (ADR-0037) implements it — wire these after it merges |

### NSCell (39)

| Members | Class | Notes |
|---|---|---|
| edit(withFrame:…), select(withFrame:…), endEditing, setUpFieldEditorAttributes, fieldEditor(for:) | a | AppKit's lifecycle (probed); nil = the window's editor |
| init() | a | null cell |
| allowsUndo, allowsEditingTextAttributes, importsGraphics, controlTint, sendsActionOnEndEditing, userInterfaceLayoutDirection (get/set each), wantsNotificationForMarkedText | a | stored with macOS's defaults |
| focusRingMaskBounds, drawFocusRingMask, expansionFrame, draw(withExpansionFrame:in:) | a | zero / nothing / zero / draw(withFrame:) for a plain cell |
| draggingImageComponents | a | icon (+ label) |
| getPeriodicDelay, hasValidObjectValue, highlightColor, menu(for:in:of:), defaultMenu, prefersTrackingUntilMouseUp | a | 0.2/0.025; formatter check; secondarySelectedControlColor; the cell's menu; nil; false |
| takeDouble/Float/Integer/Object/StringValueFrom | a | from a control or cell |
| accessibilityFrame, accessibilityParent, isAccessibilityFocused, accessibilityIdentifier | a | the control view's |

### NSTextView (40)

| Members | Class | Notes |
|---|---|---|
| breakUndoCoalescing, isCoalescingUndo | a | text undo (new) with typing coalescing |
| changeAttributes, changeDocumentBackgroundColor, highlight, outline, toggleTraditionalCharacterShape, orderFrontLinkPanel, updateFontPanel | a | Format actions through the storage and typing attributes |
| changeLayoutOrientation, setLayoutOrientation | a / c | horizontal works; vertical layout is not implemented |
| dragImageForSelection, dragSelection | a | selection image, drag session |
| fieldEditor(), init(usingTextLayoutManager:) | a | macOS 15 settings; always TextKit 1 |
| allowedWritingToolsResultOptions, writingToolsBehavior, inlinePredictionType, mathExpressionCompletionType, textHighlightAttributes, usesAdaptiveColorMappingForDarkAppearance, contentType (get/set each) | a | stored, inert (no Writing Tools) |
| registerForServices, updateCandidates, updateQuickLookPreviewPanel, updateTextTouchBarItems, updateTouchBarItemIdentifiers | a | nothing to do: no Services, candidate bar, Quick Look panel or Touch Bar |
| drawTextHighlightBackground(for:origin:) | c | NSTextRange (TextKit 2) is a generated stub |
| orderFrontSharingServicePicker, toggleQuickLookPreviewPanel | c | macOS system services |
| orderFrontSpacingPanel | c | panel not built yet |
| startSpeaking, stopSpeaking | c | needs a speech seam (NSSpeechSynthesizer is a stub) |

## Consequences

- Apps get event monitors (SwiftUI's keyboard shortcuts and drag gestures in third-party packages
  use them), real text undo and the Format menu, cell-based editors, CMYK and asset-catalog colours.
- Undo registration happens in `shouldChangeText`, as on macOS: a subclass that overrides it without
  calling super gets no undo, as there.
- PR #78 also rewrites `Generated/NSEvent+Types.swift` and `tools/apigen/config.json`; whichever
  merges second regenerates (this PR's generated hunks come from two config entries).
- Follow-ups: NSColor's colour-space members after PR #78; X11 global monitors (XInput2 raw
  events); vertical text layout; a speech seam; text-colour tint for highlights.
