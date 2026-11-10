// The seam between the platform-independent AppKit core and the operating system.
//
// The core owns policy (responder chain, view hierarchy, key/main window state, dirty
// tracking); a backend owns mechanism (native windows, the event loop, surfaces).
// Everything the core sees is in AppKit coordinates: points, origin at the bottom-left
// of the primary display, y increasing upwards. Backends convert at this boundary.

import Foundation
#if canImport(QuartzCore)
import QuartzCore
#endif
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
    /// Extended dynamic range (`NSScreen.maximumExtendedDynamicRangeColorComponentValue`
    /// and friends): the largest colour component value the display shows now, the
    /// largest it could show (HDR off but supported), and the largest in a reference
    /// mode (0 when the display has none). 1 / 1 / 0 for an SDR display.
    public var maximumEDRValue: CGFloat
    public var maximumPotentialEDRValue: CGFloat
    public var maximumReferenceEDRValue: CGFloat
    public init(frame: NSRect, visibleFrame: NSRect, backingScaleFactor: CGFloat, localizedName: String, isMain: Bool,
                maximumEDRValue: CGFloat = 1, maximumPotentialEDRValue: CGFloat = 1, maximumReferenceEDRValue: CGFloat = 0) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.backingScaleFactor = backingScaleFactor
        self.localizedName = localizedName
        self.isMain = isMain
        self.maximumEDRValue = maximumEDRValue
        self.maximumPotentialEDRValue = maximumPotentialEDRValue
        self.maximumReferenceEDRValue = maximumReferenceEDRValue
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
    /// Whether the system theme is dark (the application's default effective appearance).
    var systemAppearanceIsDark: Bool { get }
    func beep()
    /// Mouse location in AppKit screen coordinates.
    var mouseLocation: NSPoint { get }
    /// Text measurement and drawing.
    var text: any PlatformTextBackend { get }
    /// Image decoding and offscreen surfaces.
    var image: any PlatformImageBackend { get }
    /// The system clipboard.
    var systemPasteboard: any PlatformPasteboard { get }
    /// The operating system's open/save dialog (FileDialog.swift, ADR-0017); nil when the
    /// panels should draw themselves.
    var fileDialog: (any PlatformFileDialog)? { get }
    /// Runs a nested event loop for a modal window until `stop` reports true.
    /// Other windows of the application do not receive input meanwhile.
    func runModal(for window: PlatformWindow?, until stop: @escaping @MainActor () -> Bool)
    /// Pumps events until `stop` returns true without disabling any window (menu tracking).
    func runNested(until stop: @escaping @MainActor () -> Bool)
    /// Sets the mouse cursor shown over this application's windows.
    func setCursor(_ cursor: PlatformCursor)
    func setCursorHidden(_ hidden: Bool)
    /// Installs (or with nil removes) the application menu bar on every titled window.
    func setMainMenu(_ menu: PlatformMenu?, host: PlatformMenuHost?)
    /// Frame/content conversion for a window that does not exist yet.
    func frameRect(forContentRect contentRect: NSRect, styleMask: NSWindow.StyleMask) -> NSRect
    func contentRect(forFrameRect frameRect: NSRect, styleMask: NSWindow.StyleMask) -> NSRect
    /// Drags to and from other applications (see DragDrop.swift); nil when the platform has none.
    var dragDrop: (any PlatformDragDrop)? { get }
    /// The status area for `NSStatusBar` items (see StatusItem.swift); nil when the platform has none.
    var statusItems: (any PlatformStatusItemHost)? { get }
}

