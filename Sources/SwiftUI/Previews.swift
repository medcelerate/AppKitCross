// Xcode previews: the protocol and modifiers libraries declare under `#if DEBUG`; nothing
// renders them here.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/previewprovider
@MainActor @preconcurrency
public protocol PreviewProvider {
    associatedtype Previews: View
    @ViewBuilder static var previews: Previews { get }
    static var platform: PreviewPlatform? { get }
}

extension PreviewProvider {
    public static var platform: PreviewPlatform? { nil }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/previewplatform
public enum PreviewPlatform: Sendable { case iOS, macOS, tvOS, watchOS }

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/previewlayout
public enum PreviewLayout: Sendable {
    case device
    case sizeThatFits
    case fixed(width: CGFloat, height: CGFloat)
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/previewlayout(_:)
    public func previewLayout(_ value: PreviewLayout) -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/previewdisplayname(_:)
    public func previewDisplayName(_ value: String?) -> some View { self }
}

// MARK: #Preview (ADR-0049)

extension Preview {
    /// - SeeAlso: https://developer.apple.com/documentation/developertoolssupport/preview/init(_:traits:body:)
    public init(_ name: String? = nil, traits: PreviewTrait<Preview.ViewTraits>..., body: @escaping @MainActor () -> any View) {
        self = Preview._makeSwiftUIView(name, body: body)
    }
    /// What `#Preview { … }` expands to: the body through `@ViewBuilder`, as the macro
    /// declares it (several views in a preview are one tuple view).
    public static func _makeSwiftUIView(_ name: String? = nil, @ViewBuilder body: @escaping @MainActor () -> any View) -> Preview {
        Preview._erased(name, body: body)
    }
    /// `#Preview(_:traits:_:body:)`'s expansion.
    public static func _makeSwiftUIView(_ name: String? = nil, traits: PreviewTrait<Preview.ViewTraits>, _ additionalTraits: PreviewTrait<Preview.ViewTraits>..., @ViewBuilder body: @escaping @MainActor () -> any View) -> Preview {
        Preview._erased(name, body: body)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/preview(_:body:)
///
/// The port expands this through its own compiler plugin into a function that is never
/// called: the body type-checks as on macOS, and nothing renders (no preview canvas).
@freestanding(declaration)
public macro Preview(_ name: String? = nil, @ViewBuilder body: @escaping @MainActor () -> any View) = #externalMacro(module: "AppKitCrossPreviewMacros", type: "SwiftUIView")
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/preview(_:traits:_:body:)
@freestanding(declaration)
public macro Preview(_ name: String? = nil, traits: PreviewTrait<Preview.ViewTraits>, _ additionalTraits: PreviewTrait<Preview.ViewTraits>..., @ViewBuilder body: @escaping @MainActor () -> any View) = #externalMacro(module: "AppKitCrossPreviewMacros", type: "SwiftUIView")
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/previewable()
///
/// Marks a `@State` (or other dynamic property) declared in a `#Preview` body. The port's
/// previews never run, so this expands to nothing and the variable stays a local.
@attached(peer)
public macro Previewable() = #externalMacro(module: "AppKitCrossPreviewMacros", type: "Previewable")
