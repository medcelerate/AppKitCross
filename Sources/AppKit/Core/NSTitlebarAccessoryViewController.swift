// NSTitlebarAccessoryViewController (hand-written; seeded from the generated stub, see tools/apigen)
// A view controller whose view the window places in its title bar: beside the standard
// buttons and the title for the leading, trailing, left and right attributes, or in a
// band of its own under the title bar and the toolbar for `.bottom`. The window owns the
// placement (NSWindow._resolveTitlebarLayout, ADR-0022); the controller holds the
// attribute, the visibility and the size policy.
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstitlebaraccessoryviewcontroller
@available(macOS 10.10, *)
@MainActor open class NSTitlebarAccessoryViewController: NSViewController, NSAnimationDelegate, NSAnimatablePropertyContainer {
    // MARK: Storage
    private var _layoutAttribute: NSLayoutConstraint.Attribute = .bottom
    private var _fullScreenMinHeight: CGFloat = 0
    private var _isHidden = false
    private var _automaticallyAdjustsSize = true
    /// The window showing this accessory (NSWindow.swift).
    internal weak var _window: NSWindow?
    private var _frameObserver: (any NSObjectProtocol)?

    /// The size the window lays the view out with: the view's fitting size when
    /// `automaticallyAdjustsSize` and it has one, else the view's frame.
    internal var _measuredSize: NSSize {
        let v = view
        var size = v.frame.size
        if _automaticallyAdjustsSize {
            let fitting = v.fittingSize
            if fitting.width > 0 { size.width = fitting.width }
            if fitting.height > 0 { size.height = fitting.height }
        }
        return NSSize(width: max(0, size.width), height: max(0, size.height))
    }

    /// The window follows the view's frame changes (an accessory that resizes itself).
    internal func _observeViewFrame() {
        _stopObservingViewFrame()
        _frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?._window?._accessoryGeometryDidChange() }
        }
    }
    internal func _stopObservingViewFrame() {
        if let o = _frameObserver { NotificationCenter.default.removeObserver(o); _frameObserver = nil }
    }

    /// A new view replaces the old one in the window's host.
    open override var view: NSView {
        get { super.view }
        set {
            let old = viewIfLoaded
            super.view = newValue
            guard let w = _window, old !== newValue else { return }
            old?.removeFromSuperview()
            newValue.postsFrameChangedNotifications = true
            _observeViewFrame()
            w._accessoryGeometryDidChange()
        }
    }

    /// Takes the accessory out of its window.
    open override func removeFromParent() {
        if let w = _window, let i = w.titlebarAccessoryViewControllers.firstIndex(where: { $0 === self }) {
            w.removeTitlebarAccessoryViewController(at: i)
        } else {
            super.removeFromParent()
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstitlebaraccessoryviewcontroller/automaticallyadjustssize
    @available(macOS 11.0, *)
    @MainActor open var automaticallyAdjustsSize: Bool {
        get { _automaticallyAdjustsSize }
        set { guard _automaticallyAdjustsSize != newValue else { return }; _automaticallyAdjustsSize = newValue; _window?._accessoryGeometryDidChange() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstitlebaraccessoryviewcontroller/fullscreenminheight
    @MainActor open var fullScreenMinHeight: CGFloat {
        get { _fullScreenMinHeight }
        set { _fullScreenMinHeight = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstitlebaraccessoryviewcontroller/ishidden
    @available(macOS 10.12, *)
    @MainActor open var isHidden: Bool {
        get { _isHidden }
        set { guard _isHidden != newValue else { return }; _isHidden = newValue; _window?._accessoryGeometryDidChange() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstitlebaraccessoryviewcontroller/layoutattribute
    /// `.leading`, `.trailing`, `.left`, `.right` and `.bottom` are honoured; anything else
    /// is placed as `.leading`.
    @MainActor open var layoutAttribute: NSLayoutConstraint.Attribute {
        get { _layoutAttribute }
        set { guard _layoutAttribute != newValue else { return }; _layoutAttribute = newValue; _window?._accessoryGeometryDidChange() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstitlebaraccessoryviewcontroller/preferredscrolledgeeffectstyle
    @available(macOS 26.1, *)
    @MainActor open var preferredScrollEdgeEffectStyle: NSScrollEdgeEffectStyle {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstitlebaraccessoryviewcontroller/viewdidappear()
    @MainActor open override func viewDidAppear() { super.viewDidAppear() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstitlebaraccessoryviewcontroller/viewdiddisappear()
    @MainActor open override func viewDidDisappear() { super.viewDidDisappear() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstitlebaraccessoryviewcontroller/viewwillappear()
    @MainActor open override func viewWillAppear() { super.viewWillAppear() }
    // SKIPPED (Foundation.NSExtensionContext not in corelibs): func beginRequest(with context: NSExtensionContext)
}

// MARK: Host view

/// The overlay root a window keeps its accessory views in. It spans the platform's
/// content area (and the client-side title band above it); only its subviews and the
/// bands it paints take hits, so the content underneath keeps the pointer elsewhere.
@MainActor
final class _NSTitlebarAccessoryHostView: NSView {
    /// Bands the host fills in the title-bar colour: the strip under a server-side title
    /// bar and the bottom accessories' bands when they come out of the frame.
    var paintedBands: [NSRect] = [] { didSet { if paintedBands != oldValue { needsDisplay = true } } }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
        wantsLayer = true
    }
    required init?(coder: NSCoder) { nil }

    override var mouseDownCanMoveWindow: Bool { true }      // the gaps drag the window
    override var acceptsFirstResponder: Bool { false }
    override func isAccessibilityElement() -> Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard hit === self else { return hit }
        let local = convert(point, from: superview)
        return paintedBands.contains { $0.contains(local) } ? self : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !paintedBands.isEmpty else { return }
        let dark = effectiveAppearance.isDark
        let key = window?.isKeyWindow ?? true
        let fill: NSColor
        if key { fill = dark ? NSColor(white: 0.23, alpha: 1) : NSColor(white: 0.91, alpha: 1) }
        else { fill = dark ? NSColor(white: 0.18, alpha: 1) : NSColor(white: 0.96, alpha: 1) }
        for band in paintedBands where band.intersects(dirtyRect) {
            fill.setFill()
            NSBezierPath.fill(band)
            // A hairline under each band, as under the toolbar's.
            (dark ? NSColor(white: 0, alpha: 0.5) : NSColor(white: 0, alpha: 0.12)).setFill()
            NSBezierPath.fill(NSRect(x: band.minX, y: band.minY, width: band.width, height: 1))
        }
    }
}
