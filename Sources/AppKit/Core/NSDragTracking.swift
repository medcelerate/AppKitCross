// Drag and drop tracking (ADR-0011).
//
// A dragging session started from a view is tracked by `_NSDragTracker`. On platforms
// where the application keeps the pointer during a drag (the host backend, X11), the
// tracker takes every mouse and key event from `NSApplication.sendEvent`, moves the drag
// image window, and drives the destinations itself; while the pointer is over no window
// of this application it hands the position to the backend, which talks to other
// applications' windows. On platforms that run drags themselves (OLE on Windows, the
// Wayland data device) the tracker hands the drag over at the start and the backend
// delivers it back to this application's windows through the `PlatformWindowOwner` drag
// methods, exactly as it delivers drags from other applications.
//
// `_NSDragDestinationDriver` is the part both paths share: finding the destination view
// under a point (by registered types, walking up from the hit view) and sending it the
// NSDraggingDestination messages in AppKit's order.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: Dragging info

/// What a destination sees of a drag in progress.
@MainActor
final class _NSDraggingInfo: NSObject, NSDraggingInfo {
    let session: NSDraggingSession
    weak var source: AnyObject?
    var sourceOperationMask: NSDragOperation
    var destinationWindow: NSWindow?
    var locationInDestination: NSPoint = .zero     // destination window content coordinates
    var _animatesToDestination = false
    var _numberOfValidItems = 0

    init(session: NSDraggingSession, source: AnyObject?, mask: NSDragOperation) {
        self.session = session
        self.source = source
        self.sourceOperationMask = mask
        _numberOfValidItems = session._items.count
    }

    var animatesToDestination: Bool {
        get { _animatesToDestination }
        set { _animatesToDestination = newValue }
    }
    nonisolated var draggedImage: NSImage? {
        MainActor.assumeIsolated { session._items.first?.imageComponents?.first?.contents as? NSImage }
    }
    var draggedImageLocation: NSPoint {
        let frame = session._items.first?.draggingFrame ?? .zero
        return NSPoint(x: locationInDestination.x + frame.minX, y: locationInDestination.y + frame.minY)
    }
    var draggingDestinationWindow: NSWindow? { destinationWindow }
    var draggingFormation: NSDraggingFormation {
        get { session.draggingFormation }
        set { session.draggingFormation = newValue }
    }
    var draggingLocation: NSPoint { locationInDestination }
    var draggingPasteboard: NSPasteboard { session.draggingPasteboard }
    var draggingSequenceNumber: Int { session.draggingSequenceNumber }
    var draggingSource: Any? { source }
    var draggingSourceOperationMask: NSDragOperation { sourceOperationMask }
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey : Any], using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        session.enumerateDraggingItems(options: enumOpts, for: view, classes: classArray, searchOptions: searchOptions, using: block)
    }
    nonisolated func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    var numberOfValidItemsForDrop: Int {
        get { _numberOfValidItems }
        set { _numberOfValidItems = newValue }
    }
    func resetSpringLoading() { }
    func slideDraggedImage(to screenPoint: NSPoint) { }
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
}

// MARK: Drag image window

/// The translucent image that follows the pointer on platforms where the application
/// draws it itself.
@MainActor
final class _NSDragImageWindow: NSPanel {
    private let image: NSImage?
    private let size: NSSize

    init(image: NSImage?, size: NSSize) {
        self.image = image
        self.size = size
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        let v = _NSDragImageView(frame: NSRect(origin: .zero, size: size))
        v.image = image
        contentView = v
    }
    required init?(coder: NSCoder) { nil }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class _NSDragImageView: NSView {
    var image: NSImage?
    override func draw(_ dirtyRect: NSRect) {
        if let image {
            image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 0.7)
        } else {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
    }
}

// MARK: Destinations

/// Drives the NSDraggingDestination messages for one drag: finds the registered view
/// under the pointer, sends entered/updated/exited as it changes, performs the drop, and
/// tells every destination that saw the drag when it ends.
@MainActor
final class _NSDragDestinationDriver {
    let info: _NSDraggingInfo
    private(set) var destinationView: NSView?
    private var destinationOperation: NSDragOperation = []
    private var destinationsSeen: [NSView] = []
    private var modifierMask: NSDragOperation = .every
    /// `NSDraggingSource.ignoreModifierKeys`: the source wants the destination's answer unfiltered.
    var ignoresModifierKeys = false

    init(info: _NSDraggingInfo) { self.info = info }

