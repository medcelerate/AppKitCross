// Xcode previews (DeveloperToolsSupport, which AppKit and SwiftUI re-export on macOS):
// `Preview`, its traits and builders, and `#Preview` for AppKit views (ADR-0049). The
// macro expands through the port's own compiler plugin (Sources/PreviewMacros) into a
// never-called function, so a preview's body type-checks and nothing renders: the port
// has no preview canvas.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/developertoolssupport/preview
@MainActor @preconcurrency
public struct Preview {
    /// The macro's expansions build one of these; the body is kept, never called.
    @usableFromInline let _body: Any
    @usableFromInline let _name: String?
    @usableFromInline init(_name name: String?, body: Any) { _name = name; _body = body }
    /// A preview of any body (SwiftUI's initialisers build theirs through this).
    public static func _erased(_ name: String?, body: Any) -> Preview { Preview(_name: name, body: body) }

    /// - SeeAlso: https://developer.apple.com/documentation/developertoolssupport/preview/init(_:traits:body:)-4gsbu
    public init(_ name: String? = nil, traits: PreviewTrait<Preview.ViewTraits>..., body: @escaping @MainActor () -> NSView) {
        self.init(_name: name, body: body)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/developertoolssupport/preview/init(_:traits:body:)-8bxhd
    public init(_ name: String? = nil, traits: PreviewTrait<Preview.ViewTraits>..., body: @escaping @MainActor () -> NSViewController) {
        self.init(_name: name, body: body)
    }

    /// What `#Preview { NSView }` expands to (the body through the macro's builder).
    public static func _makeKitViewMacro(_ name: String? = nil, traits: PreviewTrait<Preview.ViewTraits>..., @PreviewMacroBodyBuilder<NSView> body: @escaping @MainActor () -> NSView) -> Preview {
        Preview(_name: name, body: body)
    }
    /// What `#Preview { NSViewController }` expands to.
    public static func _makeKitViewMacro(_ name: String? = nil, traits: PreviewTrait<Preview.ViewTraits>..., @PreviewMacroBodyBuilder<NSViewController> body: @escaping @MainActor () -> NSViewController) -> Preview {
        Preview(_name: name, body: body)
    }
}

extension Preview {
    /// - SeeAlso: https://developer.apple.com/documentation/developertoolssupport/preview/viewtraits
    public enum ViewTraits {}
}

/// - SeeAlso: https://developer.apple.com/documentation/developertoolssupport/previewtrait
@MainActor @preconcurrency
public struct PreviewTrait<T> {
    @usableFromInline let _description: String
    @usableFromInline init(_description: String) { self._description = _description }
    /// - SeeAlso: https://developer.apple.com/documentation/developertoolssupport/previewtrait/init(_:)
    public init(_ traits: PreviewTrait<T>...) { _description = traits.map(\._description).joined(separator: ", ") }
}

extension PreviewTrait where T == Preview.ViewTraits {
    /// - SeeAlso: https://developer.apple.com/documentation/developertoolssupport/previewtrait/defaultlayout
    public static var defaultLayout: PreviewTrait<Preview.ViewTraits> { PreviewTrait(_description: "defaultLayout") }
    /// - SeeAlso: https://developer.apple.com/documentation/developertoolssupport/previewtrait/sizethatfitslayout
    public static var sizeThatFitsLayout: PreviewTrait<Preview.ViewTraits> { PreviewTrait(_description: "sizeThatFitsLayout") }
    /// - SeeAlso: https://developer.apple.com/documentation/developertoolssupport/previewtrait/fixedlayout(width:height:)
    public static func fixedLayout(width: CGFloat, height: CGFloat) -> PreviewTrait<T> { PreviewTrait(_description: "fixedLayout(\(width)x\(height))") }
}

/// - SeeAlso: https://developer.apple.com/documentation/developertoolssupport/previewmacrobodybuilder
@resultBuilder
public struct PreviewMacroBodyBuilder<Content> {
    public static func buildBlock(_ content: Content) -> Content { content }
    @available(*, unavailable, message: "This builder requires exactly one content expression")
    public static func buildBlock(_ content: Content...) -> Content { content[0] }
    @available(*, unavailable, message: "This builder does not support control flow statements")
    public static func buildOptional(_ content: Content?) -> Content { content! }
    @available(*, unavailable, message: "This builder does not support control flow statements")
    public static func buildEither(first content: Content) -> Content { content }
    @available(*, unavailable, message: "This builder does not support control flow statements")
    public static func buildEither(second content: Content) -> Content { content }
    @available(*, unavailable, message: "This builder does not support control flow statements")
    public static func buildLimitedAvailability(_ content: Content) -> Content { content }
}

/// - SeeAlso: https://developer.apple.com/documentation/developertoolssupport/previewbodybuilder
@resultBuilder
public struct PreviewBodyBuilder<Content> {
    public static func buildBlock(_ content: Content) -> Content { content }
    @available(*, unavailable, message: "This builder requires exactly one content expression")
    public static func buildBlock(_ content: Content...) -> Content { content[0] }
    @available(*, unavailable, message: "This builder does not support control flow statements")
    public static func buildOptional(_ content: Content?) -> Content { content! }
    @available(*, unavailable, message: "This builder does not support control flow statements")
    public static func buildEither(first content: Content) -> Content { content }
    @available(*, unavailable, message: "This builder does not support control flow statements")
    public static func buildEither(second content: Content) -> Content { content }
    @available(*, unavailable, message: "This builder does not support control flow statements")
    public static func buildLimitedAvailability(_ content: Content) -> Content { content }
}

/// - SeeAlso: https://developer.apple.com/documentation/developertoolssupport/previewregistry
public protocol PreviewRegistry {
    static var fileID: String { get }
    static var line: Int { get }
    static var column: Int { get }
    @MainActor static func makePreview() throws -> Preview
}

/// - SeeAlso: https://developer.apple.com/documentation/developertoolssupport/previewunavailable
public struct PreviewUnavailable: Error {
    public init() {}
}

/// - SeeAlso: https://developer.apple.com/documentation/appkit/preview(_:traits:body:)
@freestanding(declaration)
public macro Preview(_ name: String? = nil, traits: PreviewTrait<Preview.ViewTraits>..., @PreviewMacroBodyBuilder<NSView> body: @escaping @MainActor () -> NSView) = #externalMacro(module: "AppKitCrossPreviewMacros", type: "KitViewMacro")
/// - SeeAlso: https://developer.apple.com/documentation/appkit/preview(_:traits:body:)
@freestanding(declaration)
public macro Preview(_ name: String? = nil, traits: PreviewTrait<Preview.ViewTraits>..., @PreviewMacroBodyBuilder<NSViewController> body: @escaping @MainActor () -> NSViewController) = #externalMacro(module: "AppKitCrossPreviewMacros", type: "KitViewMacro")
