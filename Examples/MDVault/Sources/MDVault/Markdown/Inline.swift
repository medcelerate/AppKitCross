import Foundation

// MARK: - Model

indirect enum MDInline: Sendable {
    case text(String)
    case code(String)
    case strong([MDInline])
    case emphasis([MDInline])
    case strikethrough([MDInline])
    case link([MDInline], String)
    case image(String, String)   // alt, destination
    case hardBreak
}

// MARK: - Parser

/// Hand-rolled inline scanner. Handles escapes, code spans, nested emphasis,
/// strikethrough, links, images, autolinks and hard line breaks.
struct MDInlineParser {
    private static let escapable: Set<Character> = Set("\\`*_{}[]()#+-.!>~|\"'")

    private let ch: [Character]
    private var pos = 0

    static func parse(_ text: String) -> [MDInline] {
        var parser = MDInlineParser(text)
        return parser.parseRun(stop: nil)
    }

    private init(_ text: String) { ch = Array(text) }

    private mutating func parseRun(stop: String?) -> [MDInline] {
        var out: [MDInline] = []
        var buf: [Character] = []

        func flush() {
            if !buf.isEmpty { out.append(.text(String(buf))); buf.removeAll(keepingCapacity: true) }
        }

        while pos < ch.count {
            if let stop, matches(stop, at: pos), closeIsValid(stop, at: pos) { break }

            let c = ch[pos]
            switch c {
            case "\\":
                if pos + 1 < ch.count, ch[pos + 1] == "\n" {
                    flush(); out.append(.hardBreak); pos += 2
                    skipLineLeadingSpace()
                } else if pos + 1 < ch.count, Self.escapable.contains(ch[pos + 1]) {
                    buf.append(ch[pos + 1]); pos += 2
                } else {
                    buf.append(c); pos += 1
                }

            case "\n":
                var trailing = 0
                while trailing < buf.count, buf[buf.count - 1 - trailing] == " " { trailing += 1 }
                if trailing > 0 { buf.removeLast(trailing) }
                if trailing >= 2 {
                    flush(); out.append(.hardBreak)
                } else {
                    buf.append(" ")
                }
                pos += 1
                skipLineLeadingSpace()

            case "`":
                let run = runLength(of: "`", at: pos)
                if let close = closingBacktickRun(length: run, from: pos + run) {
                    flush()
                    var code = Array(ch[(pos + run)..<close])
                    if code.count >= 2, code.first == " ", code.last == " ",
                       code.contains(where: { $0 != " " }) {
                        code.removeFirst(); code.removeLast()
                    }
                    out.append(.code(String(code).replacingOccurrences(of: "\n", with: " ")))
                    pos = close + run
                } else {
                    buf.append(contentsOf: Array(repeating: "`", count: run))
                    pos += run
                }

            case "*", "_":
                if let node = parseEmphasis() { flush(); out.append(node) }
                else { buf.append(c); pos += 1 }

            case "~":
                if runLength(of: "~", at: pos) >= 2,
                   let node = parseDelimited(marker: "~~", make: { .strikethrough($0) }) {
                    flush(); out.append(node)
                } else {
                    buf.append(c); pos += 1
                }

            case "[":
                if let node = parseLink(isImage: false) { flush(); out.append(node) }
                else { buf.append(c); pos += 1 }

            case "!":
                if pos + 1 < ch.count, ch[pos + 1] == "[" {
                    let save = pos
                    pos += 1
                    if let node = parseLink(isImage: true) { flush(); out.append(node) }
                    else { pos = save + 1; buf.append(c) }
                } else {
                    buf.append(c); pos += 1
                }

            case "<":
                if let node = parseAutolink() { flush(); out.append(node) }
                else { buf.append(c); pos += 1 }

            default:
                buf.append(c); pos += 1
            }
        }

        flush()
        return out
    }

    // MARK: Emphasis

    private mutating func parseEmphasis() -> MDInline? {
        let marker = ch[pos]
        if marker == "_", pos > 0, isWordChar(ch[pos - 1]) { return nil }
        let run = runLength(of: marker, at: pos)
        if run >= 2,
           let node = parseDelimited(marker: String(repeating: marker, count: 2), make: { .strong($0) }) {
            return node
        }
        return parseDelimited(marker: String(marker), make: { .emphasis($0) })
    }

