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
@MainActor open class NSWindow: NSResponder, NSAnimatablePropertyContainer, NSMenuItemValidation, NSUserInterfaceValidations, NSUserInterfaceItemIdentification, NSAppearanceCustomization, NSAccessibilityElementProtocol, NSAccessibilityProtocol, NSSelectorHandling {
    // MARK: Storage
    private var _platform: (any PlatformWindow)?

    // MARK: Native layer hosting

    /// True while the platform composites the content view's layer tree itself. Not part
    /// of Apple's API: MetalKit presents through a swap chain only on a hosted tree.
    public internal(set) var _hostsLayersNatively = false
    private var _layerSceneDirty = false
    private var _layerSceneFrame = 0

    /// Called when the content view becomes layer-backed, is replaced, or the window shows:
    /// offers the tree to the platform. Only a fully layer-backed window qualifies, so every
    /// view is a visual and stacking stays correct.
    internal func _updateLayerHosting() {
        let wantsHosting = _contentView?.layer != nil && _platform != nil
        if wantsHosting && !_hostsLayersNatively {
            _layerSceneFrame += 1
            if let scene = _makeLayerScene(), _platform?.hostLayerScene(scene) == true {
                _hostsLayersNatively = true
                _layerSceneDirty = false
                _platform?.setNeedsDisplay(nil)      // the backing store must stop showing the software composite
            }
        } else if !wantsHosting && _hostsLayersNatively {
            _hostsLayersNatively = false
            _ = _platform?.hostLayerScene(nil)
            _platform?.setNeedsDisplay(nil)
        }
    }

    private func _makeLayerScene() -> PlatformLayerScene? {
        guard let cv = _contentView, let root = cv.layer else { return nil }
        cv.layoutSubtreeIfNeeded()
        let content = NSRect(origin: .zero, size: contentRect(forFrameRect: frame).size)
        var scene = root._buildScene(parentFlipped: false, parentBounds: content, scale: backingScaleFactor, frame: _layerSceneFrame)
        // The window buttons overlay is a second root above the content.
        if let buttons = _windowButtons, _showsWindowButtons, let layer = buttons.layer {
            let extra = layer._buildScene(parentFlipped: false, parentBounds: content, scale: backingScaleFactor, frame: _layerSceneFrame)
            let offset = scene.nodes.count
            for var node in extra.nodes {
                if let p = node.parent { node.parent = p + offset }
                scene.nodes.append(node)
            }
        }
        return scene
    }

    // MARK: Standard actions (TargetAction.swift)

