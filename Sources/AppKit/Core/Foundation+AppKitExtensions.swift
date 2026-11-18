// AppKit's additions to Foundation types that need code (ADR-0033): string drawing with
// options, document reading conveniences, paragraph and script edits, bundle resource
// lookup, index paths, pasteboard hooks. Each member is listed under `skipMembers` in
// tools/apigen/config.json so Foundation+AppKit.swift no longer declares it; what is still
// declared there calls unimplemented() and ADR-0033 says why.
//
// Calls to these from the macOS test target can be ambiguous with Apple's AppKit (which
// XCTest imports transitively), so the work is in internal helpers the tests reach.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - String drawing with options

/// A text system laid out the way AppKit's string drawing lays out: no line fragment
/// padding, font leading only when asked, wrapped to `size.width` with the line fragment
/// origin option and on one unbounded line without it (a zero dimension means unlimited).
internal struct _NSStringDrawingLayout {
    let storage: NSTextStorage
    let layoutManager: NSLayoutManager
    let container: NSTextContainer
    let lineFragmentOrigin: Bool

    init(_ string: NSAttributedString, size: CGSize, options: NSString.DrawingOptions) {
        lineFragmentOrigin = options.contains(.usesLineFragmentOrigin)
        storage = NSTextStorage(attributedString: string)
        layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = options.contains(.usesFontLeading)
        storage.addLayoutManager(layoutManager)
        let unlimited = CGFloat.greatestFiniteMagnitude
        let width = lineFragmentOrigin && size.width > 0 ? size.width : unlimited
        let height = lineFragmentOrigin && size.height > 0 ? size.height : unlimited
        container = NSTextContainer(size: CGSize(width: width, height: height))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
    }

    /// The glyphs drawn: everything that fits with the line fragment origin option, the first
    /// line without it.
    var glyphRange: NSRange {
        if lineFragmentOrigin { return layoutManager.glyphRange(for: container) }
        guard storage.length > 0 else { return NSRange(location: 0, length: 0) }
        var range = NSRange(location: 0, length: 0)
        _ = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: &range)
        return range
    }

    /// Distance from the top of the first line to its baseline.
    var firstBaseline: CGFloat { storage.length > 0 ? layoutManager.location(forGlyphAt: 0).y : 0 }

    /// The bounds the drawing covers. With the line fragment origin option the origin is the
    /// top left of the first line; without it the origin is the first baseline, so the rect
    /// starts at minus the descent below it (y up).
    var boundingRect: CGRect {
        if lineFragmentOrigin {
            let used = layoutManager.usedRect(for: container)
            return CGRect(x: used.minX, y: 0, width: used.width, height: used.height)
        }
        guard storage.length > 0 else { return .zero }
        let line = layoutManager.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: nil)
        return CGRect(x: line.minX, y: -(line.height - firstBaseline), width: line.width, height: line.height)
    }

    /// Draws into the current context. `rect.origin` is the top left of the text (flipped
    /// contexts) or its bottom left, as AppKit reads it; without the line fragment origin
    /// option it is the first baseline.
    func draw(in rect: CGRect) {
        guard let gc = NSGraphicsContext.current, storage.length > 0 else { return }
        let flipped = gc.isFlipped
        // The layout manager draws in a flipped space: top of the first line at y = 0.
        let top: CGFloat
        if lineFragmentOrigin { top = flipped ? rect.minY : rect.maxY }
        else { top = flipped ? rect.minY - firstBaseline : rect.minY + firstBaseline }
        let ctx = gc.cgContext
        ctx.saveGState()
        if lineFragmentOrigin, rect.height > 0 { ctx.clip(to: rect) }
        if flipped {
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: NSPoint(x: rect.minX, y: top))
        } else {
            ctx.translateBy(x: 0, y: top)
            ctx.scaleBy(x: 1, y: -1)
            let flippedContext = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.current = flippedContext
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: NSPoint(x: rect.minX, y: 0))
            NSGraphicsContext.current = gc
        }
        ctx.restoreGState()
    }
}

