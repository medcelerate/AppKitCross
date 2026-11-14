// NSClipView (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsclipview
@MainActor open class NSClipView: NSView {
    // MARK: Storage
    private var _documentView: NSView?
    private var _backgroundColor: NSColor = .controlBackgroundColor
    private var _drawsBackground = true
    private var _copiesOnScroll = true
    private var _documentCursor: NSCursor? = nil
    private var _contentInsets = NSEdgeInsets()
    private var _automaticallyAdjustsContentInsets = true
    private var _frameObserver: Any? = nil

    /// A clip view always clips: under layer backing that is the layer's masksToBounds.
    @MainActor public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        MainActor.assumeIsolated { clipsToBounds = true }
    }

    @MainActor open override var isFlipped: Bool { _documentView?.isFlipped ?? false }
    @MainActor open override var isOpaque: Bool { _drawsBackground }

    @MainActor open override func draw(_ dirtyRect: NSRect) {
        guard _drawsBackground else { return }
        _backgroundColor.setFill()
        NSBezierPath.fill(dirtyRect)
    }

    @MainActor open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        _reconstrain()
    }

    /// Keeps the visible rect inside the document after the clip or document changed size.
    @MainActor private func _reconstrain() {
        let o = constrainScroll(bounds.origin)
        if o != bounds.origin { setBoundsOrigin(o) }
        (superview as? NSScrollView)?.reflectScrolledClipView(self)
    }

    @MainActor private func _observeDocument() {
        if let t = _frameObserver { NotificationCenter.default.removeObserver(t); _frameObserver = nil }
        guard let doc = _documentView else { return }
        doc.postsFrameChangedNotifications = true
        _frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: doc, queue: nil) { [weak self] n in
            MainActor.assumeIsolated { self?.viewFrameChanged(n) }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsclipview/automaticallyadjustscontentinsets
    @available(macOS 10.10, *)
    @MainActor open var automaticallyAdjustsContentInsets: Bool {
        get { _automaticallyAdjustsContentInsets }
        set { _automaticallyAdjustsContentInsets = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsclipview/autoscroll(with:)
    /// Scrolls towards an event outside the visible bounds by the overshoot (a drag past
    /// the edge), true if it moved.
    @MainActor open override func autoscroll(with event: NSEvent) -> Bool {
        guard event.window == nil || event.window === window else { return false }
        let p = convert(event.locationInWindow, from: nil)
        let b = bounds
        var o = b.origin
        if p.x < b.minX { o.x -= b.minX - p.x } else if p.x > b.maxX { o.x += p.x - b.maxX }
        if p.y < b.minY { o.y -= b.minY - p.y } else if p.y > b.maxY { o.y += p.y - b.maxY }
        let c = constrainScroll(o)
        guard c != b.origin else { return false }
        scroll(to: c)
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsclipview/backgroundcolor
    @MainActor open var backgroundColor: NSColor {
        get { _backgroundColor }
        set { _backgroundColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsclipview/constrainboundsrect(_:)
    @MainActor open func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        let doc = documentRect
        var r = proposedBounds
        if doc.width <= r.width { r.origin.x = doc.minX } else { r.origin.x = min(max(r.minX, doc.minX), doc.maxX - r.width) }
        if doc.height <= r.height {
            // A short document sits at its origin: the top for flipped documents, the bottom otherwise.
            r.origin.y = isFlipped ? doc.minY : doc.maxY - r.height
        } else {
            r.origin.y = min(max(r.minY, doc.minY), doc.maxY - r.height)
        }
        return r
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsclipview/constrainscroll(_:)
    @MainActor open func constrainScroll(_ newOrigin: NSPoint) -> NSPoint { constrainBoundsRect(NSRect(origin: newOrigin, size: bounds.size)).origin }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsclipview/contentinsets
    @available(macOS 10.10, *)
    @MainActor open var contentInsets: NSEdgeInsets {
        get { _contentInsets }
        set { _contentInsets = newValue; _reconstrain() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsclipview/copiesonscroll
    @MainActor open var copiesOnScroll: Bool {
        get { _copiesOnScroll }
        set { _copiesOnScroll = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsclipview/documentcursor
    @MainActor open var documentCursor: NSCursor? {
        get { _documentCursor }
        set { _documentCursor = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsclipview/documentrect
    @MainActor open var documentRect: NSRect { _documentView?.frame ?? NSRect(origin: .zero, size: bounds.size) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsclipview/documentview
    @MainActor open var documentView: NSView? {
        get { _documentView }
        set {
            if let old = _documentView { old.removeFromSuperview() }
            _documentView = newValue
            if let doc = newValue {
                addSubview(doc)
                _observeDocument()
            } else {
                _observeDocument()
            }
            _reconstrain()
            needsDisplay = true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsclipview/documentvisiblerect
    @MainActor open var documentVisibleRect: NSRect { _documentView.map { convert(bounds, to: $0) } ?? bounds }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsclipview/drawsbackground
    @MainActor open var drawsBackground: Bool {
        get { _drawsBackground }
        set { _drawsBackground = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsclipview/scroll(to:)
    @MainActor open func scroll(to newOrigin: NSPoint) {
        let o = constrainScroll(newOrigin)
        guard o != bounds.origin else { return }
        setBoundsOrigin(o)
        (superview as? NSScrollView)?.reflectScrolledClipView(self)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsclipview/viewboundschanged(_:)
    @MainActor open func viewBoundsChanged(_ notification: Notification) { _reconstrain() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsclipview/viewframechanged(_:)
    @MainActor open func viewFrameChanged(_ notification: Notification) { _reconstrain(); needsDisplay = true }
}
