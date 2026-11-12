// NSScrubberImageItemView (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// An item showing an image filling the item, placed by `imageAlignment` (ADR-0034).

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberimageitemview
@available(macOS 10.12, *)
@MainActor open class NSScrubberImageItemView: NSScrubberItemView {
    private let _imageView = NSImageView(frame: .zero)

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        _setUp()
    }
    /// Also how a scrubber makes a registered item view.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        _setUp()
    }
    private func _setUp() {
        _imageView.imageScaling = .scaleProportionallyDown
        _imageView.imageAlignment = .alignCenter
        _imageView.frame = bounds
        addSubview(_imageView)
    }
    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        _imageView.frame = bounds
    }
    /// The image view's image; reading it before one is set is a programming error, as
    /// the property is non-optional in AppKit.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberimageitemview/image
    @MainActor open var image: NSImage {
        get {
            guard let i = _imageView.image else { preconditionFailure("NSScrubberImageItemView: no image set") }
            return i
        }
        set { _imageView.image = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberimageitemview/imagealignment
    @MainActor open var imageAlignment: NSImageAlignment {
        get { _imageView.imageAlignment }
        set { _imageView.imageAlignment = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberimageitemview/imageview
    @MainActor open var imageView: NSImageView { _imageView }
}
