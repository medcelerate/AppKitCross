// NSTextFinder (hand-written; seeded from the generated stub, see tools/apigen)
//
// Find and replace for a client's text (ADR-0030). The finder owns the find bar: it puts a
// `_NSFindBarView` in its `findBarContainer` (an NSScrollView shows it above or below its
// content, per `findBarPosition`) and runs the search itself over the client's string,
// read through `string(at:effectiveRange:endsWithSearchBoundary:)` and `stringLength()`.
// Matches are case-insensitive by default; the bar's options menu switches case and the
// matching type (contains, starts with, full word, ends with). With incremental searching
// the matches are found as the search string is typed and the client is asked to redraw;
// NSTextView, the client the port ships, highlights every match and draws a ring around
// the current one. `incrementalSearchingShouldDimContentView` is stored but nothing is dimmed.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfinder
open class NSTextFinder: NSObject, NSCoding {
    private weak var _client: (any NSTextFinderClient)?
    private weak var _container: (any NSTextFinderBarContainer)?
    private var _incremental = false
    private var _dims = true
    private var _indicatorNeedsUpdate = false
    internal var _searchString = ""
    internal var _replaceString = ""
    internal var _ignoresCase = true
    internal var _matchingType: NSTextFinder.MatchingType = .contains
    private var _matches: [NSRange]?
    /// The match the ring is drawn around.
    internal private(set) var _currentMatch: NSRange?
    private var _bar: AnyObject?          // _NSFindBarView (main actor)
    internal var _showsReplace = false

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfinder/init()
    public override init() { super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfinder/init(coder:)
    public required init(coder: NSCoder) {
        _incremental = coder.decodeBool(forKey: "NSIncrementalSearchingEnabled")
        super.init()
    }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { coder.encode(_incremental, forKey: "NSIncrementalSearchingEnabled") }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfinder/client
    open var client: (any NSTextFinderClient)? {
        get { _client }
        set { _client = newValue; noteClientStringWillChange() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfinder/findbarcontainer
    open var findBarContainer: (any NSTextFinderBarContainer)? {
        get { _container }
        set {
            if let old = _container, old !== newValue, old.findBarView === (_bar as? NSView) { old.isFindBarVisible = false; old.findBarView = nil }
            _container = newValue
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfinder/findindicatorneedsupdate
    open var findIndicatorNeedsUpdate: Bool {
        get { _indicatorNeedsUpdate }
        set { _indicatorNeedsUpdate = newValue; if newValue { _redisplayClient() } }
    }
    /// The matches of the incremental search, in string order.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfinder/incrementalmatchranges
    open var incrementalMatchRanges: [NSValue] {
        guard _incremental, _barVisible else { return [] }
        return _allMatches.map { NSValue(range: $0) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfinder/incrementalsearchingshoulddimcontentview
    open var incrementalSearchingShouldDimContentView: Bool {
        get { _dims }
        set { _dims = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfinder/isincrementalsearchingenabled
    open var isIncrementalSearchingEnabled: Bool {
        get { _incremental }
        set { _incremental = newValue; _redisplayClient() }
    }
    /// The yellow highlight AppKit paints under incremental matches.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfinder/drawincrementalmatchhighlight(in:)
    public class func drawIncrementalMatchHighlight(in rect: NSRect) {
        MainActor.assumeIsolated {
            NSColor(srgbRed: 1, green: 0.93, blue: 0.35, alpha: 0.55).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: 0), xRadius: 3, yRadius: 3).fill()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfinder/cancelfindindicator()
    open func cancelFindIndicator() {
        _currentMatch = nil
        _redisplayClient()
    }
    /// The client's text changed: matches are found again on next use.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfinder/noteclientstringwillchange()
    open func noteClientStringWillChange() {
        _matches = nil
        _currentMatch = nil
        if _barVisible { MainActor.assumeIsolated { (_bar as? _NSFindBarView)?.setNeedsCountUpdate() } }
    }

    // MARK: Actions

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfinder/performaction(_:)
    open func performAction(_ op: NSTextFinder.Action) {
        guard validateAction(op) else { MainActor.assumeIsolated { NSSound.beep() }; return }
        switch op {
        case .showFindInterface: _showBar(replace: _showsReplace && _client?.isEditable == true)
        case .showReplaceInterface: _showBar(replace: true)
        case .hideFindInterface: _hideBar()
        case .hideReplaceInterface: _showsReplace = false; MainActor.assumeIsolated { (_bar as? _NSFindBarView)?.syncFromFinder() }; _container?.findBarViewDidChangeHeight()
        case .nextMatch: _find(forward: true)
        case .previousMatch: _find(forward: false)
        case .setSearchString:
            guard let c = _client else { return }
            let sel = c.selectedRanges.first?.rangeValue ?? NSRange(location: 0, length: 0)
            _searchString = _text(c).substring(with: sel)
            _matches = nil
            MainActor.assumeIsolated { (_bar as? _NSFindBarView)?.syncFromFinder() }
            _redisplayClient()
        case .replace: _replaceCurrent(thenFind: false)
        case .replaceAndFind: _replaceCurrent(thenFind: true)
        case .replaceAll: _replaceAll(inSelection: false)
        case .replaceAllInSelection: _replaceAll(inSelection: true)
        case .selectAll: _selectAll(inSelection: false)
        case .selectAllInSelection: _selectAll(inSelection: true)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfinder/validateaction(_:)
    open func validateAction(_ op: NSTextFinder.Action) -> Bool {
        guard let c = _client else { return false }
        let hasSearch = !_searchString.isEmpty
        let selection = c.selectedRanges.first?.rangeValue ?? NSRange(location: 0, length: 0)
        switch op {
        case .showFindInterface, .hideFindInterface, .hideReplaceInterface: return _container != nil
        case .showReplaceInterface: return _container != nil && c.isEditable
        case .nextMatch, .previousMatch: return hasSearch
        case .setSearchString: return c.isSelectable && selection.length > 0
        case .replace, .replaceAndFind, .replaceAll: return hasSearch && c.isEditable
        case .replaceAllInSelection: return hasSearch && c.isEditable && selection.length > 0
        case .selectAll: return hasSearch && c.isSelectable
        case .selectAllInSelection: return hasSearch && c.isSelectable && selection.length > 0
        }
    }

    // MARK: Searching

    private var _barVisible: Bool { _container?.isFindBarVisible == true && _container?.findBarView === (_bar as? NSView) && _bar != nil }

    /// The client's whole text, read the way AppKit's finder reads it.
    internal func _text(_ c: any NSTextFinderClient) -> NSString {
        let n = c.stringLength()
        let out = NSMutableString(string: "")
        var i = 0
        while i < n {
            var r = NSRange(location: 0, length: 0)
            var boundary = ObjCBool(false)
            let piece = c.string(at: i, effectiveRange: &r, endsWithSearchBoundary: &boundary) as NSString
            guard r.length > 0, NSMaxRange(r) > i else { break }
            out.append(piece.substring(with: NSRange(location: i - r.location, length: min(piece.length, NSMaxRange(r) - r.location) - (i - r.location))))
            i = NSMaxRange(r)
        }
        return out
    }

    /// Every match of the search string with the current options.
    internal var _allMatches: [NSRange] {
        if let m = _matches { return m }
        guard let c = _client, !_searchString.isEmpty else { _matches = []; return [] }
        let m = NSTextFinder._matches(of: _searchString, in: _text(c), ignoringCase: _ignoresCase, matching: _matchingType)
        _matches = m
        return m
    }

    internal static func _matches(of needle: String, in text: NSString, ignoringCase: Bool, matching: NSTextFinder.MatchingType) -> [NSRange] {
        var out: [NSRange] = []
        var options: NSString.CompareOptions = []
        if ignoringCase { options.insert(.caseInsensitive) }
        var from = 0
        func isWordChar(_ i: Int) -> Bool {
            guard i >= 0, i < text.length, let u = UnicodeScalar(text.character(at: i)) else { return false }
            return CharacterSet.alphanumerics.contains(u) || u == "_"
        }
        while from < text.length {
            let r = text.range(of: needle, options: options, range: NSRange(location: from, length: text.length - from))
            guard r.location != NSNotFound, r.length > 0 else { break }
            let startsWord = !isWordChar(r.location - 1), endsWord = !isWordChar(NSMaxRange(r))
            let ok: Bool
            switch matching {
            case .contains: ok = true
            case .startsWith: ok = startsWord
            case .endsWith: ok = endsWord
            case .fullWord: ok = startsWord && endsWord
            }
            if ok { out.append(r) }
            from = r.location + 1
        }
        return out
    }

    private func _find(forward: Bool) {
        guard let c = _client else { return }
        let matches = _allMatches
        guard !matches.isEmpty else { MainActor.assumeIsolated { NSSound.beep(); (_bar as? _NSFindBarView)?.setNeedsCountUpdate() }; return }
        let sel = c.selectedRanges.first?.rangeValue ?? NSRange(location: 0, length: 0)
        let next: NSRange
        if forward {
            next = matches.first { $0.location > sel.location || ($0.location == sel.location && sel.length == 0) && $0 != sel } ?? matches[0]
        } else {
            next = matches.last { NSMaxRange($0) < NSMaxRange(sel) || ($0.location < sel.location) } ?? matches[matches.count - 1]
        }
        _select(next, in: c)
    }

    private func _select(_ r: NSRange, in c: any NSTextFinderClient) {
        c.selectedRanges = [NSValue(range: r)]
        c.scrollRangeToVisible(r)
        _currentMatch = r
        _indicatorNeedsUpdate = false
        MainActor.assumeIsolated { (_bar as? _NSFindBarView)?.setNeedsCountUpdate() }
        _redisplayClient()
    }

    /// Typing in the bar: with incremental searching the selection moves to the first match
    /// at or after where the search began.
    internal func _searchStringChanged(_ s: String, anchor: Int) {
        _searchString = s
        _matches = nil
        _currentMatch = nil
        guard let c = _client else { return }
        if _incremental, let first = _allMatches.first(where: { $0.location >= anchor }) ?? _allMatches.first {
            _select(first, in: c)
        } else {
            _redisplayClient()
        }
    }

    private func _replaceCurrent(thenFind: Bool) {
        guard let c = _client else { return }
        let sel = c.selectedRanges.first?.rangeValue ?? NSRange(location: 0, length: 0)
        if _allMatches.contains(sel), c.shouldReplaceCharacters(inRanges: [NSValue(range: sel)], with: [_replaceString]) {
            c.replaceCharacters(in: sel, with: _replaceString)
            c.didReplaceCharacters()
            noteClientStringWillChange()
            c.selectedRanges = [NSValue(range: NSRange(location: sel.location + (_replaceString as NSString).length, length: 0))]
        }
        if thenFind { _find(forward: true) } else { _redisplayClient() }
    }

    private func _replaceAll(inSelection: Bool) {
        guard let c = _client else { return }
        let sel = c.selectedRanges.first?.rangeValue ?? NSRange(location: 0, length: 0)
        let targets = _allMatches.filter { !inSelection || NSIntersectionRange($0, sel).length == $0.length }
        guard !targets.isEmpty else { MainActor.assumeIsolated { NSSound.beep() }; return }
        let ranges = targets.map { NSValue(range: $0) }
        guard c.shouldReplaceCharacters(inRanges: ranges, with: [String](repeating: _replaceString, count: ranges.count)) else { return }
        for r in targets.reversed() { c.replaceCharacters(in: r, with: _replaceString) }
        c.didReplaceCharacters()
        noteClientStringWillChange()
        MainActor.assumeIsolated { (_bar as? _NSFindBarView)?.showStatus("\(targets.count) replaced") }
        _redisplayClient()
    }

    private func _selectAll(inSelection: Bool) {
        guard let c = _client else { return }
        let sel = c.selectedRanges.first?.rangeValue ?? NSRange(location: 0, length: 0)
        let targets = _allMatches.filter { !inSelection || NSIntersectionRange($0, sel).length == $0.length }
        guard let first = targets.first else { return }
        c.selectedRanges = c.allowsMultipleSelection ? targets.map { NSValue(range: $0) } : [NSValue(range: first)]
        c.scrollRangeToVisible(first)
    }

    // MARK: The bar

    private func _showBar(replace: Bool) {
        guard let container = _container else { return }
        _showsReplace = replace
        MainActor.assumeIsolated {
            let bar = (_bar as? _NSFindBarView) ?? _NSFindBarView(finder: self)
            _bar = bar
            bar.syncFromFinder()
            if container.findBarView !== bar { container.findBarView = bar }
            container.isFindBarVisible = true
            container.findBarViewDidChangeHeight()
            bar.focusSearchField()
        }
        _redisplayClient()
    }

    private func _hideBar() {
        guard let container = _container else { return }
        container.isFindBarVisible = false
        _currentMatch = nil
        _redisplayClient()
        MainActor.assumeIsolated {
            // Typing goes back to the content.
            if let tv = (_client as? _NSTextViewFinderClient)?.textView, let w = tv.window { _ = w.makeFirstResponder(tv) }
        }
    }

    internal func _redisplayClient() {
        MainActor.assumeIsolated {
            if let tv = (_client as? _NSTextViewFinderClient)?.textView { tv.needsDisplay = true }
            else if let v = _container?.contentView() { v.needsDisplay = true }
        }
    }

    /// The match index of the current selection ("3 of 7"), for the bar.
    internal var _status: String {
        guard !_searchString.isEmpty else { return "" }
        let m = _allMatches
        guard !m.isEmpty else { return "Not found" }
        let sel = _client?.selectedRanges.first?.rangeValue
        if let sel, let i = m.firstIndex(of: sel) { return "\(i + 1) of \(m.count)" }
        return m.count == 1 ? "1 match" : "\(m.count) matches"
    }
}

/// NSTextView as a finder client (AppKit's NSTextView adopts the protocol privately).
@MainActor final class _NSTextViewFinderClient: NSObject, NSTextFinderClient {
    weak var textView: NSTextView?
    init(_ tv: NSTextView) { textView = tv }
    nonisolated var string: String { MainActor.assumeIsolated { textView?.string ?? "" } }
    nonisolated var isSelectable: Bool { MainActor.assumeIsolated { textView?.isSelectable ?? false } }
    nonisolated var isEditable: Bool { MainActor.assumeIsolated { textView?.isEditable ?? false } }
    nonisolated var allowsMultipleSelection: Bool { false }
    nonisolated var selectedRanges: [NSValue] {
        get { MainActor.assumeIsolated { textView.map { [NSValue(range: $0.selectedRange)] } ?? [] } }
        set { MainActor.assumeIsolated { if let r = newValue.first?.rangeValue { textView?.setSelectedRange(r) } } }
    }
    nonisolated var firstSelectedRange: NSRange { MainActor.assumeIsolated { textView?.selectedRange ?? NSRange(location: 0, length: 0) } }
    nonisolated var visibleCharacterRanges: [NSValue] { MainActor.assumeIsolated { [NSValue(range: NSRange(location: 0, length: (textView?.string as NSString?)?.length ?? 0))] } }
    nonisolated func scrollRangeToVisible(_ range: NSRange) { MainActor.assumeIsolated { textView?.scrollRangeToVisible(range) } }
    nonisolated func shouldReplaceCharacters(inRanges ranges: [NSValue], with strings: [String]) -> Bool {
        MainActor.assumeIsolated { textView?.shouldChangeText(inRanges: ranges, replacementStrings: strings) ?? false }
    }
    nonisolated func replaceCharacters(in range: NSRange, with string: String) {
        MainActor.assumeIsolated { textView?._finderReplace(range, with: string) }
    }
    nonisolated func didReplaceCharacters() { MainActor.assumeIsolated { textView?.didChangeText() } }
    nonisolated func rects(forCharacterRange range: NSRange) -> [NSValue]? {
        MainActor.assumeIsolated { textView?._rects(forCharacterRange: range).map { NSValue(rect: $0) } }
    }
    nonisolated func contentView(at index: Int, effectiveCharacterRange outRange: NSRangePointer) -> NSView {
        MainActor.assumeIsolated {
            outRange.pointee = NSRange(location: 0, length: (textView?.string as NSString?)?.length ?? 0)
            return textView ?? NSView(frame: .zero)
        }
    }
}

// MARK: - The find bar

/// The bar the finder shows: options menu, search field, match count, previous/next, Done,
/// and a replace row (replace field, Replace, All) when replacing.
@MainActor final class _NSFindBarView: NSView, NSTextFieldDelegate {
    private weak var finder: NSTextFinder?
    let searchField = NSTextField(string: "")
    let replaceField = NSTextField(string: "")
    private let options = NSPopUpButton(frame: .zero, pullsDown: true)
    private let status = NSTextField(labelWithString: "")
    private let previous = NSButton(title: "\u{25C0}", target: nil, action: nil)
    private let next = NSButton(title: "\u{25B6}", target: nil, action: nil)
    private let done = NSButton(title: "Done", target: nil, action: nil)
    private let replaceToggle = NSButton(checkboxWithTitle: "Replace", target: nil, action: nil)
    private let replaceButton = NSButton(title: "Replace", target: nil, action: nil)
    private let replaceAllButton = NSButton(title: "All", target: nil, action: nil)
    private var anchor = 0
    static let rowHeight: CGFloat = 30

    init(finder: NSTextFinder) {
        self.finder = finder
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: _NSFindBarView.rowHeight))
        options.addItem(withTitle: "\u{2315}")        // a pull-down's first item is its title
        for (title, tag) in [("Ignore Case", 1), ("Contains", 10), ("Starts With", 11), ("Full Word", 12), ("Ends With", 13)] {
            options.addItem(withTitle: title)
            options.lastItem?.tag = tag
        }
        searchField.delegate = self
        searchField.placeholderString = "Find"
        replaceField.delegate = self
        replaceField.placeholderString = "Replace"
        status.alignment = .right
        status.textColor = .secondaryLabelColor
        for v in [options, searchField, status, previous, next, replaceToggle, done, replaceField, replaceButton, replaceAllButton] as [NSView] { addSubview(v) }
        bind(options, "_findBarOption:") { [weak self] in self?.optionChosen() }
        bind(searchField, "_findBarSearch:") { [weak self] in self?.finder?.performAction(.nextMatch) }
        bind(previous, "_findBarPrevious:") { [weak self] in self?.finder?.performAction(.previousMatch) }
        bind(next, "_findBarNext:") { [weak self] in self?.finder?.performAction(.nextMatch) }
        bind(done, "_findBarDone:") { [weak self] in self?.finder?.performAction(.hideFindInterface) }
        bind(replaceToggle, "_findBarToggleReplace:") { [weak self] in
            guard let self else { return }
            self.finder?.performAction(self.replaceToggle.state == .on ? .showReplaceInterface : .hideReplaceInterface)
        }
        bind(replaceField, "_findBarReplaceField:") { [weak self] in self?.finder?.performAction(.replaceAndFind) }
        bind(replaceButton, "_findBarReplace:") { [weak self] in self?.finder?.performAction(.replace) }
        bind(replaceAllButton, "_findBarReplaceAll:") { [weak self] in self?.finder?.performAction(.replaceAll) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func bind(_ control: NSControl, _ name: String, _ handler: @escaping () -> Void) {
        let sel = Selector((name))
        control.target = self
        control.action = sel
        setActionHandler(for: sel) { _ in handler() }
    }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: (finder?._showsReplace == true ? 2 : 1) * _NSFindBarView.rowHeight)
    }

    func syncFromFinder() {
        guard let f = finder else { return }
        if searchField.stringValue != f._searchString { searchField.stringValue = f._searchString }
        replaceField.stringValue = f._replaceString
        replaceToggle.state = f._showsReplace ? .on : .off
        replaceField.isHidden = !f._showsReplace
        replaceButton.isHidden = !f._showsReplace
        replaceAllButton.isHidden = !f._showsReplace
        replaceToggle.isEnabled = f.client?.isEditable == true
        options.menu?.item(withTag: 1)?.state = f._ignoresCase ? .on : .off
        for (tag, type) in [(10, NSTextFinder.MatchingType.contains), (11, .startsWith), (12, .fullWord), (13, .endsWith)] {
            options.menu?.item(withTag: tag)?.state = f._matchingType == type ? .on : .off
        }
        setFrameSize(NSSize(width: frame.width, height: intrinsicContentSize.height))
        setNeedsCountUpdate()
        needsLayout = true
        layout()
    }

    func focusSearchField() {
        anchor = finder?.client?.selectedRanges.first?.rangeValue.location ?? 0
        if let w = window { _ = w.makeFirstResponder(searchField) }
        searchField.selectText(nil)
    }

    func setNeedsCountUpdate() { status.stringValue = finder?._status ?? "" }
    func showStatus(_ s: String) { status.stringValue = s }

    private func optionChosen() {
        guard let f = finder, let item = options.selectedItem else { return }
        switch item.tag {
        case 1: f._ignoresCase.toggle()
        case 10: f._matchingType = .contains
        case 11: f._matchingType = .startsWith
        case 12: f._matchingType = .fullWord
        case 13: f._matchingType = .endsWith
        default: break
        }
        f._searchStringChanged(searchField.stringValue, anchor: anchor)
        syncFromFinder()
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = _NSFindBarView.rowHeight
        options.frame = NSRect(x: 6, y: 4, width: 40, height: 22)
        done.frame = NSRect(x: w - 66, y: 3, width: 60, height: 24)
        replaceToggle.frame = NSRect(x: w - 152, y: 5, width: 82, height: 20)
        next.frame = NSRect(x: w - 184, y: 3, width: 28, height: 24)
        previous.frame = NSRect(x: w - 214, y: 3, width: 28, height: 24)
        status.frame = NSRect(x: w - 300, y: 7, width: 82, height: 17)
        searchField.frame = NSRect(x: 50, y: 4, width: max(60, w - 356), height: 22)
        replaceField.frame = NSRect(x: 50, y: h + 4, width: max(60, w - 356), height: 22)
        replaceButton.frame = NSRect(x: w - 300, y: h + 3, width: 80, height: 24)
        replaceAllButton.frame = NSRect(x: w - 214, y: h + 3, width: 58, height: 24)
    }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); layout() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath.fill(bounds)
        NSColor.separatorColor.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1))
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        guard let f = finder else { return }
        if (obj.object as? NSTextField) === replaceField { f._replaceString = replaceField.stringValue; return }
        f._searchStringChanged(searchField.stringValue, anchor: anchor)
        setNeedsCountUpdate()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch NSStringFromSelector(commandSelector) {
        case "cancelOperation:": finder?.performAction(.hideFindInterface); return true
        case "insertNewline:":
            if control === replaceField { finder?._replaceString = replaceField.stringValue; finder?.performAction(.replaceAndFind) }
            else if NSApplication.shared.currentEvent?.modifierFlags.contains(.shift) == true { finder?.performAction(.previousMatch) }
            else { finder?.performAction(.nextMatch) }
            return true
        default: return false
        }
    }
}

/// A find bar container that is a small panel: what `usesFindPanel` text views without a
/// scroll view to hold a bar get.
@MainActor final class _NSFindPanelContainer: NSObject, NSTextFinderBarContainer {
    static let shared = _NSFindPanelContainer()
    private let panel: NSPanel
    private var bar: NSView?
    private override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 60), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Find"
        panel.isReleasedWhenClosed = false
        super.init()
    }
    nonisolated var findBarView: NSView? {
        get { MainActor.assumeIsolated { bar } }
        set {
            MainActor.assumeIsolated {
                bar = newValue
                let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 60))
                if let v = newValue { v.frame = NSRect(x: 0, y: 0, width: 520, height: v.intrinsicContentSize.height); v.autoresizingMask = [.width]; content.addSubview(v) }
                panel.contentView = content
            }
        }
    }
    nonisolated var isFindBarVisible: Bool {
        get { MainActor.assumeIsolated { panel.isVisible } }
        set { MainActor.assumeIsolated { if newValue { panel.makeKeyAndOrderFront(nil) } else { panel.orderOut(nil) } } }
    }
    nonisolated func findBarViewDidChangeHeight() {
        MainActor.assumeIsolated {
            guard let v = bar else { return }
            let h = v.intrinsicContentSize.height
            panel.setContentSize(NSSize(width: 520, height: h))
            v.frame = NSRect(x: 0, y: 0, width: 520, height: h)
        }
    }
}
