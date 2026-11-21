// Creation-time decisions of the Win32 window that depend only on the style mask and the
// application. Kept outside Platform/Win32 (which Package.swift excludes on other hosts)
// and free of WinSDK, so the macOS and Linux host builds compile and test them.

import Foundation

public enum Win32WindowPolicy {
    /// Why a window keeps or drops its redirection surface (`WS_EX_NOREDIRECTIONBITMAP`).
    public enum RedirectionBitmap: Equatable, Sendable {
        /// Dropped: the window presents through a flip-model swap chain or DirectComposition.
        case none
        /// Kept: `APPKITWIN_LEGACY_D2D=1`, the `ID2D1HwndRenderTarget` blits into it.
        case keptForLegacyTarget
        /// Kept: no D3D11 device or DXGI 1.2, so the HWND target will be used.
        case keptForMissingDevice
        /// Kept: the window carries the Win32 menu bar, which user32 draws through GDI into
        /// the redirection surface (without one the bar is a black strip).
        case keptForMenuBar
        /// Kept: `APPKITWIN_REDIRECTION_BITMAP=1` asked for it (an experiment knob: some
        /// shell features are said to need the surface).
        case keptByRequest

        public var keeps: Bool { self != .none }
    }

    /// Whether a window with `styleMask` shows the application's Win32 menu bar:
    /// titled, not a utility panel, the application has a main menu, and the content does
    /// not cover the frame (`fullSizeContentView` or borderless windows have no non-client
    /// area to show it in).
    public static func carriesMenuBar(_ styleMask: NSWindow.StyleMask, applicationHasMenuBar: Bool) -> Bool {
        styleMask.contains(.titled) && !styleMask.contains(.utilityWindow) && applicationHasMenuBar
            && !styleMask.contains(.fullSizeContentView)
    }

    /// The redirection-bitmap decision at `CreateWindowExW` (the bit is creation-only).
    public static func redirectionBitmap(styleMask: NSWindow.StyleMask, applicationHasMenuBar: Bool,
                                         legacyTarget: Bool, presentationAvailable: Bool, requested: Bool = false) -> RedirectionBitmap {
        if requested { return .keptByRequest }
        if legacyTarget { return .keptForLegacyTarget }
        if !presentationAvailable { return .keptForMissingDevice }
        if carriesMenuBar(styleMask, applicationHasMenuBar: applicationHasMenuBar) { return .keptForMenuBar }
        return .none
    }

    // MARK: Transparency and the DWM backdrop

    /// The corner radius (points) DWM rounds a window to on Windows 11 (`DWMWCP_ROUND`).
    public static let systemCornerRadius: CGFloat = 8

    /// The `DWMWA_SYSTEMBACKDROP_TYPE` a window gets. DWM paints Mica and Acrylic over the
    /// whole window rectangle (rounded only by `DWMWCP_ROUND`), behind every pixel the swap
    /// chain leaves translucent, and has no way to follow the content's alpha. So a
    /// non-opaque window whose effect views leave part of the rectangle uncovered, or clip
    /// it to corners rounder than DWM's, gets no system backdrop: the uncovered pixels stay
    /// at alpha 0 and show the desktop, as on macOS, and the effect views show their tint
    /// without the blur. An opaque window covers the rectangle itself, so it keeps the
    /// backdrop it asks for.
    public static func systemBackdrop(for chrome: PlatformWindowChrome) -> PlatformWindowChrome.Backdrop {
        guard chrome.isTransparent, chrome.backdrop != .none else { return chrome.backdrop }
        if !chrome.backdropCoversWindow || chrome.backdropCornerRadius > systemCornerRadius { return .none }
        return chrome.backdrop
    }

    /// Whether DWM's one-pixel border (`DWMWA_BORDER_COLOR`) is turned off: on borderless
    /// windows (macOS draws none) and on non-opaque windows whose content covers the frame,
    /// where the border would outline the rectangle around a shape the content draws.
    public static func hidesBorder(styleMask: NSWindow.StyleMask, chrome: PlatformWindowChrome) -> Bool {
        if !styleMask.contains(.titled) { return true }
        return chrome.isTransparent && (styleMask.contains(.fullSizeContentView) || chrome.extendsContentIntoTitleBar)
    }

    // MARK: The unified caption (ADR-0053)

    /// What a titled window's caption is on Windows.
    public enum CaptionMode: Equatable, Sendable {
        /// The system caption and Windows' own caption buttons, the HMENU menu bar under it,
        /// the toolbar as a band of the content below (the default).
        case classic
        /// The package-drawn unified title bar is the caption: title and subtitle, toolbar
        /// items and title bar accessories in the band, Windows caption buttons at its right,
        /// the application menu as a package-drawn row directly under it.
        case unified
    }

