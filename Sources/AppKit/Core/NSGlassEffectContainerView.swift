// NSGlassEffectContainerView (hand-written; seeded from the generated stub, see tools/apigen)
// Liquid Glass (ADR-0052): a container whose glass views draw as one group. The port keeps
// the API and the spacing; the glass views inside draw their own surfaces (the morphing
// bridge macOS animates between neighbours closer than `spacing` is not drawn).

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview
@MainActor open class NSGlassEffectContainerView: NSView {
    private var _contentView: NSView?
    private var _spacing: CGFloat = 0

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview/contentview
    @MainActor open var contentView: NSView? {
        get { _contentView }
        set {
            guard newValue !== _contentView else { return }
            _contentView?.removeFromSuperview()
            _contentView = newValue
            if let v = newValue {
                v.frame = bounds
                v.autoresizingMask = [.width, .height]
                addSubview(v)
            }
            needsDisplay = true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview/spacing
    /// How close two glass views in the container may be before macOS merges their
    /// surfaces. Kept for the views to read; the port draws each surface on its own.
    @MainActor open var spacing: CGFloat {
        get { _spacing }
        set { _spacing = max(0, newValue); needsDisplay = true }
    }

    open override var isOpaque: Bool { false }

    /// The glass views in the container, in paint order.
    internal var _glassViews: [NSGlassEffectView] {
        var found: [NSGlassEffectView] = []
        func visit(_ v: NSView) {
            if let g = v as? NSGlassEffectView { found.append(g); return }
            for s in v.subviews { visit(s) }
        }
        for s in subviews { visit(s) }
        return found
    }
}
