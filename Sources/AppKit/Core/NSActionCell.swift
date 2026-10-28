// NSActionCell (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif
#if canImport(CoreText)
import CoreText
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsactioncell
@MainActor open class NSActionCell: NSCell {
    private weak var _target: AnyObject?
    private var _action: Selector? = nil

    @MainActor open override var controlView: NSView? {
        get { _controlView }
        set { _controlView = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsactioncell/action
    @MainActor open override var action: Selector? {
        get { _action }
        set { _action = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsactioncell/tag
    @MainActor open override var tag: Int {
        get { _tag }
        set { _tag = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsactioncell/target
    @MainActor open override var target: AnyObject? {
        get { _target }
        set { _target = newValue }
    }
}
