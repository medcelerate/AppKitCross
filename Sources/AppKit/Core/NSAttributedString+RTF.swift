// RTF and RTFD reading and writing for NSAttributedString (the AppKit additions
// `init(rtf:documentAttributes:)`, `rtf(from:documentAttributes:)`,
// `data(from:documentAttributes:)`, `init(data:options:documentAttributes:)` and the RTFD
// members), so document-based applications can save rich text on every platform
// (ADR-0017, ADR-0030).
//
// The dialect written is the one TextEdit writes: a font table, a colour table, a list
// table, and per run the font (`\f`), size (`\fs`, half points), bold, italic, underline
// and colour (`\cf`); per paragraph the alignment, indents (`\li \fi \ri`), spacing
// (`\sb \sa`), tab stops (`\tx`, `\tqr`, `\tqc`), list membership (`\ls \ilvl`) and
// table cells (`\trowd \cellx \intbl \cell \row`); non-ASCII characters as `\uN`
// escapes. Attachments are written only into RTFD, as `\NeXTGraphic` groups naming a file
// of the RTFD directory. The reader takes the same and what other editors commonly add
// (group nesting with state, `\'xx` Latin-1 escapes, `\uc`, skipped `\*` destinations,
// `\line`, `\tab`, `\plain`, `\pard`, Word's `\levelnfc` list numbering). Pictures
// embedded as `\pict` and styles are not read.
//
// The flat RTFD data (`rtfd(from:)`, `init(RTFD:)`) is this port's serialisation of the
// RTFD directory (`_RTFDArchive`); on macOS the reader also accepts Apple's.
//
// The test target on macOS sees Apple's AppKit declarations of these members through
// XCTest's transitive imports, which makes calls ambiguous there; the tests use
// `_RTFWriter` and `_RTFReader` directly.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension NSAttributedString {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/init(rtf:documentattributes:)
    public convenience init?(rtf data: Data, documentAttributes dict: AutoreleasingUnsafeMutablePointer<NSDictionary?>?) {
        guard let parsed = _RTFReader(data: data).read() else { return nil }
        self.init(attributedString: parsed)
        dict?.pointee = [NSAttributedString.DocumentAttributeKey.documentType.rawValue: NSAttributedString.DocumentType.rtf.rawValue] as NSDictionary
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/init(data:options:documentattributes:)
    /// RTF when the data starts with `{\rtf` or the options say so; otherwise plain text
    /// in the given or detected encoding.
    public convenience init(data: Data, options: [NSAttributedString.DocumentReadingOptionKey : Any] = [:], documentAttributes dict: AutoreleasingUnsafeMutablePointer<NSDictionary?>?) throws {
        let requested = (options[.documentType] as? NSAttributedString.DocumentType) ?? (options[.documentType] as? String).map { NSAttributedString.DocumentType(rawValue: $0) }
        let looksLikeRTF = data.starts(with: Array("{\\rtf".utf8))
        if requested == .rtf || (requested == nil && looksLikeRTF) {
            guard let parsed = _RTFReader(data: data).read() else {
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadCorruptFile.rawValue, userInfo: [NSLocalizedDescriptionKey: "The RTF data could not be read."])
            }
            self.init(attributedString: parsed)
            dict?.pointee = [NSAttributedString.DocumentAttributeKey.documentType.rawValue: NSAttributedString.DocumentType.rtf.rawValue] as NSDictionary
            return
        }
        let encoding: String.Encoding
        if let raw = options[.characterEncoding] as? UInt { encoding = String.Encoding(rawValue: raw) }
        else if let n = options[.characterEncoding] as? Int { encoding = String.Encoding(rawValue: UInt(n)) }
        else { encoding = .utf8 }
        guard let text = String(data: data, encoding: encoding) ?? String(data: data, encoding: .isoLatin1) else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadInapplicableStringEncoding.rawValue, userInfo: [NSLocalizedDescriptionKey: "The text could not be decoded."])
        }
        self.init(string: text)
        dict?.pointee = [NSAttributedString.DocumentAttributeKey.documentType.rawValue: NSAttributedString.DocumentType.plain.rawValue,
                         NSAttributedString.DocumentAttributeKey.characterEncoding.rawValue: encoding.rawValue] as NSDictionary
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/rtf(from:documentattributes:)
    public func rtf(from range: NSRange, documentAttributes dict: [NSAttributedString.DocumentAttributeKey : Any] = [:]) -> Data? {
        _RTFWriter(attributedString: self, range: range).write()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/data(from:documentattributes:)
    /// RTF for `.rtf`, otherwise the plain text in `.characterEncoding` (UTF-8 by default).
    public func data(from range: NSRange, documentAttributes dict: [NSAttributedString.DocumentAttributeKey : Any] = [:]) throws -> Data {
        let type = (dict[.documentType] as? NSAttributedString.DocumentType) ?? (dict[.documentType] as? String).map { NSAttributedString.DocumentType(rawValue: $0) } ?? .plain
        if type == .rtf {
            guard let data = rtf(from: range, documentAttributes: dict) else {
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileWriteUnknown.rawValue, userInfo: [NSLocalizedDescriptionKey: "The RTF data could not be written."])
            }
            return data
        }
        let encoding: String.Encoding
        if let raw = dict[.characterEncoding] as? UInt { encoding = String.Encoding(rawValue: raw) }
        else if let n = dict[.characterEncoding] as? Int { encoding = String.Encoding(rawValue: UInt(n)) }
        else { encoding = .utf8 }
        guard let data = attributedSubstring(from: range).string.data(using: encoding) else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileWriteInapplicableStringEncoding.rawValue, userInfo: [NSLocalizedDescriptionKey: "The text cannot be encoded."])
        }
        return data
    }
}


