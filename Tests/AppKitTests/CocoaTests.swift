import XCTest
import Cocoa

/// `import Cocoa` alone must bring AppKit and Foundation into scope, as on macOS.
final class CocoaTests: XCTestCase, @unchecked Sendable {
    func testUmbrellaReexportsAppKitAndFoundation() {
        MainActor.assumeIsolated {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            window.title = "Cocoa"
            XCTAssertEqual(window.title, "Cocoa")
            XCTAssertNotNil(NSApplication.shared)
            let data = Data("umbrella".utf8)
            XCTAssertEqual(String(decoding: data, as: UTF8.self), "umbrella")
            XCTAssertEqual(NSString(string: "a").appending("b"), "ab")
            window.close()
        }
    }

    func testCanImportCocoaIsTrueHere() {
        #if canImport(Cocoa)
        XCTAssertTrue(true)
        #else
        XCTFail("canImport(Cocoa) should hold on every platform the port builds for")
        #endif
    }
}
