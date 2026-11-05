// Primitive views: Text, Font, Color, Image, Button, TextField, Toggle, Slider, Divider,
// ScrollView, List, Label, shapes.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: Font

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/font
public struct Font: Hashable, Sendable {
    public enum Weight: Hashable, Sendable { case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black }
    public enum Design: Hashable, Sendable { case `default`, serif, rounded, monospaced }
    public enum TextStyle: Hashable, CaseIterable, Sendable { case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2 }

    enum Base: Hashable { case system(CGFloat, Design), custom(String, CGFloat), style(TextStyle, Design) }
    let base: Base
    var weight: Weight? = nil
    var isItalic = false
    var monospacedDigits = false
    var width: Width? = nil
    var smallCapsStyle: SmallCaps? = nil
    var leading: Leading? = nil

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/font/width
    public struct Width: Hashable, Sendable {
        public var value: CGFloat
        public init(_ value: CGFloat) { self.value = value }
        public static let compressed = Width(-0.3)
        public static let condensed = Width(-0.2)
        public static let standard = Width(0)
        public static let expanded = Width(0.2)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/font/leading
    public enum Leading: Hashable, Sendable { case standard, tight, loose }
    enum SmallCaps: Hashable { case all, lowercase, uppercase }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/font/width(_:)
    public func width(_ width: Width) -> Font { var f = self; f.width = width; return f }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/font/smallcaps()
    public func smallCaps() -> Font { var f = self; f.smallCapsStyle = .all; return f }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/font/lowercasesmallcaps()
    public func lowercaseSmallCaps() -> Font { var f = self; f.smallCapsStyle = .lowercase; return f }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/font/uppercasesmallcaps()
    public func uppercaseSmallCaps() -> Font { var f = self; f.smallCapsStyle = .uppercase; return f }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/font/leading(_:)
    public func leading(_ leading: Leading) -> Font { var f = self; f.leading = leading; return f }

    public static let largeTitle = Font(base: .style(.largeTitle, .default))
    public static let title = Font(base: .style(.title, .default))
    public static let title2 = Font(base: .style(.title2, .default))
    public static let title3 = Font(base: .style(.title3, .default))
    public static let headline = Font(base: .style(.headline, .default))
    public static let subheadline = Font(base: .style(.subheadline, .default))
    public static let body = Font(base: .style(.body, .default))
    public static let callout = Font(base: .style(.callout, .default))
    public static let footnote = Font(base: .style(.footnote, .default))
    public static let caption = Font(base: .style(.caption, .default))
    public static let caption2 = Font(base: .style(.caption2, .default))

    public static func system(size: CGFloat, weight: Weight = .regular, design: Design = .default) -> Font {
        var f = Font(base: .system(size, design)); f.weight = weight; return f
    }
    public static func system(_ style: TextStyle, design: Design = .default) -> Font { Font(base: .style(style, design)) }
    public static func system(_ style: TextStyle, design: Design? = nil, weight: Weight? = nil) -> Font {
        var f = Font(base: .style(style, design ?? .default)); f.weight = weight; return f
    }
    public static func custom(_ name: String, size: CGFloat) -> Font { Font(base: .custom(name, size)) }
    public static func custom(_ name: String, fixedSize: CGFloat) -> Font { Font(base: .custom(name, fixedSize)) }

    public func weight(_ weight: Weight) -> Font { var f = self; f.weight = weight; return f }
    public func bold() -> Font { weight(.bold) }
    public func italic() -> Font { var f = self; f.isItalic = true; return f }
    public func monospacedDigit() -> Font { var f = self; f.monospacedDigits = true; return f }
    public func monospaced() -> Font {
        switch base {
        case .system(let s, _): return Font(base: .system(s, .monospaced), weight: weight, isItalic: isItalic)
        case .style(let st, _): return Font(base: .style(st, .monospaced), weight: weight, isItalic: isItalic)
        case .custom: return self
        }
    }

    static func pointSize(_ style: TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 26
        case .title: return 22
        case .title2: return 17
        case .title3: return 15
        case .headline: return 13
        case .subheadline: return 11
        case .body: return 13
        case .callout: return 12
        case .footnote: return 10
        case .caption: return 10
        case .caption2: return 10
        }
    }

    static func nsWeight(_ w: Weight) -> NSFont.Weight {
        switch w {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }

    @MainActor public var nsFont: NSFont {
        var w = weight
        let size: CGFloat
        let design: Design
        switch base {
        case .system(let s, let d): size = s; design = d
        case .style(let st, let d):
            size = Font.pointSize(st); design = d
            if st == .headline, w == nil { w = .semibold }
        case .custom(let name, let s):
            let f = NSFont(name: name, size: s) ?? NSFont.systemFont(ofSize: s)
            return isItalic ? (NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask)) : f
        }
        var f: NSFont = design == .monospaced ? (NSFont.monospacedSystemFont(ofSize: size, weight: Font.nsWeight(w ?? .regular))) : NSFont.systemFont(ofSize: size, weight: Font.nsWeight(w ?? .regular))
        if isItalic { f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask) }
        return f
    }
}

