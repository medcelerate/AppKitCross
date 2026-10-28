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
    /// Calls `callback` once, about one display frame from now (Core Animation's frame clock).
    func scheduleFrame(_ callback: @escaping @MainActor () -> Void)
    func beep()
    /// Mouse location in AppKit screen coordinates.
    var mouseLocation: NSPoint { get }
    /// Text measurement and drawing.
    var text: any PlatformTextBackend { get }
    /// Image decoding and offscreen surfaces.
    var image: any PlatformImageBackend { get }
    /// The system clipboard.
    var systemPasteboard: any PlatformPasteboard { get }
    /// Shows the native open/save dialog modally; nil when cancelled.
    func runFileDialog(_ options: PlatformFileDialogOptions, parent: PlatformWindow?) -> [URL]?
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
    /// Chrome beyond the style mask: title bar treatment, backdrop, shadow (Milestone 3b).
    var chrome: PlatformWindowChrome { get set }
    /// Repaints synchronously if anything is marked dirty.
    func displayIfNeeded()
    /// Repaints synchronously.
    func display()
}

/// Implemented by `NSWindow`. Callbacks arrive on the main actor.
@MainActor
public protocol PlatformWindowOwner: AnyObject {
    /// Whether this window carries the application's menu bar on platforms that attach
    /// menus per window (Windows). Panels and utility windows do not.
    var platformWantsMenuBar: Bool { get }
    /// Whether a point (content coordinates) drags the window (caption) or is content.
    func platformWindowHitTest(_ point: NSPoint) -> PlatformWindowHitRegion
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

public struct PlatformFileDialogOptions: Sendable {
    public var isSave = false
    public var title: String? = nil
    public var prompt: String? = nil            // confirm button label
    public var message: String? = nil
    public var directory: URL? = nil
    public var defaultName: String? = nil
    public var allowedExtensions: [String] = []  // without dots; empty = any
    public var allowsOtherTypes = true
    public var canChooseFiles = true
    public var canChooseDirectories = false
    public var allowsMultipleSelection = false
    public var canCreateDirectories = true
    public var showsHiddenFiles = false
    public init() {}
}

/// Window chrome a backend can offer beyond the style mask (Milestone 3b: frameless and
/// translucent windows). Windows maps these onto DWM attributes and custom non-client
/// handling; the host backend records them.
public struct PlatformWindowChrome: Equatable, Sendable {
    public enum Backdrop: Sendable { case none, mica, micaAlt, acrylic }
    /// `NSWindow.StyleMask.fullSizeContentView`: the content covers the title bar area.
    public var extendsContentIntoTitleBar = false
    /// `titleVisibility == .hidden`.
    public var hidesTitle = false
    /// `titlebarAppearsTransparent`.
    public var transparentTitleBar = false
    /// System backdrop behind the content (from `NSVisualEffectView` materials).
    public var backdrop: Backdrop = .none
    /// `!isOpaque`: the content is drawn with alpha over the backdrop.
    public var isTransparent = false
    public var hasShadow = true
    /// `isMovableByWindowBackground`.
    public var movableByBackground = false
    public var roundedCorners = true
    public init() {}
}

public enum PlatformWindowHitRegion: Sendable { case client, caption }
