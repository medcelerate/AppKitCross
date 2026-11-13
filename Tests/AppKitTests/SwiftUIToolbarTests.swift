// SwiftUI `.toolbar { ToolbarItem(placement:) { } }` over NSToolbar (ADR-0018).

import XCTest
@testable import AppKit
@testable import SwiftUI

final class SwiftUIToolbarTests: XCTestCase, @unchecked Sendable {
    @MainActor private func host<V: View>(_ view: V, mask: NSWindow.StyleMask = [.titled, .closable, .resizable]) -> (NSWindow, NSHostingView<V>) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: mask, backing: .buffered, defer: false)
        let h = NSHostingView(rootView: view)
        h.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        h.autoresizingMask = [.width, .height]
        w.contentView = h
        w.makeKeyAndOrderFront(nil)
        (Platform.backend as! HostBackend).drain()
        return (w, h)
    }

    @MainActor private final class Model: ObservableObject {
        @Published var tapped: [String] = []
        @Published var showsExtra = false
    }

    private struct Content: View {
        @ObservedObject var model: Model
        var body: some View {
            Text("Body")
                .toolbar {
                    ToolbarItem(placement: .navigation) { Button("Back") { model.tapped.append("back") } }
                    ToolbarItem(placement: .principal) { Text("Title \(model.tapped.count)") }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Share") { model.tapped.append("share") }
                        Button("Add") { model.tapped.append("add") }
                    }
                    if model.showsExtra { ToolbarItem(id: "extra") { Button("Extra") { model.tapped.append("extra") } } }
                }
        }
    }

    func testItemsBecomeToolbarItemsInPlacementOrder() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let model = Model()
            let (w, h) = host(Content(model: model))
            defer { w.close() }
            guard let tb = w.toolbar as? _SwiftUIToolbar else { return XCTFail("no toolbar on the window") }
            XCTAssertTrue(tb.isVisible)
            XCTAssertEqual(tb.items.count, 4, "navigation, principal, a flexible space, the group")
            XCTAssertEqual(tb.items[2].itemIdentifier, .flexibleSpace)
            XCTAssertEqual(tb.centeredItemIdentifiers, [tb.items[1].itemIdentifier])
            XCTAssertTrue(tb.items.allSatisfy { $0.itemIdentifier == .flexibleSpace || $0.view is NSHostingView<AnyView> })
            w.display()
            let view = tb._view!
            XCTAssertGreaterThan(w.frame.height, 300 + 28, "the window grew by the toolbar band")
            // The items are laid out in the band, navigation first.
            let frames = tb.items.filter { $0.view != nil }.map { $0.view!.frame }
            XCTAssertEqual(frames.count, 3)
            XCTAssertLessThan(frames[0].minX, frames[1].minX)
            XCTAssertLessThan(frames[1].minX, frames[2].minX)
            XCTAssertTrue(frames.allSatisfy { view.bounds.contains($0) }, "\(frames) in \(view.bounds)")
            // Clicking a hosted button runs its action.
            let backButton = tb.items[0].view!.subviews.first { $0 is NSButton } as? NSButton
            XCTAssertNotNil(backButton)
            backButton?.performClick(nil)
            XCTAssertEqual(model.tapped, ["back"])
            // State changes re-render the hosted content; a conditional item appears and goes.
            (Platform.backend as! HostBackend).drain()
            h.layoutSubtreeIfNeeded()
            model.showsExtra = true
            (Platform.backend as! HostBackend).drain()
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(tb.items.count, 5)
            XCTAssertEqual(tb.items.last?.itemIdentifier.rawValue, "extra")
            XCTAssertEqual(tb.items.last?.label, "extra")
            model.showsExtra = false
            (Platform.backend as! HostBackend).drain()
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(tb.items.count, 4)
        }
    }

    func testHiddenToolbarAndWindowToolbarStyle() throws {
        try requireHostBackend("needs the host backend's rendered window (APPKITWIN_HOST_BACKEND=1)")
        MainActor.assumeIsolated {
            let (w, _) = host(Text("x").toolbar { ToolbarItem { Text("One") } }.toolbar(.hidden, for: .windowToolbar))
            defer { w.close() }
            guard let tb = w.toolbar else { return XCTFail("no toolbar") }
            XCTAssertFalse(tb.isVisible)
            XCTAssertEqual(w.frame.height, 328, "a hidden toolbar takes no band")
            XCTAssertEqual(UnifiedWindowToolbarStyle(showsTitle: false)._toolbarStyle, .unified)
            XCTAssertEqual(ExpandedWindowToolbarStyle()._toolbarStyle, .expanded)
            XCTAssertEqual(UnifiedCompactWindowToolbarStyle()._toolbarStyle, .unifiedCompact)
        }
    }
}