// MARK: - RTFD

extension NSAttributedString {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/init(rtfd:documentattributes:)
    public convenience init?(RTFD data: Data, documentAttributes dict: AutoreleasingUnsafeMutablePointer<NSDictionary?>?) {
        guard let wrapper = _RTFDArchive.unarchive(data) else { return nil }
        self.init(RTFDFileWrapper: wrapper, documentAttributes: dict)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/init(rtfdfilewrapper:documentattributes:)
    public convenience init?(RTFDFileWrapper wrapper: FileWrapper, documentAttributes dict: AutoreleasingUnsafeMutablePointer<NSDictionary?>?) {
        guard let parsed = _RTFReader.readRTFD(wrapper) else { return nil }
        self.init(attributedString: parsed)
        dict?.pointee = [NSAttributedString.DocumentAttributeKey.documentType.rawValue: NSAttributedString.DocumentType.rtfd.rawValue] as NSDictionary
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/rtfd(from:documentattributes:)
    public func rtfd(from range: NSRange, documentAttributes dict: [NSAttributedString.DocumentAttributeKey : Any] = [:]) -> Data? {
        rtfdFileWrapper(from: range, documentAttributes: dict).map(_RTFDArchive.archive)
    }
    /// A directory: TXT.rtf and one file per attachment.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/rtfdfilewrapper(from:documentattributes:)
    public func rtfdFileWrapper(from range: NSRange, documentAttributes dict: [NSAttributedString.DocumentAttributeKey : Any] = [:]) -> FileWrapper? {
        var writer = _RTFWriter(attributedString: self, range: range)
        writer.writesAttachments = true
        guard let rtf = writer.write() else { return nil }
        var children: [String: FileWrapper] = ["TXT.rtf": FileWrapper(regularFileWithContents: rtf)]
        for (name, file) in writer.attachmentFiles { children[name] = file }
        return FileWrapper(directoryWithFileWrappers: children)
    }
    /// Whether the range has attachments, which only RTFD keeps.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/prefersrtfd(in:)
    @available(macOS 15.0, *)
    public func prefersRTFD(in range: NSRange) -> Bool { containsAttachments(in: range) }
}

/// The flat form of an RTFD directory: "rtfd", a version, the entry count, then per entry
/// its UTF-8 name and its contents, each length-prefixed (32-bit little endian).
enum _RTFDArchive {
    static func archive(_ wrapper: FileWrapper) -> Data {
        var out = Data("rtfd".utf8)
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; withUnsafeBytes(of: &x) { out.append(contentsOf: $0) } }
        let children = (wrapper.fileWrappers ?? [:]).filter { $0.value.isRegularFile }.sorted { $0.key < $1.key }
        u32(1)
        u32(children.count)
        for (name, file) in children {
            let n = Data(name.utf8), d = file.regularFileContents ?? Data()
            u32(n.count); out.append(n)
            u32(d.count); out.append(d)
        }
        return out
    }

    static func unarchive(_ data: Data) -> FileWrapper? {
        let bytes = [UInt8](data)
        guard bytes.count >= 12, bytes.starts(with: Array("rtfd".utf8)) else {
            #if canImport(Darwin)
            return FileWrapper(serializedRepresentation: data)
            #else
            return nil
            #endif
        }
        var i = 4
        func u32() -> Int? {
            guard i + 4 <= bytes.count else { return nil }
            let v = Int(bytes[i]) | Int(bytes[i + 1]) << 8 | Int(bytes[i + 2]) << 16 | Int(bytes[i + 3]) << 24
            i += 4
            return v
        }
        guard u32() == 1, let count = u32() else {
            #if canImport(Darwin)
            return FileWrapper(serializedRepresentation: data)
            #else
            return nil
            #endif
        }
        var children: [String: FileWrapper] = [:]
        for _ in 0..<count {
            guard let nl = u32(), i + nl <= bytes.count else { return nil }
            let name = String(decoding: bytes[i..<(i + nl)], as: UTF8.self); i += nl
            guard let dl = u32(), i + dl <= bytes.count else { return nil }
            children[name] = FileWrapper(regularFileWithContents: Data(bytes[i..<(i + dl)])); i += dl
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }
}

// MARK: - Writer

struct _RTFWriter {
    let attributedString: NSAttributedString
    let range: NSRange
    /// RTFD: attachments become \NeXTGraphic references to `attachmentFiles`.
    var writesAttachments = false
    private final class Files { var list: [(String, FileWrapper)] = [] }
    private let files = Files()
    /// The attachments' files, named as the RTF refers to them (after `write()`).
    var attachmentFiles: [(String, FileWrapper)] { files.list }

    init(attributedString: NSAttributedString, range: NSRange) {
        self.attributedString = attributedString
        self.range = range
    }

    private struct Run {
        var text: String
        var fontIndex: Int
        var halfPoints: Int
        var bold: Bool
        var italic: Bool
        var underline: Bool
        var colorIndex: Int
        var attachment: NSTextAttachment?
    }

    private static func twips(_ v: CGFloat) -> Int { Int((v * 20).rounded()) }

    func write() -> Data? {
        var fonts: [String] = []
        var colors: [(Int, Int, Int)] = []
        func colorIndex(_ c: NSColor) -> Int {
            let rgb = (Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
            if let i = colors.firstIndex(where: { $0 == rgb }) { return i + 1 }
            colors.append(rgb)
            return colors.count
        }
        let text = attributedString.string as NSString
        let end = NSMaxRange(range)

        // Paragraphs of the range, with their styles.
        var paragraphs: [(range: NSRange, style: NSParagraphStyle?)] = []
        var p = range.location
        while p < end {
            var e = p
            while e < end, text.character(at: e) != 0x0A, text.character(at: e) != 0x0D, text.character(at: e) != 0x2029 { e += 1 }
            if e < end { e += (text.character(at: e) == 0x0D && e + 1 < end && text.character(at: e + 1) == 0x0A) ? 2 : 1 }
            paragraphs.append((NSRange(location: p, length: e - p), attributedString.attribute(.paragraphStyle, at: p, effectiveRange: nil) as? NSParagraphStyle))
            p = e
        }

        // Lists: one \ls per outermost list object, its levels' markers in the list table.
        var lists: [(list: NSTextList, levels: [NSTextList])] = []
        for para in paragraphs {
            guard let tl = para.style?.textLists, let outer = tl.first else { continue }
            if let i = lists.firstIndex(where: { $0.list === outer }) {
                for (k, l) in tl.enumerated() where k >= lists[i].levels.count { lists[i].levels.append(l) }
            } else {
                lists.append((outer, tl))
            }
        }

        func cell(_ i: Int) -> NSTextTableBlock? {
            guard i >= 0, i < paragraphs.count else { return nil }
            return paragraphs[i].style?.textBlocks.first as? NSTextTableBlock
        }

        var body = ""
        for (pi, para) in paragraphs.enumerated() {
            let style = para.style
            let cellBlock = cell(pi)
            // A table row starts: its cell definitions.
            if let b = cellBlock, cell(pi - 1)?.table !== b.table || cell(pi - 1)?.startingRow != b.startingRow {
                var rowCells: [NSTextTableBlock] = []
                var k = pi
                while let c = cell(k), c.table === b.table, c.startingRow == b.startingRow {
                    if rowCells.last !== c { rowCells.append(c) }
                    k += 1
                }
                let t = b.table
                let n = max(1, t.numberOfColumns)
                let widths: [CGFloat] = t._columnWidth.count == n ? t._columnWidth : [CGFloat](repeating: 468 / CGFloat(n), count: n)
                let gap = rowCells.first.map { $0.width(for: .padding, edge: .minX) } ?? 0
                body += "\\trowd\\trgaph\(_RTFWriter.twips(gap))\\trleft0\n"
                var edge: CGFloat = 0
                var col = 0
                for c in rowCells {
                    while col < c.startingColumn && col < widths.count { edge += widths[col]; col += 1 }
                    for (e, name) in [(NSRectEdge.minY, "t"), (.minX, "l"), (.maxY, "b"), (.maxX, "r")] {
                        let w = c.width(for: .border, edge: e)
                        if w > 0 {
                            body += "\\clbrdr\(name)\\brdrs\\brdrw\(_RTFWriter.twips(w))"
                            if let bc = c.borderColor(for: e) { body += "\\brdrcf\(colorIndex(bc))" }
                        }
                    }
                    if let bg = c.backgroundColor { body += "\\clcbpat\(colorIndex(bg))" }
                    for _ in 0..<max(1, c.columnSpan) where col < widths.count { edge += widths[col]; col += 1 }
                    body += "\\cellx\(_RTFWriter.twips(edge))\n"
                }
            }
            // Paragraph properties.
            body += "\\pard"
            if cellBlock != nil { body += "\\intbl\\itap1" }
            if let s = style {
                for tab in s.tabStops {
                    if tab.alignment == .right { body += "\\tqr" } else if tab.alignment == .center { body += "\\tqc" }
                    body += "\\tx\(_RTFWriter.twips(tab.location))"
                }
                if s.headIndent != 0 { body += "\\li\(_RTFWriter.twips(s.headIndent))" }
                if s.firstLineHeadIndent != s.headIndent { body += "\\fi\(_RTFWriter.twips(s.firstLineHeadIndent - s.headIndent))" }
                if s.tailIndent < 0 { body += "\\ri\(_RTFWriter.twips(-s.tailIndent))" }
                if s.paragraphSpacingBefore > 0 { body += "\\sb\(_RTFWriter.twips(s.paragraphSpacingBefore))" }
                if s.paragraphSpacing > 0 { body += "\\sa\(_RTFWriter.twips(s.paragraphSpacing))" }
            }
            switch style?.alignment ?? .natural {
            case .center: body += "\\qc"
            case .right: body += "\\qr"
            case .justified: body += "\\qj"
            default: body += "\\ql"
            }
            body += "\\pardirnatural\\partightenfactor0"
            if let tl = style?.textLists, let outer = tl.first, let li = lists.firstIndex(where: { $0.list === outer }) {
                body += "\\ls\(li + 1)\\ilvl\(tl.count - 1)"
            }
            body += "\n"

            // Character runs.
            var state: Run? = nil
            let isLastOfCell = cellBlock != nil && cell(pi + 1) !== cellBlock
            let isLastOfRow = isLastOfCell && (cell(pi + 1)?.table !== cellBlock?.table || cell(pi + 1)?.startingRow != cellBlock?.startingRow)
            attributedString.enumerateAttributes(in: para.range, options: []) { attrs, r, _ in
                let font = attrs[.font] as? NSFont
                let family = font?.familyName ?? "Helvetica"
                let fontIndex: Int
                if let i = fonts.firstIndex(of: family) { fontIndex = i } else { fonts.append(family); fontIndex = fonts.count - 1 }
                var bold = false, italic = false
                if let f = font {
                    let traits = NSFontManager.shared.traits(of: f)
                    bold = traits.contains(.boldFontMask)
                    italic = traits.contains(.italicFontMask)
                }
                let ci = (attrs[.foregroundColor] as? NSColor).map(colorIndex) ?? 0
                let underline = ((attrs[.underlineStyle] as? Int) ?? (attrs[.underlineStyle] as? NSNumber)?.intValue ?? 0) != 0
                let run = Run(text: text.substring(with: r), fontIndex: fontIndex, halfPoints: Int(((font?.pointSize ?? 12) * 2).rounded()),
                              bold: bold, italic: italic, underline: underline, colorIndex: ci, attachment: attrs[.attachment] as? NSTextAttachment)
                if state == nil || state!.fontIndex != run.fontIndex || state!.halfPoints != run.halfPoints || state!.bold != run.bold
                    || state!.italic != run.italic || state!.underline != run.underline || state!.colorIndex != run.colorIndex {
                    body += "\\f\(run.fontIndex)\\fs\(run.halfPoints)"
                    body += run.bold ? "\\b" : "\\b0"
                    body += run.italic ? "\\i" : "\\i0"
                    body += run.underline ? "\\ul" : "\\ulnone"
                    body += "\\cf\(run.colorIndex) "
                    state = run
                }
                for scalar in run.text.unicodeScalars {
                    switch scalar {
                    case "\n", "\r", "\u{2029}":
                        if scalar == "\r", run.text.unicodeScalars.contains("\n") { continue }
                        body += isLastOfCell ? "\\cell \(isLastOfRow ? "\\row" : "")\n" : "\\par\n"
                    case "\u{FFFC}":
                        guard writesAttachments, let a = run.attachment else { continue }
                        body += attachmentGroup(a)
                    case "\t": body += "\\tab "
                    case "\\": body += "\\\\"
                    case "{": body += "\\{"
                    case "}": body += "\\}"
                    default:
                        if scalar.isASCII {
                            body.unicodeScalars.append(scalar)
                        } else if scalar.value <= 0xFFFF {
                            body += "\\u\(Int(Int16(truncatingIfNeeded: scalar.value)))?"
                        } else {
                            // Supplementary planes: a surrogate pair of escapes, as Word does.
                            let v = scalar.value - 0x10000
                            let high = 0xD800 + (v >> 10), low = 0xDC00 + (v & 0x3FF)
                            body += "\\u\(Int(Int16(truncatingIfNeeded: high)))?\\u\(Int(Int16(truncatingIfNeeded: low)))?"
                        }
                    }
                }
            }
            // A cell whose text does not end in a newline (the end of the range) still closes.
            if isLastOfCell, para.range.length == 0 || ![0x0A, 0x0D, 0x2029].contains(text.character(at: NSMaxRange(para.range) - 1)) {
                body += "\\cell \(isLastOfRow ? "\\row" : "")\n"
            }
        }

        var out = "{\\rtf1\\ansi\\ansicpg1252\\cocoartf2822\\cocoatextscaling0\\cocoaplatform0\n"
        out += "{\\fonttbl"
        for (i, f) in fonts.enumerated() { out += "\\f\(i)\\fnil\\fcharset0 \(f);" }
        out += "}\n{\\colortbl;"
        for c in colors { out += "\\red\(c.0)\\green\(c.1)\\blue\(c.2);" }
        out += "}\n"
        if !lists.isEmpty {
            out += "{\\*\\listtable"
            for (i, entry) in lists.enumerated() {
                out += "{\\list\\listtemplateid\(i + 1)\\listhybrid"
                for (level, l) in entry.levels.enumerated() {
                    let marker = l.markerFormat.rawValue.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "{", with: "\\{").replacingOccurrences(of: "}", with: "\\}")
                    out += "{\\listlevel\\levelnfc\(_RTFWriter.nfc(l))\\levelnfcn\(_RTFWriter.nfc(l))\\leveljc0\\leveljcn0\\levelfollow0\\levelstartat\(l.startingItemNumber)\\levelspace360\\levelindent0"
                    out += "{\\*\\levelmarker \(marker)}{\\leveltext\\leveltemplateid\((i + 1) * 100 + level)\\'01\\'00;}{\\levelnumbers;}\\fi-360\\li\(720 * (level + 1))\\lin\(720 * (level + 1)) }"
                }
                out += "{\\listname ;}\\listid\(i + 1)}"
            }
            out += "}\n{\\*\\listoverridetable"
            for i in lists.indices { out += "{\\listoverride\\listid\(i + 1)\\listoverridecount0\\ls\(i + 1)}" }
            out += "}\n"
        }
        out += body
        out += "}"
        return out.data(using: .utf8)
    }

    /// Word's number format codes for a marker (bullets are 23).
    private static func nfc(_ l: NSTextList) -> Int {
        switch l.markerFormat {
        case .decimal: return 0
        case .uppercaseRoman: return 1
        case .lowercaseRoman: return 2
        case .uppercaseAlpha, .uppercaseLatin: return 3
        case .lowercaseAlpha, .lowercaseLatin: return 4
        default: return 23
        }
    }

    /// `{{\NeXTGraphic name \width.. \height..}¬}` with the file added to the RTFD.
    private func attachmentGroup(_ a: NSTextAttachment) -> String {
        guard let file = a.fileWrapper else { return "" }
        var name = file.preferredFilename ?? file.filename ?? "Attachment"
        if name.isEmpty { name = "Attachment" }
        // Unique within the directory.
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var n = 1
        while files.list.contains(where: { $0.0 == name }) || name == "TXT.rtf" {
            n += 1
            name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
        }
        files.list.append((name, file))
        let size = a.bounds.size != .zero ? a.bounds.size : (a._resolvedImage?.size ?? .zero)
        let escaped = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "{", with: "\\{").replacingOccurrences(of: "}", with: "\\}")
        return "{{\\NeXTGraphic \(escaped) \\width\(_RTFWriter.twips(size.width)) \\height\(_RTFWriter.twips(size.height)) \\appleattachmentpadding0 \\appleembedtype0 \\appleaqc\n}\\'ac}"
    }
}

// MARK: - Reader

final class _RTFReader {
    private let bytes: [UInt8]
    private var index = 0