    func updateModifiers(_ flags: NSEvent.ModifierFlags) {
        if ignoresModifierKeys { modifierMask = .every; return }
        if flags.contains(.option) { modifierMask = .copy }
        else if flags.contains(.control) { modifierMask = .link }
        else if flags.contains(.command) { modifierMask = .generic }
        else { modifierMask = .every }
    }

    /// The registered destination view under a screen point, searching `window` only
    /// or, with nil, this application's windows front to back.
    private func destination(at point: NSPoint, in window: NSWindow?) -> (NSView, NSWindow)? {
        var candidates: [NSWindow] = []
        if let window {
            candidates = [window]
        } else {
            let app = NSApplication.shared
            if let k = app.keyWindow { candidates.append(k) }
            candidates += app.windows.reversed().filter { !candidates.contains($0) }
        }
        let types = info.session.draggingPasteboard.types ?? []
        for w in candidates where w.isVisible && !(w is _NSDragImageWindow) && !(w is _NSMenuWindow) && (window != nil || w.frame.contains(point)) {
            guard let content = w.contentView else { continue }
            let local = w.convertPoint(fromScreen: point)
            var v: NSView? = content.hitTest(local) ?? content
            while let view = v {
                if view._acceptsDraggedTypes(types) { return (view, w) }
                v = view.superview
            }
            return nil      // the topmost window under the pointer decides
        }
        return nil
    }

    /// Tracks the pointer to `point`: enters, updates or exits destinations as needed and
    /// returns the operation a drop would perform now.
    @discardableResult
    func track(screenPoint point: NSPoint, in window: NSWindow?) -> NSDragOperation {
        if let (view, w) = destination(at: point, in: window) {
            info.destinationWindow = w
            info.locationInDestination = w.convertPoint(fromScreen: point)
            if view !== destinationView {
                if let old = destinationView { old.draggingExited(info) }
                destinationView = view
                if !destinationsSeen.contains(where: { $0 === view }) { destinationsSeen.append(view) }
                let op = view.draggingEntered(info)
                view._lastDraggingEnteredOperation = op
                destinationOperation = op
            } else {
                destinationOperation = view.draggingUpdated(info)
            }
        } else {
            exit()
        }
        return effectiveOperation
    }

    /// The pointer left this application's windows (or the drag was cancelled over one).
    func exit() {
        guard let old = destinationView else { return }
        old.draggingExited(info)
        destinationView = nil
        destinationOperation = []
    }

    /// The operation the drop would perform now: the destination's answer, limited by the
    /// source and the modifier keys. One operation is chosen when several are offered.
    var effectiveOperation: NSDragOperation {
        guard destinationView != nil else { return [] }
        let allowed = destinationOperation.intersection(info.sourceOperationMask).intersection(modifierMask)
        for one in [NSDragOperation.copy, .move, .link, .generic, .private, .delete] where allowed.contains(one) { return one }
        return []
    }

    /// Sets the cursor for the current destination's answer (tracker-driven drags).
    func updateCursor() {
        let op = effectiveOperation
        if destinationView != nil && op == [] { NSCursor.operationNotAllowed.set() }
        else if op == .copy { NSCursor.dragCopy.set() }
        else if op == .link { NSCursor.dragLink.set() }
        else { NSCursor.arrow.set() }
    }

    /// Performs the drop on the current destination; returns the operation performed.
    func drop() -> NSDragOperation {
        let op = effectiveOperation
        var performed: NSDragOperation = []
        if let view = destinationView, op != [] {
            if view.prepareForDragOperation(info), view.performDragOperation(info) {
                performed = op
                view.concludeDragOperation(info)
            } else {
                view.draggingExited(info)
            }
        } else if let view = destinationView {
            view.draggingExited(info)
        }
        destinationView = nil
        destinationOperation = []
        return performed
    }

    /// The drag is over: every destination that saw it hears `draggingEnded`.
    func end() {
        for v in destinationsSeen { v.draggingEnded(info) }
        destinationsSeen.removeAll()
    }
}

// MARK: Tracker

@MainActor
final class _NSDragTracker: PlatformDragSource {
    private(set) static var current: _NSDragTracker?
    static var isDragging: Bool { current != nil }
    /// A tracker whose drop a foreign window took: kept until the outcome arrives.
    private static var awaitingOutcome: _NSDragTracker?

