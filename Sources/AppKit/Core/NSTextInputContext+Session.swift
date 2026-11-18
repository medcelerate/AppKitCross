// The platform-neutral half of input method support (ADR-0045).
//
// Each window backend speaks its platform's input method protocol: the Text Services
// Framework (a text store the input method edits, Windows), IMM32 (composition strings,
// older Windows input methods), text-input-v3 (preedit/commit/delete-surrounding batches
// applied on `done`, Wayland) and XIM (on-the-spot preedit callbacks, X11). All of them end
// up here, where the edit becomes the calls a macOS input method makes on an
// `NSTextInputClient`: `setMarkedText` for the composition (with the clause underlines in
// the attributed string, thin for clauses and thick for the one being converted, as macOS
// draws them), `insertText` to commit, `unmarkText` to end. The logic is plain Swift so the
// host tests drive it with scripted compositions.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// `APPKITWIN_TRACE_TEXTINPUT=1`: one stderr line per input method step (`[textinput] ...`).
enum _TextInputTrace {
    nonisolated(unsafe) static var enabled = ProcessInfo.processInfo.environment["APPKITWIN_TRACE_TEXTINPUT"] == "1"
    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        fputs("[textinput] \(message())\n", stderr)
    }
    /// A string with its control characters escaped, for trace lines.
    static func quote(_ s: String) -> String {
        "\"" + s.unicodeScalars.map { $0.value < 0x20 ? "\\u{\(String($0.value, radix: 16))}" : String($0) }.joined() + "\""
    }
}

/// One clause of a composition, relative to the start of the marked text. `thick` is the
/// clause the input method is converting (macOS draws it with a thick underline).
public struct _TextInputClause: Equatable {
    public var range: NSRange
    public var thick: Bool
    public init(range: NSRange, thick: Bool) { self.range = range; self.thick = thick }
}

/// The input method's view of one text input client. Made for each platform callback from
/// `PlatformTextInput`; it keeps no state of its own beyond the client.
@MainActor
public final class _TextInputSession {
    public let client: any NSTextInputClient
    weak var window: NSWindow?

    init(client: any NSTextInputClient, window: NSWindow?) {
        self.client = client
        self.window = window
    }

    // MARK: Applying the input method's edits

    nonisolated(unsafe) private static var applyingDepth = 0
    /// True while an input method edit is being applied: the client's change notifications
    /// are its own echo and are not sent back to the platform.
    nonisolated static var isApplying: Bool { applyingDepth > 0 }
    nonisolated static func applying<T>(_ body: () throws -> T) rethrows -> T {
        applyingDepth += 1
        defer { applyingDepth -= 1 }
        return try body()
    }

    nonisolated private static let notFound = NSRange(location: NSNotFound, length: 0)

    // MARK: Reading the client

    public var selectedRange: NSRange {
        let r = client.selectedRange()
        return r.location == NSNotFound ? NSRange(location: 0, length: 0) : r
    }
    public var markedRange: NSRange? {
        guard client.hasMarkedText() else { return nil }
        let r = client.markedRange()
        return r.location == NSNotFound ? nil : r
    }

    /// The client's whole text (UTF-16). An `NSText` answers directly; other clients through
    /// `attributedSubstring(forProposedRange:)` over everything they have.
    public func text() -> [UInt16] {
        if let t = client as? NSText { return Array(t.string.utf16) }
        var actual = NSRange(location: 0, length: 0)
        let s = client.attributedSubstring(forProposedRange: NSRange(location: 0, length: Int(Int32.max)), actualRange: &actual)
        return Array((s?.string ?? "").utf16)
    }

    /// A window of the client's text around the selection, as the input method sees it.
    /// Positions inside are relative to `base`.
    public struct Snapshot: Equatable {
        public var base: Int
        public var text: [UInt16]
        public var selection: NSRange
        public var marked: NSRange?
        public init(base: Int, text: [UInt16], selection: NSRange, marked: NSRange?) {
            self.base = base; self.text = text; self.selection = selection; self.marked = marked
        }
    }

