// NSScrubberProportionalLayout (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// Each item is the visible width divided by `numberOfVisibleItems`, the full height
// (ADR-0034).

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberproportionallayout
@available(macOS 10.12, *)
@MainActor open class NSScrubberProportionalLayout: NSScrubberLayout {
    private var _numberOfVisibleItems: Int
    private var _itemWidth: CGFloat = 0
    private var _height: CGFloat = 0
    private var _count = 0

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberproportionallayout/init(coder:)
    public required init(coder: NSCoder) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberproportionallayout/init(numberofvisibleitems:)
    @MainActor public init(numberOfVisibleItems: Int) {
        _numberOfVisibleItems = max(1, numberOfVisibleItems)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberproportionallayout/numberofvisibleitems
    @MainActor open var numberOfVisibleItems: Int {
        get { _numberOfVisibleItems }
        set { _numberOfVisibleItems = max(1, newValue); invalidateLayout() }
    }

    @MainActor open override func prepare() {
        guard let s = scrubber else { _count = 0; _itemWidth = 0; _height = 0; return }
        let visible = s._visibleContentRect
        _count = s.numberOfItems
        _itemWidth = visible.width / CGFloat(_numberOfVisibleItems)
        _height = visible.height
    }
    @MainActor open override var scrubberContentSize: NSSize { NSSize(width: _itemWidth * CGFloat(_count), height: _height) }
    private func _frame(_ i: Int) -> NSRect { NSRect(x: _itemWidth * CGFloat(i), y: 0, width: _itemWidth, height: _height) }
    @MainActor open override func layoutAttributesForItem(at index: Int) -> NSScrubberLayoutAttributes? {
        guard index >= 0 && index < _count else { return nil }
        let a = NSScrubberLayoutAttributes(forItemAt: index)
        a.frame = _frame(index)
        return a
    }
    @MainActor open override func layoutAttributesForItems(in rect: NSRect) -> Set<NSScrubberLayoutAttributes> {
        guard _count > 0, _itemWidth > 0 else { return [] }
        let first = max(0, Int((rect.minX / _itemWidth).rounded(.down)))
        let last = min(_count - 1, Int((rect.maxX / _itemWidth).rounded(.up)) - 1)
        guard first <= last else { return [] }
        return Set((first...last).map { i in
            let a = NSScrubberLayoutAttributes(forItemAt: i)
            a.frame = _frame(i)
            return a
        })
    }
}
