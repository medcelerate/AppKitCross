// NSPathCell (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// A URL shown as its components. The standard style lays the component cells out from
// the leading edge with chevrons between them, shrinking all but the last when the
// frame is too narrow; the pop-up style looks like a pop-up button showing the last
// component, and its menu (one item per ancestor, "Choose…" when editable) is built by
// the control.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcell
@MainActor open class NSPathCell: NSActionCell, NSMenuItemValidation, NSOpenSavePanelDelegate {
    // MARK: Storage
    private var _url: URL? = nil
    private var _componentCells: [NSPathComponentCell] = []
    private var _cellsAreCustom = false
    private var _pathStyle: NSPathControl.Style = .standard
    private var _placeholderString: String? = nil
    private var _placeholderAttributedString: NSAttributedString? = nil
    private var _backgroundColor: NSColor? = nil
    private var _allowedTypes: [String]? = nil
    private var _doubleAction: Selector? = nil
    private weak var _delegate: (any NSPathCellDelegate)?
    internal var _clickedCell: NSPathComponentCell? = nil
    /// True while the pop-up style's menu is open.
    internal var _menuOpen = false
    nonisolated(unsafe) private static var _componentCellClass: AnyClass = NSPathComponentCell.self

    static let chevronWidth: CGFloat = 12
    static let popUpChevronWidth: CGFloat = 18

    @MainActor public override init(textCell string: String) {
        super.init(textCell: string)
        _isEditable = false
    }
    @MainActor public required init(coder: NSCoder) { super.init(coder: coder) }

    // MARK: Components

    /// Builds one cell per path component of `url` (the root first).
    @MainActor internal static func _cells(for url: URL?) -> [NSPathComponentCell] {
        guard let url else { return [] }
        let components = url.pathComponents
        var cells: [NSPathComponentCell] = []
        var path = url.isFileURL ? URL(fileURLWithPath: "/") : url
        var isRoot = true
        for comp in components {
            let cell = NSPathComponentCell(textCell: comp)
            if isRoot && comp == "/" {
                cell.stringValue = url.isFileURL ? (url.host ?? "/") : "/"
                cell.url = path
            } else {
                path = isRoot && !url.isFileURL ? url : path.appendingPathComponent(comp)
                cell.url = path
            }
            isRoot = false
            cells.append(cell)
        }
        if !url.isFileURL, cells.isEmpty { let c = NSPathComponentCell(textCell: url.absoluteString); c.url = url; cells = [c] }
        return cells
    }

    private func _rebuildCells() {
        guard !_cellsAreCustom else { return }
        _componentCells = NSPathCell._cells(for: _url)
        for c in _componentCells { c.controlView = _controlView; c.font = _font }
    }

    // MARK: Geometry

    /// The rect of each component cell inside `frame`, in order. Natural widths when
    /// they fit; otherwise all but the last shrink proportionally (never below 24 pt).
    @MainActor internal func _componentRects(in frame: NSRect, rightToLeft: Bool) -> [NSRect] {
        let cells = _componentCells
        guard !cells.isEmpty else { return [] }
        let inner = frame.insetBy(dx: 4, dy: 0)
        if _pathStyle == .popUp {
            let last = cells[cells.count - 1]
            let w = min(inner.width - NSPathCell.popUpChevronWidth, last.cellSize.width)
            var rects = Array(repeating: NSRect.zero, count: cells.count)
            let x = rightToLeft ? inner.maxX - w : inner.minX
            rects[cells.count - 1] = NSRect(x: x, y: inner.minY, width: max(0, w), height: inner.height)
            return rects
        }
        var widths = cells.map { $0.cellSize.width }
        let chevrons = CGFloat(cells.count - 1) * NSPathCell.chevronWidth
        let total = widths.reduce(0, +) + chevrons
        if total > inner.width, cells.count > 1 {
            let lastW = min(widths[cells.count - 1], inner.width - chevrons - 24 * CGFloat(cells.count - 1))
            widths[cells.count - 1] = max(24, lastW)
            let available = max(0, inner.width - chevrons - widths[cells.count - 1])
            let others = widths.dropLast().reduce(0, +)
            if others > 0 {
                let scale = available / others
                let floor = min(24, available / CGFloat(cells.count - 1))
                for i in 0..<(cells.count - 1) { widths[i] = max(floor, widths[i] * scale) }
                // Flooring may overshoot: scale the rest down to what is left.
                let sum = widths.dropLast().reduce(0, +)
                if sum > available, sum > 0 { for i in 0..<(cells.count - 1) { widths[i] *= available / sum } }
            }
        }
        var rects: [NSRect] = []
        var x = rightToLeft ? inner.maxX : inner.minX
        for w in widths {
            if rightToLeft { x -= w }
            rects.append(NSRect(x: x, y: inner.minY, width: w, height: inner.height))
            if rightToLeft { x -= NSPathCell.chevronWidth } else { x += w + NSPathCell.chevronWidth }
        }
        return rects
    }

