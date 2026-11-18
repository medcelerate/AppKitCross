// Drag and drop: in-process dragging sessions, destination messages, drag image window,
// and the SwiftUI onDrag/onDrop pair.

import XCTest
@testable import AppKit
@testable import SwiftUI
import UniformTypeIdentifiers

@MainActor
private func makeWindow(x: CGFloat = 100) -> NSWindow {
    let w = NSWindow(contentRect: NSRect(x: x, y: 100, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    w.makeKeyAndOrderFront(nil)
    return w
}

@MainActor
private func send(_ type: NSEvent.EventType, _ point: NSPoint, in w: NSWindow, flags: NSEvent.ModifierFlags = []) {
    let e = NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    NSApplication.shared.sendEvent(e)
}

@MainActor
private final class Source: NSView, NSDraggingSource {
    var payload = "hello"
    var log: [String] = []
    override func mouseDragged(with event: NSEvent) {
        let item = NSPasteboardItem()
        _ = item.setString(payload, forType: .string)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        dragging.setDraggingFrame(NSRect(x: 0, y: 0, width: 40, height: 20), contents: nil)
        _ = beginDraggingSession(with: [dragging], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { [.copy, .move] }
    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) { log.append("begin") }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { log.append("end \(operation.rawValue)") }
}

@MainActor
private final class Target: NSView {
    var log: [String] = []
    var dropped: String?
    var answer: NSDragOperation = .copy
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.string])
    }
    required init?(coder: NSCoder) { nil }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { log.append("entered"); return answer }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { log.append("exited") }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        dropped = sender.draggingPasteboard.string(forType: .string)
        log.append("performed at \(Int(sender.draggingLocation.x)),\(Int(sender.draggingLocation.y))")
        return dropped != nil
    }
    override func draggingEnded(_ sender: any NSDraggingInfo) { log.append("ended") }
}

final class DragDropTests: XCTestCase, @unchecked Sendable {
    func testDragWithinAWindowEntersUpdatesAndDrops() throws {
        try requireHostBackend("hangs on Win32: not diagnosed, no result after 60s")
        MainActor.assumeIsolated {
            let w = makeWindow()
            let source = Source(frame: NSRect(x: 10, y: 10, width: 80, height: 40))
            let target = Target(frame: NSRect(x: 150, y: 10, width: 100, height: 100))
            w.contentView!.addSubview(source)
            w.contentView!.addSubview(target)
            send(.leftMouseDown, NSPoint(x: 30, y: 20), in: w)
            send(.leftMouseDragged, NSPoint(x: 40, y: 25), in: w)
            XCTAssertTrue(_NSDragTracker.isDragging)
            XCTAssertEqual(source.log, ["begin"])
            let image = NSApplication.shared.windows.compactMap { $0 as? _NSDragImageWindow }.first
            XCTAssertNotNil(image, "a drag image window follows the pointer")
            XCTAssertTrue(image!.isVisible)
            // Over empty content: no destination. Over the target: entered, then updated.
            send(.leftMouseDragged, NSPoint(x: 120, y: 60), in: w)
            XCTAssertTrue(target.log.isEmpty)
            send(.leftMouseDragged, NSPoint(x: 160, y: 30), in: w)
            XCTAssertEqual(target.log, ["entered"])
            send(.leftMouseDragged, NSPoint(x: 170, y: 40), in: w)
            XCTAssertEqual(target.log, ["entered"], "updates reuse the entered answer")
            let frame = image!.frame
            send(.leftMouseDragged, NSPoint(x: 180, y: 50), in: w)
            XCTAssertEqual(image!.frame.minX, frame.minX + 10, accuracy: 0.5, "the image moves with the pointer")
            // Leave and come back, then drop.
            send(.leftMouseDragged, NSPoint(x: 120, y: 150), in: w)
            XCTAssertEqual(target.log, ["entered", "exited"])
            send(.leftMouseDragged, NSPoint(x: 200, y: 50), in: w)
            send(.leftMouseUp, NSPoint(x: 200, y: 50), in: w)
            XCTAssertEqual(target.dropped, "hello")
            XCTAssertEqual(target.log, ["entered", "exited", "entered", "performed at 200,50", "ended"])
            XCTAssertEqual(source.log, ["begin", "end \(NSDragOperation.copy.rawValue)"])
            XCTAssertFalse(_NSDragTracker.isDragging)
            XCTAssertFalse(image!.isVisible)
            w.close()
        }
    }

