// The Text Services Framework for one window's text input (ADR-0047).
//
// CTextServices (cts.cpp) owns the COM objects: the thread's thread manager, this window's
// document with its text store, the composition, text-edit and candidate-list sinks. The
// store keeps a copy of the focused text view's text around the selection; this file keeps
// that copy in step with the view (`sync`) and, when the input method has edited the copy,
// applies the edit to the view through `_TextInputSession` (marked text for the
// composition, insertText for what was committed). While TSF owns the input the window's
// WM_IME_* handling (IMM32) stays off; without TSF it is the fallback.

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
    /// The client the input method composes into (the context activated), nil when none.
    private var session: _TextInputSession?
    /// What the store was last given: the view's text around the selection.
    private var synced: _TextInputSession.Snapshot?
    private var syncScheduled = false

    /// The services of the window with the keyboard focus (keys go to its input method).
    static weak var focused: Win32TextServices?

    /// Nil when TSF is not available (no thread manager); the window then uses IMM32.
    init?(hwnd: HWND, input: @escaping @MainActor () -> PlatformTextInput?, geometry: @escaping @MainActor () -> (scale: CGFloat, height: CGFloat)) {
        self.hwnd = hwnd
        self.input = input
        self.geometry = geometry
        cts_set_trace(_TextInputTrace.enabled ? 1 : 0)
        var callbacks = CTSCallbacks()
        callbacks.user = Unmanaged.passUnretained(self).toOpaque()
        callbacks.refresh = { user in
            Win32TextServices.perform(user) { $0.refresh() }
        }
        callbacks.edited = { user, text, length, selStart, selEnd, compStart, compLength, clauses, clauseCount in
            let units = text.map { Array(UnsafeBufferPointer(start: $0, count: Int(length))) } ?? []
            var list: [_TextInputClause] = []
            if let clauses {
                for i in 0..<Int(clauseCount) {
                    let c = clauses[i]
                    list.append(_TextInputClause(range: NSRange(location: Int(c.start), length: Int(c.length)), thick: c.thick != 0))
                }
            }
            let composition = compStart >= 0 ? NSRange(location: Int(compStart), length: Int(compLength)) : nil
            let selection = NSRange(location: Int(selStart), length: Int(max(0, selEnd - selStart)))
            Win32TextServices.perform(user) { $0.edited(units, selection: selection, composition: composition, clauses: list) }
        }
        callbacks.rect = { user, start, count, ltrb in
            Win32TextServices.perform(user) { $0.rect(start: Int(start), count: Int(count), ltrb: ltrb) }
        }
        callbacks.candidates = { user, count in
            Win32TextServices.perform(user) { _ in _TextInputTrace.log("tsf candidates \(count)") }
        }
        var hr: Int32 = 0
        guard let document = cts_document_create(&callbacks, UnsafeMutableRawPointer(hwnd), &hr) else {
            _TextInputTrace.log("tsf unavailable (hr 0x\(String(UInt32(bitPattern: hr), radix: 16))): IMM32 fallback")
            return nil
        }
        self.document = document
        _TextInputTrace.log("tsf document created")
    }

    /// Makes the Microsoft IME (Japanese) this process's text service (test hook:
    /// APPKITWIN_IME_LAYOUT). Returns the HRESULT.
    @discardableResult
    static func activateMicrosoftIME() -> Int32 { cts_activate_microsoft_ime_jp() }

    /// Releases the COM objects. Called when the window is destroyed.
    func invalidate() {
        if Win32TextServices.focused === self { Win32TextServices.focused = nil }
        session = nil
        if let document { cts_document_destroy(document) }
        document = nil
    }

    // MARK: Focus

    /// The window got the keyboard focus or its text input client changed: the input
    /// method composes into the current client, or is turned off when there is none.
    func focus() {
        guard let document else { return }
        let next = input()?.session
        if let current = session, let next, current.client as AnyObject === next.client as AnyObject {
            // Same client: keep the composition, bring the text up to date.
            sync()
        } else {
            detach()
            session = next
            synced = nil
            if next != nil { sync() }
        }
        Win32TextServices.focused = self
        cts_document_set_focus(document, session == nil ? 0 : 1)
        _TextInputTrace.log("tsf focus \(session.map { String(describing: type(of: $0.client)) } ?? "none")")
    }

    /// The window lost the keyboard focus.
    func blur() {
        guard let document else { return }
        detach()
        cts_document_set_focus(document, 0)
        if Win32TextServices.focused === self { Win32TextServices.focused = nil }
        _TextInputTrace.log("tsf blur")
    }

    /// The client is going away (deactivated): the input method's composition ends without
    /// reaching it again (the client already kept its marked text as typed).
    private func detach() {
        guard let document, session != nil else { session = nil; return }
        session = nil
        if cts_document_composing(document) != 0 { cts_document_end_composition(document) }
    }

    var isFocused: Bool { session != nil }
    var isComposing: Bool { document.map { cts_document_composing($0) != 0 } ?? false }
    var candidateCount: Int { document.map { Int(cts_document_candidate_count($0)) } ?? 0 }

    // MARK: The core's notifications

    func handle(_ change: PlatformTextInputChange) {
        guard let document else { return }
        switch change {
        case .activated: focus()
        case .deactivated: detach(); cts_document_set_focus(document, 0)
        case .textChanged, .selectionChanged: scheduleSync()
        case .layoutChanged: cts_document_layout_changed(document)
        case .discardComposition: cts_document_end_composition(document)
        }
    }

    /// Coalesces the view's change notifications into one sync after the current event.
    private func scheduleSync() {
        guard !syncScheduled else { return }
        syncScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.syncScheduled = false
                self.sync()
            }
        }
    }

    /// Hands the store the view's text and selection when they differ from what it has.
    /// A composition the view no longer shows (a click committed it) is ended.
    func sync() {
        guard let document, let session else { return }
        let snapshot = session.snapshot()
        if snapshot != synced {
            synced = snapshot
            snapshot.text.withUnsafeBufferPointer { buffer in
                cts_document_sync(document, buffer.baseAddress, Int32(buffer.count),
                                  Int32(snapshot.selection.location), Int32(NSMaxRange(snapshot.selection)))
            }
        }
        if snapshot.marked == nil, cts_document_composing(document) != 0 {
            _TextInputTrace.log("tsf view has no marked text: ending the composition")
            cts_document_end_composition(document)
        }
    }

    // MARK: Keys

    /// Offers a key message to the focused window's input method before TranslateMessage;
    /// true when it took the key. `APPKITWIN_TSF_KEYS=0` turns this off (TSF's own keyboard
    /// hook still runs).
    static func preTranslate(_ msg: MSG) -> Bool {
        guard forwardsKeys, let focused, focused.isFocused else { return false }
        let message = msg.message
        guard message == UINT(WM_KEYDOWN) || message == UINT(WM_KEYUP) else { return false }
        // Keys the hook already gave the input method arrive as VK_PROCESSKEY.
        if Int32(truncatingIfNeeded: msg.wParam) == VK_PROCESSKEY { return false }
        return cts_process_key(UInt32(message), UInt64(msg.wParam), Int64(msg.lParam)) != 0
    }
    private static let forwardsKeys = ProcessInfo.processInfo.environment["APPKITWIN_TSF_KEYS"] != "0"

    // MARK: Test hooks

    var isIMEOpen: Bool { document.map { cts_document_ime_open($0) != 0 } ?? false }
    func setIMEOpen(_ open: Bool) { if let document { cts_document_set_ime_open(document, open ? 1 : 0) } }
    var conversion: Int32 { document.map { cts_document_conversion($0) } ?? 0 }
    func setConversion(_ mode: Int32) { if let document { cts_document_set_conversion(document, mode) } }

    // MARK: Callbacks (UI thread, never inside a lock)

    private static func perform<T: Sendable>(_ user: UnsafeMutableRawPointer?, _ body: @MainActor (Win32TextServices) -> T) -> T {
        let services = Unmanaged<Win32TextServices>.fromOpaque(user!).takeUnretainedValue()
        return MainActor.assumeIsolated { body(services) }
    }

    private func refresh() { sync() }

    /// The input method edited the store: the view gets the same text, the composition as
    /// marked text. The store is then synced back from the view (normally a no-op).
    private func edited(_ text: [UInt16], selection: NSRange, composition: NSRange?, clauses: [_TextInputClause]) {
        guard let session, let old = synced else { return }
        _TextInputTrace.log("tsf edit \(_TextInputTrace.quote(String(decoding: text, as: UTF16.self))) selection \(selection.location),\(selection.length) composition \(composition.map { "\($0.location),\($0.length)" } ?? "none")")
        session.applyStoreEdit(from: old, newText: text, selection: selection, composition: composition, clauses: clauses)
        sync()
        if let document { cts_document_layout_changed(document) }
    }

    /// Screen rectangle (pixels, top-left origin) for store units `start`..`start+count`.
    private func rect(start: Int, count: Int, ltrb: UnsafeMutablePointer<Int32>?) -> Int32 {
        guard let ltrb, let session else { return 0 }
        let base = synced?.base ?? 0
        let range = NSRange(location: base + start, length: count)
        guard let rect = session.rectInWindow(range) ?? session.caretRectInWindow else { return 0 }
        let g = geometry()
        var origin = POINT(x: 0, y: 0)
        ClientToScreen(hwnd, &origin)
        ltrb[0] = origin.x + Int32((rect.minX * g.scale).rounded(.down))
        ltrb[1] = origin.y + Int32(((g.height - rect.maxY) * g.scale).rounded(.down))
        ltrb[2] = origin.x + Int32((rect.maxX * g.scale).rounded(.up))
        ltrb[3] = origin.y + Int32(((g.height - rect.minY) * g.scale).rounded(.up))
        return 1
    }
}
#endif
