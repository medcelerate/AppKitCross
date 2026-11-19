// Input methods on X11: XIM (ADR-0047).
//
// ibus and fcitx5 both serve XIM (XMODIFIERS=@im=ibus / @im=fcitx). Each window has an input
// context in on-the-spot style: the input method draws nothing itself, it sends the preedit
// through the draw/caret/done callbacks (`_XIMPreedit` keeps the string and its feedback)
// and the window shows it as marked text on the focused NSTextInputClient. The committed
// text arrives as a key press whose Xutf8LookupString status is XLookupChars. Keys go
// through XFilterEvent first (LinuxBackend.dispatch); what the input method takes is gone.
// The candidate window is placed at XNSpotLocation, the caret's baseline. Without an input
// method server Xlib's own one still composes dead keys.

#if os(Linux)
import Foundation
import Glibc
import CX11

@MainActor
final class X11InputContext {
    let ic: OpaquePointer                       // XIC
    let onTheSpot: Bool
    private let handlers: UnsafeMutablePointer<AppKitXIMHandlers>
    private var preedit = _XIMPreedit()
    private let session: @MainActor () -> _TextInputSession?
    /// The caret's baseline in window pixels (top-left origin).
    private let spot: @MainActor () -> (x: Int32, y: Int32)?
    private(set) var focused = false

    init?(im: OpaquePointer, window: Window, session: @escaping @MainActor () -> _TextInputSession?, spot: @escaping @MainActor () -> (x: Int32, y: Int32)?) {
        self.session = session
        self.spot = spot
        handlers = UnsafeMutablePointer<AppKitXIMHandlers>.allocate(capacity: 1)
        handlers.initialize(to: AppKitXIMHandlers())
        var onTheSpot: Int32 = 0
        guard let ic = appkitwin_xic_create(im, window, handlers, &onTheSpot) else {
            handlers.deallocate()
            return nil
        }
        self.ic = ic
        self.onTheSpot = onTheSpot != 0
        handlers.pointee.user = Unmanaged.passUnretained(self).toOpaque()
        handlers.pointee.start = { user in
            X11InputContext.perform(user) { _ in _TextInputTrace.log("xim preedit start") }
        }
        handlers.pointee.done = { user in
            X11InputContext.perform(user) { $0.preeditDone() }
        }
        handlers.pointee.draw = { user, caret, first, length, kind, text, count, feedback in
            var scalars: [Unicode.Scalar]? = nil
            var thick: [Bool] = []
            if kind == 1, let text {
                scalars = (0..<Int(count)).compactMap { Unicode.Scalar(text[$0]) }
            }
            if let feedback, kind != 0 {
                // XIMReverse (1) and XIMHighlight (4) mark the clause being converted.
                thick = (0..<Int(count)).map { feedback[$0] & 0x5 != 0 }
            }
            let draw = (caret: Int(caret), first: Int(first), length: Int(length), kind: Int(kind), text: scalars, thick: thick)
            X11InputContext.perform(user) { $0.preeditDraw(draw.caret, draw.first, draw.length, draw.kind, draw.text, draw.thick) }
        }
        handlers.pointee.caret = { user, position, direction in
            X11InputContext.perform(user) { $0.preeditCaret(Int(position), Int(direction)) }
        }
        _TextInputTrace.log("xim input context created (\(self.onTheSpot ? "on-the-spot" : "root window") preedit)")
    }

    /// Destroys the input context (before the window).
    func destroy() {
        XDestroyIC(ic)
        handlers.deallocate()
    }

    var filterEvents: Int { Int(appkitwin_xic_filter_events(ic)) }

    private static func perform<T: Sendable>(_ user: UnsafeMutableRawPointer?, _ body: @MainActor (X11InputContext) -> T) -> T {
        let context = Unmanaged<X11InputContext>.fromOpaque(user!).takeUnretainedValue()
        return MainActor.assumeIsolated { body(context) }
    }

    // MARK: Focus

    func setFocus(_ on: Bool) {
        guard on != focused else { if on { updateSpot() }; return }
        focused = on
        if on {
            XSetICFocus(ic)
            updateSpot()
        } else {
            if !preedit.characters.isEmpty {
                appkitwin_xic_reset(ic)
                preedit.reset()
            }
            XUnsetICFocus(ic)
        }
        _TextInputTrace.log("xim focus \(on)")
    }

    /// The core's notification for the window's text input client.
    func changed(_ change: PlatformTextInputChange, windowIsKey: Bool) {
        switch change {
        case .activated: setFocus(windowIsKey)
        case .deactivated: setFocus(false)
        case .discardComposition:
            appkitwin_xic_reset(ic)
            preedit.reset()
        case .textChanged, .selectionChanged, .layoutChanged:
            if focused { updateSpot() }
        }
    }

    func updateSpot() {
        guard let p = spot() else { return }
        appkitwin_xic_set_spot(ic, p.x, p.y)
    }

    // MARK: Keys

    /// Xutf8LookupString on a key press: the status (XLookupChars for text the input method
    /// committed), the text and the keysym.
    func lookup(_ xkey: inout XKeyEvent) -> (status: Int32, text: String, keysym: KeySym) {
        var size = 64
        while true {
            var buffer = [CChar](repeating: 0, count: size)
            var keysym: KeySym = 0
            var status: Int32 = 0
            let n = Xutf8LookupString(ic, &xkey, &buffer, Int32(size), &keysym, &status)
            if status == XBufferOverflow && size < 65536 { size *= 4; continue }
            let bytes = buffer.prefix(max(0, Int(n))).map { UInt8(bitPattern: $0) }
            return (status, String(decoding: bytes, as: UTF8.self), keysym)
        }
    }

    /// Text the input method committed: it replaces the preedit as ordinary text.
    func commit(_ text: String) -> Bool {
        guard let s = session() else { return false }
        _TextInputTrace.log("xim commit \(_TextInputTrace.quote(text))")
        preedit.reset()
        s.commit(text)
        updateSpot()
        return true
    }

    // MARK: Preedit callbacks

    private func preeditDraw(_ caret: Int, _ first: Int, _ length: Int, _ kind: Int, _ text: [Unicode.Scalar]?, _ thick: [Bool]) {
        switch kind {
        case 2: preedit.restyle(first: first, thick: thick)
        default: preedit.draw(caret: caret, first: first, length: length, text: kind == 1 ? (text ?? []) : nil, thick: thick)
        }
        preedit.caret = min(max(0, caret), preedit.characters.count)
        _TextInputTrace.log("xim preedit draw \(_TextInputTrace.quote(preedit.string)) caret \(preedit.caret)")
        show()
    }

    private func preeditCaret(_ position: Int, _ direction: Int) -> Int32 {
        switch direction {
        case 0: preedit.caret = min(preedit.characters.count, preedit.caret + 1)       // XIMForwardChar
        case 1: preedit.caret = max(0, preedit.caret - 1)                              // XIMBackwardChar
        case 8: preedit.caret = 0                                                      // XIMLineStart
        case 9: preedit.caret = preedit.characters.count                               // XIMLineEnd
        case 10: preedit.caret = min(max(0, position), preedit.characters.count)       // XIMAbsolutePosition
        default: break                                                                 // XIMDontChange and the rest
        }
        show()
        return Int32(preedit.caret)
    }

    private func preeditDone() {
        _TextInputTrace.log("xim preedit done")
        preedit.reset()
        if let s = session(), s.client.hasMarkedText() { s.cancelComposition() }
    }

    private func show() {
        guard let s = session() else { return }
        preedit.show(in: s)
        updateSpot()
    }
}
#endif
