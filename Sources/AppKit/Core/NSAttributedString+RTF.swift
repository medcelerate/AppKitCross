// RTF reading and writing for NSAttributedString (the AppKit additions
// `init(rtf:documentAttributes:)`, `rtf(from:documentAttributes:)`,
// `data(from:documentAttributes:)` and `init(data:options:documentAttributes:)`), so
// document-based applications can save rich text on every platform (ADR-0017).
//
// The dialect written is the one TextEdit writes: a font table, a colour table, and per
// run the font (`\f`), size (`\fs`, half points), bold, italic, underline and colour
// (`\cf`), with paragraph alignment (`\ql \qc \qr \qj`) at each paragraph; non-ASCII
// characters as `\uN` escapes. The reader takes the same and what other editors commonly
// add (group nesting with state, `\'xx` Latin-1 escapes, `\uc`, skipped `\*`
// destinations, `\line`, `\tab`, `\plain`, `\pard`). Images, tables, lists and
// styles are not read.
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

// MARK: - Writer

struct _RTFWriter {
    let attributedString: NSAttributedString
    let range: NSRange

    private struct Run {
        var text: String
        var fontIndex: Int
        var halfPoints: Int
        var bold: Bool
        var italic: Bool
        var underline: Bool
        var colorIndex: Int
        var alignment: NSTextAlignment
    }

