// What one frame of a scrolling AppKit scroll view costs with the backing-store copy
// engaged: the Glass example's window (a scroll view filling the content, a few controls
// floating over it, a toolbar) scrolled two points a frame. On Windows the copy ran every
// frame, yet each paint was six rectangles whose union was the whole content.

import XCTest
@testable import AppKit
@testable import SwiftUI

private final class _BandsView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        for i in 0..<Int(bounds.height / 90) {
            NSColor(calibratedHue: CGFloat(i % 10) / 10, saturation: 0.5, brightness: 0.9, alpha: 1).setFill()
            NSRect(x: 0, y: CGFloat(i) * 90, width: bounds.width, height: 90).fill()
        }
    }
}

private final class _ScrollDelegate: NSObject, NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.init("a"), .flexibleSpace, .init("b")] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.init("a"), .init("b"), .flexibleSpace] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = id.rawValue
        item.image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { r in NSColor.labelColor.setFill(); r.insetBy(dx: 6, dy: 6).fill(); return true }
        return item
    }
}

final class ScrollFrameCostTests: XCTestCase, @unchecked Sendable {
    func testTwoPointScrollPaintsTheExposedStripAndTheMovedControls() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let window = NSWindow(contentRect: NSRect(x: 160, y: 120, width: 900, height: 600), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            let content = window.contentView!
            let scroll = NSScrollView(frame: content.bounds)
            scroll.autoresizingMask = [.width, .height]
            scroll.hasVerticalScroller = true
            let document = _BandsView(frame: NSRect(x: 0, y: 0, width: 900, height: 2700))
            document.autoresizingMask = [.width]
            scroll.documentView = document
            content.addSubview(scroll)
            // Controls floating over the scroll view, as the Glass example has.
            let box = NSBox(frame: NSRect(x: 30, y: 30, width: 260, height: 44))
            box.autoresizingMask = [.maxXMargin, .maxYMargin]
            content.addSubview(box)
            let button = NSButton(title: "Next", target: nil, action: nil)
            button.frame = NSRect(x: 320, y: 30, width: 150, height: 44)
            content.addSubview(button)
            let hosting = NSHostingView(rootView: HStack { Button("Glass") {}; Text("Interactive").padding(6) })
            let size = hosting.fittingSize
            hosting.frame = NSRect(x: content.bounds.width - size.width - 24, y: content.bounds.height - size.height - 24, width: size.width, height: size.height)
            hosting.autoresizingMask = [.minXMargin, .minYMargin]
            content.addSubview(hosting)
            let delegate = _ScrollDelegate()
            let toolbar = NSToolbar(identifier: "scroll.cost")
            toolbar.delegate = delegate
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            guard let host = window._platformWindow as? HostWindow else { XCTFail("not the host backend"); return }
            var frames = 0
            while host._needsPaint, frames < 10 { host.displayIfNeeded(); frames += 1 }
            XCTAssertFalse(host._needsPaint, "idle")
            let clip = scroll.contentView
            let clipInWindow = clip.convert(clip.bounds, to: nil)
            let contentArea = content.bounds.width * content.bounds.height

            var marks: [(String, NSRect)] = []
            NSView._invalidationObserver = { v, r in MainActor.assumeIsolated { if v.window === window { marks.append(("\(type(of: v))", v._dirtyRectInWindow(r))) } } }
            defer { NSView._invalidationObserver = nil }
            // Warm up one frame (the first scroll shows the overlay scroller), then measure.
            for step in 0..<4 {
                marks = []
                let copies = host.scrollCopyCount
                var origin = clip.bounds.origin
                origin.y += 2
                clip.scroll(to: origin)
                scroll.reflectScrolledClipView(clip)
                var area: CGFloat = 0, rects: [NSRect] = [], paints = 0
                frames = 0
                while host._needsPaint, frames < 6 {
                    let n = host.paintCount
                    host.displayIfNeeded(); frames += 1
                    if host.paintCount != n { area += window._lastPaintArea; rects += window._lastPaintRects; paints += 1 }
                }
                print("ScrollFrameCostTests step \(step): \(paints) paints, \(Int(area)) pt² of \(Int(contentArea)), rects \(rects.map { "\(Int($0.width))x\(Int($0.height))@\(Int($0.minX)),\(Int($0.minY))" }); marks \(marks.map { "\($0.0) \(Int($0.1.width))x\(Int($0.1.height))@\(Int($0.1.minX)),\(Int($0.1.minY))" })")
                XCTAssertEqual(host.scrollCopyCount, copies + 1, "step \(step): the copy engaged")
                if step > 0 {
                    // What a 2 pt scroll inherently repaints: the exposed strip, each translucent
                    // control floating over the content where it was and where its pixels went
                    // (its height plus the step), and the scroller's knob in both places.
                    let overlays = [box, button, hosting].map { $0.convert($0.bounds, to: nil) }
                    let knob = scroll.verticalScroller!.rect(for: .knob)
                    let inherent = 2 * clipInWindow.width + overlays.reduce(0) { $0 + $1.width * ($1.height + 2) } + 2 * knob.width * knob.height
                    XCTAssertLessThanOrEqual(area, inherent * 1.05 + 100, "step \(step): the strip, the floating controls and the knob only (\(Int(area)) vs \(Int(inherent)); rects \(rects))")
                    XCTAssertLessThan(area, contentArea * 0.05, "step \(step): under 5% of the content (\(Int(area)) of \(Int(contentArea)))")
                    XCTAssertEqual(paints, 1, "step \(step): one paint, nothing re-marks itself from its draw")
                }
            }
        }
    }
}
