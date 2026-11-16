// NSViewInvalidating (hand-written; ADR-0037). The SDK provides the static members in
// constrained extensions (`where Self == NSView.Invalidations.Display`, ...) so that
// `@NSView.Invalidating(.display)` resolves; the generator can only emit them as
// unconstrained optional-requirement stubs, so the protocol lives in Core.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewinvalidating
@available(macOS 12.0, *)
public protocol NSViewInvalidating {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewinvalidating/invalidate(view:)
    func invalidate(view: NSView)
}

@available(macOS 12.0, *)
extension NSViewInvalidating where Self == NSView.Invalidations.Constraints {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewinvalidating/constraints
    public static var constraints: NSView.Invalidations.Constraints { NSView.Invalidations.Constraints() }
}

@available(macOS 12.0, *)
extension NSViewInvalidating where Self == NSView.Invalidations.Display {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewinvalidating/display
    public static var display: NSView.Invalidations.Display { NSView.Invalidations.Display() }
}

@available(macOS 12.0, *)
extension NSViewInvalidating where Self == NSView.Invalidations.IntrinsicContentSize {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewinvalidating/intrinsiccontentsize
    public static var intrinsicContentSize: NSView.Invalidations.IntrinsicContentSize { NSView.Invalidations.IntrinsicContentSize() }
}

@available(macOS 12.0, *)
extension NSViewInvalidating where Self == NSView.Invalidations.Layout {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewinvalidating/layout
    public static var layout: NSView.Invalidations.Layout { NSView.Invalidations.Layout() }
}

@available(macOS 12.0, *)
extension NSViewInvalidating where Self == NSView.Invalidations.RestorableState {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewinvalidating/restorablestate
    public static var restorableState: NSView.Invalidations.RestorableState { NSView.Invalidations.RestorableState() }
}
