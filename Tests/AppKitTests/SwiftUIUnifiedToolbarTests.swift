// The unified title-bar toolbar of a SwiftUI window (macOS 11 look): `.automatic` resolves
// to unified, buttons with a `Label` become icon-only image items, the title and subtitle
// lead the band, and the trailing title bar accessory shares the band's row.

import XCTest
@testable import AppKit
@testable import SwiftUI

final class SwiftUIUnifiedToolbarTests: XCTestCase, @unchecked Sendable {
    @MainActor private func host<V: View>(_ view: V, width: CGFloat = 700) -> (NSWindow, NSHostingView<V>) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 300), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        let h = NSHostingView(rootView: view)
        h.frame = NSRect(x: 0, y: 0, width: width, height: 300)
        h.autoresizingMask = [.width, .height]
        w.contentView = h
        w.makeKeyAndOrderFront(nil)
        (Platform.backend as! HostBackend).drain()
        return (w, h)
    }

    @MainActor private final class Model: ObservableObject {
        @Published var tapped: [String] = []
        @Published var running = false
    }

    /// The Sibyl main window's toolbar, cut down: a Label button with help and a
    /// conditional symbol, a `Button(_:systemImage:)` that is disabled, one with a
    /// keyboard shortcut, and a group of image buttons.
    private struct Content: View {
        @ObservedObject var model: Model
        var showsGroup = false
        var body: some View {
            Text("Body")
                .navigationTitle("New Show")
                .navigationSubtitle("Stopped")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { model.tapped.append("start"); model.running.toggle() } label: {
                            Label(model.running ? "Stop" : "Start", systemImage: model.running ? "stop.fill" : "play.fill")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .animation(nil, value: model.running)
                        .help("Start capture and transcription")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Post-Show", systemImage: "chart.bar.doc.horizontal") { model.tapped.append("report") }
                            .keyboardShortcut("r", modifiers: [.command, .shift])
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { model.tapped.append("inspector") } label: { Label("Inspector", systemImage: "sidebar.trailing") }
                            .disabled(true)
                    }
                    if showsGroup {
                        ToolbarItemGroup {
                            Button("Fit to Window", systemImage: "arrow.left.and.right.square") { model.tapped.append("fit") }
                                .help("Divide the visible width evenly")
                            Button("Expand All", systemImage: "rectangle.expand.vertical") { model.tapped.append("expand") }
                            Button("Reset Columns", systemImage: "arrow.counterclockwise") { model.tapped.append("reset") }
                        }
                    }
                }
        }
    }

    @MainActor private func items(_ tb: NSToolbar) -> [NSToolbarItem] { tb.items.filter { $0.itemIdentifier != .flexibleSpace } }
    @MainActor private func button(for item: NSToolbarItem, in view: _NSToolbarView) -> _NSToolbarItemButton? {
        view.subviews.compactMap { $0 as? _NSToolbarItemButton }.first { $0.item === item }
    }

    func testAutomaticResolvesToUnifiedForASwiftUIToolbar() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let (w, _) = host(Content(model: Model()))
            defer { w.close() }
            XCTAssertNotNil(w.toolbar as? _SwiftUIToolbar)
            XCTAssertEqual(w.toolbarStyle, .automatic, "the app sets no style")
            guard let m = w._toolbarMetrics else { return XCTFail("no toolbar metrics") }
            XCTAssertTrue(m.isUnified, "automatic is unified for a window with a toolbar (macOS 11)")
            XCTAssertEqual(m.height, 52)
            XCTAssertFalse(m.showsLabels, "the unified style shows icons only")
            XCTAssertTrue(m.showsIcons)
            XCTAssertEqual(m.placement, .belowTitleBar, "the system title bar stays; the band sits right under it")
            // Explicit styles keep their own look.
            w.toolbarStyle = .expanded
            XCTAssertFalse(w._toolbarMetrics!.isUnified)
            XCTAssertTrue(w._toolbarMetrics!.showsLabels)
            w.toolbarStyle = .unifiedCompact
            XCTAssertTrue(w._toolbarMetrics!.isUnified)
            XCTAssertEqual(w._toolbarMetrics!.height, 38)
        }
    }

    func testLabelButtonsBecomeIconOnlyImageItems() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let model = Model()
            let (w, h) = host(Content(model: model))
            defer { w.close() }
            guard let tb = w.toolbar, let view = tb._view else { return XCTFail("no toolbar") }
            w.display()
            let its = items(tb)
            XCTAssertEqual(its.map { $0.label }, ["Start", "Post-Show", "Inspector"])
            for item in its {
                XCTAssertNil(item.view, "\(item.label) is drawn by the toolbar, not hosted")
                XCTAssertNotNil(item.image, "\(item.label) has the symbol as its image")
                XCTAssertEqual(item.paletteLabel, item.label)
            }
            XCTAssertEqual(its[0].toolTip, "Start capture and transcription", ".help is the tool tip")
            XCTAssertEqual(its[1].toolTip, "Post-Show", "without .help the title is the tool tip")
            XCTAssertTrue(its[0].isEnabled)
            XCTAssertFalse(its[2].isEnabled, ".disabled carries over")
            // Icon only: the button is the standard width, shows the image and no label is drawn.
            guard let start = button(for: its[0], in: view) else { return XCTFail("no button for Start") }
            XCTAssertTrue(start.showsIcon)
            XCTAssertEqual(start.frame.width, view.metrics.buttonSize.width, "an icon-only button, no title width")
            XCTAssertEqual(start.toolTip, "Start capture and transcription")
            XCTAssertFalse(view.metrics.showsLabels)
            XCTAssertFalse(button(for: its[2], in: view)!.isEnabled)
            // Clicking runs the action; the re-render swaps the label and the symbol in place.
            let before = its[0].image
            start.performClick(nil)
            XCTAssertEqual(model.tapped, ["start"])
            (Platform.backend as! HostBackend).drain()
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(items(tb)[0].label, "Stop")
            XCTAssertFalse(items(tb)[0].image === before, "stop.fill replaced play.fill")
            XCTAssertTrue(items(tb)[0] === its[0], "the same item is kept across renders")
            // A disabled item does not fire.
            button(for: its[2], in: view)!.performClick(nil)
            XCTAssertEqual(model.tapped, ["start"])
            // The keyboard shortcut fires the item from the window.
            let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0, windowNumber: w.windowNumber, context: nil,
                                     characters: "r", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15)!
            w.sendEvent(e)
            XCTAssertEqual(model.tapped, ["start", "report"])
        }
    }

    func testTitleAndSubtitleLeadTheUnifiedBand() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let (w, _) = host(Content(model: Model()))
            defer { w.close() }
            guard let tb = w.toolbar, let view = tb._view else { return XCTFail("no toolbar") }
            XCTAssertEqual(w.title, "New Show")
            XCTAssertEqual(w.subtitle, "Stopped")
            view.layoutSubtreeIfNeeded()
            guard let title = view._titleFrame else { return XCTFail("the unified band shows no title") }
            XCTAssertEqual(title.minX, view.metrics.leadingInset, "the title leads the row")
            let first = view._frame(ofItem: items(tb)[0])!
            XCTAssertGreaterThanOrEqual(first.minX, title.maxX, "the items follow the title")
            // The expanded style has the title in the title bar, not in the band.
            w.toolbarStyle = .expanded
            view.layoutSubtreeIfNeeded()
            XCTAssertNil(view._titleFrame)
            // Nor does a hidden title show.
            w.toolbarStyle = .automatic
            w.titleVisibility = .hidden
            view.layoutSubtreeIfNeeded()
            XCTAssertNil(view._titleFrame)
        }
    }

    func testTrailingAccessorySharesTheToolbarRow() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let (w, _) = host(Content(model: Model()))
            defer { w.close() }
            guard let tb = w.toolbar, let view = tb._view else { return XCTFail("no toolbar") }
            let heightWithToolbar = w.frame.height
            let accessory = NSTitlebarAccessoryViewController()
            accessory.view = NSView(frame: NSRect(x: 0, y: 0, width: 90, height: 24))
            accessory.layoutAttribute = .trailing
            w.addTitlebarAccessoryViewController(accessory)
            w.display()
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(w.frame.height, heightWithToolbar, "no strip of its own: the accessory goes into the toolbar's row")
            let band = view.frame
            let a = accessory.view.frame          // both in the platform content area's coordinates
            XCTAssertGreaterThanOrEqual(a.minY, band.minY)
            XCTAssertLessThanOrEqual(a.maxY, band.maxY)
            XCTAssertEqual(a.midY, band.midY, accuracy: 1, "centred in the same band as the items")
            XCTAssertEqual(a.maxX, band.maxX - 8, "at the trailing end")
            // The items stop before it, and sit in the same row.
            for item in items(tb) {
                guard let f = view._frame(ofItem: item) else { return XCTFail("\(item.label) not shown") }
                let inWindow = view.convert(f, to: nil)
                XCTAssertLessThanOrEqual(inWindow.maxX, a.minX, "\(item.label) stops before the accessory")
                XCTAssertEqual(inWindow.midY, a.midY, accuracy: 2, "\(item.label) shares the accessory's row")
            }
            // With the expanded style the accessory keeps a strip of its own under the title bar.
            w.toolbarStyle = .expanded
            XCTAssertGreaterThan(w.frame.height, heightWithToolbar)
            XCTAssertGreaterThan(accessory.view.frame.minY, view.frame.maxY - 1, "above the expanded band")
        }
    }

    func testExpandedStyleShowsLabelsUnderTheIcons() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let (w, _) = host(Content(model: Model()))
            defer { w.close() }
            w.toolbarStyle = .expanded
            guard let tb = w.toolbar, let view = tb._view else { return XCTFail("no toolbar") }
            w.display()
            view.layoutSubtreeIfNeeded()
            XCTAssertTrue(view.metrics.showsLabels, "expanded shows the title text")
            XCTAssertTrue(view.metrics.showsIcons, "above it, the symbol")
            XCTAssertEqual(view.metrics.height, 56)
            let start = items(tb)[0]
            XCTAssertNotNil(start.image)
            XCTAssertEqual(start.label, "Start")
            guard let slot = view._frame(ofItem: start) else { return XCTFail("Start not shown") }
            XCTAssertLessThan(slot.maxY + 14, view.bounds.height, "room under the icon for the label")
        }
    }

    func testGroupOfImageButtonsSplitsIntoItems() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let model = Model()
            let (w, _) = host(Content(model: model, showsGroup: true), width: 900)
            defer { w.close() }
            guard let tb = w.toolbar, let view = tb._view else { return XCTFail("no toolbar") }
            w.display()
            let its = items(tb)
            XCTAssertEqual(its.map { $0.label }, ["Start", "Post-Show", "Inspector", "Fit to Window", "Expand All", "Reset Columns"])
            XCTAssertTrue(its.allSatisfy { $0.view == nil && $0.image != nil })
            XCTAssertEqual(its[3].toolTip, "Divide the visible width evenly")
            button(for: its[5], in: view)?.performClick(nil)
            XCTAssertEqual(model.tapped, ["reset"])
        }
    }
}
