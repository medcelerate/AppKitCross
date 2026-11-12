// NSSearchFieldCell (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// A rounded text field cell with a search button (a magnifying glass, with a menu
// chevron when a `searchMenuTemplate` is set) at the leading edge and a cancel button
// (a cross in a disc, shown while there is text) at the trailing edge. The recent
// searches and the menu built from the template live here too.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfieldcell
@MainActor open class NSSearchFieldCell: NSTextFieldCell {
    // MARK: Storage
    private var _searchButtonCell: NSButtonCell?
    private var _cancelButtonCell: NSButtonCell?
    private var _searchMenuTemplate: NSMenu? = nil
    private var _recentSearches: [String] = []
    private var _maximumRecents = 10
    private var _recentsAutosaveName: NSSearchField.RecentsAutosaveName? = nil
    private var _sendsSearchStringImmediately = false
    private var _sendsWholeSearchString = false
    internal var _centersPlaceholder = true
    /// The button under the pressed mouse (so it draws highlighted).
    internal var _pressedButton: NSButtonCell? = nil
    /// True while the recents menu is open.
    internal var _menuOpen = false

    /// Width of each button's strip.
    static let buttonWidth: CGFloat = 22

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfieldcell/init(textcell:)
    @MainActor public override init(textCell string: String) {
        super.init(textCell: string)
        bezelStyle = .roundedBezel
        placeholderString = "Search"
        _isScrollable = true
        resetSearchButtonCell()
        resetCancelButtonCell()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfieldcell/init(coder:)
    public required init(coder: NSCoder) { super.init(coder: coder) }

    private var _searchField: NSSearchField? { _controlView as? NSSearchField }
    internal var _isRightToLeft: Bool { _controlView?.userInterfaceLayoutDirection == .rightToLeft }

    // MARK: Recents

    private func _loadRecents() {
        guard let name = _recentsAutosaveName else { return }
        if let saved = UserDefaults.standard.array(forKey: "NSSearchField Recents \(name)") as? [String] { _recentSearches = saved }
    }
    private func _saveRecents() {
        guard let name = _recentsAutosaveName else { return }
        UserDefaults.standard.set(_recentSearches, forKey: "NSSearchField Recents \(name)")
    }

    /// Records a completed search at the head of the recents (most recent first).
    @MainActor internal func _addRecentSearch(_ string: String) {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        _recentSearches.removeAll { $0 == s }
        _recentSearches.insert(s, at: 0)
        if _recentSearches.count > _maximumRecents { _recentSearches.removeLast(_recentSearches.count - _maximumRecents) }
        _saveRecents()
    }

    /// The menu the search button shows: the template with the tagged items expanded
    /// (the recents title and clear items only while there are recents, one item per
    /// recent search in place of the `recentsMenuItemTag` item, the "no recents" item
    /// otherwise). Items of the template keep their own targets and actions.
    @MainActor internal func _buildSearchMenu() -> NSMenu? {
        guard let template = _searchMenuTemplate else { return nil }
        let menu = NSMenu(title: template.title)
        let hasRecents = !_recentSearches.isEmpty
        for item in template.items {
            switch item.tag {
            case NSSearchField.recentsTitleMenuItemTag:
                guard hasRecents else { continue }
                let copy = _copy(item)
                copy.isEnabled = false
                menu.addItem(copy)
            case NSSearchField.recentsMenuItemTag:
                guard hasRecents else { continue }
                for (i, s) in _recentSearches.enumerated() {
                    let format = item.title
                    let title = format.contains("%@") ? format.replacingOccurrences(of: "%@", with: s) : s
                    let m = NSMenuItem(title: title, action: Selector(("_selectRecentSearch:")), keyEquivalent: "")
                    m.target = _searchField
                    m.tag = NSSearchField.recentsMenuItemTag
                    m.representedObject = s
                    m.indentationLevel = item.indentationLevel
                    _ = i
                    menu.addItem(m)
                }
            case NSSearchField.noRecentsMenuItemTag:
                guard !hasRecents else { continue }
                let copy = _copy(item)
                copy.isEnabled = false
                menu.addItem(copy)
            case NSSearchField.clearRecentsMenuItemTag:
                guard hasRecents else { continue }
                let copy = _copy(item)
                copy.target = _searchField
                copy.action = Selector(("_clearRecentSearches:"))
                menu.addItem(copy)
            default:
                menu.addItem(_copy(item))
            }
        }
        return menu
    }

    private func _copy(_ item: NSMenuItem) -> NSMenuItem {
        if item.isSeparatorItem { return NSMenuItem.separator() }
        let m = NSMenuItem(title: item.title, action: item.action, keyEquivalent: item.keyEquivalent)
        m.target = item.target
        m.tag = item.tag
        m.state = item.state
        m.isEnabled = item.isEnabled
        m.representedObject = item.representedObject
        m.image = item.image
        m.submenu = item.submenu
        m.indentationLevel = item.indentationLevel
        return m
    }

    // MARK: Geometry

    /// Text keeps clear of both button strips.
    @MainActor internal override func _textRect(forBounds rect: NSRect) -> NSRect {
        searchTextRect(forBounds: rect)
    }

    @MainActor open override var cellSize: NSSize {
        var s = super.cellSize
        s.width += 2 * NSSearchFieldCell.buttonWidth
        s.height = max(s.height, 22)
        return s
    }

    /// The search text's rect when the placeholder is centred (nothing typed, not editing).
    @MainActor internal func _centeredTextRect(forBounds rect: NSRect) -> NSRect {
        let r = super._textRect(forBounds: rect)
        return r.insetBy(dx: NSSearchFieldCell.buttonWidth, dy: 0)
    }

    @MainActor open override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.draw(withFrame: cellFrame, in: controlView)
        _drawSearchButton(in: searchButtonRect(forBounds: cellFrame), flipped: controlView.isFlipped)
        if !stringValue.isEmpty || _editorHasText {
            _drawCancelButton(in: cancelButtonRect(forBounds: cellFrame))
        }
    }

