// The SwiftUI members the Sibyl port needed: Tab content in a TabView, Button with a system
// image, formatted text and value fields, ScrollViewReader and default scroll anchors,
// content shapes, fileExporter, unsorted value columns, list row decorations and onMove.

import XCTest
@testable import AppKit
@testable import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

@MainActor
private func host<V: View>(_ view: V, width: CGFloat = 320, height: CGFloat = 240) -> (NSWindow, NSHostingView<V>) {
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

private struct Destination: Identifiable { let id: Int; let name: String; let host: String }

private struct NotesFile: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

/// Holds what a view hands out (a scroll proxy, an export result) for the test to use.
@MainActor
private final class Box<T> { var value: T?; init() {} }

final class SwiftUISibylGapTests: XCTestCase, @unchecked Sendable {
    func testTabContentDrivesTabViewSelection() {
        MainActor.assumeIsolated {
            enum Pane: Hashable { case look, audio, network }
            struct Probe: View {
                @State var selected = Pane.audio
                var body: some View {
                    VStack {
                        Text("selected \(String(describing: selected))")
                        TabView(selection: $selected) {
                            Tab("Look", systemImage: "paintbrush", value: Pane.look) { Text("look page") }
                            Tab("Audio", systemImage: "waveform", value: Pane.audio) { Text("audio page") }
                            if true {
                                Tab("Network", systemImage: "network", value: Pane.network) { Text("network page") }
                            }
                        }
                    }
                }
            }
            let (w, h) = host(Probe())
            let bar = allViews(h).compactMap { $0 as? NSSegmentedControl }.first!
            XCTAssertEqual((0..<bar.segmentCount).map { bar.label(forSegment: $0) }, ["Look", "Audio", "Network"])
            XCTAssertEqual(bar.selectedSegment, 1, "the binding's value selects its tab")
            XCTAssertTrue(texts(h).contains("audio page"))
            XCTAssertFalse(texts(h).contains("look page"))
            bar.selectedSegment = 2
            _ = bar.sendAction(bar.action, to: bar.target)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("network page"), texts(h).joined(separator: "|"))
            XCTAssertTrue(texts(h).contains("selected network"), "choosing a tab writes its value")
            w.close()
        }
    }

    func testButtonWithSystemImageShowsTitleAndActs() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var count = 0
                var body: some View {
                    VStack {
                        Button("Rescan", systemImage: "arrow.clockwise") { count += 1 }
                        Button("Clear", systemImage: "trash", role: .destructive) { count = 0 }
                        Text("count \(count)")
                    }
                }
            }
            let (w, h) = host(Probe())
            XCTAssertTrue(texts(h).contains("Rescan"))
            let button = allViews(h).first { $0.isAccessibilityElement() && $0.accessibilityLabel() == "Rescan" }
            XCTAssertNotNil(button)
            XCTAssertTrue(button!.accessibilityPerformPress())
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("count 1"))
            w.close()
        }
    }

    func testTextFormatsItsInput() {
        MainActor.assumeIsolated {
            let us = Locale(identifier: "en_US")
            let (w, h) = host(VStack {
                Text(42.5, format: .number.precision(.fractionLength(2)).locale(us))
                Text(Date(timeIntervalSince1970: 0), format: .iso8601)
                Text(12345, format: .number.grouping(.never))
            })
            XCTAssertTrue(texts(h).contains("42.50"), texts(h).joined(separator: "|"))
            XCTAssertTrue(texts(h).contains("1970-01-01T00:00:00Z"), texts(h).joined(separator: "|"))
            XCTAssertTrue(texts(h).contains("12345"))
            w.close()
        }
    }

    func testTextFieldWithFormatCommitsParsedValue() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var port: UInt16 = 8080
                var body: some View {
                    VStack {
                        TextField("Port", value: $port, format: .number.grouping(.never))
                        Text("port \(port)")
                        Button("Reset") { port = 1 }
                    }
                }
            }
            let (w, h) = host(Probe())
            let field = allViews(h).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
            XCTAssertEqual(field.stringValue, "8080")
            field.stringValue = "9090"
            NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("port 8080"), "typing alone does not change the value")
            _ = field.sendAction(field.action, to: field.target)      // Return
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("port 9090"), texts(h).joined(separator: "|"))
            // Text that does not parse goes back to the value.
            field.stringValue = "port?"
            _ = field.sendAction(field.action, to: field.target)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(field.stringValue, "9090")
            XCTAssertTrue(texts(h).contains("port 9090"))
            // A change of the value from elsewhere shows in the field.
            allViews(h).compactMap { $0 as? NSButton }.first { $0.title == "Reset" }!.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(field.stringValue, "1")
            w.close()
        }
    }

    func testTextFieldWithFormatterCommits() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var amount = 2.5
                let formatter: NumberFormatter = { let f = NumberFormatter(); f.locale = Locale(identifier: "en_US"); f.numberStyle = .decimal; return f }()
                var body: some View {
                    VStack {
                        TextField("Amount", value: $amount, formatter: formatter)
                        Text("amount \(amount)")
                    }
                }
            }
            let (w, h) = host(Probe())
            let field = allViews(h).compactMap { $0 as? NSTextField }.first { $0.isEditable }!
            XCTAssertEqual(field.stringValue, "2.5")
            field.stringValue = "7.25"
            _ = field.sendAction(field.action, to: field.target)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("amount 7.25"), texts(h).joined(separator: "|"))
            w.close()
        }
    }

    func testScrollViewReaderScrollsToAnIdentifiedRow() {
        MainActor.assumeIsolated {
            let box = Box<ScrollViewProxy>()
            let (w, h) = host(ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<50, id: \.self) { i in Text("row \(i)").frame(height: 20).id(i) }
                    }
                }
                .onAppear { box.value = proxy }
            }, height: 200)
            let scroll = allViews(h).compactMap { $0 as? NSScrollView }.first!
            XCTAssertEqual(scroll.contentView.bounds.origin.y, 0)
            let visible = scroll.contentSize.height
            box.value!.scrollTo(30, anchor: .top)
            XCTAssertEqual(scroll.contentView.bounds.origin.y, 600, accuracy: 0.5)
            box.value!.scrollTo(40, anchor: .center)
            XCTAssertEqual(scroll.contentView.bounds.origin.y, 810 - visible / 2, accuracy: 0.5)
            // No anchor: the least scroll that shows the row (already visible: none).
            box.value!.scrollTo(41)
            XCTAssertEqual(scroll.contentView.bounds.origin.y, 810 - visible / 2, accuracy: 0.5)
            box.value!.scrollTo(2)
            XCTAssertEqual(scroll.contentView.bounds.origin.y, 40, accuracy: 0.5)
            // After a layout pass the request still holds.
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(scroll.contentView.bounds.origin.y, 40, accuracy: 0.5)
            w.close()
        }
    }

    func testDefaultScrollAnchorAndIndicators() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var rows = 30
                var body: some View {
                    VStack {
                        Button("More") { rows += 10 }
                        ScrollView {
                            VStack(spacing: 0) { ForEach(0..<rows, id: \.self) { Text("line \($0)").frame(height: 20) } }
                        }
                        .defaultScrollAnchor(.bottom)
                        .scrollIndicators(.never)
                    }
                }
            }
            let (w, h) = host(Probe(), height: 200)
            let scroll = allViews(h).compactMap { $0 as? NSScrollView }.first!
            XCTAssertFalse(scroll.hasVerticalScroller, "scrollIndicators(.never) removes the scroller")
            let doc = scroll.documentView!.frame.height
            XCTAssertEqual(scroll.contentView.bounds.origin.y, doc - scroll.contentSize.height, accuracy: 0.5, "starts at the bottom")
            allViews(h).compactMap { $0 as? NSButton }.first { $0.title == "More" }!.performClick(nil)
            h.layoutSubtreeIfNeeded()
            let grown = scroll.documentView!.frame.height
            XCTAssertEqual(grown, doc + 200, accuracy: 0.5)
            XCTAssertEqual(scroll.contentView.bounds.origin.y, grown - scroll.contentSize.height, accuracy: 0.5, "follows new rows at the bottom")
            w.close()
        }
    }

    func testContentShapeSetsTheHitArea() {
        MainActor.assumeIsolated {
            let (w, h) = host(HStack(spacing: 0) {
                Color.clear.frame(width: 100, height: 100).contentShape(Circle())
                Text("x").frame(width: 100, height: 100).contentShape(Rectangle())
            }.frame(width: 200, height: 100), width: 200, height: 100)
            let shapes = allViews(h).compactMap { $0 as? _ContentShapeView }
            XCTAssertEqual(shapes.count, 2)
            @MainActor func hit(_ view: NSView, _ local: NSPoint) -> NSView? {
                let p = view.superview!.convert(view.convert(local, to: view.superview), to: h.superview)
                return h.hitTest(p)
            }
            @MainActor func inside(_ v: NSView?, _ container: NSView) -> Bool {
                var n = v
                while let x = n { if x === container { return true }; n = x.superview }
                return false
            }
            let circle = shapes.first { $0.frame.minX < 50 }!, rect = shapes.first { $0.frame.minX >= 50 }!
            XCTAssertTrue(inside(hit(circle, NSPoint(x: 50, y: 50)), circle), "the circle's middle hits it")
            XCTAssertFalse(inside(hit(circle, NSPoint(x: 4, y: 4)), circle), "its corner is outside the circle")
            XCTAssertTrue(inside(hit(rect, NSPoint(x: 4, y: 4)), rect), "a rectangle shape takes hits in the text's empty corner")
            w.close()
        }
    }

    func testFileExporterWritesTheDocumentThroughTheSavePanel() throws {
        try requireHostBackend()
        try MainActor.assumeIsolated {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sibyl-exporter-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let result = Box<Result<URL, any Error>>()
            struct Probe: View {
                @State var exporting = true
                let result: Box<Result<URL, any Error>>
                var body: some View {
                    Text(exporting ? "exporting" : "idle")
                        .fileExporter(isPresented: $exporting, document: NotesFile(text: "hello"), contentType: .plainText, defaultFilename: "notes") { result.value = $0 }
                }
            }
            let (w, h) = host(Probe(result: result))
            let panel = try XCTUnwrap(w.attachedSheet as? NSSavePanel, "the save panel runs as a sheet")
            XCTAssertEqual(panel.nameFieldStringValue, "notes")
            XCTAssertEqual(panel.allowedContentTypes.first?.identifier, UTType.plainText.identifier)
            panel.directoryURL = dir
            panel.ok(nil)
            h.layoutSubtreeIfNeeded()
            let url = try XCTUnwrap(try? result.value?.get())
            XCTAssertEqual(url.lastPathComponent, "notes.txt")
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "hello")
            XCTAssertTrue(texts(h).contains("idle"), "the binding goes back to false")
            try? FileManager.default.removeItem(at: dir)
            w.close()
        }
    }

    func testUnsortedValueColumnsAndSortedHeaderClick() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var selection: Destination.ID? = nil
                @State var order = [KeyPathComparator(\Destination.name)]
                let rows = [Destination(id: 1, name: "Studio", host: "10.0.0.2"), Destination(id: 2, name: "Booth", host: "10.0.0.3")]
                var body: some View {
                    VStack {
                        // A table without a sort order takes string value columns (Sibyl's settings).
                        Table(rows, selection: $selection) {
                            TableColumn("Name", value: \.name)
                            TableColumn("Host", value: \.host)
                        }.frame(height: 90)
                        Table(rows.sorted(using: order), sortOrder: $order) {
                            TableColumn("Name", value: \.name)
                        }.frame(height: 90)
                        Text("order \(order.first?.order == .forward ? "fwd" : "rev")")
                    }
                }
            }
            let (w, h) = host(Probe(), height: 260)
            let tables = allViews(h).compactMap { $0 as? NSTableView }
            XCTAssertEqual(tables.count, 2)
            XCTAssertEqual(tables[0].tableColumns.map(\.title), ["Name", "Host"])
            XCTAssertNil(tables[0].tableColumns[0].sortDescriptorPrototype, "an unsorted table's columns do not sort")
            XCTAssertNotNil(tables[1].tableColumns[0].sortDescriptorPrototype)
            tables[1]._headerClicked(column: 0)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("order rev"), texts(h).joined(separator: "|"))
            w.close()
        }
    }

    func testListRowDecorationsAndOnMove() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var items = ["a", "b", "c"]
                var body: some View {
                    VStack {
                        List {
                            ForEach(items, id: \.self) { item in
                                Text(item).frame(height: 20)
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.red)
                            }
                            .onMove { from, to in items.move(fromOffsets: from, toOffset: to) }
                        }
                        Text(items.joined())
                    }
                }
            }
            let (w, h) = host(Probe(), height: 240)
            h.layoutSubtreeIfNeeded()
            let list = allViews(h).compactMap { $0 as? _ListView }.first!
            XCTAssertEqual(list.rowFrames.map(\.height), [20, 20, 20], "zero insets: rows are as tall as their content")
            XCTAssertEqual(list.hiddenSeparatorsBelow, [0, 1, 2])
            // Drag "a" below "c".
            @MainActor func send(_ type: NSEvent.EventType, _ y: CGFloat, _ n: Int) {
                let p = list.convert(NSPoint(x: 30, y: y), to: nil)
                NSApplication.shared.sendEvent(NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: n, clickCount: 1, pressure: 1)!)
            }
            send(.leftMouseDown, 10, 1)
            send(.leftMouseDragged, 30, 2)
            send(.leftMouseDragged, 58, 3)
            XCTAssertEqual(list.dropGap, 3)
            send(.leftMouseUp, 58, 4)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("bca"), texts(h).joined(separator: "|"))
            w.close()
        }
    }
}
