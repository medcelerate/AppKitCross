// Drag and drop tracking. A dragging session started from a view is driven in-process:
// NSApplication hands every mouse and key event to the tracker, which moves the drag
// image window, finds the destination view under the pointer (across this
// application's windows, by registered types) and sends it the NSDraggingDestination
// messages. Drags to and from other applications are the platform backends' half.

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

/// The translucent image that follows the pointer.
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

// MARK: Tracker

@MainActor
final class _NSDragTracker {
    private(set) static var current: _NSDragTracker?
    static var isDragging: Bool { current != nil }

    let session: NSDraggingSession
    let info: _NSDraggingInfo
    private weak var source: (any NSDraggingSource)?
    private weak var sourceView: NSView?
    private var imageWindow: _NSDragImageWindow?
    private var imageOffset: NSPoint = .zero         // pointer to the image frame's bottom-left, in points
    private var destinationView: NSView?
    private var destinationOperation: NSDragOperation = []
    private var modifierMask: NSDragOperation = .every
    private(set) var finished = false
    private(set) var result: NSDragOperation = []
    /// Set by an in-process destination that wants to be told when the drag ends.
    private var destinationsSeen: [NSView] = []

    /// Starts a drag for `items` from `view`. The pointer is at `event`'s location.
    static func begin(items: [NSDraggingItem], event: NSEvent, source: any NSDraggingSource, view: NSView) -> NSDraggingSession {
        current?.cancel()
        let session = NSDraggingSession(items: items, source: source as AnyObject)
        let t = _NSDragTracker(session: session, source: source, view: view, event: event)
        current = t
        return session
    }

    private init(session: NSDraggingSession, source: any NSDraggingSource, view: NSView, event: NSEvent) {
        self.session = session
        self.source = source
        self.sourceView = view
        let mask = source.draggingSession(session, sourceOperationMaskFor: .withinApplication)
        info = _NSDraggingInfo(session: session, source: source as AnyObject, mask: mask)
        let screen = _NSDragTracker.screenPoint(of: event)
        session._location = screen
        // The image: the leader item's first component, or a placeholder of its frame.
        let leader = session._items.indices.contains(session.draggingLeaderIndex) ? session._items[session.draggingLeaderIndex] : session._items.first
        let frameInView = leader?.draggingFrame ?? NSRect(x: -8, y: -8, width: 16, height: 16)
        let component = leader?.imageComponents?.first
        let image = component?.contents as? NSImage
        let size = frameInView.size == .zero ? NSSize(width: 16, height: 16) : frameInView.size
        // Where the pointer sits inside the frame (frames are in the source view's space).
        let pointerInView = view.convert(event.locationInWindow, from: nil)
        let frameInWindow = view.convert(frameInView, to: nil)
        _ = pointerInView
        let pointerInWindow = event.locationInWindow
        imageOffset = NSPoint(x: frameInWindow.minX - pointerInWindow.x, y: frameInWindow.minY - pointerInWindow.y)
        if frameInView.size == .zero { imageOffset = NSPoint(x: -8, y: -8) }
        let w = _NSDragImageWindow(image: image, size: size)
        w.setFrame(NSRect(origin: NSPoint(x: screen.x + imageOffset.x, y: screen.y + imageOffset.y), size: size), display: false)
        w.orderFront(nil)
        imageWindow = w
        source.draggingSession(session, willBeginAt: screen)
        updateModifiers(event.modifierFlags)
        // The drag may start over a destination already.
        moved(to: screen, flags: event.modifierFlags)
    }

    private static func screenPoint(of event: NSEvent) -> NSPoint {
        if let w = event.window { return w.convertPoint(toScreen: event.locationInWindow) }
        return event.locationInWindow
    }

    private func updateModifiers(_ flags: NSEvent.ModifierFlags) {
        if source?.ignoreModifierKeys(for: session) == true { modifierMask = .every; return }
        if flags.contains(.option) { modifierMask = .copy }
        else if flags.contains(.control) { modifierMask = .link }
        else if flags.contains(.command) { modifierMask = .generic }
        else { modifierMask = .every }
    }

    /// The registered destination view under a screen point, and its window.
    private func destination(at point: NSPoint) -> (NSView, NSWindow)? {
        let app = NSApplication.shared
        var candidates: [NSWindow] = []
        if let k = app.keyWindow { candidates.append(k) }
        candidates += app.windows.reversed().filter { !candidates.contains($0) }
        let types = session.draggingPasteboard.types ?? []
        for w in candidates where w.isVisible && !(w is _NSDragImageWindow) && !(w is _NSMenuWindow) && w.frame.contains(point) {
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

    /// Handles an event while dragging. Every event is consumed.
    func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .mouseMoved:
            moved(to: _NSDragTracker.screenPoint(of: event), flags: event.modifierFlags)
        case .flagsChanged:
            updateModifiers(event.modifierFlags)
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

    private func moved(to point: NSPoint, flags: NSEvent.ModifierFlags) {
        session._location = point
        if let w = imageWindow {
            w.setFrame(NSRect(origin: NSPoint(x: point.x + imageOffset.x, y: point.y + imageOffset.y), size: w.frame.size), display: true)
        }
        source?.draggingSession(session, movedTo: point)
        let hit = destination(at: point)
        if let (view, window) = hit {
            info.destinationWindow = window
            info.locationInDestination = window.convertPoint(fromScreen: point)
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
        } else if let old = destinationView {
            old.draggingExited(info)
            destinationView = nil
            destinationOperation = []
        }
        updateCursor()
    }

    /// The operation the drop would perform now: the destination's answer, limited by the
    /// source and the modifier keys. One operation is chosen when several are offered.
    private var effectiveOperation: NSDragOperation {
        let allowed = destinationOperation.intersection(info.sourceOperationMask).intersection(modifierMask)
        for one in [NSDragOperation.copy, .move, .link, .generic, .private, .delete] where allowed.contains(one) { return one }
        return []
    }

    private func updateCursor() {
        let op = effectiveOperation
        if destinationView != nil && op == [] { NSCursor.operationNotAllowed.set() }
        else if op == .copy { NSCursor.dragCopy.set() }
        else if op == .link { NSCursor.dragLink.set() }
        else { NSCursor.arrow.set() }
    }

    private func drop() {
        guard !finished else { return }
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
        end(with: performed)
    }

    /// Ends the drag without dropping.
    func cancel() {
        guard !finished else { return }
        destinationView?.draggingExited(info)
        end(with: [])
    }

    private func end(with operation: NSDragOperation) {
        finished = true
        result = operation
        destinationView = nil
        imageWindow?.close()
        imageWindow = nil
        NSCursor.arrow.set()
        if _NSDragTracker.current === self { _NSDragTracker.current = nil }
        for v in destinationsSeen { v.draggingEnded(info) }
        source?.draggingSession(session, endedAt: session._location, operation: operation)
    }
}
