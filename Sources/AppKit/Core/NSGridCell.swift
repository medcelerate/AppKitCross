// NSGridCell (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// One cell of an `NSGridView`: its content view and the placement overrides. A merged
// region's cells share a head cell, which holds the content and the region's ranges.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridcell
@available(macOS 10.12, *)
@MainActor open class NSGridCell: NSObject, NSCoding {
    internal weak var _gridView: NSGridView?
    internal var _contentView: NSView?
    internal weak var _mergeHead: NSGridCell?
    internal var _mergedColumns: NSRange?
    internal var _mergedRows: NSRange?
    private var _xPlacement: NSGridCell.Placement = .inherited
    private var _yPlacement: NSGridCell.Placement = .inherited
    private var _rowAlignment: NSGridRow.Alignment = .inherited
    private var _customPlacementConstraints: [NSLayoutConstraint] = []

    internal override init() { super.init() }

    private static var _empty: NSView?
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridcell/emptycontentview
    ///
    /// The view to pass in a row or column's views to leave the cell empty.
    @MainActor class public var emptyContentView: NSView {
        if let v = _empty { return v }
        let v = NSView(frame: .zero)
        _empty = v
        return v
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridcell/contentview
    @MainActor open var contentView: NSView? {
        get { _contentView }
        set {
            if let g = _gridView { g._setContent(newValue, of: self) } else { _contentView = newValue === NSGridCell.emptyContentView ? nil : newValue }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridcell/row
    @MainActor open var row: NSGridRow? {
        guard let g = _gridView, let p = g._position(of: self) else { return nil }
        return g.row(at: p.row)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridcell/column
    @MainActor open var column: NSGridColumn? {
        guard let g = _gridView, let p = g._position(of: self) else { return nil }
        return g.column(at: p.column)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridcell/xplacement
    @MainActor open var xPlacement: NSGridCell.Placement {
        get { _xPlacement }
        set { _xPlacement = newValue; _gridView?._gridChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridcell/yplacement
    @MainActor open var yPlacement: NSGridCell.Placement {
        get { _yPlacement }
        set { _yPlacement = newValue; _gridView?._gridChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridcell/rowalignment
    @MainActor open var rowAlignment: NSGridRow.Alignment {
        get { _rowAlignment }
        set { _rowAlignment = newValue; _gridView?._gridChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridcell/customplacementconstraints
    ///
    /// When set, these place the content view instead of the placements.
    @MainActor open var customPlacementConstraints: [NSLayoutConstraint] {
        get { _customPlacementConstraints }
        set { _customPlacementConstraints = newValue; _gridView?._gridChanged() }
    }

    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { unimplemented() }
    // Requirement of NSCoding
    public required init?(coder: NSCoder) { unimplemented() }
}
