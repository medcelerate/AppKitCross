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