    private mutating func parseDelimited(marker: String, make: ([MDInline]) -> MDInline) -> MDInline? {
        let length = marker.count
        let after = pos + length
        guard after < ch.count, !ch[after].isWhitespace else { return nil }

        let save = pos
        pos = after
        let inner = parseRun(stop: marker)
        if !inner.isEmpty, matches(marker, at: pos), closeIsValid(marker, at: pos) {
            pos += length
            return make(inner)
        }
        pos = save
        return nil
    }

    // MARK: Links

    private mutating func parseLink(isImage: Bool) -> MDInline? {
        guard let close = matchingBracket(from: pos),
              close + 1 < ch.count, ch[close + 1] == "(",
              let paren = matchingParen(from: close + 1) else { return nil }

        let label = String(ch[(pos + 1)..<close])
        let destination = Self.destination(from: String(ch[(close + 2)..<paren]))
        pos = paren + 1

        if isImage { return .image(label, destination) }
        return .link(MDInlineParser.parse(label), destination)
    }

    private static func destination(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<"), let end = trimmed.firstIndex(of: ">") {
            return String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
        }
        if let space = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" || $0 == "\n" }) {
            return String(trimmed[..<space])
        }
        return trimmed
    }

    private mutating func parseAutolink() -> MDInline? {
        var i = pos + 1
        var body: [Character] = []
        while i < ch.count, ch[i] != ">", !ch[i].isWhitespace { body.append(ch[i]); i += 1 }
        guard i < ch.count, ch[i] == ">", !body.isEmpty else { return nil }

        let text = String(body)
        let isURL = text.contains("://") || text.hasPrefix("mailto:")
        let isEmail = !isURL && text.contains("@") && text.contains(".")
        guard isURL || isEmail else { return nil }

        pos = i + 1
        return .link([.text(text)], isEmail ? "mailto:\(text)" : text)
    }

    // MARK: Scanning helpers

    private mutating func skipLineLeadingSpace() {
        while pos < ch.count, ch[pos] == " " || ch[pos] == "\t" { pos += 1 }
    }

    private func runLength(of char: Character, at start: Int) -> Int {
        var n = 0
        var i = start
        while i < ch.count, ch[i] == char { n += 1; i += 1 }
        return n
    }

    private func matches(_ s: String, at index: Int) -> Bool {
        let chars = Array(s)
        guard index + chars.count <= ch.count else { return false }
        for (offset, c) in chars.enumerated() where ch[index + offset] != c { return false }
        return true
    }

    private func closeIsValid(_ marker: String, at index: Int) -> Bool {
        guard index > 0, !ch[index - 1].isWhitespace else { return false }
        if marker.first == "_" {
            let end = index + marker.count
            if end < ch.count, isWordChar(ch[end]) { return false }
        }
        return true
    }

    private func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber }

    private func closingBacktickRun(length: Int, from start: Int) -> Int? {
        var i = start
        while i < ch.count {
            if ch[i] == "`" {
                let run = runLength(of: "`", at: i)
                if run == length { return i }
                i += run
            } else {
                i += 1
            }
        }
        return nil
    }

    private func matchingBracket(from start: Int) -> Int? {
        var depth = 0
        var i = start
        while i < ch.count {
            let c = ch[i]
            if c == "\\" { i += 2; continue }
            if c == "`" { i += runLength(of: "`", at: i); continue }
            if c == "[" { depth += 1 }
            if c == "]" {
                depth -= 1
                if depth == 0 { return i }
            }
            if c == "\n", i + 1 < ch.count, ch[i + 1] == "\n" { return nil }
            i += 1
        }
        return nil
    }

    private func matchingParen(from start: Int) -> Int? {
        var depth = 0
        var i = start
        while i < ch.count {
            let c = ch[i]
            if c == "\\" { i += 2; continue }
            if c == "(" { depth += 1 }
            if c == ")" {
                depth -= 1
                if depth == 0 { return i }
            }
            if c == "\n" { return nil }
            i += 1
        }
        return nil
    }
}
