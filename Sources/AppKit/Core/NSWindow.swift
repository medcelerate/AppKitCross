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

    /// A native surface within the content area for a GPU swap chain, where the platform
    /// has one (Linux: a child X window or a Wayland subsurface; ADR-0012). Not part of
    /// Apple's API: MetalKit presents through it when the window does not host its layers.
    public func _makePresentationSurface(frame: NSRect) -> (any PlatformPresentationSurface)? { _platform?.makePresentationSurface(frame: frame) }

    /// The content as the window system shows it, presentation surfaces included (tests).
    internal func _captureContent() -> CGImage? { _platform?.captureContent() }

    private func _makeLayerScene() -> PlatformLayerScene? {
        guard let cv = _contentView, let root = cv.layer else { return nil }
        cv.layoutSubtreeIfNeeded()
        // Every root is placed in the platform's content area: the content view sits at
        // its bottom, under the bands a toolbar or title bar accessories take at the top.
        let platformContent = NSRect(origin: .zero, size: _platformContentSize)
        var scene = root._buildScene(parentFlipped: false, parentBounds: platformContent, scale: backingScaleFactor, frame: _layerSceneFrame)
        // The toolbar, the accessories and the window buttons overlays are further roots above the content.
        var overlays: [NSView] = []
        if let t = _toolbarView, !t.isHidden { t.layoutSubtreeIfNeeded(); overlays.append(t) }
        if let a = _accessoryHost, !a.isHidden { a.layoutSubtreeIfNeeded(); overlays.append(a) }
        if let buttons = _windowButtons, _showsWindowButtons { overlays.append(buttons) }
        for overlay in overlays {
            guard let layer = overlay.layer else { continue }
            let extra = layer._buildScene(parentFlipped: false, parentBounds: platformContent, scale: backingScaleFactor, frame: _layerSceneFrame)
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
        case "toggleToolbarShown:": return _toolbar != nil
        case "runToolbarCustomizationPalette:": return _toolbar?.allowsUserCustomization == true
        case "print:", "printWindow:": return _contentView != nil && !_hasDocument
        case "runPageLayout:": return !_hasDocument
        default: return false
        }
    }
    /// A document's window leaves `print:` and `runPageLayout:` to the document, which is
    /// next in the responder chain.
    private var _hasDocument: Bool { (windowController?.document as? NSDocument) != nil }
    public func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch NSStringFromSelector(action) {
        case "print:", "printWindow:": guard !_hasDocument else { return false }; printWindow(sender)
        case "runPageLayout:": guard !_hasDocument else { return false }; NSApplication.shared.runPageLayout(sender)
        case "performClose:": performClose(sender)
        case "performMiniaturize:": performMiniaturize(sender)
        case "performZoom:": performZoom(sender)
        case "toggleToolbarShown:": toggleToolbarShown(sender)
        case "runToolbarCustomizationPalette:": runToolbarCustomizationPalette(sender)
        default: return false
        }
        return true
    }

    // MARK: Window buttons (NSWindowButtons.swift)

    private var _windowButtons: _NSWindowButtonsView?
    /// Content that covers the title bar shows AppKit's own close/miniaturize/zoom buttons;
    /// so does a title bar the platform leaves to the package (Wayland client-side decorations).
    internal var _showsWindowButtons: Bool { _styleMask.contains(.titled) && (_styleMask.contains(.fullSizeContentView) || _hasClientSideTitleBar) }
    /// The platform draws no title bar: the frame has a band above the content that
    /// `platformWindowDrawTitleBar` paints (ClientSideDecoration.swift).
    internal var _hasClientSideTitleBar: Bool { _platform?.hasClientSideTitleBar ?? false }

    /// Creates the overlay when first needed and keeps it placed and styled.
    @discardableResult
    internal func _ensureWindowButtons(create: Bool = false) -> _NSWindowButtonsView? {
        if _windowButtons == nil, create || _showsWindowButtons {
            let v = _NSWindowButtonsView()
            v.nextResponder = self
            v._setWindow(self)
            v.close.isDocumentEdited = _isDocumentEdited
            for (kind, b) in [(NSWindow.ButtonType.closeButton, v.close), (.miniaturizeButton, v.miniaturize), (.zoomButton, v.zoom)] {
                b.target = self
                let selector = kind == .closeButton ? "performClose:" : kind == .miniaturizeButton ? "performMiniaturize:" : "performZoom:"
                b.action = Selector((selector))
            }
            _windowButtons = v
        }
        if let v = _windowButtons {
            // The row sits at the top of the content when the content covers the title bar,
            // and at the top of the frame (in the band above the content) when the package
            // draws the title bar.
            let top = _hasClientSideTitleBar && !_styleMask.contains(.fullSizeContentView) ? frame.size : _platformContentSize
            v.layout(in: top, styleMask: _styleMask, isKey: _isKey)
            v.isHidden = !_showsWindowButtons
        }
        _layoutToolbarView()
        return _windowButtons
    }

    // MARK: Toolbar and title bar accessories (NSToolbarView.swift, NSTitlebarAccessoryViewController.swift; ADR-0018, ADR-0023)

    /// The toolbar's view, an overlay root like the buttons: above the content, below the buttons.
    internal var _toolbarView: _NSToolbarView? { _toolbar?._view }
    /// The band the toolbar and the accessories take out of the frame as reflected in the current frame.
    private var _chromeBandApplied: CGFloat = 0
    /// The content area the platform gives this window (the bands above the content view
    /// that a toolbar and the title bar accessories take are part of it).
    internal var _platformContentSize: NSSize {
        if let p = _platform { return p.contentRect(forFrameRect: frame).size }
        return NSSize(width: contentRect(forFrameRect: frame).width, height: contentRect(forFrameRect: frame).height + _chromeBandHeight)
    }
    /// How the toolbar is placed and sized for this window; nil when none is shown.
    internal var _toolbarMetrics: _NSToolbarMetrics? {
        guard let t = _toolbar, t.isVisible, _styleMask.contains(.titled) else { return nil }
        return _NSToolbarMetrics.resolve(style: _toolbarStyle, displayMode: t.displayMode, sizeMode: t.sizeMode, contentCoversTitleBar: _styleMask.contains(.fullSizeContentView))
    }
    /// The height the toolbar takes out of the content area (below the title band). Zero
    /// when the content covers the title bar: the toolbar then overlays the content.
    internal var _toolbarBandHeight: CGFloat {
        guard let m = _toolbarMetrics, m.placement == .belowTitleBar else { return 0 }
        return m.height
    }
    /// Everything the chrome takes out of the platform's content area: the toolbar band,
    /// the strip the leading and trailing accessories get under a title bar the package
    /// does not own, and the bottom accessories.
    internal var _chromeBandHeight: CGFloat { _toolbarBandHeight + _accessoryBandHeight }

    /// The title bar accessories (NSTitlebarAccessoryViewController.swift).
    private var _titlebarAccessories: [NSTitlebarAccessoryViewController] = []
    /// The overlay root that holds the accessory views: above the toolbar, below the buttons.
    internal var _accessoryHost: _NSTitlebarAccessoryHostView?
    /// Whether the package draws the title band the leading and trailing accessories go
    /// into: the content covers it (AppKit's buttons at its top), or the platform leaves
    /// the band to the package (Wayland client-side decorations).
    internal var _ownsTitleBand: Bool { _styleMask.contains(.titled) && (_styleMask.contains(.fullSizeContentView) || _hasClientSideTitleBar) }
    private var _visibleAccessories: [NSTitlebarAccessoryViewController] { _styleMask.contains(.titled) ? _titlebarAccessories.filter { !$0.isHidden } : [] }
    /// The strip under a server-side title bar for the leading and trailing accessories.
    private var _accessoryTopStripHeight: CGFloat {
        guard !_ownsTitleBand else { return 0 }
        return _visibleAccessories.filter { $0.layoutAttribute != .bottom }.map { $0._measuredSize.height }.max() ?? 0
    }
    /// The bottom accessories, stacked under the toolbar.
    private var _accessoryBottomHeight: CGFloat { _visibleAccessories.filter { $0.layoutAttribute == .bottom }.reduce(0) { $0 + $1._measuredSize.height } }
    /// What the accessories take out of the frame; nothing when the content covers the
    /// title bar (they overlay it, `contentLayoutRect` excludes them).
    internal var _accessoryBandHeight: CGFloat {
        guard !_styleMask.contains(.fullSizeContentView) else { return 0 }
        return _accessoryTopStripHeight + _accessoryBottomHeight
    }

    /// The resolved placement of the toolbar and every accessory, in the coordinates of
    /// the platform's content area (the client-side title band lies above it).
    internal struct _TitlebarLayout {
        /// The row the leading and trailing accessories share with the buttons and the title.
        var titleRow = NSRect.zero
        var toolbar: NSRect?
        var accessories: [(NSTitlebarAccessoryViewController, NSRect)] = []
        /// The bands the package paints in the title-bar colour (the strip and the bottom
        /// accessories when they come out of the frame).
        var paintedBands: [NSRect] = []
        /// The top of the content area free of chrome (`contentLayoutRect`).
        var contentTop: CGFloat = 0
        /// What the side accessories take out of a toolbar row they share (unified styles).
        var toolbarInsets: (leading: CGFloat, trailing: CGFloat) = (0, 0)
    }

    internal func _resolveTitlebarLayout() -> _TitlebarLayout {
        var l = _TitlebarLayout()
        let pc = _platformContentSize
        let fullSize = _styleMask.contains(.fullSizeContentView)
        let csd = _hasClientSideTitleBar && !fullSize
        var top = pc.height
        if csd {
            l.titleRow = NSRect(x: 0, y: pc.height, width: pc.width, height: max(0, frame.height - pc.height))
        } else if fullSize {
            l.titleRow = NSRect(x: 0, y: pc.height - NSWindow._titleBarBandHeight, width: pc.width, height: NSWindow._titleBarBandHeight)
        } else {
            let strip = _accessoryTopStripHeight
            l.titleRow = NSRect(x: 0, y: pc.height - strip, width: pc.width, height: strip)
            if strip > 0 { l.paintedBands.append(l.titleRow) }
            top -= strip
        }
        if let m = _toolbarMetrics {
            l.toolbar = NSRect(x: 0, y: top - m.height, width: pc.width, height: m.height)
            top -= m.height
        } else if fullSize {
            top -= NSWindow._titleBarBandHeight
        }
        // Leading and trailing accessories stack outward from their edge of the title row;
        // the buttons keep the left edge whatever the direction, as on macOS.
        let rtl = windowTitlebarLayoutDirection == .rightToLeft
        let buttonsInset: CGFloat = _showsWindowButtons ? _NSWindowButtonsView.width + 4 : 8
        var leftX = buttonsInset, rightX = pc.width - 8
        for a in _visibleAccessories where a.layoutAttribute != .bottom {
            let size = a._measuredSize
            let height = min(size.height, l.titleRow.height > 0 ? l.titleRow.height : size.height)
            let y = l.titleRow.midY - height / 2
            let onLeft: Bool
            switch a.layoutAttribute {
            case .left: onLeft = true
            case .right: onLeft = false
            case .trailing: onLeft = rtl
            default: onLeft = !rtl          // .leading and anything else
            }
            if onLeft {
                l.accessories.append((a, NSRect(x: leftX, y: y, width: size.width, height: height)))
                leftX += size.width + 8
            } else {
                l.accessories.append((a, NSRect(x: rightX - size.width, y: y, width: size.width, height: height)))
                rightX -= size.width + 8
            }
        }
        if fullSize, let t = l.toolbar, t.maxY == pc.height, _toolbarMetrics?.topInset == 0 {
            // A unified toolbar shares the row: its items start after the left-hand
            // accessories and stop before the right-hand ones.
            l.toolbarInsets = (max(0, leftX - buttonsInset), max(0, pc.width - 8 - rightX))
        }
        for a in _visibleAccessories where a.layoutAttribute == .bottom {
            let h = a._measuredSize.height
            let r = NSRect(x: 0, y: top - h, width: pc.width, height: h)
            l.accessories.append((a, r))
            if !fullSize { l.paintedBands.append(r) }
            top -= h
        }
        l.contentTop = top
        return l
    }

    /// Places the toolbar view and the accessory host across the top of the platform's content area.
    internal func _layoutToolbarView() {
        let l = _resolveTitlebarLayout()
        if let t = _toolbar, let v = t._view {
            let m = _toolbarMetrics
            v.isHidden = m == nil
            if m != nil, let f = l.toolbar {
                v.apply(style: _toolbarStyle, contentCoversTitleBar: _styleMask.contains(.fullSizeContentView), accessoryInsets: l.toolbarInsets)
                if v.frame != f { v.frame = f; v.needsLayout = true }
                v.needsDisplay = true
            }
        }
        _layoutAccessoryHost(l)
    }

    private func _layoutAccessoryHost(_ l: _TitlebarLayout) {
        guard let host = _accessoryHost else { return }
        _layingOutAccessories = true
        defer { _layingOutAccessories = false }
        let pc = _platformContentSize
        let csd = _hasClientSideTitleBar && !_styleMask.contains(.fullSizeContentView)
        let f = NSRect(x: 0, y: 0, width: pc.width, height: csd ? max(pc.height, frame.height) : pc.height)
        if host.frame != f { host.frame = f }
        host.isHidden = _visibleAccessories.isEmpty
        host.paintedBands = l.paintedBands
        for (a, r) in l.accessories {
            let v = a.view
            if v.superview !== host { host.addSubview(v) }
            v.isHidden = false
            if v.frame != r { v.frame = r }
        }
        for a in _titlebarAccessories where a.isHidden || !_styleMask.contains(.titled) { a.viewIfLoaded?.isHidden = true }
        host.needsDisplay = true
    }
    private var _layingOutAccessories = false

    /// The toolbar or the accessories appeared, disappeared or changed height: the frame
    /// grows or shrinks by the difference with the top edge fixed, so the content keeps
    /// its size, as on macOS.
    internal func _toolbarGeometryDidChange() {
        guard !_layingOutAccessories else { return }
        let band = _chromeBandHeight
        let delta = band - _chromeBandApplied
        _chromeBandApplied = band
        if delta != 0, _platform != nil {
            var f = frame
            f.origin.y -= delta
            f.size.height += delta
            setFrame(f, display: true)
            if let cv = _contentView { let cr = contentRect(forFrameRect: frame); if cv.frame.size != cr.size { cv.setFrameSize(cr.size) } }
        }
        _ensureWindowButtons()
        _contentView?.needsLayout = true     // contentLayoutRect changed with the band
        _updateChrome()        // the band drags the window (PlatformWindowChrome.hasDraggableBand)
        _toolbar?.validateVisibleItems()
        _platform?.setNeedsDisplay(nil)
    }

    /// An accessory's attribute, visibility or view size changed.
    internal func _accessoryGeometryDidChange() { _toolbarGeometryDidChange() }

    private func _ensureAccessoryHost() -> _NSTitlebarAccessoryHostView {
        if let h = _accessoryHost { return h }
        let h = _NSTitlebarAccessoryHostView()
        h.nextResponder = self
        h._setWindow(self)
        _accessoryHost = h
        return h
    }

    private func _insertTitlebarAccessory(_ vc: NSTitlebarAccessoryViewController, at index: Int) {
        if let w = vc._window, w !== self, let i = w._titlebarAccessories.firstIndex(where: { $0 === vc }) { w.removeTitlebarAccessoryViewController(at: i) }
        if let i = _titlebarAccessories.firstIndex(where: { $0 === vc }) { _titlebarAccessories.remove(at: i) }
        _titlebarAccessories.insert(vc, at: min(max(0, index), _titlebarAccessories.count))
        vc._window = self
        let host = _ensureAccessoryHost()
        let v = vc.view
        v.postsFrameChangedNotifications = true
        vc._observeViewFrame()
        host.addSubview(v)
        _toolbarGeometryDidChange()
    }

    private func _setToolbar(_ toolbar: NSToolbar?) {
        guard toolbar !== _toolbar else { return }
        if let old = _toolbar {
            old._detach()
            _toolbar = nil
            _toolbarGeometryDidChange()
        }
        _toolbar = toolbar
        guard let toolbar else { return }
        if let previous = toolbar._window, previous !== self { previous.toolbar = nil }
        toolbar._attach(to: self)
        if let v = toolbar._view {
            v.nextResponder = self
            v._setWindow(self)
        }
        _toolbarGeometryDidChange()
    }

    /// The view under a window point: the buttons overlay first, then the content.
    internal func _hitTestForTests(_ point: NSPoint) -> NSView? { _hitTest(point) }
    private func _hitTest(_ point: NSPoint) -> NSView? {
        if _showsWindowButtons, let b = _windowButtons, !b.isHidden, let hit = b.hitTest(point) { return hit }
        if let a = _accessoryHost, !a.isHidden, let hit = a.hitTest(point) { return hit }
        if let t = _toolbarView, !t.isHidden, let hit = t.hitTest(point) { return hit }
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

    // MARK: Tracking areas (NSTrackingArea.swift)

    /// The pointer's last known location in window coordinates; nil once it left.
    private var _lastMouseLocation: NSPoint?
    /// Set when a view's geometry, visibility or tracking areas changed: the next
    /// evaluation first runs `updateTrackingAreas()` on the views that need it.
    private var _trackingAreasDirty = true
    /// A tracking area with `cursorUpdate` has the pointer: the cursor rects stand back.
    private var _cursorOwnedByTrackingArea = false

    internal func _trackingAreasDidChange() { _trackingAreasDirty = true }

    /// The key window, the active application or the first responder changed: areas
    /// scoped to that activity enter or exit without the pointer moving.
    internal func _trackingActivityDidChange() { _evaluateTrackingAreas(at: _lastMouseLocation, event: nil, dragging: false) }

    /// The view roots that may carry tracking areas: the content and the overlays.
    private var _trackingRoots: [NSView] {
        var roots: [NSView] = []
        if let cv = _contentView { roots.append(cv) }
        if let t = _toolbarView, !t.isHidden { roots.append(t) }
        if let a = _accessoryHost, !a.isHidden { roots.append(a) }
        return roots
    }

    private func _updateTrackingAreasIfNeeded() {
        guard _trackingAreasDirty else { return }
        _trackingAreasDirty = false
        func visit(_ v: NSView) {
            if v._needsUpdateTrackingAreas {
                v._needsUpdateTrackingAreas = false
                v.updateTrackingAreas()
            }
            for s in v.subviews { visit(s) }
        }
        for r in _trackingRoots { visit(r) }
    }

    private func _collectTrackingAreas() -> [NSTrackingArea] {
        var areas: [NSTrackingArea] = []
        func visit(_ v: NSView) {
            areas.append(contentsOf: v._trackingAreas)    // hidden views included: their areas exit
            for s in v.subviews { visit(s) }
        }
        for r in _trackingRoots { visit(r) }
        return areas
    }

    /// Whether the area's activity scope holds now.
    private func _trackingAreaIsActive(_ area: NSTrackingArea, view: NSView) -> Bool {
        let scope = area._activity
        if scope.contains(.activeAlways) { return true }
        if scope.contains(.activeInActiveApp) { return NSApplication.shared.isActive }
        if scope.contains(.activeInKeyWindow) { return _isKey }
        if scope.contains(.activeWhenFirstResponder) {
            guard let fr = _firstResponder else { return false }
            if fr === view { return true }
            if let v = fr as? NSView { return v.isDescendant(of: view) }
            if let vc = fr as? NSViewController { return vc.viewIfLoaded === view }
            return false
        }
        return false
    }

    /// Matches every tracking area of the view tree against `location` (nil: the pointer
    /// is outside the window). Exits are sent before entries, as AppKit does; `cursorUpdate`
    /// goes to the owner on entry; `mouseMoved` events go to the owners of the areas that
    /// asked for them and hold the pointer. During a drag only areas with
    /// `enabledDuringMouseDrag` change state. Returns true when an area with `cursorUpdate`
    /// holds the pointer, in which case the cursor rects do not set the cursor.
    @discardableResult
    private func _evaluateTrackingAreas(at location: NSPoint?, event: NSEvent?, dragging: Bool) -> Bool {
        _updateTrackingAreasIfNeeded()
        let areas = _collectTrackingAreas()
        guard !areas.isEmpty else { _cursorOwnedByTrackingArea = false; return false }
        let flags = event?.modifierFlags ?? NSEvent._currentModifierFlags
        let time = event?.timestamp ?? ProcessInfo.processInfo.systemUptime
        let point = location ?? NSPoint(x: -100_000, y: -100_000)
        var exits: [NSTrackingArea] = [], entries: [NSTrackingArea] = [], moved: [NSTrackingArea] = []
        var cursorOwned = false
        for area in areas {
            guard let view = area._view, view.window === self else { continue }
            if dragging && !area.options.contains(.enabledDuringMouseDrag) {
                if area._isInside, area.options.contains(.cursorUpdate) || area._ownerCursor != nil { cursorOwned = true }
                continue
            }
            var inside = false
            if _trackingAreaIsActive(area, view: view), let r = area._windowRect, let location {
                inside = r.contains(location)
            }
            if inside != area._isInside {
                area._isInside = inside
                if inside { entries.append(area) } else { exits.append(area) }
            } else if inside, let event, event.type == .mouseMoved, area.options.contains(.mouseMoved) {
                moved.append(area)
            }
            if inside, area.options.contains(.cursorUpdate) || area._ownerCursor != nil { cursorOwned = true }
        }
        for area in exits {
            let e = NSEvent._enterExitEvent(type: .mouseExited, location: point, modifierFlags: flags, timestamp: time, windowNumber: _windowNumber, trackingArea: area)
            if let c = area._ownerCursor { c.mouseExited(with: e); continue }
            if area.options.contains(.mouseEnteredAndExited) { area._ownerResponder?.mouseExited(with: e) }
        }
        for area in entries {
            let e = NSEvent._enterExitEvent(type: .mouseEntered, location: point, modifierFlags: flags, timestamp: time, windowNumber: _windowNumber, trackingArea: area)
            if let c = area._ownerCursor { c.mouseEntered(with: e); continue }
            if area.options.contains(.mouseEnteredAndExited) { area._ownerResponder?.mouseEntered(with: e) }
            if area.options.contains(.cursorUpdate) {
                let u = NSEvent._enterExitEvent(type: .cursorUpdate, location: point, modifierFlags: flags, timestamp: time, windowNumber: _windowNumber, trackingArea: area)
                area._ownerResponder?.cursorUpdate(with: u)
            }
        }
        if let event { for area in moved { area._ownerResponder?.mouseMoved(with: event) } }
        let wasOwned = _cursorOwnedByTrackingArea
        _cursorOwnedByTrackingArea = cursorOwned
        // Leaving every cursor-updating area hands the cursor back to the cursor rects.
        if wasOwned, !cursorOwned, let location { _updateCursor(at: location) }
        return cursorOwned
    }

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
        c.hasDraggableBand = _toolbarView.map { !$0.isHidden } ?? false
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
        if let t = _toolbarView, !t.isHidden, let v = hit, v === t || v.isDescendant(of: t) { return .caption }
        if let a = _accessoryHost, !a.isHidden, let v = hit, v === a || v.isDescendant(of: a) { return .caption }
        if _isMovableByWindowBackground { return .caption }
        let chrome = _chrome
        if chrome.extendsContentIntoTitleBar, point.y >= content.bounds.height - NSWindow._titleBarBandHeight { return .caption }
        // The package-drawn title band above the content (its buttons were caught above).
        if _hasClientSideTitleBar, point.y >= content.bounds.height { return .caption }
        return .client
    }

    public func platformWindowTitleBarDoubleClicked() {
        guard _styleMask.contains(.resizable) else { return }
        performZoom(nil)
    }

    /// The title band of a window the platform does not decorate: a flat bar in the
    /// window's appearance with the title centred and the standard buttons at the left,
    /// as AppKit draws it (and over a transparent title bar, the window background).
    public func platformWindowDrawTitleBar(into context: CGContext, dirtyRect: NSRect) {
        guard _hasClientSideTitleBar, _styleMask.contains(.titled), !_styleMask.contains(.fullSizeContentView) else { return }
        let content = contentRect(forFrameRect: frame).size
        let band = NSRect(x: 0, y: content.height, width: frame.width, height: max(0, frame.height - content.height))
        guard band.height > 0, band.intersects(dirtyRect) else { return }
        context.saveGState()
        let previousAppearance = NSAppearance.current
        NSAppearance.current = effectiveAppearance
        let dark = effectiveAppearance.isDark
        let chrome = _chrome
        if chrome.transparentTitleBar {
            context.setFillColor(_backgroundColor.cgColor)
        } else if _isKey {
            context.setFillColor(dark ? CGColor(red: 0.23, green: 0.23, blue: 0.24, alpha: 1) : CGColor(red: 0.91, green: 0.91, blue: 0.91, alpha: 1))
        } else {
            context.setFillColor(dark ? CGColor(red: 0.18, green: 0.18, blue: 0.19, alpha: 1) : CGColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1))
        }
        context.fill(band)
        if !chrome.transparentTitleBar {
            context.setFillColor(dark ? CGColor(red: 0, green: 0, blue: 0, alpha: 0.5) : CGColor(red: 0, green: 0, blue: 0, alpha: 0.12))
            context.fill(NSRect(x: band.minX, y: band.minY, width: band.width, height: 1))
        }
        if !chrome.hidesTitle, !_title.isEmpty {
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let font = NSFont.titleBarFont(ofSize: 13)
            let color = _isKey ? NSColor.windowFrameTextColor : NSColor.secondaryLabelColor
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = _title.size(withAttributes: attributes)
            // Centred in the band, kept clear of the buttons on the left.
            let buttonsEnd = _NSWindowButtonsView.width + 8
            let x = max(buttonsEnd, band.midX - size.width / 2)
            let width = min(size.width, band.maxX - 8 - x)
            if width > 0 {
                context.saveGState()
                context.clip(to: NSRect(x: x, y: band.minY, width: width, height: band.height))
                _title.draw(at: NSPoint(x: x, y: band.midY - size.height / 2), withAttributes: attributes)
                context.restoreGState()
            }
            NSGraphicsContext.current = previous
        }
        if let a = _accessoryHost, !a.isHidden {
            a.layoutSubtreeIfNeeded()
            a._displayHierarchy(in: context, dirtyRect: dirtyRect)
        }
        if let buttons = _ensureWindowButtons() {
            buttons._displayHierarchy(in: context, dirtyRect: dirtyRect)
        }
        NSAppearance.current = previousAppearance
        NSGraphicsContext.current = nil
        context.restoreGState()
    }

    /// The draggable band at the top of windows whose content covers the title bar.
    internal static let _titleBarBandHeight: CGFloat = 28

    /// Called by views when a region in their coordinates needs repainting.
    internal func _viewNeedsDisplay(_ view: NSView, rect: NSRect) {
        let r = view.convert(rect, to: nil)
        _platform?.setNeedsDisplay(r)
    }

    /// Feeds the event to the gesture recognizers of the target view and its ancestors
    /// (AppKit routes to every recognizer up the hit view's chain). Returns true when a
    /// tracking recognizer asked for the view not to see this event.
    private func _routeToGestureRecognizers(_ event: NSEvent, target: NSResponder) -> Bool {
        var view: NSView? = target as? NSView
        var delayed = false
        while let v = view {
            for r in v.gestureRecognizers {
                let tracking = r.state == .began || r.state == .changed
                r._receive(event)
                if r._delays(event, tracking: tracking) { delayed = true }
            }
            view = v.superview
        }
        return delayed
    }

    private func _dispatchMouse(_ event: NSEvent, to target: NSResponder) {
        if _routeToGestureRecognizers(event, target: target) { return }
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
        case .magnify: target.magnify(with: event)
        case .rotate: target.rotate(with: event)
        case .swipe: target.swipe(with: event)
        case .smartMagnify: target.smartMagnify(with: event)
        case .beginGesture: target.beginGesture(with: event)
        case .endGesture: target.endGesture(with: event)
        case .pressure: target.pressureChange(with: event)
        default: break
        }
    }

    // MARK: PlatformWindowOwner

    public func platformWindowDidChangeFrame(_ frame: NSRect) {
        if NSView._traceInvalidation { NSView._trace("frame \'\(_title)\' \(frame)") }
        let old = _lastFrame
        _lastFrame = frame
        let cr = contentRect(forFrameRect: frame)
        // A sheet mid-slide keeps its full-size content pinned to the top (ADR-0019).
        if _sheetSlide == nil, let cv = _contentView, cv.frame.size != cr.size {
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
        if !_sheets.isEmpty { _layoutSheets() }
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
        if _isBlockedBySheet { Platform.backend.beep(); return false }    // the close button is disabled under a sheet
        let should = delegate?.windowShouldClose(self) ?? true
        if NSView._traceInvalidation { NSView._trace("shouldClose \'\(_title)\' -> \(should)") }
        guard should, let wc = _windowController, let doc = wc.document as? NSDocument else { return should }
        // The native close button on a document window: the document decides, and closes
        // the window itself when it may.
        doc._shouldCloseWindowController(wc) { [weak self] shouldClose in if shouldClose { self?.close() } }
        return false
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
        // Geometry settled for this frame: areas under a pointer that did not move still enter or exit.
        if _trackingAreasDirty { _contentView?.layoutSubtreeIfNeeded(); _evaluateTrackingAreas(at: _lastMouseLocation, event: nil, dragging: false) }
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
        if !_hostsLayersNatively, let t = _toolbarView, !t.isHidden {
            t.layoutSubtreeIfNeeded()
            t._displayHierarchy(in: context, dirtyRect: dirtyRect)
        }
        if !_hostsLayersNatively, let a = _accessoryHost, !a.isHidden {
            a.layoutSubtreeIfNeeded()
            a._displayHierarchy(in: context, dirtyRect: dirtyRect)
        }
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
    /// The end of the `cursorUpdate(with:)` chain: nothing above set a cursor, so the arrow shows.
    @MainActor open override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }
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
    @MainActor open func addTitlebarAccessoryViewController(_ childViewController: NSTitlebarAccessoryViewController) { _insertTitlebarAccessory(childViewController, at: _titlebarAccessories.count) }
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
    @MainActor open var attachedSheet: NSWindow? { _sheets.first { $0._sheetIsPresented } }

    // MARK: Sheets (ADR-0019)
    //
    // `_sheets` is the queue: the sheet presented now (attached to the platform window,
    // ordered in, key) and the ones waiting to be presented when it ends. A critical sheet
    // is inserted at the front and presented in front of the one already up.
    private var _sheets: [NSWindow] = []
    private var _sheetCompletions: [ObjectIdentifier: (NSApplication.ModalResponse) -> Void] = [:]
    private weak var _sheetParent: NSWindow?
    /// Presented (attached, ordered in) rather than waiting in the parent's queue.
    private var _sheetIsPresented = false
    /// The slide in or out running on this sheet.
    private var _sheetSlide: _NSSheetSlide? = nil
    /// Escape ends this sheet with `.cancel` when no key equivalent took it (SwiftUI's
    /// `.sheet`, as on macOS). Not part of Apple's API: SwiftUI sets it on its sheets.
    public var _cancelsSheetOnEscape = false
    /// How long the slide in takes (the slide out takes four fifths); 0 skips the
    /// animation. Off on the headless host backend (tests and the macOS host build), whose
    /// run loop nobody spins for frames; the slide test turns it on. Not part of Apple's API.
    public static var _sheetAnimationDuration: TimeInterval = Platform.backend is HostBackend ? 0 : 0.25
    /// The window is closed once its sheet session ends (after the slide out): for sheets
    /// the framework makes and nobody keeps (alert panels, SwiftUI sheets), so they do not
    /// linger hidden in the application's window list. Not part of Apple's API.
    public var _closesAfterSheetEnds = false

    /// A window with an attached sheet does not take input; the sheet does.
    private var _isBlockedBySheet: Bool { attachedSheet != nil }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/beginsheet(_:completionhandler:)
    @MainActor open func beginSheet(_ sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        _beginSheet(sheetWindow, critical: false, completionHandler: handler)
    }

    private func _beginSheet(_ sheet: NSWindow, critical: Bool, completionHandler handler: ((NSApplication.ModalResponse) -> Void)?) {
        guard sheet !== self, sheet._sheetParent == nil, !_sheets.contains(where: { $0 === sheet }) else { return }
        if NSView._traceInvalidation { NSView._trace("beginSheet '\(_title)' <- '\(sheet._title)'\(critical ? " critical" : "") queued \(_sheets.count)") }
        if let h = handler { _sheetCompletions[ObjectIdentifier(sheet)] = h }
        sheet._sheetParent = self
        sheet._sheetIsPresented = false
        if critical {
            _sheets.insert(sheet, at: 0)
            _presentSheet(sheet)
        } else {
            _sheets.append(sheet)
            if attachedSheet == nil { _presentSheet(sheet) }
        }
    }

    /// Attaches the sheet to the platform window, places it under the title band (or the
    /// toolbar), orders it front, makes it key and slides it in.
    private func _presentSheet(_ sheet: NSWindow) {
        post(NSWindow.willBeginSheetNotification)
        sheet._sheetIsPresented = true
        sheet._sheetSlide?.finish()
        sheet._reopenIfNeeded()
        sheet._attachAsSheet(to: self)
        let target = _sheetFrame(for: sheet)
        sheet._platformWindow?.frame = target
        let appearing = !sheet.isVisible
        if appearing { sheet._contentView?._windowVisibilityWillChange(true) }
        if sheet._sheetAnimates {
            let slide = _NSSheetSlide(sheet: sheet, target: target, direction: .in, duration: NSWindow._sheetAnimationDuration) { [weak sheet] in
                sheet?._sheetSlide = nil
            }
            sheet._sheetSlide = slide
            slide.start()
        }
        sheet._platformWindow?.show()
        sheet._platformWindow?.displayIfNeeded()
        if appearing { sheet._contentView?._windowVisibilityDidChange(true) }
        sheet.makeKey()
    }

    /// Whether the slide runs for this sheet: not when the window opts out of animation or
    /// the duration is zero.
    private var _sheetAnimates: Bool { _animationBehavior != .none && NSWindow._sheetAnimationDuration > 0 }

    /// Switches the platform window into (or out of) its attached, frameless form, keeping
    /// the content size: the frame/content conversion changes with the attachment.
    private func _attachAsSheet(to parent: NSWindow?) {
        guard let p = _platform else { return }
        let content = contentRect(forFrameRect: frame)
        p.attachSheet(to: parent?._platform)
        let adjusted = frameRect(forContentRect: content)
        if adjusted != frame { p.frame = adjusted }
    }

    /// Where the sheet goes: centred on the top of `contentLayoutRect` (under the title bar
    /// and the toolbar band), unless the delegate moves the attachment rect.
    private func _sheetFrame(for sheet: NSWindow) -> NSRect {
        let size = sheet.contentRect(forFrameRect: sheet.frame).size
        let layout = contentLayoutRect
        var rect = NSRect(x: ((layout.width - size.width) / 2).rounded(), y: layout.maxY, width: size.width, height: 0)
        if let d = delegate { rect = d.window(self, willPositionSheet: sheet, using: rect) }
        let origin = convertPoint(toScreen: rect.origin)
        let width = rect.width > 0 ? rect.width : size.width
        return NSRect(x: origin.x, y: origin.y - size.height, width: width, height: size.height)
    }

    /// The parent moved or resized: its presented sheets follow (Win32 and X11 do not move
    /// owned or transient windows with their owner).
    private func _layoutSheets() {
        for s in _sheets where s._sheetIsPresented && s._sheetSlide == nil {
            let f = _sheetFrame(for: s)
            if f != s.frame { s._platformWindow?.frame = f }
        }
    }

    /// A slide step: the frame grows down from the attachment line by `fraction` of the
    /// target height while the content stays pinned to the top.
    fileprivate func _applySheetSlide(fraction: CGFloat, target: NSRect) {
        guard let p = _platform else { return }
        let h = max(1, (target.height * min(max(fraction, 0), 1)).rounded())
        let partial = NSRect(x: target.minX, y: target.maxY - h, width: target.width, height: h)
        if let cv = _contentView {
            if cv.frame.size != target.size { cv.setFrameSize(target.size) }
            cv.setFrameOrigin(NSPoint(x: 0, y: h - target.height))
        }
        if p.frame != partial { p.frame = partial }
        p.setNeedsDisplay(nil)
    }

    /// Ends the sheet session on this sheet's parent with `.cancel` (a sheet closed or
    /// ordered out by other means than `endSheet`).
    private func _cancelSheetIfAttached() {
        if let p = _sheetParent { p.endSheet(self, returnCode: .cancel) }
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
        // A window with a sheet up hands the key status to the sheet (the window system
        // activated the parent: a click on its title bar, the taskbar).
        if let sheet = attachedSheet, sheet.isVisible {
            if !sheet._isKey { sheet._platformWindow?.makeKey(); sheet.becomeKey() }
            return
        }
        guard !_isKey else { return }
        if NSView._traceInvalidation { NSView._trace("becomeKey \'\(_title)\'") }
        let app = NSApplication.shared
        if let previous = app.keyWindow, previous !== self { previous.resignKey() }
        _isKey = true
        app._keyWindow = self
        // The first time the window is key, `initialFirstResponder` takes focus (macOS
        // does this when the window is first shown), so typing reaches the document's view.
        if firstResponder == nil || firstResponder === self, let initial = _initialFirstResponder, initial.window === self {
            makeFirstResponder(initial)
        }
        _toolbar?.validateVisibleItems()
        post(NSWindow.didBecomeKeyNotification)
        delegate?.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: self))
        _trackingActivityDidChange()
        // A window the window system activated (a click on it) is the main window too when
        // it can be one, as on macOS; a utility panel (the Fonts or Colors panel) cannot, so
        // the document window stays main and nil-target actions sent while the panel is
        // key still reach the document's first responder.
        if canBecomeMain, !_isMain { makeMain() }
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
    @MainActor open func beginCriticalSheet(_ sheetWindow: NSWindow) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { c in _beginSheet(sheetWindow, critical: true) { c.resume(returning: $0) } }
    }
    // DUPLICATE: @MainActor open func beginCriticalSheet(_ sheetWindow: NSWindow) async -> NSApplication.ModalResponse
    /// Begins a critical sheet with a completion handler: presented at once, in front of a
    /// sheet already up (the async form above wraps it). Not part of Apple's API.
    @MainActor public func _beginCriticalSheet(_ sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
        _beginSheet(sheetWindow, critical: true, completionHandler: handler)
    }
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
    @MainActor open var canBecomeKey: Bool { _styleMask.contains(.titled) || _styleMask.contains(.resizable) || _sheetParent != nil }
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
        // A sheet closed by other means ends its session; a window closing with sheets up
        // ends theirs (their completion handlers hear `.cancel`).
        _sheetSlide?.finish()
        _cancelSheetIfAttached()
        for s in _sheets { endSheet(s, returnCode: .cancel) }
        _isClosing = true
        post(NSWindow.willCloseNotification)
        delegate?.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: self))
        _windowController?._windowWillClose()
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
    /// The content's bounds less the toolbar band and the title bar accessories that
    /// overlay it on a window whose content covers the title bar.
    @MainActor open var contentLayoutRect: NSRect {
        guard var r = _contentView?.bounds else { return .zero }
        guard _styleMask.contains(.fullSizeContentView), _styleMask.contains(.titled) else { return r }
        if _toolbarMetrics != nil || !_visibleAccessories.isEmpty {
            r.size.height = max(0, min(r.height, _resolveTitlebarLayout().contentTop))
        }
        return r
    }
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
    /// The platform's content area less the toolbar band, when a toolbar is shown below
    /// the title bar: the band is part of the frame, as on macOS.
    @MainActor open func contentRect(forFrameRect frameRect: NSRect) -> NSRect {
        var r = _platform?.contentRect(forFrameRect: frameRect) ?? frameRect
        let band = _chromeBandHeight
        if band > 0 { r.size.height = max(0, r.height - band) }
        return r
    }
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
        if NSView._traceInvalidation { NSView._trace("endSheet '\(_title)' -> '\(sheetWindow._title)' code \(returnCode.rawValue)") }
        _sheets.remove(at: i)
        sheetWindow._sheetParent = nil
        let completion = _sheetCompletions.removeValue(forKey: ObjectIdentifier(sheetWindow))
        if sheetWindow._sheetIsPresented {
            sheetWindow._sheetIsPresented = false
            sheetWindow._sheetSlide?.finish()
            if sheetWindow._isKey { sheetWindow.resignKey() }
            if sheetWindow._sheetAnimates, sheetWindow.isVisible {
                let target = sheetWindow.frame
                let slide = _NSSheetSlide(sheet: sheetWindow, target: target, direction: .out, duration: NSWindow._sheetAnimationDuration * 0.8) { [weak sheetWindow] in
                    guard let s = sheetWindow else { return }
                    s._sheetSlide = nil
                    s.orderOut(nil)
                    s._applySheetSlide(fraction: 1, target: target)     // full size again, hidden
                    s._attachAsSheet(to: nil)
                    if s._closesAfterSheetEnds { s.close() }
                }
                sheetWindow._sheetSlide = slide
                slide.start()
            } else {
                sheetWindow.orderOut(nil)
                sheetWindow._attachAsSheet(to: nil)
                if sheetWindow._closesAfterSheetEnds { sheetWindow.close() }
            }
        } else if sheetWindow._closesAfterSheetEnds {
            sheetWindow.close()                         // ended while still queued
        }
        completion?(returnCode)
        post(NSWindow.didEndSheetNotification)
        // The next queued sheet comes up; otherwise the parent takes the keyboard back.
        if attachedSheet == nil, let next = _sheets.first {
            _presentSheet(next)
        } else if attachedSheet == nil, isVisible, !_isClosing {
            makeKey()
        } else if let s = attachedSheet, s.isVisible {
            s.makeKey()
        }
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
    @MainActor open func frameRect(forContentRect contentRect: NSRect) -> NSRect {
        var c = contentRect
        let band = _chromeBandHeight
        if band > 0 { c.size.height += band }
        return _platform?.frameRect(forContentRect: c) ?? c
    }
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
    @MainActor open func insertTitlebarAccessoryViewController(_ childViewController: NSTitlebarAccessoryViewController, at index: Int) { _insertTitlebarAccessory(childViewController, at: index) }
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
    /// The edited state shows as a dot in the close button of a package-drawn title bar
    /// (as macOS marks it) and as the platform's own mark in native title bars (an
    /// asterisk before the title on Windows and Linux).
    @MainActor open var isDocumentEdited: Bool {
        get { _isDocumentEdited }
        set {
            guard _isDocumentEdited != newValue else { return }
            _isDocumentEdited = newValue
            _platform?.setDocumentEdited(newValue)
            _ensureWindowButtons()
            _windowButtons?.close.isDocumentEdited = newValue
            if _hasClientSideTitleBar { _platform?.setNeedsDisplay(nil) }
        }
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
        _trackingActivityDidChange()
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
        if _sheetParent != nil { _cancelSheetIfAttached(); return }       // endSheet orders the sheet out
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
    /// The delegate's `windowShouldClose` first; then a window with a document asks the
    /// document (`shouldCloseWindowController`), whose unsaved-changes alert may cancel.
    @MainActor open func performClose(_ sender: Any?) {
        guard _styleMask.contains(.closable), !_isBlockedBySheet else { Platform.backend.beep(); return }
        guard delegate?.windowShouldClose(self) ?? true else { return }
        if let wc = _windowController, let doc = wc.document as? NSDocument {
            doc._shouldCloseWindowController(wc) { [weak self] shouldClose in if shouldClose { self?.close() } }
            return
        }
        close()
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
    /// File > Print… reaching the window: prints the content view (ADR-0022).
    @MainActor open func printWindow(_ sender: Any?) { _contentView?.printView(sender) }
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
    @MainActor open func removeTitlebarAccessoryViewController(at index: Int) {
        guard _titlebarAccessories.indices.contains(index) else { return }
        let vc = _titlebarAccessories.remove(at: index)
        vc._stopObservingViewFrame()
        vc.viewIfLoaded?.removeFromSuperview()
        vc._window = nil
        _toolbarGeometryDidChange()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/representedfilename
    @MainActor open var representedFilename: String {
        get { _representedURL?.path ?? "" }
        set { _representedURL = newValue.isEmpty ? nil : URL(fileURLWithPath: newValue) }
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
        if let p = _NSComboBoxPopUp.current, p.window !== self { p.dismiss() }
        let app = NSApplication.shared
        if app.keyWindow === self { app._keyWindow = nil }
        post(NSWindow.didResignKeyNotification)
        _trackingActivityDidChange()
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
    @MainActor open func runToolbarCustomizationPalette(_ sender: Any?) { _toolbar?.runCustomizationPalette(sender) }
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
    /// The event's location, or nil for the far-away location the backends send when
    /// the pointer leaves the window.
    private func _pointerLocation(of event: NSEvent) -> NSPoint? {
        let p = event.locationInWindow
        return p.x <= -50_000 || p.y <= -50_000 ? nil : p
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/sendevent(_:)
    @MainActor open func sendEvent(_ event: NSEvent) {
        _currentEvent = event
        defer { _currentEvent = nil }
        // Blocked by a sheet: the keyboard goes to the sheet (on Wayland the key events
        // arrive here, focus staying with the toplevel), the content takes no mouse.
        if let sheet = attachedSheet, sheet.isVisible {
            switch event.type {
            case .keyDown, .keyUp, .flagsChanged: sheet.sendEvent(event)
            case .mouseMoved: _updateCursor(at: event.locationInWindow)
            default: break
            }
            return
        }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard !_ignoresMouseEvents else { return }
            _lastMouseLocation = event.locationInWindow
            let hit = _hitTest(event.locationInWindow)
            if NSView._traceInvalidation { NSView._trace("mouse down '\(_title)' at \(event.locationInWindow) -> \(hit.map { String(describing: type(of: $0)) } ?? "window") accessory host \(_accessoryHost.map { "\($0.frame) hidden \($0.isHidden) bands \($0.paintedBands)" } ?? "none")") }
            _mouseDownView = hit
            if let v = hit, v._takesFirstResponderOnMouseDown, firstResponder !== v { _ = makeFirstResponder(v) }
            _dispatchMouse(event, to: hit ?? self)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            _lastMouseLocation = _pointerLocation(of: event)
            _evaluateTrackingAreas(at: _lastMouseLocation, event: event, dragging: true)
            _dispatchMouse(event, to: _mouseDownView ?? _hitTest(event.locationInWindow) ?? self)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let target: NSResponder = _mouseDownView ?? _hitTest(event.locationInWindow) ?? self
            _mouseDownView = nil
            _dispatchMouse(event, to: target)
            // The drag is over: areas that stood still during it catch up with the pointer.
            _lastMouseLocation = _pointerLocation(of: event)
            _evaluateTrackingAreas(at: _lastMouseLocation, event: nil, dragging: false)
        case .mouseMoved:
            _lastMouseLocation = _pointerLocation(of: event)
            let cursorOwned = _evaluateTrackingAreas(at: _lastMouseLocation, event: event, dragging: false)
            if !cursorOwned { _updateCursor(at: event.locationInWindow) }
            _windowButtons?.updateHover(event.locationInWindow)
            guard _acceptsMouseMovedEvents else { return }
            _dispatchMouse(event, to: _hitTest(event.locationInWindow) ?? self)
        case .scrollWheel, .mouseEntered, .mouseExited:
            _dispatchMouse(event, to: _hitTest(event.locationInWindow) ?? self)
        case .magnify, .rotate, .swipe, .smartMagnify, .beginGesture, .endGesture, .pressure:
            // Gestures go to the view under the pointer, or to the one tracking a press.
            let target = _mouseDownView ?? _hitTest(event.locationInWindow) ?? self
            if NSView._traceInvalidation {
                var chain: [String] = []
                var v = target as? NSView
                while let view = v { if !view.gestureRecognizers.isEmpty { chain.append("\(type(of: view))×\(view.gestureRecognizers.count)") }; v = view.superview }
                NSView._trace("gesture \(event.type) '\(_title)' at \(event.locationInWindow) -> \(type(of: target)) magnification \(event.magnification) recognizers [\(chain.joined(separator: ", "))]")
            }
            _dispatchMouse(event, to: target)
        case .keyDown:
            // An editing text field commits on Return before the default button sees it.
            if let editor = firstResponder as? NSTextView, editor._consumesReturnKey, event.charactersIgnoringModifiers == "\r",
               event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                editor.keyDown(with: event)
                _ = _contentView?.performKeyEquivalent(with: event)
                return
            }
            if !(_contentView?.performKeyEquivalent(with: event) ?? false) {
                // Escape ends a sheet that opted in (SwiftUI's), when no Cancel button took it.
                if _sheetParent != nil, _cancelsSheetOnEscape, event.charactersIgnoringModifiers == "\u{1B}",
                   event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                    _cancelSheetIfAttached()
                    return
                }
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
    @MainActor open func setTitleWithRepresentedFilename(_ filename: String) {
        representedFilename = filename
        title = (filename as NSString).lastPathComponent
    }
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
        set { _styleMask = newValue; _platform?.styleMask = newValue; _updateChrome(); _toolbarGeometryDidChange() }
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
        get { _titlebarAccessories }
        set {
            while !_titlebarAccessories.isEmpty { removeTitlebarAccessoryViewController(at: _titlebarAccessories.count - 1) }
            for vc in newValue { addTitlebarAccessoryViewController(vc) }
        }
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
    @MainActor open func toggleToolbarShown(_ sender: Any?) { _toolbar?.isVisible.toggle() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/toolbar
    @MainActor open var toolbar: NSToolbar? {
        get { _toolbar }
        set { _setToolbar(newValue) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/toolbarstyle
    @available(macOS 11.0, *)
    @MainActor open var toolbarStyle: NSWindow.ToolbarStyle {
        get { _toolbarStyle }
        set { guard _toolbarStyle != newValue else { return }; _toolbarStyle = newValue; _toolbarGeometryDidChange() }
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
    /// The controller is the window's next responder, so actions and the undo manager
    /// reach it and its document.
    @MainActor open var windowController: NSWindowController? {
        get { _windowController }
        set {
            _windowController = newValue
            nextResponder = newValue
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nswindow/undomanager
    /// The delegate's (`windowWillReturnUndoManager`), else the window controller's (a
    /// document's), else one of the window's own.
    private var _ownUndoManager: UndoManager? = nil
    @MainActor open override var undoManager: UndoManager? {
        if let d = delegate, let m = d.windowWillReturnUndoManager(self) { return m }
        if let wc = _windowController, let m = wc.undoManager { return m }
        if _ownUndoManager == nil { _ownUndoManager = UndoManager() }
        return _ownUndoManager
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
    @MainActor open var windowTitlebarLayoutDirection: NSUserInterfaceLayoutDirection { _contentView?.userInterfaceLayoutDirection ?? NSApplication._resolvedLayoutDirection }
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
        var children: [Any] = (cv.isAccessibilityElement() ? [cv] : cv.accessibilityChildren()) ?? []
        if let t = _toolbarView, !t.isHidden { children.append(t) }
        if let a = _accessoryHost, !a.isHidden { children.append(contentsOf: a.accessibilityChildren() ?? []) }
        return children
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
    @MainActor internal func _accessibilityView(withID id: Int) -> NSView? {
        _contentView?._accessibilityView(withID: id) ?? _toolbarView?._accessibilityView(withID: id) ?? _accessoryHost?._accessibilityView(withID: id)
    }

    public func accessibilityPerform(_ action: PlatformAccessibilityAction, on elementID: Int) -> Bool {
        if elementID == _accessibilityElementID { return action == .raise ? accessibilityPerformRaise() : false }
        guard let v = _accessibilityView(withID: elementID) else {
            return _contentView?._accessibilityVirtualElement(withID: elementID)?._accessibilityPerform(action) ?? false
        }
        switch action {
        case .press: return v.accessibilityPerformPress() || v._accessibilityPressThroughContainer()
        case .increment: return v.accessibilityPerformIncrement()
        case .decrement: return v.accessibilityPerformDecrement()
        case .showMenu: return v.accessibilityPerformShowMenu()
        case .confirm: return v.accessibilityPerformConfirm()
        case .cancel: return v.accessibilityPerformCancel()
        case .pick: return v.accessibilityPerformPick()
        case .raise: return v.accessibilityPerformRaise()
        case .expand, .collapse:
            guard v._accessibilityExpandedState() != nil else { return false }
            v.setAccessibilityExpanded(action == .expand)
            return true
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
        return v._accessibilitySetSelected(selected, extending: extending)
    }
}

// MARK: - Sheet slide (ADR-0019)

/// Slides a sheet out from under its parent's title band and back: the sheet's frame grows
/// downwards from the attachment line to its full height (or shrinks back) with the content
/// pinned to the top, one step per frame of a `CADisplayLink` on Core Animation's clock
/// (`CARuntime.now`, so tests drive it with a fake clock and `CARuntime.tick()`).
@MainActor final class _NSSheetSlide {
    enum Direction { case `in`, out }
    private let sheet: NSWindow
    private let target: NSRect
    private let direction: Direction
    private let duration: TimeInterval
    private let completion: () -> Void
    private var startTime: CFTimeInterval = 0
    private var link: CADisplayLink?
    private var finished = false

    init(sheet: NSWindow, target: NSRect, direction: Direction, duration: TimeInterval, completion: @escaping () -> Void) {
        self.sheet = sheet
        self.target = target
        self.direction = direction
        self.duration = duration
        self.completion = completion
    }

    /// Applies the first step and schedules the rest.
    func start() {
        guard duration > 0 else { finish(); return }
        startTime = CARuntime.now()
        apply(0)
        let l = CADisplayLink { [weak self] _ in self?.step() }
        link = l
        l.add(to: .main, forMode: .default)
    }

    private func step() {
        let t = min(1, max(0, (CARuntime.now() - startTime) / duration))
        // Ease out: fast off the line, settling at the end.
        let eased = 1 - (1 - t) * (1 - t)
        apply(eased)
        if t >= 1 { finish() }
    }

    private func apply(_ progress: Double) {
        let visible = direction == .in ? progress : 1 - progress
        sheet._applySheetSlide(fraction: CGFloat(visible), target: target)
    }

    /// Jumps to the end state and runs the completion (once).
    func finish() {
        guard !finished else { return }
        finished = true
        link?.invalidate()
        link = nil
        apply(1)
        completion()
    }
}