    /// The text within `limit` UTF-16 units of the selection (a long document is not handed
    /// whole to the input method on every keystroke).
    public func snapshot(limit: Int = 32_768) -> Snapshot {
        let all = text()
        let sel = clamp(selectedRange, all.count)
        let marked = markedRange.map { clamp($0, all.count) }
        var lower = 0, upper = all.count
        if all.count > limit {
            let anchor = marked?.location ?? sel.location
            lower = max(0, anchor - limit / 2)
            upper = min(all.count, lower + limit)
            lower = max(0, min(lower, upper - limit))
            if lower > 0, UTF16.isTrailSurrogate(all[lower]) { lower -= 1 }
            if upper < all.count, upper > 0, UTF16.isLeadSurrogate(all[upper - 1]) { upper += 1 }
            let keep = NSRange(location: lower, length: upper - lower)
            if let m = marked, m.location < keep.location || NSMaxRange(m) > NSMaxRange(keep) { lower = min(lower, m.location); upper = max(upper, NSMaxRange(m)) }
            if sel.location < lower || NSMaxRange(sel) > upper { lower = min(lower, sel.location); upper = max(upper, NSMaxRange(sel)) }
        }
        func rel(_ r: NSRange) -> NSRange { NSRange(location: r.location - lower, length: r.length) }
        return Snapshot(base: lower, text: Array(all[lower..<upper]), selection: rel(sel), marked: marked.map(rel))
    }

    private func clamp(_ r: NSRange, _ n: Int) -> NSRange {
        let loc = min(max(0, r.location), n)
        return NSRange(location: loc, length: min(max(0, r.length), n - loc))
    }

    // MARK: Composition (marked text)

    /// The attributed marked text macOS input methods send: underline styles per clause.
    /// Without clauses the whole text is thin and the selected part (when not empty) thick.
    nonisolated public static func markedString(_ text: String, selection: NSRange, clauses: [_TextInputClause]) -> NSAttributedString {
        let s = NSMutableAttributedString(string: text)
        let n = text.utf16.count
        guard n > 0 else { return s }
        var list = clauses.filter { $0.range.length > 0 && $0.range.location < n }
        if list.isEmpty {
            list = [_TextInputClause(range: NSRange(location: 0, length: n), thick: false)]
            if selection.length > 0, selection.location < n {
                let sel = NSRange(location: selection.location, length: min(selection.length, n - selection.location))
                list = []
                if sel.location > 0 { list.append(_TextInputClause(range: NSRange(location: 0, length: sel.location), thick: false)) }
                list.append(_TextInputClause(range: sel, thick: true))
                if NSMaxRange(sel) < n { list.append(_TextInputClause(range: NSRange(location: NSMaxRange(sel), length: n - NSMaxRange(sel)), thick: false)) }
            }
        }
        for c in list {
            let r = NSRange(location: c.range.location, length: min(c.range.length, n - c.range.location))
            s.addAttribute(.underlineStyle, value: (c.thick ? NSUnderlineStyle.thick : NSUnderlineStyle.single).rawValue, range: r)
            // macOS marks each clause as its own segment so adjacent clauses draw apart.
            s.addAttribute(.markedClauseSegment, value: list.firstIndex(of: c) ?? 0, range: r)
        }
        return s
    }

    /// Shows `text` as the composition, replacing the current one (or `replacing`). An empty
    /// text removes the composition.
    public func setComposition(_ text: String, selection: NSRange, clauses: [_TextInputClause] = [], replacing: NSRange? = nil) {
        guard !text.isEmpty else { cancelComposition(); return }
        let n = text.utf16.count
        let sel = NSRange(location: min(max(0, selection.location), n), length: max(0, min(selection.length, n - min(max(0, selection.location), n))))
        _TextInputTrace.log("setMarkedText \(_TextInputTrace.quote(text)) selected \(sel.location),\(sel.length) clauses \(clauses.map { "\($0.range.location),\($0.range.length)\($0.thick ? "*" : "")" }.joined(separator: " "))")
        _TextInputSession.applying {
            client.setMarkedText(Self.markedString(text, selection: sel, clauses: clauses), selectedRange: sel, replacementRange: replacing ?? Self.notFound)
        }
    }

    /// Commits `text`: it replaces the composition (or `replacing`) as ordinary text.
    public func commit(_ text: String, replacing: NSRange? = nil) {
        _TextInputTrace.log("insertText \(_TextInputTrace.quote(text))\(replacing.map { " replacing \($0.location),\($0.length)" } ?? "")")
        _TextInputSession.applying {
            client.insertText(text, replacementRange: replacing ?? Self.notFound)
            if client.hasMarkedText() { client.unmarkText() }
        }
    }

