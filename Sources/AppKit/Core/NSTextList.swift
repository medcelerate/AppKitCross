// NSTextList (hand-written; seeded from the generated stub, see tools/apigen)
//
// A list a paragraph belongs to (`NSParagraphStyle.textLists`, outermost first). As in
// AppKit's TextKit 1 text system the markers are ordinary text at the start of each item,
// "\t<marker>\t", positioned by the paragraph's tab stops and hanging indent; NSTextView
// inserts and renumbers them (ADR-0030). `marker(forItemNumber:)` expands the format's
// `{token}` and keeps any literal text around it ("{decimal}." gives "3.").

import Foundation
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlist
open class NSTextList: NSObject, NSSecureCoding, NSCoding, NSCopying {
    private let _markerFormat: NSTextList.MarkerFormat
    private let _options: NSTextList.Options
    private var _startingItemNumber: Int

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlist/init(coder:)
    public required init?(coder: NSCoder) {
        _markerFormat = NSTextList.MarkerFormat(rawValue: (coder.decodeObject(forKey: "NSMarker") as? String) ?? "{disc}")
        _options = NSTextList.Options(rawValue: UInt(max(0, coder.decodeInteger(forKey: "NSOptions"))))
        _startingItemNumber = coder.containsValue(forKey: "NSStartingItemNumber") ? coder.decodeInteger(forKey: "NSStartingItemNumber") : 1
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlist/init(markerformat:options:)
    public convenience init(markerFormat: NSTextList.MarkerFormat, options: Int) {
        self.init(markerFormat: markerFormat, options: NSTextList.Options(rawValue: UInt(max(0, options))), startingItemNumber: 1)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlist/init(markerformat:options:startingitemnumber:)
    @available(macOS 13.0, *)
    public init(markerFormat: NSTextList.MarkerFormat, options: NSTextList.Options = [], startingItemNumber: Int) {
        _markerFormat = markerFormat
        _options = options
        _startingItemNumber = startingItemNumber
        super.init()
    }
    /// Markers are part of the text in TextKit 1.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlist/includestextlistmarkers
    @available(macOS 26.0, *)
    class public var includesTextListMarkers: Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlist/isordered
    @available(macOS 13.0, *)
    open var isOrdered: Bool {
        guard let token = NSTextList._token(in: _markerFormat.rawValue)?.name else { return false }
        return NSTextList._orderedTokens.contains(token)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlist/listoptions
    open var listOptions: NSTextList.Options { _options }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlist/marker(foritemnumber:)
    open func marker(forItemNumber itemNumber: Int) -> String {
        let format = _markerFormat.rawValue
        guard let t = NSTextList._token(in: format) else { return format }
        let value = NSTextList._expand(t.name, itemNumber) ?? "{\(t.name)}"
        return String(format[format.startIndex..<t.range.lowerBound]) + value + String(format[t.range.upperBound...])
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlist/markerformat
    open var markerFormat: NSTextList.MarkerFormat { _markerFormat }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlist/startingitemnumber
    open var startingItemNumber: Int {
        get { _startingItemNumber }
        set { _startingItemNumber = newValue }
    }
    // Requirement of NSSecureCoding
    class public var supportsSecureCoding: Bool { true }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) {
        coder.encode(_markerFormat.rawValue, forKey: "NSMarker")
        coder.encode(Int(_options.rawValue), forKey: "NSOptions")
        coder.encode(_startingItemNumber, forKey: "NSStartingItemNumber")
    }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any {
        NSTextList(markerFormat: _markerFormat, options: _options, startingItemNumber: _startingItemNumber)
    }
    // MARK: Marker formats

    private static let _orderedTokens: Set<String> = ["decimal", "lower-alpha", "upper-alpha", "lower-latin", "upper-latin",
                                                      "lower-roman", "upper-roman", "octal", "lower-hexadecimal", "upper-hexadecimal"]

    private static func _token(in format: String) -> (name: String, range: Range<String.Index>)? {
        guard let open = format.firstIndex(of: "{"), let close = format[open...].firstIndex(of: "}") else { return nil }
        let name = String(format[format.index(after: open)..<close])
        return (name, open..<format.index(after: close))
    }

    private static func _expand(_ token: String, _ n: Int) -> String? {
        switch token {
        case "disc": return "\u{2022}"
        case "circle": return "\u{25E6}"
        case "square": return "\u{25AA}"
        case "box": return "\u{25AB}"
        case "check": return "\u{2713}"
        case "diamond": return "\u{25C6}"
        case "hyphen": return "\u{2043}"
        case "decimal": return String(n)
        case "octal": return String(n, radix: 8)
        case "lower-hexadecimal": return String(n, radix: 16)
        case "upper-hexadecimal": return String(n, radix: 16).uppercased()
        case "lower-alpha", "lower-latin": return _alpha(n)
        case "upper-alpha", "upper-latin": return _alpha(n).uppercased()
        case "lower-roman": return _roman(n).lowercased()
        case "upper-roman": return _roman(n)
        default: return nil
        }
    }

    /// 1 → a, 26 → z, 27 → aa (spreadsheet style, as AppKit numbers alphabetic lists).
    private static func _alpha(_ n: Int) -> String {
        guard n > 0 else { return String(n) }
        var n = n, out = ""
        while n > 0 {
            n -= 1
            out = String(UnicodeScalar(UInt8(97 + n % 26))) + out
            n /= 26
        }
        return out
    }

    private static func _roman(_ n: Int) -> String {
        guard n > 0, n < 4000 else { return String(n) }
        let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var n = n, out = ""
        for (v, s) in table { while n >= v { out += s; n -= v } }
        return out
    }
}
