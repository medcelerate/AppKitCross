// NSScrubberArrangedView (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// The base of the views a scrubber arranges: items and selection views. The scrubber
// sets the selected and highlighted state and applies layout attributes (ADR-0034).

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberarrangedview
@available(macOS 10.12, *)
@MainActor open class NSScrubberArrangedView: NSView {
    private var _isHighlighted = false
    private var _isSelected = false

    /// Takes the frame and alpha.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberarrangedview/apply(_:)
    @MainActor open func apply(_ layoutAttributes: NSScrubberLayoutAttributes) {
        if frame != layoutAttributes.frame { frame = layoutAttributes.frame }
        if alphaValue != layoutAttributes.alpha { alphaValue = layoutAttributes.alpha }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberarrangedview/ishighlighted
    @MainActor open var isHighlighted: Bool {
        get { _isHighlighted }
        set { guard newValue != _isHighlighted else { return }; _isHighlighted = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberarrangedview/isselected
    @MainActor open var isSelected: Bool {
        get { _isSelected }
        set { guard newValue != _isSelected else { return }; _isSelected = newValue; needsDisplay = true }
    }
}