    /// The window-level actions menus and the standard buttons send: close, minimize, zoom.
    public func respondsToSelectorAction(_ action: Selector) -> Bool {
        switch NSStringFromSelector(action) {
        case "performClose:": return _styleMask.contains(.closable)
        case "performMiniaturize:": return _styleMask.contains(.miniaturizable)
        case "performZoom:": return _styleMask.contains(.resizable)
        default: return false
        }
    }
    public func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch NSStringFromSelector(action) {
        case "performClose:": performClose(sender)
        case "performMiniaturize:": performMiniaturize(sender)
        case "performZoom:": performZoom(sender)
        default: return false
        }
        return true
    }

    // MARK: Window buttons (NSWindowButtons.swift)

    private var _windowButtons: _NSWindowButtonsView?
    /// Content that covers the title bar shows AppKit's own close/miniaturize/zoom buttons.
    internal var _showsWindowButtons: Bool { _styleMask.contains(.titled) && _styleMask.contains(.fullSizeContentView) }

    /// Creates the overlay when first needed and keeps it placed and styled.
    @discardableResult
    internal func _ensureWindowButtons(create: Bool = false) -> _NSWindowButtonsView? {
        if _windowButtons == nil, create || _showsWindowButtons {
            let v = _NSWindowButtonsView()
            v.nextResponder = self
            v._setWindow(self)
            for (kind, b) in [(NSWindow.ButtonType.closeButton, v.close), (.miniaturizeButton, v.miniaturize), (.zoomButton, v.zoom)] {
                b.target = self
                let selector = kind == .closeButton ? "performClose:" : kind == .miniaturizeButton ? "performMiniaturize:" : "performZoom:"
                b.action = Selector((selector))
            }
            _windowButtons = v
        }
        if let v = _windowButtons {
            v.layout(in: contentRect(forFrameRect: frame).size, styleMask: _styleMask, isKey: _isKey)
            v.isHidden = !_showsWindowButtons
        }
        return _windowButtons
    }

    /// The view under a window point: the buttons overlay first, then the content.
    private func _hitTest(_ point: NSPoint) -> NSView? {
        if _showsWindowButtons, let b = _windowButtons, !b.isHidden, let hit = b.hitTest(point) { return hit }
        return _contentView?.hitTest(point)
    }

    /// The hosted tree changed: a commit is coalesced into the next frame (or the next display).
    internal func _setLayerSceneNeedsCommit() {
        guard _hostsLayersNatively, !_layerSceneDirty else { return }
        _layerSceneDirty = true
        CARuntime.requestFrame()
    }

    /// Sends the current tree to the platform if anything changed since the last commit.
    internal func _commitLayerSceneIfNeeded() {
        guard _hostsLayersNatively, _layerSceneDirty else { return }
        _layerSceneDirty = false
        _layerSceneFrame += 1
        if let scene = _makeLayerScene(), _platform?.hostLayerScene(scene) != true {
            _hostsLayersNatively = false            // the platform gave hosting up: back to software
            _platform?.setNeedsDisplay(nil)
        }
    }
    private var _contentView: NSView?
    private var _accessibilityID = 0
    private var _a11yOverrides = _NSAccessibilityOverrides()
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
    private var _appearance: NSAppearance? = nil
    private var _fieldEditor: NSTextView? = nil
    /// Backdrop requested by an NSVisualEffectView blending behind the window.
    internal var _backdrop: PlatformWindowChrome.Backdrop = .none { didSet { _updateChrome() } }
    private weak var _windowController: NSWindowController?
    private var _contentViewController: NSViewController? = nil
    private var _lastFrame = NSRect.zero
    /// The screen the window was last seen on (its name), for `didChangeScreenNotification`.
    private var _lastScreenName: String?
    /// Content rect at the time of the last close (the platform window knows its real frame insets).
    private var _lastContentRect: NSRect? = nil
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
        if let vc = view._viewController { view.nextResponder = vc; vc.nextResponder = self } else { view.nextResponder = self }
        view._setWindow(self)
        _platform?.setNeedsDisplay(nil)
        _ensureWindowButtons()
        _updateLayerHosting()
    }

    internal var _platformWindow: (any PlatformWindow)? { _platform }

    /// A closed window ordered front again gets a fresh platform window, as AppKit re-shows
    /// a window that was not released when closed.
    private func _reopenIfNeeded() {
        guard _platform == nil else { return }
        if NSView._traceInvalidation { NSView._trace("reopen \'\(_title)\'") }
        let content = _lastContentRect ?? Platform.backend.contentRect(forFrameRect: _lastFrame, styleMask: _styleMask)
        _platform = Platform.backend.makeWindow(owner: self, contentRect: content, styleMask: _styleMask)
        _platform?.title = _title
        _isClosing = false
        _updateChrome()
        // The frame (not just the content) is restored so per-window menu bars do not shift it.
        if _lastFrame.width > 0 { _platform?.frame = _lastFrame }
        NSApplication.shared._register(window: self)
        _contentView?.needsDisplay = true
        _platform?.setNeedsDisplay(nil)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/appearance
    @MainActor public var appearance: NSAppearance? {
        get { _appearance }
        set { _appearance = newValue; _contentView?._effectiveAppearanceDidChange(); _platform?.setNeedsDisplay(nil) }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/effectiveappearance
    @MainActor public var effectiveAppearance: NSAppearance { _appearance ?? NSApplication.shared.effectiveAppearance }

    /// Input methods talk to the first responder when it accepts text input.
    public func platformWindowTextInput() -> PlatformTextInput? {
        guard let client = _firstResponder as? NSTextInputClient, let view = client as? NSView else { return nil }
        return PlatformTextInput(
            hasMarkedText: { client.hasMarkedText() },
            setMarkedText: { text, selected in client.setMarkedText(text, selectedRange: selected, replacementRange: NSRange(location: NSNotFound, length: 0)) },
            unmarkText: { client.unmarkText() },
            insertText: { text in client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0)) },
            markedRect: { [weak view, weak self] in
                guard let view, let self else { return nil }
                if let tv = view as? NSTextView { return tv._inputMethodRect }
                return self.convertFromScreen(client.firstRect(forCharacterRange: client.selectedRange(), actualRange: nil))
            })
    }

    /// The chrome the backend should show for the current properties.
    internal var _chrome: PlatformWindowChrome {
        var c = PlatformWindowChrome()
        c.extendsContentIntoTitleBar = _styleMask.contains(.fullSizeContentView) || !_styleMask.contains(.titled)
        c.hidesTitle = _titleVisibility == .hidden || !_styleMask.contains(.titled)
        c.transparentTitleBar = _titlebarAppearsTransparent
        c.backdrop = _backdrop
        c.isTransparent = !_isOpaque
        c.hasShadow = _hasShadow
        c.movableByBackground = _isMovableByWindowBackground
        return c
    }

    internal func _updateChrome() {
        _platform?.chrome = _chrome
    }

    /// Content that extends into the title bar is draggable in its top band (AppKit's
    /// title bar height) and anywhere when movable by background, unless a view that
    /// takes mouse downs is under the point.
    public func platformWindowHitTest(_ point: NSPoint) -> PlatformWindowHitRegion {
        guard let content = _contentView else { return .client }
        let hit = _hitTest(point) ?? content.hitTest(point)
        if let v = hit, !v.mouseDownCanMoveWindow { return .client }
        if _isMovableByWindowBackground { return .caption }
        let chrome = _chrome
        if chrome.extendsContentIntoTitleBar, point.y >= content.bounds.height - NSWindow._titleBarBandHeight { return .caption }
        return .client
    }

    /// The draggable band at the top of windows whose content covers the title bar.
    internal static let _titleBarBandHeight: CGFloat = 28

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
        if NSView._traceInvalidation { NSView._trace("frame \'\(_title)\' \(frame)") }
        let old = _lastFrame
        _lastFrame = frame
        let cr = contentRect(forFrameRect: frame)
        if let cv = _contentView, cv.frame.size != cr.size {
            cv.setFrameSize(cr.size)
        }
        _ensureWindowButtons()
        if old.size != frame.size {
            post(NSWindow.didResizeNotification)
            delegate?.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: self))
        }
        if old.origin != frame.origin {
            post(NSWindow.didMoveNotification)
            delegate?.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: self))
        }
        _noteScreen()
    }

    /// Posts `didChangeScreenNotification` when the move or resize put the window on
    /// another screen (a monitor of another scale on Windows sends WM_DPICHANGED too).
    private func _noteScreen() {
        guard let s = screen else { return }
        let name = s.localizedName
        guard name != _lastScreenName else { return }
        let first = _lastScreenName == nil
        _lastScreenName = name
        guard !first else { return }        // the first sighting, at creation, before a title exists
        if NSView._traceInvalidation { NSView._trace("screen \'\(_title)\' \(name) scale \(s.backingScaleFactor)") }
        post(NSWindow.didChangeScreenNotification)
        delegate?.windowDidChangeScreen(Notification(name: NSWindow.didChangeScreenNotification, object: self))
    }

    public func platformWindowShouldClose() -> Bool {
        let should = delegate?.windowShouldClose(self) ?? true
        if NSView._traceInvalidation { NSView._trace("shouldClose \'\(_title)\' -> \(should)") }
        return should
    }

    public func platformWindowWillClose() {
        if !_isClosing { close() }
    }

    public func platformWindowDidBecomeKey() { becomeKey() }
    public func platformWindowDidResignKey() { resignKey() }

    public func platformWindowDidChangeBackingScaleFactor(_ scale: CGFloat) {
        if NSView._traceInvalidation { NSView._trace("backing scale \'\(_title)\' \(scale)") }
        post(NSWindow.didChangeBackingPropertiesNotification)
        delegate?.windowDidChangeBackingProperties(Notification(name: NSWindow.didChangeBackingPropertiesNotification, object: self))
        func visit(_ v: NSView) {
            v.layer?.contentsScale = scale        // re-rasterises the layer, so a hosted scene recommits
            v.viewDidChangeBackingProperties()
            v.subviews.forEach(visit)
        }
        if let cv = _contentView { visit(cv) }
        _setLayerSceneNeedsCommit()
        // The backing store is a new pixel size: everything is drawn again at the new scale.
        _platform?.setNeedsDisplay(nil)
    }

    public func platformWindowDraw(into context: CGContext, dirtyRect: NSRect) {
        if NSView._traceInvalidation { NSView._trace("paint \'\(_title)\' \(dirtyRect)") }
        _commitLayerSceneIfNeeded()
        context.saveGState()
        // The background is a dynamic colour: resolve it under the window's appearance, as the
        // views do, so a dark-themed system gets a dark window behind its light text.
        let previousAppearance = NSAppearance.current
        NSAppearance.current = effectiveAppearance
        if _isOpaque {
            context.setFillColor(_backgroundColor.cgColor)
            context.fill(dirtyRect)
        }
        _contentView?.layoutSubtreeIfNeeded()
        _contentView?._displayHierarchy(in: context, dirtyRect: dirtyRect)
        if _showsWindowButtons, !_hostsLayersNatively, let buttons = _ensureWindowButtons() {
            buttons._displayHierarchy(in: context, dirtyRect: dirtyRect)
        }
        NSAppearance.current = previousAppearance
        NSGraphicsContext.current = nil
        context.restoreGState()
    }

    public func platformDragEntered(_ drag: PlatformDragInfo) -> NSDragOperation { _NSPlatformDragDelivery.entered(drag, window: self) }
    public func platformDragUpdated(_ drag: PlatformDragInfo) -> NSDragOperation { _NSPlatformDragDelivery.updated(drag, window: self) }
    public func platformDragExited() { _NSPlatformDragDelivery.exited(window: self) }
    public func platformDrop(_ drag: PlatformDragInfo) -> NSDragOperation { _NSPlatformDragDelivery.drop(drag, window: self) }
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
        _updateChrome()
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
    @MainActor public convenience init(contentViewController: NSViewController) {
        let v = contentViewController.view
        var size = v.frame.size
        if size.width <= 0 || size.height <= 0 {
            let fitting = v.fittingSize
            size = NSSize(width: max(fitting.width, 100), height: max(fitting.height, 100))
        }
        self.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        self.contentViewController = contentViewController
        if let t = contentViewController.title { title = t }
    }
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
    @MainActor open var attachedSheet: NSWindow? { _sheets.last }
    // Sheets: shown as windows parked at the top centre of their parent (no slide-down
    // animation and the parent stays interactive), ended with endSheet(_:returnCode:).
    private var _sheets: [NSWindow] = []
    private var _sheetCompletions: [ObjectIdentifier: (NSApplication.ModalResponse) -> Void] = [:]
    private weak var _sheetParent: NSWindow?

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/beginsheet(_:completionhandler:)
    @MainActor open func beginSheet(_ sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        guard !_sheets.contains(where: { $0 === sheetWindow }) else { return }
        _sheets.append(sheetWindow)
        sheetWindow._sheetParent = self
        if let h = handler { _sheetCompletions[ObjectIdentifier(sheetWindow)] = h }
        let parent = frame
        let size = sheetWindow.frame.size
        sheetWindow.setFrameOrigin(NSPoint(x: parent.midX - size.width / 2, y: parent.maxY - size.height - NSWindow._titleBarBandHeight))
        sheetWindow.makeKeyAndOrderFront(nil)
    }
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
        defer { _ensureWindowButtons(); _windowButtons?.needsDisplay = true }
        guard !_isKey else { return }
        if NSView._traceInvalidation { NSView._trace("becomeKey \'\(_title)\'") }
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
    @MainActor open func beginSheet(_ sheetWindow: NSWindow) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { c in beginSheet(sheetWindow) { c.resume(returning: $0) } }
    }
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
        if NSView._traceInvalidation { NSView._trace("close \'\(_title)\'") }
        _isClosing = true
        post(NSWindow.willCloseNotification)
        delegate?.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: self))
        let disappearing = isVisible
        let wasKey = _isKey
        if disappearing { _contentView?._windowVisibilityWillChange(false) }
        if _isKey { resignKey() }
        if _isMain { resignMain() }
        for child in _childWindows { child.close() }
        _parent?.removeChildWindow(self)
        _lastFrame = frame
        _lastContentRect = _platform?.contentRect(forFrameRect: frame)
        _platform?.close()
        _platform = nil
        if disappearing { _contentView?._windowVisibilityDidChange(false) }
        NSApplication.shared._unregister(window: self)
        // Another visible window becomes key, as AppKit does when the key window closes.
        if wasKey, let next = NSApplication.shared.windows.last(where: { $0 !== self && $0.isVisible && $0.canBecomeKey }) {
            next.makeKeyAndOrderFront(nil)
        }
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
        set {
            _contentViewController = newValue
            if let vc = newValue {
                let v = vc.view
                if v.frame.size.width > 0 && v.frame.size.height > 0 && _contentView == nil { setContentSize(v.frame.size) }
                contentView = v
            }
        }
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
    @MainActor open func deminiaturize(_ sender: Any?) {
        _platform?.deminiaturize()
        _noteDeminiaturized()
    }
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
    @MainActor open func display() { _commitLayerSceneIfNeeded(); _platform?.display() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/displayifneeded()
    @MainActor open func displayIfNeeded() { _commitLayerSceneIfNeeded(); _platform?.displayIfNeeded() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/displaylink(target:selector:)
    @available(macOS 14.0, *)
    @MainActor open func displayLink(target: Any, selector: Selector) -> CADisplayLink {
        _CoreAnimationHost.installIfNeeded()
        let t = target as AnyObject
        return CADisplayLink { link in _ = ActionRegistry.perform(selector, on: t, with: link) }
    }
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
    @MainActor open func endEditing(for object: Any?) {
        guard let e = _fieldEditor, e.superview != nil, firstResponder === e else { return }
        _ = makeFirstResponder(nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/endsheet(_:)
    @MainActor open func endSheet(_ sheetWindow: NSWindow) { endSheet(sheetWindow, returnCode: .OK) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/endsheet(_:returncode:)
    @MainActor open func endSheet(_ sheetWindow: NSWindow, returnCode: NSApplication.ModalResponse) {
        guard let i = _sheets.firstIndex(where: { $0 === sheetWindow }) else { return }
        _sheets.remove(at: i)
        sheetWindow._sheetParent = nil
        sheetWindow.orderOut(nil)
        let completion = _sheetCompletions.removeValue(forKey: ObjectIdentifier(sheetWindow))
        makeKeyAndOrderFront(nil)
        completion?(returnCode)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/fieldeditor(_:for:)
    @MainActor open func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        if let e = _fieldEditor { return e }
        guard createFlag else { return nil }
        let e = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        e.isFieldEditor = true
        _fieldEditor = e
        return e
    }
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
        set { _hasShadow = newValue; _updateChrome() }
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
    @MainActor open var isMiniaturized: Bool { _platform?.isMiniaturized ?? false }
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
        set { _isMovableByWindowBackground = newValue; _updateChrome() }
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
        set { _isOpaque = newValue; _updateChrome(); _platform?.setNeedsDisplay(nil) }
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
    @MainActor open var isSheet: Bool { _sheetParent != nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/isvisible
    @MainActor open var isVisible: Bool { _platform?.isVisible ?? false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/iszoomable
    @MainActor open var isZoomable: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/iszoomed
    @MainActor open var isZoomed: Bool { _platform?.isZoomed ?? false }
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
            _accessibilityNotify(.focus(nil))
            return false
        }
        if NSView._traceInvalidation { NSView._trace("a11y focus '\(_title)' -> \(String(describing: type(of: target))) element \(accessibilityFocusedElementID.map(String.init) ?? "none")") }
        _accessibilityNotify(.focus(accessibilityFocusedElementID))
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
    @MainActor open func miniaturize(_ sender: Any?) {
        post(NSWindow.willMiniaturizeNotification)
        _platform?.miniaturize()
        _noteMiniaturized()
    }
    /// Whether the did-miniaturize notification is outstanding: the backend may report the
    /// system's minimise synchronously inside `miniaturize()` or on its own later, and the
    /// delegate hears each change once either way.
    private var _miniaturizedNoted = false
    private func _noteMiniaturized() {
        guard !_miniaturizedNoted else { return }
        _miniaturizedNoted = true
        post(NSWindow.didMiniaturizeNotification)
        delegate?.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification, object: self))
    }
    private func _noteDeminiaturized() {
        guard _miniaturizedNoted else { return }
        _miniaturizedNoted = false
        post(NSWindow.didDeminiaturizeNotification)
        delegate?.windowDidDeminiaturize(Notification(name: NSWindow.didDeminiaturizeNotification, object: self))
    }
    public func platformWindowDidMiniaturize() { _noteMiniaturized() }
    public func platformWindowDidDeminiaturize() { _noteDeminiaturized() }
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
        _reopenIfNeeded()
        let appearing = !isVisible
        if appearing { _contentView?._windowVisibilityWillChange(true) }
        _platform?.show()
        _platform?.orderBack()
        if appearing { _contentView?._windowVisibilityDidChange(true) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/orderfront(_:)
    @MainActor open func orderFront(_ sender: Any?) {
        _reopenIfNeeded()
        let appearing = !isVisible
        if appearing { _contentView?._windowVisibilityWillChange(true) }
        _platform?.show()
        _platform?.displayIfNeeded()
        if appearing { _contentView?._windowVisibilityDidChange(true) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/orderfrontregardless()
    @MainActor open func orderFrontRegardless() { orderFront(nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/orderout(_:)
    @MainActor open func orderOut(_ sender: Any?) {
        let disappearing = isVisible
        if disappearing { _contentView?._windowVisibilityWillChange(false) }
        if _isKey { resignKey() }
        if _isMain { resignMain() }
        _platform?.hide()
        if disappearing { _contentView?._windowVisibilityDidChange(false) }
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
    @MainActor open func performMiniaturize(_ sender: Any?) {
        guard _styleMask.contains(.miniaturizable) else { return }
        miniaturize(sender)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/performzoom(_:)
    @MainActor open func performZoom(_ sender: Any?) {
        guard _styleMask.contains(.resizable) else { return }
        zoom(sender)
    }
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
        defer { _ensureWindowButtons(); _windowButtons?.needsDisplay = true }
        guard _isKey else { return }
        if NSView._traceInvalidation { NSView._trace("resignKey \'\(_title)\'") }
        _isKey = false
        // Losing the keyboard (another window or application activated) dismisses open menus.
        if let t = _NSMenuTracker.current, !t.isMenuWindow(self) { t.cancel() }
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
        // A backend that knows which monitor holds the window answers directly (its scale
        // is the window's); otherwise the screen holding most of the frame wins.
        if let d = _platform?.currentDisplay { return NSScreen(display: d) }
        let f = frame
        let all = NSScreen.screens
        return all.max { $0.frame.intersection(f).area < $1.frame.intersection(f).area } ?? all.first
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/selectkeyview(following:)
    @MainActor open func selectKeyView(following view: NSView) { _selectKeyView(forward: true, from: view) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/selectkeyview(preceding:)
    @MainActor open func selectKeyView(preceding view: NSView) { _selectKeyView(forward: false, from: view) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/selectnextkeyview(_:)
    @MainActor open func selectNextKeyView(_ sender: Any?) { _selectKeyView(forward: true, from: nil) }

    /// A key the responder chain did not use: Tab and Shift-Tab move the key view, as
    /// AppKit's window does when a plain view is the first responder.
    @MainActor open override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == "\t" || event.charactersIgnoringModifiers == "\u{19}" {
            if event.modifierFlags.contains(.shift) || event.charactersIgnoringModifiers == "\u{19}" { selectPreviousKeyView(self) } else { selectNextKeyView(self) }
            if NSView._traceInvalidation { NSView._trace("window '\(_title)' Tab -> first responder \(firstResponder.map { String(describing: type(of: $0)) } ?? "nil")") }
            return
        }
        super.keyDown(with: event)
    }

    /// Moves focus through the views that accept first responder, in hierarchy order
    /// (`nextKeyView` chains are not wired yet).
    private func _selectKeyView(forward: Bool, from start: NSView?) {
        guard let content = _contentView else { return }
        var views: [NSView] = []
        func visit(_ v: NSView) {
            if !v.isHidden && v.acceptsFirstResponder && !(v is NSText) { views.append(v) }
            for s in v.subviews { visit(s) }
        }
        visit(content)
        guard !views.isEmpty else { return }
        var current: NSView? = start ?? (firstResponder as? NSView)
        if let t = current as? NSText, let owner = t.superview { current = owner }
        var index = current.flatMap { c in views.firstIndex { $0 === c } } ?? (forward ? -1 : views.count)
        for _ in 0..<views.count {
            index = (index + (forward ? 1 : -1) + views.count) % views.count
            if views[index] !== current, makeFirstResponder(views[index]) { return }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/selectnexttab(_:)
    @available(macOS 10.12, *)
    @MainActor open func selectNextTab(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/selectpreviouskeyview(_:)
    @MainActor open func selectPreviousKeyView(_ sender: Any?) { _selectKeyView(forward: false, from: nil) }
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
            let hit = _hitTest(event.locationInWindow)
            _mouseDownView = hit
            if let v = hit, v.acceptsFirstResponder, firstResponder !== v { _ = makeFirstResponder(v) }
            _dispatchMouse(event, to: hit ?? self)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            _dispatchMouse(event, to: _mouseDownView ?? _hitTest(event.locationInWindow) ?? self)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let target: NSResponder = _mouseDownView ?? _hitTest(event.locationInWindow) ?? self
            _mouseDownView = nil
            _dispatchMouse(event, to: target)
        case .mouseMoved:
            _updateCursor(at: event.locationInWindow)
            _windowButtons?.updateHover(event.locationInWindow)
            guard _acceptsMouseMovedEvents else { return }
            _dispatchMouse(event, to: _hitTest(event.locationInWindow) ?? self)
        case .scrollWheel, .mouseEntered, .mouseExited:
            _dispatchMouse(event, to: _hitTest(event.locationInWindow) ?? self)
        case .keyDown:
            // An editing text field commits on Return before the default button sees it.
            if let editor = firstResponder as? NSTextView, editor._consumesReturnKey, event.charactersIgnoringModifiers == "\r",
               event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                editor.keyDown(with: event)
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
        if NSView._traceInvalidation { NSView._trace("setFrame \'\(_title)\' \(frameRect)") }
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
    @MainActor open var sheetParent: NSWindow? { _sheetParent }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/sheets
    @MainActor open var sheets: [NSWindow] { _sheets }
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
    @MainActor open func standardWindowButton(_ b: NSWindow.ButtonType) -> NSButton? {
        guard let v = _ensureWindowButtons(create: true) else { return nil }
        switch b {
        case .closeButton: return v.close
        case .miniaturizeButton: return v.miniaturize
        case .zoomButton: return v.zoom
        default: return nil
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/standardwindowbutton(_:for:)
    @MainActor public class func standardWindowButton(_ b: NSWindow.ButtonType, for styleMask: NSWindow.StyleMask) -> NSButton? {
        switch b {
        case .closeButton, .miniaturizeButton, .zoomButton:
            let button = _NSWindowButton(kind: b)
            button.isEnabled = b == .closeButton ? styleMask.contains(.closable) : b == .miniaturizeButton ? styleMask.contains(.miniaturizable) : styleMask.contains(.resizable)
            return button
        default: return nil
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/stylemask
    @MainActor open var styleMask: NSWindow.StyleMask {
        get { _styleMask }
        set { _styleMask = newValue; _platform?.styleMask = newValue; _updateChrome() }
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
        set { _title = newValue; _platform?.title = newValue; _accessibilityNotify(.name(_accessibilityElementID)) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/titlevisibility
    @available(macOS 10.10, *)
    @MainActor open var titleVisibility: NSWindow.TitleVisibility {
        get { _titleVisibility }
        set { _titleVisibility = newValue; _updateChrome() }
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
        set { _titlebarAppearsTransparent = newValue; _updateChrome() }
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
    @MainActor open func zoom(_ sender: Any?) {
        guard delegate?.windowShouldZoom(self, toFrame: screen?.visibleFrame ?? frame) ?? true else { return }
        _platform?.zoom()
    }
    // MARK: Accessibility (ADR-0013)

    /// Stable identity of the window in the platform accessibility tree.
    public var _accessibilityElementID: Int {
        if _accessibilityID == 0 { _accessibilityID = _NSAccessibilityIDs.next() }
        return _accessibilityID
    }
    /// Forwards a change to the platform window (UI Automation, AT-SPI) and keeps it for tests.
    @MainActor internal func _accessibilityNotify(_ change: PlatformAccessibilityChange) {
        _platform?.accessibilityDidChange(change)
    }
    open func accessibilityRole() -> NSAccessibility.Role? { _a11yOverrides.role ?? (isSheet ? .sheet : .window) }
    open func setAccessibilityRole(_ accessibilityRole: NSAccessibility.Role?) { _a11yOverrides.role = accessibilityRole }
    open func accessibilitySubrole() -> NSAccessibility.Subrole? {
        if let s = _a11yOverrides.subrole { return s }
        if isSheet { return .dialog }
        if self is NSPanel { return _styleMask.contains(.utilityWindow) ? .floatingWindow : .dialog }
        return .standardWindow
    }
    open func setAccessibilitySubrole(_ accessibilitySubrole: NSAccessibility.Subrole?) { _a11yOverrides.subrole = accessibilitySubrole }
    open func accessibilityTitle() -> String? { _a11yOverrides.title ?? _title }
    open func setAccessibilityTitle(_ accessibilityTitle: String?) { _a11yOverrides.title = accessibilityTitle; _accessibilityNotify(.name(_accessibilityElementID)) }
    open func accessibilityLabel() -> String? { _a11yOverrides.label }
    open func setAccessibilityLabel(_ accessibilityLabel: String?) { _a11yOverrides.label = accessibilityLabel; _accessibilityNotify(.name(_accessibilityElementID)) }
    open func accessibilityIdentifier() -> String { _a11yOverrides.identifier ?? _identifier?.rawValue ?? "" }
    open func setAccessibilityIdentifier(_ accessibilityIdentifier: String?) { _a11yOverrides.identifier = accessibilityIdentifier }
    open func accessibilityHelp() -> String? { _a11yOverrides.help }
    open func setAccessibilityHelp(_ accessibilityHelp: String?) { _a11yOverrides.help = accessibilityHelp }
    open func isAccessibilityElement() -> Bool { _a11yOverrides.isElement ?? true }
    open func setAccessibilityElement(_ accessibilityElement: Bool) { _a11yOverrides.isElement = accessibilityElement }
    open func isAccessibilityHidden() -> Bool { _a11yOverrides.isHidden }
    open func setAccessibilityHidden(_ accessibilityHidden: Bool) { _a11yOverrides.isHidden = accessibilityHidden }
    open func isAccessibilityEnabled() -> Bool { _a11yOverrides.isEnabled ?? true }
    open func setAccessibilityEnabled(_ accessibilityEnabled: Bool) { _a11yOverrides.isEnabled = accessibilityEnabled }
    /// The window frame in screen coordinates.
    open func accessibilityFrame() -> NSRect { _a11yOverrides.frame ?? frame }
    open func setAccessibilityFrame(_ accessibilityFrame: NSRect) { _a11yOverrides.frame = accessibilityFrame }
    open func accessibilityParent() -> Any? { _a11yOverrides.parent ?? NSApplication.shared }
    open func setAccessibilityParent(_ accessibilityParent: Any?) { _a11yOverrides.parent = accessibilityParent }
    /// The content view's elements (the content view itself is ignored, like a plain view).
    open func accessibilityChildren() -> [Any]? {
        if let c = _a11yOverrides.children { return c }
        guard let cv = _contentView else { return [] }
        return cv.isAccessibilityElement() ? [cv] : cv.accessibilityChildren()
    }
    open func setAccessibilityChildren(_ accessibilityChildren: [Any]?) { _a11yOverrides.children = accessibilityChildren; _accessibilityNotify(.structure(_accessibilityElementID)) }
    open func accessibilityVisibleChildren() -> [Any]? { accessibilityChildren() }
    open func accessibilityChildrenInNavigationOrder() -> [any NSAccessibilityElementProtocol]? { accessibilityChildren()?.compactMap { $0 as? any NSAccessibilityElementProtocol } }
    open func isAccessibilityFocused() -> Bool { _isKey }
    open func setAccessibilityFocused(_ accessibilityFocused: Bool) { if accessibilityFocused { makeKeyAndOrderFront(nil) } }
    open func isAccessibilityMain() -> Bool { isMainWindow }
    open func isAccessibilityMinimized() -> Bool { isMiniaturized }
    open func setAccessibilityMinimized(_ accessibilityMinimized: Bool) { if accessibilityMinimized { miniaturize(nil) } else { deminiaturize(nil) } }
    open func isAccessibilityModal() -> Bool { NSApplication.shared.modalWindow === self }
    open func accessibilityWindow() -> Any? { self }
    open func accessibilityTopLevelUIElement() -> Any? { self }
    open func accessibilityActivationPoint() -> NSPoint { NSPoint(x: frame.midX, y: frame.midY) }
    open func accessibilityPerformRaise() -> Bool { makeKeyAndOrderFront(nil); return true }
    /// The element with keyboard focus: the first responder view, or the text field a
    /// focused field editor edits. Nil when focus is on a view that is not an element.
    open func accessibilityApplicationFocusedUIElement() -> Any? {
        guard let v = (firstResponder as? NSView)?._accessibilityFocusTarget else { return nil }
        return v.isAccessibilityElement() && !v.isHiddenOrHasHiddenAncestor && !v.isAccessibilityHidden() ? v : nil
    }
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
    public var platformAccessibility: any PlatformAccessibilityProvider { self }
}

// MARK: - The platform's view of the window's accessibility tree (ADR-0013)

extension NSWindow: PlatformAccessibilityProvider {
    /// The window as the root of a snapshot: title, frame, key state and the content
    /// view's elements below it.
    public func accessibilityTree() -> PlatformAccessibilityElement {
        var e = PlatformAccessibilityElement(id: _accessibilityElementID, role: (accessibilityRole() ?? .window).rawValue, frame: accessibilityFrame())
        e.subrole = accessibilitySubrole()?.rawValue
        e.title = accessibilityTitle()
        e.label = accessibilityLabel()
        e.help = accessibilityHelp()
        let identifier = accessibilityIdentifier()
        e.identifier = identifier.isEmpty ? nil : identifier
        e.isEnabled = isAccessibilityEnabled()
        e.isFocusable = canBecomeKey
        e.isFocused = _isKey
        e.actions = [.raise]
        e.children = (accessibilityChildren() ?? []).compactMap { c -> PlatformAccessibilityElement? in
            guard let v = c as? NSView, !v.isHidden, !v.isAccessibilityHidden() else { return nil }
            return v._accessibilityElement()
        }
        return e
    }

    public var accessibilityFocusedElementID: Int? { (accessibilityApplicationFocusedUIElement() as? NSView)?._accessibilityElementID }

    /// The view behind an element id, the window itself for its own id.
    @MainActor internal func _accessibilityView(withID id: Int) -> NSView? { _contentView?._accessibilityView(withID: id) }

    public func accessibilityPerform(_ action: PlatformAccessibilityAction, on elementID: Int) -> Bool {
        if elementID == _accessibilityElementID { return action == .raise ? accessibilityPerformRaise() : false }
        guard let v = _accessibilityView(withID: elementID) else {
            return _contentView?._accessibilityVirtualElement(withID: elementID)?._accessibilityPerform(action) ?? false
        }
        switch action {
        case .press: return v.accessibilityPerformPress()
        case .increment: return v.accessibilityPerformIncrement()
        case .decrement: return v.accessibilityPerformDecrement()
        case .showMenu: return v.accessibilityPerformShowMenu()
        case .confirm: return v.accessibilityPerformConfirm()
        case .cancel: return v.accessibilityPerformCancel()
        case .pick: return v.accessibilityPerformPick()
        case .raise: return v.accessibilityPerformRaise()
        }
    }

    public func accessibilitySetValue(_ value: PlatformAccessibilityValue, on elementID: Int) -> Bool {
        guard let v = _accessibilityView(withID: elementID), v.isAccessibilityEnabled() else { return false }
        return v._accessibilitySetValue(value)
    }

    public func accessibilityFocus(_ elementID: Int) -> Bool {
        if elementID == _accessibilityElementID { makeKeyAndOrderFront(nil); return true }
        guard let v = _accessibilityView(withID: elementID) ?? _contentView?._accessibilityVirtualElement(withID: elementID)?._accessibilityOwnerView else { return false }
        if !_isKey { makeKeyAndOrderFront(nil) }
        return makeFirstResponder(v)
    }

    public func accessibilitySetSelected(_ selected: Bool, on elementID: Int, extending: Bool) -> Bool {
        guard let v = _accessibilityView(withID: elementID) else {
            // A tab or a segment: selecting it is pressing it.
            guard selected, let e = _contentView?._accessibilityVirtualElement(withID: elementID) else { return false }
            return e._accessibilityPerform(.press)
        }
        if let row = v as? NSTableRowView { return row._accessibilitySetSelected(selected, extending: extending) }
        v.setAccessibilitySelected(selected)
        return true
    }
}
