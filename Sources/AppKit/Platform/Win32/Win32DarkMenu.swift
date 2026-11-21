// The classic menu bar in the dark app theme. user32 paints the HMENU bar from the light
// theme whatever the app does (Windows has no public dark menu bar), so on a dark system
// the bar stayed white with black text under a dark caption. Windows' own fix, and the one
// every dark Win32 app uses (Notepad++, Explorer++, Windows Terminal's settings), is the
// undocumented pair: the uxtheme ordinals that let the app opt into dark mode (which makes
// the pop-up menus dark) and the WM_UAHDRAWMENU / WM_UAHDRAWMENUITEM messages, with which
// user32 asks the window to paint the bar's background and each title itself. Colours and
// the item-state logic are `Win32WindowPolicy.darkMenuBarTheme` / `menuBarItemColors`,
// tested on the host.

#if os(Windows)
import Foundation
import WinSDK

enum Win32DarkMenu {
    static let WM_UAHDRAWMENU: Int32 = 0x0091
    static let WM_UAHDRAWMENUITEM: Int32 = 0x0092

    // uxtheme.dll ordinals (Windows 10 1809+; 1903+ for SetPreferredAppMode).
    private typealias AllowDarkModeForWindowFn = @convention(c) (HWND?, Bool) -> Bool
    private typealias SetPreferredAppModeFn = @convention(c) (Int32) -> Int32
    private typealias FlushMenuThemesFn = @convention(c) () -> Void
    private static let uxtheme: HMODULE? = "uxtheme.dll".withCString(encodedAs: UTF16.self) { LoadLibraryW($0) }
    private static func ordinal(_ n: Int) -> UnsafeRawPointer? {
        guard let uxtheme, let proc = GetProcAddress(uxtheme, UnsafePointer<CChar>(bitPattern: n)) else { return nil }
        return unsafeBitCast(proc, to: UnsafeRawPointer.self)
    }
    private static let allowDarkModeForWindow = ordinal(133).map { unsafeBitCast($0, to: AllowDarkModeForWindowFn.self) }
    private static let setPreferredAppMode = ordinal(135).map { unsafeBitCast($0, to: SetPreferredAppModeFn.self) }
    private static let flushMenuThemes = ordinal(136).map { unsafeBitCast($0, to: FlushMenuThemesFn.self) }

    /// Once per process, before the first window: the app follows the system's app theme
    /// (`AllowDark` = 1), so pop-up menus and the system menu draw dark on a dark system.
    static func enableAppDarkMode() {
        _ = setPreferredAppMode?(1)
        flushMenuThemes?()
    }

    /// Per window, at creation: its menus may use the dark theme.
    static func allowDarkMode(for hwnd: HWND) {
        _ = allowDarkModeForWindow?(hwnd, true)
    }

    /// The system app theme changed (WM_SETTINGCHANGE "ImmersiveColorSet"): menu themes
    /// re-read, and the frame (caption, bar) repaints.
    static func themeChanged(_ hwnd: HWND) {
        flushMenuThemes?()
        RedrawWindow(hwnd, nil, nil, UINT(RDW_FRAME | RDW_INVALIDATE | RDW_UPDATENOW))
    }

    // MARK: Owner drawing

    nonisolated(unsafe) private static var brushes: [UInt32: HBRUSH] = [:]
    /// `0xRRGGBB` to a COLORREF (`0x00BBGGRR`).
    static func colorref(_ rgb: UInt32) -> COLORREF { COLORREF(((rgb & 0xFF) << 16) | (rgb & 0xFF00) | (rgb >> 16)) }
    private static func brush(_ rgb: UInt32) -> HBRUSH? {
        if let b = brushes[rgb] { return b }
        let b = CreateSolidBrush(colorref(rgb))
        if let b { brushes[rgb] = b }
        return b
    }

