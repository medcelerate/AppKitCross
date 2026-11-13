// NSScrubberSelectionStyle (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// A style makes the view the scrubber puts at the selected item. The base class makes
// none (subclasses override `makeSelectionView()`); the two built-in styles are drawn
// by the package: a rounded accent-tinted background and a rounded accent outline
// (ADR-0034).

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberselectionstyle
@available(macOS 10.12, *)
@MainActor open class NSScrubberSelectionStyle: NSObject, NSCoding {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberselectionstyle/init()
    @MainActor public override init() { super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberselectionstyle/init(coder:)
    @MainActor public required init(coder: NSCoder) { unimplemented() }
    /// None in the base class.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberselectionstyle/makeselectionview()
    @MainActor open func makeSelectionView() -> NSScrubberSelectionView? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberselectionstyle/outlineoverlay
    @MainActor class public var outlineOverlay: NSScrubberSelectionStyle { _outline }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubberselectionstyle/roundedbackground
    @MainActor class public var roundedBackground: NSScrubberSelectionStyle { _rounded }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { unimplemented() }

    private static let _outline = _NSScrubberBuiltinSelectionStyle(outline: true)
    private static let _rounded = _NSScrubberBuiltinSelectionStyle(outline: false)
}

@MainActor private final class _NSScrubberBuiltinSelectionStyle: NSScrubberSelectionStyle {
    let outline: Bool
    init(outline: Bool) { self.outline = outline; super.init() }
    required init(coder: NSCoder) { unimplemented() }
    override func makeSelectionView() -> NSScrubberSelectionView? {
        let v = _NSScrubberBuiltinSelectionView(frame: .zero)
        v.outline = outline
        return v
    }
}

@MainActor internal final class _NSScrubberBuiltinSelectionView: NSScrubberSelectionView {
    var outline = false
    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        if outline {
            let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
            p.lineWidth = 2
            accent.setStroke()
            p.stroke()
        } else {
            accent.withAlphaComponent(isHighlighted ? 0.45 : 0.3).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
    }
}
