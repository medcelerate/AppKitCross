// Navigation and presentation: TabView, Picker, NavigationStack with links and a path,
// sheets attached to the host window, alerts through NSAlert.

import XCTest
@testable import AppKit
@testable import SwiftUI
import QuartzCore

@MainActor
private func host<V: View>(_ view: V, width: CGFloat = 400, height: CGFloat = 300) -> (NSWindow, NSHostingView<V>) {
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
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
private func buttons(_ v: NSView) -> [NSButton] { allViews(v).compactMap { $0 as? NSButton } }

final class SwiftUINavigationTests: XCTestCase, @unchecked Sendable {
    func testTabViewSwitchesPagesAndSelection() {
        MainActor.assumeIsolated {
            struct Tabs: View {
                @State var tab = "b"
                var body: some View {
                    VStack {
                        TabView(selection: $tab) {
                            Text("Page A").tabItem { Text("A") }.tag("a")
                            Text("Page B").tabItem { Label("B", systemImage: "circle") }.tag("b")
                        }
                        Text("Selected: \(tab)")
                    }
                }
            }
            let (w, h) = host(Tabs())
            XCTAssertTrue(texts(h).contains("Page B"), "the selection picks the initial page")
            XCTAssertFalse(texts(h).contains("Page A"))
            let tabButtons = buttons(h).filter { $0.title == "A" || $0.title == "B" }
            XCTAssertEqual(tabButtons.count, 2)
            XCTAssertEqual(tabButtons.first { $0.title == "B" }?.state, .on)
            tabButtons.first { $0.title == "A" }?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("Page A"))
            XCTAssertTrue(texts(h).contains("Selected: a"), "the binding follows the tab")
            w.close()
        }
    }

    func testPickerDrivesItsBinding() {
        MainActor.assumeIsolated {
            enum Flavor: String, CaseIterable, Hashable { case mint, choc, vanilla }
            struct Chooser: View {
                @State var flavor = Flavor.choc
                var body: some View {
                    VStack {
                        Picker("Flavor", selection: $flavor) {
                            ForEach(Flavor.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                        Picker("Radio", selection: $flavor) {
                            Text("mint").tag(Flavor.mint)
                            Text("choc").tag(Flavor.choc)
                        }.pickerStyle(.radioGroup)
                        Text("You chose \(flavor.rawValue)")
                    }
                }
            }
            let (w, h) = host(Chooser())
            XCTAssertTrue(texts(h).contains("Flavor"))
            let segments = buttons(h).filter { ["mint", "choc", "vanilla"].contains($0.title) }
            XCTAssertEqual(segments.count, 5, "three segments plus two radio buttons")
            XCTAssertEqual(segments.first { $0.title == "choc" }?.state, .on)
            segments.first { $0.title == "vanilla" }?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("You chose vanilla"))
            // The radio group reflects the same binding (its "mint" button comes after the segment's).
            buttons(h).filter { $0.title == "mint" }.last?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("You chose mint"))
            w.close()
        }
    }

    func testNavigationStackPushesAndPops() {
        MainActor.assumeIsolated {
            struct Nav: View {
                @State var path: [Int] = []
                var body: some View {
                    VStack {
                        NavigationStack(path: $path) {
                            VStack {
                                NavigationLink("Go to detail", value: 7)
                                NavigationLink("Inline", destination: Text("Inline page"))
                            }
                            .navigationTitle("Home")
                            .navigationDestination(for: Int.self) { n in Text("Detail \(n)").navigationTitle("Detail") }
                        }
                        Text("Depth \(path.count)")
                    }
                }
            }
            var clock: CFTimeInterval = 100
            let saved = CARuntime.now
            CARuntime.now = { clock }
            defer { CARuntime.now = saved }
            let (w, h) = host(Nav())
            XCTAssertTrue(texts(h).contains("Home"))
            XCTAssertTrue(texts(h).contains("Depth 0"))
            let link = buttons(h).first { $0.title == "Go to detail" }
            XCTAssertNotNil(link)
            link?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("Detail 7"), "the value found its destination")
            XCTAssertTrue(texts(h).contains("Depth 1"), "the path binding follows the push")
            XCTAssertTrue(texts(h).contains("Detail"), "the pushed page's title shows")
            buttons(h).first { $0.title == "‹ Back" }?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("Depth 0"))
            clock = 101          // the pushed page animates out before it leaves the hierarchy
            CARuntime.tick()
            XCTAssertFalse(texts(h).contains("Detail 7"))
            buttons(h).first { $0.title == "Inline" }?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("Inline page"))
            w.close()
        }
    }

    func testSheetAttachesToTheHostWindow() {
        MainActor.assumeIsolated {
            struct Root: View {
                @State var showing = false
                var dismissed = 0
                var body: some View {
                    Button("Open") { showing = true }
                        .sheet(isPresented: $showing) { SheetContent() }
                }
            }
            struct SheetContent: View {
                @Environment(\.dismiss) var dismiss
                var body: some View { VStack { Text("Sheet body"); Button("Close") { dismiss() } } }
            }
            let (w, h) = host(Root())
            XCTAssertTrue(w.sheets.isEmpty)
            buttons(h).first { $0.title == "Open" }?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(w.sheets.count, 1)
            let sheet = w.sheets[0]
            XCTAssertTrue(sheet.isSheet)
            XCTAssertTrue(sheet.sheetParent === w)
            XCTAssertTrue(texts(sheet.contentView!).contains("Sheet body"))
            buttons(sheet.contentView!).first { $0.title == "Close" }?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(w.sheets.isEmpty, "dismiss ends the sheet")
            XCTAssertFalse(sheet.isVisible)
            w.close()
        }
    }

    func testAlertRunsAnNSAlert() {
        MainActor.assumeIsolated {
            final class Log { var pressed: [String] = [] }
            let log = Log()
            struct Root: View {
                @State var ask = false
                let log: Log
                var body: some View {
                    Button("Ask") { ask = true }
                        .alert("Delete?", isPresented: $ask) {
                            Button("Delete", role: .destructive) { log.pressed.append("delete") }
                            Button("Cancel", role: .cancel) { log.pressed.append("cancel") }
                        } message: { Text("This cannot be undone.") }
                }
            }
            let (w, h) = host(Root(log: log))
            let before = NSApp.windows.count
            buttons(h).first { $0.title == "Ask" }?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(NSApp.windows.count, before + 1, "an alert panel opened")
            let panel = NSApp.windows.last!
            XCTAssertTrue(texts(panel.contentView!).contains("Delete?") || buttons(panel.contentView!).contains { $0.title == "Delete" })
            buttons(panel.contentView!).first { $0.title == "Delete" }?.performClick(nil)
            XCTAssertEqual(log.pressed, ["delete"])
            w.close()
        }
    }
}
