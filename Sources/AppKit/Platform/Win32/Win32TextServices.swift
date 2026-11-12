// The Text Services Framework for one window's text input (ADR-0016).
//
// CTextServices (cts.cpp) owns the COM objects: the thread manager, the document with its
// text store, and the composition, candidate-list and reconversion sinks. This file answers
// its callbacks from the focused text view through the platform text input seam
// (PlatformTextInput), so a composition from the input method is drawn exactly like one from
// the WM_IME_* path, and the window's WM_IME_* handling is switched off while TSF owns the input.

#if os(Windows)
import Foundation
import WinSDK
import CoreGraphics
import CTextServices

@MainActor
final class Win32TextServices {
    private var document: OpaquePointer?          // CTSDocument*
    private let hwnd: HWND
    private let input: @MainActor () -> PlatformTextInput?
    /// The window's backing scale and content height in points (for screen rectangles).
    private let geometry: @MainActor () -> (scale: CGFloat, height: CGFloat)

    /// Nil when TSF is not available (no thread manager).
    init?(hwnd: HWND, input: @escaping @MainActor () -> PlatformTextInput?, geometry: @escaping @MainActor () -> (scale: CGFloat, height: CGFloat)) {
        self.hwnd = hwnd
        self.input = input
        self.geometry = geometry
        var callbacks = CTSCallbacks()
        callbacks.length = { user in
            Win32TextServices.perform(user) { $0.length() }
        }
        callbacks.read = { user, start, count, out in
            Win32TextServices.perform(user) { $0.read(start: start, count: count, into: out) }
        }
        callbacks.selection = { user, start, count in
            Win32TextServices.perform(user) { $0.selection(start: start, count: count) }
        }
        callbacks.setSelection = { user, start, count in
            Win32TextServices.perform(user) { $0.setSelection(start: start, count: count) }
        }
        callbacks.replace = { user, start, count, text, textCount, marked in
            Win32TextServices.perform(user) { $0.replace(start: start, count: count, text: text, textCount: textCount, marked: marked != 0) }
        }
        callbacks.markRange = { user, start, count in
            Win32TextServices.perform(user) { $0.markRange(start: start, count: count) }
        }
        callbacks.endComposition = { user in
            Win32TextServices.perform(user) { $0.endComposition() }
        }
        callbacks.rect = { user, start, count, ltrb in
            Win32TextServices.perform(user) { $0.rect(start: start, count: count, ltrb: ltrb) }
        }
        callbacks.window = { user in
            UnsafeMutableRawPointer(bitPattern: Win32TextServices.perform(user) { Int(bitPattern: $0.hwnd) })
        }
        callbacks.candidates = { user, count in
            Win32TextServices.perform(user) { $0.candidatesChanged(Int(count)) }
        }
        callbacks.user = Unmanaged.passUnretained(self).toOpaque()
        guard let document = cts_document_create(&callbacks, UnsafeMutableRawPointer(hwnd)) else { return nil }
        self.document = document
    }

    /// Makes the Microsoft IME (Japanese) this process's text service (test hook: APPKITWIN_IME_LAYOUT). Returns the HRESULT.
    @discardableResult
    static func activateMicrosoftIME() -> Int32 { cts_activate_microsoft_ime_jp() }

    /// Releases the COM objects. Called when the window is destroyed (no `deinit` on the main actor).
    func invalidate() {
        if let document { cts_document_destroy(document) }
        document = nil
    }

    // MARK: State

    func setFocus(_ focused: Bool) {
        guard let document else { return }
        cts_document_set_focus(document, focused ? 1 : 0)
    }

    var isComposing: Bool { document.map { cts_document_composing($0) != 0 } ?? false }

    /// The input method's kana (on) or direct (off) state, held in TSF's keyboard compartment.
    var isIMEOpen: Bool { document.map { cts_document_ime_open($0) != 0 } ?? false }
    func setIMEOpen(_ open: Bool) {
        guard let document else { return }
        cts_document_set_ime_open(document, open ? 1 : 0)
    }

    /// The input mode's conversion bits (see cts.h). 0x11 is native romaji (hiragana) input.
    var conversion: Int32 { document.map { cts_document_conversion($0) } ?? 0 }
    func setConversion(_ mode: Int32) {
        guard let document else { return }
        cts_document_set_conversion(document, mode)
    }

