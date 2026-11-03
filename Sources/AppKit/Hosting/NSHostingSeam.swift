// The SwiftUI hosting seam (Milestone 6).
//
// On macOS, SwiftUI's NSHostingView/NSHostingController live in the SwiftUI module and
// talk to AppKit through private hooks. Here the hooks are public: a SwiftUI
// implementation for this AppKit conforms its root content to `NSHostingContent` and
// provides an `NSHostingRoot` that attaches to the host view, measures, lays out,
// draws (through layers or the host's graphics context) and handles events. AppKit
// supplies everything the root needs through `NSHostingRootHost`.

import Foundation
#if canImport(QuartzCore)
import QuartzCore
#endif

/// A size proposal: nil components are unconstrained (SwiftUI's `ProposedViewSize`).
public struct NSHostingSizeProposal: Equatable, Sendable {
    public var width: CGFloat?
    public var height: CGFloat?
    public init(width: CGFloat? = nil, height: CGFloat? = nil) {
        self.width = width
        self.height = height
    }
    public init(_ size: NSSize) {
        width = size.width
        height = size.height
    }
    public static let unspecified = NSHostingSizeProposal()
    public static let zero = NSHostingSizeProposal(width: 0, height: 0)
}

/// Environment the host passes down: what SwiftUI's `EnvironmentValues` derives from AppKit.
public struct NSHostingEnvironment: Sendable {
    public var displayScale: CGFloat = 1
    public var layoutDirection: NSUserInterfaceLayoutDirection = .leftToRight
    public var isDarkAppearance = false
    public var isKeyWindow = false
    public var controlActiveState: ControlActiveState = .inactive
    public var locale = Locale.current
    public var dynamicTypeScale: CGFloat = 1

    public enum ControlActiveState: Sendable { case key, active, inactive }
    public init() {}
}

/// What AppKit offers a hosted root: invalidation, the host view, the window, layers
/// and a frame clock.
@MainActor
public protocol NSHostingRootHost: AnyObject {
    var hostView: NSView { get }
    var hostWindow: NSWindow? { get }
    /// The layer the root may add sublayers to (the host view's backing layer).
    var hostLayer: CALayer { get }
    var environment: NSHostingEnvironment { get }
    func setNeedsLayout()
    func setNeedsDisplay(in rect: NSRect?)
    func invalidateIntrinsicContentSize()
    func makeDisplayLink(_ callback: @escaping (CADisplayLink) -> Void) -> CADisplayLink
    /// Asks the host to adopt a size (windows sized to content, `preferredContentSize`).
    func rootDidChangeIdealSize(_ size: NSSize)
}

/// A hosted content tree, driven by its host.
@MainActor
public protocol NSHostingRoot: AnyObject {
    /// Called once with the host; the root may add subviews to `host.hostView` or
    /// sublayers to `host.hostLayer`.
    func attach(to host: any NSHostingRootHost)
    func detach()
    /// The content changed (a new value of the content was set).
    func contentDidChange()
    /// The environment (appearance, scale, key state, ...) changed.
    func environmentDidChange(_ environment: NSHostingEnvironment)
    /// Measures the content for a proposal.
    func sizeThatFits(_ proposal: NSHostingSizeProposal) -> NSSize
    /// Places the content in `bounds` (host view coordinates, flipped: y down).
    func layout(in bounds: NSRect)
    /// Draws immediate-mode content; layer- or view-based roots can leave it empty.
    func draw(_ dirtyRect: NSRect, in context: NSGraphicsContext)
    /// Returns true when the root consumed the event.
    func handle(_ event: NSEvent) -> Bool
    /// The hit-tested responder for a point (host view coordinates), if the root manages its own.
    func responder(at point: NSPoint) -> NSResponder?
}

extension NSHostingRoot {
    public func environmentDidChange(_ environment: NSHostingEnvironment) {}
    public func draw(_ dirtyRect: NSRect, in context: NSGraphicsContext) {}
    public func handle(_ event: NSEvent) -> Bool { false }
    public func responder(at point: NSPoint) -> NSResponder? { nil }
}