    /// The caption of a window with `styleMask` and `chrome`. A window opts in with the
    /// standard macOS recipe for a custom unified title bar: `fullSizeContentView` and
    /// `titlebarAppearsTransparent`. `APPKITWIN_UNIFIED_CAPTION=0` forces classic for every
    /// window (comparison runs); `=1` changes nothing here (it maps SwiftUI windows onto the
    /// recipe, `mapsSwiftUIWindows`). Everything else keeps the classic caption, so an
    /// application sees no change unless it opts in.
    public static func captionMode(styleMask: NSWindow.StyleMask, chrome: PlatformWindowChrome, switch value: PlatformFeatureSwitch) -> CaptionMode {
        guard value != .off else { return .classic }
        guard styleMask.contains(.titled), styleMask.contains(.fullSizeContentView), chrome.transparentTitleBar else { return .classic }
        return .unified
    }

    /// Whether SwiftUI's scene windows take the recipe (`.fullSizeContentView`, a transparent
    /// title bar) so their unified toolbar becomes the caption: only when the switch is on.
    public static func mapsSwiftUIWindows(switch value: PlatformFeatureSwitch) -> Bool { value == .on }

    public static let unifiedCaptionEnvironmentKey = "APPKITWIN_UNIFIED_CAPTION"
    public static let unifiedCaptionPlistKey = "AppKitCrossUnifiedCaption"

    /// The height (points) of the menu bar row the package draws under a unified caption.
    /// Windows' own bar is 20 px at 100 % for a 9 pt Segoe UI; the row holds the port's
    /// 13 pt menu font with the same proportions.
    public static let menuBarRowHeight: CGFloat = 24

    public static let VK_SPACE: Int32 = 0x20
    public static let VK_F4: Int32 = 0x73

    /// Whether a `WM_SYSKEYDOWN` (Alt held) for `virtualKey` goes to `DefWindowProc` rather
    /// than becoming an AppKit key event. With the HMENU bar every system key is
    /// DefWindowProc's (it runs the menu loop). Without one, Alt+Space must still open the
    /// system menu and Alt+F4 still close the window, as on every Windows window; the
    /// other Alt combinations are the package's (the menu row's mnemonics under a unified
    /// caption, AppKit's Option key events elsewhere).
    public static func passesSystemKeyToDefWindowProc(virtualKey: Int32, hasNativeMenuBar: Bool) -> Bool {
        if hasNativeMenuBar { return true }
        return virtualKey == VK_SPACE || virtualKey == VK_F4
    }

    // MARK: The classic menu bar (HMENU)

    /// Whether a new main-menu description changes anything the menu bar itself shows: the
    /// top-level titles, their order, visibility and enabled state. When it does not (an
    /// item inside a menu was enabled, retitled or checked: Undo after a keystroke), the
    /// bar is kept and only its pop-ups are refilled, so nothing repaints. Swapping the bar
    /// (`SetMenu` + `DrawMenuBar`) on every such change repainted it from a blank surface,
    /// which Evan saw as the bar flashing white while typing in TextEdit.
    public static func menuBarChanged(from old: PlatformMenu?, to new: PlatformMenu?) -> Bool {
        guard let old, let new else { return (old == nil) != (new == nil) }
        let a = old.items.filter { !$0.isHidden }, b = new.items.filter { !$0.isHidden }
        guard a.count == b.count else { return true }
        for (x, y) in zip(a, b) {
            if x.id != y.id || x.title != y.title || x.isSeparator != y.isSeparator || x.isEnabled != y.isEnabled
                || (x.submenu == nil) != (y.submenu == nil) || x.submenu?.id != y.submenu?.id { return true }
        }
        return false
    }

    /// The colours of an owner-drawn menu bar in the system's dark theme (user32 draws the
    /// bar white whatever the app theme; Windows 11's own dark bars, e.g. Notepad's before
    /// its redesign, use these). `0xRRGGBB`.
    public struct MenuBarTheme: Equatable, Sendable {
        public var background: UInt32
        public var text: UInt32
        public var disabledText: UInt32
        public var hotBackground: UInt32
        public var selectedBackground: UInt32
        /// The one-pixel line user32 leaves under the bar, repainted in `background`'s colour.
        public var underline: UInt32 { background }
    }
    public static let darkMenuBarTheme = MenuBarTheme(background: 0x20_20_20, text: 0xFF_FF_FF, disabledText: 0x80_80_80,
                                                      hotBackground: 0x3A_3A_3A, selectedBackground: 0x45_45_45)

