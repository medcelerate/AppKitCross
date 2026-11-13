// NSImage (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage
/// `@unchecked Sendable` as Apple's: callers share images across tasks (Nuke keeps one in a
/// `Sendable` struct); mutation after setup is the caller's responsibility, as on macOS.
open class NSImage: NSObject, NSCopying, NSSecureCoding, NSCoding, NSPasteboardReading, NSPasteboardWriting, @unchecked Sendable {
    // MARK: Storage
    private var _size: NSSize
    private var _representations: [NSImageRep] = []
    private var _name: NSImage.Name? = nil
    private var _isTemplate = false
    private var _backgroundColor: NSColor = .clear
    private var _cacheMode: NSImage.CacheMode = .default
    private var _alignmentRect: NSRect? = nil
    private var _resizingMode: NSImage.ResizingMode = .stretch
    private var _capInsets = NSEdgeInsets()
    private var _usesEPSOnResolutionMismatch = false
    private var _matchesOnMultipleResolution = true
    private var _prefersColorMatch = true
    private var _accessibilityDescription: String? = nil
    private var _drawingHandler: ((NSRect) -> Bool)? = nil
    private var _drawingHandlerFlipped = false
    private var _focusSurface: PlatformOffscreenSurface? = nil
    private var _savedContext: NSGraphicsContext? = nil
    nonisolated(unsafe) private static var _named: [NSImage.Name: NSImage] = [:]
    private weak var _delegate: (any NSImageDelegate & AnyObject)? = nil
    private var _locale: Locale? = nil
    private var _symbolConfiguration: NSImage.SymbolConfiguration? = nil
    private var _matchesOnlyOnBestFittingAxis = false

    open override var description: String { "<NSImage \(_name.map { "'\($0)' " } ?? "")size=\(_size) reps=\(_representations.count)>" }

    /// The pixels to draw, rendering drawing handlers and template images as needed.
    @MainActor internal func _cgImage(scale: CGFloat = 1, fitting destination: NSSize? = nil) -> CGImage? {
        if let handler = _drawingHandler {
            guard let surface = Platform.backend.image.makeOffscreen(size: _size, scale: scale) else { return nil }
            let gc = NSGraphicsContext(cgContext: surface.context, flipped: _drawingHandlerFlipped)
            let saved = NSGraphicsContext.current
            NSGraphicsContext.current = gc
            if _drawingHandlerFlipped {
                surface.context.translateBy(x: 0, y: _size.height)
                surface.context.scaleBy(x: 1, y: -1)
            }
            _ = handler(NSRect(origin: .zero, size: _size))
            NSGraphicsContext.current = saved
            return surface.makeImage()
        }
        let target = destination ?? _size
        if let best = _bestRepresentation(pixels: NSSize(width: target.width * scale, height: target.height * scale), destination: target),
           let image = best._cgImage() ?? best._renderedBitmap()?.cgImage { return image }
        for rep in _representations {
            if let image = rep._cgImage() { return image }
        }
        return nil
    }

    /// AppKit's choice: among reps covering the needed pixels the smallest; none covering,
    /// the largest. `matchesOnMultipleResolution` lets an exact multiple (a 2x rep for a 1x
    /// need) count as a cover; `matchesOnlyOnBestFittingAxis` compares the axis that fits.
    private func _bestRepresentation(pixels need: NSSize, destination: NSSize) -> NSImageRep? {
        guard _representations.count > 1 else { return _representations.first }
        func px(_ r: NSImageRep) -> NSSize {
            NSSize(width: r.pixelsWide > 0 ? CGFloat(r.pixelsWide) : r.size.width, height: r.pixelsHigh > 0 ? CGFloat(r.pixelsHigh) : r.size.height)
        }
        func covers(_ r: NSImageRep) -> Bool {
            let p = px(r)
            if _matchesOnlyOnBestFittingAxis {
                return destination.width / max(1, _size.width) >= destination.height / max(1, _size.height) ? p.width >= need.width - 0.5 : p.height >= need.height - 0.5
            }
            return p.width >= need.width - 0.5 && p.height >= need.height - 0.5
        }
        let area: (NSImageRep) -> CGFloat = { let p = px($0); return p.width * p.height }
        let covering = _representations.filter(covers)
        if let smallest = covering.min(by: { area($0) < area($1) }) { return smallest }
        if _matchesOnMultipleResolution, let multiple = _representations.first(where: { r in
            let p = px(r); return p.width > 0 && need.width.truncatingRemainder(dividingBy: p.width) == 0 && p.width >= need.width
        }) { return multiple }
        return _representations.max { area($0) < area($1) }
    }