    /// Paragraph formatting (`\pard` resets it).
    private struct Paragraph: Equatable {
        var alignment: NSTextAlignment = .natural
        var leftIndent = 0, firstIndent = 0, rightIndent = 0, spaceBefore = 0, spaceAfter = 0
        var tabs: [Int] = []
        var tabKinds: [Int] = []          // 0 left, 1 right, 2 centre
        var pendingTabKind = 0
        var list = 0, level = 0
        var inTable = false
        var cellRow = -1, cellColumn = -1
    }

    private struct State {
        var fontIndex = 0
        var halfPoints = 24
        var bold = false
        var italic = false
        var underline = false
        var colorIndex = 0
        var paragraph = Paragraph()
        var unicodeSkip = 1
        var skipping = false            // inside a destination we ignore
        var destination: String? = nil  // "fonttbl", "colortbl", "listtable", ...
    }

    private var fonts: [Int: String] = [:]
    private var colors: [(Int, Int, Int)] = []
    private var fontCollecting: (index: Int, name: String)? = nil
    private var colorCollecting: (r: Int, g: Int, b: Int, seen: Bool) = (0, 0, 0, false)
    private let result = NSMutableAttributedString(string: "")
    private var pendingText = ""
    private var pendingState = State()
    private var hasPendingState = false
    /// RTFD: the directory's files, by name.
    var attachmentFile: ((String) -> FileWrapper?)? = nil