    let session: NSDraggingSession
    let driver: _NSDragDestinationDriver
    var info: _NSDraggingInfo { driver.info }
    private weak var source: (any NSDraggingSource)?
    private weak var sourceView: NSView?
    private var imageWindow: _NSDragImageWindow?
    private var imageOffset: NSPoint = .zero         // pointer to the image frame's bottom-left, in points
    private let imageSize: NSSize
    private let image: NSImage?
    /// The window system runs this drag (OLE, Wayland): events are not ours to track.
    private(set) var platformDriven = false
    /// A foreign window took the drop; the outcome arrives through `platformDragEnded`.
    private var awaitingForeignDrop = false
    private(set) var finished = false
    private(set) var result: NSDragOperation = []

    /// Starts a drag for `items` from `view`. The pointer is at `event`'s location.
    static func begin(items: [NSDraggingItem], event: NSEvent, source: any NSDraggingSource, view: NSView) -> NSDraggingSession {
        current?.cancel()
        let session = NSDraggingSession(items: items, source: source as AnyObject)
        let t = _NSDragTracker(session: session, source: source, view: view, event: event)
        current = t
        t.start(event: event, view: view)
        return session
    }

    private init(session: NSDraggingSession, source: any NSDraggingSource, view: NSView, event: NSEvent) {
        self.session = session
        self.source = source
        self.sourceView = view
        let mask = source.draggingSession(session, sourceOperationMaskFor: .withinApplication)
        driver = _NSDragDestinationDriver(info: _NSDraggingInfo(session: session, source: source as AnyObject, mask: mask))
        driver.ignoresModifierKeys = source.ignoreModifierKeys(for: session)
        // The image: the leader item's first component, or a placeholder of its frame.
        let leader = session._items.indices.contains(session.draggingLeaderIndex) ? session._items[session.draggingLeaderIndex] : session._items.first
        let frameInView = leader?.draggingFrame ?? NSRect(x: -8, y: -8, width: 16, height: 16)
        image = leader?.imageComponents?.first?.contents as? NSImage
        imageSize = frameInView.size == .zero ? NSSize(width: 16, height: 16) : frameInView.size
        // Where the pointer sits inside the frame (frames are in the source view's space).
        let frameInWindow = view.convert(frameInView, to: nil)
        let pointerInWindow = event.locationInWindow
        imageOffset = NSPoint(x: frameInWindow.minX - pointerInWindow.x, y: frameInWindow.minY - pointerInWindow.y)
        if frameInView.size == .zero { imageOffset = NSPoint(x: -8, y: -8) }
    }

    private func start(event: NSEvent, view: NSView) {
        let screen = _NSDragTracker.screenPoint(of: event)
        session._location = screen
        source?.draggingSession(session, willBeginAt: screen)
        driver.updateModifiers(event.modifierFlags)
        // A platform that runs drags takes it from here; it returns once the drag is over
        // on Windows (OLE is modal), later on Wayland.
        if let dd = Platform.backend.dragDrop, let pw = view.window?._platformWindow {
            platformDriven = true
            if dd.beginDrag(from: pw, entries: pasteboardEntries(), operations: info.sourceOperationMask, image: nativeImage(), source: self) { return }
            platformDriven = false
        }
        let w = _NSDragImageWindow(image: image, size: imageSize)
        w.setFrame(NSRect(origin: NSPoint(x: screen.x + imageOffset.x, y: screen.y + imageOffset.y), size: imageSize), display: false)
        w.orderFront(nil)
        imageWindow = w
        // The drag may start over a destination already.
        moved(to: screen, flags: event.modifierFlags)
    }

    /// Every representation of every item, for a platform that carries the data itself.
    private func pasteboardEntries() -> [(item: Int, entry: PlatformPasteboardEntry)] {
        var entries: [(item: Int, entry: PlatformPasteboardEntry)] = []
        for (i, item) in (session.draggingPasteboard.pasteboardItems ?? []).enumerated() {
            for t in item.types { if let d = item.data(forType: t) { entries.append((i, PlatformPasteboardEntry(type: t.rawValue, data: d))) } }
        }
        return entries
    }

    /// The drag image as pixels (the placeholder drawn when the item has none).
    private func nativeImage() -> PlatformDragImage? {
        #if canImport(Darwin)
        return nil
        #else
        let scale = sourceView?.window?.backingScaleFactor ?? 1
        guard imageSize.width > 0, imageSize.height > 0, let surface = Platform.backend.image.makeOffscreen(size: imageSize, scale: scale) else { return nil }
        let ctx = surface.context
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let v = _NSDragImageView(frame: NSRect(origin: .zero, size: imageSize))
        v.image = image
        v.draw(v.bounds)
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = surface.makeImage(), cg.bitsPerPixel == 32 else { return nil }
        var bgra = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        cg.data.withUnsafeBytes { src in
            for row in 0..<cg.height {
                let from = src.baseAddress! + row * cg.bytesPerRow
                bgra.withUnsafeMutableBytes { dst in dst.baseAddress!.advanced(by: row * cg.width * 4).copyMemory(from: from, byteCount: cg.width * 4) }
            }
        }
        let hot = (x: Int((-imageOffset.x * scale).rounded()), y: Int(((imageSize.height + imageOffset.y) * scale).rounded()))
        return PlatformDragImage(width: cg.width, height: cg.height, scale: scale, bgra: bgra, hotspot: hot)
        #endif
    }

