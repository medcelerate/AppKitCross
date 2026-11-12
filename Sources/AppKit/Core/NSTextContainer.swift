// NSTextContainer (hand-written; seeded from the generated stub, see tools/apigen)
// A rectangular region a layout manager fills with line fragments.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer
open class NSTextContainer: NSObject, NSSecureCoding, NSCoding, NSTextLayoutOrientationProvider {
    private var _size: CGSize
    private var _lineFragmentPadding: CGFloat = 5
    private var _widthTracksTextView = false
    private var _heightTracksTextView = false
    private var _maximumNumberOfLines = 0
    private var _lineBreakMode: NSLineBreakMode = .byWordWrapping
    private var _exclusionPaths: [NSBezierPath] = []
    internal weak var _layoutManager: NSLayoutManager?
    internal weak var _textView: NSTextView?

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/init(size:)
    @available(macOS 10.11, *)
    public init(size: CGSize) {
        _size = size
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/init(containersize:)
    public convenience init(containerSize aContainerSize: NSSize) { self.init(size: aContainerSize) }
    public convenience override init() { self.init(size: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/init(coder:)
    public required init(coder: NSCoder) { _size = .zero; super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/encode(with:)
    open func encode(with coder: NSCoder) {}
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/supportssecurecoding
    class public var supportsSecureCoding: Bool { true }

    private func _geometryChanged() { _layoutManager?.textContainerChangedGeometry(self) }

    /// The width right-aligned and centred lines flush against when `size.width` is
    /// unbounded (a field editor's or a horizontally resizable view's container, which
    /// never wraps): the view's visible width. Nil flushes against the container width.
    internal var _alignmentWidth: CGFloat? {
        didSet { if _alignmentWidth != oldValue { _geometryChanged() } }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/size
    open var size: CGSize {
        get { _size }
        set { guard newValue != _size else { return }; _size = newValue; _geometryChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/containersize
    open var containerSize: NSSize {
        get { size }
        set { size = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/contains(_:)
    open func contains(_ point: NSPoint) -> Bool { NSRect(origin: .zero, size: _size).contains(point) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/exclusionpaths
    open var exclusionPaths: [NSBezierPath] {
        get { _exclusionPaths }
        set { _exclusionPaths = newValue; _geometryChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/heighttrackstextview
    open var heightTracksTextView: Bool {
        get { _heightTracksTextView }
        set { _heightTracksTextView = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/issimplerectangulartextcontainer
    open var isSimpleRectangularTextContainer: Bool { _exclusionPaths.isEmpty }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/layoutmanager
    open var layoutManager: NSLayoutManager? {
        get { _layoutManager }
        set { _layoutManager = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/linebreakmode
    open var lineBreakMode: NSLineBreakMode {
        get { _lineBreakMode }
        set { _lineBreakMode = newValue; _geometryChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/linefragmentpadding
    open var lineFragmentPadding: CGFloat {
        get { _lineFragmentPadding }
        set { _lineFragmentPadding = newValue; _geometryChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/linefragmentrect(forproposedrect:at:writingdirection:remaining:)
    open func lineFragmentRect(forProposedRect proposedRect: CGRect, at characterIndex: Int, writingDirection baseWritingDirection: NSWritingDirection, remaining remainingRect: UnsafeMutablePointer<CGRect>?) -> CGRect {
        remainingRect?.pointee = .zero
        var r = proposedRect
        r.origin.x = max(0, r.origin.x)
        r.size.width = min(_size.width - r.origin.x, r.size.width)
        if r.maxY > _size.height { return .zero }
        return r
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/maximumnumberoflines
    open var maximumNumberOfLines: Int {
        get { _maximumNumberOfLines }
        set { _maximumNumberOfLines = newValue; _geometryChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/replacelayoutmanager(_:)
    open func replaceLayoutManager(_ newLayoutManager: NSLayoutManager) {
        guard let old = _layoutManager, let storage = old.textStorage else { _layoutManager = newLayoutManager; return }
        let containers = old.textContainers
        storage.removeLayoutManager(old)
        storage.addLayoutManager(newLayoutManager)
        for c in containers { newLayoutManager.addTextContainer(c) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/textlayoutmanager
    open var textLayoutManager: NSTextLayoutManager? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/textview
    open var textView: NSTextView? {
        get { _textView }
        set { _textView = newValue; _layoutManager?.textContainerChangedTextView(self) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontainer/widthtrackstextview
    open var widthTracksTextView: Bool {
        get { _widthTracksTextView }
        set { _widthTracksTextView = newValue }
    }
    // Requirement of NSTextLayoutOrientationProvider
    open var layoutOrientation: NSLayoutManager.TextLayoutOrientation { .horizontal }
}
