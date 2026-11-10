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

    func testLegacyAndDevicelessPathsKeepTheSurface() {
        XCTAssertEqual(Win32WindowPolicy.redirectionBitmap(styleMask: [.borderless], applicationHasMenuBar: false, legacyTarget: true, presentationAvailable: true), .keptForLegacyTarget)
        XCTAssertEqual(Win32WindowPolicy.redirectionBitmap(styleMask: [.borderless], applicationHasMenuBar: false, legacyTarget: false, presentationAvailable: false), .keptForMissingDevice)
        XCTAssertTrue(Win32WindowPolicy.RedirectionBitmap.keptForMenuBar.keeps)
        XCTAssertFalse(Win32WindowPolicy.RedirectionBitmap.none.keeps)
    }
}
