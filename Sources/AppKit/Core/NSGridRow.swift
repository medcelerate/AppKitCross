// NSGridRow (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridrow
@available(macOS 10.12, *)
@MainActor open class NSGridRow: NSObject, NSCoding {
    internal weak var _gridView: NSGridView?
    private var _height: CGFloat = NSGridView.sizedForContent
    private var _topPadding: CGFloat = 0
    private var _bottomPadding: CGFloat = 0
    private var _isHidden = false
    private var _yPlacement: NSGridCell.Placement = .inherited
    private var _rowAlignment: NSGridRow.Alignment = .inherited

    internal override init() { super.init() }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridrow/gridview
    @MainActor open var gridView: NSGridView? { _gridView }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridrow/numberofcells
    @MainActor open var numberOfCells: Int { _gridView?.numberOfColumns ?? 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridrow/cell(at:)
    @MainActor open func cell(at index: Int) -> NSGridCell {
        guard let g = _gridView else { preconditionFailure("NSGridRow: the row is not in a grid view") }
        return g._cell(inRow: self, at: index)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridrow/height
    @MainActor open var height: CGFloat {
        get { _height }
        set { _height = newValue; _gridView?._gridChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridrow/toppadding
    @MainActor open var topPadding: CGFloat {
        get { _topPadding }
        set { _topPadding = newValue; _gridView?._gridChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridrow/bottompadding
    @MainActor open var bottomPadding: CGFloat {
        get { _bottomPadding }
        set { _bottomPadding = newValue; _gridView?._gridChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridrow/ishidden
    @MainActor open var isHidden: Bool {
        get { _isHidden }
        set { _isHidden = newValue; _gridView?._gridChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridrow/yplacement
    @MainActor open var yPlacement: NSGridCell.Placement {
        get { _yPlacement }
        set { _yPlacement = newValue; _gridView?._gridChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridrow/rowalignment
    @MainActor open var rowAlignment: NSGridRow.Alignment {
        get { _rowAlignment }
        set { _rowAlignment = newValue; _gridView?._gridChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridrow/mergecells(in:)
    @MainActor open func mergeCells(in range: NSRange) {
        guard let g = _gridView else { return }
        g.mergeCells(inHorizontalRange: range, verticalRange: NSRange(location: g.index(of: self), length: 1))
    }

    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { unimplemented() }
    // Requirement of NSCoding
    public required init?(coder: NSCoder) { unimplemented() }
}
