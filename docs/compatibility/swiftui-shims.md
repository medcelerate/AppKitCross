# SwiftUI shims for API the port does not declare yet

Drop-in stand-ins an app can carry while AppKitCross lacks these SwiftUI names (status
2026-11-18). They were written by the second agent validating [AGENTS.md](../../AGENTS.md) on
Cat Age Calculator (MIT), and compiled with the app's tests passing on the macOS host build
and in the Linux container. Copy the file into the app module as
`PortShims/SwiftUIPortShims.swift`; it compiles only where the manifest defines `APPKITCROSS`
(AGENTS.md, section 2). Names and signatures are Apple's, so when the port adds a name the
shim turns into an ambiguity error: delete that part. Each gap is also a port issue to close
in `Sources/SwiftUI`.

| Missing on the port | How it shows up | Shim behaviour |
| --- | --- | --- |
| `#Preview` | an error at each `#Preview` | none: wrap previews in `#if !APPKITCROSS` |
| `Section { } header: { }` (no footer) | `generic parameter 'Footer' could not be inferred`, `missing argument for parameter 'footer' in call` | real |
| `SecureField` | an error naming `SecureField` | a plain text field: **text not masked**, says so on stderr |
| `onReceive(_:perform:)` | an error naming `onReceive` | real (subscribes on appear, cancels on disappear) |
| `ForEach.onDelete(perform:)` | an error naming `onDelete` | no-op returning `some View` (the port has no `DynamicViewContent`, so Apple's return type is impossible) |
| `remove(atOffsets:)` | `no exact matches in call to instance method 'remove'` | real |
| `TextField(_:text:axis:)` | `extra argument 'axis' in call`, `cannot infer contextual base in reference to member 'vertical'` | single line; `axis` ignored |
| `lineLimit(_: ClosedRange<Int>)` | an error at the range argument | upper bound used |

A shim cannot read a `LocalizedStringKey`'s text (it is internal), so `SecureField` stores a
`TextField` built from the key.

```swift
// Stand-ins for SwiftUI API the AppKitCross port does not declare yet. Compiled only into
// port builds (`APPKITCROSS`); the Apple build uses SwiftUI's own. Names and signatures are
// Apple's, so deleting a shim is the whole migration once the port adds the API.
#if APPKITCROSS
import Combine
import Foundation
import SwiftUI

private func portShimNote(_ message: String) {
    FileHandle.standardError.write(Data("AppKitCross shim: \(message)\n".utf8))
}

// MARK: - View.onReceive

extension View {
    func onReceive<P: Publisher>(
        _ publisher: P,
        perform action: @escaping (P.Output) -> Void
    ) -> some View where P.Failure == Never {
        modifier(ReceiveShim(publisher: publisher, action: action))
    }
}

private struct ReceiveShim<P: Publisher>: ViewModifier where P.Failure == Never {
    let publisher: P
    let action: (P.Output) -> Void
    @State private var token: AnyCancellable?

    func body(content: Content) -> some View {
        content
            .onAppear { token = publisher.sink(receiveValue: action) }
            .onDisappear { token = nil }
    }
}

// MARK: - Section { } header: { }

extension Section where Footer == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent) {
        self.init(content: content, header: header, footer: { EmptyView() })
    }
}

// MARK: - SecureField

/// The port has no `SecureField`; this one is a plain text field, so the text is NOT masked.
struct SecureField<Label: View>: View {
    private let field: TextField<Text>

    init(_ titleKey: LocalizedStringKey, text: Binding<String>) where Label == Text {
        field = TextField(titleKey, text: text)
    }

    init<S: StringProtocol>(_ title: S, text: Binding<String>) where Label == Text {
        field = TextField(String(title), text: text)
    }

    var body: some View {
        field.onAppear { portShimNote("SecureField draws its text unmasked on this platform") }
    }
}

// MARK: - TextField(_:text:axis:) and lineLimit(_: ClosedRange)

extension TextField where Label == Text {
    /// The port's text field is single-line; `axis` is ignored.
    init(_ titleKey: LocalizedStringKey, text: Binding<String>, axis: Axis) {
        self.init(titleKey, text: text)
    }
}

extension View {
    /// The port has only `lineLimit(Int?)`; the range's upper bound is used.
    func lineLimit(_ limit: ClosedRange<Int>) -> some View {
        lineLimit(limit.upperBound)
    }
}

// MARK: - ForEach.onDelete

extension ForEach {
    /// The port's lists have no delete action yet; the action is never called.
    func onDelete(perform action: ((IndexSet) -> Void)?) -> some View {
        self
    }
}

// MARK: - remove(atOffsets:)

extension RangeReplaceableCollection where Self: MutableCollection {
    mutating func remove(atOffsets offsets: IndexSet) {
        for offset in offsets.reversed() {
            remove(at: index(startIndex, offsetBy: offset))
        }
    }
}
#endif
```
