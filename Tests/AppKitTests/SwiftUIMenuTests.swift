// SwiftUI menus: pop-up Picker, Menu, contextMenu.

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor
private func host<V: View>(_ view: V, width: CGFloat = 320, height: CGFloat = 220) -> (NSWindow, NSHostingView<V>) {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
    let h = NSHostingView(rootView: view)
    h.frame = NSRect(x: 0, y: 0, width: width, height: height)
    w.contentView!.addSubview(h)
    w.makeKeyAndOrderFront(nil)
    h.layoutSubtreeIfNeeded()
    return (w, h)
}

@MainActor
private func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }
@MainActor
private func texts(_ v: NSView) -> [String] { allViews(v).compactMap { ($0 as? _TextView)?.storage.string } }
@MainActor
private func menuWindows() -> [_NSMenuWindow] { NSApplication.shared.windows.compactMap { $0 as? _NSMenuWindow }.filter { $0.isVisible } }

@MainActor
private func chooseRow(_ row: Int) {
    let w = menuWindows().last!
    let f = w.menuView.layout.rows[row].frame
    let p = w.menuView.convert(NSPoint(x: f.midX, y: f.midY), to: nil)
    for type in [NSEvent.EventType.mouseMoved, .leftMouseUp] {
        let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        NSApplication.shared.sendEvent(e)
    }
}

final class SwiftUIMenuTests: XCTestCase, @unchecked Sendable {
    func testMenuStylePickerIsAPopUpButtonInBothDirections() {
        MainActor.assumeIsolated {
            enum Size: String, CaseIterable { case small, medium, large }
            struct Probe: View {
                @State var size = Size.medium
                var body: some View {
                    VStack {
                        Picker("Size", selection: $size) {
                            ForEach(Size.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }
                        Text("picked \(size.rawValue)")
                        Button("Large") { size = .large }
                    }
                }
            }
            let (w, h) = host(Probe())
            let popUp = allViews(h).compactMap { $0 as? NSPopUpButton }.first
            XCTAssertNotNil(popUp, "the automatic style is a pop-up button on macOS")
            XCTAssertEqual(popUp?.itemTitles, ["Small", "Medium", "Large"])
            XCTAssertEqual(popUp?.titleOfSelectedItem, "Medium")
            XCTAssertTrue(texts(h).contains("Size"), "the label sits next to the control")
            // Choosing from the menu updates the state.
            popUp?.performClick(nil)
            XCTAssertEqual(menuWindows().count, 1)
            chooseRow(0)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("picked small"), texts(h).joined(separator: "|"))
            XCTAssertEqual(popUp?.titleOfSelectedItem, "Small")
            // Changing the state updates the control.
            allViews(h).compactMap { $0 as? NSButton }.first { $0.title == "Large" }?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(popUp?.titleOfSelectedItem, "Large")
            w.close()
        }
    }

    func testMenuViewBuildsAPullDownWithNestedItems() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var log = "none"
                @State var flag = false
                var body: some View {
                    VStack {
                        Menu("Actions") {
                            Button("Rename") { log = "rename" }
                            Toggle("Flag", isOn: $flag)
                            Divider()
                            Menu("Export") {
                                Button("PDF") { log = "pdf" }
                                Button("PNG") { log = "png" }
                            }
                            Text("hint")
                        }
                        Text("log \(log) flag \(flag)")
                    }
                }
            }
            let (w, h) = host(Probe())
            let button = allViews(h).compactMap { $0 as? NSPopUpButton }.first
            XCTAssertNotNil(button)
            XCTAssertTrue(button!.pullsDown)
            XCTAssertEqual(button!.title, "Actions")
            let items = button!.menu!.items
            XCTAssertEqual(items.map(\.title), ["Rename", "Flag", "", "Export", "hint"])
            XCTAssertTrue(items[2].isSeparatorItem)
            XCTAssertEqual(items[3].submenu?.items.map(\.title), ["PDF", "PNG"])
            XCTAssertFalse(items[4].isEnabled)
            XCTAssertEqual(items[1].state, .off)
            // Choosing a nested item runs its action.
            button!.performClick(nil)
            let rows = menuWindows()[0].menuView.layout.rows.map { $0.item.title }
            XCTAssertEqual(rows, ["Rename", "Flag", "", "Export", "hint"], "a Menu shows every item; its title stays on the button")
            // Hover Export, then choose PNG from the submenu.
            let mw = menuWindows()[0]
            let exportFrame = mw.menuView.layout.rows[3].frame
            let p = mw.menuView.convert(NSPoint(x: exportFrame.midX, y: exportFrame.midY), to: nil)
            NSApplication.shared.sendEvent(NSEvent.mouseEvent(with: .mouseMoved, location: p, modifierFlags: [], timestamp: 0, windowNumber: mw.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!)
            XCTAssertEqual(menuWindows().count, 2)
            chooseRow(1)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("log png flag false"), texts(h).joined(separator: "|"))
            // The toggle item flips its binding and shows the state.
            button!.performClick(nil)
            chooseRow(1)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("log png flag true"))
            XCTAssertEqual(button!.menu!.items[1].state, .on)
            w.close()
        }
    }

    func testContextMenuOpensOnRightClick() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var log = "none"
                var body: some View {
                    VStack {
                        Text("target").frame(width: 200, height: 100).contextMenu {
                            Button("Inspect") { log = "inspect" }
                            Button("Delete") { log = "delete" }
                        }
                        Text("log \(log)")
                    }
                }
            }
            let (w, h) = host(Probe())
            let target = allViews(h).first { $0 is _ContextMenuView }!
            let center = target.convert(NSPoint(x: target.bounds.midX, y: target.bounds.midY), to: nil)
            let down = NSEvent.mouseEvent(with: .rightMouseDown, location: center, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            NSApplication.shared.sendEvent(down)
            XCTAssertEqual(menuWindows().count, 1)
            XCTAssertEqual(menuWindows()[0].menuView.layout.rows.map { $0.item.title }, ["Inspect", "Delete"])
            let up = NSEvent.mouseEvent(with: .rightMouseUp, location: center, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            NSApplication.shared.sendEvent(up)
            XCTAssertEqual(menuWindows().count, 1, "releasing the opening click in place keeps the menu open")
            chooseRow(1)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("log delete"), texts(h).joined(separator: "|"))
            w.close()
        }
    }
}
