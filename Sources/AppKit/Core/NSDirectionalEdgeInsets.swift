// NSDirectionalEdgeInsets: insets whose horizontal edges follow the layout direction.
// Hand-written so NSDirectionalEdgeInsetsZero has a value (ADR-0033). Apple imports it
// from a C struct, so its fields are stored and settable.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdirectionaledgeinsets
@available(macOS 10.15, *)
public struct NSDirectionalEdgeInsets: Sendable {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdirectionaledgeinsets/top
    public var top: CGFloat
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdirectionaledgeinsets/leading
    public var leading: CGFloat
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdirectionaledgeinsets/bottom
    public var bottom: CGFloat
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdirectionaledgeinsets/trailing
    public var trailing: CGFloat

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdirectionaledgeinsets/init()
    public init() { self.init(top: 0, leading: 0, bottom: 0, trailing: 0) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdirectionaledgeinsets/init(top:leading:bottom:trailing:)
    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
}
