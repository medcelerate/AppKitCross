// NSScrubberFlowLayout (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// Items in a row, `itemSpacing` apart, each `itemSize` or the size the scrubber's
// delegate gives (NSScrubberFlowLayoutDelegate), centred vertically (ADR-0034).

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberflowlayout
@available(macOS 10.12, *)
@MainActor open class NSScrubberFlowLayout: NSScrubberLayout {
    private var _itemSize = NSSize(width: 50, height: 30)
    private var _itemSpacing: CGFloat = 0
    /// The items' frames from the last `prepare()`.
    private var _frames: [NSRect] = []
    private var _contentSize = NSSize.zero

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberflowlayout/invalidatelayoutforitems(at:)
    @MainActor open func invalidateLayoutForItems(at invalidItemIndexes: IndexSet) { invalidateLayout() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberflowlayout/itemsize
    @MainActor open var itemSize: NSSize {
        get { _itemSize }
        set { _itemSize = newValue; invalidateLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberflowlayout/itemspacing
    @MainActor open var itemSpacing: CGFloat {
        get { _itemSpacing }
        set { _itemSpacing = newValue; invalidateLayout() }
    }

    @MainActor open override func prepare() {
        _frames.removeAll()
        guard let s = scrubber else { _contentSize = .zero; return }
        let n = s.numberOfItems
        let height = s._visibleContentRect.height
        let flowDelegate = s.delegate as? NSScrubberFlowLayoutDelegate
        var x: CGFloat = 0
        _frames.reserveCapacity(n)
        for i in 0..<n {
            let size = flowDelegate?.scrubber(s, layout: self, sizeForItemAt: i) ?? _itemSize
            let h = min(size.height, height)
            _frames.append(NSRect(x: x, y: ((height - h) / 2).rounded(.down), width: size.width, height: h))
            x += size.width + (i < n - 1 ? _itemSpacing : 0)
        }
        _contentSize = NSSize(width: x, height: height)
    }
    @MainActor open override var scrubberContentSize: NSSize { _contentSize }
    @MainActor open override func layoutAttributesForItem(at index: Int) -> NSScrubberLayoutAttributes? {
        guard index >= 0 && index < _frames.count else { return nil }
        let a = NSScrubberLayoutAttributes(forItemAt: index)
        a.frame = _frames[index]
        return a
    }
    @MainActor open override func layoutAttributesForItems(in rect: NSRect) -> Set<NSScrubberLayoutAttributes> {
        var out = Set<NSScrubberLayoutAttributes>()
        for (i, f) in _frames.enumerated() where f.maxX > rect.minX && f.minX < rect.maxX {
            let a = NSScrubberLayoutAttributes(forItemAt: i)
            a.frame = f
            out.insert(a)
        }
        return out
    }
}
