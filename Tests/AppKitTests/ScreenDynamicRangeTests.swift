// NSScreen's extended dynamic range members (ADR-0016): an SDR display reports a
// headroom of 1 (nothing brighter than white), no reference mode, and the values a
// backend puts on its PlatformDisplay reach the screen unchanged.
import XCTest
@testable import AppKit

final class ScreenDynamicRangeTests: XCTestCase, @unchecked Sendable {
    func testHostDisplayIsSDR() {
        MainActor.assumeIsolated {
            guard let s = NSScreen.screens.first else { return XCTFail("no screen") }
            XCTAssertEqual(s.maximumExtendedDynamicRangeColorComponentValue, 1)
            XCTAssertEqual(s.maximumPotentialExtendedDynamicRangeColorComponentValue, 1)
            XCTAssertEqual(s.maximumReferenceExtendedDynamicRangeColorComponentValue, 0)
        }
    }

    func testHeadroomComesFromTheBackend() {
        MainActor.assumeIsolated {
            let backend = Platform.backend as! HostBackend
            let saved = backend.displays
            defer { backend.displays = saved }
            backend.displays.append(PlatformDisplay(frame: NSRect(x: 1920, y: 0, width: 1280, height: 1024),
                                                    visibleFrame: NSRect(x: 1920, y: 0, width: 1280, height: 1000),
                                                    backingScaleFactor: 1, localizedName: "HDR Display", isMain: false,
                                                    maximumEDRValue: 5, maximumPotentialEDRValue: 12.5, maximumReferenceEDRValue: 0))
            guard let hdr = NSScreen.screens.first(where: { $0.localizedName == "HDR Display" }) else { return XCTFail("display missing") }
            XCTAssertEqual(hdr.maximumExtendedDynamicRangeColorComponentValue, 5)
            XCTAssertEqual(hdr.maximumPotentialExtendedDynamicRangeColorComponentValue, 12.5)
            XCTAssertEqual(hdr.maximumReferenceExtendedDynamicRangeColorComponentValue, 0)
            let w = NSWindow(contentRect: NSRect(x: 2000, y: 100, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            w.makeKeyAndOrderFront(nil)
            defer { w.close() }
            XCTAssertEqual(w.screen?.maximumExtendedDynamicRangeColorComponentValue, 5)
        }
    }
}
