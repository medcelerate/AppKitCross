// NSTextStorage (hand-written; seeded from the generated stub, see tools/apigen)
// A mutable attributed string that batches edits and tells its layout managers about
// them. The storage lives in a private NSMutableAttributedString; every primitive and
// every reader is routed there so the class works both over Apple's class cluster and
// over corelibs Foundation.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage
open class NSTextStorage: NSMutableAttributedString {
    private let _backing: NSMutableAttributedString
    private var _layoutManagers: [NSLayoutManager] = []
    private var _editedMask: NSTextStorageEditActions = []
    private var _editedRange = NSRange(location: NSNotFound, length: 0)
    private var _changeInLength = 0
    private var _editingDepth = 0
    private var _fixesAttributesLazily = true
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/delegate
    open weak var delegate: (any NSTextStorageDelegate)?
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/textstorageobserver
    open weak var textStorageObserver: (any NSTextStorageObserving)?

    // Apple's NSMutableAttributedString is a class cluster: only init() reaches a subclass.
    // corelibs has no init(); its designated initializer sets an (unused) internal store up.
    #if canImport(Darwin)
    public override init() {
        _backing = NSMutableAttributedString(string: "")
        super.init()
    }
    #else
    public init() {
        _backing = NSMutableAttributedString(string: "")
        super.init(string: "")
    }
    #endif

    public override convenience init(string str: String) {
        self.init()
        _backing.replaceCharacters(in: NSRange(location: 0, length: 0), with: str)
    }

    public override convenience init(string str: String, attributes attrs: [NSAttributedString.Key: Any]? = nil) {
        self.init()
        _backing.replaceCharacters(in: NSRange(location: 0, length: 0), with: NSAttributedString(string: str, attributes: attrs))
    }

    public override convenience init(attributedString attrStr: NSAttributedString) {
        self.init()
        _backing.replaceCharacters(in: NSRange(location: 0, length: 0), with: attrStr)
    }

    public required init?(coder: NSCoder) {
        _backing = NSMutableAttributedString(string: "")
        super.init(coder: coder)
    }

    // MARK: Primitives and readers (all through the backing store)

