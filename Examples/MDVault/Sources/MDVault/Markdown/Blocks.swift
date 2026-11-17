import Foundation

// MARK: - Model

indirect enum MDBlock: Sendable {
    case heading(level: Int, inlines: [MDInline])
    case paragraph([MDInline])
    case codeBlock(language: String?, code: String)
    case blockQuote([MDNode])
    case list(MDList)
    case table(MDTable)
    case thematicBreak
    case image(alt: String, url: String)
}

struct MDNode: Identifiable, Sendable {
    let id = UUID()
    let block: MDBlock
}

struct MDList: Sendable {
    var ordered: Bool
    var start: Int
    var tight: Bool
    var items: [MDListItem]
}

struct MDListItem: Identifiable, Sendable {
    let id = UUID()
    var checked: Bool?
    var blocks: [MDNode]
}

enum MDColumnAlign: Sendable { case leading, center, trailing }

struct MDTable: Sendable {
    var headers: [[MDInline]]
    var rows: [[[MDInline]]]
    var aligns: [MDColumnAlign]
}

// MARK: - Parser

enum MarkdownParser {

    static func parse(_ text: String) -> [MDNode] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        lines = stripFrontMatter(lines)
        return blocks(lines)
    }

    /// YAML front matter is metadata, not prose — hide it from the reader.
    private static func stripFrontMatter(_ lines: [String]) -> [String] {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return lines }
        guard let end = lines.dropFirst().firstIndex(where: {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t == "---" || t == "..."
        }) else { return lines }
        return Array(lines[(end + 1)...])
    }

    static func blocks(_ lines: [String]) -> [MDNode] {
        var out: [MDNode] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            if isBlank(line) { i += 1; continue }

            // Fenced code
            if let fence = fenceStart(line) {
                var body: [String] = []
                i += 1
                while i < lines.count, !isFenceEnd(lines[i], marker: fence.marker, count: fence.count) {
                    body.append(dropIndent(lines[i], fence.indent))
                    i += 1
                }
                if i < lines.count { i += 1 }
                out.append(MDNode(block: .codeBlock(language: fence.language,
                                                    code: body.joined(separator: "\n"))))
                continue
            }

            if isThematicBreak(line) {
                out.append(MDNode(block: .thematicBreak)); i += 1; continue
            }

            if let heading = atxHeading(line) {
                out.append(MDNode(block: .heading(level: heading.level,
                                                  inlines: MDInlineParser.parse(heading.text))))
                i += 1
                continue
            }

            // Indented (4-space) code
            if indentWidth(line) >= 4 {
                var body: [String] = []
                while i < lines.count {
                    if isBlank(lines[i]) {
                        var j = i
                        while j < lines.count, isBlank(lines[j]) { j += 1 }
                        guard j < lines.count, indentWidth(lines[j]) >= 4 else { break }
                        body.append(contentsOf: Array(repeating: "", count: j - i))
                        i = j
                    } else if indentWidth(lines[i]) >= 4 {
                        body.append(dropIndent(lines[i], 4)); i += 1
                    } else {
                        break
                    }
                }
                out.append(MDNode(block: .codeBlock(language: nil, code: body.joined(separator: "\n"))))
                continue
            }

            if isQuote(line) {
                var inner: [String] = []
                while i < lines.count {
                    if isQuote(lines[i]) {
                        inner.append(stripQuote(lines[i])); i += 1
                    } else if !isBlank(lines[i]), !isBlockStart(lines[i]) {
                        inner.append(lines[i]); i += 1          // lazy continuation
                    } else {
                        break
                    }
                }
                out.append(MDNode(block: .blockQuote(blocks(inner))))
                continue
            }

            if listMarker(line) != nil {
                let (list, next) = parseList(lines, i)
                out.append(MDNode(block: .list(list)))
                i = next
                continue
            }

            if i + 1 < lines.count, isTableStart(header: line, delimiter: lines[i + 1]) {
                let (table, next) = parseTable(lines, i)
                out.append(MDNode(block: .table(table)))
                i = next
                continue
            }

            // Paragraph (with setext heading detection)
            var paragraph: [String] = [trimLeading(line)]
            var setext: Int? = nil
            i += 1
            while i < lines.count {
                let next = lines[i]
                if isBlank(next) { break }
                if let level = setextLevel(next) { setext = level; i += 1; break }
                if isBlockStart(next) { break }
                paragraph.append(trimLeading(next))
                i += 1
            }

            let inlines = MDInlineParser.parse(paragraph.joined(separator: "\n"))
            if let level = setext {
                out.append(MDNode(block: .heading(level: level, inlines: inlines)))
            } else if let image = soleImage(inlines) {
                out.append(MDNode(block: .image(alt: image.0, url: image.1)))
            } else {
                out.append(MDNode(block: .paragraph(inlines)))
            }
        }

        return out
    }

    // MARK: Lists

    struct ListMarkerInfo {
        var indent: Int
        var ordered: Bool
        var number: Int
        var delimiter: Character
        var prefixLength: Int      // characters to drop to reach content
        var contentIndent: Int     // column that continuation lines must reach
    }

    static func listMarker(_ line: String) -> ListMarkerInfo? {
        let chars = Array(line)
        var i = 0
        var indent = 0
        while i < chars.count, chars[i] == " " || chars[i] == "\t" {
            indent += chars[i] == "\t" ? 4 : 1
            i += 1
        }
        guard indent < 4, i < chars.count else { return nil }

        var ordered = false
        var number = 1
        var delimiter: Character
        var markerEnd: Int

        if "-*+".contains(chars[i]) {
            delimiter = chars[i]
            markerEnd = i + 1
        } else if chars[i].isNumber {
            var j = i
            var digits = ""
            while j < chars.count, chars[j].isNumber, digits.count < 9 { digits.append(chars[j]); j += 1 }
            guard j < chars.count, chars[j] == "." || chars[j] == ")" else { return nil }
            ordered = true
            number = Int(digits) ?? 1
            delimiter = chars[j]
            markerEnd = j + 1
        } else {
            return nil
        }

        var k = markerEnd
        var spaces = 0
        while k < chars.count, chars[k] == " " || chars[k] == "\t" {
            spaces += chars[k] == "\t" ? 4 : 1
            k += 1
        }
        let emptyItem = k >= chars.count
        if !emptyItem, spaces == 0 { return nil }

        let spaceChars = k - markerEnd
        let useSingle = emptyItem || spaces > 4
        let dropSpaces = useSingle ? min(1, spaceChars) : spaceChars
        let markerWidth = markerEnd - i

        return ListMarkerInfo(indent: indent,
                              ordered: ordered,
                              number: number,
                              delimiter: delimiter,
                              prefixLength: markerEnd + dropSpaces,
                              contentIndent: indent + markerWidth + (useSingle ? 1 : spaces))
    }

    private static func sameFamily(_ a: ListMarkerInfo, _ b: ListMarkerInfo) -> Bool {
        a.ordered == b.ordered && a.delimiter == b.delimiter
    }

    static func parseList(_ lines: [String], _ startIndex: Int) -> (MDList, Int) {
        var i = startIndex
        let first = listMarker(lines[i])!
        var items: [MDListItem] = []
        var tight = true

        while i < lines.count {
            guard let marker = listMarker(lines[i]), sameFamily(marker, first) else { break }

            var itemLines: [String] = [String(Array(lines[i]).dropFirst(marker.prefixLength))]
            i += 1
            var blanks = 0

            while i < lines.count {
                let line = lines[i]
                if isBlank(line) { blanks += 1; i += 1; continue }

                if indentWidth(line) >= marker.contentIndent {
                    if blanks > 0 {
                        itemLines.append(contentsOf: Array(repeating: "", count: blanks))
                        tight = false
                        blanks = 0
                    }
                    itemLines.append(dropIndent(line, marker.contentIndent))
                    i += 1
                } else if blanks == 0, listMarker(line) == nil,
                          !isBlockStart(line), setextLevel(line) == nil {
                    itemLines.append(trimLeading(line))   // lazy paragraph continuation
                    i += 1
                } else {
                    break
                }
            }

            // A blank line between two items makes the whole list loose.
            if blanks > 0, i < lines.count, let next = listMarker(lines[i]), sameFamily(next, first) {
                tight = false
            }

            var checked: Bool? = nil
            if let task = taskMarker(itemLines.first ?? "") {
                checked = task.0
                itemLines[0] = task.1
            }

            items.append(MDListItem(checked: checked, blocks: blocks(itemLines)))
        }

        return (MDList(ordered: first.ordered, start: first.number, tight: tight, items: items), i)
    }

    private static func taskMarker(_ line: String) -> (Bool, String)? {
        let chars = Array(line)
        guard chars.count >= 3, chars[0] == "[", chars[2] == "]" else { return nil }
        let state = chars[1]
        guard state == " " || state == "x" || state == "X" else { return nil }
        var rest = Array(chars.dropFirst(3))
        while let f = rest.first, f == " " || f == "\t" { rest.removeFirst() }
        return (state != " ", String(rest))
    }

    // MARK: Tables

    private static func isTableStart(header: String, delimiter: String) -> Bool {
        guard header.contains("|") else { return false }
        guard let aligns = tableAligns(delimiter) else { return false }
        return aligns.count == splitRow(header).count && aligns.count >= 2
    }

    static func parseTable(_ lines: [String], _ startIndex: Int) -> (MDTable, Int) {
        var i = startIndex
        let headers = splitRow(lines[i]).map { MDInlineParser.parse($0) }
        var aligns = tableAligns(lines[i + 1]) ?? []
        i += 2

        var rows: [[[MDInline]]] = []
        while i < lines.count, !isBlank(lines[i]), lines[i].contains("|") {
            var cells = splitRow(lines[i]).map { MDInlineParser.parse($0) }
            if cells.count > headers.count { cells = Array(cells.prefix(headers.count)) }
            while cells.count < headers.count { cells.append([]) }
            rows.append(cells)
            i += 1
        }

        while aligns.count < headers.count { aligns.append(.leading) }
        return (MDTable(headers: headers, rows: rows, aligns: aligns), i)
    }

    static func splitRow(_ line: String) -> [String] {
        var chars = Array(line.trimmingCharacters(in: .whitespaces))
        if chars.first == "|" { chars.removeFirst() }
        if chars.last == "|" { chars.removeLast() }

        var cells: [String] = []
        var current = ""
        var inCode = false
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count, chars[i + 1] == "|" { current.append("|"); i += 2; continue }
            if c == "`" { inCode.toggle(); current.append(c); i += 1; continue }
            if c == "|", !inCode {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""; i += 1; continue
            }
            current.append(c); i += 1
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    static func tableAligns(_ line: String) -> [MDColumnAlign]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-"), trimmed.contains("|") else { return nil }
        guard trimmed.allSatisfy({ "-:| \t".contains($0) }) else { return nil }

        var out: [MDColumnAlign] = []
        for part in splitRow(trimmed) {
            let spec = part.trimmingCharacters(in: .whitespaces)
            guard spec.contains("-"), spec.allSatisfy({ $0 == "-" || $0 == ":" }) else { return nil }
            if spec.hasPrefix(":"), spec.hasSuffix(":") { out.append(.center) }
            else if spec.hasSuffix(":") { out.append(.trailing) }
            else { out.append(.leading) }
        }
        return out.isEmpty ? nil : out
    }

    // MARK: Line classification

    struct Fence {
        var marker: Character
        var count: Int
        var indent: Int
        var language: String?
    }

    static func fenceStart(_ line: String) -> Fence? {
        let chars = Array(line)
        var i = 0
        var indent = 0
        while i < chars.count, chars[i] == " " { indent += 1; i += 1 }
        guard indent < 4, i < chars.count, chars[i] == "`" || chars[i] == "~" else { return nil }

        let marker = chars[i]
        var count = 0
        while i < chars.count, chars[i] == marker { count += 1; i += 1 }
        guard count >= 3 else { return nil }

        let info = String(chars[i...]).trimmingCharacters(in: .whitespaces)
        if marker == "`", info.contains("`") { return nil }
        let language = info.split(separator: " ").first.map(String.init)
        return Fence(marker: marker, count: count, indent: indent,
                     language: (language?.isEmpty ?? true) ? nil : language)
    }

    static func isFenceEnd(_ line: String, marker: Character, count: Int) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= count && !trimmed.isEmpty && trimmed.allSatisfy { $0 == marker }
    }

    static func atxHeading(_ line: String) -> (level: Int, text: String)? {
        let chars = Array(line)
        var i = 0
        while i < chars.count, chars[i] == " " { i += 1 }
        guard i < 4, i < chars.count, chars[i] == "#" else { return nil }

        var level = 0
        while i < chars.count, chars[i] == "#" { level += 1; i += 1 }
        guard level <= 6 else { return nil }
        guard i >= chars.count || chars[i] == " " || chars[i] == "\t" else { return nil }

        var text = String(chars[i...]).trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") { text = String(text.dropLast()) }
        return (level, text.trimmingCharacters(in: .whitespaces))
    }

    static func setextLevel(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, indentWidth(line) < 4 else { return nil }
        if trimmed.allSatisfy({ $0 == "=" }) { return 1 }
        if trimmed.allSatisfy({ $0 == "-" }), trimmed.count >= 2 { return 2 }
        return nil
    }

    static func isThematicBreak(_ line: String) -> Bool {
        guard indentWidth(line) < 4 else { return false }
        let stripped = line.filter { $0 != " " && $0 != "\t" }
        guard stripped.count >= 3 else { return false }
        guard let first = stripped.first, "-*_".contains(first) else { return false }
        return stripped.allSatisfy { $0 == first }
    }

    static func isQuote(_ line: String) -> Bool {
        let chars = Array(line)
        var i = 0
        while i < chars.count, chars[i] == " " { i += 1 }
        return i < 4 && i < chars.count && chars[i] == ">"
    }

    static func stripQuote(_ line: String) -> String {
        var chars = Array(line)
        var i = 0
        while i < chars.count, chars[i] == " " { i += 1 }
        if i < chars.count, chars[i] == ">" { i += 1 }
        if i < chars.count, chars[i] == " " { i += 1 }
        chars.removeFirst(i)
        return String(chars)
    }

    static func isBlockStart(_ line: String) -> Bool {
        fenceStart(line) != nil
            || atxHeading(line) != nil
            || isThematicBreak(line)
            || isQuote(line)
            || listMarker(line) != nil
    }

    static func isBlank(_ line: String) -> Bool {
        line.allSatisfy { $0 == " " || $0 == "\t" }
    }

    static func indentWidth(_ line: String) -> Int {
        var width = 0
        for c in line {
            if c == " " { width += 1 }
            else if c == "\t" { width += 4 }
            else { break }
        }
        return width
    }

    static func dropIndent(_ line: String, _ columns: Int) -> String {
        let chars = Array(line)
        var removed = 0
        var i = 0
        while i < chars.count, removed < columns {
            if chars[i] == " " { removed += 1; i += 1 }
            else if chars[i] == "\t" { removed += 4; i += 1 }
            else { break }
        }
        return String(chars[i...])
    }

    static func trimLeading(_ line: String) -> String {
        var chars = Array(line)
        var i = 0
        while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 }
        chars.removeFirst(i)
        return String(chars)
    }

    private static func soleImage(_ inlines: [MDInline]) -> (String, String)? {
        var found: (String, String)? = nil
        for node in inlines {
            switch node {
            case .image(let alt, let url):
                if found != nil { return nil }
                found = (alt, url)
            case .text(let t) where t.trimmingCharacters(in: .whitespaces).isEmpty:
                continue
            case .hardBreak:
                continue
            default:
                return nil
            }
        }
        return found
    }
}