    /// Removes the composition without committing it (Escape in the input method).
    public func cancelComposition() {
        guard client.hasMarkedText() else { return }
        _TextInputTrace.log("cancel composition")
        _TextInputSession.applying {
            client.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: Self.notFound)
            if client.hasMarkedText() { client.unmarkText() }
        }
    }

    /// The composition becomes ordinary text as it stands.
    public func finishComposition() {
        guard client.hasMarkedText() else { return }
        _TextInputTrace.log("unmarkText")
        _TextInputSession.applying { client.unmarkText() }
    }

    /// Deletes `before` UTF-16 units before the selection and `after` after it (the
    /// composition is not counted: it is removed first by the caller).
    public func deleteSurrounding(before: Int, after: Int) {
        guard before > 0 || after > 0 else { return }
        let sel = selectedRange
        let all = text().count
        let lower = max(0, sel.location - before)
        let upper = min(all, NSMaxRange(sel) + after)
        _TextInputTrace.log("delete surrounding \(before) before, \(after) after")
        _TextInputSession.applying {
            if before > 0 { client.insertText("", replacementRange: NSRange(location: lower, length: sel.location - lower)) }
            let start = lower + sel.length
            if after > 0 { client.insertText("", replacementRange: NSRange(location: start, length: max(0, upper - NSMaxRange(sel)))) }
        }
    }

    /// Moves the selection when the client is an `NSText` (NSTextInputClient has no setter).
    public func setSelection(_ range: NSRange) {
        guard let t = client as? NSText, t.selectedRange != range else { return }
        _TextInputSession.applying { t.selectedRange = range }
    }

    // MARK: A text store edit (Text Services Framework)

    /// Applies an input method's edit of a text store that started as `old` (the text and
    /// selection the store was given, with the client's marked text inline) and now holds
    /// `newText` with `composition` (relative positions; nil when no composition is active).
    /// The changed span becomes committed text and the composition becomes marked text, so
    /// the client ends up holding exactly `newText`.
    public func applyStoreEdit(from old: Snapshot, newText: [UInt16], selection newSelection: NSRange, composition: NSRange?, clauses: [_TextInputClause]) {
        let oldText = old.text
        var p = 0
        let limit = min(oldText.count, newText.count)
        while p < limit && oldText[p] == newText[p] { p += 1 }
        var s = 0
        while s < limit - p && oldText[oldText.count - 1 - s] == newText[newText.count - 1 - s] { s += 1 }
        if let m = old.marked {
            p = min(p, m.location)
            s = min(s, oldText.count - NSMaxRange(m))
        }
        var comp = composition.map { NSRange(location: min(max(0, $0.location), newText.count), length: max(0, min($0.length, newText.count - min(max(0, $0.location), newText.count)))) }
        if comp?.length == 0 { comp = nil }
        if let c = comp {
            p = min(p, c.location)
            s = min(s, newText.count - NSMaxRange(c))
        }
        p = max(0, p); s = max(0, s)
        let oldSpan = NSRange(location: p, length: max(0, oldText.count - s - p))
        let newEnd = max(p, newText.count - s)
        let b = old.base
        func str(_ lo: Int, _ hi: Int) -> String { lo < hi ? String(decoding: newText[lo..<hi], as: UTF16.self) : "" }

        if let c = comp {
            let pre = str(p, c.location), post = str(NSMaxRange(c), newEnd), marked = str(c.location, NSMaxRange(c))
            let caret = NSRange(location: max(0, newSelection.location - c.location), length: newSelection.length)
            let local = clauses.map { _TextInputClause(range: NSRange(location: $0.range.location - c.location, length: $0.range.length), thick: $0.thick) }
            if pre.isEmpty && post.isEmpty && old.marked == oldSpan {
                // The usual keystroke: only the composition changed.
                setComposition(marked, selection: caret, clauses: local)
            } else if pre.isEmpty && post.isEmpty && oldSpan.length == 0 && old.marked == nil {
                setComposition(marked, selection: caret, clauses: local, replacing: NSRange(location: b + p, length: 0))
            } else {
                // Text was committed around the new composition: commit it, then mark.
                commit(pre + post, replacing: NSRange(location: b + oldSpan.location, length: oldSpan.length))
                setComposition(marked, selection: caret, clauses: local, replacing: NSRange(location: b + c.location, length: 0))
            }
        } else {
            let committed = str(p, newEnd)
            if let m = old.marked, m == oldSpan {
                commit(committed)
            } else if oldSpan.length > 0 || !committed.isEmpty {
                commit(committed, replacing: NSRange(location: b + oldSpan.location, length: oldSpan.length))
            } else if old.marked != nil {
                finishComposition()
            }
            let target = NSRange(location: b + newSelection.location, length: newSelection.length)
            if selectedRange != target { setSelection(target) }
        }
    }

    // MARK: A text-input-v3 batch (Wayland)

    /// The state a `zwp_text_input_v3` collects between `done` events. Lengths and cursor
    /// positions are UTF-8 byte counts, as the protocol sends them.
    public struct TextInputV3State: Equatable {
        public var preedit: String? = nil
        public var cursorBegin: Int32 = -1
        public var cursorEnd: Int32 = -1
        public var commit: String? = nil
        public var deleteBefore: UInt32 = 0
        public var deleteAfter: UInt32 = 0
        public init() {}
    }

    /// Applies one `done` in the order the protocol gives: remove the preedit, delete the
    /// surrounding text, insert the commit string, show the new preedit with its cursor.
    public func apply(_ state: TextInputV3State) {
        let hadMarked = client.hasMarkedText()
        let commitText = state.commit ?? ""
        if state.deleteBefore > 0 || state.deleteAfter > 0 {
            if hadMarked { cancelComposition() }
            let (before, after) = utf16Lengths(beforeBytes: Int(state.deleteBefore), afterBytes: Int(state.deleteAfter))
            deleteSurrounding(before: before, after: after)
            if !commitText.isEmpty { commit(commitText) }
        } else if !commitText.isEmpty {
            commit(commitText)
        } else if hadMarked && (state.preedit ?? "").isEmpty {
            cancelComposition()
        }
        if let preedit = state.preedit, !preedit.isEmpty {
            let selection: NSRange
            if state.cursorBegin < 0 || state.cursorEnd < 0 {
                selection = NSRange(location: preedit.utf16.count, length: 0)
            } else {
                let lo = Self.utf16Offset(ofByte: Int(min(state.cursorBegin, state.cursorEnd)), in: preedit)
                let hi = Self.utf16Offset(ofByte: Int(max(state.cursorBegin, state.cursorEnd)), in: preedit)
                selection = NSRange(location: lo, length: hi - lo)
            }
            // The highlighted range is the clause being converted.
            setComposition(preedit, selection: NSRange(location: selection.location, length: 0),
                           clauses: selection.length > 0 ? Self.clauses(around: selection, in: preedit.utf16.count) : [])
        }
    }

    /// Thin clauses on both sides of a thick one.
    nonisolated static func clauses(around sel: NSRange, in n: Int) -> [_TextInputClause] {
        var list: [_TextInputClause] = []
        if sel.location > 0 { list.append(_TextInputClause(range: NSRange(location: 0, length: sel.location), thick: false)) }
        list.append(_TextInputClause(range: sel, thick: true))
        if NSMaxRange(sel) < n { list.append(_TextInputClause(range: NSRange(location: NSMaxRange(sel), length: n - NSMaxRange(sel)), thick: false)) }
        return list
    }

    /// The UTF-16 offset of a UTF-8 byte offset in `s` (clamped; a byte inside a scalar
    /// counts up to that scalar).
    nonisolated static func utf16Offset(ofByte byte: Int, in s: String) -> Int {
        var bytes = 0, units = 0
        for scalar in s.unicodeScalars {
            let w = String(scalar).utf8.count
            if bytes + w > byte { break }
            bytes += w
            units += scalar.utf16.count
        }
        return units
    }

    /// Converts byte counts before and after the selection to UTF-16 counts.
    private func utf16Lengths(beforeBytes: Int, afterBytes: Int) -> (Int, Int) {
        let all = text()
        let sel = clamp(selectedRange, all.count)
        let before = String(decoding: all[0..<sel.location], as: UTF16.self)
        let after = String(decoding: all[NSMaxRange(sel)..<all.count], as: UTF16.self)
        var b = 0, bytes = 0
        for scalar in before.unicodeScalars.reversed() {
            if bytes >= beforeBytes { break }
            bytes += String(scalar).utf8.count
            b += scalar.utf16.count
        }
        var a = 0
        bytes = 0
        for scalar in after.unicodeScalars {
            if bytes >= afterBytes { break }
            bytes += String(scalar).utf8.count
            a += scalar.utf16.count
        }
        return (b, a)
    }

    /// The text around the caret for `set_surrounding_text`: at most `maxBytes` of UTF-8,
    /// the caret and anchor as byte offsets in it. The composition is left out, as the
    /// protocol wants.
    public func surroundingText(maxBytes: Int = 4000) -> (text: String, cursor: Int32, anchor: Int32) {
        var all = text()
        var sel = clamp(selectedRange, all.count)
        if let m = markedRange.map({ clamp($0, all.count) }) {
            all.removeSubrange(m.location..<NSMaxRange(m))
            sel = NSRange(location: m.location, length: 0)
        }
        // Whole scalars around the selection until the byte budget runs out.
        let before = Array(String(decoding: all[0..<sel.location], as: UTF16.self).unicodeScalars)
        let selected = String(decoding: all[sel.location..<NSMaxRange(sel)], as: UTF16.self)
        let after = Array(String(decoding: all[NSMaxRange(sel)..<all.count], as: UTF16.self).unicodeScalars)
        var budget = max(0, maxBytes - selected.utf8.count)
        // Half the budget before the caret, what is left after it, then the rest before.
        var lo = before.count, hi = 0
        var half = budget / 2
        while lo > 0, String(before[lo - 1]).utf8.count <= half {
            let w = String(before[lo - 1]).utf8.count
            half -= w; budget -= w; lo -= 1
        }
        while hi < after.count, String(after[hi]).utf8.count <= budget {
            budget -= String(after[hi]).utf8.count; hi += 1
        }
        while lo > 0, String(before[lo - 1]).utf8.count <= budget {
            budget -= String(before[lo - 1]).utf8.count; lo -= 1
        }
        var head = String.UnicodeScalarView(); head.append(contentsOf: before[lo...])
        var tail = String.UnicodeScalarView(); tail.append(contentsOf: after[0..<hi])
        let prefix = String(head)
        let text = prefix + selected + String(tail)
        let anchor = Int32(prefix.utf8.count)
        return (text, anchor + Int32(selected.utf8.count), anchor)
    }

    // MARK: Geometry

    /// The rectangle of `range` in window coordinates (bottom-left origin), from the
    /// client's `firstRect(forCharacterRange:)` (screen coordinates on macOS).
    public func rectInWindow(_ range: NSRange) -> NSRect? {
        if let tv = client as? NSTextView, range == caretRange { return tv._inputMethodRect }
        let screen = client.firstRect(forCharacterRange: range, actualRange: nil)
        guard let window else { return screen }
        return window.convertFromScreen(screen)
    }

    /// The composition, or the caret when there is none.
    public var caretRange: NSRange { markedRange ?? NSRange(location: selectedRange.location, length: 0) }

    /// Where the candidate window goes: the composition or the caret, in window coordinates.
    public var caretRectInWindow: NSRect? { rectInWindow(caretRange) }
}

