// NSGridColumn (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridcolumn
@available(macOS 10.12, *)
@MainActor open class NSGridColumn: NSObject, NSCoding {
    internal weak var _gridView: NSGridView?
    private var _width: CGFloat = NSGridView.sizedForContent
    private var _leadingPadding: CGFloat = 0
    private var _trailingPadding: CGFloat = 0
    private var _isHidden = false
    private var _xPlacement: NSGridCell.Placement = .inherited

    internal override init() { super.init() }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridcolumn/gridview
    @MainActor open var gridView: NSGridView? { _gridView }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridcolumn/numberofcells
    @MainActor open var numberOfCells: Int { _gridView?.numberOfRows ?? 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridcolumn/cell(at:)
    @MainActor open func cell(at index: Int) -> NSGridCell {
        guard let g = _gridView else { preconditionFailure("NSGridColumn: the column is not in a grid view") }
        return g._cell(inColumn: self, at: index)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridcolumn/width
    @MainActor open var width: CGFloat {
        get { _width }
        set { _width = newValue; _gridView?._gridChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridcolumn/leadingpadding
    @MainActor open var leadingPadding: CGFloat {
        get { _leadingPadding }
        set { _leadingPadding = newValue; _gridView?._gridChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridcolumn/trailingpadding
    @MainActor open var trailingPadding: CGFloat {
        get { _trailingPadding }
        set { _trailingPadding = newValue; _gridView?._gridChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridcolumn/ishidden
    @MainActor open var isHidden: Bool {
        get { _isHidden }
        set { _isHidden = newValue; _gridView?._gridChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridcolumn/xplacement
    @MainActor open var xPlacement: NSGridCell.Placement {
        get { _xPlacement }
        set { _xPlacement = newValue; _gridView?._gridChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridcolumn/mergecells(in:)
    @MainActor open func mergeCells(in range: NSRange) {
        guard let g = _gridView else { return }
        g.mergeCells(inHorizontalRange: NSRange(location: g.index(of: self), length: 1), verticalRange: range)
    }

    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { unimplemented() }
    // Requirement of NSCoding
    public required init?(coder: NSCoder) { unimplemented() }
}