    // Lists: levels collected per \list, then \listid; \ls maps through the override table.
    private var listLevels: [(marker: String?, nfc: Int, start: Int)] = []
    private var currentLevel: (marker: String?, nfc: Int, start: Int) = (nil, 23, 1)
    private var listDefinitions: [Int: [(marker: String?, nfc: Int, start: Int)]] = [:]
    private var overrideListID = 0
    private var overrides: [Int: Int] = [:]
    private var markerText = ""
    private var listObjects: [Int: [NSTextList]] = [:]

    // Tables: cell definitions of the current row, the cells' blocks.
    private var table: NSTextTable?
    private var tableRow = -1
    private var cellIndex = 0
    private var rowCellEdges: [Int] = []
    private var rowCellBackgrounds: [Int?] = []
    private var rowCellBorders: [[(edge: NSRectEdge, width: Int, color: Int)]] = []
    private var pendingBorders: [(edge: NSRectEdge, width: Int, color: Int)] = []
    private var pendingBorderEdge: NSRectEdge? = nil
    private var pendingBackground: Int? = nil
    private var rowGap = 0
    private var blocks: [Int: NSTextTableBlock] = [:]     // row * 1000 + column

    // Attachments.
    private var graphicName = ""
    private var skipsNotSign = false

    init(data: Data) { bytes = Array(data) }

