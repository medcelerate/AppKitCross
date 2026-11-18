// NSCollectionView drag and drop and animated updates (ADR-0041): a drag started from
// items through the host backend's event path, drops on and between items with the
// delegate's validate/accept sequence, the legacy single-section forms, the layouts' drop
// targets and inter-item gaps, the items' drag image components, and batch updates that
// animate to the frames an instant update gives.

import XCTest
@testable import AppKit
@testable import QuartzCore

// MARK: - Fixtures

@MainActor
private func send(_ type: NSEvent.EventType, _ point: NSPoint, in w: NSWindow, flags: NSEvent.ModifierFlags = []) {
    let e = NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    NSApplication.shared.sendEvent(e)
}

@MainActor
private func describe(_ op: NSCollectionView.DropOperation) -> String { op == .on ? "on" : "before" }

/// The data source and delegate: records every drag and drop call.
@MainActor
private final class DragSource: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var items = ["a", "b", "c", "d", "e", "f", "g"]
    var log: [String] = []
    var allowDrag = true
    var answer: NSDragOperation = .copy
    var retarget: ((inout IndexPath, inout NSCollectionView.DropOperation) -> Void)?
    var dropped: [String] = []
    var reorders = false
    var promised: [String] = []

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { items.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("color"), for: indexPath)
        item.textField?.stringValue = items[indexPath.item]
        return item
    }
    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        log.append("canDrag \(indexPaths.map(\.item).sorted())")
        return allowDrag
    }
    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
        log.append("writer \(indexPath.item)")
        let pi = NSPasteboardItem()
        _ = pi.setString(items[indexPath.item], forType: .string)
        return pi
    }
    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
        log.append("willBegin \(indexPaths.map(\.item).sorted())")
    }
    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
        log.append("ended \(operation.rawValue)")
    }
    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: any NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        let p = proposedDropIndexPath.pointee
        var ip = IndexPath(item: p.index(atPosition: 1), section: p.index(atPosition: 0))
        var op = proposedDropOperation.pointee
        log.append("validate \(ip.section),\(ip.item) \(describe(op))")
        if let retarget {
            retarget(&ip, &op)
            proposedDropIndexPath.pointee = NSIndexPath(indexes: [ip.section, ip.item], length: 2)
            proposedDropOperation.pointee = op
        }
        return answer
    }
    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: any NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        log.append("accept \(indexPath.section),\(indexPath.item) \(describe(dropOperation))")
        dropped = (draggingInfo.draggingPasteboard.pasteboardItems ?? []).compactMap { $0.string(forType: .string) }
        if reorders {
            // Every dragged item to the target, in order, as one (animated) batch: the demo's move.
            let froms = dropped.compactMap { items.firstIndex(of: $0) }.sorted()
            var to = indexPath.item
            for f in froms.reversed() { items.remove(at: f); if f < to { to -= 1 } }
            items.insert(contentsOf: froms.map { dropped[froms.firstIndex(of: $0)!] }, at: to)
            let moves = froms.enumerated().map { (IndexPath(item: $1, section: 0), IndexPath(item: to + $0, section: 0)) }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                collectionView.animator().performBatchUpdates {
                    for (f, t) in moves where f != t { collectionView.moveItem(at: f, to: t) }
                }
            }
        }
        return true
    }
    nonisolated func collectionView(_ collectionView: NSCollectionView, namesOfPromisedFilesDroppedAtDestination dropURL: URL, forDraggedItemsAt indexPaths: Set<IndexPath>) -> [String] {
        MainActor.assumeIsolated {
            let names = indexPaths.map(\.item).sorted().map { "\(items[$0]).txt" }
            promised = names
            return names
        }
    }
}

/// Only the old single-section (Int index) forms.
@MainActor
private final class LegacySource: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var items = ["a", "b", "c", "d", "e"]
    var log: [String] = []
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { items.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("color"), for: indexPath)
        item.textField?.stringValue = items[indexPath.item]
        return item
    }
    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexes: IndexSet, with event: NSEvent) -> Bool {
        log.append("canDrag \(Array(indexes))")
        return true
    }
    nonisolated func collectionView(_ collectionView: NSCollectionView, writeItemsAt indexes: IndexSet, to pasteboard: NSPasteboard) -> Bool {
        nonisolated(unsafe) let pb = pasteboard
        return MainActor.assumeIsolated {
            log.append("write \(Array(indexes))")
            pb.declareTypes([.string], owner: nil)
            return pb.setString(indexes.map { items[$0] }.joined(separator: ","), forType: .string)
        }
    }
    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexes: IndexSet) {
        log.append("willBegin \(Array(indexes))")
    }
    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: any NSDraggingInfo, proposedIndex proposedDropIndex: UnsafeMutablePointer<Int>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        log.append("validate \(proposedDropIndex.pointee) \(describe(proposedDropOperation.pointee))")
        return .move
    }
    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: any NSDraggingInfo, index: Int, dropOperation: NSCollectionView.DropOperation) -> Bool {
        log.append("accept \(index) \(describe(dropOperation)) \(draggingInfo.draggingPasteboard.string(forType: .string) ?? "-")")
        return true
    }
}

/// A plain view dragging a string (the drop destination tests' source).
@MainActor
private final class StringSource: NSView, NSDraggingSource {
    var log: [String] = []
    override func mouseDragged(with event: NSEvent) {
        let item = NSPasteboardItem()
        _ = item.setString("x", forType: .string)
        let d = NSDraggingItem(pasteboardWriter: item)
        d.setDraggingFrame(NSRect(x: 0, y: 0, width: 20, height: 20), contents: nil)
        _ = beginDraggingSession(with: [d], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { [.copy, .move] }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { log.append("end \(operation.rawValue)") }
}

/// A plain destination taking strings (and asking for promised files).
@MainActor
private final class StringTarget: NSView {
    var dropped: String?
    var promised: [String]?
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.string])
    }
    required init?(coder: NSCoder) { nil }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        dropped = sender.draggingPasteboard.string(forType: .string)
        promised = sender.namesOfPromisedFilesDropped(atDestination: URL(fileURLWithPath: NSTemporaryDirectory()))
        return true
    }
}

