// NSWindow (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif
#if canImport(CoreText)
import CoreText
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow
@MainActor open class NSWindow: NSResponder, NSAnimatablePropertyContainer, NSMenuItemValidation, NSUserInterfaceValidations, NSUserInterfaceItemIdentification, NSAppearanceCustomization, NSAccessibilityElementProtocol, NSAccessibilityProtocol {
    // MARK: Storage
    private var _platform: (any PlatformWindow)?
    private var _contentView: NSView?
    private var _styleMask: NSWindow.StyleMask
    private var _title = ""
    private var _subtitle = ""
    private weak var _delegate: (any NSWindowDelegate)?
    private var _isKey = false
    private var _isMain = false
    private var _isClosing = false
    private var _windowNumber = 0
    private var _level: NSWindow.Level = .normal
    private var _backgroundColor: NSColor = .windowBackgroundColor
    private var _isReleasedWhenClosed = true
    private weak var _firstResponder: NSResponder?
    private weak var _initialFirstResponder: NSView?
    private weak var _mouseDownView: NSView?
    private var _acceptsMouseMovedEvents = false
    private var _alphaValue: CGFloat = 1
    private var _isOpaque = true
    private var _hasShadow = true
    private var _collectionBehavior: NSWindow.CollectionBehavior = []
    private var _identifier: NSUserInterfaceItemIdentifier? = nil
    private var _isDocumentEdited = false
    private var _ignoresMouseEvents = false
    private var _isMovable = true
    private var _isMovableByWindowBackground = false
    private var _currentEvent: NSEvent? = nil
    private var _childWindows: [NSWindow] = []
    private weak var _parent: NSWindow?
    private var _toolbar: NSToolbar? = nil
    private var _titleVisibility: NSWindow.TitleVisibility = .visible
    private var _titlebarAppearsTransparent = false
    private weak var _windowController: NSWindowController?
    private var _contentViewController: NSViewController? = nil
    private var _lastFrame = NSRect.zero
    private var _animationBehavior: NSWindow.AnimationBehavior = .default
    private var _tabbingMode: NSWindow.TabbingMode = .automatic
    private var _frameAutosaveName: NSWindow.FrameAutosaveName = ""
    private var _representedURL: URL? = nil
    private var _canHide = true
    private var _hidesOnDeactivate = false
    private var _isRestorable = true
    private var _isExcludedFromWindowsMenu = false
    private var _showsToolbarButton = true
    private var _allowsToolTipsWhenApplicationIsInactive = false
    private var _preservesContentDuringLiveResize = true
    private var _displaysWhenScreenProfileChanges = false
    private var _isAutodisplay = true
    private var _autorecalculatesKeyViewLoop = true
    private var _resizeIncrements = NSSize(width: 1, height: 1)
    private var _aspectRatio = NSSize.zero
    private var _toolbarStyle: NSWindow.ToolbarStyle = .automatic
    private var _cursorRectsEnabled = true

    /// Chooses the cursor for the mouse position (content coordinates) from cursor rects.
    @MainActor private func _updateCursor(at location: NSPoint) {
        guard _cursorRectsEnabled else { return }
        var v = _contentView?.hitTest(location)
        while let view = v {
            if let c = view._cursor(at: view.convert(location, from: nil)) { c.set(); return }
            v = view.superview
        }
        NSCursor.arrow.set()
    }

    open override var description: String { MainActor.assumeIsolated { "<NSWindow \(_windowNumber) '\(_title)' \(frame)>" } }

    private func post(_ name: NSNotification.Name) {
        NotificationCenter.default.post(name: name, object: self)
    }

    private func _setContentView(_ view: NSView?) {
        if let old = _contentView {
            old._setWindow(nil)
            old.nextResponder = nil
        }
        _contentView = view
        guard let view else { return }
        let cr = contentRect(forFrameRect: frame)
        view.frame = NSRect(origin: .zero, size: cr.size)
        view.nextResponder = self
        view._setWindow(self)
        _platform?.setNeedsDisplay(nil)
    }

    internal var _platformWindow: (any PlatformWindow)? { _platform }

    /// Called by views when a region in their coordinates needs repainting.
    internal func _viewNeedsDisplay(_ view: NSView, rect: NSRect) {
        let r = view.convert(rect, to: nil)
        _platform?.setNeedsDisplay(r)
    }

    private func _dispatchMouse(_ event: NSEvent, to target: NSResponder) {
        switch event.type {
        case .leftMouseDown: target.mouseDown(with: event)
        case .leftMouseUp: target.mouseUp(with: event)
        case .leftMouseDragged: target.mouseDragged(with: event)
        case .rightMouseDown: target.rightMouseDown(with: event)
        case .rightMouseUp: target.rightMouseUp(with: event)
        case .rightMouseDragged: target.rightMouseDragged(with: event)
        case .otherMouseDown: target.otherMouseDown(with: event)
        case .otherMouseUp: target.otherMouseUp(with: event)
        case .otherMouseDragged: target.otherMouseDragged(with: event)
        case .mouseMoved: target.mouseMoved(with: event)
        case .scrollWheel: target.scrollWheel(with: event)
        case .mouseEntered: target.mouseEntered(with: event)
        case .mouseExited: target.mouseExited(with: event)
        default: break
        }
    }

    // MARK: PlatformWindowOwner

