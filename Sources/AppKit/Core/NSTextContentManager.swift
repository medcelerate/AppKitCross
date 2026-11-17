// NSTextContentManager (hand-written; seeded from the generated stub, see tools/apigen)
// The abstract TextKit 2 document (ADR-0040): it owns its text layout managers and editing
// transactions; NSTextContentStorage supplies the elements.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager
@available(macOS 12.0, *)
open class NSTextContentManager: NSObject, NSTextElementProvider, NSSecureCoding, NSCoding {
    private var _textLayoutManagers: [NSTextLayoutManager] = []
    private weak var _primaryTextLayoutManager: NSTextLayoutManager?
    private weak var _delegate: (any NSTextContentManagerDelegate)?
    private var _transactionDepth = 0
    private var _automaticallySynchronizesTextLayoutManagers = true
    private var _automaticallySynchronizesToBackingStore = true
    /// Edits recorded while a transaction is open: (old range, new range) in UTF-16 offsets.
    private var _pendingEdits: [(old: NSRange, new: NSRange)] = []
    private var _pendingFullChange = false

    private static let _abstractReason = "NSTextContentManager is abstract; NSTextContentStorage provides the elements"

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/init()
    public override init() { super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/init(coder:)
    public required init?(coder: NSCoder) { super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/encode(with:)
    open func encode(with coder: NSCoder) {}
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/supportssecurecoding
    class public var supportsSecureCoding: Bool { true }

    // MARK: Layout managers

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/textlayoutmanagers
    open var textLayoutManagers: [NSTextLayoutManager] { _textLayoutManagers }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/addtextlayoutmanager(_:)
    open func addTextLayoutManager(_ textLayoutManager: NSTextLayoutManager) {
        guard !_textLayoutManagers.contains(where: { $0 === textLayoutManager }) else { return }
        textLayoutManager.textContentManager?.removeTextLayoutManager(textLayoutManager)
        _textLayoutManagers.append(textLayoutManager)
        if _primaryTextLayoutManager == nil { _primaryTextLayoutManager = textLayoutManager }
        textLayoutManager._setTextContentManager(self)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/removetextlayoutmanager(_:)
    open func removeTextLayoutManager(_ textLayoutManager: NSTextLayoutManager) {
        _textLayoutManagers.removeAll { $0 === textLayoutManager }
        if _primaryTextLayoutManager === textLayoutManager { _primaryTextLayoutManager = _textLayoutManagers.first }
        if textLayoutManager.textContentManager === self { textLayoutManager._setTextContentManager(nil) }
    }
    /// The layout manager whose selections edits act on; one of `textLayoutManagers`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/primarytextlayoutmanager
    open var primaryTextLayoutManager: NSTextLayoutManager? {
        get { _primaryTextLayoutManager }
        set {
            guard let m = newValue else { _primaryTextLayoutManager = nil; return }
            if _textLayoutManagers.contains(where: { $0 === m }) { _primaryTextLayoutManager = m }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/delegate
    open var delegate: (any NSTextContentManagerDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/automaticallysynchronizestextlayoutmanagers
    open var automaticallySynchronizesTextLayoutManagers: Bool {
        get { _automaticallySynchronizesTextLayoutManagers }
        set { _automaticallySynchronizesTextLayoutManagers = newValue; if newValue, !hasEditingTransaction { _flushEdits() } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/automaticallysynchronizestobackingstore
    open var automaticallySynchronizesToBackingStore: Bool {
        get { _automaticallySynchronizesToBackingStore }
        set { _automaticallySynchronizesToBackingStore = newValue }
    }

    // MARK: Editing

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/haseditingtransaction
    open var hasEditingTransaction: Bool { _transactionDepth > 0 }
    /// Runs `transaction`; the layout managers catch up when the outermost one ends.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/performeditingtransaction(_:)
    open func performEditingTransaction(_ transaction: () -> Void) {
        _transactionDepth += 1
        transaction()
        _transactionDepth -= 1
        if _transactionDepth == 0, _automaticallySynchronizesTextLayoutManagers { _flushEdits() }
    }
    /// Tells the layout managers that `originalTextRange` became `newTextRange`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/recordeditaction(in:newtextrange:)
    open func recordEditAction(in originalTextRange: NSTextRange, newTextRange: NSTextRange) {
        if let old = originalTextRange._nsRange, let new = newTextRange._nsRange { _noteEdit(old: old, new: new) }
        else { _noteFullChange() }
    }
    /// Layout managers are told about edits synchronously.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/synchronizetextlayoutmanagers(_:)
    open func synchronizeTextLayoutManagers() async throws { _flushEdits() }

    /// An edit replaced `old` (offsets before it) with `new` (offsets after it).
    internal func _noteEdit(old: NSRange, new: NSRange) {
        _pendingEdits.append((old, new))
        if !hasEditingTransaction, _automaticallySynchronizesTextLayoutManagers { _flushEdits() }
    }
    /// The whole document changed (a new backing store).
    internal func _noteFullChange() {
        _pendingFullChange = true
        if !hasEditingTransaction, _automaticallySynchronizesTextLayoutManagers { _flushEdits() }
    }
    private func _flushEdits() {
        let edits = _pendingEdits, full = _pendingFullChange
        _pendingEdits = []
        _pendingFullChange = false
        guard full || !edits.isEmpty else { return }
        for m in _textLayoutManagers { m._contentDidChange(edits: full ? nil : edits) }
    }

    // MARK: Elements

    /// The elements intersecting `range`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/textelements(for:)
    open func textElements(for range: NSTextRange) -> [NSTextElement] {
        var out: [NSTextElement] = []
        _ = enumerateTextElements(from: range.location, options: []) { element in
            guard let r = element.elementRange else { return true }
            if r.location.compare(range.endLocation) != .orderedAscending && !(range.isEmpty && out.isEmpty) { return false }
            out.append(element)
            return true
        }
        return out
    }
    // Requirement of NSTextElementProvider
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/documentrange
    open var documentRange: NSTextRange { unimplemented("NSTextContentManager.documentRange — \(NSTextContentManager._abstractReason)") }
    // Requirement of NSTextElementProvider
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/enumeratetextelements(from:options:using:)
    open func enumerateTextElements(from textLocation: (any NSTextLocation)?, options: NSTextContentManager.EnumerationOptions = [], using block: (NSTextElement) -> Bool) -> (any NSTextLocation)? {
        unimplemented("NSTextContentManager.enumerateTextElements — \(NSTextContentManager._abstractReason)")
    }
    // Requirement of NSTextElementProvider
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/replacecontents(in:with:)
    open func replaceContents(in range: NSTextRange, with textElements: [NSTextElement]?) {
        unimplemented("NSTextContentManager.replaceContents — \(NSTextContentManager._abstractReason)")
    }
    // Requirement of NSTextElementProvider
    /// Edits reach the backing store as they are made; there is nothing to write back.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/synchronizetobackingstore(_:)
    open func synchronizeToBackingStore() async throws {}
}

@available(macOS 12.0, *)
extension NSTextContentManager {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/enumerationoptions
    @available(macOS 12.0, *)
    public struct EnumerationOptions: OptionSet, Sendable, Equatable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/enumerationoptions/reverse
        static public var reverse: NSTextContentManager.EnumerationOptions { NSTextContentManager.EnumerationOptions(rawValue: 1) }
    }
}