    /// An RTFD directory: TXT.rtf (or TXT.rtfd's legacy name) with its attachments.
    static func readRTFD(_ wrapper: FileWrapper) -> NSAttributedString? {
        let files = wrapper.fileWrappers ?? [:]
        guard let rtf = (files["TXT.rtf"] ?? files["txt.rtf"])?.regularFileContents else {
            // A plain file wrapper of RTF also reads.
            return wrapper.regularFileContents.flatMap { _RTFReader(data: $0).read() }
        }
        let reader = _RTFReader(data: rtf)
        _PasteboardTrace.log("RTFD read: \(rtf.count) bytes of TXT.rtf, files \(files.keys.sorted())")
        reader.attachmentFile = { name in
            let f = files[name]
            _PasteboardTrace.log("RTFD read: \\NeXTGraphic \(name.debugDescription) -> \(f.map { "\($0.regularFileContents?.count ?? -1) bytes" } ?? "no such file")")
            return f
        }
        return reader.read()
    }

    func read() -> NSAttributedString? {
        guard bytes.starts(with: Array("{\\rtf".utf8)) else { return nil }
        var stack: [State] = []
        var state = State()
        while index < bytes.count {
            let c = bytes[index]
            switch c {
            case UInt8(ascii: "{"):
                index += 1
                stack.append(state)
                if state.destination == "fonttbl" { fontCollecting = (0, "") }
            case UInt8(ascii: "}"):
                index += 1
                if state.destination == "fonttbl", let f = fontCollecting, stack.last?.destination == "fonttbl" || stack.last?.destination == nil {
                    if !f.name.isEmpty { fonts[f.index] = f.name.trimmingCharacters(in: .whitespaces) }
                    fontCollecting = nil
                }
                if state.destination == "colortbl" && stack.last?.destination != "colortbl" { flushColor() }
                if state.destination == "levelmarker" && stack.last?.destination != "levelmarker" { currentLevel.marker = markerText; markerText = "" }
                if state.destination == "listlevel" && stack.last?.destination != "listlevel" { listLevels.append(currentLevel); currentLevel = (nil, 23, 1) }
                if state.destination == "nextgraphic" && stack.last?.destination != "nextgraphic", let previous = stack.last { appendAttachment(named: graphicName, previous) }
                guard let previous = stack.popLast() else { return finish() }
                state = previous
            case UInt8(ascii: "\\"):
                index += 1
                guard index < bytes.count else { break }
                let n = bytes[index]
                if n == UInt8(ascii: "'") {
                    index += 1
                    let hex = String(decoding: bytes[index..<min(index + 2, bytes.count)], as: UTF8.self)
                    index += 2
                    if !state.skipping, let v = UInt8(hex, radix: 16), let scalar = UnicodeScalar(_cp1252(v)) { append(String(scalar), state) }
                } else if n == UInt8(ascii: "*") {
                    index += 1
                    state.skipping = true
                } else if (n >= UInt8(ascii: "a") && n <= UInt8(ascii: "z")) || (n >= UInt8(ascii: "A") && n <= UInt8(ascii: "Z")) {
                    var word = ""
                    while index < bytes.count, (bytes[index] >= UInt8(ascii: "a") && bytes[index] <= UInt8(ascii: "z")) || (bytes[index] >= UInt8(ascii: "A") && bytes[index] <= UInt8(ascii: "Z")) {
                        word.unicodeScalars.append(UnicodeScalar(bytes[index])); index += 1
                    }
                    var param: Int? = nil
                    var negative = false
                    if index < bytes.count, bytes[index] == UInt8(ascii: "-") { negative = true; index += 1 }
                    var digits = ""
                    while index < bytes.count, bytes[index] >= UInt8(ascii: "0") && bytes[index] <= UInt8(ascii: "9") { digits.unicodeScalars.append(UnicodeScalar(bytes[index])); index += 1 }
                    if !digits.isEmpty { param = Int(digits).map { negative ? -$0 : $0 } }
                    if index < bytes.count, bytes[index] == UInt8(ascii: " ") { index += 1 }
                    control(word, param, &state)
                } else {
                    index += 1
                    switch n {
                    case UInt8(ascii: "\\"), UInt8(ascii: "{"), UInt8(ascii: "}"): if !state.skipping { append(String(UnicodeScalar(n)), state) }
                    case UInt8(ascii: "\n"), UInt8(ascii: "\r"): if !state.skipping { append("\n", state) }
                    case UInt8(ascii: "~"): if !state.skipping { append("\u{A0}", state) }
                    case UInt8(ascii: "-"), UInt8(ascii: ":"): break
                    case UInt8(ascii: "_"): if !state.skipping { append("\u{2011}", state) }
                    default: break
                    }
                }
            case UInt8(ascii: "\r"), UInt8(ascii: "\n"):
                index += 1
            default:
                // A run of plain text up to the next control character.
                var end = index
                while end < bytes.count, bytes[end] != UInt8(ascii: "\\"), bytes[end] != UInt8(ascii: "{"), bytes[end] != UInt8(ascii: "}"), bytes[end] != UInt8(ascii: "\r"), bytes[end] != UInt8(ascii: "\n") { end += 1 }
                let text = String(decoding: bytes[index..<end], as: UTF8.self)
                index = end
                if state.destination == "fonttbl" { fontCollecting?.name += text.replacingOccurrences(of: ";", with: "") }
                else if state.destination == "colortbl" { if text.contains(";") { flushColor() } }
                else if !state.skipping { append(text, state) }
            }
        }
        return finish()
    }

