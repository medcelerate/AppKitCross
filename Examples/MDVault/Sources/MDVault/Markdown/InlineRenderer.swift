import AppKit
import SwiftUI

struct MDInlineStyle {
    var size: CGFloat
    var bold: Bool = false
    var italic: Bool = false
    var mono: Bool = false
    var strike: Bool = false
    var weight: NSFont.Weight = .regular
    var color: Color? = nil
    var link: URL? = nil
}

enum MDInlineRenderer {
    static func attributed(_ inlines: [MDInline], style: MDInlineStyle) -> AttributedString {
        var result = AttributedString()
        for node in inlines { result.append(render(node, style)) }
        return result
    }

    private static func render(_ node: MDInline, _ style: MDInlineStyle) -> AttributedString {
        switch node {
        case .text(let text):
            return styled(text, style)

        case .hardBreak:
            return AttributedString("\n")

        case .code(let code):
            var inner = style
            inner.mono = true
            var run = styled(code, inner)
            run.backgroundColor = Color.primary.opacity(0.08)
            return run

        case .strong(let inner):
            var s = style; s.bold = true
            return attributed(inner, style: s)

        case .emphasis(let inner):
            var s = style; s.italic = true
            return attributed(inner, style: s)

        case .strikethrough(let inner):
            var s = style; s.strike = true
            return attributed(inner, style: s)

        case .link(let inner, let destination):
            var s = style
            s.link = url(from: destination)
            s.color = .accentColor
            var run = attributed(inner, style: s)
            run.underlineStyle = .single
            return run

        case .image(let alt, _):
            var s = style
            s.italic = true
            s.color = .secondary
            return styled(alt.isEmpty ? "image" : alt, s)
        }
    }

    private static func styled(_ text: String, _ style: MDInlineStyle) -> AttributedString {
        var run = AttributedString(text)
        let size = style.mono ? style.size * 0.92 : style.size
        run.font = Font(MDFont.make(size: size,
                                    bold: style.bold,
                                    italic: style.italic,
                                    mono: style.mono,
                                    weight: style.weight))
        if let color = style.color { run.foregroundColor = color }
        if style.strike { run.strikethroughStyle = .single }
        if let link = style.link { run.link = link }
        return run
    }

    private static func url(from destination: String) -> URL? {
        if let url = URL(string: destination), url.scheme != nil { return url }
        if let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
           let url = URL(string: encoded), url.scheme != nil {
            return url
        }
        return nil
    }

    /// Plain text of an inline run — used for things like copying or fallbacks.
    static func plainText(_ inlines: [MDInline]) -> String {
        inlines.map { node -> String in
            switch node {
            case .text(let t), .code(let t): return t
            case .strong(let i), .emphasis(let i), .strikethrough(let i): return plainText(i)
            case .link(let i, _): return plainText(i)
            case .image(let alt, _): return alt
            case .hardBreak: return "\n"
            }
        }.joined()
    }
}
