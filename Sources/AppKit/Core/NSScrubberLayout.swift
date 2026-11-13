// NSScrubberLayout (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// The abstract layout (ADR-0034): it lays out no items and has no content size; the
// flow and proportional layouts override `prepare()`, `scrubberContentSize` and the
// attribute queries. The scrubber calls `prepare()` before each layout pass and asks for
// the attributes of the items in its visible rect.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayout
@available(macOS 10.12, *)
@MainActor open class NSScrubberLayout: NSObject, NSCoding {
    /// Set by the scrubber the layout is assigned to.
    internal weak var _scrubber: NSScrubber?

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayout/init()
    @MainActor public override init() { super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayout/init(coder:)
    @MainActor public required init(coder: NSCoder) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayout/automaticallymirrorsinrighttoleftlayout
    @MainActor open var automaticallyMirrorsInRightToLeftLayout: Bool { true }
    /// Asks the scrubber for a new layout pass.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayout/invalidatelayout()
    @MainActor open func invalidateLayout() { _scrubber?._layoutInvalidated() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayout/layoutattributesclass
    @MainActor class public var layoutAttributesClass: AnyClass { NSScrubberLayoutAttributes.self }
    /// None in the abstract layout.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayout/layoutattributesforitem(at:)
    @MainActor open func layoutAttributesForItem(at index: Int) -> NSScrubberLayoutAttributes? { nil }
    /// None in the abstract layout.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayout/layoutattributesforitems(in:)
    @MainActor open func layoutAttributesForItems(in rect: NSRect) -> Set<NSScrubberLayoutAttributes> { [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayout/prepare()
    @MainActor open func prepare() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayout/scrubber
    @MainActor open var scrubber: NSScrubber? { _scrubber }
    /// Nothing laid out in the abstract layout.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayout/scrubbercontentsize
    @MainActor open var scrubberContentSize: NSSize { .zero }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayout/shouldinvalidatelayoutforchange(fromvisiblerect:tovisiblerect:)
    @MainActor open func shouldInvalidateLayoutForChange(fromVisibleRect: NSRect, toVisibleRect: NSRect) -> Bool {
        fromVisibleRect.height != toVisibleRect.height
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayout/shouldinvalidatelayoutforhighlightchange
    @MainActor open var shouldInvalidateLayoutForHighlightChange: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayout/shouldinvalidatelayoutforselectionchange
    @MainActor open var shouldInvalidateLayoutForSelectionChange: Bool { false }
    /// The part of the content the scrubber shows, in content coordinates.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberlayout/visiblerect
    @MainActor open var visibleRect: NSRect { _scrubber?._visibleContentRect ?? .zero }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { unimplemented() }
}
