// The seam between the platform-independent AppKit core and the operating system.
//
// The core owns policy (responder chain, view hierarchy, key/main window state, dirty
// tracking); a backend owns mechanism (native windows, the event loop, surfaces).
// Everything the core sees is in AppKit coordinates: points, origin at the bottom-left
// of the primary display, y increasing upwards. Backends convert at this boundary.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A connected display, as the core wants to see it.
public struct PlatformDisplay: Sendable {
    public var frame: NSRect
    public var visibleFrame: NSRect
    public var backingScaleFactor: CGFloat
    public var localizedName: String
    public var isMain: Bool
    public init(frame: NSRect, visibleFrame: NSRect, backingScaleFactor: CGFloat, localizedName: String, isMain: Bool) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.backingScaleFactor = backingScaleFactor
        self.localizedName = localizedName
        self.isMain = isMain
    }
}

@MainActor
public protocol PlatformBackend: AnyObject {
    var displays: [PlatformDisplay] { get }
    func makeWindow(owner: PlatformWindowOwner, contentRect: NSRect, styleMask: NSWindow.StyleMask) -> PlatformWindow
    /// Runs the native event loop until `stop()`.
    func run()
    func stop()
    /// Executes `block` on the event loop as soon as possible.
    func post(_ block: @escaping @MainActor () -> Void)
    func beep()
    /// Mouse location in AppKit screen coordinates.
    var mouseLocation: NSPoint { get }
    /// Text measurement and drawing.
    var text: any PlatformTextBackend { get }
    /// Image decoding and offscreen surfaces.
    var image: any PlatformImageBackend { get }
    /// The system clipboard.
    var systemPasteboard: any PlatformPasteboard { get }
    /// Runs a nested event loop for a modal window until `stop` reports true.
    /// Other windows of the application do not receive input meanwhile.
    func runModal(for window: PlatformWindow?, until stop: @escaping @MainActor () -> Bool)
    /// Sets the mouse cursor shown over this application's windows.
    func setCursor(_ cursor: PlatformCursor)
    func setCursorHidden(_ hidden: Bool)
    /// Installs (or with nil removes) the application menu bar on every titled window.
    func setMainMenu(_ menu: PlatformMenu?, host: PlatformMenuHost?)
    /// Frame/content conversion for a window that does not exist yet.
    func frameRect(forContentRect contentRect: NSRect, styleMask: NSWindow.StyleMask) -> NSRect
    func contentRect(forFrameRect frameRect: NSRect, styleMask: NSWindow.StyleMask) -> NSRect
}

/// A native window. Frames are in AppKit screen coordinates.
@MainActor
public protocol PlatformWindow: AnyObject {
    var title: String { get set }
    var frame: NSRect { get set }
    var styleMask: NSWindow.StyleMask { get set }
    var backingScaleFactor: CGFloat { get }
    var isVisible: Bool { get }
    var isKey: Bool { get }
    var minSize: NSSize { get set }
    var maxSize: NSSize { get set }
    func frameRect(forContentRect contentRect: NSRect) -> NSRect
    func contentRect(forFrameRect frameRect: NSRect) -> NSRect
    func show()
    func hide()
    func makeKey()
    func orderBack()
    /// Destroys the native window. The object is unusable afterwards.
    func close()
    /// Marks the content area (or `rect`, in content coordinates) for repainting.
    func setNeedsDisplay(_ rect: NSRect?)
    /// Repaints synchronously if anything is marked dirty.
    func displayIfNeeded()
    /// Repaints synchronously.
    func display()
}

/// Implemented by `NSWindow`. Callbacks arrive on the main actor.
@MainActor
public protocol PlatformWindowOwner: AnyObject {
    /// The native frame changed (size and/or origin). `frame` is in screen coordinates.
    func platformWindowDidChangeFrame(_ frame: NSRect)
    func platformWindowShouldClose() -> Bool
    func platformWindowWillClose()
    func platformWindowDidBecomeKey()
    func platformWindowDidResignKey()
    func platformWindowDidChangeBackingScaleFactor(_ scale: CGFloat)
    /// Draw the content area. `context` is in content coordinates (points, bottom-left
    /// origin, already scaled for the backing store). `dirtyRect` is in content coordinates.
    func platformWindowDraw(into context: CGContext, dirtyRect: NSRect)
    /// An input event for this window, already translated into an `NSEvent` whose
    /// `locationInWindow` is in content coordinates.
    func platformWindowDispatch(_ event: NSEvent)
}
