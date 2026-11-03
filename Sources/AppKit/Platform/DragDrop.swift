// Drag and drop seam (ADR-0011, stage B): drags to and from other applications.
//
// AppKit tracks a drag within the application itself (`_NSDragTracker`). The window
// system's half comes in two shapes:
//
// - Platforms that run the drag (OLE on Windows, the Wayland data device) take it over
//   from `beginDrag`: they move the pointer image, talk to every window including this
//   application's, and report the outcome through `PlatformDragSource`. The application's
//   own windows receive such drags, and drags from other applications, through the
//   `PlatformWindowOwner` drag methods.
// - Platforms where the application keeps the pointer (X11 with its implicit grab) leave
//   the tracker in charge; it calls `foreignDragMoved`/`foreignDrop` only while the pointer
//   is over no window of this application, and the backend speaks XDND to whatever is there.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The pointer image of a native drag: premultiplied BGRA pixels, top row first, and the
/// pointer's position inside the image.
public struct PlatformDragImage: Sendable {
    public var width: Int
    public var height: Int
    public var scale: CGFloat
    public var bgra: [UInt8]
    public var hotspot: (x: Int, y: Int)
    public init(width: Int, height: Int, scale: CGFloat, bgra: [UInt8], hotspot: (x: Int, y: Int)) {
        self.width = width; self.height = height; self.scale = scale; self.bgra = bgra; self.hotspot = hotspot
    }
}

/// A drag in progress over one of this application's windows, as the window system
/// describes it: where the pointer is, what the source offers, and the data on demand.
@MainActor
public final class PlatformDragInfo {
    /// Pointer location in the window's content coordinates (points, bottom-left origin).
    public var location: NSPoint
    /// Operations the source allows.
    public var sourceOperations: NSDragOperation
    public var modifierFlags: NSEvent.ModifierFlags
    /// Pasteboard types (AppKit type identifiers) the drag carries, one list per item.
    public let items: [[String]]
    /// Fetches one representation; nil when the source cannot provide it.
    public let load: @MainActor (_ item: Int, _ type: String) -> Data?
    /// The drag was started by this application (`beginDrag`): the tracker's own session
    /// is the source of truth for its pasteboard and source.
    public let isFromThisApplication: Bool

    public init(location: NSPoint, sourceOperations: NSDragOperation, modifierFlags: NSEvent.ModifierFlags, items: [[String]],
                isFromThisApplication: Bool, load: @escaping @MainActor (Int, String) -> Data?) {
        self.location = location
        self.sourceOperations = sourceOperations
        self.modifierFlags = modifierFlags
        self.items = items
        self.isFromThisApplication = isFromThisApplication
        self.load = load
    }
}

/// Implemented by the tracker that started a native drag.
@MainActor
public protocol PlatformDragSource: AnyObject {
    /// The drag ended: `operation` is what the destination performed ([] when refused or cancelled).
    func platformDragEnded(at screenPoint: NSPoint, operation: NSDragOperation)
}

@MainActor
public protocol PlatformDragDrop: AnyObject {
    /// Starts a drag the window system runs. `entries` are every item's representations
    /// (item index, type, data); `operations` what the source allows. Returns false when
    /// the platform does not run drags: the tracker then keeps the pointer and uses the
    /// foreign-drag calls below.
    func beginDrag(from window: PlatformWindow, entries: [(item: Int, entry: PlatformPasteboardEntry)], operations: NSDragOperation,
                   image: PlatformDragImage?, source: any PlatformDragSource) -> Bool
    /// Tracker-driven drags: the pointer (screen coordinates) is over no window of this
    /// application. Returns the operation the window there would perform, [] for none.
    func foreignDragMoved(to screenPoint: NSPoint, operations: NSDragOperation) -> NSDragOperation
    /// Tracker-driven drags: the pointer was released over no window of this application.
    /// Returns true when a foreign window takes the drop; the outcome then arrives through
    /// `PlatformDragSource.platformDragEnded`.
    func foreignDrop(at screenPoint: NSPoint, operations: NSDragOperation) -> Bool
    /// Tracker-driven drags: the drag ended without a foreign drop (cancelled, or dropped
    /// in this application); any foreign window told about it hears it left.
    func foreignDragEnded()
}

extension PlatformBackend {
    /// The platform's drag and drop, when it has one.
    public var dragDrop: (any PlatformDragDrop)? { nil }
}

extension PlatformWindowOwner {
    public func platformDragEntered(_ drag: PlatformDragInfo) -> NSDragOperation { [] }
    public func platformDragUpdated(_ drag: PlatformDragInfo) -> NSDragOperation { [] }
    public func platformDragExited() { }
    public func platformDrop(_ drag: PlatformDragInfo) -> NSDragOperation { [] }
}
