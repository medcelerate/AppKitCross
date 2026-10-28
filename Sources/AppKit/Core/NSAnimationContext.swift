// NSAnimationContext (hand-written; seeded from the generated stub, see tools/apigen)
// Groups animatable property changes made through `animator()` and implicit layer
// animations; each grouping is a CATransaction.

import Foundation
#if canImport(QuartzCore)
import QuartzCore
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimationcontext
@MainActor open class NSAnimationContext: NSObject {
    private static var stack: [NSAnimationContext] = []
    private static let root = NSAnimationContext()

    private var isGroup = false

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimationcontext/current
    public class var current: NSAnimationContext { stack.last ?? root }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimationcontext/duration
    open var duration: TimeInterval = 0.25 {
        didSet { if isGroup && NSAnimationContext.stack.last === self { CATransaction.setAnimationDuration(duration) } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimationcontext/timingfunction
    open var timingFunction: CAMediaTimingFunction? {
        didSet { if isGroup && NSAnimationContext.stack.last === self { CATransaction.setAnimationTimingFunction(timingFunction) } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimationcontext/completionhandler
    open var completionHandler: (() -> Void)? {
        didSet { if isGroup && NSAnimationContext.stack.last === self { CATransaction.setCompletionBlock(completionHandler) } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimationcontext/allowsimplicitanimation
    open var allowsImplicitAnimation = false

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimationcontext/begingrouping()
    public class func beginGrouping() {
        let c = NSAnimationContext()
        c.isGroup = true
        c.duration = current.duration
        c.timingFunction = current.timingFunction
        c.allowsImplicitAnimation = current.allowsImplicitAnimation
        stack.append(c)
        CATransaction.begin()
        CATransaction.setAnimationDuration(c.duration)
        CATransaction.setAnimationTimingFunction(c.timingFunction)
        CATransaction.setCompletionBlock(nil)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimationcontext/endgrouping()
    public class func endGrouping() {
        guard let c = stack.popLast() else { return }
        c.isGroup = false
        CATransaction.commit()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimationcontext/runanimationgroup(_:)
    @available(macOS 10.12, *)
    public class func runAnimationGroup(_ changes: (NSAnimationContext) -> Void) {
        runAnimationGroup(changes, completionHandler: nil)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimationcontext/runanimationgroup(_:completionhandler:)
    public class func runAnimationGroup(_ changes: (NSAnimationContext) -> Void, completionHandler: (() -> Void)?) {
        beginGrouping()
        let c = current
        c.completionHandler = completionHandler
        changes(c)
        endGrouping()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimationcontext/runanimationgroup(_:)
    public class func runAnimationGroup(_ changes: (NSAnimationContext) -> Void) async {
        await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
            runAnimationGroup(changes, completionHandler: { k.resume() })
        }
    }
}
