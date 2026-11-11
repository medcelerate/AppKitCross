// The Win32 window's creation-time redirection-bitmap decision: swap-chain windows drop
// the surface, but a window that carries the Win32 menu bar keeps it, since user32 draws
// the bar through GDI into that surface (a black strip without it, seen on the PC).
import XCTest
@testable import AppKit

final class Win32WindowPolicyTests: XCTestCase {
    private let app: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

    func testTitledWindowWithMenuBarKeepsTheSurface() {
        XCTAssertEqual(Win32WindowPolicy.redirectionBitmap(styleMask: app, applicationHasMenuBar: true, legacyTarget: false, presentationAvailable: true), .keptForMenuBar)
    }

    func testWindowsWithoutTheMenuBarDropTheSurface() {
        XCTAssertEqual(Win32WindowPolicy.redirectionBitmap(styleMask: app, applicationHasMenuBar: false, legacyTarget: false, presentationAvailable: true), .none)
        XCTAssertEqual(Win32WindowPolicy.redirectionBitmap(styleMask: app.union(.fullSizeContentView), applicationHasMenuBar: true, legacyTarget: false, presentationAvailable: true), .none)
        XCTAssertEqual(Win32WindowPolicy.redirectionBitmap(styleMask: [.borderless], applicationHasMenuBar: true, legacyTarget: false, presentationAvailable: true), .none)
        XCTAssertEqual(Win32WindowPolicy.redirectionBitmap(styleMask: [.titled, .utilityWindow], applicationHasMenuBar: true, legacyTarget: false, presentationAvailable: true), .none)
        XCTAssertEqual(Win32WindowPolicy.redirectionBitmap(styleMask: [.borderless, .nonactivatingPanel], applicationHasMenuBar: true, legacyTarget: false, presentationAvailable: true), .none)
    }

    func testRequestedSurfaceWins() {
        XCTAssertEqual(Win32WindowPolicy.redirectionBitmap(styleMask: app.union(.fullSizeContentView), applicationHasMenuBar: false, legacyTarget: false, presentationAvailable: true, requested: true), .keptByRequest)
        XCTAssertTrue(Win32WindowPolicy.RedirectionBitmap.keptByRequest.keeps)
    }

    func testLegacyAndDevicelessPathsKeepTheSurface() {
        XCTAssertEqual(Win32WindowPolicy.redirectionBitmap(styleMask: [.borderless], applicationHasMenuBar: false, legacyTarget: true, presentationAvailable: true), .keptForLegacyTarget)
        XCTAssertEqual(Win32WindowPolicy.redirectionBitmap(styleMask: [.borderless], applicationHasMenuBar: false, legacyTarget: false, presentationAvailable: false), .keptForMissingDevice)
        XCTAssertTrue(Win32WindowPolicy.RedirectionBitmap.keptForMenuBar.keeps)
        XCTAssertFalse(Win32WindowPolicy.RedirectionBitmap.none.keeps)
    }

    /// The WM_NCHITTEST answer for what the window says a point is: the package-drawn
    /// standard buttons answer as the caption buttons (ADR-0022), which is what gives the
    /// Windows 11 snap layouts flyout over maximise.
    func testHitCodesForTheWindowsRegions() {
        XCTAssertEqual(Win32WindowPolicy.hitCode(for: .client), 1)        // HTCLIENT
        XCTAssertEqual(Win32WindowPolicy.hitCode(for: .caption), 2)       // HTCAPTION
        XCTAssertEqual(Win32WindowPolicy.hitCode(for: .miniaturizeButton), 8)   // HTMINBUTTON
        XCTAssertEqual(Win32WindowPolicy.hitCode(for: .zoomButton), 9)    // HTMAXBUTTON
        XCTAssertEqual(Win32WindowPolicy.hitCode(for: .closeButton), 20)  // HTCLOSE
        for region in [PlatformWindowHitRegion.closeButton, .miniaturizeButton, .zoomButton] {
            XCTAssertTrue(Win32WindowPolicy.isCaptionButton(hitCode: Win32WindowPolicy.hitCode(for: region)))
        }
        XCTAssertFalse(Win32WindowPolicy.isCaptionButton(hitCode: 2))
        XCTAssertFalse(Win32WindowPolicy.isCaptionButton(hitCode: 12))    // HTTOP: the resize band over the buttons
    }
}