    private var _editorHasText: Bool { !((_searchField?.currentEditor as? NSTextView)?.string.isEmpty ?? true) }

    /// Draws the placeholder centred when nothing is typed and the field is not editing.
    @MainActor open override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        if _hidesText { return }
        if stringValue.isEmpty, _centersPlaceholder, let p = placeholderString, !p.isEmpty {
            var attrs = _attributes
            attrs[.foregroundColor] = NSColor.placeholderTextColor
            _drawText(p, attributes: attrs, in: _centeredTextRect(forBounds: cellFrame), alignment: .center, flipped: controlView.isFlipped)
            return
        }
        super.drawInterior(withFrame: cellFrame, in: controlView)
    }

    private var _glyphColor: NSColor { _isEnabled ? .secondaryLabelColor : .disabledControlTextColor }

    private func _drawSearchButton(in rect: NSRect, flipped: Bool) {
        guard !rect.isEmpty else { return }
        let hasMenu = _searchMenuTemplate != nil
        let pressed = _pressedButton === _searchButtonCell || _menuOpen
        if pressed {
            NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 3), xRadius: 3, yRadius: 3).fill()
        }
        // Magnifying glass: a ring with a handle to the lower trailing side.
        let c = NSPoint(x: rect.midX - (hasMenu ? 3 : 0), y: rect.midY + (flipped ? -1 : 1))
        let r: CGFloat = 4
        let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ring.lineWidth = 1.5
        _glyphColor.setStroke()
        ring.stroke()
        let handle = NSBezierPath()
        let dx: CGFloat = _isRightToLeft ? -1 : 1
        let dy: CGFloat = flipped ? 1 : -1
        handle.move(to: NSPoint(x: c.x + dx * r * 0.72, y: c.y + dy * r * 0.72))
        handle.line(to: NSPoint(x: c.x + dx * (r + 3.5), y: c.y + dy * (r + 3.5)))
        handle.lineWidth = 1.8
        handle.lineCapStyle = .round
        handle.stroke()
        if hasMenu {
            let cx = c.x + r + 5, cy = rect.midY
            let chevron = NSBezierPath()
            chevron.move(to: NSPoint(x: cx - 2.5, y: cy + dy * -1.2))
            chevron.line(to: NSPoint(x: cx, y: cy + dy * 1.2))
            chevron.line(to: NSPoint(x: cx + 2.5, y: cy + dy * -1.2))
            chevron.lineWidth = 1.2
            chevron.lineCapStyle = .round
            chevron.lineJoinStyle = .round
            chevron.stroke()
        }
    }

    private func _drawCancelButton(in rect: NSRect) {
        guard !rect.isEmpty else { return }
        let pressed = _pressedButton === _cancelButtonCell
        let c = NSPoint(x: rect.midX, y: rect.midY)
        let r: CGFloat = 6.5
        (pressed ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).withAlphaComponent(_isEnabled ? 1 : 0.5).setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
        let cross = NSBezierPath()
        let a: CGFloat = 2.6
        cross.move(to: NSPoint(x: c.x - a, y: c.y - a)); cross.line(to: NSPoint(x: c.x + a, y: c.y + a))
        cross.move(to: NSPoint(x: c.x - a, y: c.y + a)); cross.line(to: NSPoint(x: c.x + a, y: c.y - a))
        cross.lineWidth = 1.5
        cross.lineCapStyle = .round
        NSColor.textBackgroundColor.setStroke()
        cross.stroke()
    }

    /// Which button, if any, is under a point of the cell frame.
    @MainActor internal func _button(at point: NSPoint, in cellFrame: NSRect) -> NSButtonCell? {
        if searchButtonRect(forBounds: cellFrame).contains(point) { return _searchButtonCell }
        if (!stringValue.isEmpty || _editorHasText), cancelButtonRect(forBounds: cellFrame).contains(point) { return _cancelButtonCell }
        return nil
    }

    // MARK: API

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfieldcell/cancelbuttoncell
    @MainActor open var cancelButtonCell: NSButtonCell? {
        get { _cancelButtonCell }
        set { _cancelButtonCell = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfieldcell/cancelbuttonrect(forbounds:)
    @MainActor open func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
        let w = min(rect.width, NSSearchFieldCell.buttonWidth)
        let x = _isRightToLeft ? rect.minX : rect.maxX - w
        return NSRect(x: x, y: rect.minY, width: w, height: rect.height)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfieldcell/maximumrecents
    @MainActor open var maximumRecents: Int {
        get { _maximumRecents }
        set {
            _maximumRecents = max(0, newValue)
            if _recentSearches.count > _maximumRecents { _recentSearches.removeLast(_recentSearches.count - _maximumRecents); _saveRecents() }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfieldcell/recentsearches
    @MainActor open var recentSearches: [String]! {
        get { _recentSearches }
        set { _recentSearches = Array((newValue ?? []).prefix(_maximumRecents)); _saveRecents() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfieldcell/recentsautosavename
    @MainActor open var recentsAutosaveName: NSSearchField.RecentsAutosaveName? {
        get { _recentsAutosaveName }
        set { _recentsAutosaveName = newValue; _loadRecents() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfieldcell/resetcancelbuttoncell()
    @MainActor open func resetCancelButtonCell() {
        let b = NSButtonCell(imageCell: nil)
        b.isBordered = false
        b.title = ""
        b.setButtonType(.momentaryChange)
        b.action = Selector(("_cancelButtonClicked:"))
        _cancelButtonCell = b
        _changed()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfieldcell/resetsearchbuttoncell()
    @MainActor open func resetSearchButtonCell() {
        let b = NSButtonCell(imageCell: nil)
        b.isBordered = false
        b.title = ""
        b.setButtonType(.momentaryChange)
        b.action = Selector(("_searchButtonClicked:"))
        _searchButtonCell = b
        _changed()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfieldcell/searchbuttoncell
    @MainActor open var searchButtonCell: NSButtonCell? {
        get { _searchButtonCell }
        set { _searchButtonCell = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfieldcell/searchbuttonrect(forbounds:)
    @MainActor open func searchButtonRect(forBounds rect: NSRect) -> NSRect {
        let w = min(rect.width, NSSearchFieldCell.buttonWidth + (_searchMenuTemplate != nil ? 8 : 0))
        let x = _isRightToLeft ? rect.maxX - w : rect.minX
        return NSRect(x: x, y: rect.minY, width: w, height: rect.height)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfieldcell/searchmenutemplate
    @MainActor open var searchMenuTemplate: NSMenu? {
        get { _searchMenuTemplate }
        set { _searchMenuTemplate = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfieldcell/searchtextrect(forbounds:)
    @MainActor open func searchTextRect(forBounds rect: NSRect) -> NSRect {
        var r = super._textRect(forBounds: rect)
        let search = searchButtonRect(forBounds: rect), cancel = cancelButtonRect(forBounds: rect)
        let leading = _isRightToLeft ? cancel.width : search.width
        let trailing = _isRightToLeft ? search.width : cancel.width
        r.origin.x += leading - 2
        r.size.width = max(0, r.width - leading - trailing + 4)
        return r
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfieldcell/sendssearchstringimmediately
    @MainActor open var sendsSearchStringImmediately: Bool {
        get { _sendsSearchStringImmediately }
        set { _sendsSearchStringImmediately = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfieldcell/sendswholesearchstring
    @MainActor open var sendsWholeSearchString: Bool {
        get { _sendsWholeSearchString }
        set { _sendsWholeSearchString = newValue }
    }
}