    /// Loads an image resource by name from the main bundle (any supported extension).
    private static func _loadNamed(_ name: NSImage.Name) -> NSImage? {
        let base = name
        for ext in ["png", "jpg", "jpeg", "bmp", "gif", "tiff"] {
            if let url = Bundle.main.url(forResource: base, withExtension: ext), let img = NSImage(contentsOf: url) {
                img._name = name
                return img
            }
        }
        // AppKit's own named images (NSImage.addTemplateName...) are drawn (ADR-0036).
        if let system = MainActor.assumeIsolated({ _NSSystemImages.named(name) }) { system._name = name; return system }
        return nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(byreferencing:)
    public convenience init(byReferencing url: URL) {
        self.init(size: .zero)
        if let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) { addRepresentation(rep); _size = rep.size }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(byreferencingfile:)
    public convenience init?(byReferencingFile fileName: String) { self.init(contentsOfFile: fileName) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(cgimage:size:)
    public convenience init(cgImage: CGImage, size: NSSize) {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        self.init(size: size == .zero ? rep.size : size)
        addRepresentation(rep)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(coder:)
    /// Unarchives what `encode(with:)` wrote: the size and a TIFF of the representations.
    public required init(coder: NSCoder) {
        _size = (coder.decodeObject(forKey: "NSSize") as? NSValue)?.sizeValue ?? .zero
        super.init()
        if let data = coder.decodeObject(forKey: "NSTIFFRepresentation") as? Data {
            let reps = NSBitmapImageRep.imageReps(with: data)
            _representations = reps
            if _size == .zero, let first = reps.first { _size = first.size }
        }
        _isTemplate = coder.decodeBool(forKey: "NSTemplate")
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(contentsof:)
    public convenience init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(contentsoffile:)
    public convenience init?(contentsOfFile fileName: String) { self.init(contentsOf: URL(fileURLWithPath: fileName)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(data:)
    public convenience init?(data: Data) {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        self.init(size: rep.size)
        addRepresentation(rep)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(dataignoringorientation:)
    public convenience init?(dataIgnoringOrientation data: Data) { self.init(data: data) }
    // SKIPPED (unknown module (? IconRef)): convenience init(iconRef: IconRef)
    /// Creates an instance initialized with the given resource name.
    /// 
    /// Do not call this initializer directly. Instead, initialize a variable or
    /// constant using an image literal.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(imageliteralresourcename:)
    /// The named image; a missing resource is a programming error, as with AppKit's literals.
    public required convenience init(imageLiteralResourceName name: String) {
        guard let image = NSImage(named: name) else { preconditionFailure("NSImage: no image resource named '\(name)'") }
        self.init(size: image._size)
        _representations = image._representations
        _drawingHandler = image._drawingHandler
        _drawingHandlerFlipped = image._drawingHandlerFlipped
        _isTemplate = image._isTemplate
        _name = name
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(named:)
    public convenience init?(named name: NSImage.Name) {
        if let cached = NSImage._named[name] {
            self.init(size: cached._size)
            _representations = cached._representations
            _drawingHandler = cached._drawingHandler
            _drawingHandlerFlipped = cached._drawingHandlerFlipped
            _isTemplate = cached._isTemplate
            _name = name
            return
        }
        guard let loaded = NSImage._loadNamed(name) else { return nil }
        NSImage._named[name] = loaded
        self.init(size: loaded._size)
        _representations = loaded._representations
        _drawingHandler = loaded._drawingHandler
        _drawingHandlerFlipped = loaded._drawingHandlerFlipped
        _isTemplate = loaded._isTemplate
        _name = name
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(pasteboard:)
    /// The first image type on the pasteboard, else the first image file URL on it.
    public convenience init?(pasteboard: NSPasteboard) {
        if let data = NSImageRep._imageData(on: pasteboard) {
            self.init(data: data)
        } else if let s = pasteboard.string(forType: .fileURL), let url = URL(string: s), let data = try? Data(contentsOf: url) {
            self.init(data: data)
        } else {
            return nil
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboardreading/init(pasteboardpropertylist:oftype:)
    /// The property list of an image type is its file data.
    public required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
        guard let data = propertyList as? Data, let rep = NSBitmapImageRep(data: data) else { return nil }
        _size = rep.size
        super.init()
        _representations = [rep]
    }
    // SKIPPED (DeveloperToolsSupport.ImageResource): convenience init(resource: ImageResource)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init()
    public override init() {
        _size = .zero
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(size:)
    public init(size: NSSize) {
        _size = size
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(size:flipped:drawinghandler:)
    public convenience init(size: NSSize, flipped drawingHandlerShouldBeCalledWithFlippedContext: Bool, drawingHandler: @escaping (NSRect) -> Bool) {
        self.init(size: size)
        _drawingHandler = drawingHandler
        _drawingHandlerFlipped = drawingHandlerShouldBeCalledWithFlippedContext
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(symbolname:bundle:variablevalue:)
    @available(macOS 13.0, *)
    /// Out of scope (ADR-0036): custom symbols are SF Symbols assets the port cannot render.
    public convenience init?(symbolName name: String, bundle: Bundle?, variableValue value: Double) { unimplemented("NSImage(symbolName:bundle:variableValue:) — custom symbol assets are not rendered") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(symbolname:variablevalue:)
    @available(macOS 13.0, *)
    public convenience init?(symbolName name: String, variableValue value: Double) { unimplemented("NSImage(symbolName:variableValue:) — custom symbol assets are not rendered") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(systemsymbolname:accessibilitydescription:)
    @available(macOS 11.0, *)
    /// A system symbol from the port's catalogue of drawn symbols; nil for a name it does
    /// not draw (ADR-0036 lists them), as for an unknown name on macOS.
    public convenience init?(systemSymbolName name: String, accessibilityDescription description: String?) {
        guard let symbol = MainActor.assumeIsolated({ _NSSystemImages.symbol(name) }) else { return nil }
        self.init(size: symbol._size)
        _drawingHandler = symbol._drawingHandler
        _drawingHandlerFlipped = symbol._drawingHandlerFlipped
        _isTemplate = symbol._isTemplate
        _accessibilityDescription = description
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(systemsymbolname:variablevalue:accessibilitydescription:)
    @available(macOS 13.0, *)
    /// As `init(systemSymbolName:accessibilityDescription:)`; the catalogue has no variable symbols.
    public convenience init?(systemSymbolName name: String, variableValue value: Double, accessibilityDescription description: String?) { self.init(systemSymbolName: name, accessibilityDescription: description) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/accessibilitydescription
    open var accessibilityDescription: String? {
        get { _accessibilityDescription }
        set { _accessibilityDescription = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/actiontemplatename
    static public var actionTemplateName: String { "NSActionTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/addrepresentation(_:)
    open func addRepresentation(_ imageRep: NSImageRep) {
        _representations.append(imageRep)
        if _size == .zero { _size = imageRep.size }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/addrepresentations(_:)
    open func addRepresentations(_ imageReps: [NSImageRep]) { for r in imageReps { addRepresentation(r) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/addtemplatename
    static public var addTemplateName: String { "NSAddTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/advancedname
    static public var advancedName: String { "NSAdvanced" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/alignmentrect
    open var alignmentRect: NSRect {
        get { _alignmentRect ?? NSRect(origin: .zero, size: _size) }
        set { _alignmentRect = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/applicationiconname
    static public var applicationIconName: String { "NSApplicationIcon" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/backgroundcolor
    open var backgroundColor: NSColor {
        get { _backgroundColor }
        set { _backgroundColor = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/bestrepresentation(for:context:hints:)
    /// The rep that best fits `rect` at the context's (or the main screen's) scale.
    open func bestRepresentation(for rect: NSRect, context referenceContext: NSGraphicsContext?, hints: [NSImageRep.HintKey : Any]?) -> NSImageRep? {
        MainActor.assumeIsolated {
            let scale: CGFloat
            if let ctx = referenceContext?.cgContext { scale = NSImage._deviceScale(ctx, hints: hints) }
            else if let t = hints?[.ctm] as? NSAffineTransform { scale = max(abs(t.transformStruct.m11), 0.01) }
            else { scale = NSScreen.main?.backingScaleFactor ?? 1 }
            let size = rect.isEmpty ? _size : rect.size
            return _bestRepresentation(pixels: NSSize(width: size.width * scale, height: size.height * scale), destination: size)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/bluetoothtemplatename
    static public var bluetoothTemplateName: String { "NSBluetoothTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/bonjourname
    static public var bonjourName: String { "NSBonjour" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/bookmarkstemplatename
    static public var bookmarksTemplateName: String { "NSBookmarksTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/cachemode
    open var cacheMode: NSImage.CacheMode {
        get { _cacheMode }
        set { _cacheMode = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/caninit(with:)
    public class func canInit(with pasteboard: NSPasteboard) -> Bool { NSImageRep.canInit(with: pasteboard) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/capinsets
    @available(macOS 10.10, *)
    open var capInsets: NSEdgeInsets {
        get { _capInsets }
        set { _capInsets = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/cautionname
    static public var cautionName: String { "NSCaution" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/cgimage(forproposedrect:context:hints:)
    open func cgImage(forProposedRect proposedDestRect: UnsafeMutablePointer<NSRect>?, context referenceContext: NSGraphicsContext?, hints: [NSImageRep.HintKey : Any]?) -> CGImage? {
        if !Thread.isMainThread {
            // Off the main actor (Nuke decompresses decoded images on its pipeline's tasks):
            // a bitmap rep's pixels need no rendering. Drawing handlers and other reps
            // render through the main-actor backend and are not available here.
            for rep in _representations {
                if let bitmap = rep as? NSBitmapImageRep, let image = bitmap._bitmapImage { return image }
            }
            return nil
        }
        return MainActor.assumeIsolated { _cgImage() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/colorpanelname
    static public var colorPanelName: String { "NSColorPanel" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/columnviewtemplatename
    static public var columnViewTemplateName: String { "NSColumnViewTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/computername
    static public var computerName: String { "NSComputer" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/delegate
    @MainActor open var delegate: (any NSImageDelegate)? {
        get { _delegate }
        set { _delegate = newValue as? (any NSImageDelegate & AnyObject) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/draw(at:from:operation:fraction:)
    open func draw(at point: NSPoint, from fromRect: NSRect, operation op: NSCompositingOperation, fraction delta: CGFloat) {
        let src = fromRect.isEmpty ? NSRect(origin: .zero, size: _size) : fromRect
        draw(in: NSRect(origin: point, size: src.size), from: src, operation: op, fraction: delta)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/draw(in:)
    open func draw(in rect: NSRect) { draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/draw(in:from:operation:fraction:)
    open func draw(in rect: NSRect, from fromRect: NSRect, operation op: NSCompositingOperation, fraction delta: CGFloat) {
        draw(in: rect, from: fromRect, operation: op, fraction: delta, respectFlipped: false, hints: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/draw(in:from:operation:fraction:respectflipped:hints:)
    /// Draws with the representation that best fits the destination at the context's
    /// scale. A whole-image draw of an image with `capInsets` (or `.tile`) draws nine
    /// slices: corners as they are, edges and centre stretched or tiled to fill (ADR-0036).
    /// Nothing to draw asks the delegate's `imageDidNotDraw(_:in:)` for a stand-in.
    open func draw(in dstSpacePortionRect: NSRect, from srcSpacePortionRect: NSRect, operation op: NSCompositingOperation, fraction requestedAlpha: CGFloat, respectFlipped respectContextIsFlipped: Bool, hints: [NSImageRep.HintKey : Any]?) {
        MainActor.assumeIsolated {
            guard let gc = NSGraphicsContext.current else { return }
            let scale = NSImage._deviceScale(gc.cgContext, hints: hints)
            guard let image = _cgImage(scale: scale, fitting: dstSpacePortionRect.size) else {
                if let standIn = delegate?.imageDidNotDraw(self, in: dstSpacePortionRect), standIn !== self {
                    standIn.draw(in: dstSpacePortionRect, from: srcSpacePortionRect, operation: op, fraction: requestedAlpha, respectFlipped: respectContextIsFlipped, hints: hints)
                }
                return
            }
            let whole = srcSpacePortionRect.isEmpty || srcSpacePortionRect == NSRect(origin: .zero, size: _size)
            if whole, _hasCapInsets || _resizingMode == .tile {
                _drawNineSlice(image, in: dstSpacePortionRect, operation: op, fraction: requestedAlpha, respectFlipped: respectContextIsFlipped)
                return
            }
            NSImageRep._drawImage(image, imageSize: _size, in: dstSpacePortionRect, from: srcSpacePortionRect, operation: op, fraction: requestedAlpha, respectFlipped: respectContextIsFlipped, hints: hints)
        }
    }

    private var _hasCapInsets: Bool { _capInsets.top != 0 || _capInsets.left != 0 || _capInsets.bottom != 0 || _capInsets.right != 0 }
    /// Device pixels per point of `ctx` (the CTM's scale, or the hint's transform).
    @MainActor internal static func _deviceScale(_ ctx: CGContext, hints: [NSImageRep.HintKey: Any]?) -> CGFloat {
        if let t = hints?[.ctm] as? NSAffineTransform { let m = t.transformStruct; return max(abs(m.m11), abs(m.m22), 0.01) }
        let m = ctx.ctm
        return max(0.01, (abs(m.a) + abs(m.d)) / 2 > 0 ? max(hypot(m.a, m.b), hypot(m.c, m.d)) : 1)
    }

    /// Nine slices of `image` into `dst` (see `draw(in:from:operation:fraction:respectFlipped:hints:)`).
    @MainActor private func _drawNineSlice(_ image: CGImage, in dst: NSRect, operation op: NSCompositingOperation, fraction: CGFloat, respectFlipped: Bool) {
        guard let gc = NSGraphicsContext.current, _size.width > 0, _size.height > 0 else { return }
        let ctx = gc.cgContext
        let i = _capInsets
        // Insets that do not fit the destination shrink in proportion, as AppKit's do.
        let fx = min(1, dst.width / max(0.0001, i.left + i.right)), fy = min(1, dst.height / max(0.0001, i.top + i.bottom))
        let l = i.left * fx, r = i.right * fx, t = i.top * fy, b = i.bottom * fy
        let flipped = respectFlipped && gc.isFlipped
        // Source columns/rows in image points (y up from the bottom of the image).
        let sx = [0, i.left, _size.width - i.right, _size.width]
        let sy = [0, i.bottom, _size.height - i.top, _size.height]
        // Destination columns/rows; in a flipped context the image's top is at minY.
        let dx = [dst.minX, dst.minX + l, dst.maxX - r, dst.maxX]
        let dyUp = [dst.minY, dst.minY + b, dst.maxY - t, dst.maxY]
        let dyFlipped = [dst.maxY, dst.maxY - b, dst.minY + t, dst.minY]
        let pxPerPt = (CGFloat(image.width) / _size.width, CGFloat(image.height) / _size.height)
        ctx.saveGState()
        let savedOp = gc.compositingOperation
        defer { gc.compositingOperation = savedOp; ctx.restoreGState() }
        if op != .sourceOver { gc.compositingOperation = op }
        if fraction < 1 { ctx.setAlpha(fraction) }
        for row in 0..<3 {
            for col in 0..<3 {
                let src = NSRect(x: sx[col], y: sy[row], width: sx[col + 1] - sx[col], height: sy[row + 1] - sy[row])
                let y0 = flipped ? min(dyFlipped[row], dyFlipped[row + 1]) : dyUp[row]
                let h = flipped ? abs(dyFlipped[row + 1] - dyFlipped[row]) : dyUp[row + 1] - dyUp[row]
                let d = NSRect(x: dx[col], y: y0, width: dx[col + 1] - dx[col], height: h)
                guard src.width > 0, src.height > 0, d.width > 0, d.height > 0 else { continue }
                // The slice's pixels (CGImage rows run top first).
                let crop = CGRect(x: src.minX * pxPerPt.0, y: (_size.height - src.maxY) * pxPerPt.1, width: src.width * pxPerPt.0, height: src.height * pxPerPt.1).integral
                guard let piece = NSImage._cropped(image, crop) else { continue }
                let tiles = _resizingMode == .tile && !(row != 1 && col != 1)
                ctx.saveGState()
                ctx.clip(to: d)
                if flipped { ctx.translateBy(x: 0, y: d.midY); ctx.scaleBy(x: 1, y: -1); ctx.translateBy(x: 0, y: -d.midY) }
                if tiles {
                    // Tile at the slice's own size from the slice's top-left corner.
                    let tw = col == 1 ? src.width : d.width, th = row == 1 ? src.height : d.height
                    var y = d.maxY - th
                    while y + th > d.minY {
                        var x = d.minX
                        while x < d.maxX { ctx.draw(piece, in: NSRect(x: x, y: y, width: tw, height: th)); x += tw }
                        y -= th
                    }
                } else {
                    ctx.draw(piece, in: d)
                }
                ctx.restoreGState()
            }
        }
    }

    internal static func _cropped(_ image: CGImage, _ rect: CGRect) -> CGImage? {
        #if os(Windows) || os(Linux)
        return NSBitmapImageRep._crop(image, to: rect)
        #else
        return image.cropping(to: rect)
        #endif
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/drawrepresentation(_:in:)
    open func drawRepresentation(_ imageRep: NSImageRep, in rect: NSRect) -> Bool { imageRep.draw(in: rect) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/enterfullscreentemplatename
    static public var enterFullScreenTemplateName: String { "NSEnterFullScreenTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/everyonename
    static public var everyoneName: String { "NSEveryone" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/exitfullscreentemplatename
    static public var exitFullScreenTemplateName: String { "NSExitFullScreenTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/flowviewtemplatename
    static public var flowViewTemplateName: String { "NSFlowViewTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/folderburnablename
    static public var folderBurnableName: String { "NSFolderBurnable" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/foldername
    static public var folderName: String { "NSFolder" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/foldersmartname
    static public var folderSmartName: String { "NSFolderSmart" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/followlinkfreestandingtemplatename
    static public var followLinkFreestandingTemplateName: String { "NSFollowLinkFreestandingTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/fontpanelname
    static public var fontPanelName: String { "NSFontPanel" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/gobacktemplatename
    @available(macOS 10.12, *)
    static public var goBackTemplateName: String { "NSGoBackTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/goforwardtemplatename
    @available(macOS 10.12, *)
    static public var goForwardTemplateName: String { "NSGoForwardTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/golefttemplatename
    static public var goLeftTemplateName: String { "NSGoLeftTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/gorighttemplatename
    static public var goRightTemplateName: String { "NSGoRightTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/hittest(_:withdestinationrect:context:hints:flipped:)
    /// Whether `testRectDestSpace` covers any pixel of the image (drawn in
    /// `imageRectDestSpace`) that is not fully transparent.
    open func hitTest(_ testRectDestSpace: NSRect, withDestinationRect imageRectDestSpace: NSRect, context: NSGraphicsContext?, hints: [NSImageRep.HintKey : Any]?, flipped: Bool) -> Bool {
        let hit = testRectDestSpace.intersection(imageRectDestSpace)
        guard !hit.isEmpty || (testRectDestSpace.width == 0 && imageRectDestSpace.contains(testRectDestSpace.origin)),
              imageRectDestSpace.width > 0, imageRectDestSpace.height > 0 else { return false }
        guard let image = MainActor.assumeIsolated({ _cgImage(fitting: imageRectDestSpace.size) }) else { return false }
        let px = NSBitmapImageRep._rgbaPixels(of: image)
        guard px.hasAlpha else { return true }
        let sx = CGFloat(px.width) / imageRectDestSpace.width, sy = CGFloat(px.height) / imageRectDestSpace.height
        let r = hit.isEmpty ? NSRect(origin: testRectDestSpace.origin, size: NSSize(width: 1 / sx, height: 1 / sy)) : hit
        let x0 = max(0, Int(((r.minX - imageRectDestSpace.minX) * sx).rounded(.down))), x1 = min(px.width, Int(((r.maxX - imageRectDestSpace.minX) * sx).rounded(.up)))
        // Pixel rows run top first; in a flipped destination the top is at minY.
        let top = { (y: CGFloat) in flipped ? (y - imageRectDestSpace.minY) * sy : (imageRectDestSpace.maxY - y) * sy }
        let y0 = max(0, Int(min(top(r.minY), top(r.maxY)).rounded(.down))), y1 = min(px.height, Int(max(top(r.minY), top(r.maxY)).rounded(.up)))
        guard x0 < x1, y0 < y1 else { return false }
        for y in y0..<y1 { for x in x0..<x1 where px.bytes[(y * px.width + x) * 4 + 3] > 0 { return true } }
        return false
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/hometemplatename
    static public var homeTemplateName: String { "NSHomeTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/ichattheatertemplatename
    static public var iChatTheaterTemplateName: String { "NSIChatTheaterTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/iconviewtemplatename
    static public var iconViewTemplateName: String { "NSIconViewTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/imagefiletypes()
    public class func imageFileTypes() -> [String] { NSImageRep.imageFileTypes() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/imagepasteboardtypes()
    public class func imagePasteboardTypes() -> [NSPasteboard.PasteboardType] { NSImageRep.imagePasteboardTypes() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/imagetypes
    /// Every registered rep class's types.
    class public var imageTypes: [String] { NSImageRep._unique(NSImageRep._registeredClasses.flatMap { $0.imageTypes }) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/imageunfilteredfiletypes()
    public class func imageUnfilteredFileTypes() -> [String] { NSImageRep.imageUnfilteredFileTypes() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/imageunfilteredpasteboardtypes()
    public class func imageUnfilteredPasteboardTypes() -> [NSPasteboard.PasteboardType] { NSImageRep.imageUnfilteredPasteboardTypes() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/imageunfilteredtypes
    class public var imageUnfilteredTypes: [String] { NSImageRep._unique(NSImageRep._registeredClasses.flatMap { $0.imageUnfilteredTypes }) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/infoname
    static public var infoName: String { "NSInfo" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/invaliddatafreestandingtemplatename
    static public var invalidDataFreestandingTemplateName: String { "NSInvalidDataFreestandingTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/istemplate
    open var isTemplate: Bool {
        get { _isTemplate }
        set { _isTemplate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/isvalid
    open var isValid: Bool { !_representations.isEmpty || _drawingHandler != nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/layercontents(forcontentsscale:)
    /// The pixels for a layer at `layerContentsScale` (a CGImage), as layer contents.
    open func layerContents(forContentsScale layerContentsScale: CGFloat) -> Any {
        MainActor.assumeIsolated { _cgImage(scale: layerContentsScale) as Any }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/leftfacingtriangletemplatename
    static public var leftFacingTriangleTemplateName: String { "NSLeftFacingTriangleTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/listviewtemplatename
    static public var listViewTemplateName: String { "NSListViewTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/locale
    @available(macOS 14.0, *)
    @MainActor open var locale: Locale? { _locale }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/lockfocus()
    open func lockFocus() { lockFocusFlipped(false) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/lockfocusflipped(_:)
    open func lockFocusFlipped(_ flipped: Bool) {
        MainActor.assumeIsolated {
            guard let surface = Platform.backend.image.makeOffscreen(size: _size, scale: 2) else { return }
            if let existing = _cgImage() { surface.context.draw(existing, in: NSRect(origin: .zero, size: _size)) }
            _focusSurface = surface
            _savedContext = NSGraphicsContext.current
            if flipped {
                surface.context.translateBy(x: 0, y: _size.height)
                surface.context.scaleBy(x: 1, y: -1)
            }
            NSGraphicsContext.current = NSGraphicsContext(cgContext: surface.context, flipped: flipped)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/locklockedtemplatename
    static public var lockLockedTemplateName: String { "NSLockLockedTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/lockunlockedtemplatename
    static public var lockUnlockedTemplateName: String { "NSLockUnlockedTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/matchesonmultipleresolution
    open var matchesOnMultipleResolution: Bool {
        get { _matchesOnMultipleResolution }
        set { _matchesOnMultipleResolution = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/matchesonlyonbestfittingaxis
    open var matchesOnlyOnBestFittingAxis: Bool {
        get { _matchesOnlyOnBestFittingAxis }
        set { _matchesOnlyOnBestFittingAxis = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/menumixedstatetemplatename
    static public var menuMixedStateTemplateName: String { "NSMenuMixedStateTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/menuonstatetemplatename
    static public var menuOnStateTemplateName: String { "NSMenuOnStateTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/mobilemename
    static public var mobileMeName: String { "NSMobileMe" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/multipledocumentsname
    static public var multipleDocumentsName: String { "NSMultipleDocuments" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/name()
    open func name() -> NSImage.Name? { _name }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/networkname
    static public var networkName: String { "NSNetwork" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/pathtemplatename
    static public var pathTemplateName: String { "NSPathTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/preferencesgeneralname
    static public var preferencesGeneralName: String { "NSPreferencesGeneral" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/preferscolormatch
    open var prefersColorMatch: Bool {
        get { _prefersColorMatch }
        set { _prefersColorMatch = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/quicklooktemplatename
    static public var quickLookTemplateName: String { "NSQuickLookTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/recache()
    open func recache() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/recommendedlayercontentsscale(_:)
    /// The preferred scale, unless every representation is a bitmap with fewer pixels
    /// (then the scale of the densest one, at least 1).
    open func recommendedLayerContentsScale(_ preferredContentsScale: CGFloat) -> CGFloat {
        guard _drawingHandler == nil, !_representations.isEmpty, _size.width > 0,
              _representations.allSatisfy({ $0 is NSBitmapImageRep }) else { return preferredContentsScale }
        let densest = _representations.map { CGFloat($0.pixelsWide) / _size.width }.max() ?? 1
        return max(1, min(preferredContentsScale, densest.rounded(.up)))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/refreshfreestandingtemplatename
    static public var refreshFreestandingTemplateName: String { "NSRefreshFreestandingTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/refreshtemplatename
    static public var refreshTemplateName: String { "NSRefreshTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/removerepresentation(_:)
    open func removeRepresentation(_ imageRep: NSImageRep) { _representations.removeAll { $0 === imageRep } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/removetemplatename
    static public var removeTemplateName: String { "NSRemoveTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/representations
    open var representations: [NSImageRep] { _representations }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/resizingmode
    @available(macOS 10.10, *)
    open var resizingMode: NSImage.ResizingMode {
        get { _resizingMode }
        set { _resizingMode = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/revealfreestandingtemplatename
    static public var revealFreestandingTemplateName: String { "NSRevealFreestandingTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/rightfacingtriangletemplatename
    static public var rightFacingTriangleTemplateName: String { "NSRightFacingTriangleTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/setname(_:)
    open func setName(_ string: NSImage.Name?) -> Bool {
        if let old = _name { NSImage._named[old] = nil }
        _name = string
        if let string { NSImage._named[string] = self }
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/sharetemplatename
    static public var shareTemplateName: String { "NSShareTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/size
    open var size: NSSize {
        get { _size }
        set { _size = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/slideshowtemplatename
    static public var slideshowTemplateName: String { "NSSlideshowTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/smartbadgetemplatename
    static public var smartBadgeTemplateName: String { "NSSmartBadgeTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/statusavailablename
    static public var statusAvailableName: String { "NSStatusAvailable" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/statusnonename
    static public var statusNoneName: String { "NSStatusNone" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/statuspartiallyavailablename
    static public var statusPartiallyAvailableName: String { "NSStatusPartiallyAvailable" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/statusunavailablename
    static public var statusUnavailableName: String { "NSStatusUnavailable" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/stopprogressfreestandingtemplatename
    static public var stopProgressFreestandingTemplateName: String { "NSStopProgressFreestandingTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/stopprogresstemplatename
    static public var stopProgressTemplateName: String { "NSStopProgressTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/symbolconfiguration
    @available(macOS 12.0, *)
    /// What `withSymbolConfiguration(_:)` gave the image. An image that has none would
    /// answer a default configuration, which needs `SymbolConfiguration` (a generated stub).
    @MainActor open var symbolConfiguration: NSImage.SymbolConfiguration {
        if let c = _symbolConfiguration { return c }
        unimplemented("NSImage.symbolConfiguration default — NSImage.SymbolConfiguration is not modelled")
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/tiffrepresentation
    open var tiffRepresentation: Data? {
        // Bitmap reps as they are (one TIFF page each); a drawn image rendered at 1x and 2x.
        MainActor.assumeIsolated {
            let bitmaps = _representations.compactMap { $0._renderedBitmap() }
            if !bitmaps.isEmpty { return NSBitmapImageRep.tiffRepresentationOfImageReps(in: bitmaps) }
            guard let image = _cgImage() else { return nil }
            let rep = NSBitmapImageRep(cgImage: image)
            rep.size = _size
            return rep.tiffRepresentation
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/tiffrepresentation(using:factor:)
    open func tiffRepresentation(using comp: NSBitmapImageRep.TIFFCompression, factor: Float) -> Data? { tiffRepresentation }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaradddetailtemplatename
    @available(macOS 10.12, *)
    static public var touchBarAddDetailTemplateName: String { "NSTouchBarAddDetailTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaraddtemplatename
    @available(macOS 10.12, *)
    static public var touchBarAddTemplateName: String { "NSTouchBarAddTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaralarmtemplatename
    @available(macOS 10.12, *)
    static public var touchBarAlarmTemplateName: String { "NSTouchBarAlarmTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaraudioinputmutetemplatename
    @available(macOS 10.12, *)
    static public var touchBarAudioInputMuteTemplateName: String { "NSTouchBarAudioInputMuteTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaraudioinputtemplatename
    @available(macOS 10.12, *)
    static public var touchBarAudioInputTemplateName: String { "NSTouchBarAudioInputTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaraudiooutputmutetemplatename
    @available(macOS 10.12, *)
    static public var touchBarAudioOutputMuteTemplateName: String { "NSTouchBarAudioOutputMuteTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaraudiooutputvolumehightemplatename
    @available(macOS 10.12, *)
    static public var touchBarAudioOutputVolumeHighTemplateName: String { "NSTouchBarAudioOutputVolumeHighTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaraudiooutputvolumelowtemplatename
    @available(macOS 10.12, *)
    static public var touchBarAudioOutputVolumeLowTemplateName: String { "NSTouchBarAudioOutputVolumeLowTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaraudiooutputvolumemediumtemplatename
    @available(macOS 10.12, *)
    static public var touchBarAudioOutputVolumeMediumTemplateName: String { "NSTouchBarAudioOutputVolumeMediumTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaraudiooutputvolumeofftemplatename
    @available(macOS 10.12, *)
    static public var touchBarAudioOutputVolumeOffTemplateName: String { "NSTouchBarAudioOutputVolumeOffTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarbookmarkstemplatename
    @available(macOS 10.12, *)
    static public var touchBarBookmarksTemplateName: String { "NSTouchBarBookmarksTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarcolorpickerfillname
    @available(macOS 10.12, *)
    static public var touchBarColorPickerFillName: String { "NSTouchBarColorPickerFill" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarcolorpickerfontname
    @available(macOS 10.12, *)
    static public var touchBarColorPickerFontName: String { "NSTouchBarColorPickerFont" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarcolorpickerstrokename
    @available(macOS 10.12, *)
    static public var touchBarColorPickerStrokeName: String { "NSTouchBarColorPickerStroke" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarcommunicationaudiotemplatename
    @available(macOS 10.12, *)
    static public var touchBarCommunicationAudioTemplateName: String { "NSTouchBarCommunicationAudioTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarcommunicationvideotemplatename
    @available(macOS 10.12, *)
    static public var touchBarCommunicationVideoTemplateName: String { "NSTouchBarCommunicationVideoTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarcomposetemplatename
    @available(macOS 10.12, *)
    static public var touchBarComposeTemplateName: String { "NSTouchBarComposeTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbardeletetemplatename
    @available(macOS 10.12, *)
    static public var touchBarDeleteTemplateName: String { "NSTouchBarDeleteTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbardownloadtemplatename
    @available(macOS 10.12, *)
    static public var touchBarDownloadTemplateName: String { "NSTouchBarDownloadTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarenterfullscreentemplatename
    @available(macOS 10.12, *)
    static public var touchBarEnterFullScreenTemplateName: String { "NSTouchBarEnterFullScreenTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarexitfullscreentemplatename
    @available(macOS 10.12, *)
    static public var touchBarExitFullScreenTemplateName: String { "NSTouchBarExitFullScreenTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarfastforwardtemplatename
    @available(macOS 10.12, *)
    static public var touchBarFastForwardTemplateName: String { "NSTouchBarFastForwardTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarfoldercopytotemplatename
    @available(macOS 10.12, *)
    static public var touchBarFolderCopyToTemplateName: String { "NSTouchBarFolderCopyToTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarfoldermovetotemplatename
    @available(macOS 10.12, *)
    static public var touchBarFolderMoveToTemplateName: String { "NSTouchBarFolderMoveToTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarfoldertemplatename
    @available(macOS 10.12, *)
    static public var touchBarFolderTemplateName: String { "NSTouchBarFolderTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbargetinfotemplatename
    @available(macOS 10.12, *)
    static public var touchBarGetInfoTemplateName: String { "NSTouchBarGetInfoTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbargobacktemplatename
    @available(macOS 10.12, *)
    static public var touchBarGoBackTemplateName: String { "NSTouchBarGoBackTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbargodowntemplatename
    @available(macOS 10.12, *)
    static public var touchBarGoDownTemplateName: String { "NSTouchBarGoDownTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbargoforwardtemplatename
    @available(macOS 10.12, *)
    static public var touchBarGoForwardTemplateName: String { "NSTouchBarGoForwardTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbargouptemplatename
    @available(macOS 10.12, *)
    static public var touchBarGoUpTemplateName: String { "NSTouchBarGoUpTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarhistorytemplatename
    @available(macOS 10.12, *)
    static public var touchBarHistoryTemplateName: String { "NSTouchBarHistoryTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbariconviewtemplatename
    @available(macOS 10.12, *)
    static public var touchBarIconViewTemplateName: String { "NSTouchBarIconViewTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarlistviewtemplatename
    @available(macOS 10.12, *)
    static public var touchBarListViewTemplateName: String { "NSTouchBarListViewTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarmailtemplatename
    @available(macOS 10.12, *)
    static public var touchBarMailTemplateName: String { "NSTouchBarMailTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarnewfoldertemplatename
    @available(macOS 10.12, *)
    static public var touchBarNewFolderTemplateName: String { "NSTouchBarNewFolderTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarnewmessagetemplatename
    @available(macOS 10.12, *)
    static public var touchBarNewMessageTemplateName: String { "NSTouchBarNewMessageTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaropeninbrowsertemplatename
    @available(macOS 10.12, *)
    static public var touchBarOpenInBrowserTemplateName: String { "NSTouchBarOpenInBrowserTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarpausetemplatename
    @available(macOS 10.12, *)
    static public var touchBarPauseTemplateName: String { "NSTouchBarPauseTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarplaypausetemplatename
    @available(macOS 10.12, *)
    static public var touchBarPlayPauseTemplateName: String { "NSTouchBarPlayPauseTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarplaytemplatename
    @available(macOS 10.12, *)
    static public var touchBarPlayTemplateName: String { "NSTouchBarPlayTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarplayheadtemplatename
    @available(macOS 10.12, *)
    static public var touchBarPlayheadTemplateName: String { "NSTouchBarPlayheadTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarquicklooktemplatename
    @available(macOS 10.12, *)
    static public var touchBarQuickLookTemplateName: String { "NSTouchBarQuickLookTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarrecordstarttemplatename
    @available(macOS 10.12, *)
    static public var touchBarRecordStartTemplateName: String { "NSTouchBarRecordStartTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarrecordstoptemplatename
    @available(macOS 10.12, *)
    static public var touchBarRecordStopTemplateName: String { "NSTouchBarRecordStopTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarrefreshtemplatename
    @available(macOS 10.12, *)
    static public var touchBarRefreshTemplateName: String { "NSTouchBarRefreshTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarremovetemplatename
    @available(macOS 10.13, *)
    static public var touchBarRemoveTemplateName: String { "NSTouchBarRemoveTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarrewindtemplatename
    @available(macOS 10.12, *)
    static public var touchBarRewindTemplateName: String { "NSTouchBarRewindTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarrotatelefttemplatename
    @available(macOS 10.12, *)
    static public var touchBarRotateLeftTemplateName: String { "NSTouchBarRotateLeftTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarrotaterighttemplatename
    @available(macOS 10.12, *)
    static public var touchBarRotateRightTemplateName: String { "NSTouchBarRotateRightTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarsearchtemplatename
    @available(macOS 10.12, *)
    static public var touchBarSearchTemplateName: String { "NSTouchBarSearchTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarsharetemplatename
    @available(macOS 10.12, *)
    static public var touchBarShareTemplateName: String { "NSTouchBarShareTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarsidebartemplatename
    @available(macOS 10.12, *)
    static public var touchBarSidebarTemplateName: String { "NSTouchBarSidebarTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarskipahead15secondstemplatename
    @available(macOS 10.12, *)
    static public var touchBarSkipAhead15SecondsTemplateName: String { "NSTouchBarSkipAhead15SecondsTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarskipahead30secondstemplatename
    @available(macOS 10.12, *)
    static public var touchBarSkipAhead30SecondsTemplateName: String { "NSTouchBarSkipAhead30SecondsTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarskipaheadtemplatename
    @available(macOS 10.12, *)
    static public var touchBarSkipAheadTemplateName: String { "NSTouchBarSkipAheadTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarskipback15secondstemplatename
    @available(macOS 10.12, *)
    static public var touchBarSkipBack15SecondsTemplateName: String { "NSTouchBarSkipBack15SecondsTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarskipback30secondstemplatename
    @available(macOS 10.12, *)
    static public var touchBarSkipBack30SecondsTemplateName: String { "NSTouchBarSkipBack30SecondsTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarskipbacktemplatename
    @available(macOS 10.12, *)
    static public var touchBarSkipBackTemplateName: String { "NSTouchBarSkipBackTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarskiptoendtemplatename
    @available(macOS 10.12, *)
    static public var touchBarSkipToEndTemplateName: String { "NSTouchBarSkipToEndTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarskiptostarttemplatename
    @available(macOS 10.12, *)
    static public var touchBarSkipToStartTemplateName: String { "NSTouchBarSkipToStartTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarslideshowtemplatename
    @available(macOS 10.12, *)
    static public var touchBarSlideshowTemplateName: String { "NSTouchBarSlideshowTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartagicontemplatename
    @available(macOS 10.12, *)
    static public var touchBarTagIconTemplateName: String { "NSTouchBarTagIconTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextboldtemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextBoldTemplateName: String { "NSTouchBarTextBoldTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextboxtemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextBoxTemplateName: String { "NSTouchBarTextBoxTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextcenteraligntemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextCenterAlignTemplateName: String { "NSTouchBarTextCenterAlignTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextitalictemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextItalicTemplateName: String { "NSTouchBarTextItalicTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextjustifiedaligntemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextJustifiedAlignTemplateName: String { "NSTouchBarTextJustifiedAlignTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextleftaligntemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextLeftAlignTemplateName: String { "NSTouchBarTextLeftAlignTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextlisttemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextListTemplateName: String { "NSTouchBarTextListTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextrightaligntemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextRightAlignTemplateName: String { "NSTouchBarTextRightAlignTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextstrikethroughtemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextStrikethroughTemplateName: String { "NSTouchBarTextStrikethroughTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextunderlinetemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextUnderlineTemplateName: String { "NSTouchBarTextUnderlineTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaruseraddtemplatename
    @available(macOS 10.12, *)
    static public var touchBarUserAddTemplateName: String { "NSTouchBarUserAddTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarusergrouptemplatename
    @available(macOS 10.12, *)
    static public var touchBarUserGroupTemplateName: String { "NSTouchBarUserGroupTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarusertemplatename
    @available(macOS 10.12, *)
    static public var touchBarUserTemplateName: String { "NSTouchBarUserTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarvolumedowntemplatename
    @available(macOS 10.12, *)
    static public var touchBarVolumeDownTemplateName: String { "NSTouchBarVolumeDownTemplate" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarvolumeuptemplatename
    @available(macOS 10.12, *)
    static public var touchBarVolumeUpTemplateName: String { "NSTouchBarVolumeUpTemplate" }
    // SKIPPED (CoreTransferable.TransferRepresentation): static var transferRepresentation: some TransferRepresentation { get }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/trashemptyname
    static public var trashEmptyName: String { "NSTrashEmpty" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/trashfullname
    static public var trashFullName: String { "NSTrashFull" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/unlockfocus()
    open func unlockFocus() {
        MainActor.assumeIsolated {
            guard let surface = _focusSurface else { return }
            NSGraphicsContext.current = _savedContext
            _savedContext = nil
            _focusSurface = nil
            if let image = surface.makeImage() {
                _drawingHandler = nil
                _representations = [NSBitmapImageRep(cgImage: image)]
                _representations[0].size = _size
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/useraccountsname
    static public var userAccountsName: String { "NSUserAccounts" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/usergroupname
    static public var userGroupName: String { "NSUserGroup" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/userguestname
    static public var userGuestName: String { "NSUserGuest" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/username
    static public var userName: String { "NSUser" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/usesepsonresolutionmismatch
    open var usesEPSOnResolutionMismatch: Bool {
        get { _usesEPSOnResolutionMismatch }
        set { _usesEPSOnResolutionMismatch = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/withlocale(_:)
    @available(macOS 14.0, *)
    /// A copy for `locale` (the port has no localized image variants, so the pixels match).
    @MainActor open func withLocale(_ locale: Locale?) -> NSImage {
        let c = copy() as! NSImage
        c._locale = locale
        return c
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/withsymbolconfiguration(_:)
    @available(macOS 11.0, *)
    /// A copy carrying `configuration`; nil unless the image is a symbol (the configuration's
    /// point size and weight are not applied: `SymbolConfiguration` is a generated stub).
    @MainActor open func withSymbolConfiguration(_ configuration: NSImage.SymbolConfiguration) -> NSImage? {
        guard _drawingHandler != nil, _isTemplate else { return nil }
        let c = copy() as! NSImage
        c._symbolConfiguration = configuration
        return c
    }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any {
        let c = NSImage(size: _size)
        c._representations = _representations
        c._isTemplate = _isTemplate
        c._drawingHandler = _drawingHandler
        c._drawingHandlerFlipped = _drawingHandlerFlipped
        return c
    }
    // Requirement of NSSecureCoding
    class public var supportsSecureCoding: Bool { true }
    // Requirement of NSCoding
    /// Archives the size, the template flag and a TIFF of the representations.
    open func encode(with coder: NSCoder) {
        coder.encode(NSValue(size: _size), forKey: "NSSize")
        coder.encode(_isTemplate, forKey: "NSTemplate")
        if let tiff = tiffRepresentation { coder.encode(tiff, forKey: "NSTIFFRepresentation") }
    }
    // Requirement of NSItemProviderReading
    static public var readableTypeIdentifiersForItemProvider: [String] { NSImage.imageTypes }
    // Requirement of NSItemProviderReading
    public static func object(withItemProviderData data: Data, typeIdentifier: String) throws -> Self {
        guard let rep = NSBitmapImageRep(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        guard let image = NSImage(data: data) as? Self else { throw CocoaError(.fileReadCorruptFile) }
        _ = rep
        return image
    }
    // Requirement of NSItemProviderWriting
    /// TIFF first (AppKit's), then PNG.
    static public var writableTypeIdentifiersForItemProvider: [String] { ["public.tiff", "public.png"] }
    // Requirement of NSItemProviderWriting
    open func loadData(withTypeIdentifier typeIdentifier: String, forItemProviderCompletionHandler completionHandler: @escaping (Data?, (any Error)?) -> Void) -> Progress? {
        let progress = Progress(totalUnitCount: 1)
        let data: Data?
        if typeIdentifier == "public.png" {
            data = MainActor.assumeIsolated { _cgImage().flatMap { Platform.imageCodec.encode($0, format: "public.png", quality: 1) } }
        } else if typeIdentifier == "public.tiff" {
            data = tiffRepresentation
        } else {
            data = nil
        }
        progress.completedUnitCount = 1
        completionHandler(data, data == nil ? CocoaError(.fileWriteUnknown) : nil)
        return progress
    }
}