    /// Whether the bar is owner-drawn: only in the dark app theme (light bars are user32's,
    /// unchanged), and only on a window that carries the HMENU bar.
    public static func drawsMenuBarItself(systemAppThemeIsDark: Bool, hasNativeMenuBar: Bool) -> Bool {
        systemAppThemeIsDark && hasNativeMenuBar
    }

    public static let ODS_SELECTED: UInt32 = 0x0001
    public static let ODS_GRAYED: UInt32 = 0x0002
    public static let ODS_DISABLED: UInt32 = 0x0004
    public static let ODS_HOTLIGHT: UInt32 = 0x0040
    public static let ODS_INACTIVE: UInt32 = 0x0080
    public static let ODS_NOACCEL: UInt32 = 0x0100

    /// The fill and text colours of one bar item for its `DRAWITEMSTRUCT.itemState`.
    public static func menuBarItemColors(itemState: UInt32, theme: MenuBarTheme = darkMenuBarTheme) -> (fill: UInt32, text: UInt32) {
        let disabled = itemState & (ODS_GRAYED | ODS_DISABLED) != 0
        let fill: UInt32
        if itemState & ODS_SELECTED != 0 { fill = theme.selectedBackground }
        else if itemState & ODS_HOTLIGHT != 0, !disabled { fill = theme.hotBackground }
        else { fill = theme.background }
        return (fill, disabled || itemState & ODS_INACTIVE != 0 ? theme.disabledText : theme.text)
    }

    // MARK: Non-client hit codes (WM_NCHITTEST)

    public static let HTCLIENT: Int32 = 1
    public static let HTCAPTION: Int32 = 2
    public static let HTMINBUTTON: Int32 = 8
    public static let HTMAXBUTTON: Int32 = 9
    public static let HTCLOSE: Int32 = 20

    /// The `WM_NCHITTEST` answer for what the window says a client point is. The standard
    /// buttons the package draws on a custom frame answer as the caption buttons would on
    /// a system frame, so Windows 11 shows its snap layouts flyout over the maximise
    /// button and the accessibility tree names them (ADR-0022).
    public static func hitCode(for region: PlatformWindowHitRegion) -> Int32 {
        switch region {
        case .client: return HTCLIENT
        case .caption: return HTCAPTION
        case .closeButton: return HTCLOSE
        case .miniaturizeButton: return HTMINBUTTON
        case .zoomButton: return HTMAXBUTTON
        }
    }

    /// Whether a non-client mouse message (`WM_NCMOUSEMOVE`, `WM_NCLBUTTONDOWN`, ...) is
    /// over one of the package-drawn caption buttons, so the window turns it into the
    /// mouse event the button tracks instead of leaving it to `DefWindowProc`.
    public static func isCaptionButton(hitCode: Int32) -> Bool {
        hitCode == HTCLOSE || hitCode == HTMINBUTTON || hitCode == HTMAXBUTTON
    }

    /// Whether the window takes a non-client mouse message (`WM_NCMOUSEMOVE`,
    /// `WM_NCLBUTTONDOWN`, `WM_NCLBUTTONUP`, ...) with hit code `hitCode` for a button it draws.
    /// Only a custom frame (`fullSizeContentView`, borderless, content extended into the
    /// title bar) has package-drawn caption buttons. On a system frame `HTCLOSE`,
    /// `HTMINBUTTON` and `HTMAXBUTTON` are Windows' own buttons, which `DefWindowProc` must
    /// track. If the window takes them, the minimise and maximise buttons do nothing.
    public static func takesNonClientMouse(hitCode: Int32, customFrame: Bool) -> Bool {
        customFrame && isCaptionButton(hitCode: hitCode)
    }

    // MARK: Showing (orderFront)

    public static let SW_SHOWNA: Int32 = 8

    /// The `ShowWindow` command behind `PlatformWindow.show()`, which `orderFront(_:)`
    /// calls. AppKit orders a window front without making it key (`makeKey()` activates
    /// it separately), so the window is shown in its current state without activation;
    /// the window is raised separately (`SWP_NOACTIVATE`). `SW_SHOWNORMAL`, used before,
    /// activated it: ordering the colour or font panel front took key from the document
    /// window, so the panel's `changeColor:` / `changeFont:` no longer reached the text view.
    public static let showCommand: Int32 = SW_SHOWNA
}
