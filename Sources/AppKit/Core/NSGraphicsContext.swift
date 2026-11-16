// NSGraphicsContext (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext
open class NSGraphicsContext: NSObject {
    private let _cg: CGContext
    private let _flipped: Bool
    private var _compositingOperation: NSCompositingOperation = .sourceOver
    private var _imageInterpolation: NSImageInterpolation = .default
    private var _patternPhase = NSPoint.zero
    private var _shouldAntialias = true
    private var _colorRenderingIntent: NSColorRenderingIntent = .default
    /// A context made for a bitmap rep draws into an offscreen surface; the rep takes the
    /// surface's pixels whenever the context is flushed, stops being current, or goes away.
    private var _bitmapTarget: (rep: NSBitmapImageRep, surface: PlatformOffscreenSurface)? = nil
    internal func _syncBitmap() {
        guard let t = _bitmapTarget, Thread.isMainThread else { return }
        if let image = MainActor.assumeIsolated({ t.surface.makeImage() }) { t.rep._setImage(image) }
    }
    deinit { _syncBitmap() }
    /// Font selected with `NSFont.set()`; used by string drawing when no font attribute is given.
    internal var _font: NSFont? = nil

    // Drawing happens on the main thread; AppKit's "current context" is per thread and
    // this port only draws from the main actor.
    nonisolated(unsafe) private static var _current: NSGraphicsContext?
    nonisolated(unsafe) private static var _stack: [NSGraphicsContext?] = []
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/init(attributes:)
    /// A context for the destination attribute: a bitmap rep (as `init(bitmapImageRep:)`) or
    /// a window. Nil for anything else, as macOS answers for no destination or a PDF format.
    public convenience init?(attributes: [NSGraphicsContext.AttributeKey : Any] = [:]) {
        if let rep = attributes[.destination] as? NSBitmapImageRep {
            self.init(bitmapImageRep: rep)
        } else if let window = attributes[.destination] as? NSWindow {
            self.init(window: window)
        } else {
            return nil
        }
    }
    /// Drawing in the rep's size in points (the CTM scales to its pixels, macOS 15), y up,
    /// over the rep's current pixels.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/init(bitmapimagerep:)
    public init?(bitmapImageRep bitmapRep: NSBitmapImageRep) {
        let size = bitmapRep.size.width > 0 && bitmapRep.size.height > 0 ? bitmapRep.size : NSSize(width: bitmapRep.pixelsWide, height: bitmapRep.pixelsHigh)
        guard bitmapRep.pixelsWide > 0, bitmapRep.pixelsHigh > 0,
              let surface = MainActor.assumeIsolated({ Platform.backend.image.makeOffscreen(size: size, scale: CGFloat(bitmapRep.pixelsWide) / size.width) }) else { return nil }
        let context = MainActor.assumeIsolated { surface.context }
        if let existing = bitmapRep.cgImage { context.draw(existing, in: CGRect(origin: .zero, size: size)) }
        _cg = context
        _flipped = false
        _colorRenderingIntent = .relativeColorimetric
        _bitmapTarget = (bitmapRep, surface)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/init(cgcontext:flipped:)
    @available(macOS 10.10, *)
    public init(cgContext graphicsPort: CGContext, flipped initialFlippedState: Bool) {
        _cg = graphicsPort
        _flipped = initialFlippedState
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/init(graphicsport:flipped:)
    /// `graphicsPort` is a CGContext reference (what `graphicsPort` returns).
    public convenience init(graphicsPort: UnsafeMutableRawPointer, flipped initialFlippedState: Bool) {
        self.init(cgContext: Unmanaged<CGContext>.fromOpaque(graphicsPort).takeUnretainedValue(), flipped: initialFlippedState)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/init(window:)
    public init(window: NSWindow) { unimplemented("NSGraphicsContext(window:) — windows are drawn only by their views' display pass into the compositor's layers; there is no window-wide context to draw into outside it") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/attributes
    open var attributes: [NSGraphicsContext.AttributeKey : Any]? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/cgcontext
    @available(macOS 10.10, *)
    open var cgContext: CGContext { _cg }
    // SKIPPED (unknown module (CoreImage CIContext)): var ciContext: CIContext? { get }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/colorrenderingintent
    /// Stored (a bitmap context starts relative colorimetric, as macOS 15); the port composes
    /// in sRGB, so no gamut mapping happens whatever the intent.
    open var colorRenderingIntent: NSColorRenderingIntent {
        get { _colorRenderingIntent }
        set { _colorRenderingIntent = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/compositingoperation
    open var compositingOperation: NSCompositingOperation {
        get { _compositingOperation }
        set {
            _compositingOperation = newValue
            let mode: CGBlendMode
            switch newValue {
            case .clear: mode = .clear
            case .copy: mode = .copy
            case .sourceOver: mode = .normal
            case .sourceIn: mode = .sourceIn
            case .sourceOut: mode = .sourceOut
            case .sourceAtop: mode = .sourceAtop
            case .destinationOver: mode = .destinationOver
            case .destinationIn: mode = .destinationIn
            case .destinationOut: mode = .destinationOut
            case .destinationAtop: mode = .destinationAtop
            case .xor: mode = .xor
            case .plusDarker: mode = .plusDarker
            case .plusLighter: mode = .plusLighter
            case .multiply: mode = .multiply
            case .screen: mode = .screen
            case .overlay: mode = .overlay
            case .darken: mode = .darken
            case .lighten: mode = .lighten
            case .colorDodge: mode = .colorDodge
            case .colorBurn: mode = .colorBurn
            case .softLight: mode = .softLight
            case .hardLight: mode = .hardLight
            case .difference: mode = .difference
            case .exclusion: mode = .exclusion
            case .hue: mode = .hue
            case .saturation: mode = .saturation
            case .color: mode = .color
            case .luminosity: mode = .luminosity
            default: mode = .normal
            }
            _cg.setBlendMode(mode)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/current
    class public var current: NSGraphicsContext? {
        get { _current }
        set {
            if let old = _current, old !== newValue { old._syncBitmap() }
            _current = newValue
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/currentcontextdrawingtoscreen()
    public class func currentContextDrawingToScreen() -> Bool { _current?.isDrawingToScreen ?? false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/flushgraphics()
    open func flushGraphics() { _cg.flush(); _syncBitmap() }
    /// The CGContext as an opaque reference (macOS: the same pointer as `cgContext`).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/graphicsport
    open var graphicsPort: UnsafeMutableRawPointer { Unmanaged.passUnretained(_cg).toOpaque() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/imageinterpolation
    open var imageInterpolation: NSImageInterpolation {
        get { _imageInterpolation }
        set {
            _imageInterpolation = newValue
            switch newValue {
            case .none: _cg.interpolationQuality = .none
            case .low: _cg.interpolationQuality = .low
            case .medium: _cg.interpolationQuality = .medium
            case .high: _cg.interpolationQuality = .high
            default: _cg.interpolationQuality = .default
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/isdrawingtoscreen
    open var isDrawingToScreen: Bool { !NSGraphicsContext._printing }
    /// True while `NSPrintOperation` draws a page (`isDrawingToScreen` is then false).
    nonisolated(unsafe) internal static var _printing = false
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/isflipped
    open var isFlipped: Bool { _flipped }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/patternphase
    open var patternPhase: NSPoint {
        get { _patternPhase }
        set { _patternPhase = newValue; _cg.setPatternPhase(CGSize(width: newValue.x, height: newValue.y)) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/restoregraphicsstate()
    public class func restoreGraphicsState() {
        guard let saved = _stack.popLast() else { return }
        if let old = _current, old !== saved { old._syncBitmap() }
        _current = saved
        saved?._cg.restoreGState()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/restoregraphicsstate()
    open func restoreGraphicsState() {
        _cg.restoreGState()
        if let saved = NSGraphicsContext._stack.popLast() {
            if saved !== self { _syncBitmap() }
            NSGraphicsContext._current = saved
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/savegraphicsstate()
    public class func saveGraphicsState() {
        _stack.append(_current)
        _current?._cg.saveGState()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/savegraphicsstate()
    open func saveGraphicsState() {
        NSGraphicsContext._stack.append(NSGraphicsContext._current)
        NSGraphicsContext._current = self
        _cg.saveGState()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/setgraphicsstate(_:)
    public class func setGraphicsState(_ gState: Int) { unimplemented("NSGraphicsContext.setGraphicsState(_:) — gstate numbers came from the removed NSView/NSWindow gState; nothing hands them out") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/shouldantialias
    open var shouldAntialias: Bool {
        get { _shouldAntialias }
        set { _shouldAntialias = newValue; _cg.setShouldAntialias(newValue) }
    }
}