/// A window with a collection view (grid of 50-point cells, 10 apart, five to a row) on
/// the left and a plain source and target on the right.
@MainActor
private final class Fixture {
    let window: NSWindow
    let scroll: NSScrollView
    let collectionView: NSCollectionView
    let source = StringSource(frame: NSRect(x: 320, y: 220, width: 60, height: 60))
    let target = StringTarget(frame: NSRect(x: 320, y: 20, width: 60, height: 100))

    init(dataSource: (NSObject & NSCollectionViewDataSource & NSCollectionViewDelegate), layout: NSCollectionViewLayout? = nil) {
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        scroll.hasVerticalScroller = false
        collectionView = NSCollectionView(frame: scroll.bounds)
        let grid = NSCollectionViewGridLayout()
        grid.minimumItemSize = NSSize(width: 50, height: 50)
        grid.maximumItemSize = NSSize(width: 50, height: 50)
        grid.minimumInteritemSpacing = 10
        grid.minimumLineSpacing = 10
        collectionView.collectionViewLayout = layout ?? grid
        collectionView.register(ColorItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("color"))
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.registerForDraggedTypes([.string])
        collectionView.dataSource = dataSource
        collectionView.delegate = dataSource
        scroll.documentView = collectionView
        window.contentView!.addSubview(scroll)
        window.contentView!.addSubview(source)
        window.contentView!.addSubview(target)
        window.makeKeyAndOrderFront(nil)
        window.display()
    }

    /// A point of item `i` in window coordinates (`dx` from its left edge, or its centre).
    func point(item i: Int, dx: CGFloat? = nil) -> NSPoint {
        let f = collectionView.layoutAttributesForItem(at: IndexPath(item: i, section: 0))!.frame
        return collectionView.convert(NSPoint(x: dx.map { f.minX + $0 } ?? f.midX, y: f.midY), to: nil)
    }
    func center(of v: NSView) -> NSPoint { v.convert(NSPoint(x: v.bounds.midX, y: v.bounds.midY), to: nil) }
    func texts() -> [String] {
        (0..<collectionView.numberOfItems(inSection: 0)).map { collectionView.item(at: IndexPath(item: $0, section: 0))?.textField?.stringValue ?? "?" }
    }
}

// MARK: - Drag and drop