/// A native window. Frames are in AppKit screen coordinates.
@MainActor
public protocol PlatformWindow: AnyObject {
    var title: String { get set }
    var frame: NSRect { get set }
    var styleMask: NSWindow.StyleMask { get set }
    var backingScaleFactor: CGFloat { get }
    /// The display the window system says the window is on, when it tracks that itself
    /// (Windows: the monitor an HWND belongs to). Nil when only `displays` and the frame
    /// can tell, which is how the core then decides `NSWindow.screen`.
    var currentDisplay: PlatformDisplay? { get }
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
    /// Minimises to the taskbar/dock, restores, or toggles the maximised state.
    func miniaturize()
    func deminiaturize()
    func zoom()
    var isMiniaturized: Bool { get }
    var isZoomed: Bool { get }
    /// Destroys the native window. The object is unusable afterwards.
    func close()
    /// Marks the content area (or `rect`, in content coordinates) for repainting.
    func setNeedsDisplay(_ rect: NSRect?)
    /// `NSWindow.isDocumentEdited`: platforms with native title bars mark the title (an
    /// asterisk before it, as their own editors do); the default does nothing.
    func setDocumentEdited(_ edited: Bool)
    /// Chrome beyond the style mask: title bar treatment, backdrop, shadow (Milestone 3b).
    var chrome: PlatformWindowChrome { get set }
    /// The platform draws no title bar of its own and wants the owner's (Wayland client-side
    /// decorations): the window's frame then has a band above the content that the owner
    /// paints through `platformWindowDrawTitleBar` and whose buttons it hit-tests.
    var hasClientSideTitleBar: Bool { get }
    /// Repaints synchronously if anything is marked dirty.
    func displayIfNeeded()
    /// Repaints synchronously.
    func display()
    /// Hosts the window's layer tree natively (DirectComposition visuals on Windows), or
    /// tears the hosting down when `scene` is nil. Returns false when the platform cannot;
    /// the window then composites layers in software inside `platformWindowDraw`.
    func hostLayerScene(_ scene: PlatformLayerScene?) -> Bool
    /// The accessibility tree changed (focus, a value, structure); platforms with
    /// assistive technology forward it (Accessibility.swift, ADR-0013).
    func accessibilityDidChange(_ change: PlatformAccessibilityChange)
    /// A native surface placed within the content area at `frame` (content coordinates,
    /// points) for a GPU swap chain to present into: a child X window or a Wayland
    /// subsurface (ADR-0012). The platform's counterpart of a composition visual showing a
    /// swap chain where it does not host the layer tree. Nil when it has none (the host
    /// backend); the view then reads frames back and draws them.
    func makePresentationSurface(frame: NSRect) -> (any PlatformPresentationSurface)?
    /// The content area as the window system shows it now, including presentation
    /// surfaces (X11: `XGetImage`); nil where the platform cannot read it back (Wayland).
    /// For tests and tooling.
    func captureContent() -> CGImage?
}

/// A native surface within a window's content area that a swap chain presents into
/// (`PlatformWindow.makePresentationSurface`). The surface sits above the content the
/// window draws itself and follows the window's backing scale; the view that owns it
/// moves it with `setFrame` and closes it when it leaves the window or is hidden.
@MainActor
public protocol PlatformPresentationSurface: AnyObject {
    var handle: PlatformPresentationSurfaceHandle { get }
    /// Places the surface at `frame` (content coordinates, points).
    func setFrame(_ frame: NSRect)
    /// Destroys the surface; the object is unusable afterwards.
    func close()
}

/// What a Vulkan swap chain needs from a presentation surface: the window-system
/// connection and the native window or surface.
public struct PlatformPresentationSurfaceHandle: Sendable {
    public enum Kind: Sendable {
        /// `display` is the X11 `Display*`, `window` the child `Window` id.
        case xlib
        /// `display` is the `wl_display*`, `window` the `wl_surface*` as an integer.
        case wayland
    }
    public var kind: Kind
    public var display: UnsafeMutableRawPointer
    public var window: UInt
    public init(kind: Kind, display: UnsafeMutableRawPointer, window: UInt) {
        self.kind = kind
        self.display = display
        self.window = window
    }
}

/// A layer tree flattened for the platform compositor; see `_CALayerScene` in QuartzCore.
public typealias PlatformLayerScene = _CALayerScene

extension PlatformBackend {
    public func runNested(until stop: @escaping @MainActor () -> Bool) { runModal(for: nil, until: stop) }
}

extension PlatformWindow {
    public func setDocumentEdited(_ edited: Bool) { }
    public func hostLayerScene(_ scene: PlatformLayerScene?) -> Bool { false }
    public func makePresentationSurface(frame: NSRect) -> (any PlatformPresentationSurface)? { nil }
    public func captureContent() -> CGImage? { nil }
    public var hasClientSideTitleBar: Bool { false }
    public var currentDisplay: PlatformDisplay? { nil }
    public func miniaturize() { }
    public func deminiaturize() { }
    public func zoom() { }
    public var isMiniaturized: Bool { false }
    public var isZoomed: Bool { false }
}

