// Win32 backend: keyboard-layout translation for NSEvent.characters(byApplyingModifiers:) and
// the low-level input hooks behind NSEvent.addGlobalMonitorForEvents (ADR-0038).

#if os(Windows)
import Foundation
import WinSDK

extension Win32Backend {
    /// ToUnicode on a keyboard state built from `flags`: Shift, Caps Lock, Control (AppKit's
    /// Control, the Windows key's neighbour, gives control characters as on macOS) and Option
    /// as AltGr (Ctrl+Alt), the Windows way to a layout's alternate characters. The
    /// translation does not touch the thread's dead-key state.
    nonisolated static func characters(virtualKey vk: UInt16, modifierFlags flags: NSEvent.ModifierFlags) -> String? {
        var state = [UInt8](repeating: 0, count: 256)
        if flags.contains(.shift) { state[Int(VK_SHIFT)] = 0x80; state[Int(VK_LSHIFT)] = 0x80 }
        if flags.contains(.capsLock) { state[Int(VK_CAPITAL)] = 0x01 }
        if flags.contains(.control) || flags.contains(.option) { state[Int(VK_CONTROL)] = 0x80; state[Int(VK_LCONTROL)] = 0x80 }
        if flags.contains(.option) { state[Int(VK_MENU)] = 0x80; state[Int(VK_RMENU)] = 0x80 }
        let scan = MapVirtualKeyW(UINT(vk), 0)
        var buffer = [WCHAR](repeating: 0, count: 8)
        // wFlags bit 2 (Windows 10 1607+): leave the kernel's dead-key state alone.
        let n = ToUnicode(UINT(vk), scan, state, &buffer, 8, 4)
        if n == 0 { return nil }
        // A dead key (n < 0) gives its spacing character, as macOS reports the accent.
        return String(decoding: buffer[0..<Int(n < 0 ? 1 : n)], as: UTF16.self)
    }

    func characters(forKeyCode keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> String? {
        Win32Backend.characters(virtualKey: keyCode, modifierFlags: modifierFlags)
    }

    func setGlobalEventMonitoring(mask: NSEvent.EventTypeMask, handler: (@MainActor (NSEvent) -> Void)?) {
        Win32GlobalInput.update(mask: mask, handler: handler, hInstance: hInstance)
    }
}

/// WH_MOUSE_LL / WH_KEYBOARD_LL hooks, installed while a global monitor wants their events.
/// The hooks run on the main thread (the one that installed them) while it pumps messages;
/// input that goes to this process's own windows is left to the local path.
enum Win32GlobalInput {
    nonisolated(unsafe) static var handler: (@MainActor (NSEvent) -> Void)?
    nonisolated(unsafe) static var mask: NSEvent.EventTypeMask = []
    nonisolated(unsafe) static var mouseHook: HHOOK?
    nonisolated(unsafe) static var keyboardHook: HHOOK?
    nonisolated(unsafe) static var buttonsDown = 0