    private static func screenPoint(of event: NSEvent) -> NSPoint {
        if let w = event.window { return w.convertPoint(toScreen: event.locationInWindow) }
        return event.locationInWindow
    }

    /// Handles an event while dragging. Every event is consumed.
    func handle(_ event: NSEvent) {
        guard !platformDriven, !awaitingForeignDrop else { return }
        switch event.type {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .mouseMoved:
            moved(to: _NSDragTracker.screenPoint(of: event), flags: event.modifierFlags)
        case .flagsChanged:
            driver.updateModifiers(event.modifierFlags)
            moved(to: session._location, flags: event.modifierFlags)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            moved(to: _NSDragTracker.screenPoint(of: event), flags: event.modifierFlags)
            drop()
        case .keyDown:
            if event.keyCode == 53 { cancel() }
        default:
            break
        }
    }

    /// The source's operations, limited by the modifier keys, for a foreign window.
    private var foreignOperations: NSDragOperation {
        var mask: NSDragOperation = .every
        if !driver.ignoresModifierKeys {
            let flags = NSEvent._currentModifierFlags
            if flags.contains(.option) { mask = .copy } else if flags.contains(.control) { mask = .link } else if flags.contains(.command) { mask = .generic }
        }
        return info.sourceOperationMask.intersection(mask)
    }

    private func moved(to point: NSPoint, flags: NSEvent.ModifierFlags) {
        session._location = point
        if let w = imageWindow {
            w.setFrame(NSRect(origin: NSPoint(x: point.x + imageOffset.x, y: point.y + imageOffset.y), size: w.frame.size), display: true)
        }
        source?.draggingSession(session, movedTo: point)
        driver.updateModifiers(flags)
        driver.track(screenPoint: point, in: nil)
        if driver.destinationView == nil, let dd = Platform.backend.dragDrop {
            // Over no window of ours: another application's window may be there.
            let op = dd.foreignDragMoved(to: point, operations: foreignOperations)
            if op == .copy { NSCursor.dragCopy.set() } else if op == .link { NSCursor.dragLink.set() } else { NSCursor.arrow.set() }
            return
        }
        Platform.backend.dragDrop?.foreignDragEnded()
        driver.updateCursor()
    }

    private func drop() {
        guard !finished else { return }
        if driver.destinationView == nil, let dd = Platform.backend.dragDrop, dd.foreignDrop(at: session._location, operations: foreignOperations) {
            // A foreign window takes it; the image goes now, the outcome comes later.
            awaitingForeignDrop = true
            _NSDragTracker.awaitingOutcome = self
            imageWindow?.close()
            imageWindow = nil
            NSCursor.arrow.set()
            if _NSDragTracker.current === self { _NSDragTracker.current = nil }
            return
        }
        end(with: driver.drop())
    }

    /// Ends the drag without dropping.
    func cancel() {
        guard !finished, !platformDriven else { return }
        driver.exit()
        end(with: [])
    }

    private func end(with operation: NSDragOperation) {
        guard !finished else { return }
        finished = true
        result = operation
        imageWindow?.close()
        imageWindow = nil
        if !platformDriven {
            NSCursor.arrow.set()
            Platform.backend.dragDrop?.foreignDragEnded()
        }
        if _NSDragTracker.current === self { _NSDragTracker.current = nil }
        driver.end()
        source?.draggingSession(session, endedAt: session._location, operation: operation)
        if _NSDragTracker.awaitingOutcome === self { _NSDragTracker.awaitingOutcome = nil }
    }

    // MARK: PlatformDragSource

