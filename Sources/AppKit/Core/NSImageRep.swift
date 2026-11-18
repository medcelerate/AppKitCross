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
    /// A plain NSImageRep made from a file or pasteboard draws the rep decoded from it.
    internal var _proxy: NSImageRep? = nil

    /// Subclasses provide the pixels; nil means nothing to draw.
    @MainActor internal func _cgImage() -> CGImage? { _proxy?._cgImage() }

    // MARK: Registry (ADR-0036)
    /// The rep classes `NSImage` and `class(for:)` consult, most recently registered first
    /// when looking up. Only reps the port can draw are registered (the PDF, EPS, PICT
    /// and Core Image reps are generated stubs).
    nonisolated(unsafe) internal static var _registeredClasses: [NSImageRep.Type] = [NSBitmapImageRep.self]

    /// This rep, or the decoded rep it stands for, as a bitmap (rendering when needed).
    internal func _renderedBitmap() -> NSBitmapImageRep? {
        if let b = self as? NSBitmapImageRep { return b }
        if let p = _proxy { return p._renderedBitmap() }
        return MainActor.assumeIsolated {
            if let image = _cgImage() { let r = NSBitmapImageRep(cgImage: image); r.size = _size; return r }
            let w = max(1, _pixelsWide > 0 ? _pixelsWide : Int(_size.width)), h = max(1, _pixelsHigh > 0 ? _pixelsHigh : Int(_size.height))
            guard _size.width > 0, _size.height > 0,
                  let surface = Platform.backend.image.makeOffscreen(size: _size, scale: CGFloat(w) / _size.width) else { return nil }
            _ = h
            let saved = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: surface.context, flipped: false)
            _ = draw(in: NSRect(origin: .zero, size: _size))
            NSGraphicsContext.current = saved
            guard let image = surface.makeImage() else { return nil }
            let r = NSBitmapImageRep(cgImage: image); r.size = _size
            return r
        }
    }

    /// Draws `image` (of `imageSize` points) as NSImage and NSImageRep do: the `src`
    /// portion (all of it when empty) into `dst`, composited with `op` at `alpha`, turned
    /// upright in a flipped context when `respectFlipped`.
    @MainActor internal static func _drawImage(_ image: CGImage, imageSize: NSSize, in dst: NSRect, from src: NSRect, operation op: NSCompositingOperation, fraction alpha: CGFloat, respectFlipped: Bool, hints: [NSImageRep.HintKey: Any]?) {
        guard let gc = NSGraphicsContext.current else { return }
        let ctx = gc.cgContext
        ctx.saveGState()
        let savedOp = gc.compositingOperation
        defer { gc.compositingOperation = savedOp; ctx.restoreGState() }
        if op != .sourceOver { gc.compositingOperation = op }
        if alpha < 1 { ctx.setAlpha(alpha) }
        if let interpolation = hints?[.interpolation] as? NSNumber, interpolation.intValue == NSImageInterpolation.none.rawValue { ctx.interpolationQuality = .none }
        var d = dst
        let full = NSRect(origin: .zero, size: imageSize)
        if !src.isEmpty && src != full {
            ctx.clip(to: d)
            let sx = d.width / src.width, sy = d.height / src.height
            d = NSRect(x: d.minX - src.minX * sx, y: d.minY - src.minY * sy, width: imageSize.width * sx, height: imageSize.height * sy)
        }
        if respectFlipped && gc.isFlipped {
            ctx.translateBy(x: 0, y: dst.midY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.translateBy(x: 0, y: -dst.midY)
        }
        ctx.draw(image, in: d)
    }

    open override var description: String { "<\(type(of: self)) \(_pixelsWide)x\(_pixelsHigh) size=\(_size)>" }

    /// Decodes `data` into representations with the first registered class that can.
    public class func imageReps(with data: Data) -> [NSImageRep] {
        guard self == NSImageRep.self else { return NSBitmapImageRep.imageReps(with: data) }
        for c in _registeredClasses.reversed() where c.canInit(with: data) { return c.imageReps(with: data) }
        return []
    }
    private func _adoptProxy(_ rep: NSImageRep) {
        _proxy = rep
        _size = rep.size; _pixelsWide = rep.pixelsWide; _pixelsHigh = rep.pixelsHigh
        _hasAlpha = rep.hasAlpha; _isOpaque = rep.isOpaque; _bitsPerSample = rep.bitsPerSample; _colorSpaceName = rep.colorSpaceName
    }
    /// The image data on `pasteboard` in the first image type it offers.
    internal static func _imageData(on pasteboard: NSPasteboard) -> Data? {
        let types = NSImageRep.imagePasteboardTypes()
        guard let type = pasteboard.availableType(from: types) else { return nil }
        return pasteboard.data(forType: type)
    }
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
        _adoptProxy(rep)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/init(contentsoffile:)
    public convenience init?(contentsOfFile filename: String) { self.init(contentsOf: URL(fileURLWithPath: filename)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/init(pasteboard:)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/init(pasteboard:)
    public init?(pasteboard: NSPasteboard) {
        guard let data = NSImageRep._imageData(on: pasteboard), let rep = NSImageRep.imageReps(with: data).first else { return nil }
        super.init()
        _adoptProxy(rep)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/bitspersample
    open var bitsPerSample: Int {
        get { _bitsPerSample }
        set { _bitsPerSample = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/caninit(with:)
    /// NSImageRep itself: whether a registered class can; a subclass answers for itself
    /// (`NSBitmapImageRep` checks the file signature).
    public class func canInit(with data: Data) -> Bool {
        guard self == NSImageRep.self else { return false }
        return _registeredClasses.contains { $0.canInit(with: data) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/caninit(with:)
    public class func canInit(with pasteboard: NSPasteboard) -> Bool { pasteboard.availableType(from: imagePasteboardTypes()) != nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/cgimage(forproposedrect:context:hints:)
    /// The rep's pixels, rendering it (at the proposed rect's size, else its own) when it
    /// has no bitmap.
    open func cgImage(forProposedRect proposedDestRect: UnsafeMutablePointer<NSRect>?, context: NSGraphicsContext?, hints: [NSImageRep.HintKey : Any]?) -> CGImage? {
        MainActor.assumeIsolated { _cgImage() ?? _renderedBitmap()?.cgImage }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/class(for:)
    public class func `class`(for data: Data) -> AnyClass? { _registeredClasses.reversed().first { $0.canInit(with: data) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/class(forfiletype:)
    public class func `class`(forFileType type: String) -> AnyClass? {
        let t = type.lowercased()
        return _registeredClasses.reversed().first { $0.imageUnfilteredFileTypes().contains { $0.lowercased() == t } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/class(forpasteboardtype:)
    public class func `class`(forPasteboardType type: NSPasteboard.PasteboardType) -> AnyClass? { _registeredClasses.reversed().first { $0.imageUnfilteredPasteboardTypes().contains(type) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/class(fortype:)
    public class func `class`(forType type: String) -> AnyClass? { _registeredClasses.reversed().first { $0.imageUnfilteredTypes.contains(type) } }
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
    open func draw(in dstSpacePortionRect: NSRect, from srcSpacePortionRect: NSRect, operation op: NSCompositingOperation, fraction requestedAlpha: CGFloat, respectFlipped respectContextIsFlipped: Bool, hints: [NSImageRep.HintKey : Any]?) -> Bool {
        MainActor.assumeIsolated {
            guard NSGraphicsContext.current != nil, let image = _cgImage() ?? _renderedBitmap()?.cgImage else { return false }
            NSImageRep._drawImage(image, imageSize: _size, in: dstSpacePortionRect, from: srcSpacePortionRect, operation: op, fraction: requestedAlpha, respectFlipped: respectContextIsFlipped, hints: hints)
            return true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/hasalpha
    open var hasAlpha: Bool {
        get { _hasAlpha }
        set { _hasAlpha = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/imagefiletypes()
    /// Deprecated: file extensions (and HFS types, none here) of `imageTypes`.
    public class func imageFileTypes() -> [String] { imageUnfilteredFileTypes() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/imagepasteboardtypes()
    public class func imagePasteboardTypes() -> [NSPasteboard.PasteboardType] { imageUnfilteredPasteboardTypes() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/imagereps(with:)
    public class func imageReps(with pasteboard: NSPasteboard) -> [NSImageRep]? {
        guard let data = _imageData(on: pasteboard) else { return nil }
        let reps = imageReps(with: data)
        return reps.isEmpty ? nil : reps
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/imagereps(withcontentsof:)
    public class func imageReps(withContentsOf url: URL) -> [NSImageRep]? { (try? Data(contentsOf: url)).map { imageReps(with: $0) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/imagereps(withcontentsoffile:)
    public class func imageReps(withContentsOfFile filename: String) -> [NSImageRep]? { imageReps(withContentsOf: URL(fileURLWithPath: filename)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/imagetypes
    /// The UTIs readable without a filter service (the port has no filter services).
    class public var imageTypes: [String] { imageUnfilteredTypes }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/imageunfilteredfiletypes()
    /// NSImageRep itself: every registered class's; a subclass lists its own.
    public class func imageUnfilteredFileTypes() -> [String] {
        guard self == NSImageRep.self else { return [] }
        return _unique(_registeredClasses.flatMap { $0.imageUnfilteredFileTypes() })
    }
    internal static func _unique<T: Hashable>(_ a: [T]) -> [T] { var seen = Set<T>(); return a.filter { seen.insert($0).inserted } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/imageunfilteredpasteboardtypes()
    public class func imageUnfilteredPasteboardTypes() -> [NSPasteboard.PasteboardType] {
        guard self == NSImageRep.self else { return imageUnfilteredTypes.map { NSPasteboard.PasteboardType(rawValue: $0) } }
        return _unique(_registeredClasses.flatMap { $0.imageUnfilteredPasteboardTypes() })
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/imageunfilteredtypes
    /// NSImageRep itself answers none (AppKit's base class lists nothing); see subclasses.
    class public var imageUnfilteredTypes: [String] { [] }
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
    public class func registerClass(_ imageRepClass: AnyClass) {
        guard let c = imageRepClass as? NSImageRep.Type else { return }
        _registeredClasses.removeAll { $0 == c }
        _registeredClasses.append(c)
        NotificationCenter.default.post(name: registryDidChangeNotification, object: c)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/registeredclasses
    class public var registeredClasses: [AnyClass] { _registeredClasses }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/registrydidchangenotification
    static public var registryDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSImageRepRegistryDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/size
    open var size: NSSize {
        get { _size }
        set { _size = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagerep/unregisterclass(_:)
    public class func unregisterClass(_ imageRepClass: AnyClass) {
        guard let c = imageRepClass as? NSImageRep.Type, _registeredClasses.contains(where: { $0 == c }) else { return }
        _registeredClasses.removeAll { $0 == c }
        NotificationCenter.default.post(name: registryDidChangeNotification, object: c)
    }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any { self }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { }
}