// MARK: Color

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/color
public struct Color: Hashable, Sendable, View, _PrimitiveView {
    public typealias Body = Never
    public enum RGBColorSpace: Hashable, Sendable { case sRGB, sRGBLinear, displayP3 }
    /// An NSColor kept as is (system colours resolve dynamically); identity-hashed.
    final class _NSColorBox: @unchecked Sendable, Hashable {
        let color: NSColor
        init(_ c: NSColor) { color = c }
        static func == (a: _NSColorBox, b: _NSColorBox) -> Bool { a === b || a.color == b.color }
        func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(color)) }
    }
    enum Storage: Hashable { case rgb(Double, Double, Double, Double), named(String), ns(_NSColorBox) }
    let storage: Storage
    var opacityMultiplier: Double = 1

    public init(_ colorSpace: RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1) { storage = .rgb(red, green, blue, opacity) }
    public init(_ colorSpace: RGBColorSpace = .sRGB, white: Double, opacity: Double = 1) { storage = .rgb(white, white, white, opacity) }
    public init(red: Double, green: Double, blue: Double) { storage = .rgb(red, green, blue, 1) }
    public init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1) {
        let c = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: opacity)
        storage = .rgb(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), opacity)
    }
    public init(_ name: String, bundle: Bundle? = nil) { storage = .named(name) }
    public init(nsColor: NSColor) { storage = .ns(_NSColorBox(nsColor)) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/color/init(_:)-4pf3
    public init(_ color: NSColor) { self.init(nsColor: color) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/color/init(cgcolor:)
    public init(cgColor: CGColor) { self.init(nsColor: NSColor(cgColor: cgColor) ?? .clear) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/color/init(_:)-7rkxx
    public init(_ cgColor: CGColor) { self.init(cgColor: cgColor) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/color/init(_:)-57v2
    public init(_ resolved: Color.Resolved) {
        storage = .rgb(Double(resolved.red), Double(resolved.green), Double(resolved.blue), Double(resolved.opacity))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/color/cgcolor
    /// Nil for dynamic (named and system) colours, as on macOS.
    public var cgColor: CGColor? {
        switch storage {
        case .rgb(let r, let g, let b, let a): return NSColor(red: r, green: g, blue: b, alpha: a * opacityMultiplier).cgColor
        case .ns(let box): return opacityMultiplier == 1 ? box.color.cgColor : box.color.withAlphaComponent(box.color.alphaComponent * opacityMultiplier).cgColor
        case .named: return nil
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/color/resolve(in:)
    @MainActor public func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        let c = storage == .named("primary") ? (environment.foregroundColor ?? self) : self
        let ns = c.nsColor
        return Resolved(red: Float(ns.redComponent), green: Float(ns.greenComponent), blue: Float(ns.blueComponent), opacity: Float(ns.alphaComponent))
    }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/color/resolved
    public struct Resolved: Hashable, Codable, Sendable, ShapeStyle {
        public var linearRed: Float
        public var linearGreen: Float
        public var linearBlue: Float
        public var opacity: Float
        public init(colorLinearRed: Float, green: Float, blue: Float, opacity: Float = 1) {
            linearRed = colorLinearRed; linearGreen = green; linearBlue = blue; self.opacity = opacity
        }
        public init(red: Float, green: Float, blue: Float, opacity: Float = 1) {
            linearRed = Resolved.linear(red); linearGreen = Resolved.linear(green); linearBlue = Resolved.linear(blue); self.opacity = opacity
        }
        public var red: Float { get { Resolved.gamma(linearRed) } set { linearRed = Resolved.linear(newValue) } }
        public var green: Float { get { Resolved.gamma(linearGreen) } set { linearGreen = Resolved.linear(newValue) } }
        public var blue: Float { get { Resolved.gamma(linearBlue) } set { linearBlue = Resolved.linear(newValue) } }
        public var cgColor: CGColor { NSColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(opacity)).cgColor }
        static func linear(_ v: Float) -> Float { v <= 0.04045 ? v / 12.92 : powf((v + 0.055) / 1.055, 2.4) }
        static func gamma(_ v: Float) -> Float { v <= 0.0031308 ? v * 12.92 : 1.055 * powf(v, 1 / 2.4) - 0.055 }
        @MainActor public func _fill(_ context: CGContext, path: CGPath, in rect: CGRect, environment: EnvironmentValues) {
            Color(self)._fill(context, path: path, in: rect, environment: environment)
        }
        @MainActor public func _color(at point: CGPoint, in rect: CGRect, environment: EnvironmentValues) -> CGColor? { cgColor }
    }
    init(named: String) { storage = .named(named) }

    public static let clear = Color(named: "clear")
    public static let black = Color(named: "black")
    public static let white = Color(named: "white")
    public static let gray = Color(named: "gray")
    public static let red = Color(named: "red")
    public static let green = Color(named: "green")
    public static let blue = Color(named: "blue")
    public static let orange = Color(named: "orange")
    public static let yellow = Color(named: "yellow")
    public static let pink = Color(named: "pink")
    public static let purple = Color(named: "purple")
    public static let primary = Color(named: "primary")
    public static let secondary = Color(named: "secondary")
    public static let accentColor = Color(named: "accent")
    public static let mint = Color(red: 0, green: 0.78, blue: 0.75)
    public static let teal = Color(red: 0.35, green: 0.68, blue: 0.75)
    public static let cyan = Color(red: 0.33, green: 0.75, blue: 0.9)
    public static let indigo = Color(red: 0.35, green: 0.34, blue: 0.84)
    public static let brown = Color(red: 0.64, green: 0.52, blue: 0.37)

    public func opacity(_ opacity: Double) -> Color { var c = self; c.opacityMultiplier *= opacity; return c }

    public var nsColor: NSColor {
        let base: NSColor
        switch storage {
        case .rgb(let r, let g, let b, let a): base = NSColor(red: r, green: g, blue: b, alpha: a)
        case .ns(let box): base = box.color
        case .named(let n):
            switch n {
            case "clear": base = .clear
            case "black": base = .black
            case "white": base = .white
            case "gray": base = NSColor(red: 0.56, green: 0.56, blue: 0.58, alpha: 1)
            case "red": base = NSColor(red: 1, green: 0.23, blue: 0.19, alpha: 1)
            case "green": base = NSColor(red: 0.16, green: 0.78, blue: 0.25, alpha: 1)
            case "blue": base = NSColor(red: 0, green: 0.48, blue: 1, alpha: 1)
            case "orange": base = NSColor(red: 1, green: 0.58, blue: 0, alpha: 1)
            case "yellow": base = NSColor(red: 1, green: 0.8, blue: 0, alpha: 1)
            case "pink": base = NSColor(red: 1, green: 0.18, blue: 0.33, alpha: 1)
            case "purple": base = NSColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1)
            case "primary": base = .labelColor
            case "secondary": base = .secondaryLabelColor
            case "accent": base = .controlAccentColor
            default: base = NSColor(named: n) ?? .labelColor
            }
        }
        return opacityMultiplier == 1 ? base : base.withAlphaComponent(base.alphaComponent * CGFloat(opacityMultiplier))
    }

    public func _makePrimitive(node: _ViewNode) -> _Primitive { _ShapeViewPrimitive(shape: AnyShape(Rectangle()), fill: self, isColorFill: true) }
}

extension NSColor {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(_:)-3l8e8
    /// Dynamic SwiftUI colours resolve against the current appearance at creation.
    public convenience init(_ color: Color) {
        let ns = color.nsColor
        self.init(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent, alpha: ns.alphaComponent)
    }
}

extension Color: ShapeStyle {
    @MainActor func _resolved(_ environment: EnvironmentValues) -> Color { storage == .named("primary") ? (environment.foregroundColor ?? self) : self }
    @MainActor public func _fill(_ context: CGContext, path: CGPath, in rect: CGRect, environment: EnvironmentValues) {
        context.setFillColor(_resolved(environment).nsColor.cgColor)
        context.addPath(path)
        context.fillPath()
    }
    @MainActor public func _color(at point: CGPoint, in rect: CGRect, environment: EnvironmentValues) -> CGColor? { _resolved(environment).nsColor.cgColor }
    @MainActor public func _stroke(_ context: CGContext, path: CGPath, in rect: CGRect, style: StrokeStyle, environment: EnvironmentValues) {
        context.saveGState()
        context.setStrokeColor(_resolved(environment).nsColor.cgColor)
        context._apply(style)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/shapestyle
public protocol ShapeStyle: Sendable {
    /// Fills `path` (laid out in `rect`) with this style; the hook `Shape.fill(_:style:)`
    /// and the shape-drawing primitives draw through.
    @MainActor func _fill(_ context: CGContext, path: CGPath, in rect: CGRect, environment: EnvironmentValues)
    /// Strokes `path` with this style (`Shape.stroke(_:style:)`).
    @MainActor func _stroke(_ context: CGContext, path: CGPath, in rect: CGRect, style: StrokeStyle, environment: EnvironmentValues)
    /// The style's colour at a point of `rect`, for segment strokes (nil: not a colour style).
    @MainActor func _color(at point: CGPoint, in rect: CGRect, environment: EnvironmentValues) -> CGColor?
}

extension ShapeStyle {
    @MainActor public func _fill(_ context: CGContext, path: CGPath, in rect: CGRect, environment: EnvironmentValues) { unimplemented("\(Self.self)._fill") }
    /// Default: the stroke's outline, segment by segment, each filled with the style
    /// (Shapes.swift); styles with a plain colour stroke directly.
    @MainActor public func _stroke(_ context: CGContext, path: CGPath, in rect: CGRect, style: StrokeStyle, environment: EnvironmentValues) {
        _strokeSegments(context, path: path, in: rect, style: style, environment: environment)
    }
}

extension CGContext {
    func _apply(_ style: StrokeStyle) {
        setLineWidth(style.lineWidth)
        setLineCap(style.lineCap)
        setLineJoin(style.lineJoin)
        setMiterLimit(style.miterLimit)
        setLineDash(phase: style.dashPhase, lengths: style.dash)
    }
}

// MARK: Text

/// Measures and draws through the text system (storage, layout manager, container).
@MainActor
final class _TextView: NSView {
    let storage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        container.lineFragmentPadding = 0
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // Accessibility (ADR-0013): AXStaticText whose value is the text.
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { super.accessibilityRole() ?? .staticText }
    override func accessibilityValue() -> Any? { super.accessibilityValue() ?? storage.string }

    /// Drawn on a selected list row: the text takes the selection's text colour.
    var isInSelectedRow = false {
        didSet { if isInSelectedRow != oldValue { applySelection(); needsDisplay = true } }
    }
    private func applySelection() {
        let range = NSRange(location: 0, length: storage.length)
        if isInSelectedRow { layoutManager.addTemporaryAttribute(.foregroundColor, value: NSColor.alternateSelectedControlTextColor, forCharacterRange: range) }
        else { layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range) }
    }

    /// `.redacted(reason: .placeholder)`: the text is drawn as a grey bar instead of glyphs.
    var isRedacted = false { didSet { if isRedacted != oldValue { needsDisplay = true } } }

    func configure(_ text: NSAttributedString, lineLimit: Int?, alignment: TextAlignment, truncation: NSLineBreakMode, lineSpacing: CGFloat = 0) {
        if !storage.isEqual(to: text) { storage.setAttributedString(text); if isInSelectedRow { applySelection() } }
        container.maximumNumberOfLines = lineLimit ?? 0
        container.lineBreakMode = lineLimit == 1 ? truncation : .byWordWrapping
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        switch alignment {
        case .leading: style.alignment = .left
        case .center: style.alignment = .center
        case .trailing: style.alignment = .right
        }
        storage.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: storage.length))
    }

    /// The width of the widest word: a proposal narrower than this is answered with it, as
    /// SwiftUI's `Text` wraps between words and never inside one (a stack that offers a
    /// text less than it needs gets the word width back rather than a column of letters).
    private var longestWord: (key: String, width: CGFloat)?
    private func longestWordWidth() -> CGFloat {
        let key = storage.string
        if let l = longestWord, l.key == key { return l.width }
        var widest: CGFloat = 0
        let ns = key as NSString
        var location = 0
        for word in key.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            let range = ns.range(of: String(word), options: [], range: NSRange(location: location, length: ns.length - location))
            guard range.location != NSNotFound else { continue }
            location = range.location + range.length
            widest = max(widest, storage.attributedSubstring(from: range).size().width)
        }
        longestWord = (key, widest.rounded(.up))
        return longestWord!.width
    }

    func size(for width: CGFloat?) -> CGSize {
        var w = width ?? CGFloat.greatestFiniteMagnitude
        if let width, container.maximumNumberOfLines != 1 { w = max(width, longestWordWidth()) }
        container.size = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude)
        let used = layoutManager.usedRect(for: container)
        return CGSize(width: used.width.rounded(.up), height: used.height.rounded(.up))
    }

    /// The first and last baselines from the top, by the fonts of the first and last
    /// characters (the text is laid out top-down from the first line).
    var baselines: (first: CGFloat, last: CGFloat) {
        guard storage.length > 0 else { return (0, 0) }
        let firstFont = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let lastFont = storage.attribute(.font, at: storage.length - 1, effectiveRange: nil) as? NSFont ?? firstFont
        let used = layoutManager.usedRect(for: container)
        return (firstFont.ascender.rounded(.up), (used.height + lastFont.descender).rounded(.up))
    }

    override func draw(_ dirtyRect: NSRect) {
        container.size = NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        let range = layoutManager.glyphRange(for: container)
        if isRedacted {
            let used = layoutManager.usedRect(for: container)
            NSColor.secondaryLabelColor.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: used.insetBy(dx: 0, dy: used.height * 0.12), xRadius: 3, yRadius: 3).fill()
            return
        }
        layoutManager.drawGlyphs(forGlyphRange: range, at: .zero)
    }
}

