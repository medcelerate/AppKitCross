// NSScrubberLayoutAttributes (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// Where a scrubber layout puts one item: its index, frame in the scrubber's content
// coordinates and alpha (ADR-0034).

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayoutattributes
@available(macOS 10.12, *)
open class NSScrubberLayoutAttributes: NSObject, NSCopying {
    private var _alpha: CGFloat = 1
    private var _frame = NSRect.zero
    private var _itemIndex = 0

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayoutattributes/init(foritemat:)
    public convenience init(forItemAt index: Int) {
        self.init()
        _itemIndex = index
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayoutattributes/alpha
    open var alpha: CGFloat {
        get { _alpha }
        set { _alpha = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayoutattributes/frame
    open var frame: NSRect {
        get { _frame }
        set { _frame = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayoutattributes/itemindex
    open var itemIndex: Int {
        get { _itemIndex }
        set { _itemIndex = newValue }
    }
    /// A copy with the same values.
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any {
        let c = NSScrubberLayoutAttributes()
        c._alpha = _alpha
        c._frame = _frame
        c._itemIndex = _itemIndex
        return c
    }
    /// Equal when the index, frame and alpha are.
    open override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? NSScrubberLayoutAttributes else { return false }
        return o._itemIndex == _itemIndex && o._frame == _frame && o._alpha == _alpha
    }
    open override var hash: Int { _itemIndex }
}
