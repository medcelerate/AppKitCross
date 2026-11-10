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

    open override var description: String { "<NSImage \(_name.map { "'\($0)' " } ?? "")size=\(_size) reps=\(_representations.count)>" }

    /// The pixels to draw, rendering drawing handlers and template images as needed.
    @MainActor internal func _cgImage(scale: CGFloat = 1) -> CGImage? {
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
        for rep in _representations {
            if let image = rep._cgImage() { return image }
        }
        return nil
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
    public required init(coder: NSCoder) { unimplemented() }
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
    public required convenience init(imageLiteralResourceName name: String) { unimplemented() }
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
        _name = name
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(pasteboard:)
    public convenience init?(pasteboard: NSPasteboard) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspasteboardreading/init(pasteboardpropertylist:oftype:)
    public required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) { unimplemented() }
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
    public convenience init?(symbolName name: String, bundle: Bundle?, variableValue value: Double) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(symbolname:variablevalue:)
    @available(macOS 13.0, *)
    public convenience init?(symbolName name: String, variableValue value: Double) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(systemsymbolname:accessibilitydescription:)
    @available(macOS 11.0, *)
    public convenience init?(systemSymbolName name: String, accessibilityDescription description: String?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/init(systemsymbolname:variablevalue:accessibilitydescription:)
    @available(macOS 13.0, *)
    public convenience init?(systemSymbolName name: String, variableValue value: Double, accessibilityDescription description: String?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/accessibilitydescription
    open var accessibilityDescription: String? {
        get { _accessibilityDescription }
        set { _accessibilityDescription = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/actiontemplatename
    static public var actionTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/addrepresentation(_:)
    open func addRepresentation(_ imageRep: NSImageRep) {
        _representations.append(imageRep)
        if _size == .zero { _size = imageRep.size }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/addrepresentations(_:)
    open func addRepresentations(_ imageReps: [NSImageRep]) { for r in imageReps { addRepresentation(r) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/addtemplatename
    static public var addTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/advancedname
    static public var advancedName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/alignmentrect
    open var alignmentRect: NSRect {
        get { _alignmentRect ?? NSRect(origin: .zero, size: _size) }
        set { _alignmentRect = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/applicationiconname
    static public var applicationIconName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/backgroundcolor
    open var backgroundColor: NSColor {
        get { _backgroundColor }
        set { _backgroundColor = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/bestrepresentation(for:context:hints:)
    open func bestRepresentation(for rect: NSRect, context referenceContext: NSGraphicsContext?, hints: [NSImageRep.HintKey : Any]?) -> NSImageRep? {
        _representations.max { ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/bluetoothtemplatename
    static public var bluetoothTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/bonjourname
    static public var bonjourName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/bookmarkstemplatename
    static public var bookmarksTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/cachemode
    open var cacheMode: NSImage.CacheMode {
        get { _cacheMode }
        set { _cacheMode = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/caninit(with:)
    public class func canInit(with pasteboard: NSPasteboard) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/capinsets
    @available(macOS 10.10, *)
    open var capInsets: NSEdgeInsets {
        get { _capInsets }
        set { _capInsets = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/cautionname
    static public var cautionName: String { unimplemented() }
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
    static public var colorPanelName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/columnviewtemplatename
    static public var columnViewTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/computername
    static public var computerName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/delegate
    open var delegate: (any NSImageDelegate)? {
        get { unimplemented() }
        set { unimplemented() }
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
    open func draw(in dstSpacePortionRect: NSRect, from srcSpacePortionRect: NSRect, operation op: NSCompositingOperation, fraction requestedAlpha: CGFloat, respectFlipped respectContextIsFlipped: Bool, hints: [NSImageRep.HintKey : Any]?) {
        MainActor.assumeIsolated {
            guard let gc = NSGraphicsContext.current, let image = _cgImage() else { return }
            let ctx = gc.cgContext
            ctx.saveGState()
            defer { ctx.restoreGState() }
            if requestedAlpha < 1 { ctx.setAlpha(requestedAlpha) }
            var dst = dstSpacePortionRect
            // Sub-rect of the source (in image points) via clipping and scaling.
            if !srcSpacePortionRect.isEmpty && srcSpacePortionRect != NSRect(origin: .zero, size: _size) {
                ctx.clip(to: dst)
                let sx = dst.width / srcSpacePortionRect.width, sy = dst.height / srcSpacePortionRect.height
                dst = NSRect(x: dst.minX - srcSpacePortionRect.minX * sx, y: dst.minY - srcSpacePortionRect.minY * sy, width: _size.width * sx, height: _size.height * sy)
            }
            if respectContextIsFlipped && gc.isFlipped {
                // CoreGraphics would draw upside-down in a flipped context; counter it.
                ctx.translateBy(x: 0, y: dst.midY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.translateBy(x: 0, y: -dst.midY)
            }
            ctx.draw(image, in: dst)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/drawrepresentation(_:in:)
    open func drawRepresentation(_ imageRep: NSImageRep, in rect: NSRect) -> Bool { imageRep.draw(in: rect) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/enterfullscreentemplatename
    static public var enterFullScreenTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/everyonename
    static public var everyoneName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/exitfullscreentemplatename
    static public var exitFullScreenTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/flowviewtemplatename
    static public var flowViewTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/folderburnablename
    static public var folderBurnableName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/foldername
    static public var folderName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/foldersmartname
    static public var folderSmartName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/followlinkfreestandingtemplatename
    static public var followLinkFreestandingTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/fontpanelname
    static public var fontPanelName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/gobacktemplatename
    @available(macOS 10.12, *)
    static public var goBackTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/goforwardtemplatename
    @available(macOS 10.12, *)
    static public var goForwardTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/golefttemplatename
    static public var goLeftTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/gorighttemplatename
    static public var goRightTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/hittest(_:withdestinationrect:context:hints:flipped:)
    open func hitTest(_ testRectDestSpace: NSRect, withDestinationRect imageRectDestSpace: NSRect, context: NSGraphicsContext?, hints: [NSImageRep.HintKey : Any]?, flipped: Bool) -> Bool { testRectDestSpace.intersects(imageRectDestSpace) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/hometemplatename
    static public var homeTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/ichattheatertemplatename
    static public var iChatTheaterTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/iconviewtemplatename
    static public var iconViewTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/imagefiletypes()
    public class func imageFileTypes() -> [String] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/imagepasteboardtypes()
    public class func imagePasteboardTypes() -> [NSPasteboard.PasteboardType] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/imagetypes
    class public var imageTypes: [String] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/imageunfilteredfiletypes()
    public class func imageUnfilteredFileTypes() -> [String] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/imageunfilteredpasteboardtypes()
    public class func imageUnfilteredPasteboardTypes() -> [NSPasteboard.PasteboardType] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/imageunfilteredtypes
    class public var imageUnfilteredTypes: [String] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/infoname
    static public var infoName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/invaliddatafreestandingtemplatename
    static public var invalidDataFreestandingTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/istemplate
    open var isTemplate: Bool {
        get { _isTemplate }
        set { _isTemplate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/isvalid
    open var isValid: Bool { !_representations.isEmpty || _drawingHandler != nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/layercontents(forcontentsscale:)
    open func layerContents(forContentsScale layerContentsScale: CGFloat) -> Any { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/leftfacingtriangletemplatename
    static public var leftFacingTriangleTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/listviewtemplatename
    static public var listViewTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/locale
    @available(macOS 14.0, *)
    open var locale: Locale? { unimplemented() }
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
    static public var lockLockedTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/lockunlockedtemplatename
    static public var lockUnlockedTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/matchesonmultipleresolution
    open var matchesOnMultipleResolution: Bool {
        get { _matchesOnMultipleResolution }
        set { _matchesOnMultipleResolution = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/matchesonlyonbestfittingaxis
    open var matchesOnlyOnBestFittingAxis: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/menumixedstatetemplatename
    static public var menuMixedStateTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/menuonstatetemplatename
    static public var menuOnStateTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/mobilemename
    static public var mobileMeName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/multipledocumentsname
    static public var multipleDocumentsName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/name()
    open func name() -> NSImage.Name? { _name }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/networkname
    static public var networkName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/pathtemplatename
    static public var pathTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/preferencesgeneralname
    static public var preferencesGeneralName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/preferscolormatch
    open var prefersColorMatch: Bool {
        get { _prefersColorMatch }
        set { _prefersColorMatch = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/quicklooktemplatename
    static public var quickLookTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/recache()
    open func recache() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/recommendedlayercontentsscale(_:)
    open func recommendedLayerContentsScale(_ preferredContentsScale: CGFloat) -> CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/refreshfreestandingtemplatename
    static public var refreshFreestandingTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/refreshtemplatename
    static public var refreshTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/removerepresentation(_:)
    open func removeRepresentation(_ imageRep: NSImageRep) { _representations.removeAll { $0 === imageRep } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/removetemplatename
    static public var removeTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/representations
    open var representations: [NSImageRep] { _representations }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/resizingmode
    @available(macOS 10.10, *)
    open var resizingMode: NSImage.ResizingMode {
        get { _resizingMode }
        set { _resizingMode = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/revealfreestandingtemplatename
    static public var revealFreestandingTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/rightfacingtriangletemplatename
    static public var rightFacingTriangleTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/setname(_:)
    open func setName(_ string: NSImage.Name?) -> Bool {
        if let old = _name { NSImage._named[old] = nil }
        _name = string
        if let string { NSImage._named[string] = self }
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/sharetemplatename
    static public var shareTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/size
    open var size: NSSize {
        get { _size }
        set { _size = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/slideshowtemplatename
    static public var slideshowTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/smartbadgetemplatename
    static public var smartBadgeTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/statusavailablename
    static public var statusAvailableName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/statusnonename
    static public var statusNoneName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/statuspartiallyavailablename
    static public var statusPartiallyAvailableName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/statusunavailablename
    static public var statusUnavailableName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/stopprogressfreestandingtemplatename
    static public var stopProgressFreestandingTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/stopprogresstemplatename
    static public var stopProgressTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/symbolconfiguration
    @available(macOS 12.0, *)
    open var symbolConfiguration: NSImage.SymbolConfiguration { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/tiffrepresentation
    open var tiffRepresentation: Data? {
        MainActor.assumeIsolated { _cgImage().flatMap { Platform.imageCodec.encode($0, format: "public.png", quality: 1) } }   // PNG stands in for TIFF
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/tiffrepresentation(using:factor:)
    open func tiffRepresentation(using comp: NSBitmapImageRep.TIFFCompression, factor: Float) -> Data? { tiffRepresentation }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaradddetailtemplatename
    @available(macOS 10.12, *)
    static public var touchBarAddDetailTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaraddtemplatename
    @available(macOS 10.12, *)
    static public var touchBarAddTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaralarmtemplatename
    @available(macOS 10.12, *)
    static public var touchBarAlarmTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaraudioinputmutetemplatename
    @available(macOS 10.12, *)
    static public var touchBarAudioInputMuteTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaraudioinputtemplatename
    @available(macOS 10.12, *)
    static public var touchBarAudioInputTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaraudiooutputmutetemplatename
    @available(macOS 10.12, *)
    static public var touchBarAudioOutputMuteTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaraudiooutputvolumehightemplatename
    @available(macOS 10.12, *)
    static public var touchBarAudioOutputVolumeHighTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaraudiooutputvolumelowtemplatename
    @available(macOS 10.12, *)
    static public var touchBarAudioOutputVolumeLowTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaraudiooutputvolumemediumtemplatename
    @available(macOS 10.12, *)
    static public var touchBarAudioOutputVolumeMediumTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaraudiooutputvolumeofftemplatename
    @available(macOS 10.12, *)
    static public var touchBarAudioOutputVolumeOffTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarbookmarkstemplatename
    @available(macOS 10.12, *)
    static public var touchBarBookmarksTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarcolorpickerfillname
    @available(macOS 10.12, *)
    static public var touchBarColorPickerFillName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarcolorpickerfontname
    @available(macOS 10.12, *)
    static public var touchBarColorPickerFontName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarcolorpickerstrokename
    @available(macOS 10.12, *)
    static public var touchBarColorPickerStrokeName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarcommunicationaudiotemplatename
    @available(macOS 10.12, *)
    static public var touchBarCommunicationAudioTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarcommunicationvideotemplatename
    @available(macOS 10.12, *)
    static public var touchBarCommunicationVideoTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarcomposetemplatename
    @available(macOS 10.12, *)
    static public var touchBarComposeTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbardeletetemplatename
    @available(macOS 10.12, *)
    static public var touchBarDeleteTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbardownloadtemplatename
    @available(macOS 10.12, *)
    static public var touchBarDownloadTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarenterfullscreentemplatename
    @available(macOS 10.12, *)
    static public var touchBarEnterFullScreenTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarexitfullscreentemplatename
    @available(macOS 10.12, *)
    static public var touchBarExitFullScreenTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarfastforwardtemplatename
    @available(macOS 10.12, *)
    static public var touchBarFastForwardTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarfoldercopytotemplatename
    @available(macOS 10.12, *)
    static public var touchBarFolderCopyToTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarfoldermovetotemplatename
    @available(macOS 10.12, *)
    static public var touchBarFolderMoveToTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarfoldertemplatename
    @available(macOS 10.12, *)
    static public var touchBarFolderTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbargetinfotemplatename
    @available(macOS 10.12, *)
    static public var touchBarGetInfoTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbargobacktemplatename
    @available(macOS 10.12, *)
    static public var touchBarGoBackTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbargodowntemplatename
    @available(macOS 10.12, *)
    static public var touchBarGoDownTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbargoforwardtemplatename
    @available(macOS 10.12, *)
    static public var touchBarGoForwardTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbargouptemplatename
    @available(macOS 10.12, *)
    static public var touchBarGoUpTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarhistorytemplatename
    @available(macOS 10.12, *)
    static public var touchBarHistoryTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbariconviewtemplatename
    @available(macOS 10.12, *)
    static public var touchBarIconViewTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarlistviewtemplatename
    @available(macOS 10.12, *)
    static public var touchBarListViewTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarmailtemplatename
    @available(macOS 10.12, *)
    static public var touchBarMailTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarnewfoldertemplatename
    @available(macOS 10.12, *)
    static public var touchBarNewFolderTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarnewmessagetemplatename
    @available(macOS 10.12, *)
    static public var touchBarNewMessageTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaropeninbrowsertemplatename
    @available(macOS 10.12, *)
    static public var touchBarOpenInBrowserTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarpausetemplatename
    @available(macOS 10.12, *)
    static public var touchBarPauseTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarplaypausetemplatename
    @available(macOS 10.12, *)
    static public var touchBarPlayPauseTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarplaytemplatename
    @available(macOS 10.12, *)
    static public var touchBarPlayTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarplayheadtemplatename
    @available(macOS 10.12, *)
    static public var touchBarPlayheadTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarquicklooktemplatename
    @available(macOS 10.12, *)
    static public var touchBarQuickLookTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarrecordstarttemplatename
    @available(macOS 10.12, *)
    static public var touchBarRecordStartTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarrecordstoptemplatename
    @available(macOS 10.12, *)
    static public var touchBarRecordStopTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarrefreshtemplatename
    @available(macOS 10.12, *)
    static public var touchBarRefreshTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarremovetemplatename
    @available(macOS 10.13, *)
    static public var touchBarRemoveTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarrewindtemplatename
    @available(macOS 10.12, *)
    static public var touchBarRewindTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarrotatelefttemplatename
    @available(macOS 10.12, *)
    static public var touchBarRotateLeftTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarrotaterighttemplatename
    @available(macOS 10.12, *)
    static public var touchBarRotateRightTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarsearchtemplatename
    @available(macOS 10.12, *)
    static public var touchBarSearchTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarsharetemplatename
    @available(macOS 10.12, *)
    static public var touchBarShareTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarsidebartemplatename
    @available(macOS 10.12, *)
    static public var touchBarSidebarTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarskipahead15secondstemplatename
    @available(macOS 10.12, *)
    static public var touchBarSkipAhead15SecondsTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarskipahead30secondstemplatename
    @available(macOS 10.12, *)
    static public var touchBarSkipAhead30SecondsTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarskipaheadtemplatename
    @available(macOS 10.12, *)
    static public var touchBarSkipAheadTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarskipback15secondstemplatename
    @available(macOS 10.12, *)
    static public var touchBarSkipBack15SecondsTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarskipback30secondstemplatename
    @available(macOS 10.12, *)
    static public var touchBarSkipBack30SecondsTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarskipbacktemplatename
    @available(macOS 10.12, *)
    static public var touchBarSkipBackTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarskiptoendtemplatename
    @available(macOS 10.12, *)
    static public var touchBarSkipToEndTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarskiptostarttemplatename
    @available(macOS 10.12, *)
    static public var touchBarSkipToStartTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarslideshowtemplatename
    @available(macOS 10.12, *)
    static public var touchBarSlideshowTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartagicontemplatename
    @available(macOS 10.12, *)
    static public var touchBarTagIconTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextboldtemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextBoldTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextboxtemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextBoxTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextcenteraligntemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextCenterAlignTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextitalictemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextItalicTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextjustifiedaligntemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextJustifiedAlignTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextleftaligntemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextLeftAlignTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextlisttemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextListTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextrightaligntemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextRightAlignTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextstrikethroughtemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextStrikethroughTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbartextunderlinetemplatename
    @available(macOS 10.12, *)
    static public var touchBarTextUnderlineTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbaruseraddtemplatename
    @available(macOS 10.12, *)
    static public var touchBarUserAddTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarusergrouptemplatename
    @available(macOS 10.12, *)
    static public var touchBarUserGroupTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarusertemplatename
    @available(macOS 10.12, *)
    static public var touchBarUserTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarvolumedowntemplatename
    @available(macOS 10.12, *)
    static public var touchBarVolumeDownTemplateName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/touchbarvolumeuptemplatename
    @available(macOS 10.12, *)
    static public var touchBarVolumeUpTemplateName: String { unimplemented() }
    // SKIPPED (CoreTransferable.TransferRepresentation): static var transferRepresentation: some TransferRepresentation { get }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/trashemptyname
    static public var trashEmptyName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/trashfullname
    static public var trashFullName: String { unimplemented() }
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
    static public var userAccountsName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/usergroupname
    static public var userGroupName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/userguestname
    static public var userGuestName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/username
    static public var userName: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/usesepsonresolutionmismatch
    open var usesEPSOnResolutionMismatch: Bool {
        get { _usesEPSOnResolutionMismatch }
        set { _usesEPSOnResolutionMismatch = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/withlocale(_:)
    @available(macOS 14.0, *)
    open func withLocale(_ locale: Locale?) -> NSImage { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimage/withsymbolconfiguration(_:)
    @available(macOS 11.0, *)
    open func withSymbolConfiguration(_ configuration: NSImage.SymbolConfiguration) -> NSImage? { unimplemented() }
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
    class public var supportsSecureCoding: Bool { unimplemented() }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { }
    // Requirement of NSItemProviderReading
    static public var readableTypeIdentifiersForItemProvider: [String] { unimplemented() }
    // Requirement of NSItemProviderReading
    public static func object(withItemProviderData data: Data, typeIdentifier: String) throws -> Self { unimplemented() }
    // Requirement of NSItemProviderWriting
    static public var writableTypeIdentifiersForItemProvider: [String] { unimplemented() }
    // Requirement of NSItemProviderWriting
    open func loadData(withTypeIdentifier typeIdentifier: String, forItemProviderCompletionHandler completionHandler: @escaping (Data?, (any Error)?) -> Void) -> Progress? { unimplemented() }
}
