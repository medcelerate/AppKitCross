// NSTableColumn (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecolumn
@MainActor open class NSTableColumn: NSObject, NSCoding, NSUserInterfaceItemIdentification {
    private var _identifier: NSUserInterfaceItemIdentifier
    private var _title = ""
    private var _width: CGFloat = 100
    private var _minWidth: CGFloat = 10
    private var _maxWidth: CGFloat = 100_000
    private var _isEditable = true
    private var _isHidden = false
    private var _resizingMask: NSTableColumn.ResizingOptions = [.userResizingMask, .autoresizingMask]
    private var _headerCell: NSTableHeaderCell
    private var _dataCell: Any = NSTextFieldCell(textCell: "")
    private var _headerToolTip: String?
    private var _sortDescriptorPrototype: NSSortDescriptor?
    internal weak var _tableView: NSTableView?

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecolumn/init(coder:)
    public required init?(coder: NSCoder) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecolumn/init(identifier:)
    @MainActor public init(identifier: NSUserInterfaceItemIdentifier) {
        _identifier = identifier
        _headerCell = NSTableHeaderCell(textCell: "")
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecolumn/datacell
    @MainActor open var dataCell: Any {
        get { _dataCell }
        set { _dataCell = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecolumn/datacell(forrow:)
    @MainActor open func dataCell(forRow row: Int) -> Any { _dataCell }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecolumn/headercell
    @MainActor open var headerCell: NSTableHeaderCell {
        get { _headerCell }
        set { _headerCell = newValue; _tableView?.headerView?.needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecolumn/headertooltip
    @MainActor open var headerToolTip: String? {
        get { _headerToolTip }
        set { _headerToolTip = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecolumn/identifier
    @MainActor open var identifier: NSUserInterfaceItemIdentifier {
        get { _identifier }
        set { _identifier = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecolumn/iseditable
    @MainActor open var isEditable: Bool {
        get { _isEditable }
        set { _isEditable = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecolumn/ishidden
    @MainActor open var isHidden: Bool {
        get { _isHidden }
        set { guard newValue != _isHidden else { return }; _isHidden = newValue; _tableView?._columnsDidChange() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecolumn/maxwidth
    @MainActor open var maxWidth: CGFloat {
        get { _maxWidth }
        set { _maxWidth = max(newValue, _minWidth); if _width > _maxWidth { width = _maxWidth } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecolumn/minwidth
    @MainActor open var minWidth: CGFloat {
        get { _minWidth }
        set { _minWidth = max(0, newValue); if _width < _minWidth { width = _minWidth } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecolumn/resizingmask
    @MainActor open var resizingMask: NSTableColumn.ResizingOptions {
        get { _resizingMask }
        set { _resizingMask = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecolumn/sizetofit()
    @MainActor open func sizeToFit() {
        let w = _headerCell.cellSize.width + 8
        width = min(max(w, _minWidth), _maxWidth)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecolumn/sortdescriptorprototype
    @MainActor open var sortDescriptorPrototype: NSSortDescriptor? {
        get { _sortDescriptorPrototype }
        set { _sortDescriptorPrototype = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecolumn/tableview
    @MainActor open var tableView: NSTableView? {
        get { _tableView }
        set { _tableView = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecolumn/title
    @MainActor open var title: String {
        get { _title }
        set { _title = newValue; _headerCell.stringValue = newValue; _tableView?.headerView?.needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecolumn/width
    @MainActor open var width: CGFloat {
        get { _width }
        set {
            let clamped = min(max(newValue, _minWidth), _maxWidth)
            guard clamped != _width else { return }
            _width = clamped
            _tableView?._columnDidResize(self)
        }
    }
    /// Sets the width without clamping or notifying (the table's own autoresizing).
    internal func _setWidthQuietly(_ w: CGFloat) { _width = min(max(w, _minWidth), _maxWidth) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablecolumn/encode(with:)
    open func encode(with coder: NSCoder) { unimplemented() }
}