    /// The bar's rectangle in window coordinates (what the non-client DC uses).
    private static func barRect(_ hwnd: HWND) -> RECT? {
        var mbi = MENUBARINFO()
        mbi.cbSize = DWORD(MemoryLayout<MENUBARINFO>.size)
        guard GetMenuBarInfo(hwnd, LONG(bitPattern: 0xFFFF_FFFD) /* OBJID_MENU */, 0, &mbi) else { return nil }
        var win = RECT()
        GetWindowRect(hwnd, &win)
        var rc = mbi.rcBar
        OffsetRect(&rc, -win.left, -win.top)
        return rc
    }

    /// WM_UAHDRAWMENU: `lParam` is a UAHMENU { HMENU hmenu; HDC hdc; DWORD dwFlags }. Fills
    /// the bar's background.
    static func drawMenuBar(_ hwnd: HWND, _ lParam: LPARAM, theme: Win32WindowPolicy.MenuBarTheme) -> LRESULT? {
        guard let raw = UnsafeRawPointer(bitPattern: Int(lParam)), let hdc = raw.load(fromByteOffset: MemoryLayout<HMENU?>.stride, as: HDC?.self),
              var rc = barRect(hwnd), let b = brush(theme.background) else { return nil }
        FillRect(hdc, &rc, b)
        return 0
    }

    /// WM_UAHDRAWMENUITEM: `lParam` is a UAHDRAWMENUITEM { DRAWITEMSTRUCT dis; UAHMENU um;
    /// UAHMENUITEM umi { int iPosition; ... } }. Paints one title with its state's colours.
    static func drawMenuBarItem(_ lParam: LPARAM, theme: Win32WindowPolicy.MenuBarTheme) -> LRESULT? {
        guard let raw = UnsafeRawPointer(bitPattern: Int(lParam)) else { return nil }
        let dis = raw.load(as: DRAWITEMSTRUCT.self)
        let umOffset = MemoryLayout<DRAWITEMSTRUCT>.stride
        guard let hmenu = raw.load(fromByteOffset: umOffset, as: HMENU?.self), let hdc = dis.hDC else { return nil }
        // UAHMENU is HMENU, HDC, DWORD, padded to pointer alignment: 24 bytes on x64.
        let umiOffset = umOffset + 3 * MemoryLayout<UnsafeRawPointer>.stride
        let position = raw.load(fromByteOffset: umiOffset, as: Int32.self)
        var buffer = [WCHAR](repeating: 0, count: 256)
        var mii = MENUITEMINFOW()
        mii.cbSize = UINT(MemoryLayout<MENUITEMINFOW>.size)
        mii.fMask = UINT(MIIM_STRING)
        mii.cch = UINT(buffer.count - 1)
        buffer.withUnsafeMutableBufferPointer { buf in
            mii.dwTypeData = buf.baseAddress
            _ = GetMenuItemInfoW(hmenu, UINT(position), true, &mii)
        }
        let colors = Win32WindowPolicy.menuBarItemColors(itemState: UInt32(dis.itemState), theme: theme)
        var rc = dis.rcItem
        if let b = brush(colors.fill) { FillRect(hdc, &rc, b) }
        SetBkMode(hdc, TRANSPARENT)
        SetTextColor(hdc, colorref(colors.text))
        var flags = UINT(DT_CENTER | DT_SINGLELINE | DT_VCENTER)
        if UInt32(dis.itemState) & Win32WindowPolicy.ODS_NOACCEL != 0 { flags |= UINT(DT_HIDEPREFIX) }
        buffer.withUnsafeBufferPointer { buf in _ = DrawTextW(hdc, buf.baseAddress, -1, &rc, flags) }
        return 0
    }

    /// After DefWindowProc painted the frame (WM_NCPAINT, WM_NCACTIVATE): the one-pixel line
    /// user32 leaves under the bar in the light colour is repainted in the bar's.
    static func paintUnderline(_ hwnd: HWND, theme: Win32WindowPolicy.MenuBarTheme) {
        guard var rc = barRect(hwnd), let b = brush(theme.underline), let hdc = GetWindowDC(hwnd) else { return }
        rc.top = rc.bottom
        rc.bottom += 1
        FillRect(hdc, &rc, b)
        ReleaseDC(hwnd, hdc)
    }
}
#endif