final class CollectionViewDragDropTests: XCTestCase, @unchecked Sendable {
    func testDraggingSelectedItemsCarriesTheirWritersAndReportsTheSession() throws {
        try requireHostBackend("drags track through the host backend's event path")
        MainActor.assumeIsolated {
            let ds = DragSource()
            let f = Fixture(dataSource: ds)
            f.collectionView.selectionIndexPaths = [IndexPath(item: 1, section: 0), IndexPath(item: 2, section: 0)]
            let start = f.point(item: 1)
            send(.leftMouseDown, start, in: f.window)
            XCTAssertTrue(ds.log.isEmpty)
            send(.leftMouseDragged, NSPoint(x: start.x + 2, y: start.y), in: f.window)
            XCTAssertFalse(_NSDragTracker.isDragging, "the mouse must move more than 3 points")
            send(.leftMouseDragged, NSPoint(x: start.x + 10, y: start.y), in: f.window)
            XCTAssertTrue(_NSDragTracker.isDragging)
            // The collection view is a destination too: the drag starts over it.
            XCTAssertEqual(ds.log, ["canDrag [1, 2]", "writer 1", "writer 2", "willBegin [1, 2]", "validate 0,1 on"])
            let session = _NSDragTracker.current!.session
            XCTAssertEqual(session.draggingPasteboard.pasteboardItems?.compactMap { $0.string(forType: .string) }, ["b", "c"])
            XCTAssertEqual(session._items.count, 2)
            XCTAssertEqual(session._items[0].draggingFrame, f.collectionView.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))!.frame)
            XCTAssertEqual(session._items[0].imageComponents?.first?.key, .icon, "each item drags its own image components")
            XCTAssertEqual(f.collectionView.selectionIndexPaths.count, 2, "starting a drag keeps the selection")
            // Over the plain target and drop: it takes the first item's string; the source hears the operation.
            send(.leftMouseDragged, f.center(of: f.target), in: f.window)
            send(.leftMouseUp, f.center(of: f.target), in: f.window)
            XCTAssertFalse(_NSDragTracker.isDragging)
            XCTAssertEqual(f.target.dropped, "b")
            XCTAssertEqual(f.target.promised, ["b.txt", "c.txt"], "the destination's promise request reaches the delegate")
            XCTAssertEqual(ds.log.last, "ended \(NSDragOperation.copy.rawValue)")
            // A click (no drag) on one of the selected items selects just it, on mouse-up.
            f.collectionView.selectionIndexPaths = [IndexPath(item: 1, section: 0), IndexPath(item: 2, section: 0)]
            send(.leftMouseDown, f.point(item: 2), in: f.window)
            XCTAssertEqual(f.collectionView.selectionIndexPaths.count, 2)
            send(.leftMouseUp, f.point(item: 2), in: f.window)
            XCTAssertEqual(f.collectionView.selectionIndexPaths, [IndexPath(item: 2, section: 0)])
            // A refused drag falls back to selecting by dragging.
            ds.log = []
            ds.allowDrag = false
            send(.leftMouseDown, f.point(item: 4), in: f.window)
            send(.leftMouseDragged, f.point(item: 5), in: f.window)
            XCTAssertFalse(_NSDragTracker.isDragging)
            XCTAssertEqual(ds.log, ["canDrag [4]"])
            XCTAssertEqual(f.collectionView.selectionIndexPaths, [IndexPath(item: 4, section: 0), IndexPath(item: 5, section: 0)])
            send(.leftMouseUp, f.point(item: 5), in: f.window)
            f.window.close()
        }
    }

    func testDropOnAndBetweenItemsShowsTheTargetAndAcceptsIt() throws {
        try requireHostBackend("drags track through the host backend's event path")
        MainActor.assumeIsolated {
            let ds = DragSource()
            let f = Fixture(dataSource: ds)
            let cv = f.collectionView
            send(.leftMouseDown, f.center(of: f.source), in: f.window)
            send(.leftMouseDragged, NSPoint(x: f.center(of: f.source).x - 10, y: f.center(of: f.source).y), in: f.window)
            XCTAssertTrue(_NSDragTracker.isDragging)
            // The middle of item 2: on it, highlighted as the drop target.
            send(.leftMouseDragged, f.point(item: 2), in: f.window)
            XCTAssertEqual(ds.log.last, "validate 0,2 on")
            XCTAssertEqual(cv.item(at: IndexPath(item: 2, section: 0))?.highlightState, .asDropTarget)
            XCTAssertNil(cv._gapIndicatorView)
            // Its left edge: before it, with the gap indicator between items 1 and 2.
            send(.leftMouseDragged, f.point(item: 2, dx: 3), in: f.window)
            XCTAssertEqual(ds.log.last, "validate 0,2 before")
            XCTAssertEqual(cv.item(at: IndexPath(item: 2, section: 0))?.highlightState, NSCollectionViewItem.HighlightState.none)
            XCTAssertEqual(cv._gapIndicatorView?.frame, NSRect(x: 110, y: 0, width: 10, height: 50))
            XCTAssertTrue(cv._gapIndicatorView?.superview === cv)
            // The bar is drawn in the accent colour in the middle of the gap.
            let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds)!
            cv.cacheDisplay(in: cv.bounds, to: rep)
            let scale = max(1, rep.pixelsWide / max(1, Int(rep.size.width)))
            let row = 25 * scale                                  // rows top-down, as the view shows them
            let bar = rep.colorAt(x: 115 * scale, y: row)!, beside = rep.colorAt(x: 112 * scale, y: row)!
            XCTAssertGreaterThan(bar.blueComponent, 0.6)
            XCTAssertLessThan(bar.redComponent, 0.5)
            XCTAssertGreaterThan(beside.redComponent, 0.8, "the bar is narrower than the gap")
            // Its right edge: before the next item.
            send(.leftMouseDragged, f.point(item: 2, dx: 47), in: f.window)
            XCTAssertEqual(ds.log.last, "validate 0,3 before")
            // The gap after item 3: before item 4.
            send(.leftMouseDragged, f.point(item: 3, dx: 55), in: f.window)
            XCTAssertEqual(ds.log.last, "validate 0,4 before")
            // Past the last item of the last row: before the end.
            send(.leftMouseDragged, f.collectionView.convert(NSPoint(x: 250, y: 80), to: nil), in: f.window)
            XCTAssertEqual(ds.log.last, "validate 0,7 before")
            XCTAssertEqual(cv._gapIndicatorView?.frame, NSRect(x: 110, y: 60, width: 10, height: 50))
            send(.leftMouseDragged, f.point(item: 3, dx: 55), in: f.window)
            send(.leftMouseUp, f.point(item: 3, dx: 55), in: f.window)
            XCTAssertEqual(ds.log.last, "accept 0,4 before")
            XCTAssertEqual(ds.dropped, ["x"])
            XCTAssertNil(cv._gapIndicatorView, "the indicator goes when the drop is done")
            XCTAssertNil(cv._currentDropTarget)
            XCTAssertEqual(f.source.log, ["end \(NSDragOperation.copy.rawValue)"])
            // Leaving clears the target; a refusing delegate gets no drop.
            ds.log = []
            ds.answer = []
            send(.leftMouseDown, f.center(of: f.source), in: f.window)
            send(.leftMouseDragged, f.point(item: 1), in: f.window)
            XCTAssertNil(cv._currentDropTarget)
            XCTAssertEqual(cv.item(at: IndexPath(item: 1, section: 0))?.highlightState, NSCollectionViewItem.HighlightState.none)
            send(.leftMouseUp, f.point(item: 1), in: f.window)
            XCTAssertFalse(ds.log.contains { $0.hasPrefix("accept") })
            XCTAssertEqual(f.source.log.last, "end 0")
            f.window.close()
        }
    }

    func testMovedItemsStaySelectedAtTheirDestination() throws {
        try requireHostBackend("drags track through the host backend's event path")
        MainActor.assumeIsolated {
            let ds = DragSource()
            ds.answer = .move
            ds.reorders = true
            let f = Fixture(dataSource: ds)
            let cv = f.collectionView
            // Cmd-click b and c, then drag c past the end of the row of five and drop.
            send(.leftMouseDown, f.point(item: 1), in: f.window, flags: .command)
            send(.leftMouseUp, f.point(item: 1), in: f.window, flags: .command)
            send(.leftMouseDown, f.point(item: 2), in: f.window, flags: .command)
            send(.leftMouseUp, f.point(item: 2), in: f.window, flags: .command)
            XCTAssertEqual(cv.selectionIndexPaths, [IndexPath(item: 1, section: 0), IndexPath(item: 2, section: 0)])
            send(.leftMouseDown, f.point(item: 2), in: f.window)
            send(.leftMouseDragged, f.point(item: 2, dx: 40), in: f.window)
            XCTAssertTrue(_NSDragTracker.isDragging)
            send(.leftMouseDragged, f.point(item: 4, dx: 55), in: f.window)
            send(.leftMouseUp, f.point(item: 4, dx: 55), in: f.window)
            XCTAssertEqual(ds.items, ["a", "d", "e", "b", "c", "f", "g"])
            XCTAssertEqual(f.texts(), ds.items)
            XCTAssertEqual(cv.selectionIndexPaths, [IndexPath(item: 3, section: 0), IndexPath(item: 4, section: 0)], "the dragged items stay selected where they went")
            XCTAssertEqual((0..<7).filter { cv.item(at: IndexPath(item: $0, section: 0))!.isSelected }, [3, 4])
            f.window.close()
        }
    }

    func testAModalPlatformDragKeepsTheMovedSelection() throws {
        try requireHostBackend("stands a modal drag runner in for OLE on the host backend")
        MainActor.assumeIsolated {
            /// Runs the drag as OLE does: the drop happens inside `beginDrag`, then the window
            /// delivers the button release before `beginDraggingSession` returns.
            final class ModalRunner: PlatformDragDrop {
                weak var window: NSWindow?
                var dropAt: NSPoint = .zero
                var ran = false
                func beginDrag(from window: PlatformWindow, entries: [(item: Int, entry: PlatformPasteboardEntry)], operations: NSDragOperation, image: PlatformDragImage?, source: any PlatformDragSource) -> Bool {
                    MainActor.assumeIsolated {
                        ran = true
                        guard let w = self.window else { return }
                        let info = PlatformDragInfo(location: dropAt, sourceOperations: operations, modifierFlags: [], items: [], isFromThisApplication: true) { _, _ in nil }
                        _ = w.platformDragEntered(info)
                        let op = w.platformDrop(info)
                        source.platformDragEnded(at: w.convertPoint(toScreen: dropAt), operation: op)
                        send(.leftMouseUp, dropAt, in: w)
                    }
                    return true
                }
                func foreignDragMoved(to screenPoint: NSPoint, operations: NSDragOperation) -> NSDragOperation { [] }
                func foreignDrop(at screenPoint: NSPoint, operations: NSDragOperation) -> Bool { false }
                func foreignDragEnded() { }
            }
            let host = Platform.backend as! HostBackend
            let runner = ModalRunner()
            host.dragDrop = runner
            defer { host.dragDrop = nil }
            let ds = DragSource()
            ds.answer = .move
            ds.reorders = true
            let f = Fixture(dataSource: ds)
            let cv = f.collectionView
            runner.window = f.window
            runner.dropAt = f.point(item: 4, dx: 55)
            cv.selectionIndexPaths = [IndexPath(item: 1, section: 0), IndexPath(item: 2, section: 0)]
            send(.leftMouseDown, f.point(item: 2), in: f.window)
            send(.leftMouseDragged, f.point(item: 2, dx: 40), in: f.window)
            XCTAssertTrue(runner.ran)
            XCTAssertEqual(ds.items, ["a", "d", "e", "b", "c", "f", "g"])
            XCTAssertEqual(cv.selectionIndexPaths, [IndexPath(item: 3, section: 0), IndexPath(item: 4, section: 0)], "the release after the drop selects nothing of its own")
            f.window.close()
        }
    }

    func testValidateDropRetargetsAndReorderMovesTheItem() throws {
        try requireHostBackend("drags track through the host backend's event path")
        MainActor.assumeIsolated {
            let ds = DragSource()
            ds.answer = .move
            ds.reorders = true
            let f = Fixture(dataSource: ds)
            let cv = f.collectionView
            // Drag item 0 into the gap before item 3 and drop: the delegate moves it.
            send(.leftMouseDown, f.point(item: 0), in: f.window)
            send(.leftMouseDragged, f.point(item: 0, dx: 40), in: f.window)
            XCTAssertTrue(_NSDragTracker.isDragging)
            send(.leftMouseDragged, f.point(item: 3, dx: -5), in: f.window)
            send(.leftMouseUp, f.point(item: 3, dx: -5), in: f.window)
            XCTAssertEqual(Array(ds.log.suffix(3)), ["validate 0,3 before", "accept 0,3 before", "ended \(NSDragOperation.move.rawValue)"])
            XCTAssertEqual(f.texts(), ["b", "c", "a", "d", "e", "f", "g"])
            // A delegate retargeting every drop onto item 5.
            ds.log = []
            ds.reorders = false
            ds.retarget = { ip, op in ip = IndexPath(item: 5, section: 0); op = .on }
            send(.leftMouseDown, f.center(of: f.source), in: f.window)
            send(.leftMouseDragged, f.point(item: 1, dx: 2), in: f.window)
            XCTAssertEqual(ds.log.last, "validate 0,1 before")
            XCTAssertEqual(cv.item(at: IndexPath(item: 5, section: 0))?.highlightState, .asDropTarget)
            XCTAssertNil(cv._gapIndicatorView)
            send(.leftMouseUp, f.point(item: 1, dx: 2), in: f.window)
            XCTAssertEqual(ds.log.last, "accept 0,5 on")
            XCTAssertEqual(cv.item(at: IndexPath(item: 5, section: 0))?.highlightState, NSCollectionViewItem.HighlightState.none)
            f.window.close()
        }
    }

    func testLegacySingleSectionFormsDragAndDrop() throws {
        try requireHostBackend("drags track through the host backend's event path")
        MainActor.assumeIsolated {
            let ds = LegacySource()
            let f = Fixture(dataSource: ds)
            send(.leftMouseDown, f.point(item: 1), in: f.window)
            send(.leftMouseDragged, f.point(item: 1, dx: 45), in: f.window)
            XCTAssertTrue(_NSDragTracker.isDragging)
            XCTAssertEqual(ds.log, ["canDrag [1]", "write [1]", "willBegin [1]", "validate 2 before"])
            let session = _NSDragTracker.current!.session
            XCTAssertEqual(session.draggingPasteboard.string(forType: .string), "b")
            // The default image is the item's view, centred under the pointer.
            let frame = session._items[0].draggingFrame
            XCTAssertEqual(frame.size, NSSize(width: 50, height: 50))
            XCTAssertNotNil(session._items[0].imageComponents?.first?.contents as? NSImage)
            send(.leftMouseDragged, f.point(item: 3, dx: 1), in: f.window)
            XCTAssertEqual(ds.log.last, "validate 3 before")
            send(.leftMouseUp, f.point(item: 3, dx: 1), in: f.window)
            XCTAssertEqual(ds.log.suffix(1), ["accept 3 before b"])
            f.window.close()
        }
    }

    // MARK: - Layout geometry

    func testGridDropTargetsAndGapsMatchAppKit() {
        MainActor.assumeIsolated {
            // AppKit 15: a 200-point grid of seven 50-point cells, 10 apart (three to a row).
            let ds = DragSource()
            let grid = NSCollectionViewGridLayout()
            grid.minimumItemSize = NSSize(width: 50, height: 50)
            grid.maximumItemSize = NSSize(width: 50, height: 50)
            grid.minimumInteritemSpacing = 10
            grid.minimumLineSpacing = 10
            let cv = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 200, height: 300))
            cv.collectionViewLayout = grid
            cv.register(ColorItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("color"))
            cv.dataSource = ds
            _ = cv.numberOfSections
            grid.prepare()
            @MainActor func target(_ x: CGFloat, _ y: CGFloat) -> String {
                guard let a = grid.layoutAttributesForDropTarget(at: NSPoint(x: x, y: y)) else { return "nil" }
                return "\(a.representedElementCategory == .item ? "item" : "gap") \(a.indexPath!.item) \(a.frame)"
            }
            XCTAssertEqual(target(25, 25), "item 0 \(NSRect(x: 0, y: 0, width: 50, height: 50))")
            XCTAssertEqual(target(45, 25), "item 0 \(NSRect(x: 0, y: 0, width: 50, height: 50))")
            XCTAssertEqual(target(55, 25), "gap 1 \(NSRect(x: 50, y: 0, width: 10, height: 50))")
            XCTAssertEqual(target(185, 25), "gap 3 \(NSRect(x: 170, y: 0, width: 10, height: 50))")
            XCTAssertEqual(target(120, 140), "gap 7 \(NSRect(x: 50, y: 120, width: 10, height: 50))")
            XCTAssertEqual(target(100, 200), "gap 7 \(NSRect(x: 50, y: 120, width: 10, height: 50))")
            let gaps: [NSRect] = (0...7).map { grid.layoutAttributesForInterItemGap(before: IndexPath(item: $0, section: 0))?.frame ?? .null }
            XCTAssertEqual(gaps, [
                NSRect(x: -10, y: 0, width: 10, height: 50), NSRect(x: 50, y: 0, width: 10, height: 50), NSRect(x: 110, y: 0, width: 10, height: 50),
                NSRect(x: -10, y: 60, width: 10, height: 50), NSRect(x: 50, y: 60, width: 10, height: 50), NSRect(x: 110, y: 60, width: 10, height: 50),
                NSRect(x: -10, y: 120, width: 10, height: 50), NSRect(x: 50, y: 120, width: 10, height: 50),
            ])
            let gap = grid.layoutAttributesForInterItemGap(before: IndexPath(item: 1, section: 0))!
            XCTAssertEqual(gap.representedElementCategory, .interItemGap)
            XCTAssertEqual(gap.representedElementKind, NSCollectionView.elementKindInterItemGapIndicator)
            XCTAssertNil(grid.layoutAttributesForInterItemGap(before: IndexPath(item: 8, section: 0)))
            XCTAssertNil(NSCollectionViewLayout().layoutAttributesForDropTarget(at: .zero), "the base layout has no targets")
        }
    }

    func testFlowDropTargetsInVerticalAndHorizontalFlows() {
        MainActor.assumeIsolated {
            let ds = DragSource()
            let flow = NSCollectionViewFlowLayout()
            flow.itemSize = NSSize(width: 50, height: 50)
            flow.minimumInteritemSpacing = 10
            flow.minimumLineSpacing = 10
            flow.sectionInset = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
            let cv = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 200, height: 300))
            cv.collectionViewLayout = flow
            cv.register(ColorItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("color"))
            cv.dataSource = ds
            _ = cv.numberOfSections
            flow.prepare()
            @MainActor func gap(_ i: Int) -> NSRect { flow.layoutAttributesForInterItemGap(before: IndexPath(item: i, section: 0))?.frame ?? .null }
            // As AppKit's: a spacing-wide gap ahead of each line's first item and after the last item.
            XCTAssertEqual(gap(0), NSRect(x: -5, y: 5, width: 10, height: 50))
            XCTAssertEqual(gap(1), NSRect(x: 55, y: 5, width: 10, height: 50))
            XCTAssertEqual(gap(3), NSRect(x: -5, y: 65, width: 10, height: 50))
            XCTAssertEqual(gap(7), NSRect(x: 55, y: 125, width: 10, height: 50))
            XCTAssertEqual(flow.layoutAttributesForDropTarget(at: NSPoint(x: 100, y: 200))?.indexPath, IndexPath(item: 7, section: 0))
            XCTAssertEqual(flow.layoutAttributesForDropTarget(at: NSPoint(x: 30, y: 30))?.representedElementCategory, .item)
            // The collection view proposes on/before from the item's middle half.
            XCTAssertEqual(cv._proposedDropTarget(at: NSPoint(x: 30, y: 30)).operation, .on)
            XCTAssertEqual(cv._proposedDropTarget(at: NSPoint(x: 8, y: 30)).indexPath, IndexPath(item: 0, section: 0))
            XCTAssertEqual(cv._proposedDropTarget(at: NSPoint(x: 52, y: 30)).indexPath, IndexPath(item: 1, section: 0))
            XCTAssertEqual(cv._proposedDropTarget(at: NSPoint(x: 52, y: 30)).operation, .before)
            // A horizontal flow: lines run down, the gaps lie across them.
            flow.scrollDirection = .horizontal
            _ = cv.numberOfSections
            flow.prepare()
            let a0 = flow.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame
            let a1 = flow.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))!.frame
            XCTAssertEqual(a1.minX, a0.minX, "the next item goes down the line")
            XCTAssertEqual(gap(1), NSRect(x: a0.minX, y: a0.maxY, width: 50, height: a1.minY - a0.maxY))
            XCTAssertEqual(cv._proposedDropTarget(at: NSPoint(x: a0.midX, y: a0.maxY - 2)).indexPath, IndexPath(item: 1, section: 0))
            // An empty section takes drops before its first item.
            ds.items = []
            cv.reloadData()
            _ = cv.numberOfSections
            flow.prepare()
            XCTAssertEqual(flow.layoutAttributesForDropTarget(at: NSPoint(x: 10, y: 10))?.indexPath, IndexPath(item: 0, section: 0))
            XCTAssertEqual(cv._proposedDropTarget(at: NSPoint(x: 10, y: 10)).operation, .before)
        }
    }

    // MARK: - Drag images

    func testItemDraggingImageComponentsMatchAppKit() {
        MainActor.assumeIsolated {
            final class Flipped: NSView { override var isFlipped: Bool { true } }
            // An image view and a text field: an icon and a label, at their frames.
            let v = NSView(frame: NSRect(x: 0, y: 0, width: 60, height: 60))
            let tf = NSTextField(labelWithString: "Hi")
            tf.frame = NSRect(x: 5, y: 5, width: 30, height: 17)
            let iv = NSImageView(frame: NSRect(x: 0, y: 20, width: 32, height: 32))
            v.addSubview(tf); v.addSubview(iv)
            let item = NSCollectionViewItem(nibName: nil, bundle: nil)
            item.view = v; item.textField = tf; item.imageView = iv
            let c = item.draggingImageComponents
            XCTAssertEqual(c.map(\.key), [.icon, .label])
            XCTAssertEqual(c.map(\.frame), [NSRect(x: 0, y: 20, width: 32, height: 32), NSRect(x: 5, y: 5, width: 30, height: 17)])
            XCTAssertEqual((c[1].contents as? NSImage)?.size, NSSize(width: 30, height: 17))
            // A flipped view with only a text field: one icon, measured from the bottom.
            let fv = Flipped(frame: NSRect(x: 0, y: 0, width: 60, height: 60))
            let tf2 = NSTextField(labelWithString: "Hi")
            tf2.frame = NSRect(x: 5, y: 5, width: 30, height: 17)
            fv.addSubview(tf2)
            let item2 = NSCollectionViewItem(nibName: nil, bundle: nil)
            item2.view = fv; item2.textField = tf2
            XCTAssertEqual(item2.draggingImageComponents.map(\.key), [.icon])
            XCTAssertEqual(item2.draggingImageComponents.map(\.frame), [NSRect(x: 5, y: 38, width: 30, height: 17)])
            // Neither: the whole view.
            let item3 = NSCollectionViewItem(nibName: nil, bundle: nil)
            item3.view = NSView(frame: NSRect(x: 0, y: 0, width: 60, height: 40))
            XCTAssertEqual(item3.draggingImageComponents.map(\.frame), [NSRect(x: 0, y: 0, width: 60, height: 40)])
            XCTAssertEqual((item3.draggingImageComponents[0].contents as? NSImage)?.size, NSSize(width: 60, height: 40))
        }
    }

    func testSnapshotsOfViewsInFlippedSuperviewsAreUpright() {
        MainActor.assumeIsolated {
            // A red band along the top of a y-up view, snapshotted inside a y-up and a flipped
            // superview (an item in a collection view): the band stays at the top (PR 86 PC round).
            final class Mark: NSView {
                override func draw(_ r: NSRect) { NSColor.red.setFill(); NSBezierPath(rect: NSRect(x: 0, y: bounds.height - 10, width: bounds.width, height: 10)).fill() }
            }
            final class Flipped: NSView { override var isFlipped: Bool { true } }
            for parent in [NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200)), Flipped(frame: NSRect(x: 0, y: 0, width: 200, height: 200))] {
                let m = Mark(frame: NSRect(x: 20, y: 30, width: 50, height: 50))
                parent.addSubview(m)
                let rep = m.bitmapImageRepForCachingDisplay(in: m.bounds)!
                m.cacheDisplay(in: m.bounds, to: rep)
                let s = rep.pixelsWide / 50
                XCTAssertEqual(rep.colorAt(x: 25 * s, y: 3 * s)!.redComponent, 1, accuracy: 0.05, "top, flipped superview: \(parent.isFlipped)")
                XCTAssertEqual(rep.colorAt(x: 25 * s, y: 47 * s)!.redComponent, 0, accuracy: 0.05, "bottom, flipped superview: \(parent.isFlipped)")
                // A part of the view: its upper half holds the band at its top.
                let half = m.bitmapImageRepForCachingDisplay(in: NSRect(x: 0, y: 25, width: 50, height: 25))!
                m.cacheDisplay(in: NSRect(x: 0, y: 25, width: 50, height: 25), to: half)
                XCTAssertEqual(half.colorAt(x: 25 * s, y: 3 * s)!.redComponent, 1, accuracy: 0.05)
                XCTAssertEqual(half.colorAt(x: 25 * s, y: 20 * s)!.redComponent, 0, accuracy: 0.05)
            }
        }
    }

    func testADragImageKeepsAComponentAtItsFrame() {
        MainActor.assumeIsolated {
            // An item whose one component (a label) is smaller than its frame: the image is
            // the frame's size with the label in its place, not the label stretched over it.
            let label = NSImage(size: NSSize(width: 50, height: 13), flipped: false) { r in NSColor.red.setFill(); NSBezierPath(rect: r).fill(); return true }
            let d = NSDraggingItem(pasteboardWriter: NSPasteboardItem())
            d.draggingFrame = NSRect(x: 0, y: 0, width: 56, height: 56)
            let c = NSDraggingImageComponent(key: .icon)
            c.frame = NSRect(x: 3, y: 3, width: 50, height: 13)
            c.contents = label
            d.imageComponentsProvider = { [c] }
            let image = _NSDragTracker.compositeImage(of: d)!
            XCTAssertEqual(image.size, NSSize(width: 56, height: 56))
            let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
            let scale = rep.pixelsWide / 56
            XCTAssertGreaterThan(rep.colorAt(x: 28 * scale, y: (56 - 8) * scale)?.redComponent ?? 0, 0.9, "the label at the bottom")
            XCTAssertLessThan(rep.colorAt(x: 28 * scale, y: 10 * scale)?.alphaComponent ?? 1, 0.1, "clear above it")
        }
    }

    func testDraggingImageForItemsCoversTheItems() {
        MainActor.assumeIsolated {
            let ds = DragSource()
            let f = Fixture(dataSource: ds)
            let e = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: f.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            var offset = NSPoint.zero
            let image = f.collectionView.draggingImageForItems(at: [IndexPath(item: 0, section: 0), IndexPath(item: 2, section: 0)], with: e, offset: &offset)
            XCTAssertEqual(image.size, NSSize(width: 170, height: 50), "the union of items 0 and 2")
            XCTAssertEqual(offset, .zero)
            var o2 = NSPoint.zero
            XCTAssertEqual(f.collectionView.draggingImageForItems(at: IndexSet([1]), with: e, offset: &o2).size, NSSize(width: 50, height: 50))
            f.window.close()
        }
    }

    // MARK: - Animated updates

    func testAnimatedBatchUpdatesEndAtTheInstantFrames() {
        MainActor.assumeIsolated {
            var clock: CFTimeInterval = 100
            CARuntime.now = { clock }
            defer { CARuntime.now = { ProcessInfo.processInfo.systemUptime } }
            let instantData = DragSource(), animatedData = DragSource()
            let instant = Fixture(dataSource: instantData)
            let animated = Fixture(dataSource: animatedData)
            let a = animated.collectionView
            XCTAssertNil(a.layer)
            let deleted = a.item(at: IndexPath(item: 1, section: 0))!
            let moved = a.item(at: IndexPath(item: 0, section: 0))!
            let movedFrom = moved.view.frame
            @MainActor func update(_ ds: DragSource, _ cv: NSCollectionView) {
                // a b c d e f g → delete b, insert x at 2, move a to 3: c d x a e f g
                ds.items = ["c", "d", "x", "a", "e", "f", "g"]
                cv.deleteItems(at: [IndexPath(item: 1, section: 0)])
                cv.insertItems(at: [IndexPath(item: 2, section: 0)])
                cv.moveItem(at: IndexPath(item: 0, section: 0), to: IndexPath(item: 3, section: 0))
            }
            var instantDone = false
            instant.collectionView.performBatchUpdates({ update(instantData, instant.collectionView) }, completionHandler: { instantDone = $0 })
            XCTAssertTrue(instantDone, "an instant update completes at once")
            XCTAssertNil(instant.collectionView.layer, "an instant update stays as it was")
            var done = false
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 1
                a.animator().performBatchUpdates({ update(animatedData, a) }, completionHandler: { done = $0 })
            }
            XCTAssertFalse(done, "the handler waits for the animation")
            XCTAssertNotNil(a.layer, "the collection view animates layer-backed")
            // The model is final at once: the same frames and texts as the instant update.
            @MainActor func frames(_ cv: NSCollectionView) -> [NSRect] { (0..<7).map { cv.item(at: IndexPath(item: $0, section: 0))!.view.frame } }
            XCTAssertEqual(frames(a), frames(instant.collectionView))
            XCTAssertEqual(animated.texts(), instant.texts())
            XCTAssertEqual(animated.texts(), ["c", "d", "x", "a", "e", "f", "g"])
            XCTAssertTrue(moved === a.item(at: IndexPath(item: 3, section: 0)), "the moved item keeps its view")
            // The moved item slides, the inserted one fades in, the deleted one fades out in place.
            XCTAssertNotNil(moved.view.layer?.animation(forKey: "position"))
            let inserted = a.item(at: IndexPath(item: 2, section: 0))!
            XCTAssertNotNil(inserted.view.layer?.animation(forKey: "opacity"))
            XCTAssertTrue(deleted.view.superview === a, "the deleted view stays while it fades")
            XCTAssertNotNil(deleted.view.layer?.animation(forKey: "opacity"))
            XCTAssertFalse(a.visibleItems().contains { $0 === deleted })
            clock = 100.5
            let mid = moved.view.layer!.presentation()!.position
            XCTAssertNotEqual(mid.x, moved.view.frame.minX, "halfway between")
            XCTAssertNotEqual(NSPoint(x: mid.x, y: mid.y), movedFrom.origin)
            clock = 102
            CARuntime.tick()
            XCTAssertTrue(done)
            XCTAssertNil(deleted.view.superview, "the deleted view goes when its fade ends")
            XCTAssertNil(moved.view.layer?.animationKeys())
            XCTAssertEqual(frames(a), frames(instant.collectionView))
            XCTAssertEqual(inserted.view.alphaValue, 1)
            instant.window.close(); animated.window.close()
        }
    }

    func testDiffableApplyAnimatesOnlyWhenAsked() {
        MainActor.assumeIsolated {
            var clock: CFTimeInterval = 50
            CARuntime.now = { clock }
            defer { CARuntime.now = { ProcessInfo.processInfo.systemUptime } }
            let holder = DragSource()          // only the fixture's delegate; the diffable source answers data
            let f = Fixture(dataSource: holder)
            let cv = f.collectionView
            let diffable = NSCollectionViewDiffableDataSource<Int, String>(collectionView: cv) { cv, ip, id in
                let item = cv.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("color"), for: ip)
                item.textField?.stringValue = id
                return item
            }
            var snap = NSDiffableDataSourceSnapshot<Int, String>()
            snap.appendSections([0])
            snap.appendItems(["a", "b", "c"])
            diffable.apply(snap, animatingDifferences: false)
            snap.appendItems(["d"])
            diffable.apply(snap, animatingDifferences: false)
            XCTAssertNil(cv.layer, "animatingDifferences: false is an instant update")
            XCTAssertEqual(cv.numberOfItems(inSection: 0), 4)
            snap.deleteItems(["a"])
            diffable.apply(snap, animatingDifferences: true)
            XCTAssertNotNil(cv.layer)
            XCTAssertNotNil(cv.item(at: IndexPath(item: 0, section: 0))?.view.layer?.animation(forKey: "position"), "b slides into a's place")
            XCTAssertEqual(cv.item(at: IndexPath(item: 0, section: 0))?.view.frame, NSRect(x: 0, y: 0, width: 50, height: 50))
            clock = 60
            CARuntime.tick()
            XCTAssertNil(cv.item(at: IndexPath(item: 0, section: 0))?.view.layer?.animationKeys())
            f.window.close()
        }
    }

    func testTransactionCompletionsWaitOnlyForTheirOwnAnimations() {
        MainActor.assumeIsolated {
            var clock: CFTimeInterval = 10
            CARuntime.now = { clock }
            defer { CARuntime.now = { ProcessInfo.processInfo.systemUptime } }
            // A long animation's group must not hold up a later, shorter one's completion
            // (an off-screen update used to block every completion after it).
            let slow = CALayer(), fast = CALayer()
            var slowDone = false, fastDone = false
            CATransaction.begin()
            CATransaction.setCompletionBlock { slowDone = true }
            let s1 = CABasicAnimation(keyPath: "position"); s1.duration = 10
            slow.add(s1, forKey: "position")
            CATransaction.commit()
            CATransaction.begin()
            CATransaction.setCompletionBlock { fastDone = true }
            let f1 = CABasicAnimation(keyPath: "opacity"); f1.duration = 1
            fast.add(f1, forKey: "opacity")
            CATransaction.commit()
            XCTAssertFalse(fastDone)
            clock = 11.5
            _ = fast._advanceAnimations(now: clock)
            XCTAssertTrue(fastDone)
            XCTAssertFalse(slowDone)
            // Replacing an animation under its key ends the old one for its group.
            var replacedDone = false
            CATransaction.begin()
            CATransaction.setCompletionBlock { replacedDone = true }
            let a = CABasicAnimation(keyPath: "opacity"); a.duration = 5
            slow.add(a, forKey: "opacity")
            CATransaction.commit()
            slow.add(CABasicAnimation(keyPath: "opacity"), forKey: "opacity")
            XCTAssertTrue(replacedDone)
            clock = 30
            _ = slow._advanceAnimations(now: clock)
            XCTAssertTrue(slowDone)
        }
    }

    // MARK: - Legacy API and archiving

    func testLegacyFrameForItemAndNewItem() {
        MainActor.assumeIsolated {
            final class Proto: NSCollectionViewItem {
                override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 30)) }
            }
            let cv = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            cv.minItemSize = NSSize(width: 40, height: 30)
            cv.maxItemSize = NSSize(width: 40, height: 30)
            // AppKit 15: one column for one item, else as many as fit (7 here), item 3 in the fourth.
            XCTAssertEqual(cv.frameForItem(at: 0, withNumberOfItems: 1), NSRect(x: 0, y: 0, width: 40, height: 30))
            XCTAssertEqual(cv.frameForItem(at: 3, withNumberOfItems: 1), NSRect(x: 0, y: 90, width: 40, height: 30))
            XCTAssertEqual(cv.frameForItem(at: 3, withNumberOfItems: 5), NSRect(x: 120, y: 0, width: 40, height: 30))
            XCTAssertEqual(cv.frameForItem(at: 3, withNumberOfItems: 20), NSRect(x: 120, y: 0, width: 40, height: 30))
            XCTAssertEqual(cv.frameForItem(at: 7, withNumberOfItems: 20), NSRect(x: 0, y: 30, width: 40, height: 30))
            let proto = Proto(nibName: nil, bundle: nil)
            _ = proto.view
            cv.itemPrototype = proto
            let item = cv.newItem(forRepresentedObject: "hello")
            XCTAssertFalse(item === proto)
            XCTAssertTrue(item is Proto)
            XCTAssertEqual(item.representedObject as? String, "hello")
            XCTAssertFalse(item.view === proto.view)
            XCTAssertEqual(item.view.frame.size, NSSize(width: 40, height: 30))
            XCTAssertNil(item.collectionView)
        }
    }

    func testLayoutsArchiveUnderAppKitKeys() throws {
        try MainActor.assumeIsolated {
            let flow = NSCollectionViewFlowLayout()
            flow.itemSize = NSSize(width: 70, height: 40)
            flow.minimumLineSpacing = 3
            flow.minimumInteritemSpacing = 4
            flow.scrollDirection = .horizontal
            flow.sectionInset = NSEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)
            flow.headerReferenceSize = NSSize(width: 5, height: 6)
            flow.sectionHeadersPinToVisibleBounds = true
            let archiver = NSKeyedArchiver(requiringSecureCoding: false)
            archiver.encode(flow, forKey: "root")
            archiver.finishEncoding()
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
            unarchiver.requiresSecureCoding = false
            let back = try XCTUnwrap(unarchiver.decodeObject(forKey: "root") as? NSCollectionViewFlowLayout)
            XCTAssertEqual(back.itemSize, NSSize(width: 70, height: 40))
            XCTAssertEqual(back.minimumLineSpacing, 3)
            XCTAssertEqual(back.minimumInteritemSpacing, 4)
            XCTAssertEqual(back.scrollDirection, .horizontal)
            XCTAssertEqual(back.sectionInset.left, 2)
            XCTAssertEqual(back.sectionInset.bottom, 3)
            XCTAssertEqual(back.headerReferenceSize, NSSize(width: 5, height: 6))
            XCTAssertEqual(back.footerReferenceSize, .zero)
            XCTAssertTrue(back.sectionHeadersPinToVisibleBounds)
            let grid = NSCollectionViewGridLayout()
            grid.maximumNumberOfColumns = 8
            grid.minimumItemSize = NSSize(width: 9, height: 10)
            grid.minimumLineSpacing = 6
            let a2 = NSKeyedArchiver(requiringSecureCoding: false)
            a2.encode(grid, forKey: "root")
            a2.finishEncoding()
            let u2 = try NSKeyedUnarchiver(forReadingFrom: a2.encodedData)
            u2.requiresSecureCoding = false
            let g = try XCTUnwrap(u2.decodeObject(forKey: "root") as? NSCollectionViewGridLayout)
            XCTAssertEqual(g.maximumNumberOfColumns, 8)
            XCTAssertEqual(g.minimumItemSize, NSSize(width: 9, height: 10))
            XCTAssertEqual(g.minimumLineSpacing, 6)
            XCTAssertEqual(g.maximumNumberOfRows, 0)
        }
    }
}
