# ADR-0049: Closing the gaps the AGENTS.md validation shimmed

Date: 2026-11-18. Status: accepted.

## Context

Validating AGENTS.md (ADR-0048) had two fresh agents port Cat Age Calculator (MIT). Both
passed its tests only after shimming names the port lacked, collected in
`docs/compatibility/swiftui-shims.md`: `#Preview`, `SecureField`, `onReceive`,
`ForEach.onDelete`, `remove(atOffsets:)`, `lineLimit(_: ClosedRange<Int>)`,
`TextField(_:text:axis:)` and `Section { } header: { }` without a footer. The shims were
honest but degraded (an unmasked password field, a delete action never called), and
`NSSecureTextField` itself drew its text in clear on every backend. The validation also hit
warnings for unused results of `NSPasteboard.setString(_:forType:)` and `writeObjects(_:)`,
which Swift never reports against Apple's AppKit.

## Decision

1. **A secure field masks in AppKit, not in SwiftUI.** `NSSecureTextField` and
   `NSSecureTextFieldCell` move to `Core`. The cell draws and measures one bullet per
   character (`echosBullets`; nothing when false), keeping the real text as its value.
   Editing uses a second field editor per window, returned by `NSWindow.fieldEditor(_:for:)`
   for a secure field as AppKit does: a TextKit 1 `NSTextView` whose `NSLayoutManager` lays
   out a masked copy of the storage. The mask keeps UTF-16 offsets one to one (a bullet for a
   character's first unit, zero-width spaces for the rest), so the caret, selection and
   hit-testing need no change. That editor never writes to a pasteboard (copy, cut, drag,
   services) and reads as bullets to assistive technology. `SecureField` hosts the masked
   field through its own primitive type, so switching between a `TextField` and a
   `SecureField` makes a new control. Every backend draws through the same cell and layout
   manager, so masking needs no platform code.
2. **`#Preview` is a real macro with a dependency-free plugin.** Apple's expansion lives in
   Xcode's PreviewsMacros plugin, which open-source toolchains lack. A SwiftPM `.macro`
   target does not need swift-syntax: a compiler plugin is an executable that answers the
   compiler's length-prefixed JSON messages. `AppKitCrossPreviewMacros` (about 100 lines of
   Foundation) expands `#Preview(args) { body }` into a never-called
   `@MainActor private func` named the way swift-syntax's `makeUniqueName` would (the
   compiler accepts that name at file scope), returning `Preview._make<Kind>(args) { body }`.
   The body is type-checked through `@ViewBuilder` (SwiftUI) or `PreviewMacroBodyBuilder`
   (AppKit) as Apple declares it, so an error in a preview points at the app's source;
   nothing runs because the port has no canvas. `@Previewable` expands to nothing. AppKit
   declares the `NSView`/`NSViewController` macros and `Preview`, `PreviewTrait`,
   `Preview.ViewTraits` and the builders (DeveloperToolsSupport, which AppKit re-exports on
   macOS); SwiftUI adds the `View` macros and `Preview.init(_:traits:body:)`. Rejected: a
   swift-syntax macro target (minutes of extra build on every CI job and for every consumer,
   and a network dependency for a package that has none) and a documented `#if` workaround
   (a source change in every app).
3. **`onReceive`** subscribes when its node is attached and cancels on detach; updates
   replace the action without resubscribing, so an inline `Timer.publish(...).autoconnect()`
   keeps one subscription. The action runs where the publisher delivers, as on macOS.
4. **`DynamicViewContent` and `onDelete`.** `ForEach` (and `ModifiedContent` over it)
   conforms; `onDelete(perform:)` returns `some DynamicViewContent` as Apple's does. In a
   `List` with a selection, Delete, Forward Delete and Edit > Delete call each `onDelete` with
   the offsets of its selected rows (a `ForEach` now has its own transparent primitive so a
   row maps back to its element). `onMove` is not declared: reordering by drag is not built.
   `remove(atOffsets:)` (on `RangeReplaceableCollection & MutableCollection`) and
   `move(fromOffsets:toOffset:)` (on `MutableCollection`) are SwiftUI's, order-preserving.
5. **Sections in lists.** `Section` is a row provider: under a `List` its header and footer
   are rows of their own that cannot be selected and have no separators, arrow keys step over
   them, and its content's rows follow. All of Apple's initialisers exist (content/header/
   footer closures in each combination, a `LocalizedStringKey` or `StringProtocol` title, and
   the deprecated `header:`/`footer:` value forms).
6. **Ranged `lineLimit` and vertical text fields.** `lineLimit` takes `ClosedRange`,
   `PartialRangeFrom`, `PartialRangeThrough` and `(_:reservesSpace:)`; the environment keeps
   the maximum in `lineLimit` and the minimum beside it. `TextField(…, axis: .vertical)` wraps
   and grows with its text between those bounds (macOS's heights: 21 pt for one 16 pt line,
   +16 pt a line); the field editor wraps for a wrapping cell, Return submits and
   Option-Return (`insertNewlineIgnoringFieldEditor:`) types a newline. Text with
   `reservesSpace` takes the height of its lines however short it is. A horizontal field stays
   one line whatever its text holds.
7. **Discardable AppKit results.** Swift imports every Objective-C method's result as
   discardable. `NSPasteboard` and `NSPasteboardItem`'s `Bool`/`Int` results get
   `@discardableResult` now; the same is true of every AppKit method, which the generator and
   the hand-written classes do not yet reflect (a follow-up).

## Consequences

- The shims page keeps only what cannot be provided (none of the validation's names), and
  AGENTS.md lists no SwiftUI gaps from the validation. Cat Age Calculator builds and passes
  its tests with no shim (recorded in the pull request).
- The package has its first macro target. It builds on every toolchain the port supports,
  adds no dependency, and must follow the compiler's plugin protocol; it answers with the
  protocol version the compiler offers (up to 7) and only the messages it needs.
- `SwiftUIPortGapsTests` (10) covers each item, including the masked render on the host
  backend. On Windows the visible check is a SecureField showing bullets while typing.