@MainActor
final class _TextPrimitive: _Primitive {
    var text: Text
    let view = _TextView(frame: .zero)
    init(text: Text) { self.text = text }
    override var nsView: NSView? { view }
    override func update(from other: _Primitive) {
        super.update(from: other)
        if let o = other as? _TextPrimitive { text = o.text; refresh(); view.needsDisplay = true }
    }
    override func attach(to node: _ViewNode) { super.attach(to: node); refresh(); view.needsDisplay = true }
    /// Pushes the text and environment into the view; measurement calls this too, so it
    /// must not invalidate anything by itself (the view redraws when its content changes).
    private func refresh() {
        guard let node else { return }
        let env = node.environment
        view.isRedacted = env.redactionReasons.contains(.placeholder)
        view.configure(text._attributed(env), lineLimit: env.lineLimit, alignment: env.multilineTextAlignment, truncation: env.truncationMode == .head ? .byTruncatingHead : env.truncationMode == .middle ? .byTruncatingMiddle : .byTruncatingTail, lineSpacing: env.lineSpacing)
    }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        refresh()
        var s = view.size(for: proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil })
        if let w = proposal.width, w.isFinite, w > 0, s.width > w, node.environment.lineLimit == 1 { s.width = w }
        lastMeasuredHeight = s.height
        return s
    }
    /// The height of the last measurement (baselines are read against it).
    var lastMeasuredHeight: CGFloat = 0
    /// Baselines for a layout at `size` (the text is laid out at that width first).
    func baselines(for size: CGSize) -> (first: CGFloat, last: CGFloat) {
        refresh()
        lastMeasuredHeight = view.size(for: size.width > 0 ? size.width : nil).height
        return view.baselines
    }
    override func place(node: _ViewNode, in rect: CGRect) {}
    override func didLayout(node: _ViewNode) { view.needsDisplay = true }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/text
public struct Text: View, _PrimitiveView, Equatable {
    public typealias Body = Never
    public enum TruncationMode: Hashable, Sendable { case head, tail, middle }
    public enum Case: Hashable, Sendable { case uppercase, lowercase }