extension NSAttributedString {
    /// Measures with the text system; `context` is not updated (NSStringDrawingContext's
    /// scale factors are not modelled).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/boundingrect(with:options:context:)
    public func boundingRect(with size: CGSize, options: NSString.DrawingOptions = [], context: NSStringDrawingContext?) -> CGRect {
        _NSStringDrawingLayout(self, size: size, options: options).boundingRect
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/draw(with:options:context:)
    public func draw(with rect: CGRect, options: NSString.DrawingOptions = [], context: NSStringDrawingContext?) {
        _NSStringDrawingLayout(self, size: rect.size, options: options).draw(in: rect)
    }
}

extension NSString {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstring/boundingrect(with:options:attributes:context:)
    public func boundingRect(with size: CGSize, options: NSString.DrawingOptions = [], attributes: [NSAttributedString.Key : Any]? = nil, context: NSStringDrawingContext?) -> CGRect {
        NSAttributedString(string: self as String, attributes: attributes).boundingRect(with: size, options: options, context: context)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstring/draw(with:options:attributes:context:)
    public func draw(with rect: CGRect, options: NSString.DrawingOptions = [], attributes: [NSAttributedString.Key : Any]? = nil, context: NSStringDrawingContext?) {
        NSAttributedString(string: self as String, attributes: attributes).draw(with: rect, options: options, context: context)
    }

    /// A string from a pasteboard property list: the string itself, or text data decoded as UTF-8.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstring/init(pasteboardpropertylist:oftype:)
    public convenience init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
        if let string = propertyList as? String { self.init(string: string); return }
        if let data = propertyList as? Data, let string = String(data: data, encoding: .utf8) { self.init(string: string); return }
        return nil
    }
}

extension NSString.DrawingOptions {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstring/drawingoptions/optionsresolvesnaturalalignmentwithbasewritingdirection
    @available(macOS 26.0, *)
    static public var optionsResolvesNaturalAlignmentWithBaseWritingDirection: NSString.DrawingOptions { NSString.DrawingOptions(rawValue: 1 << 9) }
}

// MARK: - Reading documents

internal enum _NSAttributedStringDocuments {
    /// Reads RTF, RTFD (flat data, or a directory URL) or plain text, as `init(data:options:)` does.
    static func read(url: URL, options: [NSAttributedString.DocumentReadingOptionKey : Any],
                     documentAttributes dict: AutoreleasingUnsafeMutablePointer<NSDictionary?>?) throws -> NSAttributedString {
        var isDirectory: ObjCBool = false
        if url.isFileURL, FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let wrapper = try FileWrapper(url: url, options: [])
            guard let s = NSAttributedString(RTFDFileWrapper: wrapper, documentAttributes: dict) else {
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadCorruptFile.rawValue, userInfo: [NSURLErrorKey: url])
            }
            return s
        }
        let data = try Data(contentsOf: url)
        var options = options
        if options[.documentType] == nil, ["rtfd"].contains(url.pathExtension.lowercased()) { options[.documentType] = NSAttributedString.DocumentType.rtfd }
        return try read(data: data, options: options, documentAttributes: dict)
    }

    static func read(data: Data, options: [NSAttributedString.DocumentReadingOptionKey : Any],
                     documentAttributes dict: AutoreleasingUnsafeMutablePointer<NSDictionary?>?) throws -> NSAttributedString {
        let requested = (options[.documentType] as? NSAttributedString.DocumentType) ?? (options[.documentType] as? String).map { NSAttributedString.DocumentType(rawValue: $0) }
        if requested == .rtfd {
            guard let s = NSAttributedString(RTFD: data, documentAttributes: dict) else {
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadCorruptFile.rawValue, userInfo: nil)
            }
            return s
        }
        if let requested, requested != .rtf, requested != .plain {
            // HTML, Word and the other importers are not part of this port.
            throw NSError(domain: NSCocoaErrorDomain, code: 65806 /* textReadInapplicableDocumentType */, userInfo: nil)
        }
        return try NSAttributedString(data: data, options: options, documentAttributes: dict)
    }
}

