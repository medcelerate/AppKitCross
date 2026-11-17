// NSTextViewportLayoutController (hand-written; seeded from the generated stub, see tools/apigen)
// Lays out only the fragments in the viewport its delegate reports (ADR-0040), and hands
// each one to the delegate to configure, between the will- and did-layout calls.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextviewportlayoutcontroller
@available(macOS 12.0, *)
open class NSTextViewportLayoutController: NSObject {
    private weak var _textLayoutManager: NSTextLayoutManager?
    private weak var _delegate: (any NSTextViewportLayoutControllerDelegate)?
    private var _viewportBounds: CGRect = .zero
    private var _viewportRange: NSTextRange?

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextviewportlayoutcontroller/init(textlayoutmanager:)
    public init(textLayoutManager: NSTextLayoutManager) {
        _textLayoutManager = textLayoutManager
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextviewportlayoutcontroller/delegate
    open var delegate: (any NSTextViewportLayoutControllerDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextviewportlayoutcontroller/textlayoutmanager
    open var textLayoutManager: NSTextLayoutManager? { _textLayoutManager }
    /// The bounds of the last layout (container coordinates).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextviewportlayoutcontroller/viewportbounds
    open var viewportBounds: CGRect { _viewportBounds }
    /// The text the last layout covered.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextviewportlayoutcontroller/viewportrange
    open var viewportRange: NSTextRange? { _viewportRange }

    /// Lays out the fragments intersecting the delegate's viewport bounds.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextviewportlayoutcontroller/layoutviewport()
    open func layoutViewport() {
        guard let tlm = _textLayoutManager else { return }
        let bounds = _delegate?.viewportBounds(for: self) ?? .zero
        _delegate?.textViewportLayoutControllerWillLayout(self)
        _viewportBounds = bounds
        let fragments = tlm._layoutFragments(in: bounds)
        for f in fragments { _delegate?.textViewportLayoutController(self, configureRenderingSurfaceFor: f) }
        if let first = fragments.first, let last = fragments.last {
            _viewportRange = NSTextRange(location: first.rangeInElement.location, end: last.rangeInElement.endLocation)
        } else {
            _viewportRange = nil
        }
        _delegate?.textViewportLayoutControllerDidLayout(self)
    }
    /// Lays out from the fragment holding `textLocation` and returns that fragment's top
    /// (the offset to scroll the viewport to).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextviewportlayoutcontroller/relocateviewport(to:)
    open func relocateViewport(to textLocation: any NSTextLocation) -> CGFloat {
        guard let tlm = _textLayoutManager, let f = tlm.textLayoutFragment(for: textLocation) else { return 0 }
        let top = f.layoutFragmentFrame.minY
        let height = max(1, _viewportBounds.height)
        _ = tlm._layoutFragments(in: CGRect(x: 0, y: top, width: max(1, _viewportBounds.width), height: height))
        return f.layoutFragmentFrame.minY
    }
    /// Moves every fragment frame by `verticalOffset` (to keep the text in the viewport still
    /// when estimated heights above it change).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextviewportlayoutcontroller/adjustviewport(byverticaloffset:)
    open func adjustViewport(byVerticalOffset verticalOffset: CGFloat) {
        guard let tlm = _textLayoutManager, verticalOffset != 0 else { return }
        tlm._originOffset += verticalOffset
        tlm._invalidatePositions()
        _viewportBounds.origin.y += verticalOffset
    }
}