/// Content that can be hosted: SwiftUI's `View` refines this in the port.
public protocol NSHostingContent {
    /// Creates the root for this content. The host calls `contentDidChange()` on the
    /// root whenever a new content value replaces the previous one.
    @MainActor func _makeHostingRoot() -> any NSHostingRoot
    /// Hands the root the new content value before `contentDidChange()`.
    @MainActor func _updateHostingRoot(_ root: any NSHostingRoot)
}

extension NSHostingContent {
    @MainActor public func _updateHostingRoot(_ root: any NSHostingRoot) {}
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/nshostingsizingoptions
public struct NSHostingSizingOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let minSize = NSHostingSizingOptions(rawValue: 1 << 0)
    public static let intrinsicContentSize = NSHostingSizingOptions(rawValue: 1 << 1)
    public static let maxSize = NSHostingSizingOptions(rawValue: 1 << 2)
    public static let preferredContentSize = NSHostingSizingOptions(rawValue: 1 << 3)
    public static let standardBounds: NSHostingSizingOptions = [.minSize, .intrinsicContentSize, .maxSize]
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/nshostingview
@MainActor open class NSHostingView<Content: NSHostingContent>: NSView, NSHostingRootHost {
    private var _rootView: Content
    private var _root: (any NSHostingRoot)?
    private var _sizingOptions: NSHostingSizingOptions = .standardBounds
    private var _environment = NSHostingEnvironment()
    private var _keyObservers: [NSObjectProtocol] = []

    public init(rootView: Content) {
        _rootView = rootView
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
        wantsLayer = true
        _attachRoot()
    }

    public required init?(coder: NSCoder) { return nil }

    open override var isFlipped: Bool { true }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/nshostingview/rootview
    open var rootView: Content {
        get { _rootView }
        set {
            _rootView = newValue
            guard let r = _root else { return }
            newValue._updateHostingRoot(r)
            r.contentDidChange()
            invalidateIntrinsicContentSize()
            needsLayout = true
            needsDisplay = true
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/nshostingview/sizingoptions
    open var sizingOptions: NSHostingSizingOptions {
        get { _sizingOptions }
        set { _sizingOptions = newValue; invalidateIntrinsicContentSize() }
    }

    /// The root the content produced (for tests and the SwiftUI port's tooling).
    public var hostingRoot: (any NSHostingRoot)? { _root }

    private func _attachRoot() {
        let r = _rootView._makeHostingRoot()
        _root = r
        _rootView._updateHostingRoot(r)
        r.attach(to: self)
        _refreshEnvironment()
    }

    private func _refreshEnvironment() {
        if NSView._traceInvalidation { NSView._trace("hosting refreshEnvironment") }
        var env = NSHostingEnvironment()
        env.displayScale = window?.backingScaleFactor ?? 1
        env.layoutDirection = userInterfaceLayoutDirection
        env.isKeyWindow = window?.isKeyWindow ?? false
        env.controlActiveState = env.isKeyWindow ? .key : (window != nil ? .active : .inactive)
        env.isDarkAppearance = false
        _environment = env
        _root?.environmentDidChange(env)
    }

    // MARK: Sizing

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/nshostingview/sizethatfits(_:)
    open func sizeThatFits(_ proposal: NSHostingSizeProposal) -> NSSize {
        _root?.sizeThatFits(proposal) ?? .zero
    }

    open override var intrinsicContentSize: NSSize {
        guard _sizingOptions.contains(.intrinsicContentSize) else { return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
        return sizeThatFits(.unspecified)
    }

    open override var fittingSize: NSSize { sizeThatFits(.unspecified) }

    open override func layout() {
        super.layout()
        _root?.layout(in: bounds)
    }

    open override func draw(_ dirtyRect: NSRect) {
        if let gc = NSGraphicsContext.current { _root?.draw(dirtyRect, in: gc) }
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for o in _keyObservers { NotificationCenter.default.removeObserver(o) }
        _keyObservers = []
        if let w = window {
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                _keyObservers.append(NotificationCenter.default.addObserver(forName: name, object: w, queue: nil) { [weak self] _ in
                    MainActor.assumeIsolated { self?._refreshEnvironment() }
                })
            }
        }
        _refreshEnvironment()
        needsLayout = true
    }

    open override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        _refreshEnvironment()
    }

    // MARK: Events

    open override var acceptsFirstResponder: Bool { true }

    private func _forward(_ event: NSEvent, _ fallback: () -> Void) {
        if _root?.handle(event) == true { return }
        fallback()
    }

    open override func mouseDown(with event: NSEvent) { _forward(event) { super.mouseDown(with: event) } }
    open override func mouseDragged(with event: NSEvent) { _forward(event) { super.mouseDragged(with: event) } }
    open override func mouseUp(with event: NSEvent) { _forward(event) { super.mouseUp(with: event) } }
    open override func mouseMoved(with event: NSEvent) { _forward(event) { super.mouseMoved(with: event) } }
    open override func rightMouseDown(with event: NSEvent) { _forward(event) { super.rightMouseDown(with: event) } }
    open override func scrollWheel(with event: NSEvent) { _forward(event) { super.scrollWheel(with: event) } }
    open override func keyDown(with event: NSEvent) { _forward(event) { super.keyDown(with: event) } }
    open override func keyUp(with event: NSEvent) { _forward(event) { super.keyUp(with: event) } }
    open override func flagsChanged(with event: NSEvent) { _forward(event) { super.flagsChanged(with: event) } }

    open override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        if let r = _root?.responder(at: local) as? NSView { return r }
        return super.hitTest(point)
    }

