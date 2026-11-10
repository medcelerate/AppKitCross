// Status items in the Windows notification area (Shell_NotifyIcon; ADR-0018).
//
// Each NSStatusItem is one NOTIFYICONDATA whose callback message lands on the backend's
// message window. The icon comes from the item's image (an HICON made from the BGRA
// pixels), the tool tip from the tool tip or the title (the notification area shows no
// text of its own), left clicks and right clicks go to the owner with the pointer
// position, and the owner opens the package's own menu window there. The message window
// is brought to the foreground first so the menu closes when the user clicks elsewhere
// (WM_KILLFOCUS cancels the tracker), as Windows asks of every notification-area menu.

#if os(Windows)
import Foundation
import WinSDK
import CoreGraphics

@MainActor
final class Win32StatusItems: PlatformStatusItemHost {
    static let callbackMessage = UINT(WM_APP) + 2
    /// Explorer restarted: the icons are added again.
    static let taskbarCreated: UINT = "TaskbarCreated".withCString(encodedAs: UTF16.self) { RegisterWindowMessageW($0) }
    private static let ninSelect = UINT(WM_USER) + 0
    private static let ninKeySelect = UINT(WM_USER) + 1

    private unowned let backend: Win32Backend
    private let hwnd: HWND
    private var items: [Win32StatusItem] = []
    private var nextID: UINT = 1
    private var trace: Bool { NSView._traceInvalidation }

    init(backend: Win32Backend, hwnd: HWND) {
        self.backend = backend
        self.hwnd = hwnd
    }

    /// Small icons are 16 px at 96 dpi; the shell scales them per monitor.
    var thickness: CGFloat { CGFloat(GetSystemMetrics(SM_CXSMICON)) * 96 / CGFloat(GetDpiForSystem()) }

    func makeStatusItem(owner: PlatformStatusItemOwner) -> PlatformStatusItem {
        let item = Win32StatusItem(host: self, hwnd: hwnd, id: nextID, owner: owner)
        nextID += 1
        items.append(item)
        item.add()
        return item
    }

    fileprivate func forget(_ item: Win32StatusItem) { items.removeAll { $0 === item } }

    /// The message window received the callback (or TaskbarCreated).
    func handle(message: UINT, wParam: WPARAM, lParam: LPARAM) {
        if message == Win32StatusItems.taskbarCreated {
            if trace { NSView._trace("win32 status: taskbar created, re-adding \(items.count) items") }
            for i in items { i.add() }
            return
        }
        let bits = UInt64(truncatingIfNeeded: lParam)
        let event = UINT(bits & 0xFFFF)
        let id = UINT((bits >> 16) & 0xFFFF)
        guard let item = items.first(where: { $0.id == id }) else { return }
        let click: PlatformStatusItemClick
        switch event {
        case Win32StatusItems.ninSelect, Win32StatusItems.ninKeySelect: click = .primary
        case UINT(WM_LBUTTONDBLCLK): click = .doublePrimary
        case UINT(WM_CONTEXTMENU): click = .secondary
        default: return
        }
        var point = backend.mouseLocation
        if event == Win32StatusItems.ninKeySelect || event == UINT(WM_CONTEXTMENU) {
            // Version 4 passes the anchor in wParam (pixels): where a keyboard selection wants the menu.
            let anchor = UInt64(truncatingIfNeeded: wParam)
            let x = Int32(truncatingIfNeeded: anchor & 0xFFFF), y = Int32(truncatingIfNeeded: (anchor >> 16) & 0xFFFF)
            let scale = CGFloat(GetDpiForSystem()) / 96
            point = NSPoint(x: CGFloat(x) / scale, y: CGFloat(Win32Backend.primaryHeightPixels - y) / scale)
        }
        if trace { NSView._trace("win32 status: item \(id) \(click) at \(point)") }
        // A menu opened from the notification area must belong to the foreground window,
        // or Windows leaves it up when the user clicks away (the documented SetForegroundWindow dance).
        SetForegroundWindow(hwnd)
        item.owner?.platformStatusItemClicked(click, at: point)
        PostMessageW(hwnd, UINT(WM_NULL), 0, 0)
    }

    /// The message window lost the foreground: an open status-item menu closes.
    func foregroundLost() {
        if let t = _NSMenuTracker.current { t.cancel() }
    }
}