    @MainActor open override var cellSize: NSSize {
        let cells = _componentCells
        let h: CGFloat = 22
        if cells.isEmpty {
            let p = _placeholderString ?? _placeholderAttributedString?.string ?? ""
            return NSSize(width: (p.isEmpty ? 60 : p.size(withAttributes: _textAttributes).width + 16), height: h)
        }
        if _pathStyle == .popUp { return NSSize(width: cells[cells.count - 1].cellSize.width + NSPathCell.popUpChevronWidth + 8, height: h) }
        let w = cells.map { $0.cellSize.width }.reduce(0, +) + CGFloat(cells.count - 1) * NSPathCell.chevronWidth + 8
        return NSSize(width: w.rounded(.up), height: h)
    }

    // MARK: Drawing

    @MainActor open override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        _controlView = controlView
        for c in _componentCells { c.controlView = controlView }
        let rtl = controlView.userInterfaceLayoutDirection == .rightToLeft
        let flipped = controlView.isFlipped
        if let bg = _backgroundColor {
            bg.setFill()
            NSBezierPath.fill(cellFrame)
        }
        if _pathStyle == .popUp {
            // The pop-up button's bezel.
            let r = cellFrame.insetBy(dx: 0.5, dy: 0.5)
            (_isEnabled ? NSColor.controlColor : NSColor.controlColor.withAlphaComponent(0.6)).setFill()
            NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5).fill()
            NSColor.separatorColor.withAlphaComponent(0.8).setStroke()
            let border = NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5)
            border.lineWidth = 1
            border.stroke()
            let chevronX = rtl ? cellFrame.minX + NSPathCell.popUpChevronWidth / 2 + 2 : cellFrame.maxX - NSPathCell.popUpChevronWidth / 2 - 2
            _drawDoubleChevron(at: NSPoint(x: chevronX, y: cellFrame.midY), flipped: flipped)
        } else if _isBezeled || _isBordered {
            NSColor.separatorColor.withAlphaComponent(0.7).setStroke()
            NSBezierPath(roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3).stroke()
        }
        let cells = _componentCells
        if cells.isEmpty {
            let p = _placeholderString ?? _placeholderAttributedString?.string ?? ""
            if !p.isEmpty {
                var attrs = _textAttributes
                attrs[.foregroundColor] = NSColor.placeholderTextColor
                _drawText(p, attributes: attrs, in: cellFrame.insetBy(dx: 7, dy: 0), alignment: .natural, flipped: flipped)
            }
            return
        }
        let rects = _componentRects(in: cellFrame, rightToLeft: rtl)
        for (i, cell) in cells.enumerated() {
            let r = rects[i]
            guard !r.isEmpty else { continue }
            if cell === _clickedCell && _pathStyle == .standard {
                NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
                NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill()
            }
            cell.isEnabled = _isEnabled
            cell.drawInterior(withFrame: r, in: controlView)
            if _pathStyle == .standard && i < cells.count - 1 {
                let cx = rtl ? r.minX - NSPathCell.chevronWidth / 2 : r.maxX + NSPathCell.chevronWidth / 2
                _drawChevron(at: NSPoint(x: cx, y: r.midY), rightToLeft: rtl)
            }
        }
    }

    private func _drawChevron(at c: NSPoint, rightToLeft: Bool) {
        let p = NSBezierPath()
        let dx: CGFloat = rightToLeft ? -1 : 1
        p.move(to: NSPoint(x: c.x - dx * 1.5, y: c.y - 3.5))
        p.line(to: NSPoint(x: c.x + dx * 1.5, y: c.y))
        p.line(to: NSPoint(x: c.x - dx * 1.5, y: c.y + 3.5))
        p.lineWidth = 1.2
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        (_isEnabled ? NSColor.tertiaryLabelColor : NSColor.disabledControlTextColor).setStroke()
        p.stroke()
    }

    private func _drawDoubleChevron(at c: NSPoint, flipped: Bool) {
        let w: CGFloat = 3, h: CGFloat = 2.2, gap: CGFloat = 1.6
        let dir: CGFloat = flipped ? 1 : -1
        let up = NSBezierPath(), down = NSBezierPath()
        up.move(to: NSPoint(x: c.x - w, y: c.y - dir * gap)); up.line(to: NSPoint(x: c.x, y: c.y - dir * (gap + h))); up.line(to: NSPoint(x: c.x + w, y: c.y - dir * gap))
        down.move(to: NSPoint(x: c.x - w, y: c.y + dir * gap)); down.line(to: NSPoint(x: c.x, y: c.y + dir * (gap + h))); down.line(to: NSPoint(x: c.x + w, y: c.y + dir * gap))
        (_isEnabled ? NSColor.secondaryLabelColor : NSColor.disabledControlTextColor).setStroke()
        for p in [up, down] { p.lineWidth = 1.5; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke() }
    }

    // MARK: API

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcell/allowedtypes
    @MainActor open var allowedTypes: [String]? {
        get { _allowedTypes }
        set { _allowedTypes = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcell/backgroundcolor
    @MainActor open var backgroundColor: NSColor? {
        get { _backgroundColor }
        set { _backgroundColor = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcell/clickedpathcomponentcell
    @MainActor open var clickedPathComponentCell: NSPathComponentCell? { _clickedCell }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcell/delegate
    @MainActor open var delegate: (any NSPathCellDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcell/doubleaction
    @MainActor open var doubleAction: Selector? {
        get { _doubleAction }
        set { _doubleAction = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcell/mouseentered(with:frame:in:)
    @MainActor open func mouseEntered(with event: NSEvent, frame: NSRect, in view: NSView) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcell/mouseexited(with:frame:in:)
    @MainActor open func mouseExited(with event: NSEvent, frame: NSRect, in view: NSView) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcell/pathcomponentcell(at:withframe:in:)
    @MainActor open func pathComponentCell(at point: NSPoint, withFrame frame: NSRect, in view: NSView) -> NSPathComponentCell? {
        let rects = _componentRects(in: frame, rightToLeft: view.userInterfaceLayoutDirection == .rightToLeft)
        for (i, r) in rects.enumerated() where r.insetBy(dx: -NSPathCell.chevronWidth / 2, dy: 0).contains(point) { return _componentCells[i] }
        return nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcell/pathcomponentcellclass
    @MainActor class public var pathComponentCellClass: AnyClass {
        get { _componentCellClass }
        set { _componentCellClass = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcell/pathcomponentcells
    @MainActor open var pathComponentCells: [NSPathComponentCell] {
        get { _componentCells }
        set {
            _componentCells = newValue
            _cellsAreCustom = true
            for c in _componentCells { c.controlView = _controlView }
            _url = newValue.last?.url
            _clickedCell = nil
            _changed()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcell/pathstyle
    @MainActor open var pathStyle: NSPathControl.Style {
        get { _pathStyle }
        set { _pathStyle = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcell/placeholderattributedstring
    @MainActor open var placeholderAttributedString: NSAttributedString? {
        get { _placeholderAttributedString }
        set { _placeholderAttributedString = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcell/placeholderstring
    @MainActor open var placeholderString: String? {
        get { _placeholderString }
        set { _placeholderString = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcell/rect(of:withframe:in:)
    @MainActor open func rect(of cell: NSPathComponentCell, withFrame frame: NSRect, in view: NSView) -> NSRect {
        guard let i = _componentCells.firstIndex(where: { $0 === cell }) else { return .zero }
        let rects = _componentRects(in: frame, rightToLeft: view.userInterfaceLayoutDirection == .rightToLeft)
        return rects.indices.contains(i) ? rects[i] : .zero
    }
    /// A URL, a path string, or nil.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcell/setobjectvalue(_:)
    @MainActor open func setObjectValue(_ obj: (any NSCopying)?) {
        switch obj {
        case let u as URL: url = u
        case let u as NSURL: url = u as URL
        case let s as String: url = s.isEmpty ? nil : URL(fileURLWithPath: s)
        case let s as NSString: url = s.length == 0 ? nil : URL(fileURLWithPath: s as String)
        default: url = nil
        }
    }
    @MainActor open override var objectValue: Any? {
        get { _url }
        set { setObjectValue(newValue as? (any NSCopying)) }
    }
    @MainActor open override var stringValue: String {
        get { _url?.path ?? "" }
        set { url = newValue.isEmpty ? nil : URL(fileURLWithPath: newValue) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcell/url
    @MainActor open var url: URL? {
        get { _url }
        set {
            _url = newValue
            _cellsAreCustom = false
            _clickedCell = nil
            _rebuildCells()
            _changed()
        }
    }
    // Requirement of NSMenuItemValidation
    open func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { true }
}