    // MARK: NSHostingRootHost

    public var hostView: NSView { self }
    public var hostWindow: NSWindow? { window }
    public var hostLayer: CALayer { layer! }
    public var environment: NSHostingEnvironment { _environment }
    public func setNeedsLayout() { needsLayout = true }
    public func setNeedsDisplay(in rect: NSRect?) { if let r = rect { setNeedsDisplay(r) } else { needsDisplay = true } }
    public func makeDisplayLink(_ callback: @escaping (CADisplayLink) -> Void) -> CADisplayLink {
        _CoreAnimationHost.installIfNeeded()
        return CADisplayLink(callback: callback)
    }
    public func rootDidChangeIdealSize(_ size: NSSize) {
        if NSView._traceInvalidation { NSView._trace("rootDidChangeIdealSize \(size)") }
        invalidateIntrinsicContentSize()
        _viewController?.preferredContentSize = size
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/nshostingcontroller
@MainActor open class NSHostingController<Content: NSHostingContent>: NSViewController {
    private var _rootView: Content
    private var _sizingOptions: NSHostingSizingOptions = []

    public init(rootView: Content) {
        _rootView = rootView
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) { return nil }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/nshostingcontroller/rootview
    open var rootView: Content {
        get { _rootView }
        set {
            _rootView = newValue
            if isViewLoaded { hostingView.rootView = newValue }
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/nshostingcontroller/sizingoptions
    open var sizingOptions: NSHostingSizingOptions {
        get { _sizingOptions }
        set { _sizingOptions = newValue; if isViewLoaded { hostingView.sizingOptions = newValue.union(.intrinsicContentSize) } }
    }

    /// The hosting view (loads the view).
    public var hostingView: NSHostingView<Content> { view as! NSHostingView<Content> }

    open override func loadView() {
        let v = NSHostingView(rootView: _rootView)
        let size = v.sizeThatFits(.unspecified)
        v.frame = NSRect(x: 0, y: 0, width: max(size.width, 1), height: max(size.height, 1))
        view = v
        if _sizingOptions.contains(.preferredContentSize) { preferredContentSize = size }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/nshostingcontroller/sizethatfits(in:)
    open func sizeThatFits(in size: NSSize) -> NSSize {
        hostingView.sizeThatFits(NSHostingSizeProposal(size))
    }
}
