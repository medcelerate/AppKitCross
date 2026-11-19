# SwiftUI shims for API the port does not declare

An app shims a name only when AppKitCross does not provide it. As of 2026-11-18 there is
**no SwiftUI shim to copy**: every name the AGENTS.md validation (ADR-0048, Cat Age
Calculator) had to shim is now part of the port (ADR-0049), with Apple's signatures and
behaviour. Delete these from an existing `PortShims` file; each one is now an ambiguity
error against the port's own declaration.

| Name the validation shimmed | Now in the port |
| --- | --- |
| `#Preview` (and `@Previewable`) | A real macro: the port's compiler plugin expands it into a function that is never called, so the body type-checks; nothing renders (no preview canvas). No `#if` needed. |
| `Section { } header: { }` (no footer) | Every `Section` initialiser; under a `List` the header is a row that cannot be selected. |
| `SecureField` | All initialisers, hosting `NSSecureTextField`, which draws bullets on every backend and never copies its text out. |
| `onReceive(_:perform:)` | Subscribes while the view is in the hierarchy. |
| `ForEach.onDelete(perform:)` | Returns `some DynamicViewContent`; Delete (and Edit > Delete) on the selected rows of a `List` calls it. |
| `remove(atOffsets:)`, `move(fromOffsets:toOffset:)` | SwiftUI's collection extensions. |
| `TextField(_:text:axis:)` | All `axis:` initialisers; `.vertical` wraps and grows with the text. |
| `lineLimit(_: ClosedRange<Int>)` | Also `PartialRangeFrom`, `PartialRangeThrough` and `lineLimit(_:reservesSpace:)`. |

The validation also saw unused-result warnings for `NSPasteboard.setString(_:forType:)` and
`writeObjects(_:)`; those results are discardable now, as they are in Apple's AppKit.

## When you do need a shim

If a SwiftUI or AppKit name is missing (`cannot find 'X' in scope`, `has no member 'x'`,
`extra argument 'x' in call`, or the misleading `generic parameter 'X' could not be
inferred` that a missing overload produces), follow AGENTS.md, step 6: one file in the app
module under `#if APPKITCROSS`, Apple's exact signature, the closest honest behaviour (or
none, said on stderr), and a port-gap issue (AGENTS.md, section 7) so the shim can go.

```swift
#if APPKITCROSS
import Foundation
import SwiftUI

extension View {
    /// Not in AppKitCross yet (issue #NNN); the modifier does nothing on the port.
    func someMissingModifier() -> some View {
        FileHandle.standardError.write(Data("AppKitCross shim: someMissingModifier is a no-op\n".utf8))
        return self
    }
}
#endif
```

Names that can never exist off macOS are not shimmed: they trap with `exists only on macOS`
(ADR-0044), and the call goes behind `#if !APPKITCROSS` with an `#else` that tells the user
the feature is unavailable (AGENTS.md, step 7).
