// NSImageView (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimageview
@MainActor open class NSImageView: NSControl, NSAccessibilityImage, NSMenuItemValidation {
    private var _allowsCutCopyPaste = true
    private var _animates = false
    private var _isEditable = false
    private var _contentTintColor: NSColor? = nil
    private var _symbolConfiguration: NSImage.SymbolConfiguration? = nil
    private var _imageDynamicRange: NSImage.DynamicRange = .standard

    internal var _imageCell: NSImageCell? { _cell as? NSImageCell }

    @MainActor open override class func _makeDefaultCell() -> NSCell? { NSImageCell(imageCell: nil) }

    @MainActor open override var intrinsicContentSize: NSSize { image?.size ?? NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimageview/init(image:)
    @available(macOS 10.12, *)
    @MainActor public convenience init(image: NSImage) {
        self.init(frame: NSRect(origin: .zero, size: image.size))
        self.image = image
    }
    // SKIPPED (Symbols.DiscreteSymbolEffect; Symbols.SymbolEffect; Symbols.SymbolEffectOptions): @MainActor func addSymbolEffect(_ effect: some DiscreteSymbolEffect & SymbolEffect, options: SymbolEffectOptions = .default, animated: Bool = true)
    // SKIPPED (Symbols.IndefiniteSymbolEffect; Symbols.SymbolEffect; Symbols.SymbolEffectOptions): @MainActor func addSymbolEffect(_ effect: some IndefiniteSymbolEffect & SymbolEffect, options: SymbolEffectOptions = .default, animated: Bool = true)
    // SKIPPED (Symbols.DiscreteSymbolEffect; Symbols.IndefiniteSymbolEffect; Symbols.SymbolEffect; Symbols.SymbolEffectOptions): @MainActor func addSymbolEffect(_ effect: some DiscreteSymbolEffect & IndefiniteSymbolEffect & SymbolEffect, options: SymbolEffectOptions = .default, animated: Bool = true)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimageview/allowscutcopypaste
    @MainActor open var allowsCutCopyPaste: Bool {
        get { _allowsCutCopyPaste }
        set { _allowsCutCopyPaste = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimageview/animates
    @MainActor open var animates: Bool {
        get { _animates }
        set { _animates = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimageview/contenttintcolor
    @available(macOS 10.14, *)
    @MainActor open var contentTintColor: NSColor? {
        get { _contentTintColor }
        set { _contentTintColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimageview/defaultpreferredimagedynamicrange
    @available(macOS 14.0, *)
    @MainActor class public var defaultPreferredImageDynamicRange: NSImage.DynamicRange { NSImage.DynamicRange(rawValue: 1)! }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimageview/image
    @MainActor open var image: NSImage? {
        get { _cell?.image }
        set { _cell?.image = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimageview/imagealignment
    @MainActor open var imageAlignment: NSImageAlignment {
        get { _imageCell?.imageAlignment ?? .alignCenter }
        set { _imageCell?.imageAlignment = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimageview/imagedynamicrange
    @available(macOS 14.0, *)
    @MainActor open var imageDynamicRange: NSImage.DynamicRange {
        get { _imageDynamicRange }
        set { _imageDynamicRange = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimageview/imageframestyle
    @MainActor open var imageFrameStyle: NSImageView.FrameStyle {
        get { _imageCell?.imageFrameStyle ?? .none }
        set { _imageCell?.imageFrameStyle = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimageview/imagescaling
    @MainActor open var imageScaling: NSImageScaling {
        get { _imageCell?.imageScaling ?? .scaleProportionallyDown }
        set { _imageCell?.imageScaling = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimageview/iseditable
    @MainActor open var isEditable: Bool {
        get { _isEditable }
        set { _isEditable = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimageview/preferredimagedynamicrange
    @available(macOS 14.0, *)
    @MainActor open var preferredImageDynamicRange: NSImage.DynamicRange {
        get { _imageDynamicRange }
        set { _imageDynamicRange = newValue }
    }
    // SKIPPED (Symbols.SymbolEffectOptions): @MainActor func removeAllSymbolEffects(options: SymbolEffectOptions = .default, animated: Bool = true)
    // SKIPPED (Symbols.DiscreteSymbolEffect; Symbols.SymbolEffect; Symbols.SymbolEffectOptions): @MainActor func removeSymbolEffect(ofType effect: some DiscreteSymbolEffect & SymbolEffect, options: SymbolEffectOptions = .default, animated: Bool = true)
    // SKIPPED (Symbols.IndefiniteSymbolEffect; Symbols.SymbolEffect; Symbols.SymbolEffectOptions): @MainActor func removeSymbolEffect(ofType effect: some IndefiniteSymbolEffect & SymbolEffect, options: SymbolEffectOptions = .default, animated: Bool = true)
    // SKIPPED (Symbols.DiscreteSymbolEffect; Symbols.IndefiniteSymbolEffect; Symbols.SymbolEffect; Symbols.SymbolEffectOptions): @MainActor func removeSymbolEffect(ofType effect: some DiscreteSymbolEffect & IndefiniteSymbolEffect & SymbolEffect, options: SymbolEffectOptions = .default, animated: Bool = true)
    // SKIPPED (Symbols.ContentTransitionSymbolEffect; Symbols.SymbolEffect; Symbols.SymbolEffectOptions): @MainActor func setSymbolImage(_ image: NSImage, contentTransition: some ContentTransitionSymbolEffect & SymbolEffect, options: SymbolEffectOptions = .default)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimageview/symbolconfiguration
    @available(macOS 11.0, *)
    @MainActor open var symbolConfiguration: NSImage.SymbolConfiguration? {
        get { _symbolConfiguration }
        set { _symbolConfiguration = newValue }
    }
    // Requirement of NSAccessibilityImage
    open func accessibilityLabel() -> String? { unimplemented() }
}
