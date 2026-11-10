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
    /// Font selected with `NSFont.set()`; used by string drawing when no font attribute is given.
    internal var _font: NSFont? = nil

    // Drawing happens on the main thread; AppKit's "current context" is per thread and
    // this port only draws from the main actor.
    nonisolated(unsafe) private static var _current: NSGraphicsContext?
    nonisolated(unsafe) private static var _stack: [NSGraphicsContext?] = []
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/init(attributes:)
    public init?(attributes: [NSGraphicsContext.AttributeKey : Any] = [:]) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/init(bitmapimagerep:)
    public init?(bitmapImageRep bitmapRep: NSBitmapImageRep) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/init(cgcontext:flipped:)
    @available(macOS 10.10, *)
    public init(cgContext graphicsPort: CGContext, flipped initialFlippedState: Bool) {
        _cg = graphicsPort
        _flipped = initialFlippedState
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/init(graphicsport:flipped:)
    public init(graphicsPort: UnsafeMutableRawPointer, flipped initialFlippedState: Bool) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/init(window:)
    public init(window: NSWindow) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/attributes
    open var attributes: [NSGraphicsContext.AttributeKey : Any]? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/cgcontext
    @available(macOS 10.10, *)
    open var cgContext: CGContext { _cg }
    // SKIPPED (unknown module (CoreImage CIContext)): var ciContext: CIContext? { get }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/colorrenderingintent
    open var colorRenderingIntent: NSColorRenderingIntent {
        get { unimplemented() }
        set { unimplemented() }
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
        set { _current = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/currentcontextdrawingtoscreen()
    public class func currentContextDrawingToScreen() -> Bool { _current?.isDrawingToScreen ?? false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/flushgraphics()
    open func flushGraphics() { _cg.flush() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/graphicsport
    open var graphicsPort: UnsafeMutableRawPointer { unimplemented() }
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
        _current = saved
        saved?._cg.restoreGState()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/restoregraphicsstate()
    open func restoreGraphicsState() {
        _cg.restoreGState()
        if let saved = NSGraphicsContext._stack.popLast() { NSGraphicsContext._current = saved }
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
    public class func setGraphicsState(_ gState: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgraphicscontext/shouldantialias
    open var shouldAntialias: Bool {
        get { _shouldAntialias }
        set { _shouldAntialias = newValue; _cg.setShouldAntialias(newValue) }
    }
}
