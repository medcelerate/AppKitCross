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
                                         legacyTarget: Bool, presentationAvailable: Bool) -> RedirectionBitmap {
        if legacyTarget { return .keptForLegacyTarget }
        if !presentationAvailable { return .keptForMissingDevice }
        if carriesMenuBar(styleMask, applicationHasMenuBar: applicationHasMenuBar) { return .keptForMenuBar }
        return .none
    }
}