/// The preedit string an X input method draws on the spot (XIM's preedit callbacks). XIM
/// counts in characters; each character carries its feedback (reverse video or highlight
/// for the clause being converted, underline for the rest).
public struct _XIMPreedit: Equatable {
    public var characters: [Unicode.Scalar] = []
    public var thick: [Bool] = []
    public var caret = 0
    public init() {}

    /// `XIMPreeditDrawCallbackStruct`: `length` characters at `first` change to `text`
    /// (nil text: deleted) with one feedback flag per new character.
    public mutating func draw(caret newCaret: Int, first: Int, length: Int, text: [Unicode.Scalar]?, thick newThick: [Bool]) {
        let lo = min(max(0, first), characters.count)
        let hi = min(characters.count, lo + max(0, length))
        let inserted = text ?? []
        characters.replaceSubrange(lo..<hi, with: inserted)
        let flags = (0..<inserted.count).map { $0 < newThick.count ? newThick[$0] : false }
        thick.replaceSubrange(lo..<hi, with: flags)
        caret = min(max(0, newCaret), characters.count)
    }

    public mutating func reset() { characters = []; thick = []; caret = 0 }

    public var string: String { var v = String.UnicodeScalarView(); v.append(contentsOf: characters); return String(v) }

    /// The caret as a UTF-16 offset.
    public var caretUTF16: Int { characters.prefix(caret).reduce(0) { $0 + $1.utf16.count } }

    /// Runs of equal feedback as UTF-16 clauses.
    public var clauses: [_TextInputClause] {
        var list: [_TextInputClause] = []
        var offset = 0
        var i = 0
        while i < characters.count {
            let flag = thick[i]
            var units = 0
            var j = i
            while j < characters.count && thick[j] == flag { units += characters[j].utf16.count; j += 1 }
            list.append(_TextInputClause(range: NSRange(location: offset, length: units), thick: flag))
            offset += units
            i = j
        }
        return list.count > 1 || list.first?.thick == true ? list : []
    }

    /// Shows this preedit on the session's client (empty: the composition ends).
    @MainActor public func show(in session: _TextInputSession) {
        session.setComposition(string, selection: NSRange(location: caretUTF16, length: 0), clauses: clauses)
    }
}
