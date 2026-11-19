// Input methods on Wayland: zwp_text_input_v3 (ADR-0047).
//
// The compositor relays the input method (ibus, fcitx5 through input-method-v2): while a
// text input is enabled on the focused surface, the keys it consumes never reach
// wl_keyboard, and its edits arrive as preedit_string / commit_string /
// delete_surrounding_text, applied together on `done`. The batch goes through
// `_TextInputSession.apply` to the focused NSTextInputClient (marked text for the preedit,
// insertText for the commit). The client tells the input method the text around the caret,
// the caret rectangle (for the candidate window) and the content type after every change,
// each followed by `commit`.

#if os(Linux)
import Foundation
import Glibc
import CWayland

@MainActor
final class WaylandTextInput {
    private unowned let backend: WaylandBackend
    private var manager: OpaquePointer?          // zwp_text_input_manager_v3*
    private var textInput: OpaquePointer?        // zwp_text_input_v3*
    /// The surface the compositor says has text input focus (enter/leave).
    private var surface: OpaquePointer?
    private var enabled = false
    private var pending = _TextInputSession.TextInputV3State()
    /// `commit` requests sent; a `done` whose serial matches answers the latest state.
    private var commits: UInt32 = 0
    private var lastCause = UInt32(ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_OTHER.rawValue)

    init(backend: WaylandBackend) { self.backend = backend }

    func managerAdded(name: UInt32, version: UInt32) {
        manager = OpaquePointer(appkitwin_wl_registry_bind(backend.registry, name, "zwp_text_input_manager_v3", 1))
        _TextInputTrace.log("wayland text-input-v3 manager bound")
        seatDidChange()
    }

    /// Makes the seat's text input once both the manager and the seat exist.
    func seatDidChange() {
        guard textInput == nil, let manager, let seat = backend.seat else { return }
        textInput = zwp_text_input_manager_v3_get_text_input(manager, seat)
        zwp_text_input_v3_add_listener(textInput, WaylandTextInput.listener, Unmanaged.passUnretained(self).toOpaque())
    }

    var isAvailable: Bool { textInput != nil }

    // MARK: Events

    private static func from(_ data: UnsafeMutableRawPointer?) -> WaylandTextInput? {
        data.map { Unmanaged<WaylandTextInput>.fromOpaque($0).takeUnretainedValue() }
    }

    private static let listener = WaylandBackend.listener(zwp_text_input_v3_listener(
        enter: { data, _, surface in
            guard let ti = WaylandTextInput.from(data) else { return }
            MainActor.assumeIsolated { ti.entered(surface) }
        },
        leave: { data, _, surface in
            guard let ti = WaylandTextInput.from(data) else { return }
            MainActor.assumeIsolated { ti.left(surface) }
        },
        preedit_string: { data, _, text, begin, end in
            guard let ti = WaylandTextInput.from(data) else { return }
            let s = text.map { String(cString: $0) }
            MainActor.assumeIsolated {
                ti.pending.preedit = s
                ti.pending.cursorBegin = begin
                ti.pending.cursorEnd = end
            }
        },
        commit_string: { data, _, text in
            guard let ti = WaylandTextInput.from(data) else { return }
            let s = text.map { String(cString: $0) }
            MainActor.assumeIsolated { ti.pending.commit = s }
        },
        delete_surrounding_text: { data, _, before, after in
            guard let ti = WaylandTextInput.from(data) else { return }
            MainActor.assumeIsolated { ti.pending.deleteBefore = before; ti.pending.deleteAfter = after }
        },
        done: { data, _, serial in
            guard let ti = WaylandTextInput.from(data) else { return }
            MainActor.assumeIsolated { ti.done(serial: serial) }
        }))

    private func entered(_ surface: OpaquePointer?) {
        self.surface = surface
        _TextInputTrace.log("wayland text-input enter")
        update(cause: UInt32(ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_OTHER.rawValue))
    }

