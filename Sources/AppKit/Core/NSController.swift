// NSController (hand-written; seeded from the generated stub, see tools/apigen)
//
// The abstract controller: it keeps the editors that registered with it (bound views that are
// mid-edit) so `commitEditing()` and `discardEditing()` reach them (ADR-0032).

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontroller
open class NSController: NSObject, NSCoding, NSEditor, NSEditorRegistration {
    private var _editors: [any NSEditor] = []

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontroller/init()
    public override init() { super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontroller/init(coder:)
    public required init?(coder: NSCoder) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontroller/commitediting()
    @MainActor open func commitEditing() -> Bool {
        for e in _editors where !e.commitEditing() { return false }
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontroller/commitediting(withdelegate:didcommit:contextinfo:)
    @MainActor open func commitEditing(withDelegate delegate: Any?, didCommit didCommitSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        let committed = commitEditing()
        // The callback is `editor:didCommit:contextInfo:`, a three-argument message that
        // target/action dispatch (one sender argument) cannot deliver without the runtime.
        if delegate != nil, didCommitSelector != nil { _ = committed; unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontroller/discardediting()
    @MainActor open func discardEditing() {
        for e in _editors { e.discardEditing() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontroller/isediting
    open var isEditing: Bool { !_editors.isEmpty }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontroller/objectdidbeginediting(_:)
    @MainActor open func objectDidBeginEditing(_ editor: any NSEditor) {
        guard !_editors.contains(where: { $0 === editor }) else { return }
        _editors.append(editor)
        _KVO.didChange(self, key: "editing")
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontroller/objectdidendediting(_:)
    @MainActor open func objectDidEndEditing(_ editor: any NSEditor) {
        let before = _editors.count
        _editors.removeAll { $0 === editor }
        if _editors.count != before { _KVO.didChange(self, key: "editing") }
    }
    // Requirement of NSCoding
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nscoding/encode(with:)
    open func encode(with coder: NSCoder) { unimplemented() }

    /// Runs a controller action the way AppKit does: after pending edits commit, on the next
    /// pass of the main run loop.
    internal func _performDeferred(_ body: @escaping () -> Void) {
        DispatchQueue.main.async { [self] in
            guard MainActor.assumeIsolated({ commitEditing() }) else { return }
            body()
        }
    }
}
