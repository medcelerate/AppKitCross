// NSTextView undo and the Format-menu actions that reach the text storage (ADR-0038).
//
// Undo: with `allowsUndo`, every change the view approves in `shouldChangeText(in:replacementString:)`
// registers an undo step with the view's undo manager, as AppKit does. A record holds the
// range the change's result occupies and the attributed text it replaced; undoing puts the
// old text back and registers the inverse record (redo). Keystrokes coalesce: while typing
// continues next to the open "Typing" record (inserting at its end, deleting into it or
// just before it) the record grows instead of a new step being registered, so one Undo takes
// back the whole run. `breakUndoCoalescing()`, moving the insertion point away, any other kind
// of change, and undo/redo themselves close the record (`isCoalescingUndo` turns false).
//
// A manager that groups by event (the default) holds the record in the event's group; one
// that does not gets a group of its own for it when none is open.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// One undoable text change: `range` is where its result is now, `original` what it replaced.
final class _NSTextUndoRecord {
    var range: NSRange
    var original: NSAttributedString
    init(range: NSRange, original: NSAttributedString) { self.range = range; self.original = original }
}

extension NSTextView {
    // MARK: Registration

    /// Called by `shouldChangeText(in:replacementString:)` once the change is approved.
    internal func _recordUndo(for range: NSRange, replacementString: String?) {
        guard allowsUndo, !_extras.isReplayingUndo, let storage = textStorage, let manager = undoManager, manager.isUndoRegistrationEnabled else { return }
        let r = _clamped(range)
        let newLength = replacementString.map { ($0 as NSString).length } ?? r.length
        if _extras.isTyping, let open = _extras.typingUndo, r.location <= open.range.location + open.range.length, r.location + r.length >= open.range.location {
            // Coalesce: whatever of `r` lies outside the open record is original text it now
            // swallows; the record then covers the union less what goes plus what comes.
            let rs = open.range.location, re = open.range.location + open.range.length
            let u0 = min(rs, r.location), u1 = max(re, r.location + r.length)
            let combined = NSMutableAttributedString(string: "")
            if u0 < rs { combined.append(storage.attributedSubstring(from: NSRange(location: u0, length: rs - u0))) }
            combined.append(open.original)
            if u1 > re { combined.append(storage.attributedSubstring(from: NSRange(location: re, length: u1 - re))) }
            open.original = combined
            open.range = NSRange(location: u0, length: (u1 - u0) - r.length + newLength)
            return
        }
        breakUndoCoalescing()
        let record = _NSTextUndoRecord(range: NSRange(location: r.location, length: newLength), original: storage.attributedSubstring(from: r))
        _register(record, name: _extras.isTyping ? "Typing" : (_extras.undoActionName ?? ""), on: manager)
        if _extras.isTyping { _extras.typingUndo = record }
    }

    private func _register(_ record: _NSTextUndoRecord, name: String, on manager: UndoManager) {
        // A manager that groups by event opens the event's group itself on registration.
        let openedGroup = manager.groupingLevel == 0 && !manager.groupsByEvent
        if openedGroup { manager.beginUndoGrouping() }
        manager.registerUndo(withTarget: self) { tv in tv._replay(record, name: name) }
        if !name.isEmpty { manager.setActionName(name) }
        if openedGroup { manager.endUndoGrouping() }
    }

    /// Undo (or redo) `record`: puts its original text back and registers the inverse.
    private func _replay(_ record: _NSTextUndoRecord, name: String) {
        breakUndoCoalescing()
        guard let storage = textStorage, let manager = undoManager else { return }
        let range = _clamped(record.range)
        let current = storage.attributedSubstring(from: range)
        _extras.isReplayingUndo = true
        defer { _extras.isReplayingUndo = false }
        guard _replaceAttributed(range, with: record.original, selectAfter: false) else { return }
        let restored = NSRange(location: range.location, length: record.original.length)
        setSelectedRange(restored.length > 0 ? restored : NSRange(location: restored.location, length: 0))
        let inverse = _NSTextUndoRecord(range: restored, original: current)
        manager.registerUndo(withTarget: self) { tv in tv._replay(inverse, name: name) }
        if !name.isEmpty { manager.setActionName(name) }
    }

    /// Runs a typed insertion or a delete key: its change may join the open typing record.
    internal func _asTyping<T>(_ body: () -> T) -> T {
        let saved = _extras.isTyping
        _extras.isTyping = true
        defer { _extras.isTyping = saved }
        return body()
    }

    /// Runs a non-typing change under an undo action name ("Underline", "Paste", …).
    internal func _withUndoName<T>(_ name: String, _ body: () -> T) -> T {
        let saved = _extras.undoActionName
        _extras.undoActionName = name
        defer { _extras.undoActionName = saved }
        return body()
    }

    /// The insertion point left the end of the open typing record: the next keystroke
    /// starts a new undo step.
    internal func _noteSelectionForUndo() {
        guard let open = _extras.typingUndo else { return }
        let sel = selectedRange
        if sel.length != 0 || sel.location != open.range.location + open.range.length { breakUndoCoalescing() }
    }

    // MARK: Format actions

    /// Toggles a character attribute over the selection (or the typing attributes): set to
    /// `value` unless the selection's first character already has it, then removed.
    internal func _toggleCharacterAttribute(_ key: NSAttributedString.Key, _ value: Any, name: String, isSet: (Any?) -> Bool) {
        let r = selectedRange
        let current: Any?
        if r.length > 0, let st = textStorage, r.location < st.length { current = st.attribute(key, at: r.location, effectiveRange: nil) }
        else { current = typingAttributes[key] }
        _withUndoName(name) { _setCharacterAttribute(key, isSet(current) ? nil : value) }
    }

    /// Text highlights (`highlight(_:)`): a rounded fill in the highlight colour behind each
    /// highlighted run, drawn under the glyphs. macOS also tints the highlighted text; the
    /// port draws the text in its own colour.
    internal func _drawTextHighlights() {
        guard let st = textStorage, st.length > 0 else { return }
        let attrs = _extras.textHighlightAttributes
        let tint = (attrs[.foregroundColor] as? NSColor) ?? .controlAccentColor
        let outline = attrs[NSAttributedString.Key("NSTextHighlightOutlineColor")] as? NSColor
        st.enumerateAttribute(NSAttributedString.Key("NSTextHighlightStyle"), in: NSRange(location: 0, length: st.length), options: []) { value, range, _ in
            guard value != nil else { return }
            for r in _rects(forCharacterRange: range) {
                let path = NSBezierPath(roundedRect: r.insetBy(dx: -1, dy: 0), xRadius: 3, yRadius: 3)
                tint.withAlphaComponent(0.2).setFill()
                path.fill()
                if let outline { outline.setStroke(); path.stroke() }
            }
        }
    }
}