    private func control(_ word: String, _ param: Int?, _ state: inout State) {
        switch word {
        case "fonttbl": state.destination = "fonttbl"; state.skipping = false
        case "colortbl": state.destination = "colortbl"; state.skipping = false; colorCollecting = (0, 0, 0, false)
        case "listtable": state.destination = "listtable"; state.skipping = false
        case "listoverridetable": state.destination = "listoverridetable"; state.skipping = false
        case "list" where state.destination == "listtable": listLevels = []
        case "listlevel": state.destination = "listlevel"; currentLevel = (nil, 23, 1)
        case "levelmarker": state.destination = "levelmarker"; state.skipping = false; markerText = ""
        case "levelnfc": if state.destination == "listlevel" { currentLevel.nfc = param ?? 23 }
        case "levelstartat": if state.destination == "listlevel" { currentLevel.start = param ?? 1 }
        case "leveltext", "levelnumbers", "listname": state.skipping = true
        case "listid":
            if state.destination == "listtable" { listDefinitions[param ?? 0] = listLevels; listLevels = [] }
            else if state.destination == "listoverridetable" { overrideListID = param ?? 0 }
        case "ls":
            if state.destination == "listoverridetable" { overrides[param ?? 0] = overrideListID } else { state.paragraph.list = param ?? 0 }
        case "ilvl": state.paragraph.level = param ?? 0
        case "NeXTGraphic": state.destination = "nextgraphic"; state.skipping = false; graphicName = ""
        case "stylesheet", "info", "pict", "header", "footer", "expandedcolortbl", "field", "fldinst", "themedata", "colorschememapping", "latentstyles", "datastore", "xmlnstbl", "rsidtbl", "generator", "mmathPr":
            state.skipping = true
        case "red": if state.destination == "colortbl" { colorCollecting.r = param ?? 0; colorCollecting.seen = true }
        case "green": if state.destination == "colortbl" { colorCollecting.g = param ?? 0; colorCollecting.seen = true }
        case "blue": if state.destination == "colortbl" { colorCollecting.b = param ?? 0; colorCollecting.seen = true }
        case "f":
            if state.destination == "fonttbl" { fontCollecting = (param ?? 0, "") } else { state.fontIndex = param ?? 0 }
        case "fs": state.halfPoints = param ?? 24
        case "b": state.bold = (param ?? 1) != 0
        case "i": state.italic = (param ?? 1) != 0
        case "ul": state.underline = (param ?? 1) != 0
        case "ulnone": state.underline = false
        case "cf": state.colorIndex = param ?? 0
        case "plain": state.bold = false; state.italic = false; state.underline = false; state.colorIndex = 0; state.halfPoints = 24; state.fontIndex = 0
        case "pard": state.paragraph = Paragraph()
        case "ql": state.paragraph.alignment = .left
        case "qc": state.paragraph.alignment = .center
        case "qr": state.paragraph.alignment = .right
        case "qj": state.paragraph.alignment = .justified
        case "li": state.paragraph.leftIndent = param ?? 0
        case "fi": state.paragraph.firstIndent = param ?? 0
        case "ri": state.paragraph.rightIndent = param ?? 0
        case "sb": state.paragraph.spaceBefore = param ?? 0
        case "sa": state.paragraph.spaceAfter = param ?? 0
        case "tqr": state.paragraph.pendingTabKind = 1
        case "tqc": state.paragraph.pendingTabKind = 2
        case "tx":
            state.paragraph.tabs.append(param ?? 0)
            state.paragraph.tabKinds.append(state.paragraph.pendingTabKind)
            state.paragraph.pendingTabKind = 0
        // Tables
        case "trowd":
            if table == nil { table = NSTextTable(); tableRow = -1; blocks = [:] }
            tableRow += 1
            cellIndex = 0
            rowCellEdges = []; rowCellBackgrounds = []; rowCellBorders = []; pendingBorders = []; pendingBackground = nil
        case "trgaph": rowGap = param ?? 0
        case "clbrdrt": pendingBorderEdge = .minY
        case "clbrdrl": pendingBorderEdge = .minX
        case "clbrdrb": pendingBorderEdge = .maxY
        case "clbrdrr": pendingBorderEdge = .maxX
        case "brdrw": if let e = pendingBorderEdge { pendingBorders.append((e, param ?? 10, 0)) }
        case "brdrcf": if !pendingBorders.isEmpty { pendingBorders[pendingBorders.count - 1].color = param ?? 0 }
        case "clcbpat": pendingBackground = param
        case "cellx":
            rowCellEdges.append(param ?? 0)
            rowCellBackgrounds.append(pendingBackground)
            rowCellBorders.append(pendingBorders)
            pendingBorders = []; pendingBackground = nil; pendingBorderEdge = nil
            table?.numberOfColumns = max(table?.numberOfColumns ?? 0, rowCellEdges.count)
        case "intbl": state.paragraph.inTable = true
        case "cell":
            if !state.skipping { append("\n", state) }
            flushText()
            cellIndex += 1
        case "row": cellIndex = 0
        case "par", "line": if !state.skipping { append("\n", state) }
        case "tab": if !state.skipping { append("\t", state) }
        case "emdash": if !state.skipping { append("\u{2014}", state) }
        case "endash": if !state.skipping { append("\u{2013}", state) }
        case "lquote": if !state.skipping { append("\u{2018}", state) }
        case "rquote": if !state.skipping { append("\u{2019}", state) }
        case "ldblquote": if !state.skipping { append("\u{201C}", state) }
        case "rdblquote": if !state.skipping { append("\u{201D}", state) }
        case "bullet": if !state.skipping { append("\u{2022}", state) }
        case "uc": state.unicodeSkip = param ?? 1
        case "u":
            guard let p = param, !state.skipping else { break }
            let value = p < 0 ? p + 0x10000 : p
            if value >= 0xD800 && value <= 0xDBFF {
                // High surrogate: look ahead for the low one (skipping its fallback too).
                pendingHigh = UInt32(value)
            } else if value >= 0xDC00 && value <= 0xDFFF, let high = pendingHigh {
                pendingHigh = nil
                let combined = 0x10000 + ((high - 0xD800) << 10) + (UInt32(value) - 0xDC00)
                if let s = UnicodeScalar(combined) { append(String(s), state) }
            } else if let s = UnicodeScalar(UInt32(value)) {
                append(String(s), state)
            }
            // Skip the fallback characters that follow (`\ucN`).
            var skip = state.unicodeSkip
            while skip > 0, index < bytes.count {
                if bytes[index] == UInt8(ascii: "\\"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "'") { index += 4 }
                else if bytes[index] == UInt8(ascii: "\\") || bytes[index] == UInt8(ascii: "{") || bytes[index] == UInt8(ascii: "}") { break }
                else { index += 1 }
                skip -= 1
            }
        default: break
        }
    }
    private var pendingHigh: UInt32? = nil