    /// Candidates the input method is listing (0 when its candidate window is closed).
    var candidateCount: Int { document.map { Int(cts_document_candidate_count($0)) } ?? 0 }

    /// Forwards a key message to the input method; true when it took the key.
    func key(wParam: WPARAM, lParam: LPARAM, down: Bool) -> Bool {
        guard let document else { return false }
        let eaten = cts_document_key(document, UInt64(wParam), Int64(lParam), down ? 1 : 0) != 0
        if eaten, NSView._traceInvalidation {
            NSView._trace("win32 tsf key \(down ? "down" : "up") vk 0x\(String(UInt64(wParam), radix: 16)) eaten, composing \(isComposing)")
        }
        return eaten
    }

    /// Reconversion of the selected text. Returns the HRESULT (0 = S_OK).
    @discardableResult
    func reconvert() -> Int32 {
        guard let document else { return -1 }
        return cts_document_reconvert(document)
    }

    /// The document text or selection changed outside an edit session.
    func notifyChange(start: Int, oldCount: Int, newCount: Int) {
        guard let document else { return }
        cts_document_notify_change(document, Int32(start), Int32(oldCount), Int32(newCount))
    }

    // MARK: Callbacks (UI thread)

    /// Runs `body` on the services the C callback names, on the main actor (the callbacks arrive on the UI thread).
    private static func perform<T: Sendable>(_ user: UnsafeMutableRawPointer?, _ body: @MainActor (Win32TextServices) -> T) -> T {
        let services = Unmanaged<Win32TextServices>.fromOpaque(user!).takeUnretainedValue()
        return MainActor.assumeIsolated { body(services) }
    }

    private func length() -> Int32 {
        Int32(input()?.documentText().utf16.count ?? 0)
    }

    private func read(start: Int32, count: Int32, into out: UnsafeMutablePointer<UInt16>?) -> Int32 {
        guard let out, let input = input() else { return 0 }
        let units = Array(input.documentText().utf16)
        let lower = max(0, min(Int(start), units.count))
        let upper = max(lower, min(lower + Int(count), units.count))
        for (i, unit) in units[lower..<upper].enumerated() { out[i] = unit }
        return Int32(upper - lower)
    }

    private func selection(start: UnsafeMutablePointer<Int32>?, count: UnsafeMutablePointer<Int32>?) {
        let range = input()?.selectedRange() ?? NSRange(location: 0, length: 0)
        start?.pointee = Int32(range.location == NSNotFound ? 0 : range.location)
        count?.pointee = Int32(range.location == NSNotFound ? 0 : range.length)
    }

    private func setSelection(start: Int32, count: Int32) {
        input()?.setSelectedRange(NSRange(location: Int(start), length: Int(count)))
    }

    private func replace(start: Int32, count: Int32, text: UnsafePointer<UInt16>?, textCount: Int32, marked: Bool) {
        guard let input = input() else { return }
        let string: String
        if let text, textCount > 0 {
            string = String(decoding: UnsafeBufferPointer(start: text, count: Int(textCount)), as: UTF16.self)
        } else {
            string = ""
        }
        input.replaceRange(NSRange(location: Int(start), length: Int(count)), string, marked)
    }

    private func markRange(start: Int32, count: Int32) {
        input()?.markRange(NSRange(location: Int(start), length: Int(count)))
    }

    private func endComposition() {
        guard let input = input(), input.hasMarkedText() else { return }
        input.unmarkText()
    }

    /// Screen rectangle (pixels, top-left origin) for the caret or composition.
    private func rect(start: Int32, count: Int32, ltrb: UnsafeMutablePointer<Int32>?) -> Int32 {
        _ = start; _ = count
        guard let ltrb, let rect = input()?.markedRect() else { return 0 }
        let g = geometry()
        var origin = POINT(x: 0, y: 0)
        ClientToScreen(hwnd, &origin)
        ltrb[0] = origin.x + Int32((rect.minX * g.scale).rounded(.down))
        ltrb[1] = origin.y + Int32(((g.height - rect.maxY) * g.scale).rounded(.down))
        ltrb[2] = origin.x + Int32((rect.maxX * g.scale).rounded(.up))
        ltrb[3] = origin.y + Int32(((g.height - rect.minY) * g.scale).rounded(.up))
        return 1
    }

    private func candidatesChanged(_ count: Int) {
        _ = count   // the input method draws the list; `candidateCount` reports it for the window
    }
}
#endif
