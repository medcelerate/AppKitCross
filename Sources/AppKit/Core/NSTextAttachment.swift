// NSTextAttachment (hand-written; seeded from the generated stub, see tools/apigen)
//
// An attachment is the object behind an NSAttachmentCharacter (U+FFFC) carrying the
// `.attachment` attribute. The layout manager reserves its size in the line with a
// CoreText run delegate and draws it after the glyphs (ADR-0030): through its attachment
// cell when it has one (`attachmentCell`, created for file wrapper attachments as in
// AppKit), otherwise through `image(forBounds:textContainer:characterIndex:)` in
// `attachmentBounds(for:proposedLineFragment:glyphPosition:characterIndex:)`.
// View providers belong to TextKit 2 (NSTextLayoutManager), which this port does not lay
// out with; the registry is kept so code that registers classes still runs.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(CoreText)
import CoreText
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachment
open class NSTextAttachment: NSObject, NSTextAttachmentLayout, NSSecureCoding, NSCoding, NSTextAttachmentContainer {
    private var _contents: Data?
    private var _fileType: String?
    private var _fileWrapper: FileWrapper?
    private var _image: NSImage?
    private var _bounds: CGRect = .zero
    private var _cell: (any NSTextAttachmentCellProtocol)?
    private var _cellWasSet = false
    private var _lineLayoutPadding: CGFloat = 0
    private var _allowsTextAttachmentView = true
    nonisolated(unsafe) private static var _viewProviderClasses: [String: AnyClass] = [:]

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachment/init(data:oftype:)
    @available(macOS 10.11, *)
    public init(data contentData: Data?, ofType uti: String?) {
        _contents = contentData
        _fileType = uti
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachment/init(filewrapper:)
    public convenience init(fileWrapper: FileWrapper?) {
        self.init(data: nil, ofType: nil)
        _fileWrapper = fileWrapper
    }
    /// AppKit's plain initializer (`init(data: nil, ofType: nil)`).
    public convenience override init() { self.init(data: nil, ofType: nil) }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachment/allowstextattachmentview
    @available(macOS 12.0, *)
    open var allowsTextAttachmentView: Bool {
        get { _allowsTextAttachmentView }
        set { _allowsTextAttachmentView = newValue }
    }
    /// The cell that sizes and draws the attachment in a layout manager. A file wrapper
    /// attachment gets an NSTextAttachmentCell showing its image (or an icon) the first time
    /// it is asked for, as AppKit does; an image or data attachment has none.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachment/attachmentcell
    open var attachmentCell: (any NSTextAttachmentCellProtocol)? {
        get {
            if _cell == nil, !_cellWasSet, _fileWrapper != nil, _image == nil {
                let made: NSTextAttachmentCell = MainActor.assumeIsolated { NSTextAttachmentCell(imageCell: _resolvedImage) }
                made.attachment = self
                _cell = made
            }
            return _cell
        }
        set {
            _cellWasSet = true
            _cell = newValue
            newValue?.attachment = self
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachment/bounds
    @available(macOS 10.11, *)
    open var bounds: CGRect {
        get { _bounds }
        set { _bounds = newValue }
    }
    /// NSAttachmentCharacter, U+FFFC.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachment/character
    class public var character: Int { 0xFFFC }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachment/contents
    @available(macOS 10.11, *)
    open var contents: Data? {
        get { _contents ?? (_fileWrapper?.isRegularFile == true ? _fileWrapper?.regularFileContents : nil) }
        set { _contents = newValue; _decodedImage = nil }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachment/filetype
    @available(macOS 10.11, *)
    open var fileType: String? {
        get {
            if let t = _fileType { return t }
            guard let name = _fileWrapper?.preferredFilename ?? _fileWrapper?.filename else { return nil }
            return NSTextAttachment._uti(forExtension: (name as NSString).pathExtension)
        }
        set { _fileType = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachment/filewrapper
    open var fileWrapper: FileWrapper? {
        get {
            if let w = _fileWrapper { return w }
            // An attachment made from data (or an image) answers a file wrapper for it, so
            // RTFD writers can store it.
            guard let data = _contents ?? _imageData() else { return nil }
            let w = FileWrapper(regularFileWithContents: data)
            w.preferredFilename = "Attachment." + NSTextAttachment._extension(forUTI: _contents != nil ? (_fileType ?? "public.data") : "public.png")
            return w
        }
        set {
            _fileWrapper = newValue
            _decodedImage = nil
            if !_cellWasSet { _cell = nil }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachment/image
    @available(macOS 10.11, *)
    open var image: NSImage? {
        get { _image }
        set { _image = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachment/linelayoutpadding
    @available(macOS 12.0, *)
    open var lineLayoutPadding: CGFloat {
        get { _lineLayoutPadding }
        set { _lineLayoutPadding = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachment/registerviewproviderclass(_:forfiletype:)
    @available(macOS 12.0, *)
    public class func registerViewProviderClass(_ textAttachmentViewProviderClass: AnyClass, forFileType fileType: String) {
        _viewProviderClasses[fileType] = textAttachmentViewProviderClass
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachment/textattachmentviewproviderclass(forfiletype:)
    @available(macOS 12.0, *)
    public class func textAttachmentViewProviderClass(forFileType fileType: String) -> AnyClass? { _viewProviderClasses[fileType] }
    /// TextKit 1 never uses a view provider, so attachments draw as images or cells.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachment/usestextattachmentview
    @available(macOS 12.0, *)
    open var usesTextAttachmentView: Bool { false }

    // MARK: NSTextAttachmentLayout (TextKit 2 entry points, answered from the TextKit 1 ones)

    open func image(for bounds: CGRect, attributes: [NSAttributedString.Key : Any] = [:], location: any NSTextLocation, textContainer: NSTextContainer?) -> NSImage? {
        image(forBounds: bounds, textContainer: textContainer, characterIndex: 0)
    }
    open func attachmentBounds(for attributes: [NSAttributedString.Key : Any], location: any NSTextLocation, textContainer: NSTextContainer?, proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
        attachmentBounds(for: textContainer, proposedLineFragment: proposedLineFragment, glyphPosition: position, characterIndex: 0)
    }
    open func viewProvider(for parentView: NSView?, location: any NSTextLocation, textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? { nil }

    // MARK: Coding

    class public var supportsSecureCoding: Bool { true }
    open func encode(with coder: NSCoder) {
        coder.encode(contents, forKey: "NSContents")
        coder.encode(fileType, forKey: "NSFileType")
        coder.encode(NSValue(rect: _bounds), forKey: "NSBounds")
    }
    public required init?(coder: NSCoder) {
        _contents = coder.decodeObject(forKey: "NSContents") as? Data
        _fileType = coder.decodeObject(forKey: "NSFileType") as? String
        _bounds = (coder.decodeObject(forKey: "NSBounds") as? NSValue)?.rectValue ?? .zero
        super.init()
    }

    // MARK: NSTextAttachmentContainer

    /// The image to draw: `image`, else the contents decoded as an image, else a document icon.
    open func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> NSImage? {
        _resolvedImage
    }
    /// `bounds` when set, otherwise the image's size sitting on the baseline.
    open func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
        if _bounds != .zero { return _bounds }
        let size = _resolvedImage?.size ?? .zero
        return CGRect(origin: .zero, size: size)
    }

    // MARK: Internals shared with the layout manager and RTFD

    private var _decodedImage: NSImage?

    /// `image`, or one decoded from the contents, or a generic icon for other files.
    internal var _resolvedImage: NSImage? {
        if let i = _image { return i }
        if let i = _decodedImage { return i }
        if let data = contents, let i = NSImage(data: data) { _decodedImage = i; return i }
        if _fileWrapper != nil || _contents != nil { _decodedImage = NSTextAttachment._documentIcon(named: _fileWrapper?.preferredFilename); return _decodedImage }
        return nil
    }

    private func _imageData() -> Data? {
        guard let image = _image else { return nil }
        return MainActor.assumeIsolated {
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
            return rep.representation(using: .png, properties: [:])
        }
    }

    /// Size and placement for layout: (size, offset of the bottom edge from the baseline,
    /// positive upwards), the way AppKit asks the cell or the container methods.
    internal func _layoutMetrics(in container: NSTextContainer?, characterIndex: Int, fragment: CGRect = .zero, position: CGPoint = .zero) -> (size: CGSize, baselineOffset: CGFloat) {
        if let cell = attachmentCell {
            let size = cell.cellSize()
            return (size, cell.cellBaselineOffset().y)
        }
        let r = attachmentBounds(for: container, proposedLineFragment: fragment, glyphPosition: position, characterIndex: characterIndex)
        if r.size == .zero { return (CGSize(width: 0, height: 0), 0) }
        return (r.size, r.origin.y)
    }

    /// Draws the attachment into `rect` (flipped view coordinates).
    @MainActor internal func _draw(in rect: NSRect, characterIndex: Int, layoutManager: NSLayoutManager, view: NSView?, selected: Bool) {
        if let cell = attachmentCell {
            cell.highlight(selected, withFrame: rect, in: view)
            cell.draw(withFrame: rect, in: view, characterIndex: characterIndex, layoutManager: layoutManager)
            return
        }
        guard let img = image(forBounds: rect, textContainer: layoutManager.textContainers.first, characterIndex: characterIndex) else { return }
        img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if selected {
            NSColor.selectedTextBackgroundColor.withAlphaComponent(0.45).setFill()
            NSBezierPath.fill(rect)
        }
    }

    /// A plain page icon with a folded corner for attachments that are not images.
    internal static func _documentIcon(named name: String?) -> NSImage {
        NSImage(size: NSSize(width: 32, height: 40), flipped: true) { r in
            let page = NSBezierPath()
            page.move(to: NSPoint(x: 3, y: 1)); page.line(to: NSPoint(x: 21, y: 1)); page.line(to: NSPoint(x: 29, y: 9))
            page.line(to: NSPoint(x: 29, y: 39)); page.line(to: NSPoint(x: 3, y: 39)); page.close()
            NSColor.white.setFill(); page.fill()
            NSColor.gray.setStroke(); page.lineWidth = 1; page.stroke()
            let fold = NSBezierPath()
            fold.move(to: NSPoint(x: 21, y: 1)); fold.line(to: NSPoint(x: 21, y: 9)); fold.line(to: NSPoint(x: 29, y: 9))
            fold.stroke()
            _ = r
            return true
        }
    }

    internal static func _uti(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "png": return "public.png"
        case "jpg", "jpeg": return "public.jpeg"
        case "gif": return "com.compuserve.gif"
        case "tif", "tiff": return "public.tiff"
        case "bmp": return "com.microsoft.bmp"
        case "pdf": return "com.adobe.pdf"
        case "txt": return "public.plain-text"
        case "rtf": return "public.rtf"
        case "": return nil
        default: return "public.data"
        }
    }
    internal static func _extension(forUTI uti: String) -> String {
        switch uti {
        case "public.png": return "png"
        case "public.jpeg": return "jpg"
        case "com.compuserve.gif": return "gif"
        case "public.tiff": return "tiff"
        case "com.microsoft.bmp": return "bmp"
        case "com.adobe.pdf": return "pdf"
        case "public.plain-text": return "txt"
        case "public.rtf": return "rtf"
        default: return "dat"
        }
    }
}
