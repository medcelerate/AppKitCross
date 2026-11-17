import AppKit

/// Regex-based markdown highlighter for the raw editor. It never hides syntax —
/// `##`, `**`, backticks and friends stay visible, just tinted so structure pops.
enum MarkdownHighlighter {

    private static let sizeLimit = 400_000

    // MARK: Colors

    private static let markerColor = NSColor.tertiaryLabelColor
    private static let headingMarker = NSColor.systemBlue
    private static let listMarker = NSColor.systemOrange
    private static let quoteMarker = NSColor.systemPurple
    private static let quoteText = NSColor.secondaryLabelColor
    private static let codeText = NSColor.mdDynamic(
        light: NSColor(srgbRed: 0.05, green: 0.44, blue: 0.44, alpha: 1),
        dark: NSColor(srgbRed: 0.44, green: 0.85, blue: 0.82, alpha: 1))
    private static let codeBackground = NSColor.mdDynamic(
        light: NSColor(white: 0, alpha: 0.055),
        dark: NSColor(white: 1, alpha: 0.075))
    private static let linkText = NSColor.linkColor
    private static let urlText = NSColor.secondaryLabelColor
    private static let taskColor = NSColor.systemGreen

    // MARK: Patterns

    private static func re(_ pattern: String) -> NSRegularExpression {
        // Patterns are literals checked at build time; a throw here is a programmer error.
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    private static let heading = re("^[ \\t]{0,3}(#{1,6})([ \\t]+)(.*)$")
    private static let quote = re("^[ \\t]{0,3}(>[ \\t]?)+(.*)$")
    private static let bullet = re("^([ \\t]*)([-*+])([ \\t]+)")
    private static let ordered = re("^([ \\t]*)([0-9]{1,9}[.)])([ \\t]+)")
    private static let task = re("^[ \\t]*(?:[-*+]|[0-9]{1,9}[.)])[ \\t]+(\\[[ xX]\\])")
    private static let rule = re("^[ \\t]{0,3}((?:[-*_][ \\t]*){3,})$")
    private static let strong = re("(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let emphasisStar = re("(?<![\\*\\w])(\\*)(?=[^\\s\\*])([^\\*\\n]+?)(?<=[^\\s\\*])(\\*)(?!\\*)")
    private static let emphasisUnderscore = re("(?<![_\\w])(_)(?=[^\\s_])([^_\\n]+?)(?<=[^\\s_])(_)(?![_\\w])")
    private static let strike = re("(~~)(?=\\S)(.+?)(?<=\\S)(~~)")
    private static let inlineCode = re("(`+)([^`\\n]*?)(\\1)")
    private static let link = re("(!?\\[)([^\\]\\n]*)(\\]\\()([^)\\n]*)(\\))")
    private static let autolink = re("<((?:https?|mailto|file):[^>\\s]+)>")
    private static let fenced = re("^([ \\t]{0,3})(```|~~~)([^\\n]*)\\n([\\s\\S]*?)(^[ \\t]{0,3}\\2[^\\n]*$|\\z)")

    // MARK: Entry point

    static func apply(to storage: NSTextStorage, fontSize: CGFloat) {
        let nsText = storage.string as NSString
        let full = NSRange(location: 0, length: nsText.length)
        let base = MDFont.make(size: fontSize, mono: true)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = fontSize * 0.3
        paragraph.defaultTabInterval = fontSize * 2
        paragraph.tabStops = []

        storage.beginEditing()
        defer { storage.endEditing() }

        storage.setAttributes([.font: base,
                               .foregroundColor: NSColor.labelColor,
                               .paragraphStyle: paragraph],
                              range: full)

        guard nsText.length <= sizeLimit else { return }

        let text = storage.string

        // Block level
        heading.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let m = match else { return }
            let level = m.range(at: 1).length
            let bump: CGFloat = level == 1 ? 1.32 : level == 2 ? 1.2 : level == 3 ? 1.1 : 1.0
            storage.addAttributes([.foregroundColor: headingMarker,
                                   .font: MDFont.make(size: fontSize * bump, bold: true, mono: true)],
                                  range: m.range(at: 1))
            storage.addAttributes([.foregroundColor: NSColor.labelColor,
                                   .font: MDFont.make(size: fontSize * bump, bold: true, mono: true)],
                                  range: m.range(at: 3))
        }

        quote.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let m = match else { return }
            storage.addAttribute(.foregroundColor, value: quoteText, range: m.range)
            if m.range(at: 1).location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: quoteMarker, range: m.range(at: 1))
            }
        }

        for pattern in [bullet, ordered] {
            pattern.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let m = match else { return }
                storage.addAttributes([.foregroundColor: listMarker,
                                       .font: MDFont.make(size: fontSize, bold: true, mono: true)],
                                      range: m.range(at: 2))
            }
        }

        task.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let m = match else { return }
            storage.addAttributes([.foregroundColor: taskColor,
                                   .font: MDFont.make(size: fontSize, bold: true, mono: true)],
                                  range: m.range(at: 1))
        }

        rule.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let m = match else { return }
            storage.addAttribute(.foregroundColor, value: markerColor, range: m.range(at: 1))
        }

        // Inline level
        strong.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let m = match else { return }
            storage.addAttribute(.font, value: MDFont.make(size: fontSize, bold: true, mono: true), range: m.range)
            dim(storage, m.range(at: 1))
            dim(storage, NSRange(location: m.range.upperBound - m.range(at: 1).length,
                                 length: m.range(at: 1).length))
        }

        for pattern in [emphasisStar, emphasisUnderscore] {
            pattern.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let m = match else { return }
                storage.addAttribute(.font,
                                     value: MDFont.make(size: fontSize, italic: true, mono: true),
                                     range: m.range(at: 2))
                dim(storage, m.range(at: 1))
                dim(storage, m.range(at: 3))
            }
        }

        strike.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let m = match else { return }
            storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                   .foregroundColor: NSColor.secondaryLabelColor],
                                  range: m.range(at: 2))
            dim(storage, m.range(at: 1))
            dim(storage, m.range(at: 3))
        }

        link.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let m = match else { return }
            dim(storage, m.range(at: 1))
            storage.addAttribute(.foregroundColor, value: linkText, range: m.range(at: 2))
            dim(storage, m.range(at: 3))
            storage.addAttribute(.foregroundColor, value: urlText, range: m.range(at: 4))
            dim(storage, m.range(at: 5))
        }

        autolink.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let m = match else { return }
            storage.addAttribute(.foregroundColor, value: linkText, range: m.range(at: 1))
        }

        inlineCode.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let m = match, m.range(at: 2).length > 0 else { return }
            storage.addAttributes([.foregroundColor: codeText,
                                   .backgroundColor: codeBackground,
                                   .font: base],
                                  range: m.range)
        }

        // Fenced blocks last so nothing inside them keeps inline styling.
        fenced.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let m = match else { return }
            storage.addAttributes([.font: base,
                                   .foregroundColor: NSColor.labelColor,
                                   .backgroundColor: codeBackground],
                                  range: m.range)
            storage.addAttribute(.foregroundColor, value: markerColor, range: m.range(at: 2))
            if m.range(at: 3).length > 0 {
                storage.addAttribute(.foregroundColor, value: headingMarker, range: m.range(at: 3))
            }
            if m.range(at: 5).length > 0 {
                storage.addAttribute(.foregroundColor, value: markerColor, range: m.range(at: 5))
            }
        }
    }

    private static func dim(_ storage: NSTextStorage, _ range: NSRange) {
        guard range.location != NSNotFound, range.length > 0 else { return }
        storage.addAttribute(.foregroundColor, value: markerColor, range: range)
    }
}
