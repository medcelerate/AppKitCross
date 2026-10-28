// Milestone 3b (AppKit side): window chrome derived from NSWindow properties, drag
// regions for content that extends into the title bar, and NSVisualEffectView backdrops.

import XCTest
@testable import AppKit

@MainActor
final class WindowChromeTests: XCTestCase {
    private func host(_ w: NSWindow) -> HostWindow { Mirror(reflecting: w).descendant("_platform") as! HostWindow }

    func testChromeFollowsWindowProperties() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        var c = host(w).chrome
        XCTAssertTrue(c.extendsContentIntoTitleBar)
        XCTAssertFalse(c.hidesTitle)
        XCTAssertFalse(c.isTransparent)
        XCTAssertEqual(c.backdrop, .none)
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isOpaque = false
        w.hasShadow = false
        w.isMovableByWindowBackground = true
        c = host(w).chrome
        XCTAssertTrue(c.hidesTitle && c.transparentTitleBar && c.isTransparent && c.movableByBackground)
        XCTAssertFalse(c.hasShadow)
        // A borderless window hides its title and covers the frame.
        let b = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        XCTAssertTrue(host(b).chrome.hidesTitle)
        XCTAssertTrue(host(b).chrome.extendsContentIntoTitleBar)
        w.close(); b.close()
    }

    func testDragRegions() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        let button = NSButton(title: "Close", target: nil, action: nil)
        button.frame = NSRect(x: 10, y: 160, width: 80, height: 28)
        w.contentView!.addSubview(button)
        // Top band drags the window; a button there does not; the body is content.
        XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 200, y: 190)), .caption)
        XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 20, y: 170)), .client)
        XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 150, y: 100)), .client)
        w.isMovableByWindowBackground = true
        XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 150, y: 100)), .caption)
        XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 20, y: 170)), .client)
        w.close()
    }

    func testVisualEffectViewRequestsBackdropAndDrawsTint() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        effect.material = .sidebar
        w.contentView!.addSubview(effect)
        XCTAssertEqual(host(w).chrome.backdrop, .mica)
        effect.material = .hudWindow
        XCTAssertEqual(host(w).chrome.backdrop, .acrylic)
        effect.blendingMode = .withinWindow
        XCTAssertEqual(host(w).chrome.backdrop, .none)
        effect.material = .sidebar
        effect.blendingMode = .behindWindow
        w.isOpaque = false
        w.backgroundColor = .clear
        w.makeKeyAndOrderFront(nil)
        w.display()
        // The tint is translucent: the pixel is lighter than the HUD material would be but not opaque white.
        let platform = host(w)
        let image = platform.lastImage!
        let data = image.dataProvider!.data! as Data
        let i = (image.height - 1 - 100) * image.bytesPerRow + 100 * 4
        let alpha = data[i + 3]
        XCTAssertGreaterThan(alpha, 20)
        XCTAssertLessThan(alpha, 250)
        effect.removeFromSuperview()
        w.close()
    }
}
