// NSImageRep (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep
open class NSImageRep: NSObject, NSCopying, NSCoding {
    // MARK: Storage
    internal var _size = NSSize.zero
    internal var _pixelsWide = 0
    internal var _pixelsHigh = 0
    internal var _hasAlpha = true
    internal var _isOpaque = false
    internal var _bitsPerSample = 8
    internal var _colorSpaceName: NSColorSpaceName = .deviceRGB
    internal var _layoutDirection: NSImage.LayoutDirection = .unspecified

    /// Subclasses provide the pixels; nil means nothing to draw.
    @MainActor internal func _cgImage() -> CGImage? { nil }

    open override var description: String { "<\(type(of: self)) \(_pixelsWide)x\(_pixelsHigh) size=\(_size)>" }

    /// Decodes `data` into representations (bitmap formats via the platform decoder).
    public class func imageReps(with data: Data) -> [NSImageRep] { NSBitmapImageRep.imageReps(with: data) }
    public class func imageRep(with data: Data) -> NSImageRep? { imageReps(with: data).first }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/init()
    public override init() { super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/init(coder:)
    public required init?(coder: NSCoder) { super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/init(contentsof:)
    public convenience init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init()
        guard let rep = NSImageRep.imageReps(with: data).first else { return nil }
        _size = rep.size; _pixelsWide = rep.pixelsWide; _pixelsHigh = rep.pixelsHigh
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/init(contentsoffile:)
    public convenience init?(contentsOfFile filename: String) { self.init(contentsOf: URL(fileURLWithPath: filename)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/init(pasteboard:)
    public init?(pasteboard: NSPasteboard) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/bitspersample
    open var bitsPerSample: Int {
        get { _bitsPerSample }
        set { _bitsPerSample = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/caninit(with:)
    public class func canInit(with data: Data) -> Bool { !data.isEmpty }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/caninit(with:)
    public class func canInit(with pasteboard: NSPasteboard) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/cgimage(forproposedrect:context:hints:)
    open func cgImage(forProposedRect proposedDestRect: UnsafeMutablePointer<NSRect>?, context: NSGraphicsContext?, hints: [NSImageRep.HintKey : Any]?) -> CGImage? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/class(for:)
    public class func `class`(for data: Data) -> AnyClass? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/class(forfiletype:)
    public class func `class`(forFileType type: String) -> AnyClass? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/class(forpasteboardtype:)
    public class func `class`(forPasteboardType type: NSPasteboard.PasteboardType) -> AnyClass? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/class(fortype:)
    public class func `class`(forType type: String) -> AnyClass? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/colorspacename
    open var colorSpaceName: NSColorSpaceName {
        get { _colorSpaceName }
        set { _colorSpaceName = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/draw()
    open func draw() -> Bool { draw(in: NSRect(origin: .zero, size: _size)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/draw(at:)
    open func draw(at point: NSPoint) -> Bool { draw(in: NSRect(origin: point, size: _size)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/draw(in:)
    open func draw(in rect: NSRect) -> Bool {
        MainActor.assumeIsolated {
            guard let ctx = NSGraphicsContext.current?.cgContext, let image = _cgImage() else { return false }
            ctx.draw(image, in: rect)
            return true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/draw(in:from:operation:fraction:respectflipped:hints:)
    open func draw(in dstSpacePortionRect: NSRect, from srcSpacePortionRect: NSRect, operation op: NSCompositingOperation, fraction requestedAlpha: CGFloat, respectFlipped respectContextIsFlipped: Bool, hints: [NSImageRep.HintKey : Any]?) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/hasalpha
    open var hasAlpha: Bool {
        get { _hasAlpha }
        set { _hasAlpha = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/imagefiletypes()
    public class func imageFileTypes() -> [String] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/imagepasteboardtypes()
    public class func imagePasteboardTypes() -> [NSPasteboard.PasteboardType] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/imagereps(with:)
    public class func imageReps(with pasteboard: NSPasteboard) -> [NSImageRep]? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/imagereps(withcontentsof:)
    public class func imageReps(withContentsOf url: URL) -> [NSImageRep]? { (try? Data(contentsOf: url)).map { imageReps(with: $0) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/imagereps(withcontentsoffile:)
    public class func imageReps(withContentsOfFile filename: String) -> [NSImageRep]? { imageReps(withContentsOf: URL(fileURLWithPath: filename)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/imagetypes
    class public var imageTypes: [String] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/imageunfilteredfiletypes()
    public class func imageUnfilteredFileTypes() -> [String] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/imageunfilteredpasteboardtypes()
    public class func imageUnfilteredPasteboardTypes() -> [NSPasteboard.PasteboardType] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/imageunfilteredtypes
    class public var imageUnfilteredTypes: [String] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/isopaque
    open var isOpaque: Bool {
        get { _isOpaque }
        set { _isOpaque = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/layoutdirection
    @available(macOS 10.12, *)
    open var layoutDirection: NSImage.LayoutDirection {
        get { _layoutDirection }
        set { _layoutDirection = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/pixelshigh
    open var pixelsHigh: Int {
        get { _pixelsHigh }
        set { _pixelsHigh = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/pixelswide
    open var pixelsWide: Int {
        get { _pixelsWide }
        set { _pixelsWide = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/registerclass(_:)
    public class func registerClass(_ imageRepClass: AnyClass) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/registeredclasses
    class public var registeredClasses: [AnyClass] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/registrydidchangenotification
    static public var registryDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSImageRepRegistryDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/size
    open var size: NSSize {
        get { _size }
        set { _size = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/unregisterclass(_:)
    public class func unregisterClass(_ imageRepClass: AnyClass) { unimplemented() }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any { self }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { }
}
