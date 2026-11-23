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
        let previous = self.spec
        self.spec = spec
        self.host = host
        // AppKit rebuilds the menu on every item state change (Undo enabling on a key press):
        // when the bar itself shows nothing new, refill the pop-ups behind the installed bars
        // and leave the bars alone, so they never repaint (the white flash while typing).
        if !Win32WindowPolicy.menuBarChanged(from: previous, to: spec), let spec {
            for hwnd in windows {
                let key = UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hwnd)))
                if let bar = builtBars[key] { refill(bar, from: spec) } else { apply(to: hwnd) }
            }
            return
        }
        for hwnd in windows { apply(to: hwnd) }
    }

    /// Replaces the contents of every pop-up of `bar` from `spec` without touching the bar's
    /// own items. The pop-ups are not visible unless open, and an open one refreshes itself
    /// through `willOpen` (AppKit suppresses rebuilds while a menu is open).
    private func refill(_ bar: HMENU, from spec: PlatformMenu) {
        let visible = spec.items.filter { !$0.isHidden }
        let count = Int(GetMenuItemCount(bar))
        guard count == visible.count else { return }
        for (i, item) in visible.enumerated() {
            guard let sub = item.submenu, let popup = GetSubMenu(bar, Int32(i)) else { continue }
            let n = GetMenuItemCount(popup)
            if n > 0 {
                for j in stride(from: n - 1, through: 0, by: -1) {
                    if let nested = GetSubMenu(popup, j) { forget(nested) }
                    DeleteMenu(popup, UINT(j), UINT(MF_BYPOSITION))       // destroys a nested pop-up too
                }
            }
            for child in sub.items where !child.isHidden { append(child, to: popup) }
            let bits = UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(popup)))
            menusByHandle[bits] = sub.id
            handlesByMenu[sub.id] = popup
        }
    }

    /// Builds (or rebuilds) the menu bar for one window.
    func apply(to hwnd: HWND) {
        let key = UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hwnd)))
        var before = RECT()
        GetClientRect(hwnd, &before)
        // The old bar stays attached until the new one replaces it: detaching it first
        // (SetMenu(nil)) grew the client area by the bar's height for a moment, and the
        // WM_SIZE in between presented one frame drawn at the window's top with a black band
        // at the bottom (a rebuild runs whenever an item's state changes, e.g. Undo enabling
        // on a key press).
        let old = builtBars[key]
        if let old { forget(old) }      // before the new bar registers the same menu ids
        builtBars[key] = nil
        guard let spec else {
            if old != nil { SetMenu(hwnd, nil) }
            if let old { DestroyMenu(old) }
            DrawMenuBar(hwnd)
            restoreClientSize(hwnd, before)
            return
        }
        let bar = CreateMenu()
        for item in spec.items where !item.isHidden {
            append(item, to: bar)
        }
        if let bar {
            builtBars[key] = bar
            SetMenu(hwnd, bar)
        } else if old != nil {
            SetMenu(hwnd, nil)
        }
        if let old { DestroyMenu(old) }
        DrawMenuBar(hwnd)
        restoreClientSize(hwnd, before)
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

    /// WM_INITMENUPOPUP: refresh titles and enabled/checked states from the host before
    /// showing (validation may retitle an item, as TextEdit's Make Rich/Plain Text does).
    func willOpen(_ hmenu: HMENU) {
        let bits = UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hmenu)))
        guard let id = menusByHandle[bits], let fresh = host?.platformMenuWillOpen(id) else { return }
        for item in fresh.items where !item.isSeparator && item.submenu == nil && !item.isHidden {
            let label = item.keyEquivalentLabel.isEmpty ? item.title : item.title + "\t" + item.keyEquivalentLabel
            var flags = UINT(MF_BYCOMMAND) | UINT(MF_STRING)
            flags |= item.isEnabled ? UINT(MF_ENABLED) : UINT(MF_GRAYED)
            flags |= item.isChecked ? UINT(MF_CHECKED) : UINT(MF_UNCHECKED)
            _ = label.withCString(encodedAs: UTF16.self) { ModifyMenuW(hmenu, UINT(item.id), flags, UINT_PTR(item.id), $0) }
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