    private func left(_ surface: OpaquePointer?) {
        _TextInputTrace.log("wayland text-input leave")
        if let window = backend.window(for: self.surface), let session = window.textInputSession { session.finishComposition() }
        self.surface = nil
        // After leave the text input is disabled by the compositor; the state goes too.
        enabled = false
        pending = .init()
    }

    private func done(serial: UInt32) {
        let state = pending
        pending = .init()
        _TextInputTrace.log("wayland text-input done serial \(serial): preedit \(state.preedit.map(_TextInputTrace.quote) ?? "nil") cursor \(state.cursorBegin),\(state.cursorEnd) commit \(state.commit.map(_TextInputTrace.quote) ?? "nil") delete \(state.deleteBefore),\(state.deleteAfter)")
        guard let window = backend.window(for: surface), let session = window.textInputSession else { return }
        session.apply(state)
        // The input method's change is answered with the new surrounding text and caret.
        if enabled { send(session, in: window, cause: UInt32(ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_INPUT_METHOD.rawValue)) }
    }

    // MARK: The window's side

    /// The core's notification for `window` (NSTextInputContext).
    func changed(in window: WaylandWindow, _ change: PlatformTextInputChange) {
        guard textInput != nil, let surface, window.surface == surface else { return }
        switch change {
        case .activated, .deactivated, .textChanged, .selectionChanged, .layoutChanged:
            update(cause: UInt32(ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_OTHER.rawValue))
        case .discardComposition:
            // There is no reset request: disabling and enabling again drops the preedit.
            if enabled, let textInput {
                zwp_text_input_v3_disable(textInput)
                commit()
                enabled = false
            }
            update(cause: UInt32(ZWP_TEXT_INPUT_V3_CHANGE_CAUSE_OTHER.rawValue))
        }
    }

    /// Enables the text input for the focused surface's text client, or disables it.
    private func update(cause: UInt32) {
        guard let textInput else { return }
        let window = backend.window(for: surface)
        if let window, let session = window.textInputSession {
            if !enabled {
                zwp_text_input_v3_enable(textInput)
                enabled = true
                _TextInputTrace.log("wayland text-input enable")
            }
            send(session, in: window, cause: cause)
        } else if enabled {
            zwp_text_input_v3_disable(textInput)
            enabled = false
            commit()
            _TextInputTrace.log("wayland text-input disable")
        }
    }

    /// Surrounding text, change cause, content type and caret rectangle, then commit.
    private func send(_ session: _TextInputSession, in window: WaylandWindow, cause: UInt32) {
        guard let textInput else { return }
        let surrounding = session.surroundingText()
        zwp_text_input_v3_set_surrounding_text(textInput, surrounding.text, surrounding.cursor, surrounding.anchor)
        zwp_text_input_v3_set_text_change_cause(textInput, cause)
        let secure = session.client is NSTextView && ((session.client as? NSTextView)?.delegate is NSSecureTextField)
        zwp_text_input_v3_set_content_type(textInput,
            UInt32(secure ? ZWP_TEXT_INPUT_V3_CONTENT_HINT_HIDDEN_TEXT.rawValue | ZWP_TEXT_INPUT_V3_CONTENT_HINT_SENSITIVE_DATA.rawValue : ZWP_TEXT_INPUT_V3_CONTENT_HINT_NONE.rawValue),
            UInt32(secure ? ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_PASSWORD.rawValue : ZWP_TEXT_INPUT_V3_CONTENT_PURPOSE_NORMAL.rawValue))
        if let r = session.caretRectInWindow {
            let s = window.surfaceRect(fromWindow: r)
            zwp_text_input_v3_set_cursor_rectangle(textInput, Int32(s.minX.rounded(.down)), Int32(s.minY.rounded(.down)),
                                                   Int32(max(1, s.width.rounded(.up))), Int32(max(1, s.height.rounded(.up))))
        }
        lastCause = cause
        commit()
    }

    private func commit() {
        guard let textInput else { return }
        zwp_text_input_v3_commit(textInput)
        commits &+= 1
        wl_display_flush(backend.display)
    }
}
#endif
