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