    struct Run: Equatable {
        var string: String
        var font: Font? = nil
        var color: Color? = nil
        var backgroundColor: Color? = nil
        var bold = false
        var italic = false
        var underline: LineStyle? = nil
        var strikethrough: LineStyle? = nil
        var kerning: CGFloat = 0
        var tracking: CGFloat = 0
        var baselineOffset: CGFloat = 0
        var monospacedDigits = false
        /// An inline image (`Text(image)`), drawn as an attachment.
        var image: Image? = nil
    }
    var runs: [Run]

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/text/linestyle
    public struct LineStyle: Hashable, Sendable {
        /// - SeeAlso: https://developer.apple.com/documentation/swiftui/text/linestyle/pattern
        public struct Pattern: Hashable, Sendable {
            let rawValue: Int
            public static let solid = Pattern(rawValue: 0)
            public static let dot = Pattern(rawValue: 1)
            public static let dash = Pattern(rawValue: 2)
            public static let dashDot = Pattern(rawValue: 3)
            public static let dashDotDot = Pattern(rawValue: 4)
        }
        public var pattern: Pattern
        public var color: Color?
        public init(pattern: Pattern = .solid, color: Color? = nil) { self.pattern = pattern; self.color = color }
        public static let single = LineStyle()
        var nsStyle: NSUnderlineStyle {
            switch pattern {
            case .dot: return [.single, .patternDot]
            case .dash: return [.single, .patternDash]
            case .dashDot: return [.single, .patternDashDot]
            case .dashDotDot: return [.single, .patternDashDotDot]
            default: return .single
            }
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/text/init(_:)-9cbvb
    public init(_ image: Image) { runs = [Run(string: "\u{FFFC}", image: image)] }

    public init(verbatim content: String) { runs = [Run(string: content)] }
    public init<S: StringProtocol>(_ content: S) { runs = [Run(string: String(content))] }
    public init(_ key: LocalizedStringKey, tableName: String? = nil, bundle: Bundle? = nil, comment: StaticString? = nil) { runs = [Run(string: key.key)] }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/text/init(_:)-1a4oh
    public init(_ attributed: AttributedString) { runs = Text._runs(of: attributed) }
    public init(_ date: Date, style: DateStyle) {
        let f = DateFormatter()
        switch style {
        case .time: f.timeStyle = .short
        case .date: f.dateStyle = .medium
        case .relative, .offset, .timer: f.timeStyle = .short
        }
        runs = [Run(string: f.string(from: date))]
    }
    public enum DateStyle: Sendable { case time, date, relative, offset, timer }

    private func mapRuns(_ f: (inout Run) -> Void) -> Text { var t = self; for i in t.runs.indices { f(&t.runs[i]) }; return t }
    public func font(_ font: Font?) -> Text { mapRuns { $0.font = font ?? $0.font } }
    public func foregroundColor(_ color: Color?) -> Text { mapRuns { $0.color = color } }
    public func foregroundStyle(_ color: Color) -> Text { mapRuns { $0.color = color } }
    public func bold() -> Text { mapRuns { $0.bold = true } }
    public func italic() -> Text { mapRuns { $0.italic = true } }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/text/underline(_:pattern:color:)
    public func underline(_ isActive: Bool = true, pattern: LineStyle.Pattern = .solid, color: Color? = nil) -> Text { mapRuns { $0.underline = isActive ? LineStyle(pattern: pattern, color: color) : nil } }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/text/strikethrough(_:pattern:color:)
    public func strikethrough(_ isActive: Bool = true, pattern: LineStyle.Pattern = .solid, color: Color? = nil) -> Text { mapRuns { $0.strikethrough = isActive ? LineStyle(pattern: pattern, color: color) : nil } }
    public func kerning(_ kerning: CGFloat) -> Text { mapRuns { $0.kerning = kerning } }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/text/tracking(_:)
    public func tracking(_ tracking: CGFloat) -> Text { mapRuns { $0.tracking = tracking } }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/text/monospaceddigit()
    public func monospacedDigit() -> Text { mapRuns { $0.monospacedDigits = true } }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/text/monospaced(_:)
    public func monospaced(_ isActive: Bool = true) -> Text { mapRuns { if isActive { $0.font = ($0.font ?? .body).monospaced() } } }
    public func baselineOffset(_ offset: CGFloat) -> Text { mapRuns { $0.baselineOffset = offset } }
    public func fontWeight(_ weight: Font.Weight?) -> Text { mapRuns { if let w = weight { $0.font = ($0.font ?? .body).weight(w) } } }
    public func textCase(_ c: Case?) -> Text {
        mapRuns { if c == .uppercase { $0.string = $0.string.uppercased() } else if c == .lowercase { $0.string = $0.string.lowercased() } }
    }
    public static func + (lhs: Text, rhs: Text) -> Text { var t = lhs; t.runs += rhs.runs; return t }

    @MainActor func _attributed(_ env: EnvironmentValues) -> NSAttributedString {
        let out = NSMutableAttributedString(string: "")
        let baseFont = env.font ?? .body
        let baseColor = env.foregroundColor
        for r in runs {
            var font = r.font ?? baseFont
            if r.bold { font = font.bold() }
            if r.italic { font = font.italic() }
            if r.monospacedDigits { font = font.monospacedDigit() }
            var attrs: [NSAttributedString.Key: Any] = [.font: font.nsFont]
            let color = r.color ?? baseColor
            attrs[.foregroundColor] = color?.nsColor ?? (env.isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor)
            if let bg = r.backgroundColor { attrs[.backgroundColor] = bg.nsColor }
            if let u = r.underline { attrs[.underlineStyle] = u.nsStyle.rawValue; if let c = u.color { attrs[.underlineColor] = c.nsColor } }
            if let st = r.strikethrough { attrs[.strikethroughStyle] = st.nsStyle.rawValue; if let c = st.color { attrs[.strikethroughColor] = c.nsColor } }
            if r.kerning != 0 || r.tracking != 0 { attrs[.kern] = r.kerning + r.tracking }
            if r.baselineOffset != 0 { attrs[.baselineOffset] = r.baselineOffset }
            if let image = r.image {
                // The text system has no attachments yet (docs/ROADMAP.md): the image's
                // accessibility label stands in for it.
                out.append(NSAttributedString(string: image.accessibilityLabel ?? "", attributes: attrs))
                continue
            }
            out.append(NSAttributedString(string: r.string, attributes: attrs))
        }
        return out
    }

    public func _makePrimitive(node: _ViewNode) -> _Primitive { _TextPrimitive(text: self) }
}

extension Text {
    /// The plain string (tests and labels).
    public var _string: String { runs.map { $0.image == nil ? $0.string : "" }.joined() }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/localizedstringkey
public struct LocalizedStringKey: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Equatable, Sendable {
    let key: String
    public init(_ value: String) { key = value }
    public init(stringLiteral value: String) { key = value }
    public init(stringInterpolation: StringInterpolation) { key = stringInterpolation.output }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/localizedstringkey/stringinterpolation
    /// The key is built as the formatted string (there is no strings table to look up).
    public struct StringInterpolation: StringInterpolationProtocol, Sendable {
        var output = ""
        public init(literalCapacity: Int, interpolationCount: Int) { output.reserveCapacity(literalCapacity) }
        public mutating func appendLiteral(_ literal: String) { output += literal }
        public mutating func appendInterpolation(_ string: String) { output += string }
        public mutating func appendInterpolation<Subject: CustomStringConvertible>(_ subject: Subject) { output += subject.description }
        public mutating func appendInterpolation<T>(_ value: T) { output += String(describing: value) }
        /// `"\(value, specifier: "%.2f")"`: a printf-style format for the value.
        public mutating func appendInterpolation<T: _FormatSpecifiable>(_ value: T, specifier: String) { output += String(format: specifier, value._arg) }
        public mutating func appendInterpolation<Subject: ReferenceConvertible>(_ subject: Subject, formatter: Formatter? = nil) {
            let any: Any = subject
            if let formatter, let formatted = formatter.string(for: any) { output += formatted } else { output += String(describing: subject) }
        }
        public mutating func appendInterpolation<Subject: NSObject>(_ subject: Subject, formatter: Formatter? = nil) {
            let any: Any = subject
            if let formatter, let formatted = formatter.string(for: any) { output += formatted } else { output += subject.description }
        }
        public mutating func appendInterpolation<F: FormatStyle>(_ input: F.FormatInput, format: F) where F.FormatOutput == String { output += format.format(input) }
        public mutating func appendInterpolation(_ text: Text) { output += text._string }
        public mutating func appendInterpolation(_ image: Image) {}
        public mutating func appendInterpolation(_ date: Date, style: Text.DateStyle) { output += Text(date, style: style)._string }
    }
}

/// The types `LocalizedStringKey` accepts with a `specifier:`, as in Apple's SwiftUI.
public protocol _FormatSpecifiable: Equatable {
    var _arg: CVarArg { get }
}
extension Int: _FormatSpecifiable { public var _arg: CVarArg { self } }
extension Int8: _FormatSpecifiable { public var _arg: CVarArg { self } }
extension Int16: _FormatSpecifiable { public var _arg: CVarArg { self } }
extension Int32: _FormatSpecifiable { public var _arg: CVarArg { self } }
extension Int64: _FormatSpecifiable { public var _arg: CVarArg { self } }
extension UInt: _FormatSpecifiable { public var _arg: CVarArg { self } }
extension UInt8: _FormatSpecifiable { public var _arg: CVarArg { self } }
extension UInt16: _FormatSpecifiable { public var _arg: CVarArg { self } }
extension UInt32: _FormatSpecifiable { public var _arg: CVarArg { self } }
extension UInt64: _FormatSpecifiable { public var _arg: CVarArg { self } }
extension Float: _FormatSpecifiable { public var _arg: CVarArg { self } }
extension Double: _FormatSpecifiable { public var _arg: CVarArg { self } }
extension CGFloat: _FormatSpecifiable { public var _arg: CVarArg { self } }
extension String: _FormatSpecifiable { public var _arg: CVarArg { self } }

// MARK: Shapes

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/path
public struct Path: Equatable, @unchecked Sendable {
    public private(set) var cgPath: CGPath
    public init() { cgPath = CGMutablePath() }
    public init(_ path: CGPath) { cgPath = path }
    public init(_ rect: CGRect) { cgPath = CGPath(rect: rect, transform: nil) }
    public init(roundedRect rect: CGRect, cornerRadius: CGFloat, style: RoundedCornerStyle = .circular) {
        cgPath = CGPath(roundedRect: rect, cornerWidth: min(cornerRadius, rect.width / 2), cornerHeight: min(cornerRadius, rect.height / 2), transform: nil)
    }
    public init(ellipseIn rect: CGRect) { cgPath = CGPath(ellipseIn: rect, transform: nil) }
    public init(_ callback: (inout Path) -> Void) { self.init(); callback(&self) }
    private var mutable: CGMutablePath {
        let m = CGMutablePath()
        m.addPath(cgPath)
        return m
    }
    public var isEmpty: Bool { cgPath.isEmpty }
    public var boundingRect: CGRect { cgPath.boundingBox }
    public mutating func move(to p: CGPoint) { let m = mutable; m.move(to: p); cgPath = m }
    public mutating func addLine(to p: CGPoint) { let m = mutable; m.addLine(to: p); cgPath = m }
    public mutating func addQuadCurve(to p: CGPoint, control: CGPoint) { let m = mutable; m.addQuadCurve(to: p, control: control); cgPath = m }
    public mutating func addCurve(to p: CGPoint, control1: CGPoint, control2: CGPoint) { let m = mutable; m.addCurve(to: p, control1: control1, control2: control2); cgPath = m }
    public mutating func closeSubpath() { let m = mutable; m.closeSubpath(); cgPath = m }
    public mutating func addRect(_ rect: CGRect, transform: CGAffineTransform = .identity) { let m = mutable; m.addRect(rect, transform: transform); cgPath = m }
    public mutating func addRects(_ rects: [CGRect], transform: CGAffineTransform = .identity) { let m = mutable; m.addRects(rects, transform: transform); cgPath = m }
    public mutating func addEllipse(in rect: CGRect, transform: CGAffineTransform = .identity) { let m = mutable; m.addEllipse(in: rect, transform: transform); cgPath = m }
    public mutating func addRoundedRect(in rect: CGRect, cornerSize: CGSize, style: RoundedCornerStyle = .circular, transform: CGAffineTransform = .identity) {
        let m = mutable; m.addRoundedRect(in: rect, cornerWidth: cornerSize.width, cornerHeight: cornerSize.height, transform: transform); cgPath = m
    }
    public mutating func addPath(_ path: Path, transform: CGAffineTransform = .identity) { let m = mutable; m.addPath(path.cgPath, transform: transform); cgPath = m }
    public mutating func addLines(_ lines: [CGPoint]) { let m = mutable; m.addLines(between: lines); cgPath = m }
    public mutating func addArc(center: CGPoint, radius: CGFloat, startAngle: Angle, endAngle: Angle, clockwise: Bool, transform: CGAffineTransform = .identity) {
        let m = mutable; m.addArc(center: center, radius: radius, startAngle: CGFloat(startAngle.radians), endAngle: CGFloat(endAngle.radians), clockwise: clockwise, transform: transform); cgPath = m
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/path/addarc(tangent1end:tangent2end:radius:transform:)
    public mutating func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat, transform: CGAffineTransform = .identity) {
        let m = mutable; m.addArc(tangent1End: tangent1End, tangent2End: tangent2End, radius: radius, transform: transform); cgPath = m
    }
    public static func == (a: Path, b: Path) -> Bool {
        #if canImport(Darwin)
        return a.cgPath == b.cgPath
        #else
        return a.cgPath === b.cgPath || a.cgPath.boundingBox == b.cgPath.boundingBox && a.cgPath.isEmpty == b.cgPath.isEmpty
        #endif
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/angle
public struct Angle: Hashable, Comparable, Sendable {
    public var radians: Double
    public var degrees: Double { get { radians * 180 / .pi } set { radians = newValue * .pi / 180 } }
    public init() { radians = 0 }
    public init(radians: Double) { self.radians = radians }
    public init(degrees: Double) { radians = degrees * .pi / 180 }
    public static func radians(_ r: Double) -> Angle { Angle(radians: r) }
    public static func degrees(_ d: Double) -> Angle { Angle(degrees: d) }
    public static let zero = Angle()
    public static func < (a: Angle, b: Angle) -> Bool { a.radians < b.radians }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/roundedcornerstyle
public enum RoundedCornerStyle: Hashable, Sendable { case circular, continuous }

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/shape
/// `Sendable` with a nonisolated `path(in:)`, as Apple's: shapes are plain values a
/// conforming struct can declare without main-actor isolation.
public protocol Shape: Sendable, View {
    nonisolated func path(in rect: CGRect) -> Path
}

extension Shape {
    public var body: some View { _ShapeView(shape: AnyShape(self), fill: Color.primary) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/shape/fill(_:style:)
    public func fill<S: ShapeStyle>(_ content: S, style: FillStyle = FillStyle()) -> some View { _ShapeView(shape: AnyShape(self), fill: content, fillStyle: style) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/shape/fill(style:)
    public func fill(style: FillStyle = FillStyle()) -> some View { _ShapeView(shape: AnyShape(self), fill: Color.primary, fillStyle: style) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/shape/stroke(_:linewidth:antialiased:)
    public func stroke<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View {
        _ShapeView(shape: AnyShape(self), stroke: content, strokeStyle: StrokeStyle(lineWidth: lineWidth))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/shape/stroke(_:style:antialiased:)
    public func stroke<S: ShapeStyle>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> some View {
        _ShapeView(shape: AnyShape(self), stroke: content, strokeStyle: style)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/shape/stroke(linewidth:)
    public func stroke(lineWidth: CGFloat = 1) -> some View { stroke(Color.primary, lineWidth: lineWidth) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/shape/stroke(style:)
    public func stroke(style: StrokeStyle) -> some View { stroke(Color.primary, style: style) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/fillstyle
public struct FillStyle: Equatable, Sendable {
    public var isEOFilled: Bool
    public var isAntialiased: Bool
    public init(eoFill: Bool = false, antialiased: Bool = true) { isEOFilled = eoFill; isAntialiased = antialiased }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/strokestyle
public struct StrokeStyle: Equatable, Sendable {
    public var lineWidth: CGFloat
    public var lineCap: CGLineCap
    public var lineJoin: CGLineJoin
    public var miterLimit: CGFloat
    public var dash: [CGFloat]
    public var dashPhase: CGFloat
    public init(lineWidth: CGFloat = 1, lineCap: CGLineCap = .butt, lineJoin: CGLineJoin = .miter, miterLimit: CGFloat = 10, dash: [CGFloat] = [], dashPhase: CGFloat = 0) {
        self.lineWidth = lineWidth; self.lineCap = lineCap; self.lineJoin = lineJoin; self.miterLimit = miterLimit; self.dash = dash; self.dashPhase = dashPhase
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/anyshape
public struct AnyShape: Shape, @unchecked Sendable {
    let pathBuilder: (CGRect) -> Path
    public init<S: Shape>(_ shape: S) { pathBuilder = { shape.path(in: $0) } }
    public func path(in rect: CGRect) -> Path { pathBuilder(rect) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/rectangle
public struct Rectangle: Shape, Sendable {
    public init() {}
    public func path(in rect: CGRect) -> Path { Path(rect) }
}
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/roundedrectangle
public struct RoundedRectangle: Shape, Sendable {
    public var cornerSize: CGSize
    public var style: RoundedCornerStyle
    public init(cornerRadius: CGFloat, style: RoundedCornerStyle = .circular) { cornerSize = CGSize(width: cornerRadius, height: cornerRadius); self.style = style }
    public init(cornerSize: CGSize, style: RoundedCornerStyle = .circular) { self.cornerSize = cornerSize; self.style = style }
    public func path(in rect: CGRect) -> Path { Path(roundedRect: rect, cornerRadius: cornerSize.width, style: style) }
}
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/circle
public struct Circle: Shape, Sendable {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        let d = min(rect.width, rect.height)
        return Path(ellipseIn: CGRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d))
    }
}
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/ellipse
public struct Ellipse: Shape, Sendable {
    public init() {}
    public func path(in rect: CGRect) -> Path { Path(ellipseIn: rect) }
}
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/capsule
public struct Capsule: Shape, Sendable {
    public var style: RoundedCornerStyle
    public init(style: RoundedCornerStyle = .circular) { self.style = style }
    public func path(in rect: CGRect) -> Path { Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2, style: style) }
}

@MainActor
final class _ShapeDrawingView: NSView {
    var draw: ((CGContext, CGRect) -> Void)?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { if let ctx = NSGraphicsContext.current?.cgContext { draw?(ctx, bounds) } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class _ShapeViewPrimitive: _Primitive {
    var shape: AnyShape
    var fill: (any ShapeStyle)?
    var fillStyle: FillStyle
    var stroke: (any ShapeStyle)?
    var strokeStyle: StrokeStyle
    let isColorFill: Bool
    let view = _ShapeDrawingView(frame: .zero)

    init(shape: AnyShape, fill: (any ShapeStyle)?, fillStyle: FillStyle = FillStyle(), stroke: (any ShapeStyle)? = nil, strokeStyle: StrokeStyle = StrokeStyle(), isColorFill: Bool = false) {
        self.shape = shape; self.fill = fill; self.fillStyle = fillStyle; self.stroke = stroke; self.strokeStyle = strokeStyle; self.isColorFill = isColorFill
        super.init()
    }
    override var nsView: NSView? { view }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _ShapeViewPrimitive else { return }
        shape = o.shape; fill = o.fill; fillStyle = o.fillStyle; stroke = o.stroke; strokeStyle = o.strokeStyle
        install()
    }
    override func attach(to node: _ViewNode) { super.attach(to: node); install() }
    private func install() {
        let fill = fill, fillStyle = fillStyle, stroke = stroke, strokeStyle = strokeStyle, shape = shape
        let env = node?.environment ?? EnvironmentValues()
        view.draw = { ctx, bounds in
            let path = shape.path(in: bounds).cgPath
            if let f = fill {
                ctx.saveGState()
                if fillStyle.isEOFilled { ctx.addPath(path); ctx.clip(using: .evenOdd) }
                f._fill(ctx, path: path, in: bounds, environment: env)
                ctx.restoreGState()
            }
            if let s = stroke, strokeStyle.lineWidth > 0 {
                s._stroke(ctx, path: path, in: bounds, style: strokeStyle, environment: env)
            }
        }
        view.needsDisplay = true
    }
    /// Shapes and colours take whatever is proposed; unspecified dimensions use 10 points.
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        CGSize(width: proposal.width.map { $0.isFinite ? $0 : 10 } ?? 10, height: proposal.height.map { $0.isFinite ? $0 : 10 } ?? 10)
    }
    override func place(node: _ViewNode, in rect: CGRect) {}
    override func didLayout(node: _ViewNode) { view.needsDisplay = true }
}

struct _ShapeView: View, _PrimitiveView {
    typealias Body = Never
    let shape: AnyShape
    var fill: (any ShapeStyle)? = nil
    var fillStyle = FillStyle()
    var stroke: (any ShapeStyle)? = nil
    var strokeStyle = StrokeStyle()
    func _makePrimitive(node: _ViewNode) -> _Primitive { _ShapeViewPrimitive(shape: shape, fill: fill, fillStyle: fillStyle, stroke: stroke, strokeStyle: strokeStyle) }
}

// MARK: Divider

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/divider
public struct Divider: View, _PrimitiveView {
    public typealias Body = Never
    public init() {}
    public func _makePrimitive(node: _ViewNode) -> _Primitive { _DividerPrimitive() }
}

@MainActor
final class _DividerPrimitive: _Primitive {
    let view = _ShapeDrawingView(frame: .zero)
    override var nsView: NSView? { view }
    override func attach(to node: _ViewNode) {
        super.attach(to: node)
        view.draw = { ctx, b in ctx.setFillColor(NSColor.separatorColor.cgColor); ctx.fill(b) }
    }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        if node.stackAxis == .horizontal { return CGSize(width: 1, height: proposal.height.map { $0.isFinite ? $0 : 10 } ?? 10) }
        return CGSize(width: proposal.width.map { $0.isFinite ? $0 : 10 } ?? 10, height: 1)
    }
    override func place(node: _ViewNode, in rect: CGRect) {}
}

// MARK: Controls backed by AppKit

/// A primitive that owns one AppKit control sized by its intrinsic size.
@MainActor
class _ControlPrimitive<Control: NSView>: _Primitive {
    let control: Control
    init(control: Control) { self.control = control }
    override var nsView: NSView? { control }
    /// The control's natural size. Measurement never resizes the control: the frame is set
    /// only by `place`, so a fractional natural width cannot fight the integral placed one.
    var intrinsicSize: CGSize { let s = control.intrinsicContentSize; return CGSize(width: s.width == NSView.noIntrinsicMetric ? 100 : s.width.rounded(.up), height: s.height == NSView.noIntrinsicMetric ? 22 : s.height.rounded(.up)) }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize { intrinsicSize }
    override func place(node: _ViewNode, in rect: CGRect) {}
}


/// - SeeAlso: https://developer.apple.com/documentation/swiftui/button
public struct Button<Label: View>: View, _PrimitiveView {
    public typealias Body = Never
    let action: () -> Void
    let label: Label
    let role: ButtonRole?
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action; self.label = label(); role = nil
    }
    public init(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action; self.label = label(); self.role = role
    }
    public func _makePrimitive(node: _ViewNode) -> _Primitive {
        if let text = label as? Text { return _ButtonPrimitive(title: text._string, action: action) }
        return _CustomButtonPrimitive(action: action, content: _ViewBox(label))
    }
}

extension Button where Label == Text {
    public init(_ title: String, action: @escaping () -> Void) { self.init(action: action) { Text(title) } }
    public init(_ titleKey: LocalizedStringKey, action: @escaping () -> Void) { self.init(action: action) { Text(titleKey) } }
    public init(_ title: String, role: ButtonRole?, action: @escaping () -> Void) { self.init(role: role, action: action) { Text(title) } }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/buttonrole
public struct ButtonRole: Equatable, Sendable {
    public static let destructive = ButtonRole()
    public static let cancel = ButtonRole()
}

@MainActor
final class _ButtonPrimitive: _ControlPrimitive<NSButton> {
    var action: () -> Void
    init(title: String, action: @escaping () -> Void) {
        self.action = action
        let b = NSButton(frame: .zero)
        b.title = title
        b.bezelStyle = .rounded
        super.init(control: b)
        b.target = b
        b.action = Selector(("swiftUIButtonAction:"))
        b.setActionHandler(for: Selector(("swiftUIButtonAction:"))) { [weak self] _ in self?.action() }
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _ButtonPrimitive else { return }
        action = o.action
        if control.title != o.control.title { control.title = o.control.title }
        apply()
    }
    override func attach(to node: _ViewNode) { super.attach(to: node); apply() }
    private func apply() {
        guard let node else { return }
        control.isEnabled = node.environment.isEnabled
        if let f = node.environment.font { control.font = f.nsFont }
        switch node.environment.buttonStyle {
        case .plain, .borderless, .link: control.isBordered = false
        default: control.isBordered = true
        }
        if let (key, mods) = node.environment._keyShortcut {
            control.keyEquivalent = String(key.character)
            var m: NSEvent.ModifierFlags = []
            if mods.contains(.command) { m.insert(.command) }
            if mods.contains(.shift) { m.insert(.shift) }
            if mods.contains(.option) { m.insert(.option) }
            if mods.contains(.control) { m.insert(.control) }
            control.keyEquivalentModifierMask = key.character == "\r" ? [] : m
        }
        control.sizeToFit()
    }
    override var intrinsicSize: CGSize { let s = super.intrinsicSize; return CGSize(width: max(s.width, 20), height: max(s.height, 20)) }
}

/// A button with custom content: a tap-handling container around the label.
@MainActor
final class _CustomButtonPrimitive: _Primitive {
    var action: () -> Void
    let view = _ContainerView(frame: .zero)
    init(action: @escaping () -> Void, content: _AnyViewBox) {
        self.action = action
        super.init()
        children = [content]
    }
    override var nsView: NSView? { view }
    override func update(from other: _Primitive) { super.update(from: other); if let o = other as? _CustomButtonPrimitive { action = o.action } }
    override func attach(to node: _ViewNode) {
        super.attach(to: node)
        view.mouseDownHandler = { [weak self] _ in self?.action(); return true }
        view.accessibilityPress = { [weak self] in self?.action() }
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/textfield
public struct TextField<Label: View>: View, _PrimitiveView {
    public typealias Body = Never
    let placeholder: String
    let text: Binding<String>
    let onCommit: () -> Void
    public init(_ title: String, text: Binding<String>) where Label == Text {
        placeholder = title; self.text = text; onCommit = {}
    }
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>) where Label == Text {
        placeholder = titleKey.key; self.text = text; onCommit = {}
    }
    public init(_ title: String, text: Binding<String>, onCommit: @escaping () -> Void) where Label == Text {
        placeholder = title; self.text = text; self.onCommit = onCommit
    }
    public init(_ title: String, text: Binding<String>, prompt: Text?) where Label == Text {
        placeholder = prompt?._string ?? title; self.text = text; onCommit = {}
    }
    public init(text: Binding<String>, prompt: Text? = nil, @ViewBuilder label: () -> Label) {
        placeholder = prompt?._string ?? (label() as? Text)?._string ?? ""; self.text = text; onCommit = {}
    }
    public func _makePrimitive(node: _ViewNode) -> _Primitive { _TextFieldPrimitive(placeholder: placeholder, text: text, onCommit: onCommit) }
}

@MainActor
final class _TextFieldPrimitive: _ControlPrimitive<NSTextField> {
    var text: Binding<String>
    var onCommit: () -> Void
    var placeholder: String
    init(placeholder: String, text: Binding<String>, onCommit: @escaping () -> Void) {
        self.text = text; self.onCommit = onCommit; self.placeholder = placeholder
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 22))
        f.placeholderString = placeholder
        f.stringValue = text.wrappedValue
        super.init(control: f)
        f.target = f
        f.action = Selector(("swiftUIFieldAction:"))
        f.setActionHandler(for: Selector(("swiftUIFieldAction:"))) { [weak self] _ in
            guard let self else { return }
            self.onCommit()
            self.node?.environment._onSubmit?.run()      // .onSubmit above the field
        }
        f.setActionHandler(for: Selector(("swiftUIFieldChanged:"))) { [weak self] _ in self?.changed() }
        NotificationCenter.default.addObserver(forName: NSControl.textDidChangeNotification, object: f, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.changed() }
        }
    }
    private func changed() {
        let v = control.stringValue
        if text.wrappedValue != v { text.wrappedValue = v }
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _TextFieldPrimitive else { return }
        text = o.text; onCommit = o.onCommit; placeholder = o.placeholder
        apply()
    }
    override func attach(to node: _ViewNode) { super.attach(to: node); apply() }
    private func apply() {
        guard let node else { return }
        if control.stringValue != text.wrappedValue, control.currentEditor == nil { control.stringValue = text.wrappedValue }
        if control.placeholderString != placeholder { control.placeholderString = placeholder }
        control.isEnabled = node.environment.isEnabled
        if let f = node.environment.font { control.font = f.nsFont }
        switch node.environment.textFieldStyle {
        case .plain: control.isBezeled = false; control.drawsBackground = false
        default: control.isBezeled = true; control.drawsBackground = true
        }
    }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        let h = control.intrinsicContentSize.height
        let w = proposal.width.map { $0.isFinite ? $0 : 160 } ?? 160
        return CGSize(width: max(w, 20), height: h == NSView.noIntrinsicMetric ? 22 : h)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/toggle
public struct Toggle<Label: View>: View, _PrimitiveView {
    public typealias Body = Never
    let isOn: Binding<Bool>
    let label: Label
    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) { self.isOn = isOn; self.label = label() }
    public func _makePrimitive(node: _ViewNode) -> _Primitive { _TogglePrimitive(title: (label as? Text)?._string ?? "", isOn: isOn) }
}

extension Toggle where Label == Text {
    public init(_ title: String, isOn: Binding<Bool>) { self.init(isOn: isOn) { Text(title) } }
    public init(_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) { self.init(isOn: isOn) { Text(titleKey) } }
}

@MainActor
final class _TogglePrimitive: _ControlPrimitive<NSButton> {
    var isOn: Binding<Bool>
    init(title: String, isOn: Binding<Bool>) {
        self.isOn = isOn
        let b = NSButton(frame: .zero)
        b.setButtonType(.switch)
        b.title = title
        b.state = isOn.wrappedValue ? .on : .off
        super.init(control: b)
        b.target = b
        b.action = Selector(("swiftUIToggleAction:"))
        b.setActionHandler(for: Selector(("swiftUIToggleAction:"))) { [weak self] _ in
            guard let self else { return }
            let v = self.control.state == .on
            if self.isOn.wrappedValue != v { self.isOn.wrappedValue = v }
        }
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _TogglePrimitive else { return }
        isOn = o.isOn
        if control.title != o.control.title { control.title = o.control.title }
        apply()
    }
    override func attach(to node: _ViewNode) { super.attach(to: node); apply() }
    private func apply() {
        let want: NSControl.StateValue = isOn.wrappedValue ? .on : .off
        if control.state != want { control.state = want }
        control.isEnabled = node?.environment.isEnabled ?? true
        control.sizeToFit()
    }
    override var intrinsicSize: CGSize { let s = super.intrinsicSize; return CGSize(width: max(s.width, 18), height: max(s.height, 18)) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/slider
public struct Slider<Label: View, ValueLabel: View>: View, _PrimitiveView {
    public typealias Body = Never
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double?
    let onEditingChanged: (Bool) -> Void
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1, step: V.Stride? = nil, onEditingChanged: @escaping (Bool) -> Void = { _ in }) where Label == EmptyView, ValueLabel == EmptyView, V.Stride: BinaryFloatingPoint {
        self.value = Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = V($0) })
        range = Double(bounds.lowerBound)...Double(bounds.upperBound)
        self.step = step.map { Double($0) }
        self.onEditingChanged = onEditingChanged
    }
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1, step: V.Stride? = nil, onEditingChanged: @escaping (Bool) -> Void = { _ in }, @ViewBuilder label: () -> Label) where ValueLabel == EmptyView, V.Stride: BinaryFloatingPoint {
        self.value = Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = V($0) })
        range = Double(bounds.lowerBound)...Double(bounds.upperBound)
        self.step = step.map { Double($0) }
        self.onEditingChanged = onEditingChanged
    }
    public func _makePrimitive(node: _ViewNode) -> _Primitive { _SliderPrimitive(value: value, range: range) }
}

@MainActor
final class _SliderPrimitive: _ControlPrimitive<NSSlider> {
    var value: Binding<Double>
    init(value: Binding<Double>, range: ClosedRange<Double>) {
        self.value = value
        let s = NSSlider(frame: NSRect(x: 0, y: 0, width: 120, height: 20))
        s.minValue = range.lowerBound
        s.maxValue = range.upperBound
        s.doubleValue = value.wrappedValue
        super.init(control: s)
        s.target = s
        s.action = Selector(("swiftUISliderAction:"))
        s.setActionHandler(for: Selector(("swiftUISliderAction:"))) { [weak self] _ in
            guard let self else { return }
            if self.value.wrappedValue != self.control.doubleValue { self.value.wrappedValue = self.control.doubleValue }
        }
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _SliderPrimitive else { return }
        value = o.value
        control.minValue = o.control.minValue; control.maxValue = o.control.maxValue
        apply()
    }
    override func attach(to node: _ViewNode) { super.attach(to: node); apply() }
    private func apply() {
        if control.doubleValue != value.wrappedValue { control.doubleValue = value.wrappedValue }
        control.isEnabled = node?.environment.isEnabled ?? true
    }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        CGSize(width: max(20, proposal.width.map { $0.isFinite ? $0 : 160 } ?? 160), height: 20)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/image
public struct Image: View, _PrimitiveView, Equatable {
    public typealias Body = Never
    public enum ResizingMode: Hashable, Sendable { case tile, stretch }
    let image: NSImage?
    let name: String
    var resizable = false
    public init(_ name: String, bundle: Bundle? = nil) { self.name = name; image = NSImage(named: name) }
    public init(systemName: String) { name = systemName; image = nil }
    public init(nsImage: NSImage) { name = ""; image = nsImage }
    public init(decorative name: String, bundle: Bundle? = nil) { self.init(name, bundle: bundle) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/image/init(_:bundle:label:)
    public init(_ name: String, bundle: Bundle? = nil, label: Text) { self.init(name, bundle: bundle); accessibilityLabel = label._string }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/image/symbolrenderingmode(_:)
    public func symbolRenderingMode(_ mode: SymbolRenderingMode?) -> Image { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/image/scale
    public enum Scale: Hashable, CaseIterable, Sendable { case small, medium, large }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/image/init(_:scale:orientation:label:)
    public init(_ cgImage: CGImage, scale: CGFloat, orientation: Image.Orientation = .up, label: Text) {
        self.init(decorative: cgImage, scale: scale, orientation: orientation)
        accessibilityLabel = label._string
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/image/init(decorative:scale:orientation:)
    public init(decorative cgImage: CGImage, scale: CGFloat, orientation: Image.Orientation = .up) {
        let s = max(scale, 0.01)
        let size = orientation.swapsAxes ? CGSize(width: CGFloat(cgImage.height) / s, height: CGFloat(cgImage.width) / s) : CGSize(width: CGFloat(cgImage.width) / s, height: CGFloat(cgImage.height) / s)
        name = ""
        image = NSImage(cgImage: cgImage, size: size)
    }
    var accessibilityLabel: String? = nil
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/image/orientation
    public enum Orientation: UInt8, CaseIterable, Hashable, Sendable {
        case up, upMirrored, down, downMirrored, left, leftMirrored, right, rightMirrored
        var swapsAxes: Bool { self == .left || self == .leftMirrored || self == .right || self == .rightMirrored }
    }
    public func resizable(capInsets: EdgeInsets = EdgeInsets(), resizingMode: ResizingMode = .stretch) -> Image { var i = self; i.resizable = true; return i }
    public func renderingMode(_ mode: TemplateRenderingMode?) -> Image { self }
    public func interpolation(_ interpolation: Interpolation) -> Image { self }
    public enum TemplateRenderingMode: Hashable, Sendable { case template, original }
    public enum Interpolation: Hashable, Sendable { case none, low, medium, high }
    public static func == (a: Image, b: Image) -> Bool { a.name == b.name && a.image === b.image && a.resizable == b.resizable }
    public static func != (a: Image, b: Image) -> Bool { !(a == b) }
    public func _makePrimitive(node: _ViewNode) -> _Primitive { _ImagePrimitive(image: self) }
}

@MainActor
final class _ImagePrimitive: _ControlPrimitive<NSImageView> {
    var image: Image
    init(image: Image) {
        self.image = image
        let v = NSImageView(frame: .zero)
        v.image = image.image
        super.init(control: v)
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _ImagePrimitive else { return }
        image = o.image
        control.image = image.image
    }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        let natural = image.image?.size ?? CGSize(width: 16, height: 16)
        guard image.resizable else { return natural }
        return CGSize(width: proposal.width.map { $0.isFinite ? $0 : natural.width } ?? natural.width, height: proposal.height.map { $0.isFinite ? $0 : natural.height } ?? natural.height)
    }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/aspectratio(_:contentmode:)
    public func aspectRatio(_ ratio: CGFloat? = nil, contentMode: ContentMode) -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/scaledtofit()
    public func scaledToFit() -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/scaledtofill()
    public func scaledToFill() -> some View { self }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/contentmode
public enum ContentMode: Hashable, CaseIterable, Sendable { case fit, fill }

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/label
public struct Label<Title: View, Icon: View>: View {
    let title: Title
    let icon: Icon
    @Environment(\._labelStyle) private var style
    public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) { self.title = title(); self.icon = icon() }
    public var body: some View {
        AnyView(style.makeBody(configuration: LabelStyleConfiguration(title: AnyView(title), icon: AnyView(icon))))
    }
}

extension Label where Title == Text, Icon == Image {
    public init(_ titleKey: LocalizedStringKey, systemImage: String) { self.init(title: { Text(titleKey) }, icon: { Image(systemName: systemImage) }) }
    public init(_ titleKey: LocalizedStringKey, image: String) { self.init(title: { Text(titleKey) }, icon: { Image(image) }) }
    public init<S: StringProtocol>(_ title: S, systemImage: String) { self.init(title: { Text(title) }, icon: { Image(systemName: systemImage) }) }
    public init<S: StringProtocol>(_ title: S, image: String) { self.init(title: { Text(title) }, icon: { Image(image) }) }
}

// MARK: ScrollView and List

@MainActor
final class _ScrollPrimitive: _Primitive {
    let scroll = NSScrollView(frame: .zero)
    let document = _ContainerView(frame: .zero)
    var axes: Axis.Set
    var showsIndicators: Bool
    init(axes: Axis.Set, showsIndicators: Bool, content: _AnyViewBox) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        super.init()
        children = [content]
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = axes.contains(.vertical) && showsIndicators
        scroll.hasHorizontalScroller = axes.contains(.horizontal) && showsIndicators
    }
    override var nsView: NSView? { scroll }
    override func update(from other: _Primitive) {
        super.update(from: other)
        if let o = other as? _ScrollPrimitive { axes = o.axes; showsIndicators = o.showsIndicators }
    }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        let content = node.children.first?.sizeThatFits(ProposedViewSize(width: axes.contains(.horizontal) ? nil : proposal.width, height: axes.contains(.vertical) ? nil : proposal.height)) ?? .zero
        return CGSize(width: axes.contains(.horizontal) ? (proposal.width.map { $0.isFinite ? $0 : content.width } ?? content.width) : content.width,
                      height: axes.contains(.vertical) ? (proposal.height.map { $0.isFinite ? $0 : content.height } ?? content.height) : content.height)
    }
    override func place(node: _ViewNode, in rect: CGRect) {
        let inner = scroll.contentSize == .zero ? rect.size : scroll.contentSize
        let proposal = ProposedViewSize(width: axes.contains(.horizontal) ? nil : inner.width, height: axes.contains(.vertical) ? nil : inner.height)
        guard let content = node.children.first else { return }
        let s = content.sizeThatFits(proposal)
        let size = CGSize(width: max(s.width, axes.contains(.horizontal) ? 0 : inner.width), height: max(s.height, axes.contains(.vertical) ? 0 : inner.height))
        // Children are laid out relative to the document view, whose frame is at the scroll origin.
        content.place(in: CGRect(origin: rect.origin, size: size))
        document.frame = NSRect(origin: .zero, size: size)
    }
    /// Content backing views belong in the document, not in the scroll view itself.
    override var childContainer: NSView? { document }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/scrollview
public struct ScrollView<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public var axes: Axis.Set
    public var showsIndicators: Bool
    let content: Content
    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.axes = axes; self.showsIndicators = showsIndicators; self.content = content()
    }
    public func _makePrimitive(node: _ViewNode) -> _Primitive { _ScrollPrimitive(axes: axes, showsIndicators: showsIndicators, content: _ViewBox(content)) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/section
public struct Section<Parent: View, Content: View, Footer: View>: View {
    let header: Parent
    let content: Content
    let footer: Footer
    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent, @ViewBuilder footer: () -> Footer) {
        self.header = header(); self.content = content(); self.footer = footer()
    }
    public var body: some View { Group { header; content; footer } }
}
extension Section where Parent == Text, Footer == EmptyView {
    public init(_ title: String, @ViewBuilder content: () -> Content) { self.init(content: content, header: { Text(title).font(.headline) }, footer: { EmptyView() }) }
}
extension Section where Parent == EmptyView, Footer == EmptyView {
    public init(@ViewBuilder content: () -> Content) { self.init(content: content, header: { EmptyView() }, footer: { EmptyView() }) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/form
public struct Form<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View { VStack(alignment: .leading, spacing: 10) { content }.padding() }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/progressview
public struct ProgressView<Label: View, CurrentValueLabel: View>: View {
    let value: Double?
    let total: Double
    let label: Label?
    public init() where Label == EmptyView, CurrentValueLabel == EmptyView { value = nil; total = 1; label = nil }
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1) where Label == EmptyView, CurrentValueLabel == EmptyView {
        self.value = value.map { Double($0) }; self.total = Double(total); label = nil
    }
    public init(_ title: String) where Label == Text, CurrentValueLabel == EmptyView { value = nil; total = 1; label = Text(title) }
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label { label }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.3)).frame(height: 6)
                RoundedRectangle(cornerRadius: 3).fill(Color.accentColor).frame(width: max(0, 160 * CGFloat((value ?? 0) / max(total, 0.0001))), height: 6)
            }.frame(width: 160)
        }
    }
}
