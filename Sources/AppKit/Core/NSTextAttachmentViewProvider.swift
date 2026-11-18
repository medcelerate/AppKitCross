// NSTextAttachmentViewProvider (hand-written; seeded from the generated stub, see tools/apigen)
//
// A TextKit 2 object that supplies a view for an attachment. This port lays text out with
// TextKit 1 (NSLayoutManager), which never asks for one (ADR-0030); the class keeps its
// state so subclasses and code that create providers directly work.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachmentviewprovider
@available(macOS 12.0, *)
open class NSTextAttachmentViewProvider: NSObject {
    private weak var _textAttachment: NSTextAttachment?
    private weak var _parentView: NSView?
    private weak var _textLayoutManager: NSTextLayoutManager?
    private let _location: any NSTextLocation
    private var _view: NSView?
    private var _tracksBounds = false

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachmentviewprovider/init(textattachment:parentview:textlayoutmanager:location:)
    public init(textAttachment: NSTextAttachment, parentView: NSView?, textLayoutManager: NSTextLayoutManager?, location: any NSTextLocation) {
        _textAttachment = textAttachment
        _parentView = parentView
        _textLayoutManager = textLayoutManager
        _location = location
        super.init()
    }
    /// The attachment's own bounds unless `tracksTextAttachmentViewBounds`, then the view's.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachmentviewprovider/attachmentbounds(for:location:textcontainer:proposedlinefragment:position:)
    open func attachmentBounds(for attributes: [NSAttributedString.Key : Any], location: any NSTextLocation, textContainer: NSTextContainer?, proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
        if _tracksBounds, let v = _view { return MainActor.assumeIsolated { CGRect(origin: .zero, size: v.frame.size) } }
        return _textAttachment?.attachmentBounds(for: attributes, location: location, textContainer: textContainer, proposedLineFragment: proposedLineFragment, position: position) ?? .zero
    }
    /// Subclasses create `view` here; the default leaves it nil.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachmentviewprovider/loadview()
    open func loadView() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachmentviewprovider/location
    open var location: any NSTextLocation { _location }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachmentviewprovider/textattachment
    open var textAttachment: NSTextAttachment? { _textAttachment }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachmentviewprovider/textlayoutmanager
    open var textLayoutManager: NSTextLayoutManager? { _textLayoutManager }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachmentviewprovider/trackstextattachmentviewbounds
    open var tracksTextAttachmentViewBounds: Bool {
        get { _tracksBounds }
        set { _tracksBounds = newValue }
    }
    /// Loaded on first access, as in AppKit.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachmentviewprovider/view
    open var view: NSView? {
        get { if _view == nil { loadView() }; return _view }
        set { _view = newValue }
    }
}
