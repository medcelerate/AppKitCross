// NSSearchField (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// A text field whose action is the search: sent as the user types (at once with
// `sendsSearchStringImmediately`, else after a short pause) unless `sendsWholeSearchString`
// restricts it to Return. Escape and the cancel button clear the text and send the (now
// empty) search; Return records the string among the recent searches, which the search
// button's menu lists when a `searchMenuTemplate` is set.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfield
@MainActor open class NSSearchField: NSTextField {
    internal var _searchCell: NSSearchFieldCell? { _cell as? NSSearchFieldCell }
    private var _searchTimer: Timer? = nil
    private var _isSearching = false
    private var _trackedButton: NSButtonCell? = nil

    /// The pause after the last keystroke before the search string is sent.
    internal static let searchDelay: TimeInterval = 0.3

    @MainActor open override class func _makeDefaultCell() -> NSCell? { NSSearchFieldCell(textCell: "") }

    @MainActor public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setActionHandler(for: Selector(("_selectRecentSearch:"))) { [weak self] sender in
            guard let self, let s = (sender as? NSMenuItem)?.representedObject as? String else { return }
            self._applyingSearchString = true
            self._applySearchString(s, endEditing: false)
            self._applyingSearchString = false
            self._searchCell?._addRecentSearch(s)
            self._fireSearch()
        }
        setActionHandler(for: Selector(("_clearRecentSearches:"))) { [weak self] _ in
            self?.recentSearches = []
        }
    }
    public required init?(coder: NSCoder) { super.init(coder: coder) }

    private var _searchDelegate: (any NSSearchFieldDelegate)? { delegate as? NSSearchFieldDelegate }
    private var _editor: NSTextView? { _fieldEditor }

    // MARK: Searching

    /// Sends the action with the current string and keeps the delegate informed of a
    /// search starting (first non-empty string) or ending (string cleared).
    @MainActor internal func _fireSearch() {
        _searchTimer?.invalidate()
        _searchTimer = nil
        let empty = stringValue.isEmpty
        if !empty && !_isSearching { _isSearching = true; _searchDelegate?.searchFieldDidStartSearching(self) }
        _fireAction()
        if empty && _isSearching { _isSearching = false; _searchDelegate?.searchFieldDidEndSearching(self) }
    }

    private func _scheduleSearch() {
        _searchTimer?.invalidate()
        let t = Timer(timeInterval: NSSearchField.searchDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?._fireSearch() }
        }
        RunLoop.main.add(t, forMode: .default)
        _searchTimer = t
    }

    /// Replaces the text (in the editor while editing) without ending the session.
    private func _applySearchString(_ s: String, endEditing: Bool) {
        if let e = _editor {
            e.string = s
            e.didChangeText()
            if !endEditing { e.selectedRange = NSRange(location: (s as NSString).length, length: 0) }
        } else {
            stringValue = s
        }
        needsDisplay = true
    }

    /// Clears the text and sends the empty search (the cancel button and Escape).
    @MainActor internal func _cancelSearch() {
        _applyingSearchString = true
        _applySearchString("", endEditing: false)
        _applyingSearchString = false
        _fireSearch()
    }
    /// True while the field itself replaces the text: the change is not a keystroke.
    private var _applyingSearchString = false

    @MainActor open override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        guard let e = _editor, (notification.object as? NSTextView) === e else { return }
        needsDisplay = true           // the cancel button comes and goes with the text
        guard !sendsWholeSearchString, !_applyingSearchString else { return }
        if sendsSearchStringImmediately { _fireSearch() } else { _scheduleSearch() }
    }

    /// Return commits the search string (the superclass sends the action) and records it
    /// among the recents; a pending delayed search is dropped.
    @MainActor open override func textDidEndEditing(_ notification: Notification) {
        if let e = _editor, (notification.object as? NSTextView) === e {
            let raw = notification.userInfo?["NSTextMovement"] as? Int ?? NSTextMovement.other.rawValue
            if raw == NSTextMovement.return.rawValue {
                _searchTimer?.invalidate(); _searchTimer = nil
                _searchCell?._addRecentSearch(e.string)
                if !e.string.isEmpty && !_isSearching { _isSearching = true; _searchDelegate?.searchFieldDidStartSearching(self) }
            }
        }
        super.textDidEndEditing(notification)
    }

    /// Escape with text clears it (and searches for nothing); with no text it ends editing.
    @MainActor internal override func _editorDoCommand(by selector: Selector) -> Bool {
        if super._editorDoCommand(by: selector) { return true }
        if selector == Selector(("cancelOperation:")), let e = _editor, !e.string.isEmpty {
            _cancelSearch()
            return true
        }
        return false
    }

    // MARK: Buttons

    @MainActor open override func mouseDown(with event: NSEvent) {
        guard isEnabled, let cell = _searchCell else { super.mouseDown(with: event); return }
        let p = convert(event.locationInWindow, from: nil)
        if let b = cell._button(at: p, in: _cellFrame) {
            _trackedButton = b
            cell._pressedButton = b
            needsDisplay = true
            return
        }
        super.mouseDown(with: event)
    }

    @MainActor open override func mouseDragged(with event: NSEvent) {
        guard let cell = _searchCell, let tracked = _trackedButton else { super.mouseDragged(with: event); return }
        let p = convert(event.locationInWindow, from: nil)
        let over = cell._button(at: p, in: _cellFrame) === tracked ? tracked : nil
        if cell._pressedButton !== over { cell._pressedButton = over; needsDisplay = true }
    }

    @MainActor open override func mouseUp(with event: NSEvent) {
        guard let cell = _searchCell, let tracked = _trackedButton else { super.mouseUp(with: event); return }
        _trackedButton = nil
        cell._pressedButton = nil
        needsDisplay = true
        let p = convert(event.locationInWindow, from: nil)
        guard cell._button(at: p, in: _cellFrame) === tracked else { return }
        if tracked === cell.cancelButtonCell { _cancelButtonClicked() }
        else if tracked === cell.searchButtonCell { _searchButtonClicked() }
    }

    @MainActor internal func _cancelButtonClicked() {
        _cancelSearch()
        if _editor == nil { _ = window?.makeFirstResponder(self) }
    }

    /// The search button opens the recents menu when there is a template; otherwise it
    /// just starts editing.
    @MainActor internal func _searchButtonClicked() {
        guard let cell = _searchCell else { return }
        if let menu = cell._buildSearchMenu(), let w = window {
            let anchor = w.convertToScreen(convert(cell.searchButtonRect(forBounds: _cellFrame), to: nil))
            cell._menuOpen = true
            needsDisplay = true
            _ = _NSMenuTracker.begin(menu: menu, anchor: anchor, placement: .besideAnchor(edge: .maxY), openedWithMouseDown: false) { [weak self] _ in
                self?._searchCell?._menuOpen = false
                self?.needsDisplay = true
            }
            return
        }
        if _editor == nil { _ = window?.makeFirstResponder(self) }
    }

    @MainActor open override func resetCursorRects() {
        guard isEnabled, let cell = _searchCell else { return }
        addCursorRect(cell.searchTextRect(forBounds: _cellFrame), cursor: .iBeam)
    }

    // MARK: API

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfield/cancelbuttonbounds
    @available(macOS 11.0, *)
    @MainActor open var cancelButtonBounds: NSRect { _searchCell?.cancelButtonRect(forBounds: _cellFrame) ?? .zero }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfield/centersplaceholder
    @available(macOS 10.11, *)
    @MainActor open var centersPlaceholder: Bool {
        get { _searchCell?._centersPlaceholder ?? true }
        set { _searchCell?._centersPlaceholder = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfield/clearrecentsmenuitemtag
    static public var clearRecentsMenuItemTag: Int { 1003 }
    // SKIPPED (override type (any NSSearchFieldDelegate)? differs from superclass (any NSTextFieldDelegate)?): @MainActor var delegate: (any NSSearchFieldDelegate)? { get set }
    // NSSearchFieldDelegate refines NSTextFieldDelegate, so a search field delegate is assigned to `delegate` as is.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfield/maximumrecents
    @available(macOS 10.10, *)
    @MainActor open var maximumRecents: Int {
        get { _searchCell?.maximumRecents ?? 10 }
        set { _searchCell?.maximumRecents = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfield/norecentsmenuitemtag
    static public var noRecentsMenuItemTag: Int { 1002 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfield/recentsearches
    @MainActor open var recentSearches: [String] {
        get { _searchCell?.recentSearches ?? [] }
        set { _searchCell?.recentSearches = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfield/recentsautosavename
    @MainActor open var recentsAutosaveName: NSSearchField.RecentsAutosaveName? {
        get { _searchCell?.recentsAutosaveName }
        set { _searchCell?.recentsAutosaveName = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfield/recentsmenuitemtag
    static public var recentsMenuItemTag: Int { 1001 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfield/recentstitlemenuitemtag
    static public var recentsTitleMenuItemTag: Int { 1000 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfield/rectforcancelbutton(whencentered:)
    @available(macOS 10.11, *)
    @MainActor open func rectForCancelButton(whenCentered isCentered: Bool) -> NSRect { cancelButtonBounds }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfield/rectforsearchbutton(whencentered:)
    @available(macOS 10.11, *)
    @MainActor open func rectForSearchButton(whenCentered isCentered: Bool) -> NSRect {
        guard let cell = _searchCell else { return .zero }
        if isCentered {
            // The glass sits just before the centred placeholder.
            let text = cell._centeredTextRect(forBounds: _cellFrame)
            let p = placeholderString ?? ""
            let w = p.size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)]).width
            let r = cell.searchButtonRect(forBounds: _cellFrame)
            return NSRect(x: text.midX - w / 2 - r.width, y: r.minY, width: r.width, height: r.height)
        }
        return cell.searchButtonRect(forBounds: _cellFrame)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfield/rectforsearchtext(whencentered:)
    @available(macOS 10.11, *)
    @MainActor open func rectForSearchText(whenCentered isCentered: Bool) -> NSRect {
        guard let cell = _searchCell else { return .zero }
        return isCentered ? cell._centeredTextRect(forBounds: _cellFrame) : cell.searchTextRect(forBounds: _cellFrame)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfield/searchbuttonbounds
    @available(macOS 11.0, *)
    @MainActor open var searchButtonBounds: NSRect { _searchCell?.searchButtonRect(forBounds: _cellFrame) ?? .zero }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfield/searchmenutemplate
    @available(macOS 10.10, *)
    @MainActor open var searchMenuTemplate: NSMenu? {
        get { _searchCell?.searchMenuTemplate }
        set { _searchCell?.searchMenuTemplate = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfield/searchtextbounds
    @available(macOS 11.0, *)
    @MainActor open var searchTextBounds: NSRect { _searchCell?.searchTextRect(forBounds: _cellFrame) ?? .zero }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfield/sendssearchstringimmediately
    @available(macOS 10.10, *)
    @MainActor open var sendsSearchStringImmediately: Bool {
        get { _searchCell?.sendsSearchStringImmediately ?? false }
        set { _searchCell?.sendsSearchStringImmediately = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssearchfield/sendswholesearchstring
    @available(macOS 10.10, *)
    @MainActor open var sendsWholeSearchString: Bool {
        get { _searchCell?.sendsWholeSearchString ?? false }
        set { _searchCell?.sendsWholeSearchString = newValue }
    }
    // MARK: Accessibility (ADR-0013)
    //
    // An AXTextField with the AXSearchField subrole; cancel clears the search.
    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .textField }
    open override func accessibilitySubrole() -> NSAccessibility.Subrole? { _a11y.subrole ?? .searchField }
    open override func accessibilityPerformCancel() -> Bool {
        guard isEnabled, !stringValue.isEmpty else { return false }
        _cancelSearch()
        return true
    }
}
