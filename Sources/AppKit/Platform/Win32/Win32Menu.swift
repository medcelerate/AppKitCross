// Win32 menu bars built from PlatformMenu descriptions.

#if os(Windows)
import Foundation
import WinSDK

@MainActor
final class Win32MenuBar {
    private(set) var spec: PlatformMenu?
    private weak var host: PlatformMenuHost?
    private var menusByHandle: [UInt: Int] = [:]       // HMENU bits -> PlatformMenu.id
    private var handlesByMenu: [Int: HMENU] = [:]
    private var builtBars: [UInt: HMENU] = [:]          // HWND bits -> HMENU owned by that window

    func install(_ spec: PlatformMenu?, host: PlatformMenuHost?, on windows: [HWND]) {
        self.spec = spec
        self.host = host
        for hwnd in windows { apply(to: hwnd) }
    }

    /// Builds (or rebuilds) the menu bar for one window.
    func apply(to hwnd: HWND) {
        let key = UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hwnd)))
        var before = RECT()
        GetClientRect(hwnd, &before)
        if let old = builtBars[key] {
            SetMenu(hwnd, nil)
            forget(old)
            DestroyMenu(old)
            builtBars[key] = nil
        }
        guard let spec else { DrawMenuBar(hwnd); restoreClientSize(hwnd, before); return }
        let bar = CreateMenu()
        for item in spec.items where !item.isHidden {
            append(item, to: bar)
        }
        if let bar {
            builtBars[key] = bar
            SetMenu(hwnd, bar)
            DrawMenuBar(hwnd)
            restoreClientSize(hwnd, before)
        }
    }

    /// SetMenu takes the bar out of the client area; grow the frame so the content keeps
    /// its size (AppKit's content rect never includes the menu bar).
    private func restoreClientSize(_ hwnd: HWND, _ before: RECT) {
        var after = RECT()
        GetClientRect(hwnd, &after)
        let delta = (before.bottom - before.top) - (after.bottom - after.top)
        guard delta != 0 else { return }
        var frame = RECT()
        GetWindowRect(hwnd, &frame)
        SetWindowPos(hwnd, nil, 0, 0, frame.right - frame.left, frame.bottom - frame.top + delta, UINT(SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE))
    }

    func windowDestroyed(_ hwnd: HWND) {
        let key = UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hwnd)))
        if let old = builtBars[key] { forget(old); DestroyMenu(old); builtBars[key] = nil }
    }

    private func forget(_ menu: HMENU) {
        let count = GetMenuItemCount(menu)
        if count > 0 {
            for i in 0..<count {
                if let sub = GetSubMenu(menu, i) { forget(sub) }
            }
        }
        let bits = UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(menu)))
        if let id = menusByHandle[bits] { handlesByMenu[id] = nil }
        menusByHandle[bits] = nil
    }

    private func append(_ item: PlatformMenuItem, to menu: HMENU?) {
        guard let menu else { return }
        if item.isSeparator {
            AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil)
            return
        }
        var flags = UINT(MF_STRING)
        if !item.isEnabled { flags |= UINT(MF_GRAYED) }
        if item.isChecked { flags |= UINT(MF_CHECKED) }
        let label = item.keyEquivalentLabel.isEmpty ? item.title : item.title + "\t" + item.keyEquivalentLabel
        if let sub = item.submenu {
            let popup = CreatePopupMenu()
            for child in sub.items where !child.isHidden { append(child, to: popup) }
            if let popup {
                let bits = UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(popup)))
                menusByHandle[bits] = sub.id
                handlesByMenu[sub.id] = popup
                label.withCString(encodedAs: UTF16.self) { AppendMenuW(menu, flags | UINT(MF_POPUP), UINT_PTR(UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(popup)))), $0) }
            }
        } else {
            label.withCString(encodedAs: UTF16.self) { AppendMenuW(menu, flags, UINT_PTR(item.id), $0) }
        }
    }

    /// WM_INITMENUPOPUP: refresh enabled/checked states from the host before showing.
    func willOpen(_ hmenu: HMENU) {
        let bits = UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hmenu)))
        guard let id = menusByHandle[bits], let fresh = host?.platformMenuWillOpen(id) else { return }
        for item in fresh.items where !item.isSeparator && item.submenu == nil {
            EnableMenuItem(hmenu, UINT(item.id), UINT(MF_BYCOMMAND) | (item.isEnabled ? UINT(MF_ENABLED) : UINT(MF_GRAYED)))
            CheckMenuItem(hmenu, UINT(item.id), UINT(MF_BYCOMMAND) | (item.isChecked ? UINT(MF_CHECKED) : UINT(MF_UNCHECKED)))
        }
    }

    /// WM_COMMAND from a menu item.
    func command(_ id: Int) -> Bool {
        guard let host else { return false }
        host.platformMenuItemSelected(id)
        return true
    }
}
#endif