/// Implemented by `NSWindow`. Callbacks arrive on the main actor.
@MainActor
public protocol PlatformWindowOwner: AnyObject {
    /// Whether this window carries the application's menu bar on platforms that attach
    /// menus per window (Windows). Panels and utility windows do not.
    var platformWantsMenuBar: Bool { get }
    /// Whether a point (content coordinates) drags the window (caption) or is content.
    func platformWindowHitTest(_ point: NSPoint) -> PlatformWindowHitRegion
    /// The active text input target for input methods (IME composition), or nil.
    func platformWindowTextInput() -> PlatformTextInput?
    /// The native frame changed (size and/or origin). `frame` is in screen coordinates.
    func platformWindowDidChangeFrame(_ frame: NSRect)
    func platformWindowShouldClose() -> Bool
    func platformWindowWillClose()
    func platformWindowDidBecomeKey()
    func platformWindowDidResignKey()
    func platformWindowDidChangeBackingScaleFactor(_ scale: CGFloat)
    /// The window system minimised or restored the window on its own (taskbar, Win+D, the
    /// window manager); a backend may also report the `miniaturize()`/`deminiaturize()` it
    /// was asked for, the owner posts each change once.
    func platformWindowDidMiniaturize()
    func platformWindowDidDeminiaturize()
    /// Draw the content area. `context` is in content coordinates (points, bottom-left
    /// origin, already scaled for the backing store). `dirtyRect` is in content coordinates.
    func platformWindowDraw(into context: CGContext, dirtyRect: NSRect)
    /// Draw the title band of a window whose platform has `hasClientSideTitleBar`: the band
    /// background, title and standard buttons. `context` and `dirtyRect` are in window
    /// coordinates (the content at the origin, the band above it, y up).
    func platformWindowDrawTitleBar(into context: CGContext, dirtyRect: NSRect)
    /// A double click on the platform-drawn title band (or the draggable band of content
    /// that covers it): AppKit zooms the window.
    func platformWindowTitleBarDoubleClicked()
    /// An input event for this window, already translated into an `NSEvent` whose
    /// `locationInWindow` is in content coordinates.
    func platformWindowDispatch(_ event: NSEvent)
    /// A drag the window system runs entered the content area (see DragDrop.swift). The
    /// answers are the operation the destination under the pointer would perform.
    func platformDragEntered(_ drag: PlatformDragInfo) -> NSDragOperation
    func platformDragUpdated(_ drag: PlatformDragInfo) -> NSDragOperation
    func platformDragExited()
    /// The drag was released here; returns the operation performed ([] when refused).
    func platformDrop(_ drag: PlatformDragInfo) -> NSDragOperation
    /// The window's accessibility tree and actions (Accessibility.swift, ADR-0013).
    var platformAccessibility: any PlatformAccessibilityProvider { get }
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
    /// The window draws a band of its own (a toolbar under a system title bar) that
    /// drags the window: the backend asks the owner's hit test for client points.
    public var hasDraggableBand = false
    public var roundedCorners = true
    public init() {}
}

public enum PlatformWindowHitRegion: Sendable { case client, caption }

extension PlatformWindowOwner {
    public func platformWindowDrawTitleBar(into context: CGContext, dirtyRect: NSRect) {}
    public func platformWindowTitleBarDoubleClicked() {}
}

/// What an input method needs from the focused text view: composition (marked text)
/// updates, committed text, and where to put its candidate window.
public struct PlatformTextInput {
    public var hasMarkedText: @MainActor () -> Bool
    /// Composition string and the selected range inside it.
    public var setMarkedText: @MainActor (String, NSRange) -> Void
    public var unmarkText: @MainActor () -> Void
    public var insertText: @MainActor (String) -> Void
    /// The caret or composition rectangle in window content coordinates (points, bottom-left).
    public var markedRect: @MainActor () -> NSRect?
    public init(hasMarkedText: @escaping @MainActor () -> Bool, setMarkedText: @escaping @MainActor (String, NSRange) -> Void, unmarkText: @escaping @MainActor () -> Void, insertText: @escaping @MainActor (String) -> Void, markedRect: @escaping @MainActor () -> NSRect?) {
        self.hasMarkedText = hasMarkedText; self.setMarkedText = setMarkedText; self.unmarkText = unmarkText; self.insertText = insertText; self.markedRect = markedRect
    }
}