    static let mouseTypes: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                                     .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]
    static let keyTypes: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]

    static func update(mask: NSEvent.EventTypeMask, handler: (@MainActor (NSEvent) -> Void)?, hInstance: HINSTANCE?) {
        self.handler = handler
        self.mask = handler == nil ? [] : mask
        let wantMouse = !self.mask.intersection(mouseTypes).isEmpty
        let wantKeys = !self.mask.intersection(keyTypes).isEmpty
        if wantMouse, mouseHook == nil { mouseHook = SetWindowsHookExW(WH_MOUSE_LL, mouseProc, hInstance, 0) }
        if !wantMouse, let h = mouseHook { _ = UnhookWindowsHookEx(h); mouseHook = nil }
        if wantKeys, keyboardHook == nil { keyboardHook = SetWindowsHookExW(WH_KEYBOARD_LL, keyboardProc, hInstance, 0) }
        if !wantKeys, let h = keyboardHook { _ = UnhookWindowsHookEx(h); keyboardHook = nil }
    }

    /// True when the input goes to one of this process's windows.
    static func isOwn(_ hwnd: HWND?) -> Bool {
        guard let hwnd else { return false }
        var pid: DWORD = 0
        _ = GetWindowThreadProcessId(hwnd, &pid)
        return pid == GetCurrentProcessId()
    }

    static func modifierFlags() -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if GetAsyncKeyState(VK_SHIFT) < 0 { flags.insert(.shift) }
        if GetAsyncKeyState(VK_CONTROL) < 0 { flags.insert(.command) }
        if GetAsyncKeyState(VK_MENU) < 0 { flags.insert(.option) }
        if GetAsyncKeyState(VK_LWIN) < 0 || GetAsyncKeyState(VK_RWIN) < 0 { flags.insert(.control) }
        if (GetKeyState(VK_CAPITAL) & 1) != 0 { flags.insert(.capsLock) }
        return flags
    }

    @MainActor static func deliver(_ event: NSEvent) {
        guard mask.contains(NSEvent.EventTypeMask(type: event.type)), let handler else { return }
        handler(event)
    }

    static let mouseProc: HOOKPROC = { code, wParam, lParam in
        MainActor.assumeIsolated { Win32GlobalInput.handleMouse(code, wParam, lParam) }
        return CallNextHookEx(nil, code, wParam, lParam)
    }

    @MainActor static func handleMouse(_ code: Int32, _ wParam: WPARAM, _ lParam: LPARAM) {
        if code == HC_ACTION, let info = UnsafePointer<MSLLHOOKSTRUCT>(bitPattern: Int(lParam))?.pointee, !isOwn(WindowFromPoint(info.pt)) {
            let scale = CGFloat(GetDpiForSystem()) / 96
            let location = NSPoint(x: CGFloat(info.pt.x) / scale, y: CGFloat(Win32Backend.primaryHeightPixels - info.pt.y) / scale)
            let time = ProcessInfo.processInfo.systemUptime
            let flags = modifierFlags()
            let message = Int32(truncatingIfNeeded: wParam)
            func mouse(_ type: NSEvent.EventType, _ button: Int) -> NSEvent {
                NSEvent._mouseEvent(type: type, location: location, modifierFlags: flags, timestamp: time, windowNumber: 0, clickCount: 1, buttonNumber: button)
            }
            var event: NSEvent?
            switch message {
            case WM_MOUSEMOVE:
                event = buttonsDown & 1 != 0 ? mouse(.leftMouseDragged, 0) : buttonsDown & 2 != 0 ? mouse(.rightMouseDragged, 1)
                    : buttonsDown != 0 ? mouse(.otherMouseDragged, 2) : mouse(.mouseMoved, 0)
            case WM_LBUTTONDOWN: buttonsDown |= 1; event = mouse(.leftMouseDown, 0)
            case WM_LBUTTONUP: buttonsDown &= ~1; event = mouse(.leftMouseUp, 0)
            case WM_RBUTTONDOWN: buttonsDown |= 2; event = mouse(.rightMouseDown, 1)
            case WM_RBUTTONUP: buttonsDown &= ~2; event = mouse(.rightMouseUp, 1)
            case WM_MBUTTONDOWN: buttonsDown |= 4; event = mouse(.otherMouseDown, 2)
            case WM_MBUTTONUP: buttonsDown &= ~4; event = mouse(.otherMouseUp, 2)
            case WM_XBUTTONDOWN, WM_XBUTTONUP:
                let button = Int32((info.mouseData >> 16) & 0xFFFF) == XBUTTON1 ? 3 : 4
                if message == WM_XBUTTONDOWN { buttonsDown |= 1 << button } else { buttonsDown &= ~(1 << button) }
                event = mouse(message == WM_XBUTTONDOWN ? .otherMouseDown : .otherMouseUp, button)
            case WM_MOUSEWHEEL, WM_MOUSEHWHEEL:
                let delta = CGFloat(Int16(truncatingIfNeeded: info.mouseData >> 16)) / CGFloat(WHEEL_DELTA)
                let horizontal = message == WM_MOUSEHWHEEL
                event = NSEvent._scrollEvent(location: location, modifierFlags: flags, timestamp: time, windowNumber: 0,
                                             deltaX: horizontal ? -delta : 0, deltaY: horizontal ? 0 : delta, precise: false)
            default: break
            }
            if let event { deliver(event) }
        }
    }

    static let keyboardProc: HOOKPROC = { code, wParam, lParam in
        MainActor.assumeIsolated { Win32GlobalInput.handleKeyboard(code, wParam, lParam) }
        return CallNextHookEx(nil, code, wParam, lParam)
    }

    @MainActor static func handleKeyboard(_ code: Int32, _ wParam: WPARAM, _ lParam: LPARAM) {
        if code == HC_ACTION, let info = UnsafePointer<KBDLLHOOKSTRUCT>(bitPattern: Int(lParam))?.pointee, !isOwn(GetForegroundWindow()) {
            let message = Int32(truncatingIfNeeded: wParam)
            let down = message == WM_KEYDOWN || message == WM_SYSKEYDOWN
            let vk = Int32(info.vkCode)
            let time = ProcessInfo.processInfo.systemUptime
            let flags = modifierFlags()
            let event: NSEvent?
            if [VK_SHIFT, VK_LSHIFT, VK_RSHIFT, VK_CONTROL, VK_LCONTROL, VK_RCONTROL, VK_MENU, VK_LMENU, VK_RMENU, VK_LWIN, VK_RWIN, VK_CAPITAL].contains(vk) {
                event = NSEvent(type: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: time, windowNumber: 0)
            } else {
                let keyCode = UInt16(truncatingIfNeeded: info.vkCode)
                let chars = Win32Backend.characters(virtualKey: keyCode, modifierFlags: flags.intersection([.shift, .capsLock])) ?? ""
                let plain = Win32Backend.characters(virtualKey: keyCode, modifierFlags: []) ?? chars
                event = NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: flags, timestamp: time, windowNumber: 0,
                                         context: nil, characters: chars, charactersIgnoringModifiers: plain, isARepeat: false, keyCode: keyCode)
            }
            if let event { deliver(event) }
        }
    }
}
#endif