    private func flushColor() {
        if colorCollecting.seen { colors.append((colorCollecting.r, colorCollecting.g, colorCollecting.b)) } else { colors.append((-1, -1, -1)) }
        colorCollecting = (0, 0, 0, false)
    }

    private func append(_ text: String, _ state: State) {
        var text = text
        switch state.destination {
        case nil: break
        case "levelmarker": markerText += text; return
        case "nextgraphic": graphicName += text; return
        default: return
        }
        // The "¬" after an attachment's group is its placeholder in plain RTF readers.
        if skipsNotSign {
            skipsNotSign = false
            if text.hasPrefix("\u{AC}") { text.removeFirst() }
            if text.isEmpty { return }
        }
        var state = state
        if state.paragraph.inTable {
            state.paragraph.cellRow = tableRow
            state.paragraph.cellColumn = cellIndex
        } else if table != nil {
            // Text outside the table ends it.
            flushText()
            table = nil
        }
        if hasPendingState && !sameAttributes(pendingState, state) { flushText() }
        pendingState = state
        hasPendingState = true
        pendingText += text
    }

    private func appendAttachment(named name: String, _ state: State) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { skipsNotSign = true }
        guard let file = attachmentFile?(trimmed) else { return }
        if file.preferredFilename == nil { file.preferredFilename = trimmed }
        flushText()
        let attachment = NSTextAttachment(fileWrapper: file)
        var attrs = attributes(for: state)
        attrs[.attachment] = attachment
        result.append(NSAttributedString(string: "\u{FFFC}", attributes: attrs))
    }