    func testRefusedDropEscapeAndModifiers() throws {
        try requireHostBackend("hangs on Win32: not diagnosed, no result after 60s")
        MainActor.assumeIsolated {
            let w = makeWindow()
            let source = Source(frame: NSRect(x: 10, y: 10, width: 80, height: 40))
            let target = Target(frame: NSRect(x: 150, y: 10, width: 100, height: 100))
            target.answer = []
            w.contentView!.addSubview(source)
            w.contentView!.addSubview(target)
            // A destination answering none gets no drop.
            send(.leftMouseDown, NSPoint(x: 30, y: 20), in: w)
            send(.leftMouseDragged, NSPoint(x: 200, y: 50), in: w)
            send(.leftMouseUp, NSPoint(x: 200, y: 50), in: w)
            XCTAssertNil(target.dropped)
            XCTAssertEqual(target.log, ["entered", "exited", "ended"])
            XCTAssertEqual(source.log.last, "end 0")
            // Escape cancels.
            target.log = []; source.log = []
            target.answer = .copy
            send(.leftMouseDown, NSPoint(x: 30, y: 20), in: w)
            send(.leftMouseDragged, NSPoint(x: 200, y: 50), in: w)
            XCTAssertEqual(target.log, ["entered"])
            let esc = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)!
            NSApplication.shared.sendEvent(esc)
            XCTAssertFalse(_NSDragTracker.isDragging)
            XCTAssertEqual(target.log, ["entered", "exited", "ended"])
            XCTAssertEqual(source.log, ["begin", "end 0"])
            XCTAssertNil(target.dropped)
            send(.leftMouseUp, NSPoint(x: 200, y: 50), in: w)       // the release after a cancel is ordinary
            // Option limits the operation to copy; the destination offering only move gets none.
            target.log = []; source.log = []
            target.answer = .move
            send(.leftMouseDown, NSPoint(x: 30, y: 20), in: w)
            send(.leftMouseDragged, NSPoint(x: 200, y: 50), in: w, flags: [.option])
            send(.leftMouseUp, NSPoint(x: 200, y: 50), in: w, flags: [.option])
            XCTAssertNil(target.dropped)
            XCTAssertEqual(source.log.last, "end 0")
            send(.leftMouseDown, NSPoint(x: 30, y: 20), in: w)
            send(.leftMouseDragged, NSPoint(x: 200, y: 50), in: w)
            send(.leftMouseUp, NSPoint(x: 200, y: 50), in: w)
            XCTAssertEqual(target.dropped, "hello")
            XCTAssertEqual(source.log.last, "end \(NSDragOperation.move.rawValue)")
            w.close()
        }
    }

    func testDragIntoAnotherWindow() throws {
        try requireHostBackend("hangs on Win32: not diagnosed, no result after 60s")
        MainActor.assumeIsolated {
            let w1 = makeWindow(x: 100)
            let w2 = makeWindow(x: 500)
            let source = Source(frame: NSRect(x: 10, y: 10, width: 80, height: 40))
            let target = Target(frame: NSRect(x: 20, y: 20, width: 200, height: 100))
            w1.contentView!.addSubview(source)
            w2.contentView!.addSubview(target)
            w1.makeKeyAndOrderFront(nil)
            send(.leftMouseDown, NSPoint(x: 30, y: 20), in: w1)
            // The source window keeps the mouse: later events arrive through it with points outside it.
            send(.leftMouseDragged, NSPoint(x: 60, y: 30), in: w1)
            send(.leftMouseDragged, NSPoint(x: 450, y: 50), in: w1)
            XCTAssertEqual(target.log, ["entered"])
            send(.leftMouseUp, NSPoint(x: 450, y: 50), in: w1)
            XCTAssertEqual(target.dropped, "hello")
            XCTAssertTrue(target.log.contains { $0.hasPrefix("performed at 50,50") }, target.log.joined(separator: ","))
            w1.close(); w2.close()
        }
    }

    func testSwiftUIDragAndDrop() throws {
        try requireHostBackend("hangs on Win32: not diagnosed, no result after 60s")
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var dropped = "none"
                @State var targeted = false
                var body: some View {
                    HStack(spacing: 20) {
                        Text("drag me").frame(width: 80, height: 30)
                            .onDrag { NSItemProvider(object: "payload" as NSString) }
                        Text(targeted ? "over" : "drop: \(dropped)").frame(width: 120, height: 80)
                            .onDrop(of: [.utf8PlainText], isTargeted: $targeted) { providers in
                                guard let p = providers.first else { return false }
                                p.loadDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier) { data, _ in
                                    let s = data.map { String(decoding: $0, as: UTF8.self) } ?? "?"
                                    DispatchQueue.main.async { dropped = s }
                                }
                                return true
                            }
                    }
                }
            }
            let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 320, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
            let h = NSHostingView(rootView: Probe())
            h.frame = NSRect(x: 0, y: 0, width: 320, height: 160)
            w.contentView!.addSubview(h)
            w.makeKeyAndOrderFront(nil)
            h.layoutSubtreeIfNeeded()
            @MainActor func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }
            @MainActor func texts() -> [String] { allViews(h).compactMap { ($0 as? _TextView)?.storage.string } }
            let sourceView = allViews(h).first { $0 is _DragSourceView }!
            let targetView = allViews(h).first { $0 is _DropTargetView }!
            let start = sourceView.convert(NSPoint(x: 20, y: 15), to: nil)
            let over = targetView.convert(NSPoint(x: 40, y: 40), to: nil)
            send(.leftMouseDown, start, in: w)
            send(.leftMouseDragged, NSPoint(x: start.x + 10, y: start.y), in: w)
            XCTAssertTrue(_NSDragTracker.isDragging, "moving past the threshold starts the drag")
            send(.leftMouseDragged, over, in: w)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts().contains("over"), "isTargeted turns on over the target: \(texts())")
            send(.leftMouseUp, over, in: w)
            h.layoutSubtreeIfNeeded()
            XCTAssertFalse(_NSDragTracker.isDragging)
            // The provider's data may arrive on another queue: give it a moment.
            let deadline = Date(timeIntervalSinceNow: 2)
            while !texts().contains("drop: payload") && Date() < deadline {
                _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
                h.layoutSubtreeIfNeeded()
            }
            XCTAssertTrue(texts().contains("drop: payload"), texts().joined(separator: "|"))
            w.close()
        }
    }
}