    func write() -> Data? {
        var fonts: [String] = []
        var colors: [(Int, Int, Int)] = []
        var runs: [Run] = []
        let text = attributedString.string as NSString
        attributedString.enumerateAttributes(in: range, options: []) { attrs, r, _ in
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
            var colorIndex = 0
            if let c = attrs[.foregroundColor] as? NSColor {
                let rgb = (Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
                if let i = colors.firstIndex(where: { $0 == rgb }) { colorIndex = i + 1 } else { colors.append(rgb); colorIndex = colors.count }
            }
            let underline = ((attrs[.underlineStyle] as? Int) ?? (attrs[.underlineStyle] as? NSNumber)?.intValue ?? 0) != 0
            let alignment = (attrs[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? .natural
            runs.append(Run(text: text.substring(with: r), fontIndex: fontIndex, halfPoints: Int(((font?.pointSize ?? 12) * 2).rounded()),
                            bold: bold, italic: italic, underline: underline, colorIndex: colorIndex, alignment: alignment))
        }
        var out = "{\\rtf1\\ansi\\ansicpg1252\\cocoartf2822\\cocoatextscaling0\\cocoaplatform0\n"
        out += "{\\fonttbl"
        for (i, f) in fonts.enumerated() { out += "\\f\(i)\\fnil\\fcharset0 \(f);" }
        out += "}\n{\\colortbl;"
        for c in colors { out += "\\red\(c.0)\\green\(c.1)\\blue\(c.2);" }
        out += "}\n"
        var atParagraphStart = true
        var state: Run? = nil
        for run in runs {
            for scalar in run.text.unicodeScalars {
                if atParagraphStart {
                    out += "\\pard"
                    switch run.alignment {
                    case .center: out += "\\qc"
                    case .right: out += "\\qr"
                    case .justified: out += "\\qj"
                    default: out += "\\ql"
                    }
                    out += "\\pardirnatural\\partightenfactor0\n"
                    atParagraphStart = false
                    state = nil
                }
                if state == nil || state!.fontIndex != run.fontIndex || state!.halfPoints != run.halfPoints || state!.bold != run.bold
                    || state!.italic != run.italic || state!.underline != run.underline || state!.colorIndex != run.colorIndex {
                    out += "\\f\(run.fontIndex)\\fs\(run.halfPoints)"
                    out += run.bold ? "\\b" : "\\b0"
                    out += run.italic ? "\\i" : "\\i0"
                    out += run.underline ? "\\ul" : "\\ulnone"
                    out += "\\cf\(run.colorIndex) "
                    state = run
                }
                switch scalar {
                case "\n", "\r", "\u{2029}":
                    out += "\\par\n"
                    atParagraphStart = true
                case "\t": out += "\\tab "
                case "\\": out += "\\\\"
                case "{": out += "\\{"
                case "}": out += "\\}"
                default:
                    if scalar.isASCII {
                        out.unicodeScalars.append(scalar)
                    } else if scalar.value <= 0xFFFF {
                        out += "\\u\(Int(Int16(truncatingIfNeeded: scalar.value)))?"
                    } else {
                        // Supplementary planes: a surrogate pair of escapes, as Word does.
                        let v = scalar.value - 0x10000
                        let high = 0xD800 + (v >> 10), low = 0xDC00 + (v & 0x3FF)
                        out += "\\u\(Int(Int16(truncatingIfNeeded: high)))?\\u\(Int(Int16(truncatingIfNeeded: low)))?"
                    }
                }
            }
        }
        out += "}"
        return out.data(using: .utf8)
    }
}

// MARK: - Reader

final class _RTFReader {
    private let bytes: [UInt8]
    private var index = 0

    private struct State {
        var fontIndex = 0
        var halfPoints = 24
        var bold = false
        var italic = false
        var underline = false
        var colorIndex = 0
        var alignment: NSTextAlignment = .natural
        var unicodeSkip = 1
        var skipping = false            // inside a destination we ignore
        var destination: String? = nil  // "fonttbl", "colortbl"
    }

    private var fonts: [Int: String] = [:]
    private var colors: [(Int, Int, Int)] = []
    private var fontCollecting: (index: Int, name: String)? = nil
    private var colorCollecting: (r: Int, g: Int, b: Int, seen: Bool) = (0, 0, 0, false)
    private let result = NSMutableAttributedString(string: "")
    private var pendingText = ""
    private var pendingState = State()
    private var hasPendingState = false

    init(data: Data) { bytes = Array(data) }

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
        case "stylesheet", "info", "pict", "header", "footer", "listtable", "listoverridetable", "expandedcolortbl", "field", "fldinst", "themedata", "colorschememapping", "latentstyles", "datastore", "xmlnstbl", "rsidtbl", "generator", "mmathPr":
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
        case "pard": state.alignment = .natural
        case "ql": state.alignment = .left
        case "qc": state.alignment = .center
        case "qr": state.alignment = .right
        case "qj": state.alignment = .justified
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
        guard state.destination == nil else { return }
        if hasPendingState && !sameAttributes(pendingState, state) { flushText() }
        pendingState = state
        hasPendingState = true
        pendingText += text
    }

    private func sameAttributes(_ a: State, _ b: State) -> Bool {
        a.fontIndex == b.fontIndex && a.halfPoints == b.halfPoints && a.bold == b.bold && a.italic == b.italic && a.underline == b.underline && a.colorIndex == b.colorIndex && a.alignment == b.alignment
    }

    private func flushText() {
        guard !pendingText.isEmpty else { return }
        var attrs: [NSAttributedString.Key: Any] = [:]
        let size = CGFloat(pendingState.halfPoints) / 2
        var font = fonts[pendingState.fontIndex].flatMap { NSFont(name: $0, size: size) } ?? NSFont.userFont(ofSize: size) ?? NSFont.systemFont(ofSize: size)
        if pendingState.bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if pendingState.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        attrs[.font] = font
        // The colour table's first entry (before the first ';') is the automatic colour, so
        // \cfN indexes the table directly.
        if pendingState.colorIndex > 0, pendingState.colorIndex < colors.count {
            let c = colors[pendingState.colorIndex]
            if c.0 >= 0 { attrs[.foregroundColor] = NSColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1) }
        }
        if pendingState.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if pendingState.alignment != .natural {
            let p = NSMutableParagraphStyle()
            p.alignment = pendingState.alignment
            attrs[.paragraphStyle] = p
        }
        result.append(NSAttributedString(string: pendingText, attributes: attrs))
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