    private func sameAttributes(_ a: State, _ b: State) -> Bool {
        a.fontIndex == b.fontIndex && a.halfPoints == b.halfPoints && a.bold == b.bold && a.italic == b.italic && a.underline == b.underline
            && a.colorIndex == b.colorIndex && a.paragraph == b.paragraph
    }

    /// One colour object per table entry: swift-corelibs-foundation's CFAttributedString
    /// traps when adjacent runs hold equal but distinct RGB NSColor objects.
    private var colorObjects: [Int: NSColor] = [:]

    private func color(_ index: Int) -> NSColor? {
        // The colour table's first entry (before the first ';') is the automatic colour, so
        // \cfN indexes the table directly.
        guard index > 0, index < colors.count else { return nil }
        if let made = colorObjects[index] { return made }
        let c = colors[index]
        let made = c.0 >= 0 ? NSColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1) : nil
        colorObjects[index] = made
        return made
    }

    private func textList(_ ls: Int, level: Int) -> [NSTextList] {
        if let cached = listObjects[ls], cached.count > level { return Array(cached[0...level]) }
        var made = listObjects[ls] ?? []
        let definition = listDefinitions[overrides[ls] ?? ls] ?? []
        while made.count <= level {
            let k = made.count
            let d: (marker: String?, nfc: Int, start: Int) = k < definition.count ? definition[k] : (nil, 23, 1)
            let format: NSTextList.MarkerFormat
            if let m = d.marker, !m.isEmpty { format = NSTextList.MarkerFormat(rawValue: m) }
            else {
                switch d.nfc {
                case 0: format = .decimal
                case 1: format = .uppercaseRoman
                case 2: format = .lowercaseRoman
                case 3: format = .uppercaseAlpha
                case 4: format = .lowercaseAlpha
                default: format = k % 2 == 0 ? .disc : .hyphen
                }
            }
            made.append(NSTextList(markerFormat: format, options: [], startingItemNumber: d.start))
        }
        listObjects[ls] = made
        return Array(made[0...level])
    }

    private func block(row: Int, column: Int) -> NSTextTableBlock? {
        guard let table, row >= 0, column >= 0 else { return nil }
        let key = row * 1000 + column
        if let b = blocks[key] { return b }
        let b = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
        if column < rowCellEdges.count {
            let left = column > 0 ? rowCellEdges[column - 1] : 0
            b.setContentWidth(max(1, CGFloat(rowCellEdges[column] - left - 2 * rowGap) / 20), type: .absoluteValueType)
            if let bg = rowCellBackgrounds[column].flatMap(color) { b.backgroundColor = bg }
            for border in rowCellBorders[column] {
                b.setWidth(CGFloat(border.width) / 20, type: .absoluteValueType, for: .border, edge: border.edge)
                b.setBorderColor(color(border.color) ?? .gray, for: border.edge)
            }
        }
        b.setWidth(CGFloat(rowGap) / 20, type: .absoluteValueType, for: .padding)
        blocks[key] = b
        return b
    }

    private func attributes(for s: State) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [:]
        let size = CGFloat(s.halfPoints) / 2
        var font = fonts[s.fontIndex].flatMap { NSFont(name: $0, size: size) } ?? NSFont.userFont(ofSize: size) ?? NSFont.systemFont(ofSize: size)
        if s.bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if s.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        attrs[.font] = font
        if let c = color(s.colorIndex) { attrs[.foregroundColor] = c }
        if s.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        let p = s.paragraph
        if p != Paragraph() {
            let style = NSMutableParagraphStyle()
            style.alignment = p.alignment
            style.headIndent = CGFloat(p.leftIndent) / 20
            style.firstLineHeadIndent = CGFloat(p.leftIndent + p.firstIndent) / 20
            if p.rightIndent > 0 { style.tailIndent = -CGFloat(p.rightIndent) / 20 }
            style.paragraphSpacingBefore = CGFloat(p.spaceBefore) / 20
            style.paragraphSpacing = CGFloat(p.spaceAfter) / 20
            style.tabStops = zip(p.tabs, p.tabKinds).map { NSTextTab(textAlignment: $0.1 == 1 ? .right : $0.1 == 2 ? .center : .left, location: CGFloat($0.0) / 20) }
            if p.list > 0 { style.textLists = textList(p.list, level: max(0, p.level)) }
            if p.inTable, let b = block(row: p.cellRow, column: p.cellColumn) { style.textBlocks = [b] }
            attrs[.paragraphStyle] = style
        }
        return attrs
    }

    private func flushText() {
        guard !pendingText.isEmpty else { return }
        result.append(NSAttributedString(string: pendingText, attributes: attributes(for: pendingState)))
        pendingText = ""
    }

    private func finish() -> NSAttributedString {
        flushText()
        return result
    }

    /// Windows-1252's upper half, where it differs from Latin-1.
    private func _cp1252(_ b: UInt8) -> UInt32 {
        let table: [UInt8: UInt32] = [0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D,
                                      0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178]
        return table[b] ?? UInt32(b)
    }
}