    func platformDragEnded(at screenPoint: NSPoint, operation: NSDragOperation) {
        session._location = screenPoint
        end(with: operation)
    }
}

// MARK: Drags delivered by the window system

/// Routes the `PlatformWindowOwner` drag methods: a drag this application started goes to
/// its tracker's driver; one from another application gets a session of its own, whose
/// pasteboard loads each representation from the platform on demand.
@MainActor
enum _NSPlatformDragDelivery {
    private static var foreign: _NSDragDestinationDriver?
    /// The drag `foreign` was made for. A backend describes each drag with its own
    /// PlatformDragInfo, so another one entering means the earlier drag left without a drop
    /// (OLE sends no "drag over" to the application): its session must not carry the new
    /// drag's drop, or the drop reads the earlier drag's data.
    private static weak var foreignInfo: PlatformDragInfo?

    private static func driver(for drag: PlatformDragInfo) -> _NSDragDestinationDriver? {
        if drag.isFromThisApplication { return _NSDragTracker.current?.driver }
        if let f = foreign, foreignInfo === drag { return f }
        if foreign != nil { foreignDragLeft() }
        let load = drag.load
        let items: [NSPasteboardItem] = drag.items.enumerated().map { index, types in
            let item = NSPasteboardItem()
            let provider = _NSClosurePasteboardDataProvider { type in load(index, type.rawValue) }
            _ = item.setDataProvider(provider, forTypes: types.map { NSPasteboard.PasteboardType($0) })
            return item
        }
        let pb = NSPasteboard(name: NSPasteboard.Name("drag-foreign-\(NSDraggingSession._nextSequenceNumber)"))
        pb._setItems(items)
        let session = NSDraggingSession(pasteboard: pb, items: items.map { NSDraggingItem(pasteboardWriter: $0) }, source: nil)
        let d = _NSDragDestinationDriver(info: _NSDraggingInfo(session: session, source: nil, mask: drag.sourceOperations))
        foreign = d
        foreignInfo = drag
        return d
    }

    private static func prepare(_ d: _NSDragDestinationDriver, _ drag: PlatformDragInfo, _ window: NSWindow) -> NSPoint {
        if !drag.isFromThisApplication { d.info.sourceOperationMask = drag.sourceOperations }
        d.updateModifiers(drag.modifierFlags)
        let screen = window.convertPoint(toScreen: drag.location)
        d.info.session._location = screen
        return screen
    }

    private static func trace(_ what: String, _ d: _NSDragDestinationDriver, _ op: NSDragOperation) {
        if NSView._traceInvalidation { NSView._trace("platform drag \(what): destination \(d.destinationView.map { String(describing: type(of: $0)) } ?? "none") source mask \(d.info.sourceOperationMask.rawValue) -> \(op.rawValue)") }
    }

    static func entered(_ drag: PlatformDragInfo, window: NSWindow) -> NSDragOperation {
        guard let d = driver(for: drag) else { if NSView._traceInvalidation { NSView._trace("platform drag entered: no driver (local \(drag.isFromThisApplication), tracker \(_NSDragTracker.current != nil))") }; return [] }
        let screen = prepare(d, drag, window)
        let op = d.track(screenPoint: screen, in: window)
        trace("entered", d, op)
        return op
    }

    static func updated(_ drag: PlatformDragInfo, window: NSWindow) -> NSDragOperation {
        guard let d = driver(for: drag) else { return [] }
        let screen = prepare(d, drag, window)
        let op = d.track(screenPoint: screen, in: window)
        trace("updated", d, op)
        return op
    }

    static func exited(window: NSWindow) {
        (_NSDragTracker.current?.driver ?? foreign)?.exit()
    }

    static func drop(_ drag: PlatformDragInfo, window: NSWindow) -> NSDragOperation {
        guard let d = driver(for: drag) else { return [] }
        let screen = prepare(d, drag, window)
        d.track(screenPoint: screen, in: window)
        trace("drop", d, d.effectiveOperation)
        let performed = d.drop()
        if NSView._traceInvalidation { NSView._trace("platform drag performed \(performed.rawValue)") }
        if !drag.isFromThisApplication {
            d.end()
            foreign = nil
            foreignInfo = nil
        }
        return performed
    }

    /// A foreign drag left the application without dropping (every window told).
    static func foreignDragLeft() {
        guard let d = foreign else { return }
        d.exit()
        d.end()
        foreign = nil
        foreignInfo = nil
    }
}

/// A pasteboard data provider over a closure (data from the window system on demand).
final class _NSClosurePasteboardDataProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
    private let load: @MainActor (NSPasteboard.PasteboardType) -> Data?
    init(_ load: @escaping @MainActor (NSPasteboard.PasteboardType) -> Data?) { self.load = load }
    nonisolated func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        MainActor.assumeIsolated {
            if let d = load(type) { _ = item.setData(d, forType: type) }
        }
    }
}