extension NSAttributedString {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/init(rtf:documentattributes:)
    public convenience init?(RTF data: Data, documentAttributes dict: AutoreleasingUnsafeMutablePointer<NSDictionary?>?) {
        self.init(rtf: data, documentAttributes: dict)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/init(url:documentattributes:)
    public convenience init?(URL url: URL, documentAttributes dict: AutoreleasingUnsafeMutablePointer<NSDictionary?>?) {
        guard let s = try? _NSAttributedStringDocuments.read(url: url, options: [:], documentAttributes: dict) else { return nil }
        self.init(attributedString: s)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/init(url:options:documentattributes:)
    public convenience init(URL url: URL, options: [NSAttributedString.DocumentReadingOptionKey : Any] = [:], documentAttributes dict: AutoreleasingUnsafeMutablePointer<NSDictionary?>?) throws {
        self.init(attributedString: try _NSAttributedStringDocuments.read(url: url, options: options, documentAttributes: dict))
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/init(path:documentattributes:)
    public convenience init?(path: String, documentAttributes dict: AutoreleasingUnsafeMutablePointer<NSDictionary?>?) {
        guard let s = try? _NSAttributedStringDocuments.read(url: URL(fileURLWithPath: path), options: [:], documentAttributes: dict) else { return nil }
        self.init(attributedString: s)
    }

    /// One object replacement character carrying the glyph.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/init(adaptiveimageglyph:attributes:)
    @available(macOS 15.0, *)
    public convenience init(adaptiveImageGlyph: NSAdaptiveImageGlyph, attributes: [NSAttributedString.Key : Any] = [:]) {
        var attrs = attributes
        attrs[.adaptiveImageGlyph] = adaptiveImageGlyph
        self.init(string: "\u{FFFC}", attributes: attrs)
    }

    /// A file wrapper in the format named by the `documentType` attribute (RTFD, RTF or plain text).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/filewrapper(from:documentattributes:)
    public func fileWrapper(from range: NSRange, documentAttributes dict: [NSAttributedString.DocumentAttributeKey : Any] = [:]) throws -> FileWrapper {
        let type = (dict[.documentType] as? NSAttributedString.DocumentType) ?? (dict[.documentType] as? String).map { NSAttributedString.DocumentType(rawValue: $0) }
        switch type {
        case .rtfd?:
            guard let wrapper = rtfdFileWrapper(from: range, documentAttributes: dict) else {
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileWriteUnknown.rawValue, userInfo: nil)
            }
            return wrapper
        case .rtf?, .plain?:
            return FileWrapper(regularFileWithContents: try data(from: range, documentAttributes: dict))
        default:
            throw NSError(domain: NSCocoaErrorDomain, code: 66062 /* textWriteInapplicableDocumentType */, userInfo: nil)
        }
    }

    /// The character-level attributes at `range.location` (everything but the paragraph style).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/fontattributes(in:)
    public func fontAttributes(in range: NSRange) -> [NSAttributedString.Key : Any] {
        guard range.location < length else { return [:] }
        var attrs = attributes(at: range.location, effectiveRange: nil)
        attrs[.paragraphStyle] = nil
        attrs[.attachment] = nil
        return attrs
    }

    /// The paragraph style at `range.location`, the only ruler attribute.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/rulerattributes(in:)
    public func rulerAttributes(in range: NSRange) -> [NSAttributedString.Key : Any] {
        guard range.location < length, let style = attribute(.paragraphStyle, at: range.location, effectiveRange: nil) else { return [:] }
        return [.paragraphStyle: style]
    }

    /// The closest index at or before `location` (and after `aRange.location`) where a line can
    /// start: after whitespace or a hyphen. NSNotFound when there is none.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/linebreak(before:within:)
    public func lineBreak(before location: Int, within aRange: NSRange) -> Int {
        let s = string as NSString
        let end = Swift.min(location, aRange.location + aRange.length, s.length)
        guard end > aRange.location else { return NSNotFound }
        var i = end
        while i > aRange.location {
            if let scalar = UnicodeScalar(s.character(at: i - 1)),
               CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == "-" || scalar == "\u{2010}" {
                return i
            }
            i -= 1
        }
        return NSNotFound
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/texttypes
    class public var textTypes: [String] { _NSAttributedStringDocuments.textTypes }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/textunfilteredtypes
    class public var textUnfilteredTypes: [String] { _NSAttributedStringDocuments.textTypes }

    /// The `.link` attribute at `location` as a URL (a string link is parsed).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/url(at:effectiverange:)
    public func url(at location: Int, effectiveRange: NSRangePointer) -> URL? {
        guard location < length else { return nil }
        let value = attribute(.link, at: location, effectiveRange: effectiveRange)
        if let url = value as? URL { return url }
        if let url = value as? NSURL { return url as URL }
        if let string = value as? String { return URL(string: string) }
        return nil
    }
}

extension _NSAttributedStringDocuments {
    /// The UTIs init(url:options:) reads.
    static let textTypes = ["public.rtf", "com.apple.rtfd", "com.apple.flat-rtfd", "public.plain-text", "public.utf8-plain-text"]
}

// MARK: - Editing

extension NSMutableAttributedString {
    /// Replaces the contents with what the URL holds; false when it cannot be read.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutableattributedstring/read(from:options:documentattributes:)-1mpo3
    public func read(from url: URL, options: [AnyHashable : Any] = [:], documentAttributes dict: AutoreleasingUnsafeMutablePointer<NSDictionary?>?) -> Bool {
        (try? read(from: url, options: Self._readingOptions(options), documentAttributes: dict, error: ())) != nil
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutableattributedstring/read(from:options:documentattributes:)-2nntu
    public func read(from data: Data, options: [AnyHashable : Any] = [:], documentAttributes dict: AutoreleasingUnsafeMutablePointer<NSDictionary?>?) -> Bool {
        (try? read(from: data, options: Self._readingOptions(options), documentAttributes: dict, error: ())) != nil
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutableattributedstring/read(from:options:documentattributes:error:)-3nnby
    public func read(from url: URL, options opts: [NSAttributedString.DocumentReadingOptionKey : Any] = [:], documentAttributes dict: AutoreleasingUnsafeMutablePointer<NSDictionary?>?, error: ()) throws {
        let s = try _NSAttributedStringDocuments.read(url: url, options: opts, documentAttributes: dict)
        setAttributedString(s)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutableattributedstring/read(from:options:documentattributes:error:)-6tc3n
    public func read(from data: Data, options opts: [NSAttributedString.DocumentReadingOptionKey : Any] = [:], documentAttributes dict: AutoreleasingUnsafeMutablePointer<NSDictionary?>?, error: ()) throws {
        let s = try _NSAttributedStringDocuments.read(data: data, options: opts, documentAttributes: dict)
        setAttributedString(s)
    }

    private static func _readingOptions(_ options: [AnyHashable : Any]) -> [NSAttributedString.DocumentReadingOptionKey : Any] {
        var out: [NSAttributedString.DocumentReadingOptionKey : Any] = [:]
        for (k, v) in options {
            if let key = k as? NSAttributedString.DocumentReadingOptionKey { out[key] = v }
            else if let key = k as? String { out[NSAttributedString.DocumentReadingOptionKey(rawValue: key)] = v }
        }
        return out
    }

    /// Converts each font in the range to have `traitMask` (bold, italic, ...) through the font manager.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutableattributedstring/applyfonttraits(_:range:)
    public func applyFontTraits(_ traitMask: NSFontTraitMask, range: NSRange) {
        var runs: [(NSRange, NSFont)] = []
        enumerateAttribute(.font, in: range, options: []) { value, r, _ in
            if let font = value as? NSFont { runs.append((r, font)) }
        }
        let manager = NSFontManager.shared
        beginEditing()
        for (r, font) in runs { addAttribute(.font, value: manager.convert(font, toHaveTrait: traitMask), range: r) }
        endEditing()
    }

    /// Gives every paragraph that overlaps the range the paragraph style of its first character.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutableattributedstring/fixparagraphstyleattribute(in:)
    public func fixParagraphStyleAttribute(in range: NSRange) {
        beginEditing()
        _forEachParagraph(in: range) { paragraph in
            if let style = attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) {
                addAttribute(.paragraphStyle, value: style, range: paragraph)
            } else {
                removeAttribute(.paragraphStyle, range: paragraph)
            }
        }
        endEditing()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutableattributedstring/setalignment(_:range:)
    public func setAlignment(_ alignment: NSTextAlignment, range: NSRange) {
        _editParagraphStyles(in: range) { $0.alignment = alignment }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutableattributedstring/setbasewritingdirection(_:range:)
    public func setBaseWritingDirection(_ writingDirection: NSWritingDirection, range: NSRange) {
        _editParagraphStyles(in: range) { $0.baseWritingDirection = writingDirection }
    }

    /// Raises the superscript level of each run by one.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutableattributedstring/superscriptrange(_:)
    public func superscriptRange(_ range: NSRange) { _shiftScript(range, by: 1) }

    /// Lowers the superscript level of each run by one.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutableattributedstring/subscriptrange(_:)
    public func subscriptRange(_ range: NSRange) { _shiftScript(range, by: -1) }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutableattributedstring/unscriptrange(_:)
    public func unscriptRange(_ range: NSRange) { removeAttribute(.superscript, range: range) }

    /// Re-reads file wrapper attachments whose file name exists in the directory at `path`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutableattributedstring/updateattachments(frompath:)
    public func updateAttachments(fromPath path: String) {
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        var updates: [(NSRange, NSTextAttachment)] = []
        enumerateAttribute(.attachment, in: NSRange(location: 0, length: length), options: []) { value, r, _ in
            guard let attachment = value as? NSTextAttachment,
                  let name = attachment.fileWrapper?.preferredFilename ?? attachment.fileWrapper?.filename else { return }
            let url = directory.appendingPathComponent(name)
            guard let wrapper = try? FileWrapper(url: url, options: [.immediate]) else { return }
            attachment.fileWrapper = wrapper
            updates.append((r, attachment))
        }
        guard !updates.isEmpty else { return }
        beginEditing()
        for (r, attachment) in updates { addAttribute(.attachment, value: attachment, range: r) }
        endEditing()
    }

    private func _shiftScript(_ range: NSRange, by delta: Int) {
        var runs: [(NSRange, Int)] = []
        enumerateAttribute(.superscript, in: range, options: []) { value, r, _ in
            runs.append((r, (value as? NSNumber)?.intValue ?? (value as? Int) ?? 0))
        }
        beginEditing()
        for (r, level) in runs {
            let next = level + delta
            if next == 0 { removeAttribute(.superscript, range: r) }
            else { addAttribute(.superscript, value: next, range: r) }
        }
        endEditing()
    }

    private func _forEachParagraph(in range: NSRange, _ body: (NSRange) -> Void) {
        let s = string as NSString
        guard s.length > 0 else { return }
        let clamped = NSRange(location: Swift.min(range.location, s.length), length: Swift.min(range.length, s.length - Swift.min(range.location, s.length)))
        var location = s.paragraphRange(for: NSRange(location: clamped.location, length: 0)).location
        let end = clamped.location + clamped.length
        repeat {
            let paragraph = s.paragraphRange(for: NSRange(location: location, length: 0))
            guard paragraph.length > 0 else { break }
            body(paragraph)
            location = paragraph.location + paragraph.length
        } while location < end && location < s.length
    }

    private func _editParagraphStyles(in range: NSRange, _ edit: (NSMutableParagraphStyle) -> Void) {
        beginEditing()
        _forEachParagraph(in: range) { paragraph in
            let current = attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle ?? NSParagraphStyle.default
            let style = current.mutableCopy() as! NSMutableParagraphStyle
            edit(style)
            addAttribute(.paragraphStyle, value: style, range: paragraph)
        }
        endEditing()
    }
}

// MARK: - Errors

extension CocoaError {
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/cocoaerror/isfonterror
    public var isFontError: Bool { (66304...66335).contains(code.rawValue) }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/cocoaerror/isserviceerror
    public var isServiceError: Bool { (66560...66817).contains(code.rawValue) }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/cocoaerror/issharingserviceerror
    public var isSharingServiceError: Bool { (67072...67327).contains(code.rawValue) }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/cocoaerror/istextreadwriteerror
    public var isTextReadWriteError: Bool { (65792...66303).contains(code.rawValue) }
}

// MARK: - Bundle resources

extension Bundle {
    private static let _imageExtensions = ["png", "tiff", "tif", "jpg", "jpeg", "gif", "bmp", "ico", "icns", "heic", "pdf", "svg"]
    private static let _soundExtensions = ["aiff", "aif", "aifc", "wav", "caf", "mp3", "m4a", "aac", "snd", "au", "flac"]

    private func _resourceURL(_ name: String, extensions: [String]) -> URL? {
        let ns = name as NSString
        if !ns.pathExtension.isEmpty, let url = url(forResource: ns.deletingPathExtension, withExtension: ns.pathExtension) { return url }
        for ext in extensions {
            if let url = url(forResource: name, withExtension: ext) { return url }
        }
        return nil
    }

    /// - SeeAlso: https://developer.apple.com/documentation/foundation/bundle/urlforimageresource(_:)
    public func urlForImageResource(_ name: NSImage.Name) -> URL? { _resourceURL(name, extensions: Bundle._imageExtensions) }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/bundle/pathforimageresource(_:)
    public func pathForImageResource(_ name: NSImage.Name) -> String? { urlForImageResource(name)?.path }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/bundle/image(forresource:)
    public func image(forResource name: NSImage.Name) -> NSImage? {
        guard let url = urlForImageResource(name) else { return nil }
        return NSImage(contentsOf: url)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/bundle/path(forsoundresource:)
    public func path(forSoundResource name: NSSound.Name) -> String? { _resourceURL(name, extensions: Bundle._soundExtensions)?.path }
}

// MARK: - Graphics

extension NSAffineTransform {
    private var _cgTransform: CGAffineTransform {
        let t = transformStruct
        return CGAffineTransform(a: t.m11, b: t.m12, c: t.m21, d: t.m22, tx: t.tX, ty: t.tY)
    }

    /// Appends the transform to the current context's matrix.
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsaffinetransform/concat()
    public func concat() {
        NSGraphicsContext.current?.cgContext.concatenate(_cgTransform)
    }

    /// Makes the transform the current context's matrix (relative to the context's base space).
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsaffinetransform/set()
    public func set() {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.concatenate(ctx.ctm.inverted())
        ctx.concatenate(_cgTransform)
    }

    /// A transformed copy of the path.
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsaffinetransform/transform(_:)
    public func transform(_ path: NSBezierPath) -> NSBezierPath {
        let t = transformStruct
        let copy = path.copy() as! NSBezierPath
        copy.transform(using: AffineTransform(m11: t.m11, m12: t.m12, m21: t.m21, m22: t.m22, tX: t.tX, tY: t.tY))
        return copy
    }
}

// MARK: - Index paths and sets

extension NSIndexPath {
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsindexpath/init(foritem:insection:)
    public convenience init(forItem item: Int, inSection section: Int) {
        let indexes = [section, item]
        self.init(indexes: indexes, length: 2)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsindexpath/item
    public var item: Int { index(atPosition: 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsindexpath/section
    public var section: Int { index(atPosition: 0) }
}

extension NSSet {
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsset/init(collectionviewindexpath:)
    public convenience init(collectionViewIndexPath indexPath: IndexPath) {
        self.init(object: indexPath as NSIndexPath)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsset/init(collectionviewindexpaths:)
    public convenience init(collectionViewIndexPaths indexPaths: [IndexPath]) {
        self.init(array: indexPaths.map { $0 as NSIndexPath })
    }
    /// Calls `block` with each member that is an index path; `.reverse` and `.concurrent` are
    /// accepted (sets are unordered; the enumeration is serial).
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsset/enumerateindexpaths(options:using:)
    public func enumerateIndexPaths(options opts: NSEnumerationOptions = [], using block: (IndexPath, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop: ObjCBool = false
        for member in allObjects {
            let path: IndexPath
            if let p = member as? IndexPath { path = p }
            else if let p = member as? NSIndexPath { path = p as IndexPath }
            else { continue }
            block(path, &stop)
            if stop.boolValue { break }
        }
    }
}

// MARK: - Pasteboard

extension NSURL {
    /// The URL on the pasteboard (a file URL first, then any URL); nil when there is none.
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsurl/init(frompasteboard:)
    public convenience init?(fromPasteboard pasteBoard: NSPasteboard) {
        guard let string = pasteBoard.string(forType: .fileURL) ?? pasteBoard.string(forType: .URL) else { return nil }
        self.init(string: string)
    }

    /// Writes the URL (and, for a file URL, the file URL type) to the pasteboard.
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/nsurl/write(to:)
    public func write(to pasteBoard: NSPasteboard) {
        let string = absoluteString ?? ""
        _ = pasteBoard.setString(string, forType: .URL)
        if isFileURL { _ = pasteBoard.setString(string, forType: .fileURL) }
    }
}

// MARK: - File wrapper icons

/// Icons set on file wrappers, keyed by the wrapper; entries go when their wrapper does.
private final class _FileWrapperIcons: @unchecked Sendable {
    static let shared = _FileWrapperIcons()
    private struct Entry { weak var wrapper: FileWrapper?; let icon: NSImage }
    private var entries: [ObjectIdentifier: Entry] = [:]
    private let lock = NSLock()

    func icon(for wrapper: FileWrapper) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        guard let e = entries[ObjectIdentifier(wrapper)], e.wrapper === wrapper else { return nil }
        return e.icon
    }

    func setIcon(_ icon: NSImage?, for wrapper: FileWrapper) {
        lock.lock(); defer { lock.unlock() }
        entries = entries.filter { $0.value.wrapper != nil }
        entries[ObjectIdentifier(wrapper)] = icon.map { Entry(wrapper: wrapper, icon: $0) }
    }
}

extension FileWrapper {
    /// - SeeAlso: https://developer.apple.com/documentation/foundation/filewrapper/icon
    public var icon: NSImage? {
        get { _FileWrapperIcons.shared.icon(for: self) }
        set { _FileWrapperIcons.shared.setIcon(newValue, for: self) }
    }
}
