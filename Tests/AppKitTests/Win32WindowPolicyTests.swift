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

    /// Who handles a non-client press or release, for every hit code a caption can answer.
    /// A custom frame takes presses on the buttons it draws. A system frame leaves every code
    /// to DefWindowProc: when it took HTMINBUTTON and HTMAXBUTTON, a click on Windows' own
    /// minimise or maximise button did nothing, although the snap layouts flyout still showed.
    func testOnlyCustomFramesTakeCaptionButtonPresses() {
        let table: [(code: Int32, name: String, customFrameTakes: Bool)] = [
            (0, "HTNOWHERE", false), (1, "HTCLIENT", false), (2, "HTCAPTION", false), (3, "HTSYSMENU", false),
            (8, "HTMINBUTTON", true), (9, "HTMAXBUTTON", true), (10, "HTLEFT", false), (11, "HTRIGHT", false),
            (12, "HTTOP", false), (13, "HTTOPLEFT", false), (14, "HTTOPRIGHT", false), (15, "HTBOTTOM", false),
            (16, "HTBOTTOMLEFT", false), (17, "HTBOTTOMRIGHT", false), (18, "HTBORDER", false),
            (20, "HTCLOSE", true), (21, "HTHELP", false),
        ]
        for row in table {
            XCTAssertEqual(Win32WindowPolicy.takesNonClientMouse(hitCode: row.code, customFrame: true), row.customFrameTakes,
                           "custom frame, \(row.name)")
            XCTAssertFalse(Win32WindowPolicy.takesNonClientMouse(hitCode: row.code, customFrame: false),
                           "system frame, \(row.name) must go to DefWindowProc")
        }
    }

    /// `orderFront(_:)` shows without activating (SW_SHOWNA): a panel ordered front leaves
    /// the document window key, as in AppKit; `makeKey()` is what activates.
    func testOrderFrontShowsWithoutActivating() {
        XCTAssertEqual(Win32WindowPolicy.showCommand, 8)                  // SW_SHOWNA
        XCTAssertNotEqual(Win32WindowPolicy.showCommand, 1)               // not SW_SHOWNORMAL, which activates
    }
}