    public func platformWindowDidChangeFrame(_ frame: NSRect) {
        let old = _lastFrame
        _lastFrame = frame
        let cr = contentRect(forFrameRect: frame)
        if let cv = _contentView, cv.frame.size != cr.size {
            cv.setFrameSize(cr.size)
        }
        if old.size != frame.size {
            post(NSWindow.didResizeNotification)
            delegate?.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: self))
        }
        if old.origin != frame.origin {
            post(NSWindow.didMoveNotification)
            delegate?.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: self))
        }
    }

    public func platformWindowShouldClose() -> Bool {
        delegate?.windowShouldClose(self) ?? true
    }

    public func platformWindowWillClose() {
        if !_isClosing { close() }
    }

    public func platformWindowDidBecomeKey() { becomeKey() }
    public func platformWindowDidResignKey() { resignKey() }

    public func platformWindowDidChangeBackingScaleFactor(_ scale: CGFloat) {
        post(NSWindow.didChangeBackingPropertiesNotification)
        delegate?.windowDidChangeBackingProperties(Notification(name: NSWindow.didChangeBackingPropertiesNotification, object: self))
        func visit(_ v: NSView) { v.viewDidChangeBackingProperties(); v.subviews.forEach(visit) }
        if let cv = _contentView { visit(cv) }
    }

    public func platformWindowDraw(into context: CGContext, dirtyRect: NSRect) {
        context.saveGState()
        if _isOpaque {
            context.setFillColor(_backgroundColor.cgColor)
            context.fill(dirtyRect)
        }
        _contentView?.layoutSubtreeIfNeeded()
        _contentView?._displayHierarchy(in: context, dirtyRect: dirtyRect)
        NSGraphicsContext.current = nil
        context.restoreGState()
    }

    public func platformWindowDispatch(_ event: NSEvent) {
        NSApplication.shared.sendEvent(event)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/init(contentrect:stylemask:backing:defer:)
    @MainActor public init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        _styleMask = style
        super.init()
        let app = NSApplication.shared
        _windowNumber = app._allocateWindowNumber()
        _platform = Platform.backend.makeWindow(owner: self, contentRect: contentRect, styleMask: style)
        _lastFrame = _platform?.frame ?? contentRect
        _firstResponder = self
        let cv = NSView(frame: NSRect(origin: .zero, size: contentRect.size))
        cv.autoresizingMask = [.width, .height]
        _setContentView(cv)
        app._register(window: self)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/init(contentrect:stylemask:backing:defer:screen:)
    @MainActor public convenience init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool, screen: NSScreen?) {
        var rect = contentRect
        if let screen { rect.origin.x += screen.frame.minX; rect.origin.y += screen.frame.minY }
        self.init(contentRect: rect, styleMask: style, backing: backingStoreType, defer: flag)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/init(contentviewcontroller:)
    @available(macOS 10.10, *)
    @MainActor public convenience init(contentViewController: NSViewController) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/init(windowref:)
    @MainActor public convenience init?(windowRef: UnsafeMutableRawPointer) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/acceptsmousemovedevents
    @MainActor open var acceptsMouseMovedEvents: Bool {
        get { _acceptsMouseMovedEvents }
        set { _acceptsMouseMovedEvents = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/addchildwindow(_:ordered:)
    @MainActor open func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) {
        _childWindows.append(childWin)
        childWin._parent = self
        if place == .above { childWin.orderFront(nil) } else { childWin.orderBack(nil) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/addtabbedwindow(_:ordered:)
    @available(macOS 10.12, *)
    @MainActor open func addTabbedWindow(_ window: NSWindow, ordered: NSWindow.OrderingMode) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/addtitlebaraccessoryviewcontroller(_:)
    @available(macOS 10.10, *)
    @MainActor open func addTitlebarAccessoryViewController(_ childViewController: NSTitlebarAccessoryViewController) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/allowsautomaticwindowtabbing
    @available(macOS 10.12, *)
    @MainActor class public var allowsAutomaticWindowTabbing: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/allowsconcurrentviewdrawing
    @MainActor open var allowsConcurrentViewDrawing: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/allowstooltipswhenapplicationisinactive
    @MainActor open var allowsToolTipsWhenApplicationIsInactive: Bool {
        get { _allowsToolTipsWhenApplicationIsInactive }
        set { _allowsToolTipsWhenApplicationIsInactive = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/alphavalue
    @MainActor open var alphaValue: CGFloat {
        get { _alphaValue }
        set { _alphaValue = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/anchorattribute(for:)
    @MainActor open func anchorAttribute(for orientation: NSLayoutConstraint.Orientation) -> NSLayoutConstraint.Attribute { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/animationbehavior
    @MainActor open var animationBehavior: NSWindow.AnimationBehavior {
        get { _animationBehavior }
        set { _animationBehavior = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/animationresizetime(_:)
    @MainActor open func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/appearancesource
    @available(macOS 10.14, *)
    @MainActor open var appearanceSource: (any NSAppearanceCustomization)! {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/arecursorrectsenabled
    @MainActor open var areCursorRectsEnabled: Bool { _cursorRectsEnabled }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/aspectratio
    @MainActor open var aspectRatio: NSSize {
        get { _aspectRatio }
        set { _aspectRatio = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/attachedsheet
    @MainActor open var attachedSheet: NSWindow? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/autorecalculatescontentborderthickness(for:)
    @MainActor open func autorecalculatesContentBorderThickness(for edge: NSRectEdge) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/autorecalculateskeyviewloop
    @MainActor open var autorecalculatesKeyViewLoop: Bool {
        get { _autorecalculatesKeyViewLoop }
        set { _autorecalculatesKeyViewLoop = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/backgroundcolor
    @MainActor open var backgroundColor: NSColor! {
        get { _backgroundColor }
        set { _backgroundColor = newValue ?? .windowBackgroundColor; _platform?.setNeedsDisplay(nil) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/backingalignedrect(_:options:)
    @MainActor open func backingAlignedRect(_ rect: NSRect, options: AlignmentOptions = []) -> NSRect { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/backinglocation
    @MainActor open var backingLocation: NSWindow.BackingLocation { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/backingscalefactor
    @MainActor open var backingScaleFactor: CGFloat { _platform?.backingScaleFactor ?? 1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/backingtype
    @MainActor open var backingType: NSWindow.BackingStoreType {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/becomekey()
    @MainActor open func becomeKey() {
        guard !_isKey else { return }
        let app = NSApplication.shared
        if let previous = app.keyWindow, previous !== self { previous.resignKey() }
        _isKey = true
        app._keyWindow = self
        post(NSWindow.didBecomeKeyNotification)
        delegate?.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: self))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/becomemain()
    @MainActor open func becomeMain() {
        guard !_isMain else { return }
        _isMain = true
        NSApplication.shared._mainWindow = self
        post(NSWindow.didBecomeMainNotification)
        delegate?.windowDidBecomeMain(Notification(name: NSWindow.didBecomeMainNotification, object: self))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/begincriticalsheet(_:)
    @MainActor open func beginCriticalSheet(_ sheetWindow: NSWindow) async -> NSApplication.ModalResponse { unimplemented() }
    // DUPLICATE: @MainActor open func beginCriticalSheet(_ sheetWindow: NSWindow) async -> NSApplication.ModalResponse
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/begindraggingsession(items:event:source:)
    @available(macOS 15.0, *)
    @MainActor open func beginDraggingSession(items: [NSDraggingItem], event: NSEvent, source: any NSDraggingSource) -> NSDraggingSession { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/beginsheet(_:)
    @MainActor open func beginSheet(_ sheetWindow: NSWindow) async -> NSApplication.ModalResponse { unimplemented() }
    // DUPLICATE: @MainActor open func beginSheet(_ sheetWindow: NSWindow) async -> NSApplication.ModalResponse
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/cacheimage(in:)
    @MainActor open func cacheImage(in rect: NSRect) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/canbecomekey
    @MainActor open var canBecomeKey: Bool { _styleMask.contains(.titled) || _styleMask.contains(.resizable) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/canbecomemain
    @MainActor open var canBecomeMain: Bool { canBecomeKey && !_styleMask.contains(.utilityWindow) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/canbecomevisiblewithoutlogin
    @MainActor open var canBecomeVisibleWithoutLogin: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/canhide
    @MainActor open var canHide: Bool {
        get { _canHide }
        set { _canHide = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/canrepresent(_:)
    @available(macOS 10.12, *)
    @MainActor open func canRepresent(_ displayGamut: NSDisplayGamut) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/canstorecolor()
    @MainActor open func canStoreColor() -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/cascadetopleft(from:)
    @MainActor open func cascadeTopLeft(from topLeftPoint: NSPoint) -> NSPoint { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/cascadingreferenceframe
    @available(macOS 15.0, *)
    @MainActor open var cascadingReferenceFrame: NSRect { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/center()
    @MainActor open func center() {
        guard let s = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let f = frame
        // AppKit places the window slightly above the vertical middle.
        setFrameOrigin(NSPoint(x: s.midX - f.width / 2, y: s.minY + (s.height - f.height) * 2 / 3))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/childwindows
    @MainActor open var childWindows: [NSWindow]? { _childWindows.isEmpty ? nil : _childWindows }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/close()
    @MainActor open func close() {
        guard !_isClosing else { return }
        _isClosing = true
        post(NSWindow.willCloseNotification)
        delegate?.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: self))
        if _isKey { resignKey() }
        if _isMain { resignMain() }
        for child in _childWindows { child.close() }
        _parent?.removeChildWindow(self)
        _platform?.close()
        _platform = nil
        NSApplication.shared._unregister(window: self)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior
    @MainActor open var collectionBehavior: NSWindow.CollectionBehavior {
        get { _collectionBehavior }
        set { _collectionBehavior = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/colorspace
    @MainActor open var colorSpace: NSColorSpace? {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/constrainframerect(_:to:)
    @MainActor open func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let s = screen?.visibleFrame else { return frameRect }
        var r = frameRect
        r.size.width = min(r.width, s.width)
        r.size.height = min(r.height, s.height)
        if r.maxY > s.maxY { r.origin.y = s.maxY - r.height }
        if r.minY < s.minY { r.origin.y = s.minY }
        if r.maxX > s.maxX { r.origin.x = s.maxX - r.width }
        if r.minX < s.minX { r.origin.x = s.minX }
        return r
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/contentaspectratio
    @MainActor open var contentAspectRatio: NSSize {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/contentborderthickness(for:)
    @MainActor open func contentBorderThickness(for edge: NSRectEdge) -> CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/contentlayoutguide
    @available(macOS 10.10, *)
    @MainActor open var contentLayoutGuide: Any? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/contentlayoutrect
    @available(macOS 10.10, *)
    @MainActor open var contentLayoutRect: NSRect { _contentView?.bounds ?? .zero }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/contentmaxsize
    @MainActor open var contentMaxSize: NSSize {
        get { contentRect(forFrameRect: NSRect(origin: .zero, size: maxSize)).size }
        set { maxSize = frameRect(forContentRect: NSRect(origin: .zero, size: newValue)).size }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/contentminsize
    @MainActor open var contentMinSize: NSSize {
        get { contentRect(forFrameRect: NSRect(origin: .zero, size: minSize)).size }
        set { minSize = frameRect(forContentRect: NSRect(origin: .zero, size: newValue)).size }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/contentrect(forframerect:)
    @MainActor open func contentRect(forFrameRect frameRect: NSRect) -> NSRect { _platform?.contentRect(forFrameRect: frameRect) ?? frameRect }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/contentrect(forframerect:stylemask:)
    @MainActor public class func contentRect(forFrameRect fRect: NSRect, styleMask style: NSWindow.StyleMask) -> NSRect { Platform.backend.contentRect(forFrameRect: fRect, styleMask: style) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/contentresizeincrements
    @MainActor open var contentResizeIncrements: NSSize {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/contentview
    @MainActor open var contentView: NSView? {
        get { _contentView }
        set { _setContentView(newValue) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/contentviewcontroller
    @available(macOS 10.10, *)
    @MainActor open var contentViewController: NSViewController? {
        get { _contentViewController }
        set { _contentViewController = newValue; if let vc = newValue { contentView = vc.view } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/convertfrombacking(_:)
    @MainActor open func convertFromBacking(_ rect: NSRect) -> NSRect { let s = backingScaleFactor; return NSRect(x: rect.minX / s, y: rect.minY / s, width: rect.width / s, height: rect.height / s) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/convertfromscreen(_:)
    @MainActor open func convertFromScreen(_ rect: NSRect) -> NSRect { let c = contentRect(forFrameRect: frame); return rect.offsetBy(dx: -c.minX, dy: -c.minY) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/convertpoint(fromscreen:)
    @available(macOS 10.12, *)
    @MainActor open func convertPoint(fromScreen point: NSPoint) -> NSPoint { let c = contentRect(forFrameRect: frame); return NSPoint(x: point.x - c.minX, y: point.y - c.minY) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/convertpoint(toscreen:)
    @available(macOS 10.12, *)
    @MainActor open func convertPoint(toScreen point: NSPoint) -> NSPoint { let c = contentRect(forFrameRect: frame); return NSPoint(x: point.x + c.minX, y: point.y + c.minY) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/convertpointfrombacking(_:)
    @available(macOS 10.14, *)
    @MainActor open func convertPointFromBacking(_ point: NSPoint) -> NSPoint { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/convertpointtobacking(_:)
    @available(macOS 10.14, *)
    @MainActor open func convertPointToBacking(_ point: NSPoint) -> NSPoint { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/converttobacking(_:)
    @MainActor open func convertToBacking(_ rect: NSRect) -> NSRect { let s = backingScaleFactor; return NSRect(x: rect.minX * s, y: rect.minY * s, width: rect.width * s, height: rect.height * s) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/converttoscreen(_:)
    @MainActor open func convertToScreen(_ rect: NSRect) -> NSRect { let c = contentRect(forFrameRect: frame); return rect.offsetBy(dx: c.minX, dy: c.minY) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/currentevent
    @MainActor open var currentEvent: NSEvent? { _currentEvent ?? NSApplication.shared.currentEvent }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/datawitheps(inside:)
    @MainActor open func dataWithEPS(inside rect: NSRect) -> Data { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/datawithpdf(inside:)
    @MainActor open func dataWithPDF(inside rect: NSRect) -> Data { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/deepestscreen
    @MainActor open var deepestScreen: NSScreen? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/defaultbuttoncell
    @MainActor open var defaultButtonCell: NSButtonCell? {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/defaultdepthlimit
    @MainActor class public var defaultDepthLimit: NSWindow.Depth { NSWindow.Depth(rawValue: 520)! }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/delegate
    @MainActor open var delegate: (any NSWindowDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/deminiaturize(_:)
    @MainActor open func deminiaturize(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/depthlimit
    @MainActor open var depthLimit: NSWindow.Depth {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/devicedescription
    @MainActor open var deviceDescription: [NSDeviceDescriptionKey : Any] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/didbecomekeynotification
    static public var didBecomeKeyNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidBecomeKeyNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/didbecomemainnotification
    static public var didBecomeMainNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidBecomeMainNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/didchangebackingpropertiesnotification
    static public var didChangeBackingPropertiesNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidChangeBackingPropertiesNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/didchangeocclusionstatenotification
    static public var didChangeOcclusionStateNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidChangeOcclusionStateNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/didchangescreennotification
    static public var didChangeScreenNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidChangeScreenNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/didchangescreenprofilenotification
    static public var didChangeScreenProfileNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidChangeScreenProfileNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/diddeminiaturizenotification
    static public var didDeminiaturizeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidDeminiaturizeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/didendliveresizenotification
    static public var didEndLiveResizeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidEndLiveResizeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/didendsheetnotification
    static public var didEndSheetNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidEndSheetNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/didenterfullscreennotification
    static public var didEnterFullScreenNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidEnterFullScreenNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/didenterversionbrowsernotification
    static public var didEnterVersionBrowserNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidEnterVersionBrowserNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/didexitfullscreennotification
    static public var didExitFullScreenNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidExitFullScreenNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/didexitversionbrowsernotification
    static public var didExitVersionBrowserNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidExitVersionBrowserNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/didexposenotification
    static public var didExposeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidExposeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/didminiaturizenotification
    static public var didMiniaturizeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidMiniaturizeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/didmovenotification
    static public var didMoveNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidMoveNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/didresignkeynotification
    static public var didResignKeyNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidResignKeyNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/didresignmainnotification
    static public var didResignMainNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidResignMainNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/didresizenotification
    static public var didResizeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidResizeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/didupdatenotification
    static public var didUpdateNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowDidUpdateNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/disablecursorrects()
    @MainActor open func disableCursorRects() { _cursorRectsEnabled = false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/disableflushing()
    @MainActor open func disableFlushing() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/disablekeyequivalentfordefaultbuttoncell()
    @MainActor open func disableKeyEquivalentForDefaultButtonCell() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/disablescreenupdatesuntilflush()
    @MainActor open func disableScreenUpdatesUntilFlush() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/disablesnapshotrestoration()
    @MainActor open func disableSnapshotRestoration() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/discardcachedimage()
    @MainActor open func discardCachedImage() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/discardcursorrects()
    @MainActor open func discardCursorRects() {
        func visit(_ v: NSView) { v.discardCursorRects(); v.subviews.forEach(visit) }
        if let cv = _contentView { visit(cv) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/discardevents(matching:before:)
    @MainActor open func discardEvents(matching mask: NSEvent.EventTypeMask, before lastEvent: NSEvent?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/display()
    @MainActor open func display() { _platform?.display() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/displayifneeded()
    @MainActor open func displayIfNeeded() { _platform?.displayIfNeeded() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/displaylink(target:selector:)
    @available(macOS 14.0, *)
    @MainActor open func displayLink(target: Any, selector: Selector) -> CADisplayLink { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/displayswhenscreenprofilechanges
    @MainActor open var displaysWhenScreenProfileChanges: Bool {
        get { _displaysWhenScreenProfileChanges }
        set { _displaysWhenScreenProfileChanges = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/docktile
    @MainActor open var dockTile: NSDockTile { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/drag(_:at:offset:event:pasteboard:source:slideback:)
    @MainActor open func drag(_ image: NSImage, at baseLocation: NSPoint, offset initialOffset: NSSize, event: NSEvent, pasteboard pboard: NSPasteboard, source sourceObj: Any, slideBack slideFlag: Bool) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/drawers
    @MainActor open var drawers: [NSDrawer]? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/enablecursorrects()
    @MainActor open func enableCursorRects() { _cursorRectsEnabled = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/enableflushing()
    @MainActor open func enableFlushing() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/enablekeyequivalentfordefaultbuttoncell()
    @MainActor open func enableKeyEquivalentForDefaultButtonCell() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/enablesnapshotrestoration()
    @MainActor open func enableSnapshotRestoration() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/endediting(for:)
    @MainActor open func endEditing(for object: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/endsheet(_:)
    @MainActor open func endSheet(_ sheetWindow: NSWindow) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/endsheet(_:returncode:)
    @MainActor open func endSheet(_ sheetWindow: NSWindow, returnCode: NSApplication.ModalResponse) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/fieldeditor(_:for:)
    @MainActor open func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/firstresponder
    @MainActor open var firstResponder: NSResponder? { _firstResponder ?? self }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/flush()
    @MainActor open func flush() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/flushifneeded()
    @MainActor open func flushIfNeeded() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/frame
    @MainActor open var frame: NSRect { _platform?.frame ?? _lastFrame }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/frameautosavename
    @MainActor open var frameAutosaveName: NSWindow.FrameAutosaveName { _frameAutosaveName }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/framedescriptor
    @MainActor open var frameDescriptor: NSWindow.PersistableFrameDescriptor { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/framerect(forcontentrect:)
    @MainActor open func frameRect(forContentRect contentRect: NSRect) -> NSRect { _platform?.frameRect(forContentRect: contentRect) ?? contentRect }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/framerect(forcontentrect:stylemask:)
    @MainActor public class func frameRect(forContentRect cRect: NSRect, styleMask style: NSWindow.StyleMask) -> NSRect { Platform.backend.frameRect(forContentRect: cRect, styleMask: style) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/gstate()
    @MainActor open func gState() -> Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/graphicscontext
    @MainActor open var graphicsContext: NSGraphicsContext? { unimplemented() }
    // SKIPPED (Foundation.NSCloseCommand not in corelibs): @MainActor func handleClose(_ command: NSCloseCommand) -> Any?
    // SKIPPED (Foundation.NSScriptCommand not in corelibs): @MainActor func handlePrint(_ command: NSScriptCommand) -> Any?
    // SKIPPED (Foundation.NSScriptCommand not in corelibs): @MainActor func handleSave(_ command: NSScriptCommand) -> Any?
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/hasactivewindowsharingsession
    @available(macOS 13.3, *)
    @MainActor open var hasActiveWindowSharingSession: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/hasclosebox
    @MainActor open var hasCloseBox: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/hasdynamicdepthlimit
    @MainActor open var hasDynamicDepthLimit: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/hasshadow
    @MainActor open var hasShadow: Bool {
        get { _hasShadow }
        set { _hasShadow = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/hastitlebar
    @MainActor open var hasTitleBar: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/hidesondeactivate
    @MainActor open var hidesOnDeactivate: Bool {
        get { _hidesOnDeactivate }
        set { _hidesOnDeactivate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents
    @MainActor open var ignoresMouseEvents: Bool {
        get { _ignoresMouseEvents }
        set { _ignoresMouseEvents = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/inliveresize
    @MainActor open var inLiveResize: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/initialfirstresponder
    @MainActor open var initialFirstResponder: NSView? {
        get { _initialFirstResponder }
        set { _initialFirstResponder = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/inserttitlebaraccessoryviewcontroller(_:at:)
    @available(macOS 10.10, *)
    @MainActor open func insertTitlebarAccessoryViewController(_ childViewController: NSTitlebarAccessoryViewController, at index: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/invalidatecursorrects(for:)
    @MainActor open func invalidateCursorRects(for view: NSView) { view._cursorRectsValid = false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/invalidateshadow()
    @MainActor open func invalidateShadow() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/isautodisplay
    @MainActor open var isAutodisplay: Bool {
        get { _isAutodisplay }
        set { _isAutodisplay = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/isdocumentedited
    @MainActor open var isDocumentEdited: Bool {
        get { _isDocumentEdited }
        set { _isDocumentEdited = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/isexcludedfromwindowsmenu
    @MainActor open var isExcludedFromWindowsMenu: Bool {
        get { _isExcludedFromWindowsMenu }
        set { _isExcludedFromWindowsMenu = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/isfloatingpanel
    @MainActor open var isFloatingPanel: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/isflushwindowdisabled
    @MainActor open var isFlushWindowDisabled: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/iskeywindow
    @MainActor open var isKeyWindow: Bool { _isKey }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/ismainwindow
    @MainActor open var isMainWindow: Bool { _isMain }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/isminiaturizable
    @MainActor open var isMiniaturizable: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/isminiaturized
    @MainActor open var isMiniaturized: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/ismodalpanel
    @MainActor open var isModalPanel: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/ismovable
    @MainActor open var isMovable: Bool {
        get { _isMovable }
        set { _isMovable = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/ismovablebywindowbackground
    @MainActor open var isMovableByWindowBackground: Bool {
        get { _isMovableByWindowBackground }
        set { _isMovableByWindowBackground = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/isonactivespace
    @MainActor open var isOnActiveSpace: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/isoneshot
    @MainActor open var isOneShot: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/isopaque
    @MainActor open var isOpaque: Bool {
        get { _isOpaque }
        set { _isOpaque = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/isreleasedwhenclosed
    @MainActor open var isReleasedWhenClosed: Bool {
        get { _isReleasedWhenClosed }
        set { _isReleasedWhenClosed = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/isresizable
    @MainActor open var isResizable: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/isrestorable
    @MainActor open var isRestorable: Bool {
        get { _isRestorable }
        set { _isRestorable = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/issheet
    @MainActor open var isSheet: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/isvisible
    @MainActor open var isVisible: Bool { _platform?.isVisible ?? false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/iszoomable
    @MainActor open var isZoomable: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/iszoomed
    @MainActor open var isZoomed: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/keyviewselectiondirection
    @MainActor open var keyViewSelectionDirection: NSWindow.SelectionDirection { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/layoutifneeded()
    @MainActor open func layoutIfNeeded() { _contentView?.layoutSubtreeIfNeeded() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/level
    @MainActor open var level: NSWindow.Level {
        get { _level }
        set { _level = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/makefirstresponder(_:)
    @MainActor open func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let target = responder ?? self
        if _firstResponder === target { return true }
        if target !== self && !target.acceptsFirstResponder { return false }
        if let current = _firstResponder, current !== self, !current.resignFirstResponder() { return false }
        _firstResponder = target
        if target !== self && !target.becomeFirstResponder() {
            _firstResponder = self
            return false
        }
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/makekey()
    @MainActor open func makeKey() {
        guard canBecomeKey else { return }
        _platform?.makeKey()
        if !_isKey { becomeKey() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/makekeyandorderfront(_:)
    @MainActor open func makeKeyAndOrderFront(_ sender: Any?) {
        orderFront(sender)
        makeKey()
        if canBecomeMain { makeMain() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/makemain()
    @MainActor open func makeMain() {
        guard canBecomeMain, !_isMain else { return }
        NSApplication.shared.mainWindow?.resignMain()
        becomeMain()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/maxfullscreencontentsize
    @available(macOS 10.11, *)
    @MainActor open var maxFullScreenContentSize: NSSize {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/maxsize
    @MainActor open var maxSize: NSSize {
        get { _platform?.maxSize ?? NSSize(width: 100_000, height: 100_000) }
        set { _platform?.maxSize = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/menuchanged(_:)
    @MainActor public class func menuChanged(_ menu: NSMenu) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/mergeallwindows(_:)
    @available(macOS 10.12, *)
    @MainActor open func mergeAllWindows(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/minframewidth(withtitle:stylemask:)
    @MainActor public class func minFrameWidth(withTitle title: String, styleMask style: NSWindow.StyleMask) -> CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/minfullscreencontentsize
    @available(macOS 10.11, *)
    @MainActor open var minFullScreenContentSize: NSSize {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/minsize
    @MainActor open var minSize: NSSize {
        get { _platform?.minSize ?? .zero }
        set { _platform?.minSize = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/miniaturize(_:)
    @MainActor open func miniaturize(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/miniwindowimage
    @MainActor open var miniwindowImage: NSImage? {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/miniwindowtitle
    @MainActor open var miniwindowTitle: String! {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/mouselocationoutsideofeventstream
    @MainActor open var mouseLocationOutsideOfEventStream: NSPoint { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/movetabtonewwindow(_:)
    @available(macOS 10.12, *)
    @MainActor open func moveTabToNewWindow(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/nextevent(matching:)
    @MainActor open func nextEvent(matching mask: NSEvent.EventTypeMask) -> NSEvent? { NSApplication.shared.nextEvent(matching: mask, until: nil, inMode: .default, dequeue: true) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/nextevent(matching:until:inmode:dequeue:)
    @MainActor open func nextEvent(matching mask: NSEvent.EventTypeMask, until expiration: Date?, inMode mode: RunLoop.Mode, dequeue deqFlag: Bool) -> NSEvent? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/occlusionstate
    @MainActor open var occlusionState: NSWindow.OcclusionState { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/oldcolorspaceuserinfokey
    static public var oldColorSpaceUserInfoKey: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/oldscalefactoruserinfokey
    static public var oldScaleFactorUserInfoKey: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/order(_:relativeto:)
    @MainActor open func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        switch place {
        case .out: orderOut(nil)
        case .below: orderBack(nil)
        default: orderFront(nil)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/orderback(_:)
    @MainActor open func orderBack(_ sender: Any?) {
        _platform?.show()
        _platform?.orderBack()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/orderfront(_:)
    @MainActor open func orderFront(_ sender: Any?) {
        _platform?.show()
        _platform?.displayIfNeeded()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/orderfrontregardless()
    @MainActor open func orderFrontRegardless() { orderFront(nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/orderout(_:)
    @MainActor open func orderOut(_ sender: Any?) {
        if _isKey { resignKey() }
        if _isMain { resignMain() }
        _platform?.hide()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/orderedindex
    @MainActor open var orderedIndex: Int {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/parent
    @MainActor open var parent: NSWindow? {
        get { _parent }
        set { _parent = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/performclose(_:)
    @MainActor open func performClose(_ sender: Any?) {
        guard _styleMask.contains(.closable) else { Platform.backend.beep(); return }
        if delegate?.windowShouldClose(self) ?? true { close() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/performdrag(with:)
    @available(macOS 10.11, *)
    @MainActor open func performDrag(with event: NSEvent) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/performminiaturize(_:)
    @MainActor open func performMiniaturize(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/performzoom(_:)
    @MainActor open func performZoom(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/postevent(_:atstart:)
    @MainActor open func postEvent(_ event: NSEvent, atStart flag: Bool) { NSApplication.shared.postEvent(event, atStart: flag) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/preferredbackinglocation
    @MainActor open var preferredBackingLocation: NSWindow.BackingLocation {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/preservescontentduringliveresize
    @MainActor open var preservesContentDuringLiveResize: Bool {
        get { _preservesContentDuringLiveResize }
        set { _preservesContentDuringLiveResize = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/preventsapplicationterminationwhenmodal
    @MainActor open var preventsApplicationTerminationWhenModal: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/printwindow(_:)
    @MainActor open func printWindow(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/recalculatekeyviewloop()
    @MainActor open func recalculateKeyViewLoop() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/registerfordraggedtypes(_:)
    @MainActor open func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/removechildwindow(_:)
    @MainActor open func removeChildWindow(_ childWin: NSWindow) {
        _childWindows.removeAll { $0 === childWin }
        childWin._parent = nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/removeframe(usingname:)
    @MainActor public class func removeFrame(usingName name: NSWindow.FrameAutosaveName) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/removetitlebaraccessoryviewcontroller(at:)
    @available(macOS 10.10, *)
    @MainActor open func removeTitlebarAccessoryViewController(at index: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/representedfilename
    @MainActor open var representedFilename: String {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/representedurl
    @MainActor open var representedURL: URL? {
        get { _representedURL }
        set { _representedURL = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/requestsharingofwindow(_:)
    @available(macOS 15.0, *)
    @MainActor open func requestSharingOfWindow(_ window: NSWindow) async throws { unimplemented() }
    // DUPLICATE: @MainActor open func requestSharingOfWindow(_ window: NSWindow) async throws
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/requestsharingofwindow(usingpreview:title:)
    @available(macOS 15.0, *)
    @MainActor open func requestSharingOfWindow(usingPreview image: NSImage, title: String) async throws { unimplemented() }
    // DUPLICATE: @MainActor open func requestSharingOfWindow(usingPreview image: NSImage, title: String) async throws
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/resetcursorrects()
    @MainActor open func resetCursorRects() { discardCursorRects() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/resignkey()
    @MainActor open func resignKey() {
        guard _isKey else { return }
        _isKey = false
        let app = NSApplication.shared
        if app.keyWindow === self { app._keyWindow = nil }
        post(NSWindow.didResignKeyNotification)
        delegate?.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: self))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/resignmain()
    @MainActor open func resignMain() {
        guard _isMain else { return }
        _isMain = false
        let app = NSApplication.shared
        if app.mainWindow === self { app._mainWindow = nil }
        post(NSWindow.didResignMainNotification)
        delegate?.windowDidResignMain(Notification(name: NSWindow.didResignMainNotification, object: self))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/resizeflags
    @MainActor open var resizeFlags: NSEvent.ModifierFlags { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/resizeincrements
    @MainActor open var resizeIncrements: NSSize {
        get { _resizeIncrements }
        set { _resizeIncrements = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/restorationclass
    @MainActor open var restorationClass: (any NSWindowRestoration.Type)? {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/restorecachedimage()
    @MainActor open func restoreCachedImage() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/runtoolbarcustomizationpalette(_:)
    @MainActor open func runToolbarCustomizationPalette(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/saveframe(usingname:)
    @MainActor open func saveFrame(usingName name: NSWindow.FrameAutosaveName) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/screen
    @MainActor open var screen: NSScreen? {
        let f = frame
        let all = NSScreen.screens
        return all.max { $0.frame.intersection(f).area < $1.frame.intersection(f).area } ?? all.first
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/selectkeyview(following:)
    @MainActor open func selectKeyView(following view: NSView) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/selectkeyview(preceding:)
    @MainActor open func selectKeyView(preceding view: NSView) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/selectnextkeyview(_:)
    @MainActor open func selectNextKeyView(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/selectnexttab(_:)
    @available(macOS 10.12, *)
    @MainActor open func selectNextTab(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/selectpreviouskeyview(_:)
    @MainActor open func selectPreviousKeyView(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/selectprevioustab(_:)
    @available(macOS 10.12, *)
    @MainActor open func selectPreviousTab(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/sendevent(_:)
    @MainActor open func sendEvent(_ event: NSEvent) {
        _currentEvent = event
        defer { _currentEvent = nil }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard !_ignoresMouseEvents else { return }
            let hit = _contentView?.hitTest(event.locationInWindow)
            _mouseDownView = hit
            if let v = hit, v.acceptsFirstResponder, firstResponder !== v { _ = makeFirstResponder(v) }
            _dispatchMouse(event, to: hit ?? self)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            _dispatchMouse(event, to: _mouseDownView ?? _contentView?.hitTest(event.locationInWindow) ?? self)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let target: NSResponder = _mouseDownView ?? _contentView?.hitTest(event.locationInWindow) ?? self
            _mouseDownView = nil
            _dispatchMouse(event, to: target)
        case .mouseMoved:
            _updateCursor(at: event.locationInWindow)
            guard _acceptsMouseMovedEvents else { return }
            _dispatchMouse(event, to: _contentView?.hitTest(event.locationInWindow) ?? self)
        case .scrollWheel, .mouseEntered, .mouseExited:
            _dispatchMouse(event, to: _contentView?.hitTest(event.locationInWindow) ?? self)
        case .keyDown:
            // An editing text field commits on Return before the default button sees it.
            if let field = firstResponder as? NSTextField, field._consumesReturnKey, event.charactersIgnoringModifiers == "\r",
               event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                field.keyDown(with: event)
                _ = _contentView?.performKeyEquivalent(with: event)
                return
            }
            if !(_contentView?.performKeyEquivalent(with: event) ?? false) {
                firstResponder?.keyDown(with: event)
            }
        case .keyUp:
            firstResponder?.keyUp(with: event)
        case .flagsChanged:
            firstResponder?.flagsChanged(with: event)
        default:
            break
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/setanchorattribute(_:for:)
    @MainActor open func setAnchorAttribute(_ attr: NSLayoutConstraint.Attribute, for orientation: NSLayoutConstraint.Orientation) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/setautorecalculatescontentborderthickness(_:for:)
    @MainActor open func setAutorecalculatesContentBorderThickness(_ flag: Bool, for edge: NSRectEdge) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/setcontentborderthickness(_:for:)
    @MainActor open func setContentBorderThickness(_ thickness: CGFloat, for edge: NSRectEdge) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/setcontentsize(_:)
    @MainActor open func setContentSize(_ size: NSSize) {
        let cr = contentRect(forFrameRect: frame)
        setFrame(frameRect(forContentRect: NSRect(origin: cr.origin, size: size)), display: true)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/setdynamicdepthlimit(_:)
    @MainActor open func setDynamicDepthLimit(_ flag: Bool) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/setframe(_:display:)
    @MainActor open func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect
        if let d = delegate, rect.size != frame.size {
            rect.size = d.windowWillResize(self, to: rect.size)
        }
        _platform?.frame = rect
        if flag { display() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/setframe(_:display:animate:)
    @MainActor open func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) { setFrame(frameRect, display: displayFlag) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/setframe(from:)
    @MainActor open func setFrame(from string: NSWindow.PersistableFrameDescriptor) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/setframeautosavename(_:)
    @MainActor open func setFrameAutosaveName(_ name: NSWindow.FrameAutosaveName) -> Bool { _frameAutosaveName = name; return true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/setframeorigin(_:)
    @MainActor open func setFrameOrigin(_ point: NSPoint) { setFrame(NSRect(origin: point, size: frame.size), display: false) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/setframetopleftpoint(_:)
    @MainActor open func setFrameTopLeftPoint(_ point: NSPoint) { setFrameOrigin(NSPoint(x: point.x, y: point.y - frame.height)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/setframeusingname(_:)
    @MainActor open func setFrameUsingName(_ name: NSWindow.FrameAutosaveName) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/setframeusingname(_:force:)
    @MainActor open func setFrameUsingName(_ name: NSWindow.FrameAutosaveName, force: Bool) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/setisminiaturized(_:)
    @MainActor open func setIsMiniaturized(_ flag: Bool) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/setisvisible(_:)
    @MainActor open func setIsVisible(_ flag: Bool) { if flag { orderFront(nil) } else { orderOut(nil) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/setiszoomed(_:)
    @MainActor open func setIsZoomed(_ flag: Bool) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/settitlewithrepresentedfilename(_:)
    @MainActor open func setTitleWithRepresentedFilename(_ filename: String) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/sharingtype
    @MainActor open var sharingType: NSWindow.SharingType {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/sheetparent
    @MainActor open var sheetParent: NSWindow? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/sheets
    @MainActor open var sheets: [NSWindow] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/showsresizeindicator
    @MainActor open var showsResizeIndicator: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/showstoolbarbutton
    @MainActor open var showsToolbarButton: Bool {
        get { _showsToolbarButton }
        set { _showsToolbarButton = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/standardwindowbutton(_:)
    @MainActor open func standardWindowButton(_ b: NSWindow.ButtonType) -> NSButton? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/standardwindowbutton(_:for:)
    @MainActor public class func standardWindowButton(_ b: NSWindow.ButtonType, for styleMask: NSWindow.StyleMask) -> NSButton? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/stylemask
    @MainActor open var styleMask: NSWindow.StyleMask {
        get { _styleMask }
        set { _styleMask = newValue; _platform?.styleMask = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/subtitle
    @available(macOS 11.0, *)
    @MainActor open var subtitle: String {
        get { _subtitle }
        set { _subtitle = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/tab
    @available(macOS 10.13, *)
    @MainActor open var tab: NSWindowTab { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/tabgroup
    @available(macOS 10.13, *)
    @MainActor open var tabGroup: NSWindowTabGroup? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/tabbedwindows
    @available(macOS 10.12, *)
    @MainActor open var tabbedWindows: [NSWindow]? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/tabbingidentifier
    @available(macOS 10.12, *)
    @MainActor open var tabbingIdentifier: NSWindow.TabbingIdentifier {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/tabbingmode
    @available(macOS 10.12, *)
    @MainActor open var tabbingMode: NSWindow.TabbingMode {
        get { _tabbingMode }
        set { _tabbingMode = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/title
    @MainActor open var title: String {
        get { _title }
        set { _title = newValue; _platform?.title = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/titlevisibility
    @available(macOS 10.10, *)
    @MainActor open var titleVisibility: NSWindow.TitleVisibility {
        get { _titleVisibility }
        set { _titleVisibility = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/titlebaraccessoryviewcontrollers
    @available(macOS 10.10, *)
    @MainActor open var titlebarAccessoryViewControllers: [NSTitlebarAccessoryViewController] {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/titlebarappearstransparent
    @available(macOS 10.10, *)
    @MainActor open var titlebarAppearsTransparent: Bool {
        get { _titlebarAppearsTransparent }
        set { _titlebarAppearsTransparent = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/titlebarseparatorstyle
    @available(macOS 11.0, *)
    @MainActor open var titlebarSeparatorStyle: NSTitlebarSeparatorStyle {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/togglefullscreen(_:)
    @MainActor open func toggleFullScreen(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/toggletabbar(_:)
    @available(macOS 10.12, *)
    @MainActor open func toggleTabBar(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/toggletaboverview(_:)
    @available(macOS 10.13, *)
    @MainActor open func toggleTabOverview(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/toggletoolbarshown(_:)
    @MainActor open func toggleToolbarShown(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/toolbar
    @MainActor open var toolbar: NSToolbar? {
        get { _toolbar }
        set { _toolbar = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/toolbarstyle
    @available(macOS 11.0, *)
    @MainActor open var toolbarStyle: NSWindow.ToolbarStyle {
        get { _toolbarStyle }
        set { _toolbarStyle = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/trackevents(matching:timeout:mode:handler:)
    @available(macOS 10.10, *)
    @MainActor open func trackEvents(matching mask: NSEvent.EventTypeMask, timeout: TimeInterval, mode: RunLoop.Mode, handler trackingHandler: (NSEvent?, UnsafeMutablePointer<ObjCBool>) -> Void) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/transferwindowsharing(to:)
    @available(macOS 13.3, *)
    @MainActor open func transferWindowSharing(to window: NSWindow) async throws { unimplemented() }
    // DUPLICATE: @MainActor open func transferWindowSharing(to window: NSWindow) async throws
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/trytoperform(_:with:)
    @MainActor open override func tryToPerform(_ action: Selector, with object: Any?) -> Bool { super.tryToPerform(action, with: object) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/unregisterdraggedtypes()
    @MainActor open func unregisterDraggedTypes() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/update()
    @MainActor open func update() { post(NSWindow.didUpdateNotification) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/updateconstraintsifneeded()
    @MainActor open func updateConstraintsIfNeeded() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/useoptimizeddrawing(_:)
    @MainActor open func useOptimizedDrawing(_ flag: Bool) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/usertabbingpreference
    @available(macOS 10.12, *)
    @MainActor class public var userTabbingPreference: NSWindow.UserTabbingPreference { NSWindow.UserTabbingPreference(rawValue: 2)! }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/validrequestor(forsendtype:returntype:)
    @MainActor open override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/viewsneeddisplay
    @MainActor open var viewsNeedDisplay: Bool {
        get { _contentView?.needsDisplay ?? false }
        set { if newValue { _platform?.setNeedsDisplay(nil) } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/visualizeconstraints(_:)
    @MainActor open func visualizeConstraints(_ constraints: [NSLayoutConstraint]?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/willbeginsheetnotification
    static public var willBeginSheetNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowWillBeginSheetNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/willclosenotification
    static public var willCloseNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowWillCloseNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/willenterfullscreennotification
    static public var willEnterFullScreenNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowWillEnterFullScreenNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/willenterversionbrowsernotification
    static public var willEnterVersionBrowserNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowWillEnterVersionBrowserNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/willexitfullscreennotification
    static public var willExitFullScreenNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowWillExitFullScreenNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/willexitversionbrowsernotification
    static public var willExitVersionBrowserNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowWillExitVersionBrowserNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/willminiaturizenotification
    static public var willMiniaturizeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowWillMiniaturizeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/willmovenotification
    static public var willMoveNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowWillMoveNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/willstartliveresizenotification
    static public var willStartLiveResizeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSWindowWillStartLiveResizeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/windowcontroller
    @MainActor open var windowController: NSWindowController? {
        get { _windowController }
        set { _windowController = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/windownumber
    @MainActor open var windowNumber: Int { _windowNumber }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/windownumber(at:belowwindowwithwindownumber:)
    @MainActor public class func windowNumber(at point: NSPoint, belowWindowWithWindowNumber windowNumber: Int) -> Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/windownumbers(options:)
    @MainActor public class func windowNumbers(options: NSWindow.NumberListOptions = []) -> [NSNumber]? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/windowref
    @MainActor open var windowRef: UnsafeMutableRawPointer { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/windowtitlebarlayoutdirection
    @available(macOS 10.12, *)
    @MainActor open var windowTitlebarLayoutDirection: NSUserInterfaceLayoutDirection { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/workswhenmodal
    @MainActor open var worksWhenModal: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/zoom(_:)
    @MainActor open func zoom(_ sender: Any?) { unimplemented() }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityFrame() -> NSRect { unimplemented() }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityParent() -> Any? { unimplemented() }
    // Requirement of NSAccessibilityElementProtocol
    open func isAccessibilityFocused() -> Bool { unimplemented() }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityIdentifier() -> String { unimplemented() }
    // Required by the superclass (NSCoding).
    /// AppKit's plain initializer: a small titled window, as `NSWindow()` gives on macOS.
    @MainActor public override convenience init() {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
    }

    @MainActor public required init?(coder: NSCoder) {
        _styleMask = []
        super.init(coder: coder)
    }
}

extension NSWindow: PlatformWindowOwner {
    public var platformWantsMenuBar: Bool { !(self is NSPanel) }
}