// MARK: Drags the window system delivers (ADR-0011 stage B)

/// The `PlatformWindowOwner` drag methods, as a backend calls them for a drag from
/// another application: types known up front, data loaded on demand, one item per file.
final class PlatformDragDeliveryTests: XCTestCase, @unchecked Sendable {
    @MainActor
    private func makeInfo(in w: NSWindow, at point: NSPoint, loads: inout Int) -> PlatformDragInfo {
        nonisolated(unsafe) var count = 0
        let info = PlatformDragInfo(location: point, sourceOperations: [.copy, .move], modifierFlags: [],
                                    items: [["public.utf8-plain-text", "public.file-url"], ["public.file-url"]], isFromThisApplication: false) { item, type in
            count += 1
            switch (item, type) {
            case (0, "public.utf8-plain-text"): return Data("from outside".utf8)
            case (0, "public.file-url"): return Data("file:///tmp/a.txt".utf8)
            case (1, "public.file-url"): return Data("file:///tmp/b.txt".utf8)
            default: return nil
            }
        }
        loads = count
        return info
    }

    func testForeignDragEntersUpdatesDropsWithLazyData() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let target = Target(frame: NSRect(x: 150, y: 10, width: 100, height: 100))
            w.contentView!.addSubview(target)
            var loads = 0
            let info = makeInfo(in: w, at: NSPoint(x: 50, y: 50), loads: &loads)
            // Over empty content: nothing accepts, no data loaded.
            XCTAssertEqual(w.platformDragEntered(info), [])
            XCTAssertTrue(target.log.isEmpty)
            info.location = NSPoint(x: 160, y: 30)
            XCTAssertEqual(w.platformDragUpdated(info), .copy)
            XCTAssertEqual(target.log, ["entered"])
            info.location = NSPoint(x: 170, y: 40)
            XCTAssertEqual(w.platformDragUpdated(info), .copy)
            XCTAssertEqual(target.log, ["entered"])
            w.platformDragExited()
            XCTAssertEqual(target.log, ["entered", "exited"])
            info.location = NSPoint(x: 200, y: 50)
            XCTAssertEqual(w.platformDragEntered(info), .copy)
            XCTAssertEqual(w.platformDrop(info), .copy)
            XCTAssertEqual(target.dropped, "from outside", "the representation is loaded when the destination reads it")
            XCTAssertEqual(target.log, ["entered", "exited", "entered", "performed at 200,50", "ended"])
            w.close()
        }
    }

    func testForeignFileDropYieldsOneItemPerFile() {
        MainActor.assumeIsolated {
            final class Files: NSView {
                var urls: [String] = []
                override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
                required init?(coder: NSCoder) { nil }
                override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { .copy }
                override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
                    urls = (sender.draggingPasteboard.pasteboardItems ?? []).compactMap { $0.string(forType: .fileURL) }
                    return !urls.isEmpty
                }
            }
            let w = makeWindow()
            let files = Files(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            w.contentView!.addSubview(files)
            var loads = 0
            let info = makeInfo(in: w, at: NSPoint(x: 50, y: 50), loads: &loads)
            XCTAssertEqual(w.platformDragEntered(info), .copy)
            XCTAssertEqual(w.platformDrop(info), .copy)
            XCTAssertEqual(files.urls, ["file:///tmp/a.txt", "file:///tmp/b.txt"])
            w.close()
        }
    }

    func testSwiftUIDropTakesForeignDrags() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var dropped = "none"
                var body: some View {
                    Text("drop: \(dropped)").frame(width: 200, height: 100)
                        .onDrop(of: [.utf8PlainText], isTargeted: nil) { providers in
                            guard let p = providers.first else { return false }
                            p.loadDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier) { data, _ in
                                let s = data.map { String(decoding: $0, as: UTF8.self) } ?? "?"
                                DispatchQueue.main.async { dropped = s }
                            }
                            return true
                        }
                }
            }
            let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 320, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
            let h = NSHostingView(rootView: Probe())
            h.frame = NSRect(x: 0, y: 0, width: 320, height: 160)
            w.contentView!.addSubview(h)
            w.makeKeyAndOrderFront(nil)
            h.layoutSubtreeIfNeeded()
            var loads = 0
            let info = makeInfo(in: w, at: NSPoint(x: 160, y: 80), loads: &loads)
            XCTAssertEqual(w.platformDragEntered(info), .copy)
            XCTAssertEqual(w.platformDrop(info), .copy)
            @MainActor func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }
            @MainActor func texts() -> [String] { allViews(h).compactMap { ($0 as? _TextView)?.storage.string } }
            let deadline = Date(timeIntervalSinceNow: 2)
            while !texts().contains("drop: from outside") && Date() < deadline {
                _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
                h.layoutSubtreeIfNeeded()
            }
            XCTAssertTrue(texts().contains("drop: from outside"), texts().joined(separator: "|"))
            w.close()
        }
    }
}

