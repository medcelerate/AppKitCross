// Milestone 6: the SwiftUI hosting seam — a hosted root that measures, lays out, draws
// and takes events through NSHostingView / NSHostingController, and representables.

import XCTest
@testable import AppKit

/// A stand-in for a SwiftUI view tree: a coloured block of a given size.
struct BlockContent: NSHostingContent {
    var size: NSSize
    var color: NSColor

    @MainActor final class Root: NSHostingRoot {
        var content: BlockContent
        weak var host: (any NSHostingRootHost)?
        var layouts: [NSRect] = []
        var draws = 0
        var clicks = 0
        var attached = false
        var environment: NSHostingEnvironment?

        init(_ c: BlockContent) { content = c }

        func attach(to host: any NSHostingRootHost) { self.host = host; attached = true }
        func detach() { attached = false }
        func contentDidChange() { host?.invalidateIntrinsicContentSize(); host?.setNeedsDisplay(in: nil) }
        func environmentDidChange(_ environment: NSHostingEnvironment) { self.environment = environment }
        func sizeThatFits(_ proposal: NSHostingSizeProposal) -> NSSize {
            NSSize(width: min(proposal.width ?? content.size.width, content.size.width), height: min(proposal.height ?? content.size.height, content.size.height))
        }
        func layout(in bounds: NSRect) { layouts.append(bounds) }
        func draw(_ dirtyRect: NSRect, in context: NSGraphicsContext) {
            draws += 1
            content.color.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: content.size)).fill()
        }
        func handle(_ event: NSEvent) -> Bool {
            if event.type == .leftMouseDown { clicks += 1; return true }
            return false
        }
    }

    @MainActor func _makeHostingRoot() -> any NSHostingRoot { Root(self) }
    @MainActor func _updateHostingRoot(_ root: any NSHostingRoot) { (root as? Root)?.content = self }
}

final class HostingTests: XCTestCase, @unchecked Sendable {
    @MainActor private func pixel(_ w: NSWindow, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let platform = Mirror(reflecting: w).descendant("_platform") as? HostWindow
        let image = platform!.lastImage!
        let data = _pixels(image)
        let row = image.height - 1 - y * 2
        let i = row * image.bytesPerRow + x * 2 * 4
        return (data[i + 2], data[i + 1], data[i])
    }

    func testHostingViewMeasuresLaysOutDrawsAndRoutesEvents() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let hosting = NSHostingView(rootView: BlockContent(size: NSSize(width: 60, height: 40), color: .red))
            let root = hosting.hostingRoot as! BlockContent.Root
            XCTAssertTrue(root.attached)
            XCTAssertNotNil(hosting.layer, "hosting views are layer-backed")
            XCTAssertEqual(hosting.intrinsicContentSize, NSSize(width: 60, height: 40))
            XCTAssertEqual(hosting.sizeThatFits(NSHostingSizeProposal(width: 30, height: nil)), NSSize(width: 30, height: 40))
            // In a window, pinned with Auto Layout: the intrinsic size sizes it.
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            w.contentView!.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor, constant: 10),
                hosting.bottomAnchor.constraint(equalTo: w.contentView!.bottomAnchor, constant: -10),
            ])
            w.makeKeyAndOrderFront(nil)
            w.display()
            XCTAssertEqual(hosting.frame, NSRect(x: 10, y: 10, width: 60, height: 40))
            XCTAssertEqual(root.layouts.last, NSRect(x: 0, y: 0, width: 60, height: 40))
            XCTAssertGreaterThan(root.draws, 0)
            XCTAssertEqual(root.environment?.isKeyWindow, true)
            let p = pixel(w, 20, 20)
            XCTAssertGreaterThan(p.r, 200); XCTAssertLessThan(p.g, 30)
            // Replacing the content updates the root in place and re-measures.
            hosting.rootView = BlockContent(size: NSSize(width: 80, height: 20), color: .blue)
            XCTAssertTrue(hosting.hostingRoot === root)
            w.layoutIfNeeded()
            XCTAssertEqual(hosting.frame.size, NSSize(width: 80, height: 20))
            w.display()
            let q = pixel(w, 20, 15)
            XCTAssertGreaterThan(q.b, 200)
            // Events reach the root first.
            let click = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 20, y: 15), modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            w.sendEvent(click)
            XCTAssertEqual(root.clicks, 1)
            w.close()
        }
    }

    func testHostingControllerSizesItsWindow() {
        MainActor.assumeIsolated {
            let hc = NSHostingController(rootView: BlockContent(size: NSSize(width: 120, height: 90), color: .green))
            hc.sizingOptions = [.preferredContentSize]
            let w = NSWindow(contentViewController: hc)
            XCTAssertEqual(w.contentView!.frame.size, NSSize(width: 120, height: 90))
            XCTAssertEqual(hc.preferredContentSize, NSSize(width: 120, height: 90))
            XCTAssertEqual(hc.sizeThatFits(in: NSSize(width: 50, height: 500)), NSSize(width: 50, height: 90))
            hc.rootView = BlockContent(size: NSSize(width: 10, height: 10), color: .green)
            XCTAssertEqual(hc.hostingView.intrinsicContentSize, NSSize(width: 10, height: 10))
            w.close()
        }
    }
}