    open override var string: String { _backing.string }
    open override var length: Int { _backing.length }
    open override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        _backing.attributes(at: location, effectiveRange: range)
    }
    open override func attribute(_ attrName: NSAttributedString.Key, at location: Int, effectiveRange range: NSRangePointer?) -> Any? {
        _backing.attribute(attrName, at: location, effectiveRange: range)
    }
    open override func attributes(at location: Int, longestEffectiveRange range: NSRangePointer?, in rangeLimit: NSRange) -> [NSAttributedString.Key: Any] {
        _backing.attributes(at: location, longestEffectiveRange: range, in: rangeLimit)
    }
    open override func attribute(_ attrName: NSAttributedString.Key, at location: Int, longestEffectiveRange range: NSRangePointer?, in rangeLimit: NSRange) -> Any? {
        _backing.attribute(attrName, at: location, longestEffectiveRange: range, in: rangeLimit)
    }
    open override func attributedSubstring(from range: NSRange) -> NSAttributedString { _backing.attributedSubstring(from: range) }
    open override func enumerateAttributes(in enumerationRange: NSRange, options opts: NSAttributedString.EnumerationOptions = [], using block: ([NSAttributedString.Key: Any], NSRange, UnsafeMutablePointer<ObjCBool>) -> Void) {
        _backing.enumerateAttributes(in: enumerationRange, options: opts, using: block)
    }
    open override func enumerateAttribute(_ attrName: NSAttributedString.Key, in enumerationRange: NSRange, options opts: NSAttributedString.EnumerationOptions = [], using block: (Any?, NSRange, UnsafeMutablePointer<ObjCBool>) -> Void) {
        _backing.enumerateAttribute(attrName, in: enumerationRange, options: opts, using: block)
    }
    open override func isEqual(to other: NSAttributedString) -> Bool { _backing.isEqual(to: other) }
    open override func copy(with zone: NSZone? = nil) -> Any { NSAttributedString(attributedString: _backing) }
    open override func mutableCopy(with zone: NSZone? = nil) -> Any { NSMutableAttributedString(attributedString: _backing) }

    private func _clamp(_ r: NSRange) -> NSRange {
        let n = _backing.length
        let loc = min(max(0, r.location), n)
        return NSRange(location: loc, length: min(max(0, r.length), n - loc))
    }

    open override func replaceCharacters(in range: NSRange, with str: String) {
        let r = _clamp(range)
        _backing.replaceCharacters(in: r, with: str)
        edited(.editedCharacters, range: r, changeInLength: (str as NSString).length - r.length)
    }
    open override func replaceCharacters(in range: NSRange, with attrString: NSAttributedString) {
        let r = _clamp(range)
        _backing.replaceCharacters(in: r, with: attrString)
        edited([.editedCharacters, .editedAttributes], range: r, changeInLength: attrString.length - r.length)
    }
    open override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        let r = _clamp(range)
        _backing.setAttributes(attrs, range: r)
        edited(.editedAttributes, range: r, changeInLength: 0)
    }
    open override func addAttribute(_ name: NSAttributedString.Key, value: Any, range: NSRange) {
        let r = _clamp(range)
        _backing.addAttribute(name, value: value, range: r)
        edited(.editedAttributes, range: r, changeInLength: 0)
    }
    open override func addAttributes(_ attrs: [NSAttributedString.Key: Any] = [:], range: NSRange) {
        let r = _clamp(range)
        _backing.addAttributes(attrs, range: r)
        edited(.editedAttributes, range: r, changeInLength: 0)
    }
    open override func removeAttribute(_ name: NSAttributedString.Key, range: NSRange) {
        let r = _clamp(range)
        _backing.removeAttribute(name, range: r)
        edited(.editedAttributes, range: r, changeInLength: 0)
    }
    open override func insert(_ attrString: NSAttributedString, at loc: Int) {
        replaceCharacters(in: NSRange(location: loc, length: 0), with: attrString)
    }
    open override func append(_ attrString: NSAttributedString) {
        replaceCharacters(in: NSRange(location: _backing.length, length: 0), with: attrString)
    }
    open override func deleteCharacters(in range: NSRange) {
        replaceCharacters(in: range, with: "")
    }
    open override func setAttributedString(_ attrString: NSAttributedString) {
        replaceCharacters(in: NSRange(location: 0, length: _backing.length), with: attrString)
    }

    // MARK: Editing transactions

    open override func beginEditing() { _editingDepth += 1 }

    open override func endEditing() {
        _editingDepth = max(0, _editingDepth - 1)
        if _editingDepth == 0 && _editedMask.rawValue != 0 { processEditing() }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/edited(_:range:changeinlength:)
    open func edited(_ editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        _editedMask.formUnion(editedMask)
        _changeInLength += delta
        let newRange = NSRange(location: editedRange.location, length: editedRange.length + delta)
        if _editedRange.location == NSNotFound {
            _editedRange = newRange
        } else {
            let lo = min(_editedRange.location, newRange.location)
            let hi = max(_editedRange.location + _editedRange.length + (editedMask.contains(.editedCharacters) ? delta : 0), newRange.location + newRange.length)
            _editedRange = NSRange(location: lo, length: max(0, hi - lo))
        }
        if _editingDepth == 0 { processEditing() }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/processediting()
    open func processEditing() {
        let mask = _editedMask
        let range = _editedRange.location == NSNotFound ? NSRange(location: 0, length: 0) : _clamp(_editedRange)
        let delta = _changeInLength
        _editedMask = []
        _editedRange = NSRange(location: NSNotFound, length: 0)
        _changeInLength = 0
        delegate?.textStorage(self, willProcessEditing: mask, range: range, changeInLength: delta)
        NotificationCenter.default.post(name: NSTextStorage.willProcessEditingNotification, object: self)
        // The invalidated range is the edited paragraphs, since line layout depends on them.
        let invalidated = (string as NSString).paragraphRange(for: range)
        if mask.contains(.editedCharacters) { ensureAttributesAreFixed(in: invalidated) }
        for lm in _layoutManagers {
            lm.processEditing(for: self, edited: mask, range: range, changeInLength: delta, invalidatedRange: invalidated)
        }
        textStorageObserver?.processEditing(for: self, edited: mask, range: range, changeInLength: delta, invalidatedRange: invalidated)
        delegate?.textStorage(self, didProcessEditing: mask, range: range, changeInLength: delta)
        NotificationCenter.default.post(name: NSTextStorage.didProcessEditingNotification, object: self)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/editedmask
    open var editedMask: NSTextStorageEditActions { _editedMask }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/editedrange
    open var editedRange: NSRange { _editedRange }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/changeinlength
    open var changeInLength: Int { _changeInLength }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/ensureattributesarefixed(in:)
    open func ensureAttributesAreFixed(in range: NSRange) {}
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/fixesattributeslazily
    open var fixesAttributesLazily: Bool { _fixesAttributesLazily }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/invalidateattributes(in:)
    open func invalidateAttributes(in range: NSRange) {}

    // MARK: Layout managers

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/addlayoutmanager(_:)
    open func addLayoutManager(_ aLayoutManager: NSLayoutManager) {
        guard !_layoutManagers.contains(where: { $0 === aLayoutManager }) else { return }
        _layoutManagers.append(aLayoutManager)
        aLayoutManager._setTextStorage(self)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/removelayoutmanager(_:)
    open func removeLayoutManager(_ aLayoutManager: NSLayoutManager) {
        _layoutManagers.removeAll { $0 === aLayoutManager }
        if aLayoutManager.textStorage === self { aLayoutManager._setTextStorage(nil) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/layoutmanagers
    open var layoutManagers: [NSLayoutManager] { _layoutManagers }

    // MARK: Convenience attributes

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/font
    open var font: NSFont? {
        get { length > 0 ? attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil }
        set {
            let r = NSRange(location: 0, length: length)
            if let f = newValue { addAttribute(.font, value: f, range: r) } else { removeAttribute(.font, range: r) }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/foregroundcolor
    open var foregroundColor: NSColor? {
        get { length > 0 ? attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor : nil }
        set {
            let r = NSRange(location: 0, length: length)
            if let c = newValue { addAttribute(.foregroundColor, value: c, range: r) } else { removeAttribute(.foregroundColor, range: r) }
        }
    }

    private func _pieces(_ ranges: [NSRange]) -> [NSTextStorage] {
        ranges.map { NSTextStorage(attributedString: attributedSubstring(from: $0)) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/attributeruns
    open var attributeRuns: [NSTextStorage] {
        get {
            var ranges: [NSRange] = []
            enumerateAttributes(in: NSRange(location: 0, length: length), options: []) { _, r, _ in ranges.append(r) }
            return _pieces(ranges)
        }
        set { setAttributedString(newValue.reduce(into: NSMutableAttributedString(string: "")) { $0.append($1) }) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/paragraphs
    open var paragraphs: [NSTextStorage] {
        get {
            var ranges: [NSRange] = []
            let s = string as NSString
            var i = 0
            while i < s.length { let r = s.paragraphRange(for: NSRange(location: i, length: 0)); ranges.append(r); i = r.location + max(1, r.length) }
            return _pieces(ranges)
        }
        set { setAttributedString(newValue.reduce(into: NSMutableAttributedString(string: "")) { $0.append($1) }) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/words
    open var words: [NSTextStorage] {
        get {
            var ranges: [NSRange] = []
            let s = string as NSString
            var start: Int? = nil
            for i in 0...s.length {
                let ws = i == s.length || NSCharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(s.character(at: i)) ?? " ")
                if ws { if let st = start { ranges.append(NSRange(location: st, length: i - st)); start = nil } } else if start == nil { start = i }
            }
            return _pieces(ranges)
        }
        set { setAttributedString(newValue.reduce(into: NSMutableAttributedString(string: "")) { $0.append($1) }) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/characters
    open var characters: [NSTextStorage] {
        get { _pieces((0..<length).map { NSRange(location: $0, length: 1) }) }
        set { setAttributedString(newValue.reduce(into: NSMutableAttributedString(string: "")) { $0.append($1) }) }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/didprocesseditingnotification
    static public var didProcessEditingNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSTextStorageDidProcessEditingNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextstorage/willprocesseditingnotification
    static public var willProcessEditingNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSTextStorageWillProcessEditingNotification") }
}