@MainActor
final class Win32StatusItem: PlatformStatusItem {
    private unowned let host: Win32StatusItems
    private let hwnd: HWND
    let id: UINT
    fileprivate weak var owner: PlatformStatusItemOwner?
    private var icon: HICON?
    private var added = false
    private var removed = false
    var title = "" { didSet { if title != oldValue { update() } } }
    var toolTip: String? { didSet { if toolTip != oldValue { update() } } }
    var isVisible = true { didSet { if isVisible != oldValue { update() } } }
    var appearsDisabled = false

    init(host: Win32StatusItems, hwnd: HWND, id: UINT, owner: PlatformStatusItemOwner) {
        self.host = host
        self.hwnd = hwnd
        self.id = id
        self.owner = owner
    }

    private func data() -> NOTIFYICONDATAW {
        var nid = NOTIFYICONDATAW()
        nid.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        nid.hWnd = hwnd
        nid.uID = id
        nid.uFlags = UINT(NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP | NIF_STATE)
        nid.uCallbackMessage = Win32StatusItems.callbackMessage
        nid.hIcon = icon ?? LoadIconW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))     // IDI_APPLICATION
        nid.dwStateMask = DWORD(NIS_HIDDEN)
        nid.dwState = isVisible ? 0 : DWORD(NIS_HIDDEN)
        // The notification area names the icon by its tip (hover text, UI Automation):
        // the tool tip, else the title, else the process name so it is never blank.
        var text = toolTip ?? ""
        if text.isEmpty { text = title }
        if text.isEmpty { text = ProcessInfo.processInfo.processName }
        let tip = Array(text.utf16.prefix(127)) + [0]
        withUnsafeMutablePointer(to: &nid.szTip) { p in
            p.withMemoryRebound(to: WCHAR.self, capacity: 128) { dst in
                for (i, c) in tip.enumerated() { dst[i] = c }
            }
        }
        return nid
    }

    func add() {
        guard !removed else { return }
        var nid = data()
        if Shell_NotifyIconW(DWORD(NIM_ADD), &nid) {
            added = true
            nid.uVersion = 4           // NOTIFYICON_VERSION_4 (the anonymous union's member): NIN_SELECT / WM_CONTEXTMENU with anchors
            _ = Shell_NotifyIconW(DWORD(NIM_SETVERSION), &nid)
            if NSView._traceInvalidation { NSView._trace("win32 status: added item \(id) '\(title)'") }
        } else if NSView._traceInvalidation {
            NSView._trace("win32 status: Shell_NotifyIcon add failed for item \(id): \(GetLastError())")
        }
    }

    private func update() {
        guard added, !removed else { return }
        var nid = data()
        let ok = Shell_NotifyIconW(DWORD(NIM_MODIFY), &nid)
        if NSView._traceInvalidation { NSView._trace("win32 status: modify item \(id) tip '\(toolTip ?? title)' icon \(icon == nil ? "default" : "custom") \(ok ? "ok" : "failed \(GetLastError())")") }
    }

    func setImage(_ image: CGImage?, scale: CGFloat) {
        if let old = icon { DestroyIcon(old); icon = nil }
        if let image { icon = Win32StatusItem.makeIcon(image) }
        update()
    }

    /// An HICON from premultiplied BGRA pixels (top-down rows, as the port's CGImage holds them).
    static func makeIcon(_ image: CGImage) -> HICON? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var packed = [UInt8](repeating: 0, count: w * h * 4)
        image.data.withUnsafeBytes { src in
            guard let base = src.baseAddress else { return }
            for y in 0..<h {
                memcpy(&packed[y * w * 4], base + y * image.bytesPerRow, w * 4)
            }
        }
        return Win32Backend.makeIconHandle(width: w, height: h, hotSpot: (0, 0), isIcon: true, bgra: packed)
    }

    func remove() {
        guard !removed else { return }
        removed = true
        if added {
            var nid = NOTIFYICONDATAW()
            nid.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
            nid.hWnd = hwnd
            nid.uID = id
            _ = Shell_NotifyIconW(DWORD(NIM_DELETE), &nid)
        }
        if let i = icon { DestroyIcon(i); icon = nil }
        host.forget(self)
    }
}
#endif
